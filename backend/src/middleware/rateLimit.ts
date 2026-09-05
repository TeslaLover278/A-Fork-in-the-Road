import type { FastifyReply, FastifyRequest } from "fastify";
import { config } from "../config.js";

/**
 * Fixed-window counter, in process memory.
 *
 * Deliberately not Redis: one instance is the deployment shape this backend
 * targets, and the point here is to stop a runaway client from burning the
 * Anthropic budget, not to enforce a billing quota. If this ever runs on more
 * than one instance, swap the Map for a shared store — the interface below
 * is the only thing callers depend on.
 */
interface Window {
  count: number;
  resetAt: number;
}

const buckets = new Map<string, Window>();

/** Bounded sweep so an unbounded key space can't grow into a memory leak. */
function sweep(now: number): void {
  if (buckets.size < 10_000) return;
  for (const [key, window] of buckets) {
    if (window.resetAt <= now) buckets.delete(key);
  }
}

export interface RateLimitResult {
  allowed: boolean;
  limit: number;
  remaining: number;
  resetAt: number;
}

export function consume(key: string, limit: number, now: number = Date.now()): RateLimitResult {
  sweep(now);
  const windowMs = config.rateLimit.windowSeconds * 1000;
  const existing = buckets.get(key);

  if (!existing || existing.resetAt <= now) {
    const window = { count: 1, resetAt: now + windowMs };
    buckets.set(key, window);
    return { allowed: true, limit, remaining: limit - 1, resetAt: window.resetAt };
  }

  existing.count++;
  const remaining = Math.max(0, limit - existing.count);
  return { allowed: existing.count <= limit, limit, remaining, resetAt: existing.resetAt };
}

/** Test seam — the fixed window would otherwise leak state between cases. */
export function resetRateLimits(): void {
  buckets.clear();
}

/**
 * Keyed by user id when authenticated so a shared NAT or office Wi-Fi
 * doesn't make one user's usage throttle everyone behind the same IP.
 */
export function rateLimit(bucket: "banter" | "auth" | "default") {
  return async function rateLimitHook(request: FastifyRequest, reply: FastifyReply): Promise<void> {
    const limit = config.rateLimit[bucket];
    const identity = request.userId ?? request.ip;
    const result = consume(`${bucket}:${identity}`, limit);

    reply.header("RateLimit-Limit", String(result.limit));
    reply.header("RateLimit-Remaining", String(result.remaining));
    reply.header("RateLimit-Reset", String(Math.ceil((result.resetAt - Date.now()) / 1000)));

    if (!result.allowed) {
      reply.header("Retry-After", String(Math.ceil((result.resetAt - Date.now()) / 1000)));
      return reply.code(429).send({
        error: "rate_limited",
        message: "Too many requests. Slow down and try again shortly.",
      });
    }
  };
}
