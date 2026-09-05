import crypto from "node:crypto";
import { config } from "../config.js";

/* ------------------------------------------------------------------ ids */

export function newId(prefix: string): string {
  return `${prefix}_${crypto.randomBytes(16).toString("hex")}`;
}

/* ------------------------------------------------------------ passwords */

const SCRYPT_KEYLEN = 64;
const SCRYPT_PARAMS = { N: 16384, r: 8, p: 1 } as const;

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.randomBytes(16);
  const derived = await scrypt(password, salt);
  return `scrypt$${SCRYPT_PARAMS.N}$${SCRYPT_PARAMS.r}$${SCRYPT_PARAMS.p}$${salt.toString("base64")}$${derived.toString("base64")}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parts = stored.split("$");
  if (parts.length !== 6 || parts[0] !== "scrypt") return false;
  const [, n, r, p, saltB64, hashB64] = parts as [string, string, string, string, string, string];

  const salt = Buffer.from(saltB64, "base64");
  const expected = Buffer.from(hashB64, "base64");
  const derived = await scrypt(password, salt, {
    N: Number(n),
    r: Number(r),
    p: Number(p),
    keylen: expected.length,
  });

  // Lengths must match before timingSafeEqual — it throws on a mismatch.
  if (derived.length !== expected.length) return false;
  return crypto.timingSafeEqual(derived, expected);
}

function scrypt(
  password: string,
  salt: Buffer,
  opts: { N: number; r: number; p: number; keylen: number } = { ...SCRYPT_PARAMS, keylen: SCRYPT_KEYLEN },
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    crypto.scrypt(
      password.normalize("NFKC"),
      salt,
      opts.keylen,
      // scrypt's default 32MB memory cap is below what N=16384,r=8 needs.
      { N: opts.N, r: opts.r, p: opts.p, maxmem: 256 * 1024 * 1024 },
      (err, derived) => (err ? reject(err) : resolve(derived)),
    );
  });
}

/* --------------------------------------------------------- access tokens */

export interface AccessTokenPayload {
  sub: string;
  iat: number;
  exp: number;
}

/**
 * Compact HMAC-signed token (a JWT in shape, without dragging in a JWT
 * library for one algorithm we control both ends of). Stateless by design:
 * verifying costs no database round trip. Revocation lives on the refresh
 * token instead, which is why access tokens are short-lived.
 */
export function signAccessToken(userId: string, now: number = Date.now()): { token: string; expiresAt: number } {
  const issuedAt = Math.floor(now / 1000);
  const expiresAt = issuedAt + config.auth.accessTokenTtlSeconds;
  const payload: AccessTokenPayload = { sub: userId, iat: issuedAt, exp: expiresAt };

  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = b64url(JSON.stringify(payload));
  const signature = sign(`${header}.${body}`);

  return { token: `${header}.${body}.${signature}`, expiresAt: expiresAt * 1000 };
}

export function verifyAccessToken(token: string, now: number = Date.now()): AccessTokenPayload | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [header, body, signature] = parts as [string, string, string];

  const expected = sign(`${header}.${body}`);
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  let payload: AccessTokenPayload;
  try {
    payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    return null;
  }

  if (typeof payload.sub !== "string" || typeof payload.exp !== "number") return null;
  if (payload.exp * 1000 <= now) return null;
  return payload;
}

function sign(input: string): string {
  return crypto.createHmac("sha256", config.auth.secret).update(input).digest("base64url");
}

function b64url(input: string): string {
  return Buffer.from(input, "utf8").toString("base64url");
}

/* -------------------------------------------------------- refresh tokens */

/**
 * Opaque and random — there is nothing to parse, so nothing to forge. Only
 * the SHA-256 hash is stored, so a database leak doesn't hand out sessions.
 */
export function newRefreshToken(): { token: string; hash: string } {
  const token = crypto.randomBytes(48).toString("base64url");
  return { token, hash: hashRefreshToken(token) };
}

export function hashRefreshToken(token: string): string {
  return crypto.createHash("sha256").update(token).digest("hex");
}
