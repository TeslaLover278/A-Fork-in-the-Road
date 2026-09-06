import Foundation
import AVFoundation

/// A comedic voice persona. There is deliberately no behavioral/logic
/// difference between personas — they only differ in how they sound, how
/// they deliver a line (`VoiceStyle`), and what lines they're assigned in
/// BanterLineBank.
struct VoicePersona: Identifiable, Equatable {
    let id: String
    let displayName: String
    let tagline: String
    let style: VoiceStyle
    /// Preferred system voices, best first. Only names that actually ship on
    /// iOS belong here — a name that doesn't exist silently costs the
    /// persona its character and drops it onto the system default voice.
    let preferredVoiceNames: [String]
    /// Used only when none of the preferred names are installed, to keep the
    /// fallback in the right register rather than whatever the device
    /// happens to default to.
    let preferredGender: AVSpeechSynthesisVoiceGender
    /// Spoken by the Settings preview button.
    let previewLine: String

    /// Best-effort match against whatever voices are installed on this
    /// device, preferring the highest-quality variant of the first
    /// preferred name that is present. See `VoiceCatalog`.
    @MainActor
    func resolvedVoice() -> AVSpeechSynthesisVoice? {
        VoiceCatalog.shared.voice(for: self)
    }

    // Placeholder tagline/preview/style — Dan now speaks primarily from the
    // recorded clips in BanterAudioBank, but the style/preview here still
    // back the TTS fallback path (maneuvers with no matching clip). Update
    // once Dan's actual personality is written.
    static let dan = VoicePersona(
        id: "dan",
        displayName: "Dan",
        tagline: "Dramatic. Paranoid. Convinced every trip is a near-death experience.",
        style: .anxious,
        preferredVoiceNames: ["Tom", "Aaron", "Evan", "Alex", "Nathan", "Daniel"],
        preferredGender: .male,
        previewLine: "Okay. Okay okay okay. There's a turn coming up and I do NOT like the look of it."
    )

    // Placeholder tagline/preview/style — Harry has no recorded clips yet, so
    // everything he says still goes through TTS using this. Update once
    // Harry's actual personality is written and/or clips exist.
    static let harry = VoicePersona(
        id: "harry",
        displayName: "Harry",
        tagline: "Smug. Overconfident. Has never once been wrong, by his own account.",
        style: .smug,
        // Deliberately a different list than Dan's — until Harry has his own
        // recorded clips, this is the only thing keeping the two voices from
        // sounding identical over TTS.
        preferredVoiceNames: ["Fred", "Rocko", "Jester", "Albert", "Arthur"],
        preferredGender: .male,
        previewLine: "Relax, Dan. I've driven this exact route in my head a thousand times... and I was right every single time."
    )

    static let all: [VoicePersona] = [.dan, .harry]
}

/// Picks the actual system voice behind each persona, and remembers it.
///
/// Two things here matter more than they look. First, a device usually has
/// several installed voices sharing one *name* — "Samantha" exists as
/// compact, enhanced, and premium — and `speechVoices()` does not return them
/// best-first. Matching on name alone therefore tends to land on the compact
/// variant, which is the flat, buzzy one people mean when they say the voices
/// sound bad. So we group by name and take the best quality available.
///
/// Second, some listed voices cannot actually be used by a third-party app:
/// Siri voices are reserved, and Personal Voice needs a separate
/// authorization we never request. Both have to be filtered out or they
/// resolve to something unusable and the synthesizer quietly substitutes a
/// default.
@MainActor
final class VoiceCatalog {
    static let shared = VoiceCatalog()

    private var cache: [String: AVSpeechSynthesisVoice] = [:]
    private var navigationVoiceCache: AVSpeechSynthesisVoice??

    private init() {}

    /// Drops the resolved-voice cache. Worth calling if the installed voices
    /// can change under the app — the user downloading an enhanced voice in
    /// iOS Settings while we are backgrounded.
    func invalidate() {
        cache.removeAll()
        navigationVoiceCache = nil
    }

    func voice(for persona: VoicePersona) -> AVSpeechSynthesisVoice? {
        if let cached = cache[persona.id] { return cached }
        guard let resolved = resolve(persona) else { return nil }
        cache[persona.id] = resolved
        return resolved
    }

    /// The voice for real turn-by-turn instructions. Deliberately whatever
    /// the system default is — directions should sound like the app, not
    /// like a third character — but upgraded to the best installed variant
    /// of that voice.
    func navigationVoice() -> AVSpeechSynthesisVoice? {
        if let cached = navigationVoiceCache { return cached }
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let systemDefault = AVSpeechSynthesisVoice(language: language)
        let resolved = systemDefault.flatMap { bestVariant(named: $0.name, in: usableVoices()) } ?? systemDefault
        navigationVoiceCache = .some(resolved)
        return resolved
    }

    /// The voice a persona actually ended up with, for display in Settings.
    func description(for persona: VoicePersona) -> String {
        guard let voice = voice(for: persona) else { return "System default" }
        switch voice.quality {
        case .premium: return "\(voice.name) · Premium"
        case .enhanced: return "\(voice.name) · Enhanced"
        default: return "\(voice.name) · Standard"
        }
    }

    /// True when every persona is stuck on a basic-quality voice. That is the
    /// case worth nudging the user about: the better variants are a free
    /// download in iOS Settings, and they are most of the difference.
    func allVoicesAreBasicQuality() -> Bool {
        VoicePersona.all.allSatisfy { persona in
            guard let voice = voice(for: persona) else { return true }
            return voice.quality.rawValue <= AVSpeechSynthesisVoiceQuality.default.rawValue
        }
    }

    private func resolve(_ persona: VoicePersona) -> AVSpeechSynthesisVoice? {
        let usable = usableVoices()

        // Preferred names in order, each at the best quality installed. Name
        // is ranked above quality on purpose: the persona's identity is the
        // point, and every name listed has a good variant available.
        for name in persona.preferredVoiceNames {
            if let match = bestVariant(named: name, in: usable) { return match }
        }

        // Nothing preferred is installed. Stay in the right register and take
        // the best-quality voice of the matching gender, preferring an exact
        // locale match over a same-language one.
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let genderMatches = usable.filter { $0.gender == persona.preferredGender }
        if let best = bestByQuality(genderMatches, exactLanguage: language) { return best }
        if let best = bestByQuality(usable, exactLanguage: language) { return best }
        return AVSpeechSynthesisVoice(language: language)
    }

    private func bestVariant(named name: String, in voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        let matches = voices.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return bestByQuality(matches, exactLanguage: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    private func bestByQuality(
        _ voices: [AVSpeechSynthesisVoice],
        exactLanguage: String
    ) -> AVSpeechSynthesisVoice? {
        voices.max { lhs, rhs in
            let lhsExact = lhs.language == exactLanguage
            let rhsExact = rhs.language == exactLanguage
            if lhsExact != rhsExact { return rhsExact }
            return lhs.quality.rawValue < rhs.quality.rawValue
        }
    }

    /// Installed voices this app is actually allowed to speak with, in the
    /// user's current language.
    private func usableVoices() -> [AVSpeechSynthesisVoice] {
        let languagePrefix = String(AVSpeechSynthesisVoice.currentLanguageCode().prefix(2))
        return AVSpeechSynthesisVoice.speechVoices().filter { voice in
            guard voice.language.hasPrefix(languagePrefix) else { return false }
            // Siri's voices are listed but reserved for the system.
            guard !voice.identifier.lowercased().contains("siri") else { return false }
            // Personal Voice needs an authorization request we never make.
            guard !voice.voiceTraits.contains(.isPersonalVoice) else { return false }
            return true
        }
    }
}
