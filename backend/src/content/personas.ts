/**
 * Server-side mirror of VoicePersona.swift. The client ships these as a
 * built-in default and treats whatever /v1/content returns as an override,
 * so tuning a voice or adding a persona is a deploy, not an App Store review.
 *
 * `prompt` is server-only — it steers generation and is never sent to the
 * client, so a persona's writing direction can be iterated on freely.
 */
export interface Persona {
  id: string;
  displayName: string;
  tagline: string;
  /** AVSpeechUtteranceDefaultSpeechRate multiplier, matching the Swift model. */
  rateMultiplier: number;
  pitchMultiplier: number;
  preferredVoiceNames: string[];
  prompt: string;
}

export const PERSONAS: Persona[] = [
  {
    id: "dez",
    displayName: "Dez",
    tagline: "Dramatic. Paranoid. Convinced every trip is a near-death experience.",
    rateMultiplier: 1.12,
    pitchMultiplier: 1.18,
    preferredVoiceNames: ["Fred", "Albert", "Bad News"],
    prompt:
      "Dez is a catastrophist. Every ordinary thing about a drive reads to him as a warning sign, " +
      "and he narrates his own anxiety out loud as if keeping a record for the investigation later. " +
      "He is never mean, never actually panicked enough to be alarming — the joke is that the stakes " +
      "are always mundane and his reaction never is. He is fond of Vale and slightly exhausted by her.",
  },
  {
    id: "vale",
    displayName: "Vale",
    tagline: "Smug. Overconfident. Has never once been wrong, by her own account.",
    rateMultiplier: 0.94,
    pitchMultiplier: 0.88,
    preferredVoiceNames: ["Samantha", "Karen", "Moira"],
    prompt:
      "Vale is serenely, unshakably certain she is right, and retroactively claims every outcome as " +
      "something she predicted. Detours were 'the plan.' Wrong turns were 'optimizing.' She is smug " +
      "rather than cruel, and enjoys needling Dez without ever landing a real hit.",
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
