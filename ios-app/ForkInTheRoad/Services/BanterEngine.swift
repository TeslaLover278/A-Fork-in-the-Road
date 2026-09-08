import Foundation

/// Decides *when* and *what* comedic banter fires. This is intentionally
/// dumb about routing — it only reacts to NavigationEvents it's handed and
/// pushes finished lines into SpeechQueueManager's low-priority banter lane,
/// which is what actually guarantees banter can't step on real directions.
///
/// Everything a character says comes from a pre-recorded clip in
/// `BanterAudioBank`. There is no synthesized stand-in for a line that hasn't
/// been recorded: a persona/category with no clip simply stays quiet, and a
/// persona with no clips at all (`VoicePersona.hasRecordedClips`) never
/// speaks.
///
/// Turns are the one exception to "just flavor": where a recorded turn clip
/// exists, Dan *is* how the turn gets spoken — see `announceManeuver`. Where
/// one doesn't, the turn is not left to silence; `canAnnounceManeuver` tells
/// `ContentView` to fall back to the plain navigation voice instead.
@MainActor
final class BanterEngine: ObservableObject {
    private let settings: BanterSettings
    private let speechQueue: SpeechQueueManager

    private var lastFired: [BanterCategory: Date] = [:]
    private var recentClipNames: [String] = []
    private let recentHistoryLimit = 12
    private var hasFiredTripStart = false
    private var hasFiredArrival = false

    /// Avoid picking the same turn clip twice in a row.
    private var recentTurnClipNames: [String] = []

    init(settings: BanterSettings, speechQueue: SpeechQueueManager) {
        self.settings = settings
        self.speechQueue = speechQueue
    }

    /// Call when a new trip starts so the once-per-trip triggers (trip
    /// start, arrival) can fire again.
    func resetForNewTrip() {
        hasFiredTripStart = false
        hasFiredArrival = false
        lastFired.removeAll()
        recentClipNames.removeAll()
        recentTurnClipNames.removeAll()
    }

    /// Whether this maneuver has a character who can actually announce it.
    /// False means no unmuted persona has a recorded clip for this direction
    /// — sharp turns, roundabouts, merges, exits and u-turns always land here
    /// — and the caller must speak the plain instruction itself. Silence on a
    /// turn is never an option, so `ContentView` consults this before
    /// deciding whether to skip the real announcement.
    ///
    /// Deliberately a pure query: it must not touch the recently-used clip
    /// history, or asking the question would change which clip
    /// `announceManeuver` then picks.
    func canAnnounceManeuver(step: RouteStepInfo) -> Bool {
        guard settings.frequency != .off, !settings.mustUseRealDirections else { return false }
        guard let direction = BanterAudioBank.direction(for: step.instructions) else { return false }
        return VoicePersona.all.contains { persona in
            !settings.isMuted(persona) && BanterAudioBank.hasTurnClip(persona: persona.id, direction: direction)
        }
    }

    func handle(_ event: NavigationEvent) {
        guard settings.frequency != .off else { return }

        switch event {
        case .tripStarted:
            guard !hasFiredTripStart else { return }
            hasFiredTripStart = true
            fireExchange(for: .tripStart)
        case .approachingManeuver(let step, _):
            guard !settings.mustUseRealDirections else { return } // real voice already covers this maneuver
            announceManeuver(step: step)
        case .wentOffRoute, .rerouted:
            fireExchange(for: .rerouting)
        case .arrived:
            guard !hasFiredArrival else { return }
            hasFiredArrival = true
            fireExchange(for: .arrival)
        case .idleTick:
            // Skip roughly half the idle ticks so chatter doesn't fire like
            // clockwork even at the "chatty" setting.
            if Bool.random() {
                fireExchange(for: .idleChatter)
            }
        case .advancedToStep:
            break // upcomingTurn already covered the comedic beat for this maneuver
        }
    }

    /// Personas who are unmuted *and* have recordings. A persona still waiting
    /// on clips is skipped rather than counted and then left silent — counting
    /// them would burn a slot in the exchange on nothing.
    private var availablePersonas: [VoicePersona] {
        VoicePersona.all.filter { !settings.isMuted($0) && $0.hasRecordedClips }
    }

    private func fireExchange(for category: BanterCategory) {
        let cooldown = settings.frequency.cooldown(for: category)
        if let last = lastFired[category], Date().timeIntervalSince(last) < cooldown {
            return
        }

        let activePersonas = availablePersonas
        guard !activePersonas.isEmpty else { return }

        let length = Int.random(in: settings.frequency.exchangeLength)
        guard length > 0 else { return }

        var requests: [SpeechRequest] = []
        for cursor in 0..<length {
            let persona = activePersonas[cursor % activePersonas.count]

            if let clip = BanterAudioBank.clip(persona: persona.id, category: category, excluding: recentClipNames) {
                recentClipNames.append(clip.resourceName)
                if recentClipNames.count > recentHistoryLimit {
                    recentClipNames.removeFirst()
                }
                requests.append(audioRequest(clip: clip, persona: persona))
            }
        }
        guard !requests.isEmpty else { return }
        lastFired[category] = Date()
        enqueue(requests)
    }

    /// The default way a plain left/right turn is spoken: the character calls
    /// it out from a recording instead of the flat navigation voice. Unlike
    /// `fireExchange` this ignores cooldowns — a turn isn't optional flavor,
    /// it's the thing the driver needs to hear.
    ///
    /// A recorded clip doesn't state the distance out loud, but
    /// `TurnBannerView` shows the real distance and instruction on screen the
    /// whole time, so that's covered regardless of what's spoken.
    ///
    /// Anything without a matching clip is left alone here on purpose:
    /// `canAnnounceManeuver` has already told `ContentView` to announce it in
    /// the plain voice, so returning without enqueuing anything is what makes
    /// that fallback correct rather than a dropped turn.
    private func announceManeuver(step: RouteStepInfo) {
        guard let direction = BanterAudioBank.direction(for: step.instructions) else { return }

        for persona in availablePersonas {
            guard let clip = BanterAudioBank.turnClip(
                persona: persona.id,
                direction: direction,
                excluding: recentTurnClipNames
            ) else { continue }
            recentTurnClipNames.append(clip.resourceName)
            if recentTurnClipNames.count > recentHistoryLimit {
                recentTurnClipNames.removeFirst()
            }
            enqueue([audioRequest(clip: clip, persona: persona)])
            return
        }
    }

    /// A request that plays a recorded clip. Nothing here needs to describe
    /// what is being said: the on-screen indicator is a waveform
    /// (`BanterWaveformView`), fed by the speech queue's playback meter rather
    /// than by any text this engine could supply.
    private func audioRequest(clip: BanterAudioBank.Clip, persona: VoicePersona) -> SpeechRequest {
        SpeechRequest(
            resourceName: clip.resourceName,
            fileExtension: clip.fileExtension,
            persona: persona,
            rateMultiplier: settings.speechRateMultiplier,
            onStart: nil,
            onFinish: nil
        )
    }

    private func enqueue(_ requests: [SpeechRequest]) {
        for request in requests {
            speechQueue.enqueueBanter(request)
        }
    }
}
