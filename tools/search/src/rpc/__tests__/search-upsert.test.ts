import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import "../search-upsert.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
});
afterEach(async () => {
  await db.close();
});

const BASE_ARGS = {
  sourceType: "session",
  sourcePath: "/sessions/2026_01_01_FOO/LOG.md",
  sectionTitle: "## Introduction",
  chunkText: "This is a test chunk.",
  contentHash: "abc123",
  embedding: [1, 0, 0, 0],
};

describe("search.upsert", () => {
  it("should insert a new chunk and embedding", async () => {
    const result = await dispatch({ cmd: "search.upsert", args: BASE_ARGS }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.chunkId).toBe(1);
    expect(result.data.contentHash).toBe("abc123");
    expect(result.data.created).toBe(true);
  });

  it("should be idempotent — same content_hash and path re-upserts cleanly", async () => {
    await dispatch({ cmd: "search.upsert", args: BASE_ARGS }, { db } as unknown as RpcContext);
    const result = await dispatch({ cmd: "search.upsert", args: BASE_ARGS }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.created).toBe(false);

    // Only one embedding and one chunk row
    const embRow = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM embeddings");
    const chunkRow = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM chunks");
    expect(embRow!.cnt).toBe(1);
    expect(chunkRow!.cnt).toBe(1);
  });

  it("should update existing chunk when content_hash changes", async () => {
    await dispatch({ cmd: "search.upsert", args: BASE_ARGS }, { db } as unknown as RpcContext);

    const updated = {
      ...BASE_ARGS,
      chunkText: "Updated chunk text.",
      contentHash: "xyz999",
      embedding: [0, 1, 0, 0],
    };
    const result = await dispatch({ cmd: "search.upsert", args: updated }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.contentHash).toBe("xyz999");
    expect(result.data.created).toBe(false);

    const chunk = await db.get<{ chunkText: string; contentHash: string }>(
      "SELECT chunk_text, content_hash FROM chunks WHERE id = 1"
    );
    expect(chunk!.chunkText).toBe("Updated chunk text.");
    expect(chunk!.contentHash).toBe("xyz999");
  });

  it("should share one embedding for two chunks with the same content_hash", async () => {
    const chunk1 = { ...BASE_ARGS };
    const chunk2 = {
      ...BASE_ARGS,
      sourcePath: "/sessions/2026_01_02_BAR/LOG.md",
      sectionTitle: "## Intro",
    };

    await dispatch({ cmd: "search.upsert", args: chunk1 }, { db } as unknown as RpcContext);
    await dispatch({ cmd: "search.upsert", args: chunk2 }, { db } as unknown as RpcContext);

    const embRow = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM embeddings");
    const chunkRow = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM chunks");
    expect(embRow!.cnt).toBe(1); // same content_hash → one embedding
    expect(chunkRow!.cnt).toBe(2); // two distinct chunks
  });

  it("should update sourceType on re-upsert of same path+title", async () => {
    await dispatch({ cmd: "search.upsert", args: BASE_ARGS }, { db } as unknown as RpcContext);

    const updated = { ...BASE_ARGS, sourceType: "doc" };
    await dispatch({ cmd: "search.upsert", args: updated }, { db } as unknown as RpcContext);

    const chunk = await db.get<{ sourceType: string }>(
      "SELECT source_type FROM chunks WHERE id = 1"
    );
    expect(chunk!.sourceType).toBe("doc");
  });

  it("should leave orphaned old embedding when content_hash changes (cleaned by delete)", async () => {
    await dispatch({ cmd: "search.upsert", args: BASE_ARGS }, { db } as unknown as RpcContext);

    const updated = {
      ...BASE_ARGS,
      chunkText: "New text.",
      contentHash: "xyz999",
      embedding: [0, 1, 0, 0],
    };
    await dispatch({ cmd: "search.upsert", args: updated }, { db } as unknown as RpcContext);

    // Both embeddings exist — upsert doesn't clean orphans (that's delete's job)
    const embRow = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM embeddings");
    expect(embRow!.cnt).toBe(2);
  });

  it("should preserve shared embedding when one of two chunks updates content_hash", async () => {
    const sharedArgs = { ...BASE_ARGS, contentHash: "shared-hash" };
    await dispatch({ cmd: "search.upsert", args: sharedArgs }, { db } as unknown as RpcContext);
    await dispatch(
      {
        cmd: "search.upsert",
        args: { ...sharedArgs, sourcePath: "/other.md", sectionTitle: "## Other" },
      },
      { db } as unknown as RpcContext
    );

    // Update chunk 1 to a new hash
    await dispatch(
      {
        cmd: "search.upsert",
        args: { ...BASE_ARGS, contentHash: "new-hash", embedding: [0, 1, 0, 0] },
      },
      { db } as unknown as RpcContext
    );

    // Both old and new embeddings should exist (old still referenced by chunk 2)
    const embRow = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM embeddings");
    expect(embRow!.cnt).toBe(2);

    const chunkRow = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM chunks");
    expect(chunkRow!.cnt).toBe(2);
  });

  it("should accept empty string fields without crashing", async () => {
    const result = await dispatch(
      {
        cmd: "search.upsert",
        args: {
          sourceType: "",
          sourcePath: "",
          sectionTitle: "",
          chunkText: "",
          contentHash: "empty-hash",
          embedding: [1, 0, 0, 0],
        },
      },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
  });

  it("should handle very long chunkText without error", async () => {
    const longText = "x".repeat(100_000);
    const result = await dispatch(
      {
        cmd: "search.upsert",
        args: { ...BASE_ARGS, chunkText: longText, contentHash: "long-hash" },
      },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const chunk = await db.get<{ chunkText: string }>(
      "SELECT chunk_text FROM chunks WHERE id = ?",
      [result.data.chunkId]
    );
    expect(chunk!.chunkText.length).toBe(100_000);
  });

  it("should reject missing required fields", async () => {
    const result = await dispatch(
      { cmd: "search.upsert", args: { sourceType: "session" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });
});
