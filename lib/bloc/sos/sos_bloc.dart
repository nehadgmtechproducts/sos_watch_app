import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/alarm_service.dart';
import '../../services/api_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/contacts_store.dart';
import '../../services/emergency_call_service.dart';
import '../../services/emergency_sms_service.dart';
import '../../services/profile_store.dart';
import '../../services/push_service.dart';

/// Outcome of attempting the FCM "ring" push to contacts' devices.
enum RingOutcome {
  /// No network was available, so the ring push wasn't even attempted —
  /// SMS and calls (which don't need internet) still go out.
  offline,

  /// We had a network but the request to the backend failed.
  requestFailed,

  /// The backend processed the request; see [RingResult]'s counts for what it
  /// actually found and reached.
  delivered,
}

class RingResult {
  final RingOutcome outcome;

  /// Contact devices the backend found eligible to ring.
  final int targeted;

  /// Of those, how many FCM accepted.
  final int delivered;

  /// Of those, how many FCM rejected.
  final int failed;

  const RingResult(
    this.outcome, {
    this.targeted = 0,
    this.delivered = 0,
    this.failed = 0,
  });
}

// ─────────────────────────── Events ───────────────────────────
sealed class SosEvent extends Equatable {
  const SosEvent();
  @override
  List<Object?> get props => [];
}

/// Ring the user's other devices (via the backend + FCM) and alert contacts.
class SosFired extends SosEvent {
  const SosFired();
}

/// Check whether we may override Do-Not-Disturb.
class SosDndChecked extends SosEvent {
  const SosDndChecked();
}

/// Open the system screen to grant DND-override access.
class SosDndRequested extends SosEvent {
  const SosDndRequested();
}

// ─────────────────────────── State ───────────────────────────
class SosState extends Equatable {
  final bool sending;
  final bool dndGranted;

  /// One-shot user feedback. [feedbackId] increments each time so the UI's
  /// BlocListener fires even if the text repeats.
  final String? feedback;
  final int feedbackId;

  const SosState({
    this.sending = false,
    this.dndGranted = true,
    this.feedback,
    this.feedbackId = 0,
  });

  SosState copyWith({
    bool? sending,
    bool? dndGranted,
    String? feedback,
    int? feedbackId,
  }) =>
      SosState(
        sending: sending ?? this.sending,
        dndGranted: dndGranted ?? this.dndGranted,
        feedback: feedback ?? this.feedback,
        feedbackId: feedbackId ?? this.feedbackId,
      );

  @override
  List<Object?> get props => [sending, dndGranted, feedback, feedbackId];
}

// ─────────────────────────── Bloc ───────────────────────────
class SosBloc extends Bloc<SosEvent, SosState> {
  final ApiService _api;
  final ContactsStore _contacts;
  final EmergencyCallService _calls;
  final EmergencySmsService _sms;
  final ConnectivityService _connectivity;

  SosBloc({
    required ApiService api,
    required ContactsStore contacts,
    required EmergencyCallService calls,
    required EmergencySmsService sms,
    ConnectivityService? connectivity,
  })  : _api = api,
        _contacts = contacts,
        _calls = calls,
        _sms = sms,
        _connectivity = connectivity ?? ConnectivityService.instance,
        super(const SosState()) {
    on<SosFired>(_onFired);
    on<SosDndChecked>(_onDndChecked);
    on<SosDndRequested>((_, __) => AlarmService.requestDndAccess());
  }

  Future<void> _onFired(SosFired e, Emitter<SosState> emit) async {
    if (state.sending) return;
    emit(state.copyWith(sending: true));
    final contacts = await _contacts.all();
    // The alarm push needs the backend + FCM, so only attempt it when a
    // network is actually up. SMS and calls are telephony-based and go out
    // either way, so they never wait on this check.
    final online = await _connectivity.hasNetwork();
    final ringResult = online ? await _ringDevices() : const RingResult(RingOutcome.offline);
    // Text each contact our current location, then start the call sequence.
    final smsResult = await _sms.sendLocationToContacts(contacts);
    final callResult = await _calls.startContactCallSequence(contacts);
    emit(state.copyWith(
      sending: false,
      feedback: _feedback(ringResult, smsResult, callResult),
      feedbackId: state.feedbackId + 1,
    ));
  }

  /// Ask the backend to ring the user's other devices over FCM. Passing our own
  /// FCM token lets the server skip this phone.
  Future<RingResult> _ringDevices() async {
    try {
      final profile = await ProfileStore.instance.load();
      final fcmToken = await PushService.instance.getToken();
      // Only a fingerprint: the full token is long and not needed to tell
      // whether the server is excluding the right device.
      final tokenTail = fcmToken == null
          ? '(none — this phone cannot be excluded!)'
          : '…${fcmToken.substring(fcmToken.length - 12)}';
      debugPrint('$ringLogTag sending ring request, ourToken=$tokenTail');

      final response = await _api.request('POST', '/devices/ring', body: {
        'fromName': profile.name.isNotEmpty ? profile.name : 'A contact',
        if (fcmToken != null) 'fcmToken': fcmToken,
      });
      debugPrint('$ringLogTag server response: targeted='
          '${response['targeted']} delivered=${response['delivered']} '
          'failed=${response['failed']}');
      return RingResult(
        RingOutcome.delivered,
        targeted: response['targeted'] as int? ?? 0,
        delivered: response['delivered'] as int? ?? 0,
        failed: response['failed'] as int? ?? 0,
      );
    } on ApiException catch (e) {
      debugPrint('$ringLogTag ring request FAILED: ${e.message}');
      return const RingResult(RingOutcome.requestFailed);
    }
  }

  Future<void> _onDndChecked(SosDndChecked e, Emitter<SosState> emit) async {
    emit(state.copyWith(dndGranted: await AlarmService.isDndAccessGranted()));
  }

  String _feedback(
    RingResult ring,
    EmergencySmsOutcome smsResult,
    EmergencyCallOutcome callResult,
  ) {
    final broadcastText = switch (ring.outcome) {
      RingOutcome.offline => 'No internet — skipped the alarm alert.',
      RingOutcome.requestFailed => 'Could not reach the server to alert your contacts.',
      // Nobody eligible: no contact has the app registered under the number
      // saved for them. Nothing was even attempted.
      RingOutcome.delivered when ring.targeted == 0 =>
        'No contacts have the app — no alarm sent.',
      // Devices were found, but every push was rejected — a delivery problem,
      // not a missing contact. Kept distinct so it isn't misread as the above.
      RingOutcome.delivered when ring.delivered == 0 =>
        'Alarm failed to reach ${ring.targeted} device(s).',
      RingOutcome.delivered when ring.failed > 0 =>
        'Alarm reached ${ring.delivered} of ${ring.targeted} devices.',
      RingOutcome.delivered when ring.delivered == 1 =>
        'Ringing 1 contact\'s device.',
      RingOutcome.delivered => 'Ringing ${ring.delivered} contacts\' devices.',
    };
    final smsText = switch (smsResult.result) {
      EmergencySmsResult.sent when smsResult.sent < smsResult.total =>
        'Location SMS sent to ${smsResult.sent} of ${smsResult.total} contacts.',
      EmergencySmsResult.sent =>
        'Location SMS sent to ${smsResult.total} contact(s).',
      EmergencySmsResult.noPhoneNumbers => 'No contact phone numbers saved.',
      EmergencySmsResult.permissionDenied => 'SMS permission was denied.',
      EmergencySmsResult.unsupportedPlatform => 'This device cannot send SMS.',
      EmergencySmsResult.cancelled => 'SMS was not sent — message cancelled.',
      EmergencySmsResult.noTelephony =>
        'This device has no SIM, so it cannot send SMS.',
      EmergencySmsResult.failed => 'Could not send the location SMS.',
    };
    final callText = switch (callResult.result) {
      EmergencyCallStartResult.started =>
        'Calling ${callResult.contactCount} contact(s), one after another.',
      EmergencyCallStartResult.alreadyRunning =>
        'Emergency calling is already running.',
      EmergencyCallStartResult.noPhoneNumbers =>
        'No contact phone numbers saved.',
      EmergencyCallStartResult.permissionDenied =>
        'Phone-call permission was denied.',
      EmergencyCallStartResult.unsupportedPlatform =>
        'Automatic emergency calling is Android-only.',
    };
    return '$broadcastText $smsText $callText';
  }
}
