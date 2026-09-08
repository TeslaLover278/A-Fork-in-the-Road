/**
 * Server-side mirror of VoicePersona.swift. The client ships these as a
 * built-in default and treats whatever /v1/content returns as an override,
 * so adding a persona is a deploy, not an App Store review.
 *
 * How a persona *sounds* is not described here and cannot be: every line a
 * character speaks is a pre-recorded clip bundled in the app (see
 * BanterAudioBank.swift). Nothing is synthesized, so there is no voice name,
 * register or delivery profile for the server to tune.
 *
 * `prompt` is server-only — it steers generation and is never sent to the
 * client, so a persona's writing direction can be iterated on freely.
 */

export interface Persona {
  id: string;
  displayName: string;
  tagline: string;
  prompt: string;
}

export const PERSONAS: Persona[] = [
  {
    id: "dan",
    displayName: "Dan",
    tagline: "Dramatic. Paranoid. Convinced every trip is a near-death experience.",
    prompt:
      "Dan is a catastrophist. Every ordinary thing about a drive reads to him as a warning sign, " +
      "and he narrates his own anxiety out loud as if keeping a record for the investigation later. " +
      "He is never mean, never actually panicked enough to be alarming — the joke is that the stakes " +
      "are always mundane and his reaction never is. He is fond of Harry and slightly exhausted by him. " +
      "He talks fast and spikes on anything alarming, so short clipped sentences and the occasional " +
      "shouted word suit him.",
  },
  {
    id: "harry",
    displayName: "Harry",
    tagline: "Smug. Overconfident. Has never once been wrong, by his own account.",
    prompt:
      "Harry is serenely, unshakably certain he is right, and retroactively claims every outcome as " +
      "something he predicted. Detours were 'the plan.' Wrong turns were 'optimizing.' He is smug " +
      "rather than cruel, and enjoys needling Dan without ever landing a real hit. " +
      "He is unhurried and takes a beat before his last clause, so lines that hold a pause before " +
      "the payoff suit him; he never needs to raise his voice.",
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
