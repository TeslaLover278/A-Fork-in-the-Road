import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildServer } from "../src/server.js";
import { openDatabase, type DB } from "../src/db/index.js";
import { resetRateLimits } from "../src/middleware/rateLimit.js";
import { CONTENT_VERSION, LINE_BANK } from "../src/content/lineBank.js";

let app: FastifyInstance;
let db: DB;

beforeEach(async () => {
  resetRateLimits();
  db = openDatabase(":memory:");
  ({ app } = await buildServer(db));
  await app.ready();
});

afterEach(async () => {
  await app.close();
  db.close();
});

async function register(email = "driver@example.com", password = "correct-horse-battery") {
  const res = await app.inject({
    method: "POST",
    url: "/v1/auth/register",
    payload: { email, password },
  });
  expect(res.statusCode).toBe(201);
  return res.json() as { accessToken: string; refreshToken: string; user: { id: string } };
}

function auth(token: string) {
  return { authorization: `Bearer ${token}` };
}

describe("health & content", () => {
  it("reports health", async () => {
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json().status).toBe("ok");
  });

  it("serves the line bank and personas", async () => {
    const bank = await app.inject({ method: "GET", url: "/v1/content/line-bank" });
    expect(bank.statusCode).toBe(200);
    expect(bank.json().version).toBe(CONTENT_VERSION);
    expect(bank.json().lines).toHaveLength(LINE_BANK.length);

    const personas = await app.inject({ method: "GET", url: "/v1/content/personas" });
    expect(personas.statusCode).toBe(200);
    const ids = personas.json().personas.map((p: { id: string }) => p.id);
    expect(ids).toEqual(["dez", "vale"]);
  });

  it("never leaks the server-only generation prompt to clients", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/content/personas" });
    for (const persona of res.json().personas) {
      expect(persona).not.toHaveProperty("prompt");
    }
  });

  it("answers a conditional GET with 304", async () => {
    const first = await app.inject({ method: "GET", url: "/v1/content/line-bank" });
    const etag = first.headers.etag as string;
    expect(etag).toBeTruthy();

    const second = await app.inject({
      method: "GET",
      url: "/v1/content/line-bank",
      headers: { "if-none-match": etag },
    });
    expect(second.statusCode).toBe(304);
    expect(second.body).toBe("");
  });
});

describe("auth", () => {
  it("registers, then authenticates the returned token", async () => {
    const session = await register();
    const me = await app.inject({ method: "GET", url: "/v1/me", headers: auth(session.accessToken) });
    expect(me.statusCode).toBe(200);
    expect(me.json().user.email).toBe("driver@example.com");
  });

  it("rejects a duplicate email", async () => {
    await register();
    const res = await app.inject({
      method: "POST",
      url: "/v1/auth/register",
      payload: { email: "driver@example.com", password: "another-long-password" },
    });
    expect(res.statusCode).toBe(409);
  });

  it("normalises email case on register and login", async () => {
    await register("Driver@Example.com");
    const res = await app.inject({
      method: "POST",
      url: "/v1/auth/login",
      payload: { email: "DRIVER@example.COM", password: "correct-horse-battery" },
    });
    expect(res.statusCode).toBe(200);
  });

  it("rejects a wrong password", async () => {
    await register();
    const res = await app.inject({
      method: "POST",
      url: "/v1/auth/login",
      payload: { email: "driver@example.com", password: "wrong-password-here" },
    });
    expect(res.statusCode).toBe(401);
  });

  it("gives the same answer for a wrong password and an unknown account", async () => {
    await register();
    const wrongPassword = await app.inject({
      method: "POST",
      url: "/v1/auth/login",
      payload: { email: "driver@example.com", password: "wrong-password-here" },
    });
    const noSuchUser = await app.inject({
      method: "POST",
      url: "/v1/auth/login",
      payload: { email: "nobody@example.com", password: "wrong-password-here" },
    });
    expect(wrongPassword.statusCode).toBe(401);
    expect(noSuchUser.statusCode).toBe(401);
    expect(wrongPassword.json()).toEqual(noSuchUser.json());
  });

  it("rotates refresh tokens and refuses the old one", async () => {
    const session = await register();

    const refreshed = await app.inject({
      method: "POST",
      url: "/v1/auth/refresh",
      payload: { refreshToken: session.refreshToken },
    });
    expect(refreshed.statusCode).toBe(200);
    expect(refreshed.json().refreshToken).not.toBe(session.refreshToken);

    const replay = await app.inject({
      method: "POST",
      url: "/v1/auth/refresh",
      payload: { refreshToken: session.refreshToken },
    });
    expect(replay.statusCode).toBe(401);
  });

  it("revokes a refresh token on logout", async () => {
    const session = await register();
    const logout = await app.inject({
      method: "POST",
      url: "/v1/auth/logout",
      payload: { refreshToken: session.refreshToken },
    });
    expect(logout.statusCode).toBe(204);

    const res = await app.inject({
      method: "POST",
      url: "/v1/auth/refresh",
      payload: { refreshToken: session.refreshToken },
    });
    expect(res.statusCode).toBe(401);
  });

  it("rejects a tampered access token", async () => {
    const session = await register();
    const [header, payload] = session.accessToken.split(".");
    const forged = `${header}.${payload}.not-the-real-signature`;

    const res = await app.inject({ method: "GET", url: "/v1/me", headers: auth(forged) });
    expect(res.statusCode).toBe(401);
  });

  it("requires auth on protected routes", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/trips" });
    expect(res.statusCode).toBe(401);
  });

  it("deletes the account and its trips", async () => {
    const session = await register();
    await app.inject({
      method: "POST",
      url: "/v1/trips/sync",
      headers: auth(session.accessToken),
      payload: { trips: [trip("a")] },
    });

    const del = await app.inject({ method: "DELETE", url: "/v1/me", headers: auth(session.accessToken) });
    expect(del.statusCode).toBe(204);

    const remaining = db.prepare("SELECT COUNT(*) AS n FROM trips").get() as { n: number };
    expect(remaining.n).toBe(0);
  });
});

function trip(clientId: string, overrides: Record<string, unknown> = {}) {
  return {
    clientId,
    destinationName: "Coffee place",
    startedAt: 1_700_000_000_000,
    endedAt: 1_700_000_600_000,
    distanceMeters: 4200,
    durationSeconds: 600,
    rerouteCount: 1,
    banterLineCount: 8,
    updatedAt: 1_700_000_600_000,
    ...overrides,
  };
}

describe("trip sync", () => {
  it("pushes and pulls in one round trip", async () => {
    const session = await register();
    const res = await app.inject({
      method: "POST",
      url: "/v1/trips/sync",
      headers: auth(session.accessToken),
      payload: { since: 0, trips: [trip("a"), trip("b")] },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.accepted).toBe(2);
    expect(body.trips).toHaveLength(2);
    expect(body.cursor).toBeGreaterThan(0);
  });

  it("returns only what changed after the cursor", async () => {
    const session = await register();
    const first = await app.inject({
      method: "POST",
      url: "/v1/trips/sync",
      headers: auth(session.accessToken),
      payload: { since: 0, trips: [trip("a")] },
    });
    const cursor = first.json().cursor;

    const second = await app.inject({
      method: "POST",
      url: "/v1/trips/sync",
      headers: auth(session.accessToken),
      payload: { since: cursor, trips: [trip("b")] },
    });

    const clientIds = second.json().trips.map((t: { clientId: string }) => t.clientId);
    expect(clientIds).toEqual(["b"]);
  });

  it("keeps the newer version on conflict and ignores a stale write", async () => {
    const session = await register();
    const headers = auth(session.accessToken);

    await app.inject({
      method: "POST",
      url: "/v1/trips/sync",
      headers,
      payload: { trips: [trip("a", { destinationName: "Newer", updatedAt: 2000 })] },
    });

    const stale = await app.inject({
      method: "POST",
      url: "/v1/trips/sync",
      headers,
      payload: { trips: [trip("a", { destinationName: "Older", updatedAt: 1000 })] },
    });
    expect(stale.json().accepted).toBe(0);

    const read = await app.inject({ method: "GET", url: "/v1/trips/a", headers });
    expect(read.json().trip.destinationName).toBe("Newer");
  });

  it("is idempotent when the same payload is retried", async () => {
    const session = await register();
    const headers = auth(session.accessToken);
    const payload = { trips: [trip("a")] };

    const first = await app.inject({ method: "POST", url: "/v1/trips/sync", headers, payload });
    const second = await app.inject({ method: "POST", url: "/v1/trips/sync", headers, payload });

    expect(first.json().accepted).toBe(1);
    expect(second.json().accepted).toBe(0);
    expect(second.json().trips.filter((t: { clientId: string }) => t.clientId === "a")).toHaveLength(1);
  });

  it("tombstones a delete so other devices can see it", async () => {
    const session = await register();
    const headers = auth(session.accessToken);

    await app.inject({ method: "POST", url: "/v1/trips/sync", headers, payload: { trips: [trip("a")] } });
    const del = await app.inject({ method: "DELETE", url: "/v1/trips/a", headers });
    expect(del.statusCode).toBe(200);
    expect(del.json().trip.deleted).toBe(true);

    // A full sync surfaces the tombstone...
    const sync = await app.inject({ method: "POST", url: "/v1/trips/sync", headers, payload: { since: 0 } });
    expect(sync.json().trips[0].deleted).toBe(true);

    // ...while the plain listing hides it by default.
    const list = await app.inject({ method: "GET", url: "/v1/trips", headers });
    expect(list.json().trips).toHaveLength(0);
  });

  it("never returns another user's trips", async () => {
    const mine = await register("me@example.com");
    const theirs = await register("them@example.com");

    await app.inject({
      method: "POST",
      url: "/v1/trips/sync",
      headers: auth(mine.accessToken),
      payload: { trips: [trip("a")] },
    });

    const res = await app.inject({
      method: "POST",
      url: "/v1/trips/sync",
      headers: auth(theirs.accessToken),
      payload: { since: 0 },
    });
    expect(res.json().trips).toHaveLength(0);

    const direct = await app.inject({ method: "GET", url: "/v1/trips/a", headers: auth(theirs.accessToken) });
    expect(direct.statusCode).toBe(404);
  });

  it("pages with hasMore and a resumable cursor", async () => {
    const session = await register();
    const headers = auth(session.accessToken);
    const many = Array.from({ length: 5 }, (_, i) => trip(`t${i}`));

    await app.inject({ method: "POST", url: "/v1/trips/sync", headers, payload: { trips: many } });

    const page1 = await app.inject({ method: "GET", url: "/v1/trips?since=0&limit=2", headers });
    expect(page1.json().trips).toHaveLength(2);
    expect(page1.json().hasMore).toBe(true);

    const page2 = await app.inject({
      method: "GET",
      url: `/v1/trips?since=${page1.json().cursor}&limit=10`,
      headers,
    });
    expect(page2.json().trips).toHaveLength(3);
    expect(page2.json().hasMore).toBe(false);
  });

  it("rejects a malformed trip", async () => {
    const session = await register();
    const res = await app.inject({
      method: "POST",
      url: "/v1/trips/sync",
      headers: auth(session.accessToken),
      payload: { trips: [{ clientId: "a" }] },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe("banter", () => {
  // No ANTHROPIC_API_KEY is set under test, so these exercise the fallback
  // path — which is the path that has to work in a car with no signal.
  it("serves scripted lines when generation is unavailable", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/banter",
      payload: { category: "tripStart", lineCount: 2 },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.source).toBe("bank");
    expect(body.fallbackReason).toBe("no_api_key");
    expect(body.lines).toHaveLength(2);
    expect(body.lines[0].personaId).toBe("dez");
    expect(body.lines[1].personaId).toBe("vale");
    for (const line of body.lines) {
      expect(typeof line.text).toBe("string");
      expect(line.text.length).toBeGreaterThan(0);
    }
  });

  it("works signed out", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/banter",
      payload: { category: "idleChatter" },
    });
    expect(res.statusCode).toBe(200);
  });

  it("honours a single-persona request when the other is muted", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/banter",
      payload: { category: "arrival", personaIds: ["vale"], lineCount: 3 },
    });

    const personaIds = res.json().lines.map((l: { personaId: string }) => l.personaId);
    expect(new Set(personaIds)).toEqual(new Set(["vale"]));
  });

  it("avoids lines the client has recently played", async () => {
    const all = LINE_BANK.filter((l) => l.personaId === "dez" && l.category === "arrival");
    const exclude = all.slice(0, all.length - 1).map((l) => l.id);

    const res = await app.inject({
      method: "POST",
      url: "/v1/banter",
      payload: { category: "arrival", personaIds: ["dez"], lineCount: 1, excludeLineIds: exclude },
    });

    expect(res.json().lines[0].lineId).toBe(all[all.length - 1]!.id);
  });

  it("rejects an unknown category", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/banter",
      payload: { category: "gossip" },
    });
    expect(res.statusCode).toBe(400);
  });

  it("rejects an unknown persona", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/banter",
      payload: { category: "tripStart", personaIds: ["hal9000"] },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe("rate limiting", () => {
  it("throttles the banter route and reports when to retry", async () => {
    const send = () =>
      app.inject({ method: "POST", url: "/v1/banter", payload: { category: "idleChatter" } });

    let limited: Awaited<ReturnType<typeof send>> | undefined;
    for (let i = 0; i < 40; i++) {
      const res = await send();
      if (res.statusCode === 429) {
        limited = res;
        break;
      }
    }

    expect(limited).toBeDefined();
    expect(limited!.json().error).toBe("rate_limited");
    expect(limited!.headers["retry-after"]).toBeDefined();
  });
});
