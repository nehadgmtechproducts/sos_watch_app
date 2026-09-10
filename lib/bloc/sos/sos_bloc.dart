import 'package:equatable/equatable.dart';
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

  /// The backend accepted the push; [RingResult.count] devices were targeted.
  delivered,
}

class RingResult {
  final RingOutcome outcome;
  final int count;
  const RingResult(this.outcome, [this.count = 0]);
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
    final callResult = await _calls.startContactCallAlarmSequence(contacts);
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
      final response = await _api.request('POST', '/devices/ring', body: {
        'fromName': profile.name.isNotEmpty ? profile.name : 'A contact',
        if (fcmToken != null) 'fcmToken': fcmToken,
      });
      return RingResult(RingOutcome.delivered, response['delivered'] as int? ?? 0);
    } on ApiException {
      return const RingResult(RingOutcome.requestFailed);
    }
  }

  Future<void> _onDndChecked(SosDndChecked e, Emitter<SosState> emit) async {
    emit(state.copyWith(dndGranted: await AlarmService.isDndAccessGranted()));
  }

  String _feedback(
    RingResult ring,
    EmergencySmsResult smsResult,
    EmergencyCallStartResult callResult,
  ) {
    final broadcastText = switch (ring.outcome) {
      RingOutcome.offline => 'No internet — skipped the alarm alert.',
      RingOutcome.requestFailed => 'Could not reach the server to alert your contacts.',
      RingOutcome.delivered when ring.count == 0 => 'No app-using contacts to alert.',
      RingOutcome.delivered when ring.count == 1 => 'Ringing 1 contact\'s device.',
      RingOutcome.delivered => 'Ringing ${ring.count} contacts\' devices.',
    };
    final smsText = switch (smsResult) {
      EmergencySmsResult.sent => 'Location SMS sent to contacts.',
      EmergencySmsResult.noPhoneNumbers => 'No contact phone numbers saved.',
      EmergencySmsResult.permissionDenied => 'SMS permission was denied.',
      EmergencySmsResult.unsupportedPlatform => 'This device cannot send SMS.',
      EmergencySmsResult.cancelled => 'SMS was not sent — message cancelled.',
      EmergencySmsResult.failed => 'Could not send the location SMS.',
    };
    final callText = switch (callResult) {
      EmergencyCallStartResult.started =>
        'Calling emergency contacts one by one; alarm rings after the call timer.',
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
