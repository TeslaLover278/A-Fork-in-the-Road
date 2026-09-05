import Foundation
import AVFoundation

/// A comedic voice persona. There is deliberately no behavioral/logic
/// difference between personas — they only differ in how they sound and
/// what lines they're assigned in BanterLineBank.
struct VoicePersona: Identifiable, Equatable {
    let id: String
    let displayName: String
    let tagline: String
    let rate: Float
    let pitchMultiplier: Float
    let preferredVoiceNames: [String]

    /// Best-effort match against whatever system voices are installed on
    /// this device; falls back to the default voice for the current
    /// language if none of the preferred names are present.
    func resolvedVoice() -> AVSpeechSynthesisVoice? {
        let available = AVSpeechSynthesisVoice.speechVoices()
        for name in preferredVoiceNames {
            if let match = available.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return match
            }
        }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    static let dez = VoicePersona(
        id: "dez",
        displayName: "Dez",
        tagline: "Dramatic. Paranoid. Convinced every trip is a near-death experience.",
        rate: AVSpeechUtteranceDefaultSpeechRate * 1.12,
        pitchMultiplier: 1.18,
        preferredVoiceNames: ["Fred", "Albert", "Bad News"]
    )

    static let vale = VoicePersona(
        id: "vale",
        displayName: "Vale",
        tagline: "Smug. Overconfident. Has never once been wrong, by her own account.",
        rate: AVSpeechUtteranceDefaultSpeechRate * 0.94,
        pitchMultiplier: 0.88,
        preferredVoiceNames: ["Samantha", "Karen", "Moira"]
    )

    static let all: [VoicePersona] = [.dez, .vale]
}
