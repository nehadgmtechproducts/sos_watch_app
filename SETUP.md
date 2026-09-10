# SOS Emergency — static demo

A self-contained demo (no Firebase, no backend, no accounts). It shows:

* a big **SOS button** + a home-screen widget button,
* a local list of **emergency contacts**,
* and the part that matters most — a **loud alarm that rings through silent /
  vibrate mode** on Android, with a full-screen red alarm UI.

Because there's no backend, pressing SOS simulates the send and then rings
**this same device** so you can experience exactly what a recipient would.

---

## 1. Install Flutter (one time)
Your machine doesn't have Flutter yet:
```bash
brew install --cask flutter
flutter doctor          # follow any "✗" fixes (Android toolchain / licenses)
```

## 2. Generate native folders + fetch packages
```bash
cd /Users/pratikmehta/AndroidStudioProjects/sos_emergency
flutter create --platforms=android,ios .   # won't touch lib/ or pubspec.yaml
flutter pub get
```

## 3. Add a siren sound
Drop a loud `siren.mp3` into `assets/audio/` (see that folder's README.txt for
free sources). Without it the alarm is silent.

## 4. (Android) enable the loud-alarm + lock-screen behaviour
Merge the snippets in `android_native_snippets/` — at minimum the permissions
in `AndroidManifest_additions.xml` and the `MainActivity.kt` replacement. The
siren still plays without these, but the full-screen-over-lock-screen and the
home-widget button need them. (See the table in section 6.)

## 5. Run it
```bash
flutter devices
flutter run -d <android-device-id>
```

### Demo script — two phones on the same Wi-Fi
This demo uses **UDP broadcast** over the local network (serverless). One phone
broadcasts; every other phone running the app on the same Wi-Fi rings.

1. Install the app on **two real phones on the same Wi-Fi network**.
2. Set phone B to **silent / vibrate**.
3. On phone A, **long-press the red SOS button**.
4. Phone B **rings loudly** with the full-screen alarm — even on silent. Tap
   **Stop** to dismiss.

### Single-device check (works on an emulator too)
The **"Simulate an incoming SOS"** button rings the *same* device immediately —
handy to test the alarm without a second phone.

> ⚠️ **Two emulators can't do the cross-device demo.** Each Android emulator is
> network-isolated (its own NAT), so broadcasts don't cross between them. Use
> two physical phones on the same Wi-Fi for the real phone-to-phone test; use
> the "Simulate" button on a single emulator.

## 6. Home-screen button (optional)
After `flutter create`, copy these from `android_native_snippets/`:

| Snippet | Goes to |
|---|---|
| `AndroidManifest_additions.xml` | merge into `android/app/src/main/AndroidManifest.xml` |
| `MainActivity.kt` | replace `android/app/src/main/kotlin/.../MainActivity.kt` (fix `package`) |
| `SosWidgetProvider.kt` | `android/app/src/main/kotlin/.../SosWidgetProvider.kt` (fix `package`) |
| `res/layout/sos_widget_layout.xml` | `android/app/src/main/res/layout/` |
| `res/drawable/sos_widget_bg.xml` | `android/app/src/main/res/drawable/` |
| `res/xml/sos_widget_info.xml` | `android/app/src/main/res/xml/` |

Then long-press the home screen → **Widgets** → **SOS Emergency** → drag the
button out. Tapping it opens the app via `sosemergency://sos` and fires the SOS.

---

## How it works
**Delivery (same Wi-Fi, no server)** — [lan_sos_service.dart](lib/services/lan_sos_service.dart):
* Pressing SOS broadcasts a UDP packet to `255.255.255.255` on port `45678`.
* Every phone running the app listens on that port and rings on receipt.
* A native multicast lock ([MainActivity.kt](android/app/src/main/kotlin/com/example/sos_emergency/MainActivity.kt))
  is held so Android actually delivers the broadcast packets.
* Reaches only the **local network** — different networks need a cloud relay + push.

**Loud alarm (bypasses silent)** — [alarm_service.dart](lib/services/alarm_service.dart):
* The siren plays on Android's **`STREAM_ALARM`**. Silent/vibrate mode mutes the
  ring & notification streams but **not** the alarm stream.
* `volume_controller` forces that stream to **max volume** first.
* A **full-screen-intent** notification ([notification_service.dart](lib/services/notification_service.dart))
  pops the alarm UI over the lock screen.

## Turning the demo into the real app later
This demo deliberately has no networking. To make one phone ring another phone,
you add back the Firebase relay (anonymous auth + Firestore tokens + a
`sendSos` Cloud Function) and replace [sos_demo_service.dart](lib/services/sos_demo_service.dart)
with a real send. The alarm/receiver code stays exactly the same. The earlier
backend version is in this conversation's history if you want it back.

* **iOS** ringing-through-silent needs Apple's **Critical Alerts** entitlement.
* **Watch:** Wear OS only (Flutter can't target Apple Watch) — see `docs/WEAR_OS.md`.
```
