import { z } from "zod";
import dotenv from "dotenv";

dotenv.config();

/**
 * Every knob the server has, resolved and validated once at boot. Anything
 * that reads `process.env` outside this file is a bug — a typo'd variable
 * should fail loudly here, not silently behave differently at 3am.
 */
const schema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().default("0.0.0.0"),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),

  DATABASE_PATH: z.string().default("./data/fork.db"),

  /**
   * Signing key for access tokens. Required in production — a predictable
   * default there would let anyone mint a token for any account.
   */
  AUTH_SECRET: z.string().min(32).optional(),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(60 * 60),
  REFRESH_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(60 * 60 * 24 * 60),

  /**
   * Optional. With no key the banter route still works — it just serves
   * scripted lines from the bundled bank instead of generated ones, which
   * is exactly the offline behaviour the iOS client already ships with.
   */
  ANTHROPIC_API_KEY: z.string().optional(),
  BANTER_MODEL: z.string().default("claude-opus-5"),
  BANTER_EFFORT: z.enum(["low", "medium", "high", "xhigh", "max"]).default("low"),
  BANTER_TIMEOUT_MS: z.coerce.number().int().positive().default(8_000),
  BANTER_CACHE_TTL_SECONDS: z.coerce.number().int().nonnegative().default(60 * 60 * 24),

  /** Requests per window, per identity (user id when authenticated, else IP). */
  RATE_LIMIT_WINDOW_SECONDS: z.coerce.number().int().positive().default(60),
  RATE_LIMIT_BANTER: z.coerce.number().int().positive().default(20),
  RATE_LIMIT_AUTH: z.coerce.number().int().positive().default(10),
  RATE_LIMIT_DEFAULT: z.coerce.number().int().positive().default(120),

  /** Comma-separated origins for the landing page / web clients. `*` allows all. */
  CORS_ORIGINS: z.string().default("*"),

  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  const issues = parsed.error.issues.map((i) => `  ${i.path.join(".")}: ${i.message}`).join("\n");
  throw new Error(`Invalid environment configuration:\n${issues}`);
}

const env = parsed.data;

if (env.NODE_ENV === "production" && !env.AUTH_SECRET) {
  throw new Error(
    "AUTH_SECRET is required in production (32+ chars). Generate one with: node -e \"console.log(require('crypto').randomBytes(48).toString('base64url'))\"",
  );
}

/**
 * Dev/test only. Deterministic so a restart doesn't invalidate the tokens
 * you're mid-way through testing with; production refuses to reach here.
 */
const DEV_AUTH_SECRET = "dev-only-insecure-secret-do-not-use-in-production-0000";

export const config = {
  env: env.NODE_ENV,
  isProduction: env.NODE_ENV === "production",
  isTest: env.NODE_ENV === "test",
  host: env.HOST,
  port: env.PORT,
  logLevel: env.LOG_LEVEL,
  databasePath: env.DATABASE_PATH,

  auth: {
    secret: env.AUTH_SECRET ?? DEV_AUTH_SECRET,
    accessTokenTtlSeconds: env.ACCESS_TOKEN_TTL_SECONDS,
    refreshTokenTtlSeconds: env.REFRESH_TOKEN_TTL_SECONDS,
  },

  banter: {
    apiKey: env.ANTHROPIC_API_KEY,
    enabled: Boolean(env.ANTHROPIC_API_KEY),
    model: env.BANTER_MODEL,
    effort: env.BANTER_EFFORT,
    timeoutMs: env.BANTER_TIMEOUT_MS,
    cacheTtlSeconds: env.BANTER_CACHE_TTL_SECONDS,
  },

  rateLimit: {
    windowSeconds: env.RATE_LIMIT_WINDOW_SECONDS,
    banter: env.RATE_LIMIT_BANTER,
    auth: env.RATE_LIMIT_AUTH,
    default: env.RATE_LIMIT_DEFAULT,
  },

  corsOrigins: env.CORS_ORIGINS === "*" ? true : env.CORS_ORIGINS.split(",").map((o) => o.trim()).filter(Boolean),
} as const;

export type Config = typeof config;
