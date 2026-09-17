package com.dgm.sosemergency

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.util.Log

/**
 * Makes an incoming SOS loud regardless of the receiver's settings, and puts
 * those settings back afterwards.
 *
 *  * **Ringer silent / vibrate** — handled by playing on the alarm stream
 *    (the notification channel and AlarmService both use alarm usage), which
 *    silent mode does not mute. Nothing to do here.
 *  * **Low or zero alarm volume** — [raise] forces STREAM_ALARM to maximum.
 *  * **Do-Not-Disturb** — [raise] turns DND off, if the user granted
 *    notification-policy access.
 *
 * This is native and state-free on purpose: it is called both from
 * [SosMessagingService] — which runs when a push arrives even with the app
 * killed, when no Flutter engine with our method channels exists — and from
 * the app's own alarm channel while it is open.
 *
 * The originals are persisted and only captured once per alarm. Both callers
 * raise, so without that guard the second call would record the already-maxed
 * volume as "original", and stopping the alarm would leave the phone at full
 * volume permanently.
 */
object AlarmVolumeGuard {
    private const val TAG = "SosAlarm"
    private const val PREFS = "sos_alarm_guard"
    private const val KEY_VOLUME = "original_alarm_volume"
    private const val KEY_DND = "original_dnd_filter"
    private const val NONE = -1

    /** Raise the alarm stream to max and lift DND. Safe to call repeatedly. */
    @Synchronized
    fun raise(context: Context) {
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val current = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        if (!prefs.contains(KEY_VOLUME)) {
            prefs.edit().putInt(KEY_VOLUME, current).apply()
        }
        try {
            audio.setStreamVolume(AudioManager.STREAM_ALARM, max, 0)
            Log.i(TAG, "Alarm volume raised $current → $max")
        } catch (e: SecurityException) {
            // Thrown while DND is active and we lack policy access.
            Log.w(TAG, "Could not raise alarm volume (DND without policy access)", e)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.isNotificationPolicyAccessGranted) {
                if (!prefs.contains(KEY_DND)) {
                    prefs.edit().putInt(KEY_DND, nm.currentInterruptionFilter).apply()
                }
                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                Log.i(TAG, "Do-Not-Disturb lifted for the alarm")
            } else {
                Log.w(TAG, "No DND policy access — alarm may be muted if DND is on")
            }
        }
    }

    /** Put the original volume and DND back. No-op if nothing was raised. */
    @Synchronized
    fun restore(context: Context) {
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        val volume = prefs.getInt(KEY_VOLUME, NONE)
        if (volume != NONE) {
            val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            try {
                audio.setStreamVolume(AudioManager.STREAM_ALARM, volume, 0)
                Log.i(TAG, "Alarm volume restored to $volume")
            } catch (e: SecurityException) {
                Log.w(TAG, "Could not restore alarm volume", e)
            }
        }

        val filter = prefs.getInt(KEY_DND, NONE)
        if (filter > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.isNotificationPolicyAccessGranted) {
                nm.setInterruptionFilter(filter)
                Log.i(TAG, "Do-Not-Disturb restored")
            }
        }

        prefs.edit().remove(KEY_VOLUME).remove(KEY_DND).apply()
    }
}
