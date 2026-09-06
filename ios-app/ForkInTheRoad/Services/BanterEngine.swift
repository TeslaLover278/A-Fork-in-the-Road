import Foundation
import CoreLocation

/// Decides *when* and *what* comedic banter fires. This is intentionally
/// dumb about routing — it only reacts to NavigationEvents it's handed and
/// pushes finished lines into SpeechQueueManager's low-priority banter lane,
/// which is what actually guarantees banter can't step on real directions.
///
/// Turns are the one exception to "just flavor": by default Dan and Harry
/// *are* how a turn gets spoken — see `announceManeuver` — with the plain
/// navigation voice only as a fallback (`BanterSettings.mustUseRealDirections`).
///
/// Every category tries a recorded clip (`BanterAudioBank`) before falling
/// back to a scripted text line spoken through TTS — so a persona with no
/// clips yet (or a maneuver with no matching clip) still works exactly as it
/// did before clips existed.
@MainActor
final class BanterEngine: ObservableObject {
    @Published private(set) var currentCaption: (personaID: String, text: String)?

    private let settings: BanterSettings
    private let speechQueue: SpeechQueueManager
    private let lineBank: BanterLineBank
    private let unitSettings: UnitSettings

    private var lastFired: [BanterCategory: Date] = [:]
    private var recentLineIDs: [UUID] = []
    private var recentClipNames: [String] = []
    private let recentHistoryLimit = 12
    private var hasFiredTripStart = false
    private var hasFiredArrival = false

    /// Avoid picking the same direction-announcement template/clip twice in
    /// a row.
    private var lastDanAnnouncementIndex: Int?
    private var lastHarryRebuttalIndex: Int?
    private var lastHarrySoloAnnouncementIndex: Int?
    private var recentTurnClipNames: [String] = []

    init(settings: BanterSettings, speechQueue: SpeechQueueManager, unitSettings: UnitSettings, lineBank: BanterLineBank = .shared) {
        self.settings = settings
        self.speechQueue = speechQueue
        self.unitSettings = unitSettings
        self.lineBank = lineBank
    }

    /// Call when a new trip starts so the once-per-trip triggers (trip
    /// start, arrival) can fire again.
    func resetForNewTrip() {
        hasFiredTripStart = false
        hasFiredArrival = false
        lastFired.removeAll()
        recentLineIDs.removeAll()
        recentClipNames.removeAll()
        recentTurnClipNames.removeAll()
    }

    func handle(_ event: NavigationEvent) {
        guard settings.frequency != .off else { return }

        switch event {
        case .tripStarted:
            guard !hasFiredTripStart else { return }
            hasFiredTripStart = true
            fireExchange(for: .tripStart)
        case .approachingManeuver(let step, let distanceRemaining):
            guard !settings.mustUseRealDirections else { return } // real voice already covers this maneuver
            announceManeuver(step: step, distanceRemaining: distanceRemaining)
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

    private func fireExchange(for category: BanterCategory) {
        let cooldown = settings.frequency.cooldown(for: category)
        if let last = lastFired[category], Date().timeIntervalSince(last) < cooldown {
            return
        }

        let activePersonas = VoicePersona.all.filter { !settings.isMuted($0) }
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
            } else if let line = lineBank.line(persona: persona.id, category: category, excluding: recentLineIDs) {
                recentLineIDs.append(line.id)
                if recentLineIDs.count > recentHistoryLimit {
                    recentLineIDs.removeFirst()
                }
                requests.append(textRequest(text: line.text, persona: persona))
            }
        }
        guard !requests.isEmpty else { return }
        lastFired[category] = Date()
        enqueue(requests)
    }

    /// The default way a turn is spoken: Dan states the real instruction,
    /// then Harry disagrees with him — never with the turn itself, since two
    /// characters giving conflicting real directions would be dangerous, not
    /// funny. Unlike `fireExchange`, this always fires; a turn isn't optional
    /// flavor, it's the thing the driver needs to hear.
    ///
    /// A plain left/right turn prefers Dan's recorded clip for that
    /// direction — it doesn't state the distance out loud, but
    /// `TurnBannerView` already shows the real distance and instruction on
    /// screen the whole time, so that's covered regardless of what's spoken.
    /// Anything else (sharp turns, roundabouts, merges, exits, u-turns, or
    /// Dan having no clip) falls back to the dynamic-distance TTS template.
    private func announceManeuver(step: RouteStepInfo, distanceRemaining: CLLocationDistance) {
        let activePersonas = VoicePersona.all.filter { !settings.isMuted($0) }
        guard !activePersonas.isEmpty else { return }
        let hasDan = activePersonas.contains { $0.id == "dan" }
        let hasHarry = activePersonas.contains { $0.id == "harry" }

        var requests: [SpeechRequest] = []

        if hasDan, let direction = BanterAudioBank.direction(for: step.instructions),
           let clip = BanterAudioBank.turnClip(persona: "dan", direction: direction, excluding: recentTurnClipNames) {
            recentTurnClipNames.append(clip.resourceName)
            if recentTurnClipNames.count > recentHistoryLimit {
                recentTurnClipNames.removeFirst()
            }
            requests.append(audioRequest(clip: clip, persona: .dan))
            if hasHarry {
                requests.append(harryRebuttalRequest())
            }
        } else if hasDan {
            let distance = unitSettings.spokenDistance(distanceRemaining)
            let template = DirectionAnnouncementBank.danAnnouncements.pickAvoiding(&lastDanAnnouncementIndex)
            let text = DirectionAnnouncementBank.fill(template, distance: distance, instruction: step.instructions)
            requests.append(textRequest(text: text, persona: .dan))

            if hasHarry {
                requests.append(harryRebuttalRequest())
            }
        } else if hasHarry {
            // Dan is muted — Harry has to deliver the actual instruction
            // himself rather than the turn going unspoken.
            let distance = unitSettings.spokenDistance(distanceRemaining)
            let template = DirectionAnnouncementBank.harrySoloAnnouncements.pickAvoiding(&lastHarrySoloAnnouncementIndex)
            let text = DirectionAnnouncementBank.fill(template, distance: distance, instruction: step.instructions)
            requests.append(textRequest(text: text, persona: .harry))
        }

        guard !requests.isEmpty else { return }
        enqueue(requests)
    }

    private func harryRebuttalRequest() -> SpeechRequest {
        let rebuttal = DirectionAnnouncementBank.harryRebuttals.pickAvoiding(&lastHarryRebuttalIndex)
        return textRequest(text: rebuttal, persona: .harry)
    }

    /// A request that speaks scripted text through TTS, with the caption set
    /// to that same text.
    private func textRequest(text: String, persona: VoicePersona) -> SpeechRequest {
        SpeechRequest(
            content: .text(text),
            persona: persona,
            rateMultiplier: settings.speechRateMultiplier,
            onStart: { [weak self] in
                self?.currentCaption = (persona.id, text)
            },
            onFinish: { [weak self] in
                if self?.currentCaption?.text == text {
                    self?.currentCaption = nil
                }
            }
        )
    }

    /// A request that plays a recorded clip. There's no transcript for these
    /// yet, so no caption is shown while one plays.
    private func audioRequest(clip: BanterAudioBank.Clip, persona: VoicePersona) -> SpeechRequest {
        SpeechRequest(
            content: .audioClip(resourceName: clip.resourceName, fileExtension: clip.fileExtension),
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

private extension Array where Element == String {
    /// A random element, steering away from whichever index was picked last
    /// so a template doesn't repeat back-to-back on consecutive turns.
    func pickAvoiding(_ lastIndex: inout Int?) -> String {
        guard count > 1 else {
            lastIndex = indices.first
            return first ?? ""
        }
        var index = Int.random(in: indices)
        if index == lastIndex {
            index = (index + 1) % count
        }
        lastIndex = index
        return self[index]
    }
}
