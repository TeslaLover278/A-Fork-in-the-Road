# Setting up the Xcode project

This repo does not include a `.xcodeproj` — it was written on a machine
without Xcode/macOS, so there was no way to create and verify a project file
directly. Instead, here's the exact sequence to get a real, working Xcode
project from these source files in a few minutes.

## Fast path: generate the project with XcodeGen

`project.yml` in this folder is an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
spec covering everything steps 1–3 below do by hand:

```sh
brew install xcodegen
cd ios-app
xcodegen generate
open ForkInTheRoad.xcodeproj
```

That sets the iOS 17 deployment target, adds every source file to the app
target, and generates the Info.plist with the location usage description
already in place — so the "app crashes on the permission prompt" failure
below can't happen. Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to
your own, set a Team in Signing & Capabilities, and skip to **step 4**.

The generated `.xcodeproj` is disposable: it's in `.gitignore`, and
regenerating it after adding source files is always safe. If you'd rather
not install XcodeGen, the manual route is below.

## 1. Create the project

1. Open Xcode > **File > New > Project…**
2. Choose **iOS > App**, click Next.
3. Product Name: `ForkInTheRoad`. Interface: **SwiftUI**. Language: **Swift**.
   Storage: none needed — leave "Use Core Data" and "Include Tests" unchecked
   for now (add tests later if you want them).
4. Set a Team/Bundle Identifier as usual, save it anywhere you like.
5. Set the deployment target to **iOS 17.0** (Project > target > General >
   Minimum Deployments) — the code uses the SwiftUI `Map(position:)` API and
   the two-parameter `.onChange` modifier, both iOS 17+.

## 2. Replace the generated files with these

1. In the new project, delete the generated `ContentView.swift` (keep
   `ForkInTheRoadApp.swift` for now, you'll overwrite it).
2. Drag the `ForkInTheRoad/` folder from this repo (everything inside
   `ios-app/ForkInTheRoad/` — `Models/`, `Services/`, `Content/`, `Views/`,
   and `ForkInTheRoadApp.swift`) into the Xcode project navigator, dropped
   onto the project's root group.
   - When prompted, choose **Copy items if needed** and **Create groups**
     (not folder references), and make sure the app target's checkbox is
     ticked for every file.
3. Delete Xcode's auto-generated `ForkInTheRoadApp.swift` if it's still
   present and conflicts with the one you just added (only one `@main`
   struct is allowed).

## 3. Add the Info.plist keys

Open `Info-Plist-Additions.md` in this folder and add the listed keys under
the target's **Info** tab (or directly in `Info.plist` if your template uses
one). Skipping this means the app crashes the moment it asks for location
permission.

## 4. Capabilities

No capabilities are required for the MVP to run in the Simulator or on a
device with When-In-Use location. If you want background tracking later,
see the "Background Modes" section of `Info-Plist-Additions.md`.

## 5. Run it

- **Simulator**: Xcode's Simulator can simulate GPS movement via
  **Features > Location > Custom Location** or by feeding a GPX file
  (**Debug > Simulate Location**), which is the easiest way to test
  rerouting and maneuver announcements without driving anywhere.
- **Device**: build to a real iPhone to hear the two voices and test actual
  live GPS tracking. AirPods/car Bluetooth audio should work automatically
  since the app configures `AVAudioSession` for `.playback` / `.voicePrompt`.

## Known rough edges to expect on first run

These are flagged in code comments too — nothing here is hidden, just
untested without a compiler/device on hand while writing it:

- **Step-boundary timing** (`NavigationEngine.advanceStepsIfNeeded`): the
  heuristic for "we've reached the end of this instruction's segment" is a
  distance-to-polyline-end check. MapKit doesn't document step boundaries
  precisely enough to guarantee this lines up perfectly with when a human
  would expect the next instruction — drive one real route and adjust
  `stepAdvanceRadius`/`approachAnnounceDistance` in `NavigationEngine.swift`
  if instructions feel early/late.
- **Voice matching** (`VoiceCatalog` in `VoicePersona.swift`): each persona
  lists preferred system voices in order (`Tom`, `Aaron`, … / `Ava`, `Zoe`,
  …) and takes the highest-quality variant installed of the first one it
  finds; failing that, the best voice in the right register. A stock
  simulator usually has only the compact variants, which sound noticeably
  worse than what a real device with a downloaded voice gets — so judge the
  voices on hardware, after downloading an Enhanced or Premium English voice
  under **Settings > Accessibility > Spoken Content > Voices**. The app's own
  Settings screen shows which voice and quality each persona resolved to, has
  a per-persona preview button, and prompts for the download if both landed
  on basic voices.
- **Delivery** (`Services/SpeechScript.swift`): lines are cut at their
  punctuation and each clause is spoken with its own pitch/rate/volume and
  pause. The parameters live in `Models/VoiceStyle.swift` and are the thing
  to tune by ear on a device — `pauseScale` and `punchlinePause` in
  particular change comic timing a lot, and are easiest to judge with the
  Settings preview button rather than by driving.
- No unit/UI tests are included — the plan explicitly scoped this to
  UX/feature/voice-system design, not test infrastructure.
