import Foundation

/// Decides *when* and *what* comedic banter fires. This is intentionally
/// dumb about routing — it only reacts to NavigationEvents it's handed and
/// pushes finished lines into SpeechQueueManager's low-priority banter lane,
/// which is what actually guarantees banter can't step on real directions.
@MainActor
final class BanterEngine: ObservableObject {
    @Published private(set) var currentCaption: (personaID: String, text: String)?

    private let settings: BanterSettings
    private let speechQueue: SpeechQueueManager
    private let lineBank: BanterLineBank

    private var lastFired: [BanterCategory: Date] = [:]
    private var recentLineIDs: [UUID] = []
    private let recentHistoryLimit = 12
    private var hasFiredTripStart = false
    private var hasFiredArrival = false

    init(settings: BanterSettings, speechQueue: SpeechQueueManager, lineBank: BanterLineBank = .shared) {
        self.settings = settings
        self.speechQueue = speechQueue
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
        case .approachingManeuver:
            fireExchange(for: .upcomingTurn)
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
