import Foundation

enum BanterCategory: String, CaseIterable, Codable, Hashable {
    case tripStart
    case upcomingTurn
    case rerouting
    case arrival
    case idleChatter
    /// Reserved for a future live-traffic trigger. Clips exist for it
    /// (BanterAudioBank) but nothing fires it yet — the app has no traffic
    /// data source to react to.
    case trafficComment
}

enum BanterFrequency: String, CaseIterable, Identifiable, Codable, Hashable {
    case off
    case occasional
    case chatty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .occasional: return "Occasional"
        case .chatty: return "Chatty"
        }
    }

    /// Minimum seconds before banter *of the same category* is allowed to
    /// fire again. tripStart and arrival ignore this — BanterEngine caps
    /// those to exactly once per trip regardless of frequency.
    func cooldown(for category: BanterCategory) -> TimeInterval {
        if self == .off { return .infinity }
        switch category {
        case .tripStart, .arrival:
            return .infinity
        case .idleChatter:
            return self == .chatty ? 3 * 60 : 8 * 60
        case .upcomingTurn:
            return self == .chatty ? 25 : 90
        case .rerouting:
            return self == .chatty ? 5 : 20
        case .trafficComment:
            return .infinity // not wired to a live trigger yet
        }
    }

    /// How many lines long a fired exchange is.
    var exchangeLength: ClosedRange<Int> {
        switch self {
        case .off: return 0...0
        case .occasional: return 1...2
        case .chatty: return 2...4
        }
    }
}

/// User-facing banter preferences. Backed by UserDefaults directly (rather
/// than @AppStorage) because it's shared with non-view types like
/// BanterEngine, not just SwiftUI views.
@MainActor
final class BanterSettings: ObservableObject {
    @Published var frequency: BanterFrequency {
        didSet { UserDefaults.standard.set(frequency.rawValue, forKey: Keys.frequency) }
    }
    @Published var mutedPersonaIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(mutedPersonaIDs), forKey: Keys.muted) }
    }
    @Published var speechRateMultiplier: Double {
        didSet { UserDefaults.standard.set(speechRateMultiplier, forKey: Keys.rate) }
    }
    /// Shows the on-screen `BanterWaveformView` while a character is talking.
    @Published var showWaveform: Bool {
        didSet { UserDefaults.standard.set(showWaveform, forKey: Keys.showWaveform) }
    }
    /// When on, turns are read out in the plain navigation voice like a
    /// normal maps app. When off (the default), a recorded character clip
    /// calls out the turn instead where one exists — see
    /// `BanterEngine.announceManeuver`.
    @Published var realDirectionsEnabled: Bool {
        didSet { UserDefaults.standard.set(realDirectionsEnabled, forKey: Keys.realDirections) }
    }

    private enum Keys {
        static let frequency = "banter.frequency"
        static let muted = "banter.mutedPersonaIDs"
        static let rate = "banter.speechRateMultiplier"
        static let showWaveform = "banter.showWaveform"
        static let realDirections = "banter.realDirectionsEnabled"
    }

    init() {
        let defaults = UserDefaults.standard
        frequency = BanterFrequency(rawValue: defaults.string(forKey: Keys.frequency) ?? "") ?? .occasional
        mutedPersonaIDs = Set(defaults.stringArray(forKey: Keys.muted) ?? [])
        speechRateMultiplier = defaults.object(forKey: Keys.rate) as? Double ?? 1.0
        showWaveform = defaults.object(forKey: Keys.showWaveform) as? Bool ?? true
        realDirectionsEnabled = defaults.object(forKey: Keys.realDirections) as? Bool ?? false
    }

    func isMuted(_ persona: VoicePersona) -> Bool {
        mutedPersonaIDs.contains(persona.id)
    }

    func toggleMute(_ persona: VoicePersona) {
        if mutedPersonaIDs.contains(persona.id) {
            mutedPersonaIDs.remove(persona.id)
        } else {
            mutedPersonaIDs.insert(persona.id)
        }
    }

    /// True whenever there's nobody available to deliver *any* turn as banter
    /// — the user asked for the plain voice, muted every character, turned
    /// banter off outright, or no character has recordings yet.
    ///
    /// This covers the settings-level cases only. Whether a *particular*
    /// maneuver has a recording that fits it is a separate question, answered
    /// per turn by `BanterEngine.canAnnounceManeuver`; both have to be
    /// consulted, since silence on a turn is never an option.
    var mustUseRealDirections: Bool {
        realDirectionsEnabled
            || frequency == .off
            || VoicePersona.all.allSatisfy { isMuted($0) || !$0.hasRecordedClips }
    }
}
