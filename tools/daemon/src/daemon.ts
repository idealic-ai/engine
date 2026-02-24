import * as net from "node:net";
import * as fs from "node:fs";
import * as path from "node:path";
import { createDb, type DbConnection } from "../../db/src/db-wrapper.js";
import { applySchema } from "../../db/src/schema.js";

export interface DaemonOptions {
  socketPath: string;
  dbPath: string;
}

import { dispatch, getRegistry, type RpcRequest } from "../../shared/src/dispatch.js";
import { rpcEnvSchema, type RpcContext } from "../../shared/src/context.js";
import { buildNamespace } from "../../shared/src/namespace-builder.js";
import { registerMiddleware, clearMiddlewares, txMiddleware, fsBufferMiddleware, setFsExecutor, type FsOp } from "../../shared/src/middleware.js";
import "./registry.js"; // master registry — imports all namespace registries + namespace augmentations

interface QueryRequest {
  sql: string;
  params: (string | number | null)[];
  format: "json" | "tsv" | "scalar";
  single: boolean;
}

let server: net.Server | null = null;
let db: DbConnection | null = null;
let ctx: RpcContext | null = null;
let currentDbPath: string | null = null;

/**
 * Start the daemon — opens DB via wa-sqlite (WASM + sqlite-vec), applies schema, listens on Unix socket.
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

  // Initialize wa-sqlite (WASM build with sqlite-vec statically linked)
  db = await createDb(dbPath);
  currentDbPath = dbPath;

  // Apply schema (idempotent)
  await applySchema(db);

  // Build RPC context once — connection + namespace proxies
  const registry = getRegistry();
  ctx = {} as RpcContext;
  ctx.env = {}; // per-request env — overwritten in handleQuery before dispatch
  const ns = buildNamespace("db", registry, ctx);
  ctx.db = Object.assign(db, ns) as unknown as RpcContext["db"];


  // Register middleware — order matters: fsBuffer (outer) → tx (inner) → handler
  // fsBufferMiddleware collects FS ops during handler execution, flushes after tx commits
  // txMiddleware wraps handler in BEGIN/COMMIT/ROLLBACK
  registerMiddleware(fsBufferMiddleware);
  registerMiddleware(txMiddleware);

  // Wire FS executor for fsBufferMiddleware
  setFsExecutor(async (op: FsOp) => {
    switch (op.op) {
      case "write":
        fs.mkdirSync(path.dirname(op.path), { recursive: true });
        fs.writeFileSync(op.path, op.content ?? "");
        break;
      case "append":
        fs.mkdirSync(path.dirname(op.path), { recursive: true });
        fs.appendFileSync(op.path, op.content ?? "");
        break;
      case "mkdir":
        fs.mkdirSync(op.path, { recursive: true });
        break;
      case "unlink":
        if (fs.existsSync(op.path)) fs.unlinkSync(op.path);
        break;
    }
  });

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

        handleQuery(message).then((response) => {
          conn.write(JSON.stringify(response) + "\n");
        });
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
}

/**
 * Stop the daemon — close socket, close DB.
 * wa-sqlite persists to disk via NodeAsyncVFS (file-backed WASM).
 */
export async function stopDaemon(): Promise<void> {
  // Clear middleware registrations
  clearMiddlewares();
  setFsExecutor(undefined);

  // Close server
  if (server) {
    await new Promise<void>((resolve) => {
      server!.close(() => resolve());
    });
    server = null;
  }

  // Close DB
  if (db) {
    await db.close();
    db = null;
  }

  ctx = null;
  currentDbPath = null;
}

/**
 * Handle a single message — route to RPC dispatch or raw SQL.
 */
async function handleQuery(message: string): Promise<Record<string, unknown>> {
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
    // Validate and inject per-request env vars into ctx before dispatch
    // Zod defaults fill CWD and AGENT_ID when absent; extra fields are stripped
    const envResult = rpcEnvSchema.safeParse(parsed.env ?? {});
    ctx!.env = envResult.success ? envResult.data : { CWD: process.cwd(), AGENT_ID: "default" };
    return await dispatch(parsed as unknown as RpcRequest, ctx!) as unknown as Record<string, unknown>;
  }

  const request = parsed as unknown as QueryRequest;
  const { sql, params, format, single } = request;

  try {
    // Determine if this is a read or write query
    const trimmed = sql.trim().toUpperCase();
    const isSelect = trimmed.startsWith("SELECT") || trimmed.startsWith("PRAGMA") || trimmed.startsWith("EXPLAIN");

    if (isSelect) {
      if (format === "scalar") {
        const row = await db.raw.get<Record<string, unknown>>(sql, params);
        if (!row) return { ok: true, value: null };
        const keys = Object.keys(row);
        return { ok: true, value: keys.length > 0 ? row[keys[0]] : null };
      }

      const rows = await db.raw.all<Record<string, unknown>>(sql, params);

      if (rows.length === 0) {
        if (single) return { ok: true, row: null };
        return { ok: true, rows: [] };
      }

      if (format === "tsv") {
        const columns = Object.keys(rows[0]);
        const header = columns.join("\t");
        const tsvRows = rows.map((row) =>
          columns.map((c) => (row[c] === null ? "" : String(row[c]))).join("\t")
        );
        return { ok: true, tsv: [header, ...tsvRows].join("\n") };
      }

      if (single) {
        return { ok: true, row: rows[0] ?? null };
      }

      return { ok: true, rows };
    } else {
      // Write query (INSERT, UPDATE, DELETE, CREATE, etc.)
      const result = await db.run(sql, params);
      return { ok: true, changes: result.changes };
    }
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    return { ok: false, error: errorMessage };
  }
}
