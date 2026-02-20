import { parseArgs } from "node:util";
import * as path from "node:path";
import * as fs from "node:fs";
import * as crypto from "node:crypto";
import { startDaemon, stopDaemon } from "./daemon.js";
import { sendQuery } from "./query-client.js";

/**
 * Resolve the default socket path for this project.
 * Uses /tmp/engine-daemon-{hash}.sock where hash is derived from project root.
 */
function defaultSocketPath(): string {
  const projectRoot = process.env.PROJECT_ROOT || process.cwd();
  const hash = crypto.createHash("md5").update(projectRoot).digest("hex").slice(0, 8);
  return `/tmp/engine-daemon-${hash}.sock`;
}

/**
 * Resolve the default DB path for this project.
 */
function defaultDbPath(): string {
  const projectRoot = process.env.PROJECT_ROOT || process.cwd();
  return path.join(projectRoot, ".claude", ".engine.db");
}

/**
 * Check if daemon is running by testing socket connectivity.
 */
async function isDaemonRunning(socketPath: string): Promise<boolean> {
  try {
    const result = await sendQuery(socketPath, {
      sql: "SELECT 1",
      params: [],
      format: "scalar",
      single: false,
    });
    return result.ok === true;
  } catch {
    return false;
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error("Usage: engine-db <command> [args...]");
    console.error("Commands: daemon, query");
    process.exit(1);
  }

  const command = args[0];

  if (command === "daemon") {
    await handleDaemon(args.slice(1));
  } else if (command === "query") {
    await handleQuery(args.slice(1));
  } else {
    console.error(`Unknown command: ${command}`);
    process.exit(1);
  }
}

async function handleDaemon(args: string[]): Promise<void> {
  const subcommand = args[0];

  const socketPath = defaultSocketPath();
  const dbPath = defaultDbPath();

  if (subcommand === "start") {
    // Check if already running
    if (await isDaemonRunning(socketPath)) {
      console.error("Daemon is already running");
      process.exit(1);
    }

    console.error(`Starting daemon...`);
    console.error(`  Socket: ${socketPath}`);
    console.error(`  DB: ${dbPath}`);

    await startDaemon({ socketPath, dbPath });

    // Write PID file
    const pidPath = socketPath.replace(".sock", ".pid");
    fs.writeFileSync(pidPath, String(process.pid));

    console.error(`Daemon started (PID: ${process.pid})`);

    // Keep process alive
    process.on("SIGTERM", async () => {
      console.error("Received SIGTERM, shutting down...");
      await stopDaemon();
      fs.rmSync(pidPath, { force: true });
      process.exit(0);
    });

    process.on("SIGINT", async () => {
      console.error("Received SIGINT, shutting down...");
      await stopDaemon();
      fs.rmSync(pidPath, { force: true });
      process.exit(0);
    });
  } else if (subcommand === "stop") {
    const pidPath = socketPath.replace(".sock", ".pid");
    if (!fs.existsSync(pidPath)) {
      console.error("Daemon is not running (no PID file)");
      process.exit(1);
    }

    const pid = parseInt(fs.readFileSync(pidPath, "utf-8").trim(), 10);
    try {
      process.kill(pid, "SIGTERM");
      console.error(`Sent SIGTERM to daemon (PID: ${pid})`);
    } catch {
      console.error(`Daemon process ${pid} not found — cleaning up stale PID file`);
    }
    fs.rmSync(pidPath, { force: true });
  } else if (subcommand === "status") {
    const running = await isDaemonRunning(socketPath);
    if (running) {
      const pidPath = socketPath.replace(".sock", ".pid");
      const pid = fs.existsSync(pidPath)
        ? fs.readFileSync(pidPath, "utf-8").trim()
        : "unknown";
      console.log(`running (PID: ${pid})`);
      console.error(`  Socket: ${socketPath}`);
      console.error(`  DB: ${dbPath}`);
    } else {
      console.log("stopped");
      process.exit(1);
    }
  } else {
    console.error("Usage: engine-db daemon <start|stop|status>");
    process.exit(1);
  }
}

async function handleQuery(args: string[]): Promise<void> {
  // Parse flags
  const { values, positionals } = parseArgs({
    args,
    options: {
      single: { type: "boolean", default: false },
      format: { type: "string", default: "json" },
    },
    allowPositionals: true,
  });

  if (positionals.length === 0) {
    // Check if SQL is on stdin (heredoc)
    const stdin = fs.readFileSync(0, "utf-8").trim();
    if (!stdin) {
      console.error("Usage: engine-db query 'SQL' [params...] [--single] [--format=json|tsv|scalar]");
      process.exit(1);
    }
    positionals.unshift(stdin);
  }

  const sql = positionals[0];
  const params = positionals.slice(1).map((p) => {
    // Try to parse as number
    const num = Number(p);
    return Number.isFinite(num) ? num : p;
  });

  const socketPath = defaultSocketPath();
  const format = (values.format as "json" | "tsv" | "scalar") ?? "json";

  try {
    const result = await sendQuery(socketPath, {
      sql,
      params,
      format,
      single: values.single ?? false,
    });

    if (!result.ok) {
      console.error(`Error: ${(result as { error: string }).error}`);
      process.exit(1);
    }

    // Output based on format
    if (format === "tsv") {
      console.log((result as { tsv: string }).tsv);
    } else if (format === "scalar") {
      const value = (result as { value: unknown }).value;
      console.log(value === null ? "" : String(value));
    } else if (values.single) {
      const row = (result as { row: unknown }).row;
      console.log(JSON.stringify(row));
    } else {
      const rows = (result as { rows: unknown[] }).rows;
      console.log(JSON.stringify(rows));
    }
  } catch (err: unknown) {
    if (err instanceof Error && "code" in err && (err as NodeJS.ErrnoException).code === "ENOENT") {
      console.error("Error: Daemon is not running. Start it with: engine daemon start");
    } else if (err instanceof Error && "code" in err && (err as NodeJS.ErrnoException).code === "ECONNREFUSED") {
      console.error("Error: Daemon is not running. Start it with: engine daemon start");
    } else {
      console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
    }
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
