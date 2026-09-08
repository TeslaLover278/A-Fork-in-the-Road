import Foundation

/// A comedic voice persona. There is deliberately no behavioral/logic
/// difference between personas — they only differ in what they sound like,
/// which is entirely a function of the pre-recorded clips assigned to them in
/// `BanterAudioBank`.
///
/// A persona with no clips is silent rather than broken: nothing is
/// synthesized to cover for missing recordings, so `hasRecordedClips` is the
/// honest answer to "can this character actually say anything yet".
struct VoicePersona: Identifiable, Equatable {
    let id: String
    let displayName: String
    let tagline: String

    /// False for a persona whose recordings haven't been made yet. Such a
    /// persona stays listed in Settings — the roster is the plan — but can't
    /// contribute a line, and callers must not count on one from them.
    var hasRecordedClips: Bool {
        BanterAudioBank.hasAnyClips(persona: id)
    }

    // Placeholder tagline — Dan speaks entirely from the recorded clips in
    // BanterAudioBank. Update once Dan's actual personality is written.
    static let dan = VoicePersona(
        id: "dan",
        displayName: "Dan",
        tagline: "Dramatic. Paranoid. Convinced every trip is a near-death experience."
    )

    // Placeholder — Harry has no recorded clips yet, so he is listed but
    // silent. He starts speaking the moment clips for him land in
    // BanterAudioBank; nothing else has to change.
    static let harry = VoicePersona(
        id: "harry",
        displayName: "Harry",
        tagline: "Smug. Overconfident. Has never once been wrong, by his own account."
    )

    static let all: [VoicePersona] = [.dan, .harry]
}
