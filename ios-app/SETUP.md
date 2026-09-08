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
   `ForkInTheRoadApp.swift` for now, you'll overwrite it) and delete
   Xcode's auto-generated `Assets.xcassets` — this repo ships its own with
   the app icon already in it, and having two catalogs both define
   "AppIcon" is a build error.
2. Drag the `ForkInTheRoad/` folder from this repo (everything inside
   `ios-app/ForkInTheRoad/` — `Models/`, `Services/`, `Content/`, `Views/`,
   `Assets.xcassets`, and `ForkInTheRoadApp.swift`) into the Xcode project
   navigator, dropped onto the project's root group.
   - When prompted, choose **Copy items if needed** and **Create groups**
     (not folder references), and make sure the app target's checkbox is
     ticked for every file.
3. Delete Xcode's auto-generated `ForkInTheRoadApp.swift` if it's still
   present and conflicts with the one you just added (only one `@main`
   struct is allowed).
4. Under the target's **General > App Icons and Launch Screen**, confirm
   **App Icon Source** is set to `AppIcon` (it should be, since that's the
   only icon set in the catalog now).

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
- **Clip bundling** (`Content/BanterAudioBank.swift`): every character line
  is a pre-recorded mp3 under `ForkInTheRoad/Resources/BanterAudio/<persona>/`,
  looked up at play time by resource name via `Bundle.main.url`. If a target
  is set up by hand rather than with XcodeGen, confirm those files actually
  landed in **Copy Bundle Resources** — a clip that wasn't bundled fails
  silently by design (the line is skipped rather than stalling the queue), so
  the symptom is a character who is simply quiet, not a crash. The Settings
  screen's per-persona preview button is the fastest way to check.
- **Silent characters are expected**: nothing is synthesized to stand in for a
  missing recording, so a persona with no clips is genuinely silent. Harry is
  in that state today — he is listed in Settings and says nothing until his
  clips exist. Only plain left/right turns have turn recordings; every other
  maneuver is announced in the plain navigation voice instead.
- No unit/UI tests are included — the plan explicitly scoped this to
  UX/feature/voice-system design, not test infrastructure.
