import { describe, it, expect, afterEach, vi } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { initDb } from "../db.js";
import { reconcileChunks, type IndexReport } from "../indexer.js";
import type { Chunk } from "../chunker.js";
import type { EmbeddingClient } from "../embed.js";

function makeTmpDbPath(): string {
  return path.join(
    os.tmpdir(),
    `session-search-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
  );
}

function makeMockEmbedder(model = "embeddinggemma", dimensions = 768): EmbeddingClient {
  // Returns a deterministic fake embedding based on the text length
  return {
    model,
    dimensions,
    async embedTexts(texts: string[]): Promise<Float32Array[]> {
      return texts.map((t) => {
        const arr = new Float32Array(dimensions);
        // Fill with a simple pattern derived from text length
        for (let i = 0; i < arr.length; i++) {
          arr[i] = (t.length + i) / 10000;
        }
        return arr;
      });
    },
    async embedSingle(text: string): Promise<Float32Array> {
      const arr = new Float32Array(dimensions);
      for (let i = 0; i < arr.length; i++) {
        arr[i] = (text.length + i) / 10000;
      }
      return arr;
    },
  };
}

describe("indexer - reconcileChunks", () => {
  const tmpDbs: string[] = [];

  async function setupDb() {
    const p = makeTmpDbPath();
    tmpDbs.push(p);
    const db = await initDb(p);
    return { db, dbPath: p };
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

  it("should insert new chunks into empty database", async () => {
    const { db, dbPath } = await setupDb();
    const embedder = makeMockEmbedder();

    const chunks: Chunk[] = [
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/BRAINSTORM.md",
        sectionTitle: "Section One",
        content: "Content of section one.",
        contentHash: "hash_one",
      },
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/BRAINSTORM.md",
        sectionTitle: "Section Two",
        content: "Content of section two.",
        contentHash: "hash_two",
      },
    ];

    const report = await reconcileChunks(db, dbPath, chunks, embedder);

    expect(report.inserted).toBe(2);
    expect(report.updated).toBe(0);
    expect(report.skipped).toBe(0);
    expect(report.deleted).toBe(0);

    // Verify data in DB
    const rowsResult = db.exec("SELECT * FROM chunks");
    expect(rowsResult).toHaveLength(1);
    expect(rowsResult[0].values).toHaveLength(2);

    // Verify embeddings exist
    const embResult = db.exec("SELECT chunk_id FROM embeddings");
    expect(embResult).toHaveLength(1);
    expect(embResult[0].values).toHaveLength(2);

    db.close();
  });

  it("should skip unchanged chunks", async () => {
    const { db, dbPath } = await setupDb();
    const embedder = makeMockEmbedder();

    const chunks: Chunk[] = [
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/BRAINSTORM.md",
        sectionTitle: "Section One",
        content: "Content of section one.",
        contentHash: "hash_one",
      },
    ];

    // First run — insert
    await reconcileChunks(db, dbPath, chunks, embedder);

    // Second run — same chunks, should skip
    const report = await reconcileChunks(db, dbPath, chunks, embedder);

    expect(report.inserted).toBe(0);
    expect(report.updated).toBe(0);
    expect(report.skipped).toBe(1);
    expect(report.deleted).toBe(0);

    db.close();
  });

  it("should update changed chunks", async () => {
    const { db, dbPath } = await setupDb();
    const embedder = makeMockEmbedder();

    const chunks: Chunk[] = [
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/BRAINSTORM.md",
        sectionTitle: "Section One",
        content: "Original content.",
        contentHash: "hash_original",
      },
    ];

    // First run — insert
    await reconcileChunks(db, dbPath, chunks, embedder);

    // Second run — changed hash
    const updatedChunks: Chunk[] = [
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/BRAINSTORM.md",
        sectionTitle: "Section One",
        content: "Updated content.",
        contentHash: "hash_updated",
      },
    ];

    const report = await reconcileChunks(db, dbPath, updatedChunks, embedder);

    expect(report.inserted).toBe(0);
    expect(report.updated).toBe(1);
    expect(report.skipped).toBe(0);
    expect(report.deleted).toBe(0);

    // Verify content updated
    const result = db.exec("SELECT content_hash FROM chunks WHERE section_title = 'Section One'");
    expect(result).toHaveLength(1);
    expect(result[0].values[0][0]).toBe("hash_updated");

    db.close();
  });

  it("should delete orphaned chunks", async () => {
    const { db, dbPath } = await setupDb();
    const embedder = makeMockEmbedder();

    const chunks: Chunk[] = [
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/BRAINSTORM.md",
        sectionTitle: "Section One",
        content: "Content one.",
        contentHash: "hash_one",
      },
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/BRAINSTORM.md",
        sectionTitle: "Section Two",
        content: "Content two.",
        contentHash: "hash_two",
      },
    ];

    // First run — insert both
    await reconcileChunks(db, dbPath, chunks, embedder);

    // Second run — only one chunk remains (section two was deleted from file)
    const remainingChunks: Chunk[] = [
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/BRAINSTORM.md",
        sectionTitle: "Section One",
        content: "Content one.",
        contentHash: "hash_one",
      },
    ];

    const report = await reconcileChunks(db, dbPath, remainingChunks, embedder);

    expect(report.inserted).toBe(0);
    expect(report.updated).toBe(0);
    expect(report.skipped).toBe(1);
    expect(report.deleted).toBe(1);

    // Verify only one chunk remains
    const result = db.exec("SELECT * FROM chunks");
    expect(result).toHaveLength(1);
    expect(result[0].values).toHaveLength(1);

    db.close();
  });

  it("should handle mixed operations: insert + skip + update + delete", async () => {
    const { db, dbPath } = await setupDb();
    const embedder = makeMockEmbedder();

    const initialChunks: Chunk[] = [
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/FILE.md",
        sectionTitle: "Unchanged",
        content: "Same content.",
        contentHash: "hash_same",
      },
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/FILE.md",
        sectionTitle: "Will Change",
        content: "Old content.",
        contentHash: "hash_old",
      },
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/FILE.md",
        sectionTitle: "Will Delete",
        content: "Doomed content.",
        contentHash: "hash_doomed",
      },
    ];

    await reconcileChunks(db, dbPath, initialChunks, embedder);

    // Second round: Unchanged stays, Will Change is modified, Will Delete is gone, New appears
    const updatedChunks: Chunk[] = [
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/FILE.md",
        sectionTitle: "Unchanged",
        content: "Same content.",
        contentHash: "hash_same",
      },
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/FILE.md",
        sectionTitle: "Will Change",
        content: "New content.",
        contentHash: "hash_new",
      },
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/FILE.md",
        sectionTitle: "Brand New",
        content: "Fresh content.",
        contentHash: "hash_fresh",
      },
    ];

    const report = await reconcileChunks(db, dbPath, updatedChunks, embedder);

    expect(report.inserted).toBe(1); // Brand New
    expect(report.updated).toBe(1); // Will Change
    expect(report.skipped).toBe(1); // Unchanged
    expect(report.deleted).toBe(1); // Will Delete

    const result = db.exec("SELECT section_title FROM chunks ORDER BY section_title");
    expect(result).toHaveLength(1);
    expect(result[0].values).toHaveLength(3);
    expect(result[0].values.map((r) => r[0])).toEqual([
      "Brand New",
      "Unchanged",
      "Will Change",
    ]);

    db.close();
  });

  it("should handle empty chunk list (delete all)", async () => {
    const { db, dbPath } = await setupDb();
    const embedder = makeMockEmbedder();

    const chunks: Chunk[] = [
      {
        sessionPath: "sessions/2026_02_04_TEST",
        sessionDate: "2026-02-04",
        filePath: "sessions/2026_02_04_TEST/FILE.md",
        sectionTitle: "Section",
        content: "Content.",
        contentHash: "hash_x",
      },
    ];

    await reconcileChunks(db, dbPath, chunks, embedder);

    // Pass empty chunks — should delete everything
    const report = await reconcileChunks(db, dbPath, [], embedder);

    expect(report.inserted).toBe(0);
    expect(report.deleted).toBe(1);

    const result = db.exec("SELECT * FROM chunks");
    // Empty result set — no rows
    expect(result.length === 0 || result[0].values.length === 0).toBe(true);

    db.close();
  });

  describe("generation guard — a mixed index cannot recur", () => {
    const chunk = (hash: string, title = "Section"): Chunk => ({
      sessionPath: "sessions/2026_02_04_TEST",
      sessionDate: "2026-02-04",
      filePath: "sessions/2026_02_04_TEST/FILE.md",
      sectionTitle: title,
      content: `Content ${title}.`,
      contentHash: hash,
    });

    it("stores the embedder's model and width on every embedding row", async () => {
      const { db, dbPath } = await setupDb();
      await reconcileChunks(db, dbPath, [chunk("h1")], makeMockEmbedder(), { log: () => {} });

      const rows = db.exec("SELECT model, dimensions, length(embedding) FROM embeddings");
      expect(rows[0].values).toEqual([["embeddinggemma", 768, 768 * 4]]);
      db.close();
    });

    it("re-embeds an unchanged chunk whose row was written by another model/width", async () => {
      const { db, dbPath } = await setupDb();
      await reconcileChunks(db, dbPath, [chunk("h1")], makeMockEmbedder("old-model", 16), { log: () => {} });

      const report = await reconcileChunks(db, dbPath, [chunk("h1")], makeMockEmbedder(), { log: () => {} });

      expect(report.skipped).toBe(0);
      expect(report.updated).toBe(1);
      const rows = db.exec("SELECT model, dimensions FROM embeddings");
      expect(rows[0].values).toEqual([["embeddinggemma", 768]]);
      db.close();
    });

    it("skips an unchanged chunk already embedded by the same model and width", async () => {
      const { db, dbPath } = await setupDb();
      const embedder = makeMockEmbedder();
      await reconcileChunks(db, dbPath, [chunk("h1")], embedder, { log: () => {} });
      const report = await reconcileChunks(db, dbPath, [chunk("h1")], embedder, { log: () => {} });
      expect(report).toMatchObject({ skipped: 1, updated: 0, inserted: 0 });
      db.close();
    });

    it("the schema refuses a blob whose length does not match its declared width", async () => {
      const { db } = await setupDb();
      db.run("INSERT INTO chunks (session_path, session_date, file_path, section_title, content, content_hash) VALUES ('s','d','f','t','c','h')");
      expect(() =>
        db.run("INSERT INTO embeddings (chunk_id, embedding, model, dimensions) VALUES (1, ?, 'm', 768)", [new Uint8Array(3072 * 4)])
      ).toThrow(/CHECK/);
      db.close();
    });
  });

  it("embeds in checkpointed slabs and saves after each one", async () => {
    const { db, dbPath } = await setupDb();
    const base = makeMockEmbedder();
    const slabSizes: number[] = [];
    const embedder: EmbeddingClient = {
      ...base,
      async embedTexts(texts) {
        slabSizes.push(texts.length);
        return base.embedTexts(texts);
      },
    };
    const lines: string[] = [];
    const chunks: Chunk[] = Array.from({ length: 5 }, (_, i) => ({
      sessionPath: "sessions/2026_02_04_TEST",
      sessionDate: "2026-02-04",
      filePath: "sessions/2026_02_04_TEST/FILE.md",
      sectionTitle: `S${i}`,
      content: `Content ${i}.`,
      contentHash: `h${i}`,
    }));

    const report = await reconcileChunks(db, dbPath, chunks, embedder, { checkpointEvery: 2, log: (l) => lines.push(l) });

    expect(slabSizes).toEqual([2, 2, 1]);
    expect(report.inserted).toBe(5);
    expect(lines).toEqual([
      "[session-search] embedded 2/5 (checkpoint saved)",
      "[session-search] embedded 4/5 (checkpoint saved)",
    ]);
    expect(fs.existsSync(dbPath)).toBe(true);
    db.close();
  });

  it("a run cut off after a checkpoint resumes: saved slabs are skipped, not re-embedded", async () => {
    const { db, dbPath } = await setupDb();
    const base = makeMockEmbedder();
    let calls = 0;
    const failing: EmbeddingClient = {
      ...base,
      async embedTexts(texts) {
        if (++calls === 3) throw new Error("runner went away");
        return base.embedTexts(texts);
      },
    };
    const chunks: Chunk[] = Array.from({ length: 6 }, (_, i) => ({
      sessionPath: "sessions/2026_02_04_TEST",
      sessionDate: "2026-02-04",
      filePath: "sessions/2026_02_04_TEST/FILE.md",
      sectionTitle: `S${i}`,
      content: `Content ${i}.`,
      contentHash: `h${i}`,
    }));

    await expect(reconcileChunks(db, dbPath, chunks, failing, { checkpointEvery: 2, log: () => {} })).rejects.toThrow(/went away/);
    db.close();

    const reopened = await initDb(dbPath);
    const report = await reconcileChunks(reopened, dbPath, chunks, base, { checkpointEvery: 2, log: () => {} });
    expect(report).toMatchObject({ skipped: 4, inserted: 2 });
    reopened.close();
  });
});
