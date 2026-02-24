/**
 * CLI entry point for the engine daemon.
 *
 * Usage: npx tsx main.ts --socket /tmp/engine.sock --db /tmp/engine.db
 *
 * Parses --socket and --db flags, then calls startDaemon().
 */
import { startDaemon } from "./daemon.js";

const args = process.argv.slice(2);

function getArg(name: string, fallback: string): string {
  const idx = args.indexOf(`--${name}`);
  return idx !== -1 && args[idx + 1] ? args[idx + 1] : fallback;
}

const socketPath = getArg("socket", "/tmp/engine-daemon/engine.sock");
const dbPath = getArg("db", "/tmp/engine-daemon/engine.db");

console.log(`Engine daemon starting...`);
console.log(`  Socket: ${socketPath}`);
console.log(`  DB: ${dbPath}`);

startDaemon({ socketPath, dbPath })
  .then(() => console.log("Engine daemon listening."))
  .catch((err) => {
    console.error("Failed to start daemon:", err);
    process.exit(1);
  });

// Graceful shutdown
for (const sig of ["SIGINT", "SIGTERM"] as const) {
  process.on(sig, async () => {
    console.log(`\nReceived ${sig}, shutting down...`);
    const { stopDaemon } = await import("./daemon.js");
    await stopDaemon();
    process.exit(0);
  });
}
