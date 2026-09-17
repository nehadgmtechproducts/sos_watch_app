import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows the SOS as a high-importance, full-screen-intent notification.
///
/// The full-screen intent is what makes the alarm UI pop over the lock screen
/// on Android. The notification's *sound* is intentionally silent here — the
/// audible siren comes from [AlarmService] on the ALARM stream, which is not
/// muted by the ringer's silent/vibrate mode. (A notification-channel sound
/// would be silenced by Do-Not-Disturb / silent mode, so we don't rely on it.)
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Channel must be created with max importance for full-screen intent to fire.
  static const _channel = AndroidNotificationChannel(
    'sos_alarm_channel',
    'SOS Emergency Alarm',
    description: 'Full-screen emergency alerts from your linked contacts.',
    importance: Importance.max,
    playSound: false, // siren is handled by AlarmService on the alarm stream
    enableVibration: false, // vibration handled by AlarmService
  );

  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false, // requested explicitly elsewhere
      requestSoundPermission: false,
      requestBadgePermission: false,
    );

    await _plugin.initialize(
      settings:
          const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onTap,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  Future<void> showSosFullScreen(Map<String, dynamic> data) async {
    // On Android the native SosAlarmService posts the SOS notification (same
    // id) as part of running the siren. Posting it here as well would replace
    // the service's notification with one it doesn't own.
    if (Platform.isAndroid) return;
    final from = (data['fromName'] as String?) ?? 'A contact';

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true, // <-- pops the alarm UI over the lock screen
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.public,
    );

    await _plugin.show(
      id: 42, // fixed id so we can cancel it when the alarm is dismissed
      title: '🚨 EMERGENCY',
      body: '$from needs help — tap to open',
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: 'sos',
    );
  }

  Future<void> cancelSos() => _plugin.cancel(id: 42);

  void _onTap(NotificationResponse response) {
    // No-op: when an SOS arrives the AlarmBloc is already ringing and
    // AlarmNavigator has shown the alarm screen. Tapping just brings the app
    // to the foreground.
  }

  /// Request the runtime permissions needed for full-screen alarms.
  Future<void> requestPermissions() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
              alert: true, badge: true, sound: true, critical: true);
    } catch (_) {}
  }
}
