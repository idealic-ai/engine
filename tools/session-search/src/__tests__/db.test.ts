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
});
