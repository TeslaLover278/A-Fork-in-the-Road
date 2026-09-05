import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import { config } from "./config.js";
import { openDatabase, type DB } from "./db/index.js";
import { pruneBanterCache } from "./services/banter.js";
import { registerAuthRoutes } from "./routes/auth.js";
import { registerTripRoutes } from "./routes/trips.js";
import { registerBanterRoutes } from "./routes/banter.js";
import { registerContentRoutes } from "./routes/content.js";
import { CONTENT_VERSION } from "./content/lineBank.js";

export interface BuiltServer {
  app: FastifyInstance;
  db: DB;
}

export async function buildServer(db: DB = openDatabase()): Promise<BuiltServer> {
  const app = Fastify({
    logger: config.isTest ? false : { level: config.logLevel },
    // Behind a load balancer this is what makes request.ip the real client
    // rather than the proxy — rate limiting is keyed on it.
    trustProxy: true,
    bodyLimit: 256 * 1024,
  });

  await app.register(cors, {
    origin: config.corsOrigins,
    methods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "If-None-Match"],
    maxAge: 86_400,
  });

  app.setErrorHandler((error: FastifyError, request, reply) => {
    // Fastify surfaces client-side problems (malformed JSON, oversized body)
    // as 4xx — pass those through instead of masking them as server faults.
    const status = error.statusCode ?? 500;
    if (status >= 500) {
      request.log.error({ err: error }, "unhandled request error");
      return reply.code(500).send({ error: "internal_error", message: "Something went wrong." });
    }
    return reply.code(status).send({ error: error.code ?? "bad_request", message: error.message });
  });

  app.setNotFoundHandler((request, reply) => {
    reply.code(404).send({ error: "not_found", message: `No route for ${request.method} ${request.url}` });
  });

  app.get("/health", async () => ({
    status: "ok",
    contentVersion: CONTENT_VERSION,
    generatedBanterAvailable: config.banter.enabled,
    uptimeSeconds: Math.floor(process.uptime()),
  }));

  registerAuthRoutes(app, db);
  registerTripRoutes(app, db);
  registerBanterRoutes(app, db);
  registerContentRoutes(app);

  return { app, db };
}

/**
 * Housekeeping the app would otherwise never do: expired cache rows and dead
 * refresh tokens accumulate forever in a long-running process. Hourly is far
 * more often than needed at this scale, and costs a single indexed DELETE.
 */
export function startMaintenance(db: DB, intervalMs = 60 * 60 * 1000): NodeJS.Timeout {
  const timer = setInterval(() => {
    const now = Date.now();
    pruneBanterCache(db, now);
    db.prepare("DELETE FROM refresh_tokens WHERE expires_at <= ?").run(now);
  }, intervalMs);

  // Don't hold the event loop open purely for cleanup.
  timer.unref();
  return timer;
}
