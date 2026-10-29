import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { initDb, saveDb, SCHEMA_VERSION, EMBEDDING_DIMENSIONS } from "../db.js";
import { isSearchDbRefused } from "../../../shared/search-db-guard.js";

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

  /** A real image at `version`, holding one row of "precious" content. */
  async function imageAt(version: number): Promise<{ dbPath: string; before: Buffer }> {
    const dbPath = makeTmpDbPath();
    const db1 = await initDb(dbPath);
    db1.run("INSERT INTO chunks (session_path, session_date, file_path, section_title, content, content_hash) VALUES ('s','d','f','t','precious','h')");
    db1.run(`PRAGMA user_version = ${version};`);
    saveDb(db1, dbPath);
    db1.close();
    return { dbPath, before: fs.readFileSync(dbPath) };
  }

  // S1: schema 0 (Gemini DBs built before a76a78f carried no version) and any
  // newer schema (a rollback to this build) used to be dropped and overwritten.
  it("refuses an unversioned (user_version 0) image and leaves it byte-identical", async () => {
    const { dbPath, before } = await imageAt(0);
    await expect(initDb(dbPath)).rejects.toThrow(/unversioned index \(user_version 0/);
    expect(fs.readFileSync(dbPath).equals(before)).toBe(true);
  });

  it("refuses an image from a newer schema and leaves it byte-identical", async () => {
    const { dbPath, before } = await imageAt(SCHEMA_VERSION + 1);
    await expect(initDb(dbPath)).rejects.toThrow(/newer build \(schema 4\).*rollback/);
    expect(fs.readFileSync(dbPath).equals(before)).toBe(true);
  });

  it("names `engine reindex` as the only reset", async () => {
    const { dbPath } = await imageAt(99);
    await expect(initDb(dbPath)).rejects.toThrow(/engine reindex/);
  });

  it("refusals are SearchDbRefused, so the CLIs print them without a stack", async () => {
    const { dbPath } = await imageAt(0);
    const err = await initDb(dbPath).catch((e: unknown) => e);
    expect(isSearchDbRefused(err)).toBe(true);
  });

  it("opens a zero-length file as a fresh index", async () => {
    const dbPath = makeTmpDbPath();
    fs.writeFileSync(dbPath, "");
    const db = await initDb(dbPath);
    expect(db.exec("PRAGMA user_version;")[0].values[0][0]).toBe(SCHEMA_VERSION);
    db.close();
  });

  // M1: an old search-db-lib.sh exports the Gemini-era name; new code must not
  // create a local index there (kit's 52,900-chunk build was stranded that way).
  it("refuses the Gemini-era file name and creates nothing there", async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "session-search-name-"));
    const dbPath = path.join(dir, ".session-search.db");
    await expect(initDb(dbPath)).rejects.toThrow(/\.session-search\.db is a Gemini-era file name/);
    expect(fs.existsSync(dbPath)).toBe(false);
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("refuses doc-search's Gemini-era file name too", async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "session-search-name-"));
    await expect(initDb(path.join(dir, ".doc-search.db"))).rejects.toThrow(/Gemini-era file name/);
    fs.rmSync(dir, { recursive: true, force: true });
  });

  // S2: the version comes from the 100-byte header. A file over 2 GiB cannot
  // even be read whole (ERR_FS_FILE_TOO_LARGE), so this only passes when the
  // refusal happens before the full read. The file is sparse: no real disk use.
  it("refuses a 3 GiB Gemini-era file from its header, without loading it", async () => {
    const { dbPath } = await imageAt(2);
    fs.truncateSync(dbPath, 3 * 1024 ** 3);
    const t0 = Date.now();
    await expect(initDb(dbPath)).rejects.toThrow(/Gemini-era index \(schema 2\)/);
    expect(Date.now() - t0).toBeLessThan(5000);
  });
});
