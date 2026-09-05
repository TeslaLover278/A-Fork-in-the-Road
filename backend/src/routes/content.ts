import crypto from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { config } from "../config.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { PERSONAS, publicPersona } from "../content/personas.js";
import { BANTER_CATEGORIES, CONTENT_VERSION, LINE_BANK } from "../content/lineBank.js";

/**
 * Remote content delivery: personas and the joke bank ship from here rather
 * than from the app bundle, so new material is a deploy instead of an App
 * Store review. The client keeps its bundled copy as the offline default and
 * treats anything served here as an override.
 *
 * Payloads are computed once at boot — this content only changes on deploy,
 * so recomputing it (and its ETag) per request would be pure waste.
 */

const personasPayload = {
  version: CONTENT_VERSION,
  personas: PERSONAS.map(publicPersona),
};

const lineBankPayload = {
  version: CONTENT_VERSION,
  categories: BANTER_CATEGORIES,
  lines: LINE_BANK,
};

const manifestPayload = {
  version: CONTENT_VERSION,
  categories: BANTER_CATEGORIES,
  personaIds: PERSONAS.map((p) => p.id),
  lineCount: LINE_BANK.length,
  /** Whether generated banter is actually available, so the client can
   *  decide up front whether calling /v1/banter is worth a round trip. */
  generatedBanterAvailable: config.banter.enabled,
};

function etagFor(payload: unknown): string {
  return `"${crypto.createHash("sha256").update(JSON.stringify(payload)).digest("hex").slice(0, 32)}"`;
}

const etags = {
  personas: etagFor(personasPayload),
  lineBank: etagFor(lineBankPayload),
  manifest: etagFor(manifestPayload),
};

/**
 * Conditional GET. The line bank is the largest thing this API serves and
 * the least likely to change, so a client that polls it on launch should
 * almost always get a 304 and no body.
 */
function sendCacheable(request: FastifyRequest, reply: FastifyReply, etag: string, payload: unknown) {
  reply.header("ETag", etag);
  reply.header("Cache-Control", "public, max-age=300");

  if (request.headers["if-none-match"] === etag) {
    return reply.code(304).send();
  }
  return reply.send(payload);
}

export function registerContentRoutes(app: FastifyInstance): void {
  app.get("/v1/content/manifest", { preHandler: rateLimit("default") }, async (request, reply) =>
    sendCacheable(request, reply, etags.manifest, manifestPayload),
  );

  app.get("/v1/content/personas", { preHandler: rateLimit("default") }, async (request, reply) =>
    sendCacheable(request, reply, etags.personas, personasPayload),
  );

  app.get("/v1/content/line-bank", { preHandler: rateLimit("default") }, async (request, reply) =>
    sendCacheable(request, reply, etags.lineBank, lineBankPayload),
  );
}
