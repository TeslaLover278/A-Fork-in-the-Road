import type { FastifyReply, FastifyRequest } from "fastify";
import { verifyAccessToken } from "../services/crypto.js";

declare module "fastify" {
  interface FastifyRequest {
    userId?: string;
  }
}

function bearerToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (!header) return null;
  const [scheme, token] = header.split(" ");
  if (!scheme || !token || scheme.toLowerCase() !== "bearer") return null;
  return token;
}

/**
 * Populates `request.userId` when a valid token is present, but never
 * rejects. Used on routes that work signed-out and merely behave better
 * signed in — banter is the main one, so a first-run user gets jokes
 * before they have ever seen an account screen.
 */
export async function optionalAuth(request: FastifyRequest): Promise<void> {
  const token = bearerToken(request);
  if (!token) return;
  const payload = verifyAccessToken(token);
  if (payload) request.userId = payload.sub;
}

/** Rejects anything without a valid, unexpired access token. */
export async function requireAuth(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  const token = bearerToken(request);
  if (!token) {
    return reply.code(401).send({ error: "unauthorized", message: "Missing bearer token." });
  }

  const payload = verifyAccessToken(token);
  if (!payload) {
    // Same response for malformed and expired: the client's move is
    // identical either way (refresh, then retry once).
    return reply.code(401).send({ error: "invalid_token", message: "Token is invalid or expired." });
  }

  request.userId = payload.sub;
}
