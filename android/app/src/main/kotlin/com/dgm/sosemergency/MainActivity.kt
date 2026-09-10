package com.dgm.sosemergency

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.telephony.SmsManager
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Must run before super.onCreate() — takes explicit, code-level control
        // of the splash screen instead of relying solely on theme attributes,
        // which some OEM skins (e.g. Samsung One UI) don't fully respect.
        installSplashScreen()
        super.onCreate(savedInstanceState)
        // Ensure the alarm UI shows over the lock screen and turns the screen on
        // when launched from the full-screen-intent notification.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Android drops broadcast/multicast UDP packets unless a multicast lock
        // is held. LanSosService asks us to acquire one so it can receive SOS
        // broadcasts on the local network.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sos_emergency/wifi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticastLock" -> {
                        if (multicastLock == null) {
                            val wifi = applicationContext
                                .getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("sos_emergency").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(true)
                    }
                    "releaseMulticastLock" -> {
                        multicastLock?.release()
                        multicastLock = null
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Force the alarm to be audible regardless of the receiver's volume /
        // Do-Not-Disturb settings.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sos_emergency/alarm")
            .setMethodCallHandler { call, result ->
                val audio = applicationContext
                    .getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val nm = applicationContext
                    .getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val hasDndAccess = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                    nm.isNotificationPolicyAccessGranted
                when (call.method) {
                    // Max out the ALARM stream; returns the previous level to restore.
                    "maxAlarmVolume" -> {
                        val prev = audio.getStreamVolume(AudioManager.STREAM_ALARM)
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                        try {
                            audio.setStreamVolume(AudioManager.STREAM_ALARM, max, 0)
                        } catch (e: SecurityException) {
                            // DND is active and we lack policy access — ignore.
                        }
                        result.success(prev)
                    }
                    "restoreAlarmVolume" -> {
                        val v = call.argument<Int>("volume")
                        if (v != null) {
                            try {
                                audio.setStreamVolume(AudioManager.STREAM_ALARM, v, 0)
                            } catch (e: SecurityException) { }
                        }
                        result.success(true)
                    }
                    // Turn Do-Not-Disturb off for the emergency (needs access);
                    // returns the previous interruption filter to restore.
                    "disableDnd" -> {
                        if (hasDndAccess && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val prevFilter = nm.currentInterruptionFilter
                            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                            result.success(prevFilter)
                        } else {
                            result.success(-1)
                        }
                    }
                    "restoreDnd" -> {
                        val f = call.argument<Int>("filter") ?: -1
                        if (f > 0 && hasDndAccess &&
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            nm.setInterruptionFilter(f)
                        }
                        result.success(true)
                    }
                    "isDndAccessGranted" -> result.success(hasDndAccess)
                    "requestDndAccess" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            startActivity(
                                Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sos_emergency/phone")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "placeCall" -> {
                        val phoneNumber = call.argument<String>("phoneNumber")?.trim().orEmpty()
                        if (phoneNumber.isEmpty()) {
                            result.error("missing_phone_number", "Phone number is empty.", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val intent = Intent(
                                Intent.ACTION_CALL,
                                Uri.fromParts("tel", phoneNumber, null)
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("call_permission_denied", "CALL_PHONE permission denied.", null)
                        } catch (e: Exception) {
                            result.error("call_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Send the emergency SMS (with location) directly via SmsManager.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sos_emergency/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val numbers = call.argument<List<String>>("numbers").orEmpty()
                        val message = call.argument<String>("message").orEmpty()
                        if (numbers.isEmpty() || message.isEmpty()) {
                            result.error("missing_args", "numbers/message empty.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                applicationContext.getSystemService(SmsManager::class.java)
                            } else {
                                @Suppress("DEPRECATION") SmsManager.getDefault()
                            }
                            for (number in numbers) {
                                val parts = sms.divideMessage(message)
                                sms.sendMultipartTextMessage(number, null, parts, null, null)
                            }
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("sms_permission_denied", "SEND_SMS permission denied.", null)
                        } catch (e: Exception) {
                            result.error("sms_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
