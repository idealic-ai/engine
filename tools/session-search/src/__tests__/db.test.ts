import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { initDb, saveDb, SCHEMA_VERSION, EMBEDDING_DIMENSIONS } from "../db.js";

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

  it("should create database and return a connection", async () => {
    const dbPath = makeTmpDbPath();
    const db = await initDb(dbPath);
    expect(db).toBeDefined();
    db.close();
  });

  it("should create the chunks metadata table", async () => {
    const dbPath = makeTmpDbPath();
    const db = await initDb(dbPath);

    const result = db.exec(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='chunks'"
    );
    expect(result).toHaveLength(1);
    expect(result[0].values[0][0]).toBe("chunks");
    db.close();
  });

  it("should create the embeddings table", async () => {
    const dbPath = makeTmpDbPath();
    const db = await initDb(dbPath);

    const result = db.exec(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='embeddings'"
    );
    expect(result).toHaveLength(1);
    expect(result[0].values[0][0]).toBe("embeddings");
    db.close();
  });

  it("should have embeddings table with correct schema", async () => {
    const dbPath = makeTmpDbPath();
    const db = await initDb(dbPath);

    const result = db.exec("PRAGMA table_info(embeddings)");
    const columns = result[0].values.map((row) => ({
      name: row[1] as string,
      type: row[2] as string,
    }));

    const chunkIdCol = columns.find((c) => c.name === "chunk_id");
    expect(chunkIdCol).toBeDefined();
    expect(chunkIdCol!.type).toBe("INTEGER");

    const embeddingCol = columns.find((c) => c.name === "embedding");
    expect(embeddingCol).toBeDefined();
    expect(embeddingCol!.type).toBe("BLOB");
    db.close();
  });

  it("should be idempotent — calling initDb twice works", async () => {
    const dbPath = makeTmpDbPath();
    const db1 = await initDb(dbPath);
    db1.close();

    const db2 = await initDb(dbPath);
    const result = db2.exec(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='chunks'"
    );
    expect(result).toHaveLength(1);
    db2.close();
  });

  it("should include session_date NOT NULL column in chunks table", async () => {
    const dbPath = makeTmpDbPath();
    const db = await initDb(dbPath);

    const result = db.exec("PRAGMA table_info(chunks)");
    const columns = result[0].values.map((row) => ({
      name: row[1] as string,
      notnull: row[3] as number,
    }));

    const sessionDateCol = columns.find((c) => c.name === "session_date");
    expect(sessionDateCol).toBeDefined();
    expect(sessionDateCol!.notnull).toBe(1);
    db.close();
  });

  it("should create unique index on file_path + section_title", async () => {
    const dbPath = makeTmpDbPath();
    const db = await initDb(dbPath);

    const result = db.exec(
      "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_chunks_path_section'"
    );
    expect(result).toHaveLength(1);
    db.close();
  });

  it("is at schema 3, with 768 as the default width", () => {
    expect(SCHEMA_VERSION).toBe(3);
    expect(EMBEDDING_DIMENSIONS).toBe(768);
  });

  it("embedding rows carry NOT NULL model and dimensions columns", async () => {
    const db = await initDb(makeTmpDbPath());
    const cols = db.exec("PRAGMA table_info(embeddings)")[0].values.map((r) => [r[1], r[3]]);
    expect(cols).toEqual(expect.arrayContaining([["model", 1], ["dimensions", 1]]));
    db.close();
  });

  it("refuses a schema-2 (Gemini 3072-d) image and leaves the file byte-identical", async () => {
    const dbPath = makeTmpDbPath();
    const db1 = await initDb(dbPath);
    db1.run("INSERT INTO chunks (session_path, session_date, file_path, section_title, content, content_hash) VALUES ('s','d','f','t','c','h')");
    db1.run("PRAGMA user_version = 2;");
    saveDb(db1, dbPath);
    db1.close();
    const before = fs.readFileSync(dbPath);

    await expect(initDb(dbPath)).rejects.toThrow(/Gemini-era index \(schema 2\)/);
    expect(fs.readFileSync(dbPath).equals(before)).toBe(true);
  });

  it("still drops and recreates on a non-Gemini version mismatch", async () => {
    const dbPath = makeTmpDbPath();
    const db1 = await initDb(dbPath);
    db1.run("INSERT INTO chunks (session_path, session_date, file_path, section_title, content, content_hash) VALUES ('s','d','f','t','c','h')");
    db1.run("PRAGMA user_version = 99;");
    saveDb(db1, dbPath);
    db1.close();

    const db2 = await initDb(dbPath);
    expect(db2.exec("SELECT COUNT(*) FROM chunks")[0].values[0][0]).toBe(0);
    expect(db2.exec("PRAGMA user_version;")[0].values[0][0]).toBe(3);
    db2.close();
  });
});
