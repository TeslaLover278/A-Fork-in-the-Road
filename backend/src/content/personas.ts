/**
 * Server-side mirror of VoicePersona.swift. The client ships these as a
 * built-in default and treats whatever /v1/content returns as an override,
 * so tuning a voice or adding a persona is a deploy, not an App Store review.
 *
 * `prompt` is server-only — it steers generation and is never sent to the
 * client, so a persona's writing direction can be iterated on freely.
 */

/**
 * Mirror of VoiceStyle.swift — how a persona *delivers* a line, as opposed to
 * what they say. The client cuts each line into clauses and applies these per
 * clause, which is what keeps a line from being spoken at one flat setting
 * from beginning to end. Pitch values are offsets on `basePitch`, rate values
 * are multipliers on `baseRate`, pauses are seconds.
 */
export interface VoiceStyle {
  /** Multiplier on the platform's default speech rate. */
  baseRate: number;
  /** Multiplier on the voice's natural pitch. */
  basePitch: number;
  /** Kept under 1.0 so emphasis has somewhere to go. */
  baseVolume: number;
  /** Applied to a shouted clause — ALL CAPS, or one ending in "!". */
  emphasisPitch: number;
  emphasisRate: number;
  emphasisVolume: number;
  /** Applied to a clause ending in "?". */
  questionPitch: number;
  /** Applied to a clause trailing off into "..." or a dash. */
  trailOffPitch: number;
  trailOffRate: number;
  /** Shed on the last clause of a line — the settle at the end of a thought. */
  finalPitch: number;
  /** Shed per clause as a line goes on; real speech drifts downward. */
  declinationPerClause: number;
  /** Multiplies every pause derived from punctuation. */
  pauseScale: number;
  /** Extra beat before the final clause — how long this one sits on a punchline. */
  punchlinePause: number;
  openingPause: number;
  closingPause: number;
  /** Per-line random wobble, so a character doesn't hit the same note twice. */
  pitchJitter: number;
  rateJitter: number;
}

export interface Persona {
  id: string;
  displayName: string;
  tagline: string;
  style: VoiceStyle;
  /**
   * Preferred system voices, best first. iOS names only — a name that does
   * not exist on the platform silently costs the persona its character and
   * drops it onto the system default voice.
   */
  preferredVoiceNames: string[];
  /** Register to fall back to when none of the preferred names are installed. */
  preferredGender: "male" | "female" | "unspecified";
  /** Spoken by the client's voice preview button. */
  previewLine: string;
  prompt: string;
}

export const PERSONAS: Persona[] = [
  {
    id: "dez",
    displayName: "Dez",
    tagline: "Dramatic. Paranoid. Convinced every trip is a near-death experience.",
    style: {
      baseRate: 1.14,
      basePitch: 1.2,
      baseVolume: 0.9,
      emphasisPitch: 0.2,
      emphasisRate: 1.12,
      emphasisVolume: 0.1,
      questionPitch: 0.13,
      trailOffPitch: -0.1,
      trailOffRate: 0.86,
      finalPitch: -0.04,
      declinationPerClause: 0.02,
      pauseScale: 1.1,
      punchlinePause: 0.06,
      openingPause: 0,
      closingPause: 0.15,
      pitchJitter: 0.05,
      rateJitter: 0.05,
    },
    preferredVoiceNames: ["Tom", "Aaron", "Evan", "Alex", "Nathan", "Daniel"],
    preferredGender: "male",
    previewLine:
      "Okay. Okay okay okay. There's a turn coming up and I do NOT like the look of it.",
    prompt:
      "Dez is a catastrophist. Every ordinary thing about a drive reads to him as a warning sign, " +
      "and he narrates his own anxiety out loud as if keeping a record for the investigation later. " +
      "He is never mean, never actually panicked enough to be alarming — the joke is that the stakes " +
      "are always mundane and his reaction never is. He is fond of Vale and slightly exhausted by her. " +
      "He is spoken fast and high, and spikes on anything alarming, so short clipped sentences and " +
      "the occasional shouted word suit him.",
  },
  {
    id: "vale",
    displayName: "Vale",
    tagline: "Smug. Overconfident. Has never once been wrong, by her own account.",
    style: {
      baseRate: 0.9,
      basePitch: 0.86,
      baseVolume: 0.92,
      emphasisPitch: -0.05,
      emphasisRate: 0.88,
      emphasisVolume: 0.08,
      questionPitch: 0.06,
      trailOffPitch: -0.07,
      trailOffRate: 0.82,
      finalPitch: -0.1,
      declinationPerClause: 0.015,
      pauseScale: 1.35,
      punchlinePause: 0.28,
      openingPause: 0.1,
      closingPause: 0.25,
      pitchJitter: 0.02,
      rateJitter: 0.02,
    },
    preferredVoiceNames: ["Ava", "Zoe", "Samantha", "Allison", "Serena", "Karen", "Moira"],
    preferredGender: "female",
    previewLine:
      "Relax, Dez. I've driven this exact route in my head a thousand times... and I was right every single time.",
    prompt:
      "Vale is serenely, unshakably certain she is right, and retroactively claims every outcome as " +
      "something she predicted. Detours were 'the plan.' Wrong turns were 'optimizing.' She is smug " +
      "rather than cruel, and enjoys needling Dez without ever landing a real hit. " +
      "She is spoken slow and low and takes a beat before her last clause, so lines that hold a " +
      "pause before the payoff suit her; she never needs to raise her voice.",
  },
];

export const PERSONA_IDS = PERSONAS.map((p) => p.id);

export function getPersona(id: string): Persona | undefined {
  return PERSONAS.find((p) => p.id === id);
}

/** The client-facing shape — deliberately drops the generation `prompt`. */
export function publicPersona(p: Persona) {
  const { prompt: _prompt, ...rest } = p;
  return rest;
}
