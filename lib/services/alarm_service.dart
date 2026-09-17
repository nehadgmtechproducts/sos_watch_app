import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Plays a loud, looping siren that is audible even when the phone is on
/// silent / vibrate, has low (or zero) alarm volume, or is in Do-Not-Disturb.
///
/// How each setting is beaten on Android:
///  * **Ringer silent/vibrate** — audio is played with
///    [AudioContextAndroid.usageType] = `alarm`, routing it to STREAM_ALARM,
///    which the ringer's silent/vibrate mode does NOT mute.
///  * **Low / zero alarm volume** — the native `raiseAlarm` method forces
///    STREAM_ALARM to its maximum (`AudioManager.setStreamVolume`).
///  * **Do-Not-Disturb / Focus** — if the user granted notification-policy
///    access, `raiseAlarm` also turns DND off for the duration of the alarm.
///
/// Both are done by the native `AlarmVolumeGuard`, which is shared with
/// `SosMessagingService`: when the app is closed, that service raises the
/// volume the moment the push arrives, before this class ever runs. The guard
/// remembers the user's true original settings, which [stop] restores.
///
/// On iOS, true silent-switch override additionally needs the Critical Alerts
/// entitlement (see docs/IOS_CRITICAL_ALERTS.md).
class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  static const MethodChannel _native = MethodChannel('sos_emergency/alarm');

  final AudioPlayer _player = AudioPlayer();
  bool _ringing = false;

  bool get isRinging => _ringing;

  /// True if we're allowed to override Do-Not-Disturb. Used to prompt the user.
  static Future<bool> isDndAccessGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _native.invokeMethod<bool>('isDndAccessGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system screen where the user grants DND override access.
  static Future<void> requestDndAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await _native.invokeMethod('requestDndAccess');
    } catch (_) {}
  }

  Future<void> start(Map<String, dynamic> data) async {
    if (_ringing) return;
    _ringing = true;

    await WakelockPlus.enable();

    if (Platform.isAndroid) {
      // Android: the native SosAlarmService plays the siren, raises alarm
      // volume and lifts DND. It is the single source of sound in every app
      // state — when the app was closed it is already ringing by the time we
      // get here (started by the push), and this call just keeps it going.
      // Playing here too would stack a second siren on top of it.
      try {
        await _native.invokeMethod(
            'startAlarm', {'fromName': data['fromName'] ?? 'A contact'});
      } catch (_) {}
      return;
    }

    // iOS: in-app playback.

    // Route playback to the ALARM stream so silent mode does not mute it.
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm, // <-- the key line
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.duckOthers},
        ),
      ),
    );

    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
    await _player.play(AssetSource('audio/siren.mp3'));

    // Continuous vibration pattern alongside the siren.
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(
        pattern: [0, 800, 400, 800, 400],
        repeat: 0, // repeat from index 0 => continuous until cancelled
      );
    }
  }

  Future<void> stop() async {
    if (_ringing) {
      _ringing = false;
      await WakelockPlus.disable();
      if (!Platform.isAndroid) {
        await _player.stop();
        Vibration.cancel();
      }
    }

    // Stop even when this class never started the alarm: with the app closed,
    // the push started the native siren on its own, and this is the only place
    // it gets stopped. Also restores volume/DND; a no-op if nothing is ringing.
    if (Platform.isAndroid) {
      try {
        await _native.invokeMethod('stopAlarm');
      } catch (_) {}
    }
  }
}
