import initSqlJs, { type Database, type SqlValue } from "sql.js";
import * as fs from "node:fs";
import * as path from "node:path";

export const EMBEDDING_DIMENSIONS = 3072;

/**
 * Schema version — bump this when table structure changes.
 * On open, if the DB's PRAGMA user_version doesn't match,
 * all tables are dropped and recreated (reindex required).
 */
export const SCHEMA_VERSION = 1;

export type { Database };

let SQL: Awaited<ReturnType<typeof initSqlJs>> | null = null;

/**
 * Initialize sql.js WASM module (cached after first call).
 */
async function getSqlJs(): Promise<NonNullable<typeof SQL>> {
  if (!SQL) {
    SQL = await initSqlJs();
  }
  return SQL;
}

/**
 * Initialize or open a database at the given path.
 * Uses sql.js (WASM-based SQLite) for cross-platform compatibility.
 */
export async function initDb(dbPath: string): Promise<Database> {
  const SqlJs = await getSqlJs();

  let db: Database;

  // Ensure directory exists
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  // Load existing database if it exists
  if (fs.existsSync(dbPath)) {
    const buffer = fs.readFileSync(dbPath);
    db = new SqlJs.Database(buffer);

    // Check schema version — drop and recreate if mismatched
    const result = db.exec("PRAGMA user_version;");
    const dbVersion = result[0]?.values[0]?.[0] as number ?? 0;
    if (dbVersion !== SCHEMA_VERSION) {
      console.error(
        `[doc-search] Schema version mismatch (db=${dbVersion}, expected=${SCHEMA_VERSION}). Dropping tables and reindexing.`
      );
      db.run("DROP TABLE IF EXISTS doc_chunks;");
      db.run("DROP TABLE IF EXISTS embeddings;");
    }
  } else {
    db = new SqlJs.Database();
  }

  // Set schema version
  db.run(`PRAGMA user_version = ${SCHEMA_VERSION};`);

  // Create embeddings table (content-addressed, global)
  db.run(`
    CREATE TABLE IF NOT EXISTS embeddings (
      content_hash TEXT PRIMARY KEY,
      embedding BLOB NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  // Create doc_chunks table
  db.run(`
    CREATE TABLE IF NOT EXISTS doc_chunks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project_name TEXT NOT NULL,
      branch TEXT NOT NULL,
      file_path TEXT NOT NULL,
      section_title TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      mtime INTEGER NOT NULL,
      snippet TEXT,
      indexed_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (content_hash) REFERENCES embeddings(content_hash)
    );
  `);

  // Create unique index on project+branch+file+section
  db.run(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_doc_chunks_unique
      ON doc_chunks(project_name, branch, file_path, section_title);
  `);

  // Create index for efficient branch queries
  db.run(`
    CREATE INDEX IF NOT EXISTS idx_doc_chunks_project_branch
      ON doc_chunks(project_name, branch);
  `);

  return db;
}

/**
 * Save database to disk.
 */
export function saveDb(db: Database, dbPath: string): void {
  const data = db.export();
  const buffer = Buffer.from(data);

  // Ensure directory exists
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  fs.writeFileSync(dbPath, buffer);
}

/**
 * Convert Float32Array to Uint8Array for storage.
 */
export function float32ToBytes(arr: Float32Array): Uint8Array {
  return new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength);
}

/**
 * Convert Uint8Array back to Float32Array.
 */
export function bytesToFloat32(bytes: Uint8Array): Float32Array {
  // Create a copy to ensure proper alignment
  const buffer = new ArrayBuffer(bytes.length);
  new Uint8Array(buffer).set(bytes);
  return new Float32Array(buffer);
}

/**
 * Compute cosine similarity between two vectors.
 * Returns value between -1 and 1 (1 = identical).
 */
export function cosineSimilarity(a: Float32Array, b: Float32Array): number {
  if (a.length !== b.length) {
    throw new Error(`Vector length mismatch: ${a.length} vs ${b.length}`);
  }

  let dotProduct = 0;
  let normA = 0;
  let normB = 0;

  for (let i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  const magnitude = Math.sqrt(normA) * Math.sqrt(normB);
  if (magnitude === 0) return 0;

  return dotProduct / magnitude;
}

/**
 * Convert cosine similarity to distance (for compatibility with existing code).
 * Distance = 1 - similarity (0 = identical, 2 = opposite).
 */
export function similarityToDistance(similarity: number): number {
  return 1 - similarity;
}

/**
 * Execute a query and return all rows as objects.
 */
export function queryAll<T>(db: Database, sql: string, params: SqlValue[] = []): T[] {
  const stmt = db.prepare(sql);
  stmt.bind(params);

  const results: T[] = [];
  while (stmt.step()) {
    results.push(stmt.getAsObject() as T);
  }
  stmt.free();

  return results;
}

/**
 * Execute a query and return the first row as an object.
 */
export function queryOne<T>(db: Database, sql: string, params: SqlValue[] = []): T | undefined {
  const stmt = db.prepare(sql);
  stmt.bind(params);

  let result: T | undefined;
  if (stmt.step()) {
    result = stmt.getAsObject() as T;
  }
  stmt.free();

  return result;
}

/**
 * Execute an INSERT/UPDATE/DELETE statement.
 */
export function execute(db: Database, sql: string, params: SqlValue[] = []): void {
  db.run(sql, params);
}
