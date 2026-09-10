import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'contacts_store.dart';

/// Sends an emergency SMS — including the device's current location as a Google
/// Maps link — to every contact that has a phone number.
///
/// Android: uses the native `SmsManager` (via the `sos_emergency/sms`
/// MethodChannel) to send a separate, silent SMS to each contact — no user
/// interaction needed once SEND_SMS permission is granted.
///
/// iOS: Apple provides no API to send SMS without user confirmation — there is
/// no silent-send path, by design. The native side presents the system
/// Messages compose sheet pre-filled with every contact and the message, so
/// the user only has to tap Send once. That also means, unlike Android, all
/// recipients land in one group conversation and can see each other's number.
class EmergencySmsService {
  EmergencySmsService._();
  static final EmergencySmsService instance = EmergencySmsService._();

  static const MethodChannel _native = MethodChannel('sos_emergency/sms');

  Future<EmergencySmsResult> sendLocationToContacts(
    List<DemoContact> contacts, {
    String prefix = 'Emergency! I need help.',
  }) async {
    final numbers = contacts
        .map((c) => c.phone.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (numbers.isEmpty) return EmergencySmsResult.noPhoneNumbers;

    if (!Platform.isAndroid && !Platform.isIOS) {
      return EmergencySmsResult.unsupportedPlatform;
    }

    // iOS has no runtime "send SMS" permission — the compose sheet itself is
    // the user's consent, so only Android needs the SEND_SMS permission check.
    if (Platform.isAndroid) {
      final smsPermission = await Permission.sms.request();
      if (!smsPermission.isGranted) {
        return EmergencySmsResult.permissionDenied;
      }
    }

    final message = '$prefix ${await _currentLocationText()}';

    try {
      await _native.invokeMethod<void>('sendSms', {
        'numbers': numbers,
        'message': message,
      });
      return EmergencySmsResult.sent;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'sms_permission_denied':
          return EmergencySmsResult.permissionDenied;
        case 'sms_cancelled':
          return EmergencySmsResult.cancelled;
        case 'sms_unsupported':
          return EmergencySmsResult.unsupportedPlatform;
        default:
          return EmergencySmsResult.failed;
      }
    } catch (_) {
      return EmergencySmsResult.failed;
    }
  }

  /// A human-readable location line. Degrades gracefully if location is off or
  /// denied — the SMS still goes out, just without coordinates.
  Future<String> _currentLocationText() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return '(Location services are off.)';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return '(Location permission denied.)';
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final lat = pos.latitude.toStringAsFixed(6);
      final lng = pos.longitude.toStringAsFixed(6);
      return 'My location: https://maps.google.com/?q=$lat,$lng';
    } catch (_) {
      return '(Current location unavailable.)';
    }
  }
}

enum EmergencySmsResult {
  sent,
  noPhoneNumbers,
  permissionDenied,
  unsupportedPlatform,
  /// iOS only: the user dismissed the Messages compose sheet without sending.
  cancelled,
  failed,
}
