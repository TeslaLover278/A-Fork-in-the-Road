import type { FastifyInstance } from "fastify";
import type { DB } from "../db/index.js";
import { optionalAuth } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { banterRequestSchema } from "../schemas.js";
import { getBanter } from "../services/banter.js";

export function registerBanterRoutes(app: FastifyInstance, db: DB): void {
  /**
   * Signed-out callers are allowed on purpose: banter is the app's whole
   * personality, and gating it behind an account would make a brand-new
   * install feel broken. Rate limiting falls back to IP for those.
   *
   * This route never returns a 5xx for a generation problem. Every failure
   * path — no key, timeout, refusal, filtered output — resolves to scripted
   * lines, because the client is mid-drive and an error it has to handle at
   * 60mph is worse than a joke it has heard before.
   */
  app.post("/v1/banter", { preHandler: [optionalAuth, rateLimit("banter")] }, async (request, reply) => {
    const parsed = banterRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", details: parsed.error.flatten() });
    }

    const result = await getBanter(parsed.data, { db, log: request.log });

    if (result.lines.length === 0) {
      // Only reachable if the requested personas have no bank content at all,
      // which means a content bug rather than a runtime failure.
      return reply.code(503).send({
        error: "no_banter_available",
        message: "No banter could be produced for that request.",
      });
    }

    return reply.send(result);
  });
}
