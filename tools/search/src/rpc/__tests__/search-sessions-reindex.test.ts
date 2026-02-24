import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import { registerCommand } from "engine-shared/dispatch";
import "../search-upsert.js";
import "../search-query.js";
import "../search-delete.js";
import "../search-sessions-reindex.js";
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

const SESSION_PATH = "sessions/2026_01_01_TEST";

describe("search.sessions.reindex", () => {
  it("should scan session .md files and produce chunks", async () => {
    const result = await dispatch(
      {
        cmd: "search.sessions.reindex",
        args: {
          sessionPaths: [SESSION_PATH],
          fileContents: {
            [`${SESSION_PATH}/LOG.md`]:
              "# Log\n## Entry One\nContent of entry one.\n## Entry Two\nContent of entry two.",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.inserted).toBe(2);
    expect(result.data.totalChunks).toBe(2);

    // Verify chunks in DB
    const chunks = await db.all<{ sectionTitle: string }>(
      "SELECT section_title AS sectionTitle FROM chunks ORDER BY section_title"
    );
    expect(chunks.map((c) => c.sectionTitle)).toEqual(["Entry One", "Entry Two"]);
  });

  it("should parse .state.json for searchKeywords and sessionDescription", async () => {
    const stateJson = JSON.stringify({
      searchKeywords: ["keyword-alpha", "keyword-beta"],
      sessionDescription: "A test session about search tools.",
    });

    const result = await dispatch(
      {
        cmd: "search.sessions.reindex",
        args: {
          sessionPaths: [SESSION_PATH],
          fileContents: {
            [`${SESSION_PATH}/.state.json`]: stateJson,
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.inserted).toBe(3); // 2 keywords + 1 description
    expect(result.data.totalChunks).toBe(3);
  });

  it("should skip empty/whitespace-only files", async () => {
    const result = await dispatch(
      {
        cmd: "search.sessions.reindex",
        args: {
          sessionPaths: [SESSION_PATH],
          fileContents: {
            [`${SESSION_PATH}/EMPTY.md`]: "   \n\n  ",
            [`${SESSION_PATH}/REAL.md`]: "## Section\nReal content here.",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.inserted).toBe(1);
    expect(result.data.totalChunks).toBe(1);
  });

  it("should skip unchanged chunks on second reindex (same contentHash)", async () => {
    const files = {
      [`${SESSION_PATH}/LOG.md`]: "## Section A\nContent A.\n## Section B\nContent B.",
    };

    // First reindex
    await dispatch(
      { cmd: "search.sessions.reindex", args: { sessionPaths: [SESSION_PATH], fileContents: files } },
      { db } as unknown as RpcContext
    );

    // Second reindex — same content
    const result = await dispatch(
      { cmd: "search.sessions.reindex", args: { sessionPaths: [SESSION_PATH], fileContents: files } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.inserted).toBe(0);
    expect(result.data.skipped).toBe(2);
    expect(result.data.updated).toBe(0);
  });

  it("should delete orphaned chunks when sections are removed", async () => {
    // First reindex — 3 sections
    await dispatch(
      {
        cmd: "search.sessions.reindex",
        args: {
          sessionPaths: [SESSION_PATH],
          fileContents: {
            [`${SESSION_PATH}/LOG.md`]: "## A\nContent A\n## B\nContent B\n## C\nContent C",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    // Second reindex — only 2 sections (C removed)
    const result = await dispatch(
      {
        cmd: "search.sessions.reindex",
        args: {
          sessionPaths: [SESSION_PATH],
          fileContents: {
            [`${SESSION_PATH}/LOG.md`]: "## A\nContent A\n## B\nContent B",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.deleted).toBe(1);
    expect(result.data.skipped).toBe(2);

    const count = await db.get<{ cnt: number }>("SELECT COUNT(*) AS cnt FROM chunks");
    expect(count!.cnt).toBe(2);
  });

  it("should return reconciliation report with correct counts", async () => {
    // First reindex — 3 sections
    await dispatch(
      {
        cmd: "search.sessions.reindex",
        args: {
          sessionPaths: [SESSION_PATH],
          fileContents: {
            [`${SESSION_PATH}/LOG.md`]: "## A\nOriginal A\n## B\nOriginal B\n## C\nOriginal C",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    // Second reindex — A unchanged, B modified, C removed, D added
    const result = await dispatch(
      {
        cmd: "search.sessions.reindex",
        args: {
          sessionPaths: [SESSION_PATH],
          fileContents: {
            [`${SESSION_PATH}/LOG.md`]: "## A\nOriginal A\n## B\nModified B\n## D\nNew D",
          },
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.skipped).toBe(1); // A unchanged
    expect(result.data.updated).toBe(1); // B modified
    expect(result.data.inserted).toBe(1); // D new
    expect(result.data.deleted).toBe(1); // C removed
    expect(result.data.totalChunks).toBe(3);
  });
});
