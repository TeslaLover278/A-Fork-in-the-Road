# Fork in the Road — backend

Node + TypeScript (Fastify, SQLite) service behind the iOS app. Three jobs:

1. **Generated banter** — fresh Dan/Harry lines from the Claude API, in place of
   the fixed scripted bank.
2. **Accounts + trip sync** — email/password accounts and trip history synced
   across devices.
3. **Content delivery** — personas and the joke bank served from the server, so
   new material ships without an App Store release.

## The one rule this service is built around

The app's core guarantee is that banter never interferes with real driving
directions. On the client that's structural — `SpeechQueueManager` owns the
audio lane and turn instructions always pre-empt banter.

Generated text needs the *content* half of that guarantee, because a model can
write something a human never would. So:

- The system prompt forbids giving, restating, or contradicting any
  instruction.
- Every generated line is then re-checked server-side by
  [`src/services/banterFilter.ts`](src/services/banterFilter.ts), which rejects
  navigation-imperative phrasing ("turn left onto…", "in 500 feet…", "take the
  next exit"), profanity, over-long lines, and meta-commentary.
- Anything filtered falls back to the scripted bank.

The prompt is the request; the filter is the guarantee. The filter has its own
test suite, including the assertion that every shipped bank line passes it —
which is how the "starts with Okay" false positive that would have rejected two
of Dan's real lines got caught.

## Nothing here can break the app

`/v1/banter` never returns a 5xx for a generation problem. No API key, timeout,
rate limit, refusal, unparseable response, every line filtered — all of them
resolve to scripted lines from the bundled bank, with a `fallbackReason` for
diagnostics. That bank is the same content the iOS app already ships, so a
total backend outage degrades the app to its existing offline behaviour rather
than to an error a driver has to deal with at 60mph.

The server also runs fine with **no `ANTHROPIC_API_KEY` at all** — it just
serves the bank. That's the default in tests.

## Running it

```bash
cd backend
npm install
cp .env.example .env      # optional: add ANTHROPIC_API_KEY for generated banter
npm run dev               # http://localhost:8080
```

```bash
npm test            # 122 tests, no network calls
npm run typecheck
npm run build && npm start
```

`AUTH_SECRET` (32+ chars) is **required** when `NODE_ENV=production` — the
server refuses to start without it rather than falling back to a shared dev
key. Every other setting has a working default; see
[`.env.example`](.env.example).

## API

All responses are JSON. Errors are `{ "error": "<code>", "message": "..." }`.
Authenticated routes take `Authorization: Bearer <accessToken>`.

### Auth

| Method | Path | Notes |
|---|---|---|
| `POST` | `/v1/auth/register` | `{email, password, displayName?}` → session. Password min 10 chars. |
| `POST` | `/v1/auth/login` | `{email, password}` → session |
| `POST` | `/v1/auth/refresh` | `{refreshToken}` → new session; **rotates** the refresh token |
| `POST` | `/v1/auth/logout` | `{refreshToken}` → 204 |
| `GET` | `/v1/me` | current user |
| `PATCH` | `/v1/me` | `{displayName}` |
| `DELETE` | `/v1/me` | deletes the account and all its trips |

A session is `{user, accessToken, accessTokenExpiresAt, refreshToken,
refreshTokenExpiresAt}`. Access tokens are stateless HMAC-signed and short-lived
(1h); refresh tokens are opaque, stored only as a SHA-256 hash, and rotate on
every use, so a stolen one is good for exactly one call.

Login returns an identical response for a wrong password and an unknown
account, and hashes a dummy password in the latter case so timing doesn't
distinguish them either.

### Trips

| Method | Path | Notes |
|---|---|---|
| `POST` | `/v1/trips/sync` | **the one clients should use** — push and pull in one round trip |
| `GET` | `/v1/trips?since=&limit=&includeDeleted=` | pull only |
| `GET` | `/v1/trips/:clientId` | single trip |
| `DELETE` | `/v1/trips/:clientId` | tombstones it |

```jsonc
// POST /v1/trips/sync
{
  "since": 0,          // server rev the client last saw; 0 = full pull
  "trips": [ { "clientId": "…", "destinationName": "Airport",
               "startedAt": 1700000000000, "updatedAt": 1700001800000,
               "rerouteCount": 2, "banterLineCount": 14 } ]
}
// → { trips: [...], cursor: 12, hasMore: false, accepted: 1, rejected: 0 }
```

**How sync works.** The client owns `clientId` (a UUID it can mint offline) and
`updatedAt`; the server owns `rev`, a globally monotonic counter. Clients pull
everything with `rev > cursor`. Conflicts are last-write-wins on the client's
`updatedAt`, and ties keep the stored row, which makes a retried request
idempotent rather than churning a new rev.

Deletes are tombstones, not row removals — a hard delete would be invisible to
other devices, since they only ever learn about changes by pulling revs above
their cursor. `/v1/trips/sync` therefore always returns tombstones;
`GET /v1/trips` hides them unless you ask.

A CRDT would be overkill here: a trip is an append-mostly record written by one
device at a time, because you are not driving two cars at once.

### Banter

```jsonc
// POST /v1/banter   — works signed out
{
  "category": "upcomingTurn",       // tripStart | upcomingTurn | rerouting | arrival | idleChatter
  "personaIds": ["dan", "harry"],    // unmuted personas, in speaking order
  "lineCount": 2,                   // 1–4, matches BanterFrequency.exchangeLength
  "context": {
    "destinationName": "the airport",
    "maneuverInstruction": "Turn left onto Maple St",   // context only; never echoed
    "distanceMeters": 400,
    "rerouteCount": 2,
    "timeOfDay": "evening"
  },
  "excludeLineIds": ["dan.arrival.1"],  // recently played, so fallback won't repeat
  "allowGenerated": true                // false forces the bank
}
// → { source: "generated" | "generated_cached" | "bank",
//     lines: [ { personaId, text, lineId? } ],
//     fallbackReason?: "timeout" }
```

`lineId` is present only on scripted lines, so the client can feed them back as
`excludeLineIds` next time. Generated lines have no id — they're never repeated.

**Privacy.** The context is deliberately coarse: a place name and the maneuver
text the driver is already being shown. No coordinates, no heading, no track —
there's nothing here that reconstructs a route. Requests are not stored against
a user.

**Cost.** Identical moments recur constantly across users, so responses are
cached on a bucketed key (category, personas, maneuver *kind*, distance band,
time of day) for 24h — exact distances would make every key unique and the
cache useless. The key is a SHA-256 hash, so no place name is stored in
plaintext. Only fully-generated exchanges are cached; a bank-topped-up one
would pin a scripted line in the cache and over-repeat it. The system prompt is
a stable cacheable prefix, and generation runs at `effort: low` — the right
trade for short, creative, latency-bound output with a driver waiting on the
beat.

### Content

| Method | Path |
|---|---|
| `GET` | `/v1/content/manifest` |
| `GET` | `/v1/content/personas` |
| `GET` | `/v1/content/line-bank` |

All three support `ETag` / `If-None-Match` → `304`. The client should keep its
bundled copy as the offline default and treat these as an override. Personas
served here omit the server-only generation `prompt`.

`/health` returns status, content version, and whether generated banter is
actually available.

## Rate limits

Fixed window per identity — user id when signed in, IP otherwise, so office
Wi-Fi doesn't make one user throttle everyone. Defaults: 20/min banter, 10/min
auth, 120/min everything else. Responses carry `RateLimit-*` headers and
`Retry-After` on a 429.

This is in-process memory, deliberately: the point is stopping a runaway client
from burning the Anthropic budget on a single-instance deployment, not
enforcing a billing quota. Running more than one instance means swapping the
`Map` in [`src/middleware/rateLimit.ts`](src/middleware/rateLimit.ts) for a
shared store.

## Layout

```
src/
  config.ts              all env parsing, validated once at boot
  server.ts              app assembly, error handling, maintenance sweep
  db/index.ts            SQLite connection + ordered migrations
  routes/                auth, trips, banter, content
  services/
    banter.ts            prompt, generation, cache, fallback
    banterFilter.ts      the content-side safety guarantee
    crypto.ts            scrypt passwords, HMAC access tokens
  content/               personas + line bank, mirrored from the Swift source
  middleware/            auth, rate limiting
test/                    122 tests
```

`src/content/personas.ts` mirrors `ios-app/ForkInTheRoad/Models/VoicePersona.swift`.
**They are duplicated, not shared** — a Swift file can't be imported by Node. If
you edit one, edit the other and bump `CONTENT_VERSION`. Only the persona roster
is mirrored: how a character sounds isn't described on either side any more,
because every line is a pre-recorded clip bundled in the app.

`src/content/lineBank.ts` has no Swift counterpart. The app used to carry a
matching text bank; it now speaks only from recordings, so the line bank here
serves generated-banter text that nothing on the client voices yet.

## Not done

**The iOS app doesn't call this yet.** It has no networking layer at all — no
`URLSession`, no base URL, no `BanterService`. The backend is complete and
tested on its own terms, but wiring it up means adding a client to the Swift
side, plus a sign-in screen for sync. That's app work, not backend work, so
it's left as the next step rather than half-done here.

Generated banter has a further gap now: the app plays pre-recorded clips and
synthesizes nothing, so a line of freshly generated *text* has no voice to
speak it. Accounts, trip sync and content delivery are usable as-is; `/v1/banter`
needs a decision about how a generated line would ever be heard.

Also out of scope: OAuth/Sign in with Apple (email+password only), push
notifications, and any multi-instance concerns (see rate limits above).
