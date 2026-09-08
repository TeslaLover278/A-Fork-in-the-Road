import Foundation
import AVFoundation

enum SpeechLane: Equatable {
    case navigation
    case banter
}

struct SpeechRequest {
    /// Bundle resource name of the recording to play, without extension.
    let resourceName: String
    let fileExtension: String
    let persona: VoicePersona?
    let rateMultiplier: Double
    let onStart: (() -> Void)?
    let onFinish: (() -> Void)?
}

/// Single owner of both audio outputs — the banter clip player and the
/// navigation synthesizer — so real turn-by-turn instructions and comedic
/// banter can never race to speak at once. This is the piece that makes
/// "banter never blocks or delays real directions" true:
///
/// - Navigation instructions always interrupt whatever is currently
///   playing (including a banter clip mid-sentence) and speak immediately.
/// - Banter only ever plays when the navigation lane is free, and is
///   dropped rather than queued if a nav instruction is about to speak.
///
/// The lane — not `synthesizer.isSpeaking` — is the gate. `speak()` is
/// asynchronous, so `isSpeaking` can still read `false` immediately after a
/// navigation utterance is handed to the synthesizer; gating on it would let
/// a banter clip that was enqueued in the same runloop turn slip out on top
/// of the instruction.
///
/// Every persona line is a pre-recorded clip played through `AVAudioPlayer`,
/// with its performance already baked in. The synthesizer here is used for
/// exactly one thing: the plain navigation voice, which has to read out
/// street names and distances no fixed recording could cover.
@MainActor
final class SpeechQueueManager: NSObject, ObservableObject {
    @Published private(set) var isSpeakingBanter = false
    @Published private(set) var activePersonaID: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var banterQueue: [SpeechRequest] = []
    private var currentLane: SpeechLane?
    private var currentBanterFinishHandler: (() -> Void)?

    /// The player for the banter clip currently playing. Held only while one
    /// actually is.
    private var audioPlayer: AVAudioPlayer?

    /// The utterance currently owning the navigation lane, held by identity so
    /// the delegate callbacks can tell it apart from a stale one.
    private var navigationUtterance: AVSpeechUtterance?

    /// Resolved lazily and cached, since `speechVoices()` is not cheap and the
    /// answer only changes when the user installs a voice. See
    /// `invalidateNavigationVoice`.
    private var navigationVoiceCache: AVSpeechSynthesisVoice??

    override init() {
        super.init()
        configureAudioSession()
        synthesizer.delegate = self
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
    }

    /// Speak a real navigation instruction right now, cutting off any
    /// in-progress or queued banter to do it.
    func speakNavigation(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil
        banterQueue.removeAll()
        currentBanterFinishHandler = nil
        isSpeakingBanter = false
        activePersonaID = nil
        currentLane = .navigation

        // Instructions get no persona and no expression — they are the part
        // that has to be understood the first time — but they do get the
        // best-quality variant of the system voice.
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = navigationVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        navigationUtterance = utterance
        synthesizer.speak(utterance)
    }

    /// Queue a comedic line. It only actually plays once the navigation lane
    /// is free, and a navigation instruction will always preempt it.
    ///
    /// Callers routinely enqueue banter for the same event that just
    /// triggered an instruction (see `ContentView.handle`), so the line sits
    /// in the queue until the instruction finishes rather than being lost.
    func enqueueBanter(_ request: SpeechRequest) {
        banterQueue.append(request)
        playNextBanterIfIdle()
    }

    func stopAllBanter() {
        if currentLane == .banter {
            if let player = audioPlayer, player.isPlaying {
                player.stop()
            }
            currentLane = nil
        }
        audioPlayer = nil
        banterQueue.removeAll()
        currentBanterFinishHandler = nil
        isSpeakingBanter = false
        activePersonaID = nil
    }

    /// Drops the cached navigation voice. Worth calling if the installed
    /// voices can change under the app — the user downloading an enhanced
    /// voice in iOS Settings while we are backgrounded.
    func invalidateNavigationVoice() {
        navigationVoiceCache = nil
    }

    private func playNextBanterIfIdle() {
        // A held navigation lane blocks banter even before the synthesizer
        // reports itself as speaking; see the note on the class.
        guard currentLane == nil, !synthesizer.isSpeaking, !banterQueue.isEmpty else { return }
        let next = banterQueue.removeFirst()
        play(next)
    }

    /// A missing or unloadable recording is reported as finished and skipped,
    /// rather than stalling the queue on a file that was never bundled.
    private func play(_ request: SpeechRequest) {
        guard let url = Bundle.main.url(forResource: request.resourceName, withExtension: request.fileExtension),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            request.onFinish?()
            playNextBanterIfIdle()
            return
        }

        currentLane = .banter
        isSpeakingBanter = true
        activePersonaID = request.persona?.id
        currentBanterFinishHandler = request.onFinish
        request.onStart?()

        player.delegate = self
        player.enableRate = true
        player.rate = min(2.0, max(0.5, Float(request.rateMultiplier)))
        audioPlayer = player
        player.play()
    }

    /// The voice for real turn-by-turn instructions. Deliberately whatever
    /// the system default is — directions should sound like the app, not like
    /// a third character — but upgraded to the best installed variant of that
    /// voice, since a device usually has several sharing one name (compact,
    /// enhanced, premium) and `speechVoices()` does not return them best
    /// first.
    private func navigationVoice() -> AVSpeechSynthesisVoice? {
        if let cached = navigationVoiceCache { return cached }
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let systemDefault = AVSpeechSynthesisVoice(language: language)
        let resolved = systemDefault.flatMap { bestVariant(named: $0.name, language: language) } ?? systemDefault
        navigationVoiceCache = .some(resolved)
        return resolved
    }

    /// The highest-quality installed voice sharing `name`, preferring an exact
    /// locale match over a same-language one. Siri's voices are listed but
    /// reserved for the system, and Personal Voice needs an authorization we
    /// never request — both resolve to something unusable, so both are
    /// filtered out.
    private func bestVariant(named name: String, language: String) -> AVSpeechSynthesisVoice? {
        let languagePrefix = String(language.prefix(2))
        let matches = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            guard voice.language.hasPrefix(languagePrefix) else { return false }
            guard voice.name.caseInsensitiveCompare(name) == .orderedSame else { return false }
            guard !voice.identifier.lowercased().contains("siri") else { return false }
            guard !voice.voiceTraits.contains(.isPersonalVoice) else { return false }
            return true
        }
        return matches.max { lhs, rhs in
            let lhsExact = lhs.language == language
            let rhsExact = rhs.language == language
            if lhsExact != rhsExact { return rhsExact }
            return lhs.quality.rawValue < rhs.quality.rawValue
        }
    }

    fileprivate func handleFinished(_ utterance: AVSpeechUtterance) {
        guard utterance === navigationUtterance else { return }
        // Releasing the navigation lane is what lets banter queued alongside
        // this instruction finally play.
        navigationUtterance = nil
        currentLane = nil
        playNextBanterIfIdle()
    }

    fileprivate func handleCancelled(_ utterance: AVSpeechUtterance) {
        guard utterance === navigationUtterance else { return }
        navigationUtterance = nil
        currentLane = nil
        playNextBanterIfIdle()
    }

    /// A clip finishing naturally. `stop()` from `speakNavigation`/
    /// `stopAllBanter` does not trigger this delegate callback, so unlike a
    /// cancelled utterance this path only ever sees a completed line.
    fileprivate func handleAudioClipFinished() {
        audioPlayer = nil
        guard currentLane == .banter else { return }
        currentBanterFinishHandler?()
        currentBanterFinishHandler = nil
        isSpeakingBanter = false
        activePersonaID = nil
        currentLane = nil
        playNextBanterIfIdle()
    }
}

extension SpeechQueueManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.handleFinished(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.handleCancelled(utterance) }
    }
}

extension SpeechQueueManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.handleAudioClipFinished() }
    }
}
