import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import "../search-reindex.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
});
afterEach(async () => {
  await db.close();
});

describe("search.reindex", () => {
  it("should return not_implemented status", async () => {
    const result = await dispatch({ cmd: "search.reindex", args: {} }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.status).toBe("not_implemented");
    expect(result.data.message).toBe("Requires fs.* and ai.* RPCs");
  });

  it("should accept optional sourceTypes without error", async () => {
    const result = await dispatch(
      { cmd: "search.reindex", args: { sourceTypes: ["session", "doc"] } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.status).toBe("not_implemented");
  });

  it("should accept empty sourceTypes array", async () => {
    const result = await dispatch(
      { cmd: "search.reindex", args: { sourceTypes: [] } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.status).toBe("not_implemented");
  });
});
