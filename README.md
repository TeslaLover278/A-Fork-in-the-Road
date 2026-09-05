# Fork in the Road

A turn-by-turn iOS navigation app that works like a normal maps app — live
GPS tracking, real route display, automatic rerouting — except two comedic
AI-voice personas ride along and bicker about the drive.

- **Dez** — dramatic, paranoid, convinced every trip is a near-death
  experience.
- **Vale** — smug, overconfident, has never once been wrong (by her own
  account).

They have no effect on routing or logic. They just talk, and they never get
in the way of the actual directions.

## What's here

```
ios-app/            SwiftUI + MapKit source for the iOS app (see below)
backend/            Node + TypeScript API (banter, accounts, content)
landing-page/       Static single-page marketing site
```

## iOS app

See [`ios-app/SETUP.md`](ios-app/SETUP.md) for exact steps to turn the
source in `ios-app/ForkInTheRoad/` into a runnable Xcode project — with
XcodeGen installed it is `cd ios-app && xcodegen generate`, and the manual
Xcode-GUI route is documented alongside it. In short:

- **Navigation**: MapKit (`MKDirections`, live `CLLocationManager` tracking,
  off-route detection against the route polyline, automatic reroute).
- **Voices**: on-device `AVSpeechSynthesizer`, no cloud TTS, no API keys.
- **Banter**: a scripted content bank (`Content/BanterLineBank.swift`) picked
  by a small rules engine (`Services/BanterEngine.swift`). This works fully
  offline and needs no backend; the backend upgrades it to generated lines
  when reachable, and is not required for the app to function.
- **The core guarantee**: `Services/SpeechQueueManager.swift` is the single
  owner of speech output. Real turn-by-turn instructions always interrupt
  and take priority over banter; banter only ever plays in the gaps.

This was written on a machine without Xcode/macOS available, so there's no
`.xcodeproj` in the repo — `ios-app/SETUP.md` walks through generating one
from the source files in a few minutes, and flags the couple of things
(step-timing heuristics, voice availability) worth sanity-checking on a real
device once you can build it.

The app is designed to run entirely client-side and still work — the
backend below is an enhancement layer, never a dependency.

## Backend

`backend/` is a Node + TypeScript service (Fastify + SQLite). See
[`backend/README.md`](backend/README.md) for the full API and design notes.
It does three things:

- **Generated banter** — fresh Dez/Vale lines from the Claude API instead of
  the fixed script. Every generated line is re-checked server-side and
  rejected if it could be mistaken for a real driving instruction; anything
  filtered falls back to the scripted bank. `/v1/banter` never returns a
  server error for a generation problem, so the app degrades to its offline
  behaviour rather than to an error mid-drive.
- **Accounts and trip sync** — email/password accounts, rotating refresh
  tokens, and last-write-wins trip history sync across devices.
- **Content delivery** — personas and the joke bank served over HTTP with
  ETags, so new material ships without an App Store release.

It runs with no `ANTHROPIC_API_KEY` at all (serving the scripted bank), and
`npm test` covers 122 cases without making a network call.

**The iOS app does not call it yet** — the Swift side has no networking
layer. Wiring the two together is the next step; see the "Not done" section
of the backend README.

## Landing page

`landing-page/index.html` is a single static HTML+CSS page (no build step,
no JS framework, no external dependencies beyond system fonts) describing
the concept, with a placeholder App Store download button. Open it directly
in a browser, or serve the folder with any static file host.
