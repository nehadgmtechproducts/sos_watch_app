package com.dgm.sosemergency

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Plays the SOS siren itself, on the alarm stream, from a foreground service.
 *
 * Why not a notification sound: Android decides whether a notification's sound
 * plays, and from Android 15 it can refuse. NotificationAttentionHelper gained
 * a `vibrateOnly` path that skips the sound of any notification that also
 * vibrates (while unlocked, with the new notification-cooldown setting on), and
 * "polite notifications" that scale down repeated alerts; manufacturer builds
 * add vibrate-mode muting on top. The result was an SOS that only vibrated on
 * an Android 15 phone in vibrate mode, while Android 13 rang loudly.
 *
 * Audio played by the app through MediaPlayer with USAGE_ALARM never passes
 * through that notification logic, so ringer mode, cooldown and polite volume
 * don't apply — only alarm-stream volume, which [AlarmVolumeGuard] raises to
 * max. It is how clock apps ring. The foreground service keeps the process (and
 * the siren) alive while the app is closed.
 *
 * Stopped with [stop]; everything is torn down, and the user's volume and DND
 * restored, in [onDestroy].
 */
class SosAlarmService : Service() {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val fromName = intent?.getStringExtra(EXTRA_FROM_NAME) ?: "A contact"

        // Must happen promptly after startForegroundService, or the system
        // kills the app. Repeat starts just refresh the notification.
        val notification = buildNotification(this, fromName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        if (player == null) {
            Log.i(TAG, "Starting siren for SOS from $fromName")
            try {
                AlarmVolumeGuard.raise(this)
            } catch (e: Exception) {
                Log.e(TAG, "Could not raise alarm volume", e)
            }
            startSiren()
            startVibration()
        }
        // Not sticky: if the system kills us, don't resurrect a siren later.
        return START_NOT_STICKY
    }

    private fun startSiren() {
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(
                    this@SosAlarmService,
                    Uri.parse("android.resource://$packageName/${R.raw.siren}"),
                )
                isLooping = true
                setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Siren failed to start", e)
            player?.release()
            player = null
        }
    }

    private fun startVibration() {
        val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!v.hasVibrator()) return
        vibrator = v

        // Repeat from index 0 until cancelled.
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 800, 400, 800, 400), 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Alarm usage: vibration isn't suppressed the way notification
            // vibration can be.
            v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(
                effect,
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build(),
            )
        }
    }

    override fun onDestroy() {
        Log.i(TAG, "Stopping siren")
        player?.run {
            try {
                stop()
            } catch (e: IllegalStateException) {
                // Never started or already stopped — release regardless.
            }
            release()
        }
        player = null
        vibrator?.cancel()
        vibrator = null
        try {
            AlarmVolumeGuard.restore(this)
        } catch (e: Exception) {
            Log.e(TAG, "Could not restore alarm volume", e)
        }
        super.onDestroy()
    }

    companion object {
        private const val TAG = "SosAlarm"
        private const val EXTRA_FROM_NAME = "from_name"

        /** Shared with the Dart side's notification id, so they never stack. */
        const val NOTIFICATION_ID = 42

        /** Silent: the service plays the siren and drives vibration itself. */
        private const val CHANNEL_ID = "sos_alarm_service_v1"

        /**
         * Only used if the service can't start (see [start]); the system plays
         * this channel's sound, so it's the best available fallback.
         */
        private const val FALLBACK_CHANNEL_ID = "sos_alarm_loud_v1"

        /**
         * Start (or refresh) the siren. Safe to call repeatedly — the push
         * service and the open app both call it for the same SOS.
         *
         * Starting a foreground service from the background is allowed while
         * handling a high-priority FCM message, which is how the backend sends
         * rings. If the system refuses anyway (e.g. it downgraded the message's
         * priority), fall back to a loud insistent notification: it may be
         * reduced to vibration on Android 15, but it is far better than silence.
         */
        fun start(context: Context, fromName: String) {
            val intent = Intent(context, SosAlarmService::class.java)
                .putExtra(EXTRA_FROM_NAME, fromName)
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (e: Exception) {
                Log.e(TAG, "Foreground service start refused — using fallback notification", e)
                postFallbackNotification(context, fromName)
            }
        }

        /** Stop the siren, restore volume/DND, and remove the notification. */
        fun stop(context: Context) {
            context.stopService(Intent(context, SosAlarmService::class.java))
            // Also clears the fallback notification if that path was used; the
            // guard restore is a no-op when nothing was raised.
            context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
            AlarmVolumeGuard.restore(context)
        }

        private fun openAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun buildNotification(context: Context, fromName: String): Notification {
            val nm = context.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "SOS Emergency Alarm",
                        NotificationManager.IMPORTANCE_HIGH,
                    ).apply {
                        description = "Full-screen emergency alerts from your linked contacts."
                        setSound(null, null)
                        enableVibration(false)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    }
                )
            }
            val open = openAppIntent(context)
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("🚨 EMERGENCY")
                .setContentText("$fromName needs help — tap to open")
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(open)
                .setFullScreenIntent(open, true)
                .build()
        }

        private fun postFallbackNotification(context: Context, fromName: String) {
            try {
                AlarmVolumeGuard.raise(context)
            } catch (e: Exception) {
                Log.e(TAG, "Could not raise alarm volume", e)
            }
            val nm = context.getSystemService(NotificationManager::class.java)
            val siren = Uri.parse("android.resource://${context.packageName}/${R.raw.siren}")
            if (nm.getNotificationChannel(FALLBACK_CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        FALLBACK_CHANNEL_ID,
                        "SOS Emergency Alarm (fallback)",
                        NotificationManager.IMPORTANCE_HIGH,
                    ).apply {
                        setSound(
                            siren,
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build(),
                        )
                        enableVibration(true)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    }
                )
            }
            val open = openAppIntent(context)
            val notification = NotificationCompat.Builder(context, FALLBACK_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("🚨 EMERGENCY")
                .setContentText("$fromName needs help — tap to open")
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(open)
                .setFullScreenIntent(open, true)
                .build()
            // FLAG_INSISTENT: keep repeating the sound until cancelled.
            notification.flags = notification.flags or Notification.FLAG_INSISTENT
            nm.notify(NOTIFICATION_ID, notification)
        }
    }
}
