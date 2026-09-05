import Foundation
import CoreLocation

/// Decides *when* and *what* comedic banter fires. This is intentionally
/// dumb about routing — it only reacts to NavigationEvents it's handed and
/// pushes finished lines into SpeechQueueManager's low-priority banter lane,
/// which is what actually guarantees banter can't step on real directions.
///
/// Turns are the one exception to "just flavor": by default Dez and Vale
/// *are* how a turn gets spoken — see `announceManeuver` — with the plain
/// navigation voice only as a fallback (`BanterSettings.mustUseRealDirections`).
@MainActor
final class BanterEngine: ObservableObject {
    @Published private(set) var currentCaption: (personaID: String, text: String)?

    private let settings: BanterSettings
    private let speechQueue: SpeechQueueManager
    private let lineBank: BanterLineBank
    private let unitSettings: UnitSettings

    private var lastFired: [BanterCategory: Date] = [:]
    private var recentLineIDs: [UUID] = []
    private let recentHistoryLimit = 12
    private var hasFiredTripStart = false
    private var hasFiredArrival = false

    /// Avoid picking the same direction-announcement template twice in a row.
    private var lastDezAnnouncementIndex: Int?
    private var lastValeRebuttalIndex: Int?
    private var lastValeSoloAnnouncementIndex: Int?

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

        var lines: [BanterLine] = []
        for cursor in 0..<length {
            let persona = activePersonas[cursor % activePersonas.count]
            guard let line = lineBank.line(persona: persona.id, category: category, excluding: recentLineIDs) else { continue }
            lines.append(line)
            recentLineIDs.append(line.id)
            if recentLineIDs.count > recentHistoryLimit {
                recentLineIDs.removeFirst()
            }
        }
        guard !lines.isEmpty else { return }
        lastFired[category] = Date()
        enqueue(lines)
    }

    /// The default way a turn is spoken: Dez states the real instruction,
    /// then Vale disagrees with him — never with the turn itself, since two
    /// characters giving conflicting real directions would be dangerous, not
    /// funny. Unlike `fireExchange`, this always fires; a turn isn't optional
    /// flavor, it's the thing the driver needs to hear.
    private func announceManeuver(step: RouteStepInfo, distanceRemaining: CLLocationDistance) {
        let activePersonas = VoicePersona.all.filter { !settings.isMuted($0) }
        guard !activePersonas.isEmpty else { return }
        let hasDez = activePersonas.contains { $0.id == "dez" }
        let hasVale = activePersonas.contains { $0.id == "vale" }

        let distance = unitSettings.spokenDistance(distanceRemaining)
        var lines: [BanterLine] = []

        if hasDez {
            let template = DirectionAnnouncementBank.dezAnnouncements.pickAvoiding(&lastDezAnnouncementIndex)
            let text = DirectionAnnouncementBank.fill(template, distance: distance, instruction: step.instructions)
            lines.append(BanterLine(personaID: "dez", category: .upcomingTurn, text: text))

            if hasVale {
                let rebuttal = DirectionAnnouncementBank.valeRebuttals.pickAvoiding(&lastValeRebuttalIndex)
                lines.append(BanterLine(personaID: "vale", category: .upcomingTurn, text: rebuttal))
            }
        } else if hasVale {
            // Dez is muted — Vale has to deliver the actual instruction
            // herself rather than the turn going unspoken.
            let template = DirectionAnnouncementBank.valeSoloAnnouncements.pickAvoiding(&lastValeSoloAnnouncementIndex)
            let text = DirectionAnnouncementBank.fill(template, distance: distance, instruction: step.instructions)
            lines.append(BanterLine(personaID: "vale", category: .upcomingTurn, text: text))
        }

        guard !lines.isEmpty else { return }
        enqueue(lines)
    }

    private func enqueue(_ lines: [BanterLine]) {
        for line in lines {
            guard let persona = VoicePersona.all.first(where: { $0.id == line.personaID }) else { continue }
            let request = SpeechRequest(
                text: line.text,
                persona: persona,
                rateMultiplier: settings.speechRateMultiplier,
                onStart: { [weak self] in
                    self?.currentCaption = (persona.id, line.text)
                },
                onFinish: { [weak self] in
                    if self?.currentCaption?.text == line.text {
                        self?.currentCaption = nil
                    }
                }
            )
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
