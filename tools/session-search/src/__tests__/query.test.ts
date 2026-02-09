import { describe, it, expect, afterEach } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { initDb } from "../db.js";
import { reconcileChunks } from "../indexer.js";
import {
  searchChunks,
  groupResultsBySession,
  groupResultsByFile,
  buildFilterClauses,
  type SearchResult,
  type QueryFilters,
} from "../query.js";
import type { EmbeddingClient } from "../embed.js";
import type { Chunk } from "../chunker.js";

function makeTmpDbPath(): string {
  return path.join(
    os.tmpdir(),
    `session-search-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
  );
}

function makeMockEmbedder(): EmbeddingClient {
  return {
    async embedTexts(texts: string[]): Promise<Float32Array[]> {
      return texts.map((t) => {
        const arr = new Float32Array(3072);
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

describe("query", () => {
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

  describe("groupResultsBySession", () => {
    it("should group results by session and sort by distance", () => {
      const results: SearchResult[] = [
        {
          sessionPath: "sessions/2026_02_04_TEST_A",
          filePath: "sessions/2026_02_04_TEST_A/BRAINSTORM.md",
          sectionTitle: "Section 1",
          distance: 0.3,
          snippet: "Content A1...",
        },
        {
          sessionPath: "sessions/2026_02_04_TEST_B",
          filePath: "sessions/2026_02_04_TEST_B/ANALYSIS.md",
          sectionTitle: "Section 2",
          distance: 0.1,
          snippet: "Content B...",
        },
        {
          sessionPath: "sessions/2026_02_04_TEST_A",
          filePath: "sessions/2026_02_04_TEST_A/LOG.md",
          sectionTitle: "Section 3",
          distance: 0.5,
          snippet: "Content A2...",
        },
      ];

      const grouped = groupResultsBySession(results);

      expect(grouped).toHaveLength(2);
      // Best match session first (lowest distance)
      expect(grouped[0].sessionPath).toBe("sessions/2026_02_04_TEST_B");
      expect(grouped[0].sessionDate).toBe("2026-02-04");
      expect(grouped[0].matches).toHaveLength(1);

      expect(grouped[1].sessionPath).toBe("sessions/2026_02_04_TEST_A");
      expect(grouped[1].sessionDate).toBe("2026-02-04");
      expect(grouped[1].matches).toHaveLength(2);
      // Matches within session sorted by distance
      expect(grouped[1].matches[0].distance).toBe(0.3);
      expect(grouped[1].matches[1].distance).toBe(0.5);
    });

    it("should extract date from session path", () => {
      const results: SearchResult[] = [
        {
          sessionPath: "sessions/2026_01_15_LAYOUT_REFACTOR",
          filePath: "sessions/2026_01_15_LAYOUT_REFACTOR/IMPLEMENTATION.md",
          sectionTitle: "Summary",
          distance: 0.2,
          snippet: "Refactored...",
        },
      ];

      const grouped = groupResultsBySession(results);
      expect(grouped).toHaveLength(1);
      expect(grouped[0].sessionDate).toBe("2026-01-15");
    });

    it("should handle empty results", () => {
      const grouped = groupResultsBySession([]);
      expect(grouped).toHaveLength(0);
    });
  });

  describe("groupResultsByFile", () => {
    it("should group results by file and sort by distance", () => {
      const results: SearchResult[] = [
        {
          sessionPath: "sessions/2026_02_04_TEST_A",
          filePath: "sessions/2026_02_04_TEST_A/BRAINSTORM.md",
          sectionTitle: "Section 1",
          distance: 0.3,
          snippet: "Content A1...",
        },
        {
          sessionPath: "sessions/2026_02_04_TEST_A",
          filePath: "sessions/2026_02_04_TEST_A/LOG.md",
          sectionTitle: "Section 2",
          distance: 0.1,
          snippet: "Content log...",
        },
        {
          sessionPath: "sessions/2026_02_04_TEST_A",
          filePath: "sessions/2026_02_04_TEST_A/BRAINSTORM.md",
          sectionTitle: "Section 3",
          distance: 0.5,
          snippet: "Content A2...",
        },
      ];

      const grouped = groupResultsByFile(results);

      expect(grouped).toHaveLength(2);
      // Best file first (LOG.md has distance 0.1)
      expect(grouped[0].filePath).toBe("sessions/2026_02_04_TEST_A/LOG.md");
      expect(grouped[0].sessionDate).toBe("2026-02-04");
      expect(grouped[0].matches).toHaveLength(1);

      // BRAINSTORM.md second (best match distance 0.3)
      expect(grouped[1].filePath).toBe("sessions/2026_02_04_TEST_A/BRAINSTORM.md");
      expect(grouped[1].matches).toHaveLength(2);
      expect(grouped[1].matches[0].distance).toBe(0.3);
      expect(grouped[1].matches[1].distance).toBe(0.5);
    });

    it("should preserve session path as breadcrumb", () => {
      const results: SearchResult[] = [
        {
          sessionPath: "yarik/finch/sessions/2026_01_15_REFACTOR",
          filePath: "yarik/finch/sessions/2026_01_15_REFACTOR/IMPLEMENTATION.md",
          sectionTitle: "Summary",
          distance: 0.2,
          snippet: "Refactored...",
        },
      ];

      const grouped = groupResultsByFile(results);
      expect(grouped).toHaveLength(1);
      expect(grouped[0].sessionPath).toBe("yarik/finch/sessions/2026_01_15_REFACTOR");
      expect(grouped[0].sessionDate).toBe("2026-01-15");
    });

    it("should handle empty results", () => {
      const grouped = groupResultsByFile([]);
      expect(grouped).toHaveLength(0);
    });
  });

  describe("buildFilterClauses", () => {
    it("should return empty for no filters", () => {
      const { whereClauses, params } = buildFilterClauses({});
      expect(whereClauses).toHaveLength(0);
      expect(params).toHaveLength(0);
    });

    it("should filter by date range (after)", () => {
      const { whereClauses, params } = buildFilterClauses({
        after: "2026-01-01",
      });
      expect(whereClauses).toHaveLength(1);
      expect(whereClauses[0]).toContain("session_date");
      expect(whereClauses[0]).toContain(">=");
      expect(params).toHaveLength(1);
      expect(params[0]).toBe("2026-01-01");
    });

    it("should filter by date range (before)", () => {
      const { whereClauses, params } = buildFilterClauses({
        before: "2026-03-01",
      });
      expect(whereClauses).toHaveLength(1);
      expect(whereClauses[0]).toContain("session_date");
      expect(whereClauses[0]).toContain("<");
      expect(params).toHaveLength(1);
      expect(params[0]).toBe("2026-03-01");
    });

    it("should filter by file glob", () => {
      const { whereClauses, params } = buildFilterClauses({
        file: "BRAINSTORM",
      });
      expect(whereClauses).toHaveLength(1);
      expect(whereClauses[0]).toContain("file_path");
      expect(params).toHaveLength(1);
      expect(params[0]).toContain("BRAINSTORM");
    });

    it("should combine multiple filters", () => {
      const { whereClauses, params } = buildFilterClauses({
        after: "2026-01-01",
        before: "2026-03-01",
        file: "LOG",
      });
      expect(whereClauses).toHaveLength(3);
      expect(params).toHaveLength(3);
    });
  });

  describe("searchChunks (integration)", () => {
    it("should find indexed chunks via vector search", async () => {
      const db = setupDb();
      const embedder = makeMockEmbedder();

      const chunks: Chunk[] = [
        {
          sessionPath: "sessions/2026_02_04_TEST",
          sessionDate: "2026-02-04",
          filePath: "sessions/2026_02_04_TEST/BRAINSTORM.md",
          sectionTitle: "Design Decision",
          content:
            "We decided to use SQLite with sqlite-vec for vector storage.",
          contentHash: "hash_1",
        },
        {
          sessionPath: "sessions/2026_02_04_TEST",
          sessionDate: "2026-02-04",
          filePath: "sessions/2026_02_04_TEST/LOG.md",
          sectionTitle: "Task Start",
          content: "Started implementation of the embedding pipeline.",
          contentHash: "hash_2",
        },
      ];

      await reconcileChunks(db, chunks, embedder);

      // Search with the mock embedder
      const results = await searchChunks(db, "SQLite vector storage", embedder, {}, 10);

      expect(results.length).toBeGreaterThan(0);
      expect(results[0]).toMatchObject({
        sessionPath: expect.any(String),
        filePath: expect.any(String),
        sectionTitle: expect.any(String),
        distance: expect.any(Number),
        snippet: expect.any(String),
      });

      db.close();
    });
  });
});
