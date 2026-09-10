import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs key: a ring recorded by the background isolate, awaiting UI delivery.
const _pendingRingKey = 'pending_ring_from';

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

Future<void> _showOtpNotification(
  FlutterLocalNotificationsPlugin plugin,
  RemoteMessage message,
) async {
  final notification = message.notification;
  final otp = message.data['otp']?.toString().trim();
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
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingRingKey, fromName);
  } catch (_) {}
  // This isolate may be the app's first run, so the channel might not exist yet.
  // Creating a channel is idempotent, so this is safe to repeat.
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        'sos_alarm_channel',
        'SOS Emergency Alarm',
        description: 'Full-screen emergency alerts from your linked contacts.',
        importance: Importance.max,
        playSound: false,
        enableVibration: false,
      ));
  await plugin.show(
    id: 42,
    title: '🚨 EMERGENCY',
    body: '$fromName needs help — tap to open',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'sos_alarm_channel',
        'SOS Emergency Alarm',
        channelDescription: 'Full-screen emergency alerts from your linked contacts.',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: false,
        enableVibration: false,
        visibility: NotificationVisibility.public,
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
    switch (message.data['type']) {
      case 'ring':
        _emitRing(message);
        break;
      case 'otp':
        _showOtpNotification(_notifications, message);
        break;
    }
  }

  void _onRingOpened(RemoteMessage message) {
    if (message.data['type'] == 'ring') _emitRing(message);
  }

  void _emitRing(RemoteMessage message) {
    final from = (message.data['fromName'] as String?)?.trim();
    _ring.add(from == null || from.isEmpty ? 'A contact' : from);
  }

  /// Delivers a ring recorded by [firebaseMessagingBackgroundHandler] while the
  /// app was backgrounded/terminated. Call once the UI + AlarmBloc are ready
  /// (app start) and again on resume; safe to call when nothing is pending.
  Future<void> deliverPendingRing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final from = prefs.getString(_pendingRingKey);
      if (from == null) return;
      await prefs.remove(_pendingRingKey);
      _ring.add(from);
    } catch (_) {}
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
