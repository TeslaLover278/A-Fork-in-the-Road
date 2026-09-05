# Info.plist additions

Xcode's default SwiftUI App template creates an `Info.plist` (or, in newer
templates, generates these values from build settings under
**Target > Info**). Add the following keys — the app will crash on launch
when requesting location if these are missing, since iOS refuses to show a
permission prompt without a usage description.

| Key | Value | Why |
|---|---|---|
| `NSLocationWhenInUseUsageDescription` | `Fork in the Road needs your location to show turn-by-turn directions while you drive.` | Required for any `CLLocationManager` authorization request. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | `Fork in the Road can keep guiding you (and bantering) even if you switch apps mid-drive.` | Only needed if you later add background location — not required for the MVP, which only requests when-in-use. |

## Background Modes capability (optional, for background tracking)

If you want turn-by-turn to keep working while the phone is locked or
another app is in the foreground:

1. Select the app target > **Signing & Capabilities** > **+ Capability**.
2. Add **Background Modes**.
3. Check **Location updates**.
4. In `LocationService.swift`, you'd also set
   `manager.allowsBackgroundLocationUpdates = true` and
   `manager.pausesLocationUpdatesAutomatically = false` — not included by
   default since it requires the Always authorization above and changes App
   Review expectations (Apple wants a clear justification for background
   location in your app's review notes).

The MVP as delivered only requests **When In Use** and does not need this
capability to run and be tested in the foreground/simulator.
