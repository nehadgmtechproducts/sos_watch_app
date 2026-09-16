import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'contacts_store.dart';
import '../utils/phone.dart';

/// Calls every emergency contact, one at a time with [callWindow] between
/// calls.
///
/// This deliberately never raises an alarm on the *sender's* device: the SOS
/// alarm belongs only on the recipients' phones, and gets there via the
/// backend's FCM "ring" push (see PushService/AlarmBloc).
///
/// Android: dials directly via `ACTION_CALL` — no confirmation UI, once
/// CALL_PHONE permission is granted.
///
/// iOS: there is no API to place a call without the user's confirmation —
/// Apple requires every `tel://` launch to show the system "Call?" alert,
/// which the user must tap through. This is an OS-level restriction, not a
/// bug; there is no way to make outgoing iOS calls fully silent.
class EmergencyCallService {
  EmergencyCallService._();
  static final EmergencyCallService instance = EmergencyCallService._();

  static const MethodChannel _native = MethodChannel('sos_emergency/phone');

  /// Longest we'll stay on one contact before moving to the next. Only applies
  /// when the call never connects or is never hung up — a call that ends
  /// normally advances the sequence immediately.
  static const Duration callTimeout = Duration(seconds: 45);

  /// Breathing room after a call ends, so the dialer has settled before the
  /// next `ACTION_CALL` fires.
  static const Duration gapBetweenCalls = Duration(seconds: 3);

  bool _running = false;

  bool get isRunning => _running;

  Future<EmergencyCallOutcome> startContactCallSequence(
    List<DemoContact> contacts,
  ) async {
    if (_running) {
      return const EmergencyCallOutcome(EmergencyCallStartResult.alreadyRunning);
    }

    // One call per person, even if the same number was saved twice.
    final seen = <String>{};
    final callableContacts = contacts
        .where((contact) => contact.phone.trim().isNotEmpty)
        .where((contact) => seen.add(phoneDedupeKey(contact.phone)))
        .toList(growable: false);
    if (callableContacts.isEmpty) {
      return const EmergencyCallOutcome(
          EmergencyCallStartResult.noPhoneNumbers);
    }

    if (Platform.isAndroid) {
      final permission = await Permission.phone.request();
      if (!permission.isGranted) {
        return const EmergencyCallOutcome(
            EmergencyCallStartResult.permissionDenied);
      }
    } else if (!Platform.isIOS) {
      return const EmergencyCallOutcome(
          EmergencyCallStartResult.unsupportedPlatform);
    }

    _running = true;
    unawaited(_runSequence(callableContacts));
    return EmergencyCallOutcome(
      EmergencyCallStartResult.started,
      contactCount: callableContacts.length,
    );
  }

  /// Dials every contact in turn. Each call is followed by a wait for the line
  /// to clear, so contact 2 isn't dialled on top of contact 1's still-active
  /// call — which is why only the first contact used to be reached.
  Future<void> _runSequence(List<DemoContact> contacts) async {
    try {
      for (final contact in contacts) {
        try {
          await _placeCall(contact.phone);
          await _awaitCallEnd();
        } catch (_) {
          // One bad number, a denied/declined call, or a platform error must
          // not stop the rest of the contact list from being tried.
        }
        await Future<void>.delayed(gapBetweenCalls);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _placeCall(String phoneNumber) async {
    await _native.invokeMethod<void>('placeCall', {
      // Dialled as saved: Android parses formatted numbers, and rewriting them
      // here risks corrupting valid non-mobile entries.
      'phoneNumber': phoneNumber.trim(),
    });
  }

  /// Waits for the active call to finish. Falls back to a plain timer when the
  /// platform can't report call state (iOS, or READ_PHONE_STATE not granted).
  Future<void> _awaitCallEnd() async {
    if (Platform.isAndroid) {
      try {
        final ended = await _native.invokeMethod<bool>(
          'awaitCallEnd',
          {'timeoutMs': callTimeout.inMilliseconds},
        );
        // The native side already blocked for up to `callTimeout`, whether the
        // call ended cleanly or timed out; no further delay needed.
        if (ended != null) return;
      } catch (_) {
        // Fall through to the timer below.
      }
    }
    await Future<void>.delayed(callTimeout);
  }
}

/// Result of kicking off the call sequence, plus how many contacts it covers.
class EmergencyCallOutcome {
  final EmergencyCallStartResult result;
  final int contactCount;
  const EmergencyCallOutcome(this.result, {this.contactCount = 0});
}

enum EmergencyCallStartResult {
  started,
  alreadyRunning,
  noPhoneNumbers,
  permissionDenied,
  unsupportedPlatform,
}
