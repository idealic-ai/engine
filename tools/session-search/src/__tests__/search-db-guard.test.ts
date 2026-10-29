/**
 * tools/shared/search-db-guard.ts: the refusals both search tools apply before
 * any DB is loaded. Lives in session-search's suite because tools/shared has
 * no test runner of its own.
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  assertLocalDbPath,
  checkExistingDb,
  readSqliteHeader,
  LEGACY_DB_BASENAMES,
} from "../../../shared/search-db-guard.js";

let dir: string;
beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "search-db-guard-"));
});
afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

/** A 100-byte SQLite header with `userVersion` at offset 60, plus a page of junk. */
function headerFile(userVersion: number, name = "x.local.db"): string {
  const buf = Buffer.alloc(4096);
  buf.write("SQLite format 3\u0000", 0, "latin1");
  buf.writeUInt32BE(userVersion, 60);
  const p = path.join(dir, name);
  fs.writeFileSync(p, buf);
  return p;
}

const expectation = { tool: "t", schemaVersion: 3, firstLocalSchemaVersion: 3, hint: ".t.local.db" };

describe("search-db-guard", () => {
  it("names exactly the two Gemini-era files", () => {
    expect([...LEGACY_DB_BASENAMES].sort()).toEqual([".doc-search.db", ".session-search.db"]);
  });

  it("assertLocalDbPath refuses both old names and passes the .local.db names", () => {
    expect(() => assertLocalDbPath("t", "/a/.session-search.db", "h")).toThrow(/Gemini-era file name/);
    expect(() => assertLocalDbPath("t", "/a/.doc-search.db", "h")).toThrow(/Gemini-era file name/);
    expect(() => assertLocalDbPath("t", "/a/.session-search.local.db", "h")).not.toThrow();
    expect(() => assertLocalDbPath("t", "/a/.doc-search.local.db", "h")).not.toThrow();
  });

  it("reads user_version as the big-endian u32 at offset 60", () => {
    expect(readSqliteHeader(headerFile(3))).toEqual({ kind: "sqlite", userVersion: 3 });
    expect(readSqliteHeader(headerFile(0x01020304))).toEqual({ kind: "sqlite", userVersion: 0x01020304 });
  });

  it("tells an empty file and a non-SQLite file apart", () => {
    const empty = path.join(dir, "empty.db");
    fs.writeFileSync(empty, "");
    const junk = path.join(dir, "junk.db");
    fs.writeFileSync(junk, "not a database at all, but longer than nothing".repeat(5));
    expect(readSqliteHeader(empty)).toEqual({ kind: "empty" });
    expect(readSqliteHeader(junk)).toEqual({ kind: "not-sqlite" });
  });

  it("checkExistingDb: missing or empty is fresh, the current schema is current", () => {
    expect(checkExistingDb(path.join(dir, "absent.db"), expectation)).toBe("fresh");
    const empty = path.join(dir, "empty.db");
    fs.writeFileSync(empty, "");
    expect(checkExistingDb(empty, expectation)).toBe("fresh");
    expect(checkExistingDb(headerFile(3), expectation)).toBe("current");
  });

  it("checkExistingDb refuses every other version, each with its own reason", () => {
    expect(() => checkExistingDb(headerFile(0), expectation)).toThrow(/unversioned index/);
    expect(() => checkExistingDb(headerFile(2), expectation)).toThrow(/Gemini-era index \(schema 2\)/);
    expect(() => checkExistingDb(headerFile(4), expectation)).toThrow(/newer build \(schema 4\)/);
    expect(() => checkExistingDb(headerFile(99), expectation)).toThrow(/newer build \(schema 99\)/);
  });

  it("checkExistingDb refuses a file that is not SQLite", () => {
    const junk = path.join(dir, "junk.db");
    fs.writeFileSync(junk, "x".repeat(200));
    expect(() => checkExistingDb(junk, expectation)).toThrow(/is not a SQLite database/);
  });
});
