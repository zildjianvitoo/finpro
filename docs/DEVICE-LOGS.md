# Device logs

The app copies its own log messages (every `Logger` with the app's subsystem) into
`Library/Logs/events.log` inside its container, every 10 s and whenever it leaves the foreground
(`finpro/Shared/AppEventLog.swift`). Each launch starts with a `===== launch …` line. The file
stays on the phone (cut back to its newest ~1 MB beyond 2 MB); nothing is sent anywhere.

Categories you will see: `Flow` (screen changes), `Import`, `Recognition` (Shazam), `Lyrics`,
`Preparation`, `Separation`, `KeyPreview`, `Preview`, `Export`, `Capture`, `Prewarm`.

## Pull it from a phone (USB or same Wi-Fi, app installed from Xcode)

Find the phone's identifier:

```bash
xcrun devicectl list devices
```

Copy the file (replace the device name):

```bash
xcrun devicectl device copy from --device "Zildjian Vito 3" --domain-type appDataContainer --domain-identifier pakenanya.finpro --source Library/Logs/events.log --destination events.log
```

This works for builds installed from Xcode (development signing). TestFlight builds cannot be
read this way; use Console.app with the phone connected, filtered on the subsystem
`pakenanya.finpro`.
