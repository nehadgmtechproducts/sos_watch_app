package com.dgm.sosemergency

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Replaces the firebase_messaging plugin's service (see AndroidManifest.xml) so
 * an incoming SOS can be made loud *natively*, before anything else happens.
 *
 * Why this has to live here: when the receiver's app is closed, the push is
 * handled by a background Dart isolate on a separate Flutter engine. Our
 * `sos_emergency/alarm` method channel is only registered on the main
 * activity's engine, so that isolate has no way to raise the volume — the
 * notification's siren would play at whatever (possibly near-zero) alarm
 * volume the phone was left at. This service runs in the app process for every
 * push, in every app state, with no Flutter engine required.
 *
 * Everything else is delegated to the plugin via `super`, so Dart still
 * receives every message exactly as before.
 */
class SosMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        if (remoteMessage.data["type"] == "ring") {
            Log.i("SosAlarm", "Ring push received — raising volume before the siren plays")
            try {
                AlarmVolumeGuard.raise(this)
            } catch (e: Exception) {
                // Never let a volume problem stop the alarm from being delivered.
                Log.e("SosAlarm", "Failed to raise alarm volume", e)
            }
        }
        super.onMessageReceived(remoteMessage)
    }
}
