# Wear OS watch app

Flutter runs on Wear OS, so the watch app is a second Flutter entry point that
talks to the phone (or directly to the relay).

## Two ways to build it

### A. Watch as a thin trigger (recommended to start)
The watch UI is just the big SOS button. On press it tells the **paired phone**
to fire the SOS, using the Wear Data Layer / MessageClient. The phone (which is
already authenticated to Firebase) calls `SosService.fire()`. Simplest, and the
watch needs no network/auth of its own.

Packages:
  * `wear_plus` — detect Wear OS, ambient mode, screen shape.
  * A Data Layer bridge: either `flutter_wear_os_connectivity` or a small
    native MessageClient channel.

### B. Standalone watch (LTE/Wi-Fi watches)
The watch app itself initialises Firebase and calls the `sendSos` function
directly — same `lib/services` code reused. Needs the watch to have
connectivity and its own anonymous auth. More robust if the phone is off, but
more setup.

## Project layout
Create a separate Flutter module/flavor or a second app that depends on the
shared `services/`:

```
sos_emergency/            # phone app (this project)
sos_emergency_wear/       # Wear OS app
  lib/main_wear.dart      # round-screen SOS button -> phone MessageClient or direct fire
```

Build/run on a Wear OS emulator or watch:
```
flutter run -d <wear-device-id>
```

## Watch UI notes
  * Design for a round, ~200dp screen; one large centered button.
  * Use `wear_plus`'s `AmbientMode` to dim when the wrist drops.
  * Long-press (not tap) to avoid accidental fires, same as the phone.

This scaffold ships the phone app + relay first. Say the word and we'll add the
`sos_emergency_wear` module with the Data Layer bridge.
