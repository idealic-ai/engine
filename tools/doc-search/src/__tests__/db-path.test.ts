import { describe, it, expect, afterEach } from "vitest";
import { getDbPath } from "../db-path.js";

const ENV_KEY = "ENGINE_SEARCH_DB_PATH";

afterEach(() => {
  delete process.env[ENV_KEY];
});

describe("getDbPath", () => {
  it("returns ENGINE_SEARCH_DB_PATH verbatim when set", () => {
    // The wrapper .sh owns the DB location and exports it; the CLI must not
    // re-derive the path or the two can silently disagree.
    const wrapperPath = "/Users/x/.claude/cache/search-db/y/proj/sessions/.doc-search.db";
    process.env[ENV_KEY] = wrapperPath;
    expect(getDbPath()).toBe(wrapperPath);
  });

  it("falls back to a legacy path when unset", () => {
    // Direct `tsx cli.ts` invocations bypass the wrapper, so the previous
    // behaviour has to remain intact.
    const resolved = getDbPath();
    expect(resolved.endsWith(".doc-search.db")).toBe(true);
  });

  it("ignores an empty ENGINE_SEARCH_DB_PATH rather than returning an empty path", () => {
    process.env[ENV_KEY] = "";
    const resolved = getDbPath();
    expect(resolved.endsWith(".doc-search.db")).toBe(true);
    expect(resolved.length).toBeGreaterThan(".doc-search.db".length);
  });
});
