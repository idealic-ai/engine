import * as net from "node:net";
import * as fs from "node:fs";
import * as path from "node:path";
import initSqlJs, { type Database } from "sql.js";
import { applySchema } from "./schema.js";

export interface DaemonOptions {
  socketPath: string;
  dbPath: string;
}

import { dispatch, type RpcRequest } from "./rpc/dispatch.js";
import "./rpc/registry.js"; // registers all RPC commands

interface QueryRequest {
  sql: string;
  params: (string | number | null)[];
  format: "json" | "tsv" | "scalar";
  single: boolean;
}

let server: net.Server | null = null;
let db: Database | null = null;
let currentDbPath: string | null = null;
let flushInterval: ReturnType<typeof setInterval> | null = null;

const FLUSH_INTERVAL_MS = 30_000; // 30 seconds

/**
 * Start the daemon — opens DB, applies schema, listens on Unix socket.
 */
export async function startDaemon(options: DaemonOptions): Promise<void> {
  const { socketPath, dbPath } = options;

  // Clean up stale socket file
  if (fs.existsSync(socketPath)) {
    fs.unlinkSync(socketPath);
  }

  // Ensure parent directories exist
  const socketDir = path.dirname(socketPath);
  if (!fs.existsSync(socketDir)) {
    fs.mkdirSync(socketDir, { recursive: true });
  }
  const dbDir = path.dirname(dbPath);
  if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
  }

  // Initialize sql.js and open/create DB
  const SQL = await initSqlJs();

  if (fs.existsSync(dbPath)) {
    const buffer = fs.readFileSync(dbPath);
    db = new SQL.Database(buffer);
  } else {
    db = new SQL.Database();
  }

  currentDbPath = dbPath;

  // Apply schema (idempotent)
  applySchema(db);

  // Start Unix socket server
  server = net.createServer((conn) => {
    let buffer = "";

    conn.on("data", (chunk) => {
      buffer += chunk.toString();

      // Process complete messages (newline-delimited)
      while (buffer.includes("\n")) {
        const newlineIndex = buffer.indexOf("\n");
        const message = buffer.slice(0, newlineIndex);
        buffer = buffer.slice(newlineIndex + 1);

        const response = handleQuery(message);
        conn.write(JSON.stringify(response) + "\n");
      }
    });

    conn.on("error", () => {
      // Client disconnected — ignore
    });
  });

  await new Promise<void>((resolve, reject) => {
    server!.on("error", reject);
    server!.listen(socketPath, () => resolve());
  });

  // Periodic DB flush — limit crash data loss to 30s
  flushInterval = setInterval(() => saveDbToDisk(), FLUSH_INTERVAL_MS);
}

/**
 * Stop the daemon — save DB to disk, close socket.
 */
export async function stopDaemon(): Promise<void> {
  // Save DB to disk
  if (db && currentDbPath) {
    saveDbToDisk();
  }

  // Stop periodic flush
  if (flushInterval) {
    clearInterval(flushInterval);
    flushInterval = null;
  }

  // Close server
  if (server) {
    await new Promise<void>((resolve) => {
      server!.close(() => resolve());
    });
    server = null;
  }

  // Close DB
  if (db) {
    db.close();
    db = null;
  }

  currentDbPath = null;
}

/**
 * Save the in-memory DB to disk.
 */
function saveDbToDisk(): void {
  if (!db || !currentDbPath) return;

  const data = db.export();
  const buffer = Buffer.from(data);
  const dir = path.dirname(currentDbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(currentDbPath, buffer);
}

/**
 * Handle a single message — route to RPC dispatch or raw SQL.
 */
function handleQuery(message: string): Record<string, unknown> {
  if (!db) {
    return { ok: false, error: "Database not initialized" };
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(message);
  } catch {
    return { ok: false, error: "Invalid JSON request" };
  }

  // Route: {cmd} → RPC dispatch, {sql} → raw SQL
  if ("cmd" in parsed && typeof parsed.cmd === "string") {
    return dispatch(parsed as RpcRequest, db);
  }

  const request = parsed as unknown as QueryRequest;
  const { sql, params, format, single } = request;

  try {
    // Determine if this is a read or write query
    const trimmed = sql.trim().toUpperCase();
    const isSelect = trimmed.startsWith("SELECT") || trimmed.startsWith("PRAGMA") || trimmed.startsWith("EXPLAIN");

    if (isSelect) {
      const result = db.exec(sql, params);

      if (result.length === 0) {
        // No results
        if (format === "scalar") {
          return { ok: true, value: null };
        }
        if (single) {
          return { ok: true, row: null };
        }
        return { ok: true, rows: [] };
      }

      const { columns, values } = result[0];

      if (format === "scalar") {
        return { ok: true, value: values[0]?.[0] ?? null };
      }

      if (format === "tsv") {
        const header = columns.join("\t");
        const rows = values.map((row) =>
          row.map((v) => (v === null ? "" : String(v))).join("\t")
        );
        return { ok: true, tsv: [header, ...rows].join("\n") };
      }

      // JSON format — convert to objects
      const rows = values.map((row) => {
        const obj: Record<string, unknown> = {};
        for (let i = 0; i < columns.length; i++) {
          obj[columns[i]] = row[i];
        }
        return obj;
      });

      if (single) {
        return { ok: true, row: rows[0] ?? null };
      }

      return { ok: true, rows };
    } else {
      // Write query (INSERT, UPDATE, DELETE, CREATE, etc.)
      db.run(sql, params);
      const changes = db.getRowsModified();
      return { ok: true, changes };
    }
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    return { ok: false, error: errorMessage };
  }
}
