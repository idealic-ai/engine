import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import "../search-upsert.js";
import "../search-delete.js";
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

async function counts(db: DbConnection) {
  const c = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM chunks");
  const e = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM embeddings");
  return { chunks: c!.cnt, embeddings: e!.cnt };
}

describe("search.delete", () => {
  it("should delete chunks by sourcePath and clean orphaned embedding", async () => {
    await upsertChunk(db, {
      sourcePath: "/sessions/A/LOG.md",
      contentHash: "hash-a",
    });

    const result = await dispatch(
      { cmd: "search.delete", args: { sourcePath: "/sessions/A/LOG.md" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.chunksDeleted).toBe(1);
    expect(result.data.embeddingsDeleted).toBe(1);

    const c = await counts(db);
    expect(c.chunks).toBe(0);
    expect(c.embeddings).toBe(0);
  });

  it("should delete chunks by sourceType and clean orphaned embeddings", async () => {
    await upsertChunk(db, {
      sourceType: "doc",
      sourcePath: "/doc1.md",
      sectionTitle: "## A",
      contentHash: "hash-d1",
    });
    await upsertChunk(db, {
      sourceType: "doc",
      sourcePath: "/doc2.md",
      sectionTitle: "## B",
      contentHash: "hash-d2",
    });
    await upsertChunk(db, {
      sourceType: "session",
      sourcePath: "/session.md",
      sectionTitle: "## C",
      contentHash: "hash-s",
    });

    const result = await dispatch(
      { cmd: "search.delete", args: { sourceType: "doc" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.chunksDeleted).toBe(2);
    expect(result.data.embeddingsDeleted).toBe(2);

    const c = await counts(db);
    expect(c.chunks).toBe(1); // session chunk remains
    expect(c.embeddings).toBe(1); // session embedding remains
  });

  it("should not delete embeddings still referenced by surviving chunks", async () => {
    // Two chunks share same content_hash — only delete one
    await upsertChunk(db, {
      sourcePath: "/a.md",
      sectionTitle: "## A",
      contentHash: "shared-hash",
    });
    await upsertChunk(db, {
      sourcePath: "/b.md",
      sectionTitle: "## B",
      contentHash: "shared-hash",
    });

    await dispatch(
      { cmd: "search.delete", args: { sourcePath: "/a.md" } },
      { db } as unknown as RpcContext
    );

    const c = await counts(db);
    expect(c.chunks).toBe(1); // /b.md still there
    expect(c.embeddings).toBe(1); // shared embedding still referenced by /b.md
  });

  it("should return zero counts when no chunks match", async () => {
    await upsertChunk(db, { sourcePath: "/exists.md", contentHash: "hash-x" });

    const result = await dispatch(
      { cmd: "search.delete", args: { sourcePath: "/no-such-file.md" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.chunksDeleted).toBe(0);
    expect(result.data.embeddingsDeleted).toBe(0);
  });

  it("should delete by both sourcePath and sourceType", async () => {
    await upsertChunk(db, {
      sourceType: "doc",
      sourcePath: "/doc.md",
      sectionTitle: "## A",
      contentHash: "hash-target",
    });
    // same path, different type — should NOT be deleted
    await upsertChunk(db, {
      sourceType: "session",
      sourcePath: "/doc.md",
      sectionTitle: "## B",
      contentHash: "hash-keep",
      embedding: [0, 1, 0, 0],
    });

    const result = await dispatch(
      { cmd: "search.delete", args: { sourcePath: "/doc.md", sourceType: "doc" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.chunksDeleted).toBe(1);

    const c = await counts(db);
    expect(c.chunks).toBe(1); // session chunk survives
  });

  it("should handle delete+re-insert cycle cleanly", async () => {
    await upsertChunk(db, {
      sourcePath: "/cycle.md",
      sectionTitle: "## A",
      contentHash: "hash-cycle",
    });

    await dispatch(
      { cmd: "search.delete", args: { sourcePath: "/cycle.md" } },
      { db } as unknown as RpcContext
    );

    const c1 = await counts(db);
    expect(c1.chunks).toBe(0);

    // Re-insert same chunk
    const result = await upsertChunk(db, {
      sourcePath: "/cycle.md",
      sectionTitle: "## A",
      contentHash: "hash-cycle",
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.created).toBe(true);

    const c2 = await counts(db);
    expect(c2.chunks).toBe(1);
    expect(c2.embeddings).toBe(1);
  });

  it("should not delete when sourceType filter doesn't match existing chunks", async () => {
    await upsertChunk(db, {
      sourceType: "session",
      sourcePath: "/s.md",
      contentHash: "hash-s",
    });

    const result = await dispatch(
      { cmd: "search.delete", args: { sourceType: "doc" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.chunksDeleted).toBe(0);

    const c = await counts(db);
    expect(c.chunks).toBe(1);
  });

  it("should count orphan cleanup correctly with multiple shared embeddings", async () => {
    // hash-A shared by 2 chunks, hash-B used by 1 chunk
    await upsertChunk(db, {
      sourcePath: "/a1.md",
      sectionTitle: "## A1",
      contentHash: "hash-A",
    });
    await upsertChunk(db, {
      sourcePath: "/a2.md",
      sectionTitle: "## A2",
      contentHash: "hash-A",
    });
    await upsertChunk(db, {
      sourcePath: "/b.md",
      sectionTitle: "## B",
      contentHash: "hash-B",
      embedding: [0, 1, 0, 0],
    });

    // Delete the chunk with hash-B
    const result = await dispatch(
      { cmd: "search.delete", args: { sourcePath: "/b.md" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.chunksDeleted).toBe(1);
    expect(result.data.embeddingsDeleted).toBe(1); // hash-B orphaned

    const c = await counts(db);
    expect(c.chunks).toBe(2); // hash-A chunks remain
    expect(c.embeddings).toBe(1); // hash-A embedding remains
  });

  it("should reject when neither sourcePath nor sourceType is provided", async () => {
    const result = await dispatch(
      { cmd: "search.delete", args: {} },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });
});
