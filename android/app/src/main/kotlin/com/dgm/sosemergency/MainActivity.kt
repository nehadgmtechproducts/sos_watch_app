package com.dgm.sosemergency

import android.app.Activity
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.telephony.PhoneStateListener
import android.telephony.SmsManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import java.util.concurrent.atomic.AtomicBoolean
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    // Held only while an "awaitCallEnd" request is in flight, so the listener
    // can be unregistered once the call finishes.
    private var callStateCallback: Any? = null
    private var callStateListener: PhoneStateListener? = null
    // Held only while an SMS fan-out is awaiting its per-message sent-intents.
    private var smsResultReceiver: BroadcastReceiver? = null

    private companion object {
        // Matches the Dart side's "[SOS-CALL]" prefix, so one logcat filter
        // shows the whole sequence: adb logcat | grep -E "SOS-CALL|SosCall"
        const val CALL_LOG_TAG = "SosCall"
        const val EXTRA_SMS_RECIPIENT = "sms_recipient"
        const val SMS_RESULT_TIMEOUT_MS = 20_000L
        // Spaces out each recipient's PendingIntent request codes so the parts
        // of one message can't collide with another recipient's.
        const val MAX_SMS_PARTS = 100
    }

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

    override fun onDestroy() {
        // An SOS can be fired right before the activity goes away; don't leak
        // the sent-intent receiver if its results never arrived.
        smsResultReceiver?.let { receiver ->
            try { unregisterReceiver(receiver) } catch (e: Exception) { }
        }
        smsResultReceiver = null
        super.onDestroy()
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
                            Log.i(CALL_LOG_TAG, "ACTION_CALL dispatched to $phoneNumber")
                            result.success(true)
                        } catch (e: SecurityException) {
                            Log.e(CALL_LOG_TAG, "CALL_PHONE denied for $phoneNumber", e)
                            result.error("call_permission_denied", "CALL_PHONE permission denied.", null)
                        } catch (e: Exception) {
                            Log.e(CALL_LOG_TAG, "Could not dial $phoneNumber", e)
                            result.error("call_failed", e.message, null)
                        }
                    }
                    // Block until the in-progress call ends, so the next contact
                    // is dialled only once the line is free. Returns true when a
                    // call actually started and finished, false on timeout (or
                    // when this device has no telephony at all).
                    "awaitCallEnd" -> {
                        val timeoutMs = (call.argument<Int>("timeoutMs") ?: 45_000).toLong()
                        awaitCallEnd(timeoutMs, result)
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
                        sendSmsWithResults(numbers, message, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Sends the emergency SMS to each recipient separately and waits for the
     * platform's own per-message result.
     *
     * `sendMultipartTextMessage` returns immediately and reports nothing, so
     * passing no sent-intent (as this used to) meant a message the radio never
     * transmitted — no SIM, no service, carrier rejection — was still counted
     * as delivered and shown to the user as "sent". The PendingIntent below is
     * what turns that silent failure into a real result.
     */
    private fun sendSmsWithResults(
        numbers: List<String>,
        message: String,
        result: MethodChannel.Result,
    ) {
        // A tethered Wear OS watch or an emulator has no cellular radio at all;
        // say so plainly instead of reporting a send that cannot happen.
        val messagingFeature = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PackageManager.FEATURE_TELEPHONY_MESSAGING
        } else {
            @Suppress("DEPRECATION") PackageManager.FEATURE_TELEPHONY
        }
        if (!packageManager.hasSystemFeature(messagingFeature)) {
            result.error(
                "sms_no_telephony",
                "This device has no cellular radio, so it cannot send SMS.",
                null,
            )
            return
        }

        val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applicationContext.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION") SmsManager.getDefault()
        }
        val parts = sms.divideMessage(message)
        val action = "$packageName.SMS_SENT.${System.currentTimeMillis()}"
        val expected = numbers.size * parts.size
        val outcomes = AtomicInteger(0)
        val failedRecipients = Collections.synchronizedSet(mutableSetOf<Int>())
        val replied = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        var onTimeout: Runnable? = null

        fun releaseReceiver() {
            onTimeout?.let { handler.removeCallbacks(it) }
            smsResultReceiver?.let { receiver ->
                try { unregisterReceiver(receiver) } catch (e: Exception) { }
            }
            smsResultReceiver = null
        }

        fun reply() {
            if (!replied.compareAndSet(false, true)) return
            releaseReceiver()
            val failed = failedRecipients.size
            val sent = numbers.size - failed
            if (sent == 0) {
                result.error("sms_failed", "Every message was rejected by the network.", null)
            } else {
                result.success(mapOf("sent" to sent, "failed" to failed))
            }
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val recipient = intent?.getIntExtra(EXTRA_SMS_RECIPIENT, -1) ?: -1
                if (resultCode != Activity.RESULT_OK && recipient >= 0) {
                    failedRecipients.add(recipient)
                }
                if (outcomes.incrementAndGet() >= expected) reply()
            }
        }
        smsResultReceiver = receiver
        ContextCompat.registerReceiver(
            this, receiver, IntentFilter(action), ContextCompat.RECEIVER_NOT_EXPORTED,
        )

        // Delivery reports can be slow or never arrive; don't hang the SOS flow.
        onTimeout = Runnable { reply() }
        handler.postDelayed(onTimeout, SMS_RESULT_TIMEOUT_MS)

        try {
            numbers.forEachIndexed { recipient, number ->
                val sentIntents = ArrayList<PendingIntent>(parts.size)
                for (part in parts.indices) {
                    sentIntents.add(
                        PendingIntent.getBroadcast(
                            this,
                            recipient * MAX_SMS_PARTS + part,
                            Intent(action)
                                .setPackage(packageName)
                                .putExtra(EXTRA_SMS_RECIPIENT, recipient),
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    )
                }
                try {
                    sms.sendMultipartTextMessage(number, null, parts, sentIntents, null)
                } catch (e: SecurityException) {
                    throw e // a permission problem affects every recipient
                } catch (e: Exception) {
                    // Rejected outright — no broadcast will arrive for it.
                    failedRecipients.add(recipient)
                    if (outcomes.addAndGet(parts.size) >= expected) reply()
                }
            }
        } catch (e: SecurityException) {
            if (replied.compareAndSet(false, true)) {
                releaseReceiver()
                result.error("sms_permission_denied", "SEND_SMS permission denied.", null)
            }
        }
    }

    /**
     * Watches the telephony call state and completes once an outgoing call has
     * started and then returned to idle — i.e. the user hung up, the callee
     * declined, or it rang out. [timeoutMs] caps the wait so one unanswered
     * contact can never stall the rest of the emergency call list.
     */
    private fun awaitCallEnd(timeoutMs: Long, result: MethodChannel.Result) {
        val telephony = applicationContext
            .getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        if (telephony == null) {
            result.success(false)
            return
        }

        val handler = Handler(Looper.getMainLooper())
        val finished = AtomicBoolean(false)
        var callStarted = false
        var onTimeout: Runnable? = null

        fun finish(ended: Boolean) {
            if (!finished.compareAndSet(false, true)) return
            onTimeout?.let { handler.removeCallbacks(it) }
            stopListeningToCallState(telephony)
            Log.i(
                CALL_LOG_TAG,
                if (ended) "Call ended — ready for the next contact"
                else "No call-end seen within ${timeoutMs}ms — advancing anyway",
            )
            result.success(ended)
        }

        val onState = { state: Int ->
            when (state) {
                TelephonyManager.CALL_STATE_OFFHOOK,
                TelephonyManager.CALL_STATE_RINGING -> callStarted = true
                // Idle before the call ever went off-hook is just the state we
                // started in — only treat it as "ended" once a call was seen.
                TelephonyManager.CALL_STATE_IDLE -> if (callStarted) finish(true)
            }
            Unit
        }

        onTimeout = Runnable { finish(false) }
        handler.postDelayed(onTimeout, timeoutMs)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) { onState(state) }
                }
                callStateCallback = callback
                telephony.registerTelephonyCallback(mainExecutor, callback)
            } else {
                @Suppress("DEPRECATION")
                val listener = object : PhoneStateListener() {
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        onState(state)
                    }
                }
                callStateListener = listener
                @Suppress("DEPRECATION")
                telephony.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            }
        } catch (e: SecurityException) {
            // READ_PHONE_STATE not granted — fall back to the caller's timer.
            finish(false)
        }
    }

    private fun stopListeningToCallState(telephony: TelephonyManager) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (callStateCallback as? TelephonyCallback)
                    ?.let { telephony.unregisterTelephonyCallback(it) }
            } else {
                @Suppress("DEPRECATION")
                (callStateListener)?.let {
                    telephony.listen(it, PhoneStateListener.LISTEN_NONE)
                }
            }
        } catch (e: Exception) {
            // Nothing actionable — the listener is being dropped either way.
        }
        callStateCallback = null
        callStateListener = null
    }
}
