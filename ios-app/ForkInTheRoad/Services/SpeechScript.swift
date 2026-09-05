import Foundation
import AVFoundation

/// One clause of a line, with the delivery settings it should be spoken at.
struct SpeechFragment: Equatable {
    let text: String
    let rate: Float
    let pitchMultiplier: Float
    let volume: Float
    let preUtteranceDelay: TimeInterval
    let postUtteranceDelay: TimeInterval
}

/// Turns a written line into a performance.
///
/// `AVSpeechUtterance` only carries one rate, one pitch and one volume for
/// the whole string, so a line handed over in one piece comes out at a single
/// flat setting from beginning to end. That flatness — not the voice itself —
/// is most of what makes on-device TTS sound lifeless.
///
/// So a line is cut into clauses at its punctuation, and each clause gets its
/// own settings and its own pause in front of it, derived from what the
/// punctuation means: a shout goes up (or, for a deadpan character, down and
/// slower), a question lifts, a trail-off falls away, pitch drifts down across
/// a long line the way real speech does, and the last clause gets a beat in
/// front of it so a punchline lands.
///
/// Deliberately pure and synchronous — the only Swift here that touches
/// AVFoundation is `utterances(for:persona:rateMultiplier:)` at the bottom.
enum SpeechScript {

    // MARK: - Parsing

    enum ClauseBreak: Equatable {
        /// , ; :
        case soft
        /// — – -
        case dash
        /// . !
        case sentence
        /// ?
        case question
        /// ... …
        case trailOff
        /// End of the line.
        case end

        /// Silence to leave after this clause, before scaling by the
        /// persona's `pauseScale`.
        var pause: TimeInterval {
            switch self {
            case .soft: return 0.10
            case .dash: return 0.22
            case .sentence, .question: return 0.26
            case .trailOff: return 0.42
            case .end: return 0
            }
        }
    }

    struct Clause: Equatable {
        var text: String
        var terminator: ClauseBreak
        /// The clause is being shouted — ALL CAPS somewhere in it, or a "!".
        var isShouted: Bool
    }

    /// Words that are upper-case because that is simply how they are
    /// written, not because anyone is shouting them. Without this they would
    /// be read as emphasis and get lower-cased, which can change how the
    /// synthesizer pronounces them.
    private static let acronyms: Set<String> = [
        "GPS", "US", "USA", "UK", "EU", "AM", "PM", "MPH", "KPH", "KM", "ETA",
        "OK", "TV", "DJ", "AI", "EV", "SUV", "DMV", "HOV", "AC", "CD", "ID",
    ]

    static func clauses(in text: String) -> [Clause] {
        var result: [Clause] = []
        var buffer = ""
        let characters = Array(text)
        var index = 0

        func flush(_ terminator: ClauseBreak) {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = ""
            guard !trimmed.isEmpty else { return }
            let (spoken, shouted) = softenShouts(in: trimmed)
            result.append(Clause(text: spoken, terminator: terminator, isShouted: shouted))
        }

        while index < characters.count {
            let character = characters[index]

            if ".!?…".contains(character) {
                // Consume the whole run so "?!" and "..." are read as one
                // terminator rather than as several empty clauses.
                var run = ""
                while index < characters.count, ".!?…".contains(characters[index]) {
                    run.append(characters[index])
                    index += 1
                }
                buffer.append(run)
                let isEllipsis = run.contains("…") || run.filter { $0 == "." }.count >= 3
                let terminator: ClauseBreak = isEllipsis ? .trailOff : (run.contains("?") ? .question : .sentence)
                let wasFlushedEmpty = buffer.trimmingCharacters(in: .whitespacesAndNewlines) == run
                flush(terminator)
                // A run that stood alone leaves a bare terminator as its own
                // clause; drop it rather than speaking punctuation.
                if wasFlushedEmpty, result.last?.text == run {
                    result.removeLast()
                }
                continue
            }

            if ",;:".contains(character) {
                buffer.append(character)
                index += 1
                flush(.soft)
                continue
            }

            if character == "—" || character == "–" {
                buffer.append(character)
                index += 1
                flush(.dash)
                continue
            }

            // A spaced hyphen is an aside; a hyphen inside a word is not.
            if character == "-", index > 0, characters[index - 1] == " ",
               index + 1 < characters.count, characters[index + 1] == " " {
                index += 1
                flush(.dash)
                continue
            }

            buffer.append(character)
            index += 1
        }

        flush(.end)
        return merged(result)
    }

    /// Folds a very short comma-clause into the one after it. Splitting
    /// "Relax, Dez." into two utterances puts an audible gap after one word
    /// and sounds stilted; the comma is still worth a beat inside a longer
    /// run, just not its own breath.
    private static func merged(_ clauses: [Clause]) -> [Clause] {
        var result: [Clause] = []
        for clause in clauses {
            if let previous = result.last,
               previous.terminator == .soft,
               !previous.isShouted,
               wordCount(previous.text) < 3 {
                result.removeLast()
                result.append(Clause(
                    text: previous.text + " " + clause.text,
                    terminator: clause.terminator,
                    isShouted: clause.isShouted
                ))
            } else {
                result.append(clause)
            }
        }
        return result
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " }).count
    }

    /// Lower-cases shouted words and reports that the clause was shouted, so
    /// the shout is carried by the delivery instead of by the spelling. Left
    /// as-is, a synthesizer may spell an all-caps word out letter by letter.
    private static func softenShouts(in text: String) -> (text: String, shouted: Bool) {
        var shouted = false
        let rewritten = text.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let letters = word.filter { $0.isLetter }
            guard letters.count >= 2, letters.allSatisfy({ $0.isUppercase }) else { return String(word) }
            guard !acronyms.contains(String(letters).uppercased()) else { return String(word) }
            shouted = true
            return word.lowercased()
        }
        return (rewritten.joined(separator: " "), shouted || text.contains("!"))
    }

    // MARK: - Performance

    /// Kept well inside the synthesizer's legal ranges. The extremes are not
    /// usable output — rate 0 is near-silence and pitch 2.0 is a chipmunk —
    /// and a persona plus a user rate slider plus per-clause modifiers can
    /// otherwise multiply their way out there.
    private static let rateRange: ClosedRange<Float> =
        (AVSpeechUtteranceDefaultSpeechRate * 0.55)...(AVSpeechUtteranceDefaultSpeechRate * 1.6)
    private static let pitchRange: ClosedRange<Float> = 0.7...1.6
    private static let volumeRange: ClosedRange<Float> = 0.2...1.0

    static func fragments(
        for text: String,
        style: VoiceStyle,
        rateMultiplier: Double
    ) -> [SpeechFragment] {
        let clauses = clauses(in: text)
        guard !clauses.isEmpty else { return [] }

        // One wobble per line, not per clause: a character should sound like
        // they are in a slightly different mood each time they speak, not
        // like they are changing mood mid-sentence.
        let pitchWobble = style.pitchJitter > 0 ? Float.random(in: -style.pitchJitter...style.pitchJitter) : 0
        let rateWobble = style.rateJitter > 0 ? Float.random(in: -style.rateJitter...style.rateJitter) : 0

        var fragments: [SpeechFragment] = []
        var pendingPause = style.openingPause

        for (index, clause) in clauses.enumerated() {
            let isLast = index == clauses.count - 1

            // Per-clause wobble sits on top of the per-line wobble: small
            // enough that the character stays in one mood, varied enough
            // that no two clauses land on the same note.
            let clausePitchWobble = style.clausePitchJitter > 0
                ? Float.random(in: -style.clausePitchJitter...style.clausePitchJitter) : 0
            let clauseRateWobble = style.clauseRateJitter > 0
                ? Float.random(in: -style.clauseRateJitter...style.clauseRateJitter) : 0

            var pitch = style.basePitch + pitchWobble + clausePitchWobble
                - style.declinationPerClause * Float(index)
            var rate = style.baseRate * (1 + rateWobble) * (1 + clauseRateWobble)
            var volume = style.baseVolume

            // The intake of energy at the start of a multi-clause line.
            if index == 0, clauses.count > 1 {
                pitch += style.onsetPitch
            }

            if clause.isShouted {
                pitch += style.emphasisPitch
                rate *= style.emphasisRate
                volume += style.emphasisVolume
            }

            switch clause.terminator {
            case .question:
                pitch += style.questionPitch
            case .trailOff, .dash:
                pitch += style.trailOffPitch
                rate *= style.trailOffRate
            case .soft, .sentence, .end:
                break
            }

            // The settle at the end of a thought — but not on a question or
            // a shout, which end up rather than down. The phrase also
            // lengthens: the last clause is spoken a touch slower.
            if isLast, !clause.isShouted, clause.terminator != .question {
                pitch += style.finalPitch
                rate *= style.finalRate
            }

            var preDelay = pendingPause
            if isLast, clauses.count > 1 {
                preDelay += style.punchlinePause
            }

            fragments.append(SpeechFragment(
                text: clause.text,
                rate: clamp(AVSpeechUtteranceDefaultSpeechRate * rate * Float(rateMultiplier), to: rateRange),
                pitchMultiplier: clamp(pitch, to: pitchRange),
                volume: clamp(volume, to: volumeRange),
                preUtteranceDelay: preDelay,
                postUtteranceDelay: isLast ? style.closingPause : 0
            ))

            let pauseWobble = style.pauseJitter > 0
                ? Double.random(in: -style.pauseJitter...style.pauseJitter) : 0
            pendingPause = clause.terminator.pause * style.pauseScale * (1 + pauseWobble)
        }

        return fragments
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// The whole performance, ready to hand to a synthesizer one at a time.
    @MainActor
    static func utterances(
        for text: String,
        persona: VoicePersona?,
        rateMultiplier: Double
    ) -> [AVSpeechUtterance] {
        let voice = persona?.resolvedVoice() ?? VoiceCatalog.shared.navigationVoice()
        let style = persona?.style ?? .neutral
        return fragments(for: text, style: style, rateMultiplier: rateMultiplier).map { fragment in
            let utterance = AVSpeechUtterance(string: fragment.text)
            utterance.voice = voice
            utterance.rate = fragment.rate
            utterance.pitchMultiplier = fragment.pitchMultiplier
            utterance.volume = fragment.volume
            utterance.preUtteranceDelay = fragment.preUtteranceDelay
            utterance.postUtteranceDelay = fragment.postUtteranceDelay
            return utterance
        }
    }
}
