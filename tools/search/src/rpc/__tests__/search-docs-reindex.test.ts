import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import { registerCommand } from "engine-shared/dispatch";
import "../search-upsert.js";
import "../search-delete.js";
import "../search-docs-reindex.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

// Mock ai.embed — returns deterministic fake embeddings
registerCommand("ai.embed", {
  schema: (await import("zod/v4")).z.object({ texts: (await import("zod/v4")).z.array((await import("zod/v4")).z.string()) }),
  handler: (args: { texts: string[] }) => ({
    ok: true as const,
    data: {
      embeddings: args.texts.map(() => [1, 0, 0, 0]),
      model: "mock",
    },
  }),
});

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
});
afterEach(async () => {
  await db.close();
});

describe("search.docs.reindex", () => {
  it("should chunk docs with breadcrumb titles from H1/H2/H3", async () => {
    const result = await dispatch(
      {
        cmd: "search.docs.reindex",
        args: {
          fileContents: {
            "docs/guide.md":
              "# Getting Started\nThis is the intro text for the getting started guide which is long enough to exceed the minimum chunk size threshold of one hundred characters easily.\n## Installation\nRun npm install to set up all dependencies. Make sure you have the correct node version and all prerequisites configured before attempting installation.\n### Prerequisites\nYou need Node 18+ installed on your system. Also ensure you have git and a compatible package manager like npm or yarn available in your PATH.",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.inserted).toBeGreaterThanOrEqual(2);

    const chunks = await db.all<{ sectionTitle: string }>(
      "SELECT section_title AS sectionTitle FROM chunks ORDER BY id"
    );
    const titles = chunks.map((c) => c.sectionTitle);
    // Should have breadcrumb-style titles
    expect(titles.some((t) => t.includes("guide.md"))).toBe(true);
    expect(titles.some((t) => t.includes("Installation"))).toBe(true);
  });

  it("should merge tiny chunks (< 100 chars) with next sibling", async () => {
    const result = await dispatch(
      {
        cmd: "search.docs.reindex",
        args: {
          fileContents: {
            "docs/small.md": "## Tiny\nHi.\n## Big Section\n" + "x".repeat(200),
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    // "Tiny" section (< 100 chars) should merge into "Big Section"
    expect(result.data.inserted).toBe(1);

    const chunks = await db.all<{ chunkText: string }>(
      "SELECT chunk_text AS chunkText FROM chunks"
    );
    expect(chunks).toHaveLength(1);
    expect(chunks[0].chunkText).toContain("Hi.");
    expect(chunks[0].chunkText).toContain("x".repeat(200));
  });

  it("should deduplicate embeddings via content_hash", async () => {
    const identicalContent = "## Shared\nThis content is exactly the same in both files.";
    const result = await dispatch(
      {
        cmd: "search.docs.reindex",
        args: {
          fileContents: {
            "docs/file-a.md": identicalContent,
            "docs/file-b.md": identicalContent,
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.inserted).toBe(2); // 2 chunks

    const chunks = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM chunks");
    const embs = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM embeddings");
    expect(chunks!.cnt).toBe(2);
    expect(embs!.cnt).toBe(1); // shared content_hash → 1 embedding
  });

  it("should reconcile: insert new, skip unchanged, update changed, delete orphaned", async () => {
    // First reindex — 2 files
    await dispatch(
      {
        cmd: "search.docs.reindex",
        args: {
          fileContents: {
            "docs/keep.md": "## Keep\nOriginal keep content that is long enough to not merge.",
            "docs/remove.md": "## Remove\nThis file will be removed and is long enough.",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    // Second reindex — keep.md modified, remove.md gone, new.md added
    const result = await dispatch(
      {
        cmd: "search.docs.reindex",
        args: {
          fileContents: {
            "docs/keep.md": "## Keep\nModified keep content that is still long enough here.",
            "docs/new.md": "## New\nBrand new file content that is definitely long enough.",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.updated).toBe(1); // keep.md changed
    expect(result.data.inserted).toBe(1); // new.md added
    expect(result.data.deleted).toBe(1); // remove.md gone
  });

  it("should handle docs with no headers (full document chunk)", async () => {
    const result = await dispatch(
      {
        cmd: "search.docs.reindex",
        args: {
          fileContents: {
            "docs/plain.md": "Just some plain text without any markdown headers at all.",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.inserted).toBe(1);

    const chunks = await db.all<{ sectionTitle: string }>(
      "SELECT section_title AS sectionTitle FROM chunks"
    );
    expect(chunks[0].sectionTitle).toContain("plain.md");
    expect(chunks[0].sectionTitle).toContain("(full document)");
  });
});
