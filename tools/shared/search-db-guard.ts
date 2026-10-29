/**
 * What both search tools refuse to open, decided before any DB is loaded.
 *
 * Two refusals, both of which leave the file on disk byte-identical:
 *
 * 1. A path whose basename is a Gemini-era file name (`.session-search.db`,
 *    `.doc-search.db`). An old scripts/search-db-lib.sh paired with this code
 *    still exports those names. Without this check the new code would create a
 *    fresh local-embeddings index under the old name, stranded where no current
 *    wrapper looks (this happened to kit on 2026-10-29), or open an old file.
 *
 * 2. Any existing image whose PRAGMA user_version is not exactly this build's
 *    schema: 0 (unversioned, before a76a78f), a Gemini-era version, or a newer
 *    version (a rollback to this build). The only reset is a deliberate one:
 *    `engine reindex`, which deletes the file.
 *
 * The version is read from the 100-byte SQLite header (user_version is the
 * big-endian u32 at offset 60), so refusing a 2 GB file costs one small read
 * rather than loading the whole image into memory.
 */
import fs from "node:fs";
import path from "node:path";

/** The file names the Gemini-era tools used. New code never reads or writes them. */
export const LEGACY_DB_BASENAMES: readonly string[] = [".session-search.db", ".doc-search.db"];

export class SearchDbRefused extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SearchDbRefused";
  }
}

export function isSearchDbRefused(err: unknown): err is SearchDbRefused {
  return err instanceof SearchDbRefused;
}

/** Throw SearchDbRefused when `dbPath` names a Gemini-era file. */
export function assertLocalDbPath(tool: string, dbPath: string, hint: string): void {
  const base = path.basename(dbPath);
  if (LEGACY_DB_BASENAMES.includes(base)) {
    throw new SearchDbRefused(
      `[${tool}] Refusing ${dbPath}: ${base} is a Gemini-era file name, and this build embeds locally. ` +
        `It will neither open nor create a file under that name. Point ENGINE_SEARCH_DB_PATH at ${hint} ` +
        `(the wrappers do when scripts/search-db-lib.sh is the same version as this tool).`
    );
  }
}

export const SQLITE_HEADER_BYTES = 100;
const SQLITE_MAGIC = "SQLite format 3\u0000";
const USER_VERSION_OFFSET = 60;

export type SqliteHeader =
  | { kind: "empty" }
  | { kind: "not-sqlite" }
  | { kind: "sqlite"; userVersion: number };

/** Read only the SQLite header of an existing file. */
export function readSqliteHeader(dbPath: string): SqliteHeader {
  const fd = fs.openSync(dbPath, "r");
  try {
    const header = Buffer.alloc(SQLITE_HEADER_BYTES);
    const read = fs.readSync(fd, header, 0, SQLITE_HEADER_BYTES, 0);
    if (read === 0) return { kind: "empty" };
    if (read < SQLITE_HEADER_BYTES || header.toString("latin1", 0, SQLITE_MAGIC.length) !== SQLITE_MAGIC) {
      return { kind: "not-sqlite" };
    }
    return { kind: "sqlite", userVersion: header.readUInt32BE(USER_VERSION_OFFSET) };
  } finally {
    fs.closeSync(fd);
  }
}

export interface SchemaExpectation {
  tool: string;
  /** The one version this build reads and writes. */
  schemaVersion: number;
  /** The first version of the local-embeddings generation. Below it is Gemini-era. */
  firstLocalSchemaVersion: number;
  /** The current file name, for the message. */
  hint: string;
}

/**
 * Decide whether an existing file may be opened, from its header alone.
 * Returns "fresh" for a missing or zero-length file (safe to create), "current"
 * for this build's schema, and throws SearchDbRefused for anything else.
 */
export function checkExistingDb(dbPath: string, expect: SchemaExpectation): "fresh" | "current" {
  if (!fs.existsSync(dbPath)) return "fresh";
  const header = readSqliteHeader(dbPath);
  if (header.kind === "empty") return "fresh";

  const { tool, schemaVersion, firstLocalSchemaVersion, hint } = expect;
  const leave = `It will not open or overwrite it, and the file is unchanged.`;
  const reset = `To start over on purpose, run \`engine reindex\`, which deletes the index file.`;

  if (header.kind === "not-sqlite") {
    throw new SearchDbRefused(`[${tool}] ${dbPath} is not a SQLite database. ${leave} ${reset}`);
  }

  const v = header.userVersion;
  if (v === schemaVersion) return "current";

  let what: string;
  if (v === 0) {
    what = `an unversioned index (user_version 0: built before schema versioning, so Gemini-era, or not this tool's)`;
  } else if (v < firstLocalSchemaVersion) {
    what = `a Gemini-era index (schema ${v})`;
  } else if (v > schemaVersion) {
    what = `an index from a newer build (schema ${v}); this build is older, as after a rollback`;
  } else {
    what = `an index at schema ${v}, which this build does not read`;
  }
  throw new SearchDbRefused(
    `[${tool}] ${dbPath} is ${what}; this build embeds locally (schema ${schemaVersion}). ${leave} ` +
      `Point ENGINE_SEARCH_DB_PATH at ${hint} built by this version. ${reset}`
  );
}
