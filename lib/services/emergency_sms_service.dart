import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'contacts_store.dart';
import '../utils/phone.dart';

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

  Future<EmergencySmsOutcome> sendLocationToContacts(
    List<DemoContact> contacts, {
    String prefix = 'Emergency! I need help.',
  }) async {
    // De-duplicate by subscriber, so a contact saved twice in different
    // formats isn't texted twice — but send the number exactly as saved,
    // which SmsManager parses correctly.
    final byRecipient = <String, String>{};
    for (final c in contacts) {
      final number = c.phone.trim();
      if (number.isEmpty) continue;
      byRecipient.putIfAbsent(phoneDedupeKey(number), () => number);
    }
    final numbers = byRecipient.values.toList(growable: false);
    if (numbers.isEmpty) {
      return const EmergencySmsOutcome(EmergencySmsResult.noPhoneNumbers);
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      return const EmergencySmsOutcome(
          EmergencySmsResult.unsupportedPlatform, total: 0);
    }

    // iOS has no runtime "send SMS" permission — the compose sheet itself is
    // the user's consent, so only Android needs the SEND_SMS permission check.
    if (Platform.isAndroid) {
      final smsPermission = await Permission.sms.request();
      if (!smsPermission.isGranted) {
        return EmergencySmsOutcome(EmergencySmsResult.permissionDenied,
            total: numbers.length);
      }
    }

    final message = '$prefix ${await _currentLocationText()}';

    try {
      final response = await _native.invokeMethod<dynamic>('sendSms', {
        'numbers': numbers,
        'message': message,
      });
      // Android reports per-recipient counts so a partial delivery is visible
      // instead of being reported as a clean success.
      final sent = response is Map
          ? (response['sent'] as int? ?? numbers.length)
          : numbers.length;
      return EmergencySmsOutcome(
        EmergencySmsResult.sent,
        sent: sent,
        total: numbers.length,
      );
    } on PlatformException catch (e) {
      final result = switch (e.code) {
        'sms_permission_denied' => EmergencySmsResult.permissionDenied,
        'sms_cancelled' => EmergencySmsResult.cancelled,
        'sms_unsupported' => EmergencySmsResult.unsupportedPlatform,
        'sms_no_telephony' => EmergencySmsResult.noTelephony,
        _ => EmergencySmsResult.failed,
      };
      return EmergencySmsOutcome(result, total: numbers.length);
    } catch (_) {
      return EmergencySmsOutcome(EmergencySmsResult.failed,
          total: numbers.length);
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

/// Outcome of the SMS fan-out, including how many contacts actually got it.
class EmergencySmsOutcome {
  final EmergencySmsResult result;
  final int sent;
  final int total;
  const EmergencySmsOutcome(this.result, {this.sent = 0, this.total = 0});
}

enum EmergencySmsResult {
  sent,
  noPhoneNumbers,
  permissionDenied,
  unsupportedPlatform,
  /// iOS only: the user dismissed the Messages compose sheet without sending.
  cancelled,

  /// The device has no cellular radio — a tethered Wear OS watch or an
  /// emulator. Nothing can be sent from here, regardless of permissions.
  noTelephony,
  failed,
}
