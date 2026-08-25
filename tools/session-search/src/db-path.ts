import path from "node:path";
import { dbPathFromEnv } from "../../shared/db-path.js";

export const DB_FILENAME = ".session-search.db";

/**
 * Namespace used to PREFIX SESSION PATHS IN SEARCH RESULTS, so results from
 * several users' session trees stay distinguishable.
 * e.g., ".../Shared drives/finch-os/yarik/finch/sessions" -> "yarik/finch/sessions"
 * Falls back to "sessions" off Google Drive — correct here, because a shared
 * prefix on result paths is harmless.
 *
 * NOT the DB cache namespace. `search_db_namespace` in scripts/search-db-lib.sh
 * answers a different question — where the DB FILE lives — and deliberately uses
 * a project-scoped fallback, because a constant would collapse every off-Drive
 * project onto one cache file. Do not "unify" the two; they disagree on purpose.
 */
export function extractResultNamespace(resolvedPath: string): string {
  const marker = "finch-os/";
  const idx = resolvedPath.indexOf(marker);
  if (idx !== -1) {
    return resolvedPath.slice(idx + marker.length);
  }
  return "sessions";
}

/**
 * Where this run should read and write the DB.
 *
 * Lives in its own module (rather than cli.ts) because cli.ts calls main() at
 * import time — importing it from a test would execute the CLI.
 */
export function resolveDbPath(sessionsDir: string): string {
  return dbPathFromEnv() ?? path.join(sessionsDir, DB_FILENAME);
}
