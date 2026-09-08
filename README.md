# Fork in the Road

A turn-by-turn iOS navigation app that works like a normal maps app — live
GPS tracking, real route display, automatic rerouting — except two comedic
AI-voice personas ride along and bicker about the drive.

- **Dan** — dramatic, paranoid, convinced every trip is a near-death
  experience.
- **Harry** — smug, overconfident, has never once been wrong (by his own
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
- **Voices**: pre-recorded only. Every line a character speaks is a real
  performance bundled with the app (`Resources/BanterAudio/<persona>/`,
  inventoried in `Content/BanterAudioBank.swift`) and played back through
  `AVAudioPlayer`. Nothing is synthesized: there is no per-character voice
  matching and no prosody pass, because there is no generated speech left to
  make sound human. A line that hasn't been recorded is simply not spoken, and
  a character with no recordings yet — Harry, currently — stays listed in
  Settings but silent.
- **Banter**: which recording plays when is decided by a small rules engine
  (`Services/BanterEngine.swift`) over the clip inventory. Fully offline; no
  backend required. While a clip plays, `Views/BanterWaveformView.swift` shows
  who is talking and a waveform driven by the player's own level meter — there
  are no transcripts to subtitle, so the indicator shows what the app actually
  knows.
- **Directions**: ordinary left/right turns are called out by a recorded
  character clip. Everything a fixed recording can't describe — distances,
  street names, roundabouts, merges, exits, u-turns — is read out in a plain
  system voice instead, which is the one and only place
  `AVSpeechSynthesizer` is still used. A "Real directions" setting switches
  every turn over to that plain voice; it is off by default.
- **The core guarantee**: `Services/SpeechQueueManager.swift` is the single
  owner of speech output. Real turn-by-turn instructions always interrupt
  and take priority over banter; banter only ever plays in the gaps.

This was written on a machine without Xcode/macOS available, so there's no
`.xcodeproj` in the repo — `ios-app/SETUP.md` walks through generating one
from the source files in a few minutes, and flags the couple of things
(step-timing heuristics, clip playback) worth sanity-checking on a real
device once you can build it.

The app is designed to run entirely client-side and still work — the
backend below is an enhancement layer, never a dependency.

## Backend

`backend/` is a Node + TypeScript service (Fastify + SQLite). See
[`backend/README.md`](backend/README.md) for the full API and design notes.
It does three things:

- **Generated banter** — fresh Dan/Harry lines as *text*, from the Claude
  API. Every generated line is re-checked server-side and rejected if it
  could be mistaken for a real driving instruction; anything filtered falls
  back to the scripted bank. `/v1/banter` never returns a server error for a
  generation problem, so a caller degrades rather than erroring mid-drive.
  Note that the iOS app does not consume this today: it speaks only from its
  recordings, so there is nothing on the client to voice a generated line.
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
