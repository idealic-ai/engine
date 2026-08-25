import { describe, it, expect, afterEach } from "vitest";
import path from "node:path";
import { resolveDbPath } from "../db-path.js";

const ENV_KEY = "ENGINE_SEARCH_DB_PATH";

afterEach(() => {
  delete process.env[ENV_KEY];
});

describe("resolveDbPath", () => {
  it("returns ENGINE_SEARCH_DB_PATH verbatim when set", () => {
    // The wrapper .sh is the single source of truth for the DB location; the
    // CLI must not second-guess it or re-derive the path.
    const wrapperPath = "/Users/x/.claude/cache/search-db/y/proj/sessions/.session-search.db";
    process.env[ENV_KEY] = wrapperPath;
    expect(resolveDbPath("/anywhere/else/sessions")).toBe(wrapperPath);
  });

  it("falls back to the legacy in-sessions path when unset", () => {
    // Preserves today's behaviour for direct `tsx cli.ts` invocations, which
    // bypass the wrapper and therefore never get the env var.
    const sessionsDir = "/anywhere/else/sessions";
    expect(resolveDbPath(sessionsDir)).toBe(
      path.join(sessionsDir, ".session-search.db"),
    );
  });

  it("ignores an empty ENGINE_SEARCH_DB_PATH rather than returning an empty path", () => {
    process.env[ENV_KEY] = "";
    const sessionsDir = "/anywhere/else/sessions";
    expect(resolveDbPath(sessionsDir)).toBe(
      path.join(sessionsDir, ".session-search.db"),
    );
  });
});
