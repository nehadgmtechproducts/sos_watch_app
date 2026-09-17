import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_service.dart';

/// Same id NotificationService uses, so the in-app alarm replaces this
/// notification and its Stop button cancels it.
const _sosNotificationId = 42;

/// Prefs key: a ring recorded by the background isolate, awaiting UI delivery.
/// Stores JSON ({from, at}) — the v1 key held a bare name with no timestamp.
const _pendingRingKey = 'pending_ring_v2';
const _legacyPendingRingKey = 'pending_ring_from';

/// How recent a stored ring must be to still be worth raising.
///
/// Without this, a ring recorded while the app was killed sat in prefs forever
/// and fired at the next resume, whenever that happened to be. That misfires
/// worst on the *sender's* own phone: pressing SOS launches the dialer, which
/// backgrounds the app, so coming back from the call replays whatever old ring
/// was still sitting there — looking exactly like "my own phone alarmed".
///
/// Long enough to cover a receiver who reacts to the ringing notification a few
/// minutes late — they must still get the alarm screen and its Stop button —
/// while still rejecting leftovers from hours or days ago.
const _pendingRingMaxAge = Duration(minutes: 10);

/// Grep-able prefix for the whole ring path: `adb logcat | grep SOS-RING`.
const ringLogTag = '[SOS-RING]';

/// The siren, as an Android raw resource (android/app/src/main/res/raw).
/// The Flutter asset can't be used here: a notification channel's sound is
/// played by the system, which has no access to Flutter's asset bundle.
const _sirenSound = RawResourceAndroidNotificationSound('siren');

final Int64List sosVibrationPattern =
    Int64List.fromList(<int>[0, 800, 400, 800, 400, 800]);

/// Channel for a ring that arrives while the app is **not** in the foreground.
///
/// The system plays this sound itself, which matters because the background
/// isolate cannot drive AlarmService — that lives in the UI isolate, which is
/// not running. Routing it through [AudioAttributesUsage.alarm] puts it on
/// STREAM_ALARM, so ringer-silent does not mute it, exactly as an alarm clock
/// stays audible.
///
/// A new id on purpose: channel settings are immutable once created, so devices
/// that already have the old silent `sos_alarm_channel` would otherwise keep
/// playing nothing forever.
final loudSosChannel = AndroidNotificationChannel(
  'sos_alarm_loud_v1',
  'SOS Emergency Alarm',
  description: 'Full-screen emergency alerts from your linked contacts.',
  importance: Importance.max,
  playSound: true,
  sound: _sirenSound,
  audioAttributesUsage: AudioAttributesUsage.alarm,
  enableVibration: true,
  vibrationPattern: sosVibrationPattern,
);

const _otpChannel = AndroidNotificationChannel(
  'otp_notifications',
  'Verification codes',
  description: 'One-time verification codes for SOS Emergency.',
  importance: Importance.high,
);

const _otpNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'otp_notifications',
    'Verification codes',
    channelDescription: 'One-time verification codes for SOS Emergency.',
    importance: Importance.high,
    priority: Priority.high,
  ),
);

/// Echoes a received OTP to the log so it can be read during testing without a
/// second handset: `adb logcat | grep SOS-OTP`.
///
/// Guarded by [kDebugMode] on purpose — a one-time passcode is a credential,
/// and it must never be written to the log of a release build.
void logOtp(String source, String? otp) {
  if (!kDebugMode) return;
  debugPrint('[SOS-OTP] ($source) ${otp == null || otp.isEmpty ? '(none in '
      'payload — read it from the notification)' : otp}');
}

Future<void> _showOtpNotification(
  FlutterLocalNotificationsPlugin plugin,
  RemoteMessage message,
) async {
  final notification = message.notification;
  final otp = message.data['otp']?.toString().trim();
  logOtp('push', otp);
  await plugin.show(
    id: 100,
    title: notification?.title ?? 'SOS Emergency verification code',
    body: notification?.body ??
        '${otp == null || otp.isEmpty ? 'Your' : otp} is your verification code.',
    notificationDetails: _otpNotificationDetails,
    payload: 'otp',
  );
}

/// Handles messages that arrive while the app is terminated or backgrounded.
///
/// Runs in its own isolate, so it can't touch the AlarmBloc/AlarmService that
/// live in the UI isolate. Instead it raises the full-screen-intent SOS
/// notification directly; that pops the alarm screen over the lock screen, and
/// when the app comes to the foreground [PushService] replays the ring into the
/// alarm pipeline (see getInitialMessage / onMessageOpenedApp) to start audio.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {/* already initialised in this isolate */}
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  if (message.data['type'] == 'otp') {
    // Logged here as well as in _showOtpNotification: the backend sends OTPs
    // with a notification block, so the early return below means that helper
    // never runs for a backgrounded app.
    logOtp('push/background', message.data['otp']?.toString().trim());
    // FCM already renders notification-payload messages in the background.
    // Data-only OTPs need a local notification so both message formats work
    // without creating duplicate notifications.
    if (message.notification == null) {
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_otpChannel);
      await _showOtpNotification(plugin, message);
    }
    return;
  }

  if (message.data['type'] != 'ring') return;
  final from = (message.data['fromName'] as String?)?.trim();
  final fromName = from == null || from.isEmpty ? 'A contact' : from;
  // Record a pending ring so the foreground UI starts the siren + alarm screen
  // when it next resumes (this background isolate can't touch the AlarmBloc).
  debugPrint('$ringLogTag received ring push (background isolate) from '
      '$fromName');
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingRingKey,
      jsonEncode({
        'from': fromName,
        'at': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  } catch (_) {}
  // This isolate may be the app's first run, so the channel might not exist yet.
  // Creating a channel is idempotent, so this is safe to repeat.
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(loudSosChannel);
  await plugin.show(
    id: _sosNotificationId,
    title: '🚨 EMERGENCY',
    body: '$fromName needs help — tap to open',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        loudSosChannel.id,
        loudSosChannel.name,
        channelDescription: loudSosChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        sound: _sirenSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        vibrationPattern: sosVibrationPattern,
        visibility: NotificationVisibility.public,
        // FLAG_INSISTENT: repeat the sound until the notification is cancelled.
        // A channel sound otherwise plays once, which is not an alarm.
        additionalFlags: Int32List.fromList(<int>[4]),
      ),
    ),
    payload: 'sos',
  );
}

/// Firebase Cloud Messaging: fetches this device's FCM token on launch and
/// keeps it fresh. The token is the "push address" your server stores against
/// the user (the registration call) so it can later push an SOS "ring" command
/// to this specific device.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// Emits the sender's name whenever a "ring" command arrives. AlarmBloc
  /// subscribes to this to start the siren — the same seam the LAN broadcast
  /// used to feed, now driven by Firebase Cloud Messaging.
  final StreamController<String> _ring = StreamController<String>.broadcast();
  Stream<String> get incoming => _ring.stream;

  String? _token;

  // Retained for the app's lifetime to keep the resume listener alive.
  // ignore: unused_field
  AppLifecycleListener? _lifecycle;

  /// The current FCM token, or null if it couldn't be obtained yet.
  String? get token => _token;

  /// Platform label sent to the backend when registering this device.
  String get platform => Platform.isIOS ? 'ios' : 'android';

  /// Called when the FCM token changes, so the app can re-register with the
  /// backend. Set by the auth layer, which owns the API client.
  void Function(String token)? onTokenRefresh;

  /// Returns the current FCM token, fetching it again if app initialization
  /// completed before Firebase generated one.
  Future<String?> getToken() async {
    if (_token != null) return _token;
    try {
      _token = await _messaging.getToken();
      return _token;
    } catch (e) {
      debugPrint('FCM getToken failed: $e');
      return null;
    }
  }

  Future<void> init() async {
    // iOS/Android 13+ notification permission (Android <13 is auto-granted).
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    await _initNotifications();

    // Deliver "ring" commands that arrive while the app is killed/backgrounded.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      _token = await _messaging.getToken();
      _logToken('FCM_TOKEN', _token);
    } catch (e) {
      // On iOS this throws until APNs is configured; safe to ignore for now.
      debugPrint('FCM getToken failed (expected on iOS w/o APNs): $e');
    }

    // Tokens can rotate; keep ours current and re-register with the backend.
    _messaging.onTokenRefresh.listen((newToken) {
      _token = newToken;
      _logToken('FCM_TOKEN_REFRESHED', newToken);
      onTokenRefresh?.call(newToken);
    });

    // Foreground: Android does not auto-display data messages, so we route them.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    // App opened by tapping the SOS notification (was backgrounded): ring now.
    FirebaseMessaging.onMessageOpenedApp.listen(_onRingOpened);
    // App launched cold from the SOS notification: ring once it's ready.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onRingOpened(initial);

    // Deliver a ring recorded by the background handler whenever the app
    // resumes (e.g. brought forward by the full-screen SOS notification).
    _lifecycle = AppLifecycleListener(onResume: deliverPendingRing);
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      settings: const InitializationSettings(android: android),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_otpChannel);
  }

  void _onForegroundMessage(RemoteMessage message) {
    final type = message.data['type'];
    debugPrint('$ringLogTag foreground push received, type=$type');
    switch (type) {
      case 'ring':
        _emitRing(message, 'foreground push');
        break;
      case 'otp':
        _showOtpNotification(_notifications, message);
        break;
    }
  }

  void _onRingOpened(RemoteMessage message) {
    if (message.data['type'] == 'ring') {
      _emitRing(message, 'notification tap');
    }
  }

  void _emitRing(RemoteMessage message, String source) {
    final from = (message.data['fromName'] as String?)?.trim();
    final fromName = from == null || from.isEmpty ? 'A contact' : from;
    debugPrint('$ringLogTag raising alarm — ring from $fromName (via $source)');
    _ring.add(fromName);
  }

  /// Delivers a ring recorded by [firebaseMessagingBackgroundHandler] while the
  /// app was backgrounded/terminated. Call once the UI + AlarmBloc are ready
  /// (app start) and again on resume; safe to call when nothing is pending.
  ///
  /// Anything older than [_pendingRingMaxAge] is discarded rather than raised —
  /// an emergency that arrived long ago is not an emergency happening now.
  Future<void> deliverPendingRing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Values written before rings carried a timestamp can't be aged, and are
      // exactly the stale entries causing spurious alarms — drop them.
      if (prefs.containsKey(_legacyPendingRingKey)) {
        await prefs.remove(_legacyPendingRingKey);
        debugPrint('$ringLogTag discarded a legacy pending ring (no timestamp)');
      }

      final raw = prefs.getString(_pendingRingKey);
      if (raw == null) return;
      await prefs.remove(_pendingRingKey);

      final stored = jsonDecode(raw) as Map<String, dynamic>;
      final from = stored['from'] as String? ?? 'A contact';
      final at = stored['at'] as int? ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - at;

      if (age > _pendingRingMaxAge.inMilliseconds) {
        debugPrint('$ringLogTag discarded stale pending ring from $from '
            '(${(age / 1000).round()}s old)');
        // The background notification rings until cancelled, and no alarm
        // screen (with its Stop button) will open for a discarded ring — so
        // silence it and put the volume back here, or it would ring on with
        // no way to stop it. Skipped if a live alarm is already sounding.
        if (!AlarmService.instance.isRinging) {
          await _notifications.cancel(id: _sosNotificationId);
          await AlarmService.instance.stop();
        }
        return;
      }
      debugPrint('$ringLogTag raising alarm — pending ring from $from '
          '(${(age / 1000).round()}s old)');
      _ring.add(from);
    } catch (e) {
      debugPrint('$ringLogTag could not read pending ring: $e');
    }
  }

  /// Prints the token inside a clear banner so it's easy to find/copy from
  /// `adb logcat`. debugPrint chunks long lines, but the [tag] makes it
  /// greppable, e.g.  `adb logcat | grep FCM_TOKEN`.
  void _logToken(String tag, String? token) {
    debugPrint('========== $tag ==========');
    debugPrint(token ?? '(null)');
    debugPrint('========== END $tag ==========');
  }
}
