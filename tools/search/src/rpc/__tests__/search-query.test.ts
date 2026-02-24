import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import "../search-upsert.js";
import "../search-query.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
});
afterEach(async () => {
  await db.close();
});

// Helper: upsert a chunk
async function upsertChunk(
  db: DbConnection,
  overrides: Partial<{
    sourceType: string;
    sourcePath: string;
    sectionTitle: string;
    chunkText: string;
    contentHash: string;
    embedding: number[];
  }> = {}
) {
  return dispatch(
    {
      cmd: "search.upsert",
      args: {
        sourceType: "session",
        sourcePath: "/sessions/FOO/LOG.md",
        sectionTitle: "## Intro",
        chunkText: "Hello world.",
        contentHash: "hash1",
        embedding: [1, 0, 0, 0],
        ...overrides,
      },
    },
    { db } as unknown as RpcContext
  );
}

describe("search.query", () => {
  it("should return empty results when index is empty", async () => {
    const result = await dispatch(
      { cmd: "search.query", args: { embedding: [1, 0, 0, 0] } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.results).toHaveLength(0);
  });

  it("should return closest chunk when querying with identical vector", async () => {
    await upsertChunk(db, {
      embedding: [1, 0, 0, 0],
      contentHash: "hash-a",
    });

    const result = await dispatch(
      { cmd: "search.query", args: { embedding: [1, 0, 0, 0] } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.results).toHaveLength(1);
    const r = result.data.results[0] as Record<string, unknown>;
    expect(r.distance).toBeCloseTo(0, 5); // identical vectors → 0 distance
    expect(r.chunkText).toBe("Hello world.");
    expect(r.sourcePath).toBe("/sessions/FOO/LOG.md");
  });

  it("should order results by distance ASC", async () => {
    // [1,0,0,0] vs query [1,0,0,0] → distance 0 (closest)
    await upsertChunk(db, {
      embedding: [1, 0, 0, 0],
      contentHash: "hash-close",
      sectionTitle: "## A",
      sourcePath: "/a.md",
    });
    // [0,1,0,0] vs query [1,0,0,0] → distance 1 (orthogonal)
    await upsertChunk(db, {
      embedding: [0, 1, 0, 0],
      contentHash: "hash-far",
      sectionTitle: "## B",
      sourcePath: "/b.md",
    });

    const result = await dispatch(
      { cmd: "search.query", args: { embedding: [1, 0, 0, 0] } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const results = result.data.results as Array<Record<string, unknown>>;
    expect(results).toHaveLength(2);
    expect(results[0].sourcePath).toBe("/a.md"); // closest first
    expect(results[1].sourcePath).toBe("/b.md");
    expect(results[0].distance as number).toBeLessThan(results[1].distance as number);
  });

  it("should filter by sourceType", async () => {
    await upsertChunk(db, {
      sourceType: "session",
      embedding: [1, 0, 0, 0],
      contentHash: "hash-s",
      sectionTitle: "## S",
      sourcePath: "/session.md",
    });
    await upsertChunk(db, {
      sourceType: "doc",
      embedding: [0, 1, 0, 0],
      contentHash: "hash-d",
      sectionTitle: "## D",
      sourcePath: "/doc.md",
    });

    const result = await dispatch(
      {
        cmd: "search.query",
        args: { embedding: [1, 0, 0, 0], sourceTypes: ["doc"] },
      },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const results = result.data.results as Array<Record<string, unknown>>;
    expect(results).toHaveLength(1);
    expect(results[0].sourceType).toBe("doc");
  });

  it("should respect the limit parameter", async () => {
    for (let i = 0; i < 5; i++) {
      await upsertChunk(db, {
        embedding: [1, 0, 0, 0],
        contentHash: `hash-${i}`,
        sectionTitle: `## Section ${i}`,
        sourcePath: `/file${i}.md`,
      });
    }

    const result = await dispatch(
      { cmd: "search.query", args: { embedding: [1, 0, 0, 0], limit: 3 } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.results).toHaveLength(3);
  });

  it("should return empty results when sourceTypes filter matches no chunks", async () => {
    await upsertChunk(db, {
      sourceType: "session",
      embedding: [1, 0, 0, 0],
      contentHash: "hash-session",
    });

    const result = await dispatch(
      {
        cmd: "search.query",
        args: { embedding: [1, 0, 0, 0], sourceTypes: ["doc"] },
      },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.results).toHaveLength(0);
  });

  it("should handle multiple sourceTypes filter", async () => {
    await upsertChunk(db, {
      sourceType: "session",
      sourcePath: "/s.md",
      sectionTitle: "## S",
      contentHash: "hash-s",
      embedding: [1, 0, 0, 0],
    });
    await upsertChunk(db, {
      sourceType: "doc",
      sourcePath: "/d.md",
      sectionTitle: "## D",
      contentHash: "hash-d",
      embedding: [0, 1, 0, 0],
    });
    await upsertChunk(db, {
      sourceType: "directive",
      sourcePath: "/dir.md",
      sectionTitle: "## Dir",
      contentHash: "hash-dir",
      embedding: [0, 0, 1, 0],
    });

    const result = await dispatch(
      {
        cmd: "search.query",
        args: { embedding: [1, 0, 0, 0], sourceTypes: ["session", "doc"] },
      },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const results = result.data.results as Array<Record<string, unknown>>;
    expect(results).toHaveLength(2);
    const types = results.map((r) => r.sourceType).sort();
    expect(types).toEqual(["doc", "session"]);
  });

  it("should default limit to 10 when not specified", async () => {
    for (let i = 0; i < 15; i++) {
      await upsertChunk(db, {
        embedding: [1, 0, 0, 0],
        contentHash: `hash-${i}`,
        sectionTitle: `## Section ${i}`,
        sourcePath: `/file${i}.md`,
      });
    }

    const result = await dispatch(
      { cmd: "search.query", args: { embedding: [1, 0, 0, 0] } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.results).toHaveLength(10);
  });

  it("should treat empty sourceTypes array as no filter", async () => {
    await upsertChunk(db, {
      sourceType: "session",
      sourcePath: "/s.md",
      sectionTitle: "## S",
      contentHash: "hash-s1",
      embedding: [1, 0, 0, 0],
    });
    await upsertChunk(db, {
      sourceType: "doc",
      sourcePath: "/d.md",
      sectionTitle: "## D",
      contentHash: "hash-d1",
      embedding: [0, 1, 0, 0],
    });

    const result = await dispatch(
      {
        cmd: "search.query",
        args: { embedding: [1, 0, 0, 0], sourceTypes: [] },
      },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.results).toHaveLength(2);
  });

  it("should return correct result shape with all fields", async () => {
    await upsertChunk(db, {
      sourceType: "directive",
      sourcePath: "/directives/TESTING.md",
      sectionTitle: "## Rules",
      chunkText: "Test everything.",
      embedding: [1, 0, 0, 0],
      contentHash: "hash-shape",
    });

    const result = await dispatch(
      { cmd: "search.query", args: { embedding: [1, 0, 0, 0] } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const r = result.data.results[0] as Record<string, unknown>;
    expect(r.sourceType).toBe("directive");
    expect(r.sourcePath).toBe("/directives/TESTING.md");
    expect(r.sectionTitle).toBe("## Rules");
    expect(r.chunkText).toBe("Test everything.");
    expect(typeof r.distance).toBe("number");
  });
});
