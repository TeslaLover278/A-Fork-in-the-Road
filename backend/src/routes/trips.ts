import type { FastifyInstance } from "fastify";
import { nextRev, type DB } from "../db/index.js";
import { newId } from "../services/crypto.js";
import { requireAuth } from "../middleware/auth.js";
import { rateLimit } from "../middleware/rateLimit.js";
import { listTripsQuerySchema, syncSchema, type TripInput } from "../schemas.js";

interface TripRow {
  id: string;
  client_id: string;
  rev: number;
  destination_name: string;
  destination_latitude: number | null;
  destination_longitude: number | null;
  started_at: number;
  ended_at: number | null;
  distance_meters: number | null;
  duration_seconds: number | null;
  reroute_count: number;
  banter_line_count: number;
  updated_at: number;
  deleted: number;
}

function publicTrip(row: TripRow) {
  return {
    id: row.id,
    clientId: row.client_id,
    rev: row.rev,
    destinationName: row.destination_name,
    destinationLatitude: row.destination_latitude,
    destinationLongitude: row.destination_longitude,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    distanceMeters: row.distance_meters,
    durationSeconds: row.duration_seconds,
    rerouteCount: row.reroute_count,
    banterLineCount: row.banter_line_count,
    updatedAt: row.updated_at,
    deleted: row.deleted === 1,
  };
}

export function registerTripRoutes(app: FastifyInstance, db: DB): void {
  const findByClientId = db.prepare<[string, string], TripRow>(
    "SELECT * FROM trips WHERE user_id = ? AND client_id = ?",
  );

  const insertTrip = db.prepare(
    `INSERT INTO trips (
       id, user_id, client_id, rev, destination_name, destination_latitude, destination_longitude,
       started_at, ended_at, distance_meters, duration_seconds, reroute_count, banter_line_count,
       updated_at, deleted
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  );

  const updateTrip = db.prepare(
    `UPDATE trips SET
       rev = ?, destination_name = ?, destination_latitude = ?, destination_longitude = ?,
       started_at = ?, ended_at = ?, distance_meters = ?, duration_seconds = ?,
       reroute_count = ?, banter_line_count = ?, updated_at = ?, deleted = ?
     WHERE id = ?`,
  );

  /**
   * Last-write-wins on the client's own `updatedAt`.
   *
   * A trip is an append-mostly record written by one device at a time — you
   * are not driving two cars at once — so a full CRDT would be a lot of
   * machinery for a conflict that barely occurs. Ties keep the stored row so
   * a retried request is idempotent rather than churning a new rev.
   */
  function upsert(userId: string, input: TripInput): { row: TripRow; changed: boolean } {
    const existing = findByClientId.get(userId, input.clientId);

    if (existing && existing.updated_at >= input.updatedAt) {
      return { row: existing, changed: false };
    }

    const rev = nextRev(db);
    const values = [
      input.destinationName,
      input.destinationLatitude ?? null,
      input.destinationLongitude ?? null,
      input.startedAt,
      input.endedAt ?? null,
      input.distanceMeters ?? null,
      input.durationSeconds ?? null,
      input.rerouteCount,
      input.banterLineCount,
      input.updatedAt,
      input.deleted ? 1 : 0,
    ] as const;

    if (existing) {
      updateTrip.run(rev, ...values, existing.id);
    } else {
      insertTrip.run(newId("trip"), userId, input.clientId, rev, ...values);
    }

    return { row: findByClientId.get(userId, input.clientId)!, changed: true };
  }

  function changesSince(userId: string, since: number, limit: number, includeDeleted: boolean) {
    const rows = db
      .prepare<[string, number, number], TripRow>(
        `SELECT * FROM trips
         WHERE user_id = ? AND rev > ?${includeDeleted ? "" : " AND deleted = 0"}
         ORDER BY rev ASC
         LIMIT ?`,
      )
      // One extra row is the cheapest reliable way to know if more remain.
      .all(userId, since, limit + 1);

    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    const cursor = page.length > 0 ? page[page.length - 1]!.rev : since;

    return { trips: page.map(publicTrip), cursor, hasMore };
  }

  /**
   * The endpoint the client should actually use: one round trip that pushes
   * local changes and pulls remote ones, so a device coming back online
   * reconciles in a single request.
   *
   * Deletes always come back, regardless of `includeDeleted` on the pull-only
   * route — a client that filtered out tombstones could never learn that a
   * trip was removed on another device.
   */
  app.post("/v1/trips/sync", { preHandler: [requireAuth, rateLimit("default")] }, async (request, reply) => {
    const parsed = syncSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", details: parsed.error.flatten() });
    }

    const userId = request.userId!;
    const { since, trips, limit } = parsed.data;

    const applied = db.transaction(() => trips.map((t) => upsert(userId, t)))();

    const accepted = applied.filter((r) => r.changed).length;
    const result = changesSince(userId, since, limit, true);

    return reply.send({
      ...result,
      accepted,
      rejected: applied.length - accepted,
    });
  });

  app.get("/v1/trips", { preHandler: [requireAuth, rateLimit("default")] }, async (request, reply) => {
    const parsed = listTripsQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", details: parsed.error.flatten() });
    }

    const { since, limit, includeDeleted } = parsed.data;
    return reply.send(changesSince(request.userId!, since, limit, includeDeleted));
  });

  app.get("/v1/trips/:clientId", { preHandler: [requireAuth, rateLimit("default")] }, async (request, reply) => {
    const { clientId } = request.params as { clientId: string };
    const row = findByClientId.get(request.userId!, clientId);
    if (!row || row.deleted === 1) {
      return reply.code(404).send({ error: "not_found", message: "No such trip." });
    }
    return reply.send({ trip: publicTrip(row) });
  });

  /**
   * Tombstones rather than removing the row — a hard delete would be
   * invisible to other devices, which only ever learn about changes by
   * pulling revs greater than their cursor.
   */
  app.delete("/v1/trips/:clientId", { preHandler: [requireAuth, rateLimit("default")] }, async (request, reply) => {
    const { clientId } = request.params as { clientId: string };
    const userId = request.userId!;

    const existing = findByClientId.get(userId, clientId);
    if (!existing) return reply.code(404).send({ error: "not_found", message: "No such trip." });

    if (existing.deleted === 1) return reply.send({ trip: publicTrip(existing) });

    const now = Date.now();
    db.transaction(() => {
      db.prepare("UPDATE trips SET deleted = 1, rev = ?, updated_at = ? WHERE id = ?").run(
        nextRev(db),
        now,
        existing.id,
      );
    })();

    return reply.send({ trip: publicTrip(findByClientId.get(userId, clientId)!) });
  });
}
