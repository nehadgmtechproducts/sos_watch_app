import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'alarm_service.dart';
import 'contacts_store.dart';
import 'notification_service.dart';

/// Calls every emergency contact, one at a time with [callWindow] between
/// calls, then plays the local SOS alarm.
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
  static const Duration callWindow = Duration(minutes: 2);

  bool _running = false;

  bool get isRunning => _running;

  Future<EmergencyCallStartResult> startContactCallAlarmSequence(
    List<DemoContact> contacts, {
    String alarmFromName = 'Emergency call timer',
  }) async {
    if (_running) {
      return EmergencyCallStartResult.alreadyRunning;
    }

    final callableContacts = contacts
        .where((contact) => contact.phone.trim().isNotEmpty)
        .toList(growable: false);
    if (callableContacts.isEmpty) {
      return EmergencyCallStartResult.noPhoneNumbers;
    }

    if (Platform.isAndroid) {
      final permission = await Permission.phone.request();
      if (!permission.isGranted) {
        return EmergencyCallStartResult.permissionDenied;
      }
    } else if (!Platform.isIOS) {
      return EmergencyCallStartResult.unsupportedPlatform;
    }

    _running = true;
    unawaited(_runSequence(callableContacts, alarmFromName));
    return EmergencyCallStartResult.started;
  }

  Future<void> _runSequence(
    List<DemoContact> contacts,
    String alarmFromName,
  ) async {
    try {
      for (final contact in contacts) {
        try {
          await _placeCall(contact.phone);
        } catch (_) {
          // One bad number, a denied/declined call, or a platform error must
          // not stop the rest of the contact list from being tried.
        }
        await Future<void>.delayed(callWindow);
      }
      await NotificationService.instance
          .showSosFullScreen({'fromName': alarmFromName});
      await AlarmService.instance.start({'fromName': alarmFromName});
    } finally {
      _running = false;
    }
  }

  Future<void> _placeCall(String phoneNumber) async {
    await _native.invokeMethod<void>('placeCall', {
      'phoneNumber': phoneNumber,
    });
  }
}

enum EmergencyCallStartResult {
  started,
  alreadyRunning,
  noPhoneNumbers,
  permissionDenied,
  unsupportedPlatform,
}
