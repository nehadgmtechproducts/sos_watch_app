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
///  * **Low / zero alarm volume** — the native `maxAlarmVolume` method forces
///    STREAM_ALARM to its maximum (`AudioManager.setStreamVolume`).
///  * **Do-Not-Disturb / Focus** — if the user granted notification-policy
///    access, `disableDnd` turns DND off for the duration of the alarm.
///
/// All of the original settings are restored in [stop].
///
/// On iOS, true silent-switch override additionally needs the Critical Alerts
/// entitlement (see docs/IOS_CRITICAL_ALERTS.md).
class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  static const MethodChannel _native = MethodChannel('sos_emergency/alarm');

  final AudioPlayer _player = AudioPlayer();
  bool _ringing = false;
  int? _previousAlarmVolume;
  int? _previousDndFilter;

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
      // Force the ALARM stream to max so a low/zero alarm volume can't quiet us.
      try {
        _previousAlarmVolume =
            await _native.invokeMethod<int>('maxAlarmVolume');
      } catch (_) {}
      // If allowed, turn Do-Not-Disturb off for the duration of the alarm.
      try {
        final prev = await _native.invokeMethod<int>('disableDnd');
        if (prev != null && prev > 0) _previousDndFilter = prev;
      } catch (_) {}
    }

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
    if (!_ringing) return;
    _ringing = false;

    await _player.stop();
    Vibration.cancel();
    await WakelockPlus.disable();

    if (Platform.isAndroid) {
      if (_previousAlarmVolume != null) {
        try {
          await _native.invokeMethod(
              'restoreAlarmVolume', {'volume': _previousAlarmVolume});
        } catch (_) {}
        _previousAlarmVolume = null;
      }
      if (_previousDndFilter != null) {
        try {
          await _native
              .invokeMethod('restoreDnd', {'filter': _previousDndFilter});
        } catch (_) {}
        _previousDndFilter = null;
      }
    }
  }
}
