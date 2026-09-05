import Foundation

/// Content for turns delivered *as* banter — the default experience — rather
/// than in the plain navigation voice. See `BanterSettings.realDirections
/// Enabled` for the toggle back to the old flat delivery.
///
/// Dez states the actual instruction (the informative half; `{distance}` and
/// `{instruction}` are substituted at speak time) and Vale disagrees — but
/// only with Dez's dramatics, never with the maneuver itself. Two characters
/// giving conflicting *real* directions would just be dangerous, so Vale's
/// lines never contradict which way to actually go.
enum DirectionAnnouncementBank {
    static let dezAnnouncements: [String] = [
        "Okay. In {distance}, {instruction}. I need everyone to take this seriously.",
        "Coming up in {distance}: {instruction}. I've checked it twice. We're doing this.",
        "In {distance}, {instruction}. This is the part I've been dreading.",
        "Heads up. In {distance}, {instruction}. I'm just the messenger here.",
        "In {distance} — {instruction}. Please, no sudden movements.",
        "There it is. In {distance}, {instruction}. Don't make me say it twice.",
        "Okay okay okay, in {distance}, {instruction}. I've never been more sure of anything.",
        "In {distance}, {instruction}. I'm trusting the map with my whole life right now.",
    ]

    /// Vale's half of the exchange — the disagreement. Deliberately has no
    /// idea what the actual turn was; she's reacting to Dez, not to the road.
    static let valeRebuttals: [String] = [
        "Obviously. I called that one before we even left the driveway.",
        "Relax, Dez. I already knew. I always know.",
        "See, this is exactly why you let me handle the turns.",
        "Cute that you think announcing it makes you the hero here.",
        "You say that like it's news. I've known since we started.",
        "Dramatic much? It's a turn, Dez, not a plot twist.",
        "I was already turning before you finished that sentence.",
        "Wow, big reveal. I'm shaking.",
        "Noted, dramatized, and completely unnecessary. But go off.",
        "Somehow you make every single turn sound like the season finale.",
    ]

    /// Used only when Dez is muted, so Vale has to deliver the instruction
    /// herself rather than the exchange going silent.
    static let valeSoloAnnouncements: [String] = [
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
