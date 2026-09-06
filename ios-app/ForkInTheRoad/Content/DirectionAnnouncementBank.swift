import Foundation

/// Content for turns delivered *as* banter — the default experience — rather
/// than in the plain navigation voice. See `BanterSettings.realDirections
/// Enabled` for the toggle back to the old flat delivery.
///
/// This is the dynamic-template fallback used when no matching recorded clip
/// exists for the maneuver (see `BanterAudioBank.direction(for:)` — sharp
/// turns, roundabouts, merges, exits and u-turns all land here since only
/// plain left/right turns have clips). Dan states the actual instruction (the
/// informative half; `{distance}` and `{instruction}` are substituted at
/// speak time) and Harry disagrees — but only with Dan's dramatics, never
/// with the maneuver itself. Two characters giving conflicting *real*
/// directions would just be dangerous, so Harry's lines never contradict
/// which way to actually go.
enum DirectionAnnouncementBank {
    static let danAnnouncements: [String] = [
        "Okay. In {distance}, {instruction}. I need everyone to take this seriously.",
        "Coming up in {distance}: {instruction}. I've checked it twice. We're doing this.",
        "In {distance}, {instruction}. This is the part I've been dreading.",
        "Heads up. In {distance}, {instruction}. I'm just the messenger here.",
        "In {distance} — {instruction}. Please, no sudden movements.",
        "There it is. In {distance}, {instruction}. Don't make me say it twice.",
        "Okay okay okay, in {distance}, {instruction}. I've never been more sure of anything.",
        "In {distance}, {instruction}. I'm trusting the map with my whole life right now.",
    ]

    /// Harry's half of the exchange — the disagreement. Deliberately has no
    /// idea what the actual turn was; he's reacting to Dan, not to the road.
    static let harryRebuttals: [String] = [
        "Obviously. I called that one before we even left the driveway.",
        "Relax, Dan. I already knew. I always know.",
        "See, this is exactly why you let me handle the turns.",
        "Cute that you think announcing it makes you the hero here.",
        "You say that like it's news. I've known since we started.",
        "Dramatic much? It's a turn, Dan, not a plot twist.",
        "I was already turning before you finished that sentence.",
        "Wow, big reveal. I'm shaking.",
        "Noted, dramatized, and completely unnecessary. But go off.",
        "Somehow you make every single turn sound like the season finale.",
    ]

    /// Used only when Dan is muted, so Harry has to deliver the instruction
    /// himself rather than the exchange going silent.
    static let harrySoloAnnouncements: [String] = [
        "In {distance}, {instruction}. Obviously. I already knew that.",
        "Coming up in {distance}: {instruction}. Try to keep up.",
        "In {distance}, {instruction}. Was there ever any doubt?",
        "Heads up. In {distance}, {instruction}. I'm always right about this part.",
    ]

    static func fill(_ template: String, distance: String, instruction: String) -> String {
        template
            .replacingOccurrences(of: "{distance}", with: distance)
            .replacingOccurrences(of: "{instruction}", with: instruction)
    }
}
