import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import "../search-upsert.js";
import "../search-delete.js";
import "../search-status.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
});
afterEach(async () => {
  await db.close();
});

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

describe("search.status", () => {
  it("should return zeros for empty db", async () => {
    const result = await dispatch({ cmd: "search.status", args: {} }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.totalChunks).toBe(0);
    expect(result.data.totalEmbeddings).toBe(0);
    expect(result.data.bySourceType).toEqual({});
    expect(result.data.uniquePaths).toBe(0);
  });

  it("should return correct counts for populated db", async () => {
    await upsertChunk(db, {
      sourceType: "session",
      sourcePath: "/session1.md",
      sectionTitle: "## A",
      contentHash: "hash-1",
    });
    await upsertChunk(db, {
      sourceType: "session",
      sourcePath: "/session1.md",
      sectionTitle: "## B",
      contentHash: "hash-2",
      embedding: [0, 1, 0, 0],
    });
    await upsertChunk(db, {
      sourceType: "doc",
      sourcePath: "/docs/guide.md",
      sectionTitle: "## Intro",
      contentHash: "hash-3",
      embedding: [0, 0, 1, 0],
    });

    const result = await dispatch({ cmd: "search.status", args: {} }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.totalChunks).toBe(3);
    expect(result.data.totalEmbeddings).toBe(3);
    expect(result.data.uniquePaths).toBe(2); // /session1.md and /docs/guide.md
  });

  it("should return per-source-type breakdown", async () => {
    await upsertChunk(db, {
      sourceType: "session",
      sourcePath: "/s1.md",
      sectionTitle: "## A",
      contentHash: "h1",
    });
    await upsertChunk(db, {
      sourceType: "session",
      sourcePath: "/s2.md",
      sectionTitle: "## B",
      contentHash: "h2",
      embedding: [0, 1, 0, 0],
    });
    await upsertChunk(db, {
      sourceType: "doc",
      sourcePath: "/d1.md",
      sectionTitle: "## C",
      contentHash: "h3",
      embedding: [0, 0, 1, 0],
    });
    await upsertChunk(db, {
      sourceType: "directive",
      sourcePath: "/dir1.md",
      sectionTitle: "## D",
      contentHash: "h4",
      embedding: [0, 0, 0, 1],
    });

    const result = await dispatch({ cmd: "search.status", args: {} }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const byType = result.data.bySourceType as Record<string, number>;
    expect(byType.session).toBe(2);
    expect(byType.doc).toBe(1);
    expect(byType.directive).toBe(1);
    expect(byType.skill).toBeUndefined();
  });

  it("should return correct counts after delete (decremented)", async () => {
    await upsertChunk(db, {
      sourcePath: "/a.md",
      sectionTitle: "## A",
      contentHash: "h1",
    });
    await upsertChunk(db, {
      sourcePath: "/b.md",
      sectionTitle: "## B",
      contentHash: "h2",
      embedding: [0, 1, 0, 0],
    });
    await upsertChunk(db, {
      sourcePath: "/c.md",
      sectionTitle: "## C",
      contentHash: "h3",
      embedding: [0, 0, 1, 0],
    });

    // Need to import search-delete for this test
    await dispatch(
      { cmd: "search.delete", args: { sourcePath: "/c.md" } },
      { db } as unknown as RpcContext
    );

    const result = await dispatch({ cmd: "search.status", args: {} }, { db } as unknown as RpcContext);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.totalChunks).toBe(2);
    expect(result.data.totalEmbeddings).toBe(2);
    expect(result.data.uniquePaths).toBe(2);
  });

  it("should count uniquePaths correctly with multiple sections per file", async () => {
    // 3 sections from path-A
    for (let i = 0; i < 3; i++) {
      await upsertChunk(db, {
        sourcePath: "/path-A.md",
        sectionTitle: `## Section ${i}`,
        contentHash: `hA${i}`,
        embedding: [i + 1, 0, 0, 0],
      });
    }
    // 2 sections from path-B
    for (let i = 0; i < 2; i++) {
      await upsertChunk(db, {
        sourcePath: "/path-B.md",
        sectionTitle: `## Section ${i}`,
        contentHash: `hB${i}`,
        embedding: [0, i + 1, 0, 0],
      });
    }

    const result = await dispatch({ cmd: "search.status", args: {} }, { db } as unknown as RpcContext);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.totalChunks).toBe(5);
    expect(result.data.uniquePaths).toBe(2);
  });

  it("should deduplicate embeddings in totalEmbeddings (shared content_hash)", async () => {
    // Two chunks same content_hash → one embedding row
    await upsertChunk(db, {
      sourcePath: "/a.md",
      sectionTitle: "## A",
      contentHash: "shared",
    });
    await upsertChunk(db, {
      sourcePath: "/b.md",
      sectionTitle: "## B",
      contentHash: "shared",
    });

    const result = await dispatch({ cmd: "search.status", args: {} }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.totalChunks).toBe(2);
    expect(result.data.totalEmbeddings).toBe(1); // deduplicated
  });
});
