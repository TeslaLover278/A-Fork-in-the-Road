/**
 * The app's one hard guarantee is that banter never interferes with real
 * directions. On the client that is enforced structurally — SpeechQueueManager
 * owns the audio lane and turn instructions always pre-empt banter.
 *
 * Generated text needs the *content* half of that guarantee too: a joke that
 * happens to read like "take the next left" is dangerous in a way a scripted
 * bank line never was, because a human wrote every one of those. Anything a
 * model produces is checked here before it can reach a speaker in a moving car.
 */

/** Speech, not prose — long lines overrun the beat they were written for. */
export const MAX_LINE_LENGTH = 180;

/**
 * Phrasing that could be mistaken for a navigation instruction. Matches an
 * imperative directly followed by a direction or a road reference, which is
 * what an actual maneuver announcement sounds like. Commentary such as
 * "this turn looks tight" or "I hate this intersection" is unaffected.
 */
const NAVIGATION_IMPERATIVES = [
  /\b(turn|bear|veer|hang|keep|stay|merge|exit|head|proceed|continue|go|drive)\s+(left|right|north|south|east|west|straight)\b/i,
  /\b(take|use)\s+(the\s+)?(next|second|third|\d+(st|nd|rd|th)?)\s+(left|right|exit|ramp|turn)\b/i,
  /\b(make|do)\s+a\s+u[-\s]?turn\b/i,
  /\bin\s+\d+(\.\d+)?\s*(feet|foot|ft|yards?|miles?|mi|meters?|metres?|m|kilometers?|kilometres?|km)\b/i,
  /\b(exit|merge)\s+onto\b/i,
  /\bat\s+the\s+(roundabout|traffic\s+circle)\b/i,
  /\b(destination|arriv\w+)\s+(is\s+)?on\s+(the\s+)?(left|right)\b/i,
];

/**
 * A floor, not a ceiling — the model's own safety training and the persona
 * prompts do the real work. This catches the narrow case of something
 * genuinely unpleasant reaching a car speaker, where the cost of a false
 * negative is much higher than the cost of dropping one joke.
 */
const BLOCKED_TERMS = [
  "fuck", "shit", "bitch", "bastard", "cunt", "dick", "asshole", "piss",
  "slut", "whore", "retard", "faggot", "nigger", "kike", "spic", "chink",
  "kill yourself", "kys", "suicide", "rape",
];

/** Compiled once — screenLine runs on every generated line. */
const BLOCKED_PATTERNS = BLOCKED_TERMS.map((term) => new RegExp(`\\b${term}\\b`, "i"));

export type RejectionReason =
  | "empty"
  | "too_long"
  | "navigation_phrasing"
  | "blocked_term"
  | "meta_commentary";

/**
 * Signs the model answered *about* the task instead of performing it.
 *
 * These have to be narrow. A bare "starts with okay/sure" rule looks
 * reasonable and is wrong: Dan opens lines with "Okay." constantly, and it
 * silently rejected two shipped bank lines. Match the preamble *shape* — a
 * filler opener leading into an offer, or a line that names its own output —
 * not the filler word alone.
 */
const META_PATTERNS = [
  // "Sure! Here you go:" / "Okay, let me write..." — but not "Okay. Okay okay
  // okay." because the gap can't cross a sentence boundary.
  /^(sure|okay|certainly|of course|absolutely)\b[^.!?]{0,20}\b(here|i'?ll|let me|i can)\b/i,
  // Text that describes its own output rather than being it.
  /\bhere (are|is|'s)\b[^.!?]{0,40}\b(lines?|banter|exchange|options?|dialogue)\b/i,
  /\b(as an ai|language model|i cannot|i can't help with)\b/i,
  // Speaker labels — the persona is already carried structurally.
  /^(dan|harry)\s*:/i,
];

export function screenLine(text: string): { ok: true; text: string } | { ok: false; reason: RejectionReason } {
  const trimmed = text.trim().replace(/\s+/g, " ");

  if (trimmed.length === 0) return { ok: false, reason: "empty" };
  if (trimmed.length > MAX_LINE_LENGTH) return { ok: false, reason: "too_long" };

  // Word-boundary matched, so the "Scunthorpe problem" doesn't drop clean
  // lines. Terms are plain words by construction — nothing to escape.
  for (const pattern of BLOCKED_PATTERNS) {
    if (pattern.test(trimmed)) return { ok: false, reason: "blocked_term" };
  }

  for (const pattern of NAVIGATION_IMPERATIVES) {
    if (pattern.test(trimmed)) return { ok: false, reason: "navigation_phrasing" };
  }

  for (const pattern of META_PATTERNS) {
    if (pattern.test(trimmed)) return { ok: false, reason: "meta_commentary" };
  }

  return { ok: true, text: trimmed };
}
