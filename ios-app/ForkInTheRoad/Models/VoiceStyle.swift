import Foundation
import AVFoundation

/// How a persona *delivers* a line, as opposed to what they say.
///
/// AVSpeechSynthesizer only exposes rate/pitch/volume per utterance, so the
/// only way to get expression out of it is to break a line into clauses and
/// speak each one with its own settings (see `SpeechScript`). This struct is
/// the per-persona knob set that drives that: a baseline voice, plus how far
/// the delivery moves when a clause is shouted, asked, trailed off, or is
/// the punchline.
///
/// All pitch values are offsets applied to `basePitch`, all rate values are
/// multipliers applied to `baseRate`, and everything is clamped to the
/// synthesizer's legal ranges before it is used.
struct VoiceStyle: Equatable {
    /// Multiplier on `AVSpeechUtteranceDefaultSpeechRate`.
    var baseRate: Float
    /// Multiplier on the voice's natural pitch (synthesizer range 0.5...2.0).
    var basePitch: Float
    /// Resting volume. Kept under 1.0 so emphasis has somewhere to go.
    var baseVolume: Float

    /// A shouted clause (ALL CAPS, or one ending in "!").
    var emphasisPitch: Float
    var emphasisRate: Float
    var emphasisVolume: Float

    /// A clause ending in "?".
    var questionPitch: Float

    /// A clause trailing off into "..." or a dash.
    var trailOffPitch: Float
    var trailOffRate: Float

    /// Pitch shed on the last clause of a line — the settle at the end of a
    /// thought. Small for characters who never quite settle.
    var finalPitch: Float

    /// Pitch shed per clause as a line goes on. Real speech drifts downward
    /// across a sentence; a flat pitch is most of what makes TTS sound dead.
    var declinationPerClause: Float

    /// Multiplies every pause computed from punctuation.
    var pauseScale: Double
    /// Extra beat before the final clause of a multi-clause line, i.e. how
    /// long this character sits on a punchline.
    var punchlinePause: TimeInterval
    var openingPause: TimeInterval
    var closingPause: TimeInterval

    /// Per-line random wobble, so a character doesn't hit the exact same
    /// note every time they speak. Steady characters get very little.
    var pitchJitter: Float
    var rateJitter: Float

    /// Dez: fast, high, jittery. Rushes through clauses, spikes on anything
    /// alarming, and never really lands the end of a sentence.
    static let anxious = VoiceStyle(
        baseRate: 1.14,
        basePitch: 1.20,
        baseVolume: 0.90,
        emphasisPitch: 0.20,
        emphasisRate: 1.12,
        emphasisVolume: 0.10,
        questionPitch: 0.13,
        trailOffPitch: -0.10,
        trailOffRate: 0.86,
        finalPitch: -0.04,
        declinationPerClause: 0.02,
        pauseScale: 1.10,
        punchlinePause: 0.06,
        openingPause: 0.0,
        closingPause: 0.15,
        pitchJitter: 0.05,
        rateJitter: 0.05
    )

    /// Vale: slow, low, unbothered. Emphasis makes her go *quieter and
    /// slower* rather than louder — the deadpan read — and she takes a real
    /// beat before the last clause of anything.
    static let smug = VoiceStyle(
        baseRate: 0.90,
        basePitch: 0.86,
        baseVolume: 0.92,
        emphasisPitch: -0.05,
        emphasisRate: 0.88,
        emphasisVolume: 0.08,
        questionPitch: 0.06,
        trailOffPitch: -0.07,
        trailOffRate: 0.82,
        finalPitch: -0.10,
        declinationPerClause: 0.015,
        pauseScale: 1.35,
        punchlinePause: 0.28,
        openingPause: 0.10,
        closingPause: 0.25,
        pitchJitter: 0.02,
        rateJitter: 0.02
    )

    /// Flat, neutral delivery — used when something is spoken without a
    /// persona attached.
    static let neutral = VoiceStyle(
        baseRate: 1.0,
        basePitch: 1.0,
        baseVolume: 1.0,
        emphasisPitch: 0.06,
        emphasisRate: 1.0,
        emphasisVolume: 0.0,
        questionPitch: 0.05,
        trailOffPitch: -0.04,
        trailOffRate: 0.95,
        finalPitch: -0.04,
        declinationPerClause: 0.01,
        pauseScale: 1.0,
        punchlinePause: 0.0,
        openingPause: 0.0,
        closingPause: 0.0,
        pitchJitter: 0.0,
        rateJitter: 0.0
    )
}
