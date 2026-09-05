import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import { config } from "../config.js";

export type DB = Database.Database;

/**
 * Ordered, append-only. Each entry runs exactly once and is recorded in
 * `schema_migrations`; never edit a migration that has shipped — add a new one.
 */
const MIGRATIONS: { name: string; sql: string }[] = [
  {
    name: "001_initial",
    sql: `
      CREATE TABLE users (
        id            TEXT PRIMARY KEY,
        email         TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        display_name  TEXT,
        created_at    INTEGER NOT NULL,
        updated_at    INTEGER NOT NULL
      );

      CREATE TABLE refresh_tokens (
        token_hash TEXT PRIMARY KEY,
        user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        expires_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        revoked_at INTEGER
      );
      CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);

      /*
       * Trips are synced, not authored, on the server: the client owns
       * client_id and updated_at, the server owns rev. Sync pulls everything
       * with rev > cursor, so rev must be globally monotonic — see
       * nextRev() rather than relying on rowid or a timestamp.
       */
      CREATE TABLE trips (
        id                   TEXT PRIMARY KEY,
        user_id              TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        client_id            TEXT NOT NULL,
        rev                  INTEGER NOT NULL,
        destination_name     TEXT NOT NULL,
        destination_latitude REAL,
        destination_longitude REAL,
        started_at           INTEGER NOT NULL,
        ended_at             INTEGER,
        distance_meters      REAL,
        duration_seconds     REAL,
        reroute_count        INTEGER NOT NULL DEFAULT 0,
        banter_line_count    INTEGER NOT NULL DEFAULT 0,
        updated_at           INTEGER NOT NULL,
        deleted              INTEGER NOT NULL DEFAULT 0,
        UNIQUE(user_id, client_id)
      );
      CREATE INDEX idx_trips_user_rev ON trips(user_id, rev);

      /* Single-row counter backing nextRev(). */
      CREATE TABLE rev_counter (
        id  INTEGER PRIMARY KEY CHECK (id = 1),
        rev INTEGER NOT NULL
      );
      INSERT INTO rev_counter (id, rev) VALUES (1, 0);

      /*
       * Generated banter is expensive and highly repetitive across users —
       * the same category/persona/context bucket recurs constantly. Cache
       * on the coarse bucket key, never on anything user-identifying.
       */
      CREATE TABLE banter_cache (
        cache_key  TEXT PRIMARY KEY,
        payload    TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        hits       INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX idx_banter_cache_expiry ON banter_cache(expires_at);
    `,
  },
];

function applyMigrations(db: DB): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name       TEXT PRIMARY KEY,
      applied_at INTEGER NOT NULL
    );
  `);

  const applied = new Set(
    db.prepare<[], { name: string }>("SELECT name FROM schema_migrations").all().map((r) => r.name),
  );

  const record = db.prepare("INSERT INTO schema_migrations (name, applied_at) VALUES (?, ?)");

  for (const migration of MIGRATIONS) {
    if (applied.has(migration.name)) continue;
    db.transaction(() => {
      db.exec(migration.sql);
      record.run(migration.name, Date.now());
    })();
  }
}

export function openDatabase(filePath: string = config.databasePath): DB {
  if (filePath !== ":memory:") {
    fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true });
  }

  const db = new Database(filePath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.pragma("busy_timeout = 5000");
  applyMigrations(db);
  return db;
}

/**
 * Allocates the next global revision. Callers must already be inside the
 * transaction that writes the row using it, so a crash can't burn a rev and
 * leave a gap that a client cursor would skip past.
 */
export function nextRev(db: DB): number {
  db.prepare("UPDATE rev_counter SET rev = rev + 1 WHERE id = 1").run();
  const row = db.prepare<[], { rev: number }>("SELECT rev FROM rev_counter WHERE id = 1").get();
  if (!row) throw new Error("rev_counter row missing — database is corrupt");
  return row.rev;
}
