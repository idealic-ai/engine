import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { initDb } from "../db.js";

describe("db", () => {
  const tmpDbs: string[] = [];

  function makeTmpDbPath(): string {
    const p = path.join(
      os.tmpdir(),
      `session-search-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
    );
    tmpDbs.push(p);
    return p;
  }

  afterEach(() => {
    for (const p of tmpDbs) {
      try {
        fs.unlinkSync(p);
      } catch {
        // ignore
      }
    }
    tmpDbs.length = 0;
  });

  it("should create database and return a connection", () => {
    const dbPath = makeTmpDbPath();
    const db = initDb(dbPath);
    expect(db).toBeDefined();
    expect(db.open).toBe(true);
    db.close();
  });

  it("should create the chunks metadata table", () => {
    const dbPath = makeTmpDbPath();
    const db = initDb(dbPath);

    const tables = db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='chunks'"
      )
      .all() as Array<{ name: string }>;
    expect(tables).toHaveLength(1);
    expect(tables[0].name).toBe("chunks");
    db.close();
  });

  it("should create the vec_chunks virtual table", () => {
    const dbPath = makeTmpDbPath();
    const db = initDb(dbPath);

    const tables = db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='vec_chunks'"
      )
      .all() as Array<{ name: string }>;
    expect(tables).toHaveLength(1);
    expect(tables[0].name).toBe("vec_chunks");
    db.close();
  });

  it("should load sqlite-vec extension and return version", () => {
    const dbPath = makeTmpDbPath();
    const db = initDb(dbPath);

    const result = db.prepare("SELECT vec_version() as version").get() as {
      version: string;
    };
    expect(result.version).toBeTruthy();
    expect(typeof result.version).toBe("string");
    db.close();
  });

  it("should use DELETE journal mode for Google Drive compatibility", () => {
    const dbPath = makeTmpDbPath();
    const db = initDb(dbPath);

    const result = db.prepare("PRAGMA journal_mode").get() as {
      journal_mode: string;
    };
    expect(result.journal_mode).toBe("delete");
    db.close();
  });

  it("should be idempotent — calling initDb twice works", () => {
    const dbPath = makeTmpDbPath();
    const db1 = initDb(dbPath);
    db1.close();

    const db2 = initDb(dbPath);
    expect(db2.open).toBe(true);

    const tables = db2
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='chunks'"
      )
      .all() as Array<{ name: string }>;
    expect(tables).toHaveLength(1);
    db2.close();
  });

  it("should include session_date NOT NULL column in chunks table", () => {
    const dbPath = makeTmpDbPath();
    const db = initDb(dbPath);

    const columns = db
      .prepare("PRAGMA table_info(chunks)")
      .all() as Array<{ name: string; notnull: number }>;

    const sessionDateCol = columns.find((c) => c.name === "session_date");
    expect(sessionDateCol).toBeDefined();
    expect(sessionDateCol!.notnull).toBe(1);
    db.close();
  });

  it("should create unique index on file_path + section_title", () => {
    const dbPath = makeTmpDbPath();
    const db = initDb(dbPath);

    const indexes = db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_chunks_path_section'"
      )
      .all() as Array<{ name: string }>;
    expect(indexes).toHaveLength(1);
    db.close();
  });
});
