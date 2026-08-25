/**
 * The wrapper scripts (scripts/session-search.sh, scripts/doc-search.sh) are the
 * single source of truth for where a search DB lives — they derive the path via
 * scripts/search-db-lib.sh, perform any pending migration off the Google Drive
 * sessions mount, and export the result as ENGINE_SEARCH_DB_PATH.
 *
 * The CLIs only read that value. Do not re-derive the path in TypeScript: if the
 * two implementations ever disagree, a tool indexes into one file and reads from
 * another, with no error.
 */
const ENV_KEY = "ENGINE_SEARCH_DB_PATH";

/** The wrapper-supplied DB path, or null when invoked without the wrapper. */
export function dbPathFromEnv(): string | null {
  const value = process.env[ENV_KEY];
  return value && value.length > 0 ? value : null;
}
