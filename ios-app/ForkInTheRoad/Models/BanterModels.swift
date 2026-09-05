import Foundation

enum BanterCategory: String, CaseIterable, Codable, Hashable {
    case tripStart
    case upcomingTurn
    case rerouting
    case arrival
    case idleChatter
}

struct BanterLine: Identifiable {
    let id = UUID()
    let personaID: String
    let category: BanterCategory
    let text: String
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
    @Published var showCaptions: Bool {
        didSet { UserDefaults.standard.set(showCaptions, forKey: Keys.showCaptions) }
    }

    private enum Keys {
        static let frequency = "banter.frequency"
        static let muted = "banter.mutedPersonaIDs"
        static let rate = "banter.speechRateMultiplier"
        static let showCaptions = "banter.showCaptions"
    }

    init() {
        let defaults = UserDefaults.standard
        frequency = BanterFrequency(rawValue: defaults.string(forKey: Keys.frequency) ?? "") ?? .occasional
        mutedPersonaIDs = Set(defaults.stringArray(forKey: Keys.muted) ?? [])
        speechRateMultiplier = defaults.object(forKey: Keys.rate) as? Double ?? 1.0
        showCaptions = defaults.object(forKey: Keys.showCaptions) as? Bool ?? true
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
}
