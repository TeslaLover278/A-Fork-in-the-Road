import Foundation

/// Fixed inventory of pre-recorded persona clips bundled with the app (see
/// `Resources/BanterAudio/<persona>/`). This is deliberately just data, same
/// spirit as `BanterLineBank`: a persona/category with no clips here isn't
/// broken, it just isn't covered yet — `BanterEngine` falls back to the
/// scripted text bank spoken through on-device TTS for anything missing.
enum BanterAudioBank {
    struct Clip {
        let personaID: String
        let category: BanterCategory
        /// Bundle resource name, without extension.
        let resourceName: String
        let fileExtension: String
    }

    /// Only the two directions we can reliably tell apart from MapKit's
    /// instruction string get their own clip — see `direction(for:)`. Every
    /// other maneuver keeps the dynamic-distance TTS announcement instead.
    enum TurnDirection {
        case left
        case right
    }

    private struct TurnClip {
        let personaID: String
        let direction: TurnDirection
        let resourceName: String
        let fileExtension: String
    }

    private static let clips: [Clip] = [
        .init(personaID: "dan", category: .tripStart, resourceName: "Dan-Start1", fileExtension: "mp3"),
        .init(personaID: "dan", category: .tripStart, resourceName: "Dan-Start2", fileExtension: "mp3"),
        .init(personaID: "dan", category: .tripStart, resourceName: "Dan-Start3", fileExtension: "mp3"),

        .init(personaID: "dan", category: .rerouting, resourceName: "Dan-Reroute1", fileExtension: "mp3"),
        .init(personaID: "dan", category: .rerouting, resourceName: "Dan-Reroute2", fileExtension: "mp3"),
        .init(personaID: "dan", category: .rerouting, resourceName: "Dan-Reroute3", fileExtension: "mp3"),

        .init(personaID: "dan", category: .arrival, resourceName: "Dan-Arrival1", fileExtension: "mp3"),
        .init(personaID: "dan", category: .arrival, resourceName: "Dan-Arrival2", fileExtension: "mp3"),

        .init(personaID: "dan", category: .idleChatter, resourceName: "Dan-Chatter1", fileExtension: "mp3"),
        .init(personaID: "dan", category: .idleChatter, resourceName: "Dan-Chatter2", fileExtension: "mp3"),
        .init(personaID: "dan", category: .idleChatter, resourceName: "Dan-Chatter3", fileExtension: "mp3"),
        .init(personaID: "dan", category: .idleChatter, resourceName: "Dan-Chatter4", fileExtension: "mp3"),
        .init(personaID: "dan", category: .idleChatter, resourceName: "Dan-Chatter5", fileExtension: "mp3"),
        .init(personaID: "dan", category: .idleChatter, resourceName: "Dan-Chatter6", fileExtension: "mp3"),

        // Not fired yet — see BanterCategory.trafficComment.
        .init(personaID: "dan", category: .trafficComment, resourceName: "Dan-Traffic1", fileExtension: "mp3"),
        .init(personaID: "dan", category: .trafficComment, resourceName: "Dan-Traffic2", fileExtension: "mp3"),
        .init(personaID: "dan", category: .trafficComment, resourceName: "Dan-Traffic3", fileExtension: "mp3"),
    ]

    private static let turnClips: [TurnClip] = [
        .init(personaID: "dan", direction: .left, resourceName: "Dan-LeftTurn1", fileExtension: "mp3"),
        .init(personaID: "dan", direction: .left, resourceName: "Dan-LeftTurn2", fileExtension: "mp3"),
        .init(personaID: "dan", direction: .right, resourceName: "Dan-RightTurn1", fileExtension: "mp3"),
    ]

    /// Picks a random clip for the given persona/category, avoiding recently
    /// used ones when possible — mirrors `BanterLineBank.line`.
    static func clip(persona: String, category: BanterCategory, excluding: [String]) -> Clip? {
        let candidates = clips.filter { $0.personaID == persona && $0.category == category }
        guard !candidates.isEmpty else { return nil }
        let fresh = candidates.filter { !excluding.contains($0.resourceName) }
        let pool = fresh.isEmpty ? candidates : fresh
        return pool.randomElement()
    }

    /// Picks a random turn clip for the given persona/direction, avoiding
    /// recently used ones when possible.
    static func turnClip(persona: String, direction: TurnDirection, excluding: [String]) -> Clip? {
        let candidates = turnClips.filter { $0.personaID == persona && $0.direction == direction }
        guard !candidates.isEmpty else { return nil }
        let fresh = candidates.filter { !excluding.contains($0.resourceName) }
        let pool = fresh.isEmpty ? candidates : fresh
        return pool.randomElement().map { Clip(personaID: $0.personaID, category: .upcomingTurn, resourceName: $0.resourceName, fileExtension: $0.fileExtension) }
    }

    /// Best-effort maneuver direction from MapKit's instruction string, for
    /// deciding whether a turn has a recorded clip at all. Mirrors the
    /// heuristic in `ManeuverIcon.symbolName`, but narrower: sharp/slight
    /// turns, roundabouts, merges, exits and u-turns return nil so they keep
    /// the dynamic-distance TTS announcement instead of a generic clip that
    /// can't describe them accurately.
    static func direction(for instructions: String) -> TurnDirection? {
        let text = instructions.lowercased()
        guard !text.contains("sharp"),
              !text.contains("slight"),
              !text.contains("roundabout"),
              !text.contains("merge"),
              !text.contains("exit"),
              !text.contains("ramp"),
              !text.contains("u-turn"),
              !text.contains("u turn") else { return nil }
        if text.contains("left") { return .left }
        if text.contains("right") { return .right }
        return nil
    }
}
