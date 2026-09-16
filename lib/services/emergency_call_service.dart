import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
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

  /// Grep-able prefix so the call sequence can be followed in logcat:
  /// `adb logcat | grep SOS-CALL`
  static const String _logTag = '[SOS-CALL]';

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
    debugPrint('$_logTag sequence started — ${contacts.length} contact(s) to call');
    try {
      for (var i = 0; i < contacts.length; i++) {
        final contact = contacts[i];
        final position = '${i + 1}/${contacts.length}';
        try {
          debugPrint('$_logTag [$position] dialling ${contact.name} '
              '<${contact.phone}>');
          await _placeCall(contact.phone);
          debugPrint('$_logTag [$position] dialer launched for ${contact.phone}');
          final ended = await _awaitCallEnd();
          debugPrint('$_logTag [$position] ${ended ? 'call ended' : 'no call-end '
              'signal — moving on after timeout'} for ${contact.phone}');
        } catch (error) {
          // One bad number, a denied/declined call, or a platform error must
          // not stop the rest of the contact list from being tried.
          debugPrint('$_logTag [$position] FAILED for ${contact.phone}: $error '
              '— continuing to the next contact');
        }
        await Future<void>.delayed(gapBetweenCalls);
      }
      debugPrint('$_logTag sequence finished — all ${contacts.length} '
          'contact(s) attempted');
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
  /// Returns true when the call was observed to end, false when we gave up
  /// waiting and advanced on the timeout instead.
  Future<bool> _awaitCallEnd() async {
    if (Platform.isAndroid) {
      try {
        final ended = await _native.invokeMethod<bool>(
          'awaitCallEnd',
          {'timeoutMs': callTimeout.inMilliseconds},
        );
        // The native side already blocked for up to `callTimeout`, whether the
        // call ended cleanly or timed out; no further delay needed.
        if (ended != null) return ended;
      } catch (error) {
        debugPrint('$_logTag call-state watch unavailable ($error) — '
            'falling back to a fixed ${callTimeout.inSeconds}s wait');
      }
    }
    await Future<void>.delayed(callTimeout);
    return false;
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
