Put your siren sound file here, named exactly:

    siren.mp3

Requirements:
  * A loud, looping-friendly alarm/siren tone.
  * Keep it a few seconds long; AlarmService loops it.
  * Royalty-free sources: pixabay.com/sound-effects (search "alarm" / "siren"),
    freesound.org, or mixkit.co.

For iOS Critical Alerts you ALSO need a CAF file bundled natively (see
docs/IOS_CRITICAL_ALERTS.md), named siren.caf and added to the Xcode Runner
target. Convert with:

    afconvert siren.mp3 siren.caf -d ima4 -f caff -v
