import { z } from "zod";
import { BANTER_CATEGORIES } from "./content/lineBank.js";
import { PERSONA_IDS } from "./content/personas.js";

/* ------------------------------------------------------------------ auth */

export const emailSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(3)
  .max(254)
  .email();

/**
 * Length-only, deliberately. Composition rules ("one symbol, one digit")
 * push people toward predictable passwords without measurably helping;
 * a 10-char floor plus scrypt is the better trade.
 */
export const passwordSchema = z.string().min(10).max(256);

export const registerSchema = z.object({
  email: emailSchema,
  password: passwordSchema,
  displayName: z.string().trim().min(1).max(80).optional(),
});

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1).max(256),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1).max(512),
});

export const updateMeSchema = z.object({
  displayName: z.string().trim().min(1).max(80).nullable().optional(),
});

/* ----------------------------------------------------------------- trips */

/**
 * `clientId` is the client's own identifier for the trip (a UUID it made
 * offline). It, not the server id, is the sync key — the client can create
 * trips with no network and reconcile later.
 */
export const tripInputSchema = z.object({
  clientId: z.string().trim().min(1).max(128),
  destinationName: z.string().trim().min(1).max(200),
  destinationLatitude: z.number().min(-90).max(90).nullable().optional(),
  destinationLongitude: z.number().min(-180).max(180).nullable().optional(),
  startedAt: z.number().int().nonnegative(),
  endedAt: z.number().int().nonnegative().nullable().optional(),
  distanceMeters: z.number().nonnegative().nullable().optional(),
  durationSeconds: z.number().nonnegative().nullable().optional(),
  rerouteCount: z.number().int().nonnegative().max(10_000).default(0),
  banterLineCount: z.number().int().nonnegative().max(100_000).default(0),
  /** Client-side last-modified time; drives last-write-wins on conflict. */
  updatedAt: z.number().int().nonnegative(),
  deleted: z.boolean().default(false),
});

export const syncSchema = z.object({
  /** Server revision the client last saw. Omit or 0 for a full pull. */
  since: z.number().int().nonnegative().default(0),
  trips: z.array(tripInputSchema).max(500).default([]),
  limit: z.number().int().positive().max(500).default(200),
});

export const listTripsQuerySchema = z.object({
  since: z.coerce.number().int().nonnegative().default(0),
  limit: z.coerce.number().int().positive().max(500).default(200),
  includeDeleted: z
    .union([z.boolean(), z.enum(["true", "false"])])
    .transform((v) => v === true || v === "true")
    .default(false),
});

/* ---------------------------------------------------------------- banter */

/**
 * Context is intentionally coarse and non-identifying: a place name and the
 * maneuver text the driver is already being shown, never a coordinate, a
 * heading, or a track. There is nothing here that reconstructs a route.
 */
export const banterContextSchema = z.object({
  destinationName: z.string().trim().max(200).optional(),
  maneuverInstruction: z.string().trim().max(300).optional(),
  roadName: z.string().trim().max(200).optional(),
  distanceMeters: z.number().nonnegative().max(5_000_000).optional(),
  etaSeconds: z.number().nonnegative().max(360_000).optional(),
  rerouteCount: z.number().int().nonnegative().max(10_000).optional(),
  timeOfDay: z.enum(["morning", "afternoon", "evening", "night"]).optional(),
  weather: z.string().trim().max(60).optional(),
});

export const banterRequestSchema = z.object({
  category: z.enum(BANTER_CATEGORIES),
  /** Unmuted personas, in speaking order. */
  personaIds: z
    .array(z.enum(PERSONA_IDS as [string, ...string[]]))
    .min(1)
    .max(8)
    .default([...PERSONA_IDS]),
  lineCount: z.number().int().min(1).max(4).default(2),
  context: banterContextSchema.default({}),
  /** Bank line ids recently played, so fallback doesn't repeat them. */
  excludeLineIds: z.array(z.string().max(128)).max(64).default([]),
  /** Set false to force the scripted bank (useful for A/B and for testing). */
  allowGenerated: z.boolean().default(true),
});

export type BanterRequest = z.infer<typeof banterRequestSchema>;
export type BanterContext = z.infer<typeof banterContextSchema>;
export type TripInput = z.infer<typeof tripInputSchema>;
