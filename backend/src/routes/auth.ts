import type { FastifyInstance } from "fastify";
import { config } from "../config.js";
import type { DB } from "../db/index.js";
import {
  hashPassword,
  hashRefreshToken,
  newId,
  newRefreshToken,
  signAccessToken,
  verifyPassword,
} from "../services/crypto.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { requireAuth } from "../middleware/auth.js";
import { loginSchema, refreshSchema, registerSchema, updateMeSchema } from "../schemas.js";

interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  display_name: string | null;
  created_at: number;
  updated_at: number;
}

function publicUser(row: UserRow) {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    createdAt: row.created_at,
  };
}

function issueSession(db: DB, userId: string) {
  const access = signAccessToken(userId);
  const refresh = newRefreshToken();
  const now = Date.now();

  db.prepare(
    "INSERT INTO refresh_tokens (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
  ).run(refresh.hash, userId, now + config.auth.refreshTokenTtlSeconds * 1000, now);

  return {
    accessToken: access.token,
    accessTokenExpiresAt: access.expiresAt,
    refreshToken: refresh.token,
    refreshTokenExpiresAt: now + config.auth.refreshTokenTtlSeconds * 1000,
  };
}

export function registerAuthRoutes(app: FastifyInstance, db: DB): void {
  const findByEmail = db.prepare<[string], UserRow>("SELECT * FROM users WHERE email = ?");
  const findById = db.prepare<[string], UserRow>("SELECT * FROM users WHERE id = ?");

  app.post("/v1/auth/register", { preHandler: rateLimit("auth") }, async (request, reply) => {
    const parsed = registerSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", details: parsed.error.flatten() });
    }
    const { email, password, displayName } = parsed.data;

    if (findByEmail.get(email)) {
      // Registration inherently reveals whether an email is taken; there is
      // no way around that without an email-verification round trip, which
      // this app does not have. Login, where it *is* avoidable, does not leak.
      return reply.code(409).send({ error: "email_taken", message: "An account with that email already exists." });
    }

    const id = newId("usr");
    const now = Date.now();
    const passwordHash = await hashPassword(password);

    db.prepare(
      `INSERT INTO users (id, email, password_hash, display_name, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(id, email, passwordHash, displayName ?? null, now, now);

    const row = findById.get(id)!;
    return reply.code(201).send({ user: publicUser(row), ...issueSession(db, id) });
  });

  app.post("/v1/auth/login", { preHandler: rateLimit("auth") }, async (request, reply) => {
    const parsed = loginSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", details: parsed.error.flatten() });
    }
    const { email, password } = parsed.data;

    const row = findByEmail.get(email);

    // Hash even when the user doesn't exist, so response time doesn't
    // distinguish "no such account" from "wrong password".
    const stored = row?.password_hash ?? "scrypt$16384$8$1$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAA==";
    const valid = await verifyPassword(password, stored);

    if (!row || !valid) {
      return reply.code(401).send({ error: "invalid_credentials", message: "Email or password is incorrect." });
    }

    return reply.send({ user: publicUser(row), ...issueSession(db, row.id) });
  });

  app.post("/v1/auth/refresh", { preHandler: rateLimit("auth") }, async (request, reply) => {
    const parsed = refreshSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", details: parsed.error.flatten() });
    }

    const hash = hashRefreshToken(parsed.data.refreshToken);
    const now = Date.now();
    const row = db
      .prepare<[string], { user_id: string; expires_at: number; revoked_at: number | null }>(
        "SELECT user_id, expires_at, revoked_at FROM refresh_tokens WHERE token_hash = ?",
      )
      .get(hash);

    if (!row || row.revoked_at !== null || row.expires_at <= now) {
      return reply.code(401).send({ error: "invalid_token", message: "Refresh token is invalid or expired." });
    }

    // Rotate on every use: a stolen refresh token is good for one call, and
    // the legitimate client's next refresh fails loudly rather than silently
    // sharing a session with an attacker.
    db.prepare("UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ?").run(now, hash);

    const user = findById.get(row.user_id);
    if (!user) {
      return reply.code(401).send({ error: "invalid_token", message: "Account no longer exists." });
    }

    return reply.send({ user: publicUser(user), ...issueSession(db, row.user_id) });
  });

  app.post("/v1/auth/logout", { preHandler: rateLimit("auth") }, async (request, reply) => {
    const parsed = refreshSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", details: parsed.error.flatten() });
    }

    db.prepare("UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL").run(
      Date.now(),
      hashRefreshToken(parsed.data.refreshToken),
    );

    // 204 regardless of whether the token existed — logout should never be
    // a way to probe which tokens are live.
    return reply.code(204).send();
  });

  app.get("/v1/me", { preHandler: requireAuth }, async (request, reply) => {
    const row = findById.get(request.userId!);
    if (!row) return reply.code(404).send({ error: "not_found", message: "Account no longer exists." });
    return reply.send({ user: publicUser(row) });
  });

  app.patch("/v1/me", { preHandler: requireAuth }, async (request, reply) => {
    const parsed = updateMeSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", details: parsed.error.flatten() });
    }

    if (parsed.data.displayName !== undefined) {
      db.prepare("UPDATE users SET display_name = ?, updated_at = ? WHERE id = ?").run(
        parsed.data.displayName,
        Date.now(),
        request.userId!,
      );
    }

    const row = findById.get(request.userId!);
    if (!row) return reply.code(404).send({ error: "not_found", message: "Account no longer exists." });
    return reply.send({ user: publicUser(row) });
  });

  /**
   * Full account deletion. The App Store requires this for any app with
   * accounts, and the foreign keys cascade, so trips and sessions go with it.
   */
  app.delete("/v1/me", { preHandler: requireAuth }, async (request, reply) => {
    db.prepare("DELETE FROM users WHERE id = ?").run(request.userId!);
    return reply.code(204).send();
  });
}
