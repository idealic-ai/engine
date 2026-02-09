import initSqlJs, { type Database } from "sql.js";
import * as fs from "fs";
import * as path from "path";

export const EMBEDDING_DIMENSIONS = 3072;

let SQL: Awaited<ReturnType<typeof initSqlJs>> | null = null;

/**
 * Initialize sql.js WASM module (cached after first call).
 */
async function getSqlJs(): Promise<typeof SQL> {
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
  if (!SqlJs) throw new Error("Failed to initialize sql.js");

  let db: Database;

  // Load existing database if it exists
  if (fs.existsSync(dbPath)) {
    const buffer = fs.readFileSync(dbPath);
    db = new SqlJs.Database(buffer);
  } else {
    db = new SqlJs.Database();
  }

  // Create metadata table
  db.run(`
    CREATE TABLE IF NOT EXISTS chunks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_path TEXT NOT NULL,
      session_date TEXT NOT NULL,
      file_path TEXT NOT NULL,
      section_title TEXT NOT NULL,
      content TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  // Create unique index on file_path + section_title
  db.run(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_chunks_path_section
      ON chunks(file_path, section_title);
  `);

  // Create embeddings table (replaces sqlite-vec virtual table)
  // Embeddings stored as BLOB (raw Float32Array bytes)
  db.run(`
    CREATE TABLE IF NOT EXISTS embeddings (
      chunk_id INTEGER PRIMARY KEY,
      embedding BLOB NOT NULL,
      FOREIGN KEY (chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
    );
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
