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

  function setupDb(): ReturnType<typeof initDb> {
    const p = makeTmpDbPath();
    tmpDbs.push(p);
    return initDb(p);
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
    const db = setupDb();
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

    const report = await reconcileChunks(db, chunks, embedder);

    expect(report.inserted).toBe(2);
    expect(report.updated).toBe(0);
    expect(report.skipped).toBe(0);
    expect(report.deleted).toBe(0);

    // Verify data in DB
    const rows = db.prepare("SELECT * FROM chunks").all() as Array<{
      id: number;
      content_hash: string;
      session_date: string;
    }>;
    expect(rows).toHaveLength(2);
    expect(rows[0].session_date).toBe("2026-02-04");

    // Verify vectors exist
    const vecRows = db
      .prepare("SELECT chunk_id FROM vec_chunks")
      .all() as Array<{ chunk_id: number }>;
    expect(vecRows).toHaveLength(2);

    db.close();
  });

  it("should skip unchanged chunks", async () => {
    const db = setupDb();
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
    await reconcileChunks(db, chunks, embedder);

    // Second run — same chunks, should skip
    const report = await reconcileChunks(db, chunks, embedder);

    expect(report.inserted).toBe(0);
    expect(report.updated).toBe(0);
    expect(report.skipped).toBe(1);
    expect(report.deleted).toBe(0);

    db.close();
  });

  it("should update changed chunks", async () => {
    const db = setupDb();
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
    await reconcileChunks(db, chunks, embedder);

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

    const report = await reconcileChunks(db, updatedChunks, embedder);

    expect(report.inserted).toBe(0);
    expect(report.updated).toBe(1);
    expect(report.skipped).toBe(0);
    expect(report.deleted).toBe(0);

    // Verify content updated
    const row = db
      .prepare("SELECT content_hash FROM chunks WHERE section_title = ?")
      .get("Section One") as { content_hash: string };
    expect(row.content_hash).toBe("hash_updated");

    db.close();
  });

  it("should delete orphaned chunks", async () => {
    const db = setupDb();
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
    await reconcileChunks(db, chunks, embedder);

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

    const report = await reconcileChunks(db, remainingChunks, embedder);

    expect(report.inserted).toBe(0);
    expect(report.updated).toBe(0);
    expect(report.skipped).toBe(1);
    expect(report.deleted).toBe(1);

    // Verify only one chunk remains
    const rows = db.prepare("SELECT * FROM chunks").all();
    expect(rows).toHaveLength(1);

    db.close();
  });

  it("should handle mixed operations: insert + skip + update + delete", async () => {
    const db = setupDb();
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

    await reconcileChunks(db, initialChunks, embedder);

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

    const report = await reconcileChunks(db, updatedChunks, embedder);

    expect(report.inserted).toBe(1); // Brand New
    expect(report.updated).toBe(1); // Will Change
    expect(report.skipped).toBe(1); // Unchanged
    expect(report.deleted).toBe(1); // Will Delete

    const rows = db.prepare("SELECT section_title FROM chunks ORDER BY section_title").all() as Array<{
      section_title: string;
    }>;
    expect(rows).toHaveLength(3);
    expect(rows.map((r) => r.section_title)).toEqual([
      "Brand New",
      "Unchanged",
      "Will Change",
    ]);

    db.close();
  });

  it("should handle empty chunk list (delete all)", async () => {
    const db = setupDb();
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

    await reconcileChunks(db, chunks, embedder);

    // Pass empty chunks — should delete everything
    const report = await reconcileChunks(db, [], embedder);

    expect(report.inserted).toBe(0);
    expect(report.deleted).toBe(1);

    const rows = db.prepare("SELECT * FROM chunks").all();
    expect(rows).toHaveLength(0);

    db.close();
  });
});
