/**
 * IDE-334 (RAGPROOFS): the search index's database.
 *
 * The same shape as doc-search's (tools/doc-search/src/db.ts): a content-addressed `embeddings` table whose
 * rows carry the model and width that made them, and a chunk table keyed by its item and section. It adds
 * an `items` table, one row per thing a person would open (an ask, a broadcast, a proof page), holding the
 * cheap change stamp the indexer compares, and a `meta` table for when the last pass ran.
 *
 * It uses node:sqlite rather than sql.js because the ask app runs under plain `node`, where sql.js is not
 * installed; the file is an ordinary SQLite database either way. WAL mode lets the server read while a CLI
 * pass writes. The default path is `<asks root>/.ask-app.search.db`: the server's watcher ignores names
 * that start with `.ask-app`, so the index's own writes never look like an ask changing.
 */
import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

export const SCHEMA_VERSION = 1;
export const DB_FILENAME = ".ask-app.search.db";

export type SearchDb = DatabaseSync;

/** ASK_SEARCH_DB, else `<root>/.ask-app.search.db`. */
export function searchDbPath(root: string): string {
  return process.env.ASK_SEARCH_DB || path.join(root, DB_FILENAME);
}

export class SearchDbError extends Error {}

/** Open (creating when absent) the index at `file`. A file at another schema version is refused, never dropped. */
export function openSearchDb(file: string, opts: { create?: boolean } = {}): SearchDb {
  const create = opts.create ?? true;
  if (!create && !fs.existsSync(file)) throw new SearchDbError("the search index has not been built yet");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec("PRAGMA busy_timeout = 5000; PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;");
  const v = (db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version;
  const empty = (db.prepare("SELECT count(*) AS n FROM sqlite_master").get() as { n: number }).n === 0;
  if (!empty && v !== SCHEMA_VERSION) {
    db.close();
    throw new SearchDbError(`the search index is at schema ${v}, this code reads ${SCHEMA_VERSION}; delete it and run \`engine ask search index\``);
  }
  db.exec(`
    PRAGMA user_version = ${SCHEMA_VERSION};
    CREATE TABLE IF NOT EXISTS embeddings (
      content_hash TEXT PRIMARY KEY,
      embedding BLOB NOT NULL,
      model TEXT NOT NULL,
      dimensions INTEGER NOT NULL CHECK (dimensions > 0),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      CHECK (length(embedding) = dimensions * 4)
    );
    CREATE TABLE IF NOT EXISTS items (
      key TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      kind TEXT NOT NULL,
      seat TEXT NOT NULL,
      id TEXT NOT NULL,
      title TEXT NOT NULL,
      status TEXT NOT NULL,
      url TEXT,
      app_path TEXT,
      stamp TEXT NOT NULL,
      text_hash TEXT NOT NULL,
      dup_of TEXT,
      indexed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_items_source ON items(source);
    CREATE INDEX IF NOT EXISTS idx_items_text_hash ON items(text_hash);
    CREATE TABLE IF NOT EXISTS chunks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_key TEXT NOT NULL REFERENCES items(key) ON DELETE CASCADE,
      section TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      body TEXT NOT NULL,
      UNIQUE (item_key, section)
    );
    CREATE INDEX IF NOT EXISTS idx_chunks_hash ON chunks(content_hash);
    CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
  `);
  return db;
}

export function getMeta(db: SearchDb, k: string): string | undefined {
  return (db.prepare("SELECT v FROM meta WHERE k = ?").get(k) as { v: string } | undefined)?.v;
}

export function setMeta(db: SearchDb, k: string, v: string): void {
  db.prepare("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v").run(k, v);
}

/** Run `fn` in one write transaction (BEGIN IMMEDIATE, so a second writer waits rather than failing late). */
export function inTransaction<T>(db: SearchDb, fn: () => T): T {
  db.exec("BEGIN IMMEDIATE");
  try {
    const out = fn();
    db.exec("COMMIT");
    return out;
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

export function float32ToBytes(a: Float32Array): Uint8Array {
  return new Uint8Array(a.buffer, a.byteOffset, a.byteLength);
}

export function bytesToFloat32(b: Uint8Array): Float32Array {
  const buf = new ArrayBuffer(b.byteLength);
  new Uint8Array(buf).set(b);
  return new Float32Array(buf);
}
