/**
 * DbConnection — Async wrapper using wa-sqlite (WASM build with sqlite-vec).
 *
 * Convention-based transforms (on by default):
 *   Output: snake_case keys → camelCase, JSON-looking strings → parsed objects
 *   Input:  object/array params → JSON.stringify'd
 *
 * API:
 *   run(sql, params?)  → { lastID, changes }  (params auto-stringify)
 *   get<T>(sql, params?) → T | undefined       (camelCase + JSON parse)
 *   all<T>(sql, params?) → T[]                 (camelCase + JSON parse)
 *   exec(sql)           → void
 *   close()             → void
 *   raw.run/get/all     → no transforms (escape hatch)
 */
import { createDbConnection } from "@finch/sqlite-wasm/db-connection";
import type { WasmDbConnection } from "@finch/sqlite-wasm/db-connection";

// ── Types ──────────────────────────────────────────────

export interface RunResult {
  lastID: number;
  changes: number;
}

export interface RawDb {
  /** run() without param transforms. */
  run(sql: string, params?: unknown[]): Promise<RunResult>;
  /** get() without row transforms — returns snake_case keys, raw strings. */
  get<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T | undefined>;
  /** all() without row transforms — returns snake_case keys, raw strings. */
  all<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
}

export interface DbConnection {
  /** Execute a write statement. Params auto-stringify objects/arrays. */
  run(sql: string, params?: unknown[]): Promise<RunResult>;

  /** Query a single row. Auto camelCase keys + JSON parse string values. */
  get<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T | undefined>;

  /** Query all matching rows. Auto camelCase keys + JSON parse string values. */
  all<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;

  /** Execute raw SQL (DDL, multi-statement). No return value. */
  exec(sql: string): Promise<void>;

  /** Close the database connection. */
  close(): Promise<void>;

  /** Escape hatch — no transforms, snake_case as-is. */
  raw: RawDb;
}

// ── Transforms ─────────────────────────────────────────

/** snake_case → camelCase */
export function snakeToCamel(s: string): string {
  return s.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
}

/** Try to parse a string as JSON if it looks like an object or array. */
function tryParseJson(value: unknown): unknown {
  if (typeof value !== "string") return value;
  const t = value.trim();
  if (
    (t.startsWith("{") && t.endsWith("}")) ||
    (t.startsWith("[") && t.endsWith("]"))
  ) {
    try {
      return JSON.parse(value);
    } catch {
      return value;
    }
  }
  return value;
}

/** Transform a DB row: snake_case → camelCase keys, JSON strings → parsed. */
export function transformRow<T = Record<string, unknown>>(
  row: Record<string, unknown>
): T {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) {
    out[snakeToCamel(k)] = tryParseJson(v);
  }
  return out as T;
}

/** Auto-stringify object/array params for JSONB columns. Skips Buffer/Uint8Array. */
export function prepareParams(params: unknown[]): unknown[] {
  return params.map((v) => {
    if (v === null || v === undefined) return v;
    if (v instanceof Buffer || v instanceof Uint8Array) return v;
    if (typeof v === "object") return JSON.stringify(v);
    return v;
  });
}

// ── Factory ────────────────────────────────────────────

/**
 * Create a new DbConnection. Opens/creates the database at `dbPath`.
 * sqlite-vec is statically linked — no extension loading needed.
 * Foreign keys are enabled automatically.
 *
 * @param dbPath — File path or ":memory:" for in-memory database.
 */
export async function createDb(dbPath: string): Promise<DbConnection> {
  const wasm = await createDbConnection(dbPath);

  // Enable foreign keys
  await wasm.exec("PRAGMA foreign_keys = ON");

  return wrapWasm(wasm);
}

// ── Internal helpers ───────────────────────────────────

function wrapWasm(wasm: WasmDbConnection): DbConnection {
  const raw: RawDb = {
    async run(sql: string, params: unknown[] = []): Promise<RunResult> {
      const result = await wasm.run(sql, params);
      return { lastID: result.lastInsertRowid, changes: result.changes };
    },

    get<T = Record<string, unknown>>(
      sql: string,
      params: unknown[] = []
    ): Promise<T | undefined> {
      return wasm.get(sql, params) as Promise<T | undefined>;
    },

    all<T = Record<string, unknown>>(
      sql: string,
      params: unknown[] = []
    ): Promise<T[]> {
      return wasm.all(sql, params) as Promise<T[]>;
    },
  };

  return {
    async run(sql: string, params: unknown[] = []): Promise<RunResult> {
      return raw.run(sql, prepareParams(params));
    },

    async get<T = Record<string, unknown>>(
      sql: string,
      params: unknown[] = []
    ): Promise<T | undefined> {
      const row = await raw.get(sql, prepareParams(params));
      return row ? transformRow<T>(row as Record<string, unknown>) : undefined;
    },

    async all<T = Record<string, unknown>>(
      sql: string,
      params: unknown[] = []
    ): Promise<T[]> {
      const rows = await raw.all(sql, prepareParams(params));
      return (rows as Record<string, unknown>[]).map((r) => transformRow<T>(r));
    },

    exec(sql: string): Promise<void> {
      return wasm.exec(sql);
    },

    close(): Promise<void> {
      return wasm.close();
    },

    raw,
  };
}
