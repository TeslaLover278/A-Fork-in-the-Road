import crypto from "node:crypto";
import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import { config } from "../config.js";
import type { DB } from "../db/index.js";
import { getPersona, type Persona } from "../content/personas.js";
import { pickBankLine, type BanterCategory } from "../content/lineBank.js";
import { screenLine } from "./banterFilter.js";
import type { BanterContext, BanterRequest } from "../schemas.js";

export interface BanterLine {
  personaId: string;
  text: string;
  /** Present only for scripted lines, so clients can de-duplicate them. */
  lineId?: string;
}

export type BanterSource = "generated" | "generated_cached" | "bank";

export interface BanterResult {
  source: BanterSource;
  lines: BanterLine[];
  /** Why generation was not used, when it wasn't. Diagnostic, never an error. */
  fallbackReason?: string;
}

/** Shape the model must return. Kept flat — it is easier to get right. */
const GeneratedBanter = z.object({
  lines: z
    .array(
      z.object({
        personaId: z.string().describe("Which persona speaks this line. Must be one of the provided persona ids."),
        text: z.string().describe("One spoken line of banter. Conversational, under 25 words, no stage directions."),
      }),
    )
    .describe("The exchange, in speaking order."),
});

let client: Anthropic | null = null;
function getClient(): Anthropic | null {
  if (!config.banter.enabled) return null;
  client ??= new Anthropic({
    apiKey: config.banter.apiKey,
    // A stale joke is worth nothing — the bank fallback is a better answer
    // than a retry that blows past the moment the line was written for.
    maxRetries: 0,
  });
  return client;
}

/* ------------------------------------------------------------- prompting */

const CATEGORY_BEATS: Record<BanterCategory, string> = {
  tripStart: "The drive has just begun. React to setting off.",
  upcomingTurn: "A turn is coming up shortly. React to the anticipation of it — never to how to perform it.",
  rerouting: "The route just changed, either because a turn was missed or a better route appeared.",
  arrival: "The car has arrived at the destination.",
  idleChatter: "Nothing is happening. It is a long, uneventful stretch of road.",
};

/**
 * Stable across every request so it stays a cacheable prefix — all the
 * per-trip variation goes in the user message instead.
 */
const SYSTEM_PROMPT = [
  "You write short comedic voice lines for two AI passengers in a turn-by-turn navigation app called Fork in the Road.",
  "",
  "They are passengers, not the navigator. The app speaks its own real driving directions in a separate voice; your lines play only in the gaps between them.",
  "",
  "Absolute rules:",
  "- Never give, restate, confirm, or contradict a driving instruction. Do not say which way to turn, which exit to take, how far anything is, or where the destination is. React to the drive as a passenger would; never direct it.",
  "- Never say anything that could be mistaken for the app's real navigation voice.",
  "- Keep each line under 25 words. These are spoken aloud in a moving car.",
  "- No stage directions, no emoji, no speaker labels, no narration of tone. Just the words said.",
  "- Keep it light and clean. No profanity, no insults with a real edge, nothing about crashes, injury, or death played straight.",
  "- The two personas needle each other; they never get genuinely mean.",
  "- Write fresh lines. Avoid the most obvious joke for the situation.",
].join("\n");

function buildUserPrompt(req: BanterRequest, personas: Persona[]): string {
  const parts: string[] = [];

  parts.push("Personas in this exchange:");
  for (const p of personas) {
    parts.push(`- id "${p.id}" (${p.displayName}): ${p.prompt}`);
  }

  parts.push("", `Moment: ${CATEGORY_BEATS[req.category]}`);

  const ctx = describeContext(req.context);
  if (ctx.length > 0) {
    parts.push("", "What is going on:", ...ctx.map((c) => `- ${c}`));
  }

  const first = personas[0]!;
  parts.push(
    "",
    `Write exactly ${req.lineCount} line${req.lineCount === 1 ? "" : "s"}, alternating between the personas in the order listed, starting with ${first.displayName}.`,
    "It should read as one continuous exchange, not as separate unrelated remarks.",
  );

  return parts.join("\n");
}

function describeContext(ctx: BanterContext): string[] {
  const out: string[] = [];
  if (ctx.destinationName) out.push(`Destination: ${ctx.destinationName}`);
  if (ctx.roadName) out.push(`Currently on: ${ctx.roadName}`);
  if (ctx.maneuverInstruction) {
    // Given only so the joke lands on the right kind of maneuver. The system
    // prompt forbids repeating it, and screenLine() enforces that afterwards.
    out.push(`Upcoming maneuver (context only — never repeat or paraphrase it): ${ctx.maneuverInstruction}`);
  }
  if (ctx.distanceMeters !== undefined) out.push(`Roughly ${describeDistance(ctx.distanceMeters)} of driving left`);
  if (ctx.etaSeconds !== undefined) out.push(`About ${Math.round(ctx.etaSeconds / 60)} minutes remaining`);
  if (ctx.rerouteCount) out.push(`The route has already changed ${ctx.rerouteCount} time(s) this trip`);
  if (ctx.timeOfDay) out.push(`Time of day: ${ctx.timeOfDay}`);
  if (ctx.weather) out.push(`Weather: ${ctx.weather}`);
  return out;
}

function describeDistance(meters: number): string {
  if (meters < 1000) return `${Math.round(meters / 100) * 100} meters`;
  return `${(meters / 1000).toFixed(1)} km`;
}

/* ----------------------------------------------------------------- cache */

/**
 * Buckets the request so near-identical moments share a cache entry — exact
 * distances would make every key unique and the cache useless. The key is a
 * hash, so no place name is ever stored in plaintext as a cache key.
 */
function cacheKey(req: BanterRequest): string {
  const ctx = req.context;
  const bucket = {
    category: req.category,
    personas: [...req.personaIds].sort(),
    lineCount: req.lineCount,
    destination: ctx.destinationName?.toLowerCase() ?? null,
    maneuver: maneuverKind(ctx.maneuverInstruction),
    distance: ctx.distanceMeters === undefined ? null : distanceBucket(ctx.distanceMeters),
    reroutes: ctx.rerouteCount === undefined ? null : Math.min(ctx.rerouteCount, 3),
    timeOfDay: ctx.timeOfDay ?? null,
    weather: ctx.weather?.toLowerCase() ?? null,
    model: config.banter.model,
  };
  return crypto.createHash("sha256").update(JSON.stringify(bucket)).digest("hex");
}

/** Mirrors ManeuverIcon.symbolName in NavigationModels.swift. */
function maneuverKind(instruction?: string): string | null {
  if (!instruction) return null;
  const t = instruction.toLowerCase();
  if (t.includes("arrive")) return "arrive";
  if (t.includes("u-turn") || t.includes("u turn")) return "uturn";
  if (t.includes("roundabout")) return "roundabout";
  if (t.includes("merge")) return "merge";
  if (t.includes("exit") || t.includes("ramp")) return "exit";
  if (t.includes("left")) return "left";
  if (t.includes("right")) return "right";
  return "straight";
}

function distanceBucket(meters: number): string {
  if (meters < 500) return "<500m";
  if (meters < 2000) return "<2km";
  if (meters < 10_000) return "<10km";
  if (meters < 50_000) return "<50km";
  return "50km+";
}

function readCache(db: DB, key: string, now: number): BanterLine[] | null {
  const row = db
    .prepare<[string, number], { payload: string }>(
      "SELECT payload FROM banter_cache WHERE cache_key = ? AND expires_at > ?",
    )
    .get(key, now);
  if (!row) return null;

  db.prepare("UPDATE banter_cache SET hits = hits + 1 WHERE cache_key = ?").run(key);
  try {
    return JSON.parse(row.payload) as BanterLine[];
  } catch {
    return null;
  }
}

function writeCache(db: DB, key: string, lines: BanterLine[], now: number): void {
  if (config.banter.cacheTtlSeconds === 0) return;
  db.prepare(
    `INSERT INTO banter_cache (cache_key, payload, created_at, expires_at)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(cache_key) DO UPDATE SET payload = excluded.payload, expires_at = excluded.expires_at`,
  ).run(key, JSON.stringify(lines), now, now + config.banter.cacheTtlSeconds * 1000);
}

export function pruneBanterCache(db: DB, now: number = Date.now()): number {
  return db.prepare("DELETE FROM banter_cache WHERE expires_at <= ?").run(now).changes;
}

/* ------------------------------------------------------------ generation */

export interface BanterLogger {
  warn: (obj: unknown, msg: string) => void;
  info: (obj: unknown, msg: string) => void;
}

export interface BanterDeps {
  db: DB;
  log?: BanterLogger;
}

export async function getBanter(req: BanterRequest, deps: BanterDeps): Promise<BanterResult> {
  const personas = req.personaIds
    .map((id) => getPersona(id))
    .filter((p): p is Persona => p !== undefined);

  if (personas.length === 0) {
    return { source: "bank", lines: [], fallbackReason: "no_known_personas" };
  }

  if (!req.allowGenerated) return fromBank(req, personas, "generation_not_requested");

  const anthropic = getClient();
  if (!anthropic) return fromBank(req, personas, "no_api_key");

  const now = Date.now();
  const key = cacheKey(req);
  const cached = readCache(deps.db, key, now);
  if (cached && cached.length > 0) {
    return { source: "generated_cached", lines: cached };
  }

  try {
    const response = await anthropic.messages.parse(
      {
        model: config.banter.model,
        // Room for adaptive thinking plus a handful of short lines. The
        // visible output is tiny; almost all of this headroom is thinking.
        max_tokens: 4096,
        // Low effort is the right trade here: the task is short, creative and
        // latency-bound, and a driver is waiting on the beat.
        output_config: { effort: config.banter.effort, format: zodOutputFormat(GeneratedBanter) },
        system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
        messages: [{ role: "user", content: buildUserPrompt(req, personas) }],
      },
      { timeout: config.banter.timeoutMs },
    );

    if (response.stop_reason === "refusal") {
      deps.log?.warn({ category: response.stop_details?.category }, "banter generation refused");
      return fromBank(req, personas, "refusal");
    }

    const parsed = response.parsed_output;
    if (!parsed) return fromBank(req, personas, "unparseable_response");

    const known = new Set(personas.map((p) => p.id));
    const accepted: BanterLine[] = [];
    let rejected = 0;

    for (const line of parsed.lines) {
      if (accepted.length === req.lineCount) break;
      if (!known.has(line.personaId)) {
        rejected++;
        continue;
      }
      const screened = screenLine(line.text);
      if (!screened.ok) {
        rejected++;
        deps.log?.warn({ reason: screened.reason }, "banter line rejected by filter");
        continue;
      }
      accepted.push({ personaId: line.personaId, text: screened.text });
    }

    if (accepted.length === 0) return fromBank(req, personas, "all_lines_filtered");

    const wasComplete = accepted.length === req.lineCount && rejected === 0;

    // A partial exchange still works — top it up from the bank so the beat
    // lands at the length the client's frequency setting asked for.
    if (accepted.length < req.lineCount) {
      const used = new Set(req.excludeLineIds);
      for (let i = accepted.length; i < req.lineCount; i++) {
        const persona = personas[i % personas.length]!;
        const line = pickBankLine(persona.id, req.category, used);
        if (!line) break;
        used.add(line.id);
        accepted.push({ personaId: line.personaId, text: line.text, lineId: line.id });
      }
    }

    // Only cache a fully-generated exchange. Caching a topped-up one would
    // pin a scripted line into the cache and repeat it far more than intended.
    if (wasComplete) {
      writeCache(deps.db, key, accepted, now);
    }

    return { source: "generated", lines: accepted };
  } catch (error) {
    const reason = classifyError(error);
    deps.log?.warn(
      { err: error instanceof Error ? error.message : String(error), reason },
      "banter generation failed",
    );
    return fromBank(req, personas, reason);
  }
}

function classifyError(error: unknown): string {
  if (error instanceof Anthropic.RateLimitError) return "rate_limited";
  if (error instanceof Anthropic.AuthenticationError) return "auth_failed";
  if (error instanceof Anthropic.APIConnectionTimeoutError) return "timeout";
  if (error instanceof Anthropic.APIConnectionError) return "connection_error";
  if (error instanceof Anthropic.BadRequestError) return "bad_request";
  if (error instanceof Anthropic.APIError) return `api_error_${error.status}`;
  return "unknown_error";
}

/**
 * The always-available answer. This is the same content the iOS client
 * already ships, so a total backend outage degrades the app to its offline
 * behaviour rather than to silence.
 */
function fromBank(req: BanterRequest, personas: Persona[], reason: string): BanterResult {
  const used = new Set(req.excludeLineIds);
  const lines: BanterLine[] = [];

  for (let i = 0; i < req.lineCount; i++) {
    const persona = personas[i % personas.length]!;
    const line = pickBankLine(persona.id, req.category, used);
    if (!line) continue;
    used.add(line.id);
    lines.push({ personaId: line.personaId, text: line.text, lineId: line.id });
  }

  return { source: "bank", lines, fallbackReason: reason };
}
