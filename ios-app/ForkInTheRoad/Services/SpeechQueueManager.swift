import Foundation
import AVFoundation

enum SpeechLane: Equatable {
    case navigation
    case banter
}

struct SpeechRequest {
    let text: String
    let persona: VoicePersona?
    let rateMultiplier: Double
    let onStart: (() -> Void)?
    let onFinish: (() -> Void)?
}

/// Single owner of the AVSpeechSynthesizer so real turn-by-turn instructions
/// and comedic banter can never race to speak at once. This is the piece
/// that makes "banter never blocks or delays real directions" true:
///
/// - Navigation instructions always interrupt whatever is currently
///   speaking (including a banter line mid-sentence) and speak immediately.
/// - Banter only ever plays when the navigation lane is free, and is
///   dropped rather than queued if a nav instruction is about to speak.
///
/// The lane — not `synthesizer.isSpeaking` — is the gate. `speak()` is
/// asynchronous, so `isSpeaking` can still read `false` immediately after a
/// navigation utterance is handed to the synthesizer; gating on it would let
/// a banter line that was enqueued in the same runloop turn slip out on top
/// of the instruction.
@MainActor
final class SpeechQueueManager: NSObject, ObservableObject {
    @Published private(set) var isSpeakingBanter = false
    @Published private(set) var activePersonaID: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var banterQueue: [SpeechRequest] = []
    private var currentLane: SpeechLane?
    private var currentBanterFinishHandler: (() -> Void)?

    /// The utterance currently owning the navigation lane. Held by identity
    /// so the delegate callbacks can tell a finished/cancelled *navigation*
    /// utterance apart from a banter one — they share one synthesizer.
    private var navigationUtterance: AVSpeechUtterance?

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
        banterQueue.removeAll()
        currentBanterFinishHandler = nil
        isSpeakingBanter = false
        activePersonaID = nil
        currentLane = .navigation

        let utterance = AVSpeechUtterance(string: text)
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
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .word)
            }
            currentLane = nil
        }
        banterQueue.removeAll()
        currentBanterFinishHandler = nil
        isSpeakingBanter = false
        activePersonaID = nil
    }

    private func playNextBanterIfIdle() {
        // A held navigation lane blocks banter even before the synthesizer
        // reports itself as speaking; see the note on the class.
        guard currentLane == nil, !synthesizer.isSpeaking, !banterQueue.isEmpty else { return }
        let next = banterQueue.removeFirst()
        currentLane = .banter
        isSpeakingBanter = true
        activePersonaID = next.persona?.id
        currentBanterFinishHandler = next.onFinish
        next.onStart?()

        let utterance = AVSpeechUtterance(string: next.text)
        if let persona = next.persona {
            utterance.voice = persona.resolvedVoice()
            utterance.pitchMultiplier = persona.pitchMultiplier
            let rate = persona.rate * Float(next.rateMultiplier)
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, rate))
        }
        synthesizer.speak(utterance)
    }

    fileprivate func handleFinished(_ utterance: AVSpeechUtterance) {
        if utterance === navigationUtterance {
            // Releasing the navigation lane is what lets banter queued
            // alongside this instruction finally play.
            navigationUtterance = nil
            currentLane = nil
            playNextBanterIfIdle()
        } else if currentLane == .banter {
            currentBanterFinishHandler?()
            currentBanterFinishHandler = nil
            isSpeakingBanter = false
            activePersonaID = nil
            currentLane = nil
            playNextBanterIfIdle()
        }
    }

    fileprivate func handleCancelled(_ utterance: AVSpeechUtterance) {
        if utterance === navigationUtterance {
            navigationUtterance = nil
            currentLane = nil
            playNextBanterIfIdle()
            return
        }
        // A cancelled banter line. Don't clear the lane blindly: when
        // `speakNavigation` interrupts banter it has already claimed the
        // navigation lane by the time this callback lands, and clearing it
        // here would let the next banter line talk over the instruction.
        currentBanterFinishHandler = nil
        isSpeakingBanter = false
        activePersonaID = nil
        if currentLane == .banter {
            currentLane = nil
        }
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
