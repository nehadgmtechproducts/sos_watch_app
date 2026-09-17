package com.dgm.sosemergency

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Replaces the firebase_messaging plugin's service (see AndroidManifest.xml) so
 * an incoming SOS starts ringing *natively*, the instant the push arrives.
 *
 * Why this has to live here: when the receiver's app is closed, the push is
 * otherwise handled by a background Dart isolate on a separate Flutter engine,
 * which has no access to our method channels and can only post a notification
 * — and from Android 15 the system may play such a notification as vibration
 * only. This service runs in the app process for every push, in every app
 * state, and hands the ring to [SosAlarmService], which plays the siren itself.
 *
 * Everything else is delegated to the plugin via `super`, so Dart still
 * receives every message exactly as before (it records the pending ring so the
 * alarm screen opens when the app does).
 */
class SosMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        if (remoteMessage.data["type"] == "ring") {
            val fromName = remoteMessage.data["fromName"]?.trim()
                .takeUnless { it.isNullOrEmpty() } ?: "A contact"
            Log.i("SosAlarm", "Ring push received from $fromName — starting siren")
            try {
                SosAlarmService.start(this, fromName)
            } catch (e: Exception) {
                // Never let this stop the message reaching Dart below.
                Log.e("SosAlarm", "Failed to start the siren", e)
            }
        }
        super.onMessageReceived(remoteMessage)
    }
}
