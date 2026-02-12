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

function makeMockEmbedder(): EmbeddingClient {
  // Returns a deterministic fake embedding based on the text length
  return {
    async embedTexts(texts: string[]): Promise<Float32Array[]> {
      return texts.map((t) => {
        const arr = new Float32Array(3072);
        // Fill with a simple pattern derived from text length
        for (let i = 0; i < arr.length; i++) {
          arr[i] = (t.length + i) / 10000;
        }
        return arr;
      });
    },
    async embedSingle(text: string): Promise<Float32Array> {
      const arr = new Float32Array(3072);
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
});
