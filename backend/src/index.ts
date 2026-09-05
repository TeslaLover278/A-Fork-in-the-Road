import { config } from "./config.js";
import { buildServer, startMaintenance } from "./server.js";
import { openDatabase } from "./db/index.js";

async function main(): Promise<void> {
  const db = openDatabase();
  const { app } = await buildServer(db);

  startMaintenance(db);

  if (!config.banter.enabled) {
    app.log.warn(
      "ANTHROPIC_API_KEY is not set — /v1/banter will serve scripted lines from the bundled bank only.",
    );
  }

  // Close the listener first so in-flight requests finish, then the database.
  // Killing SQLite while a write is open is how a WAL ends up needing repair.
  const shutdown = async (signal: string): Promise<void> => {
    app.log.info({ signal }, "shutting down");
    try {
      await app.close();
      db.close();
      process.exit(0);
    } catch (error) {
      app.log.error({ err: error }, "error during shutdown");
      process.exit(1);
    }
  };

  process.on("SIGTERM", () => void shutdown("SIGTERM"));
  process.on("SIGINT", () => void shutdown("SIGINT"));

  await app.listen({ host: config.host, port: config.port });
}

main().catch((error) => {
  console.error("Failed to start server:", error);
  process.exit(1);
});
