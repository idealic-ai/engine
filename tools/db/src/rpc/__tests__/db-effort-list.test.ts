import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-effort-list.js";
import { createTestDb } from "../../__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },  { db } as unknown as RpcContext);
});
afterEach(async () => { await db.close(); });

describe("db.effort.list", () => {
  it("should return empty array for task with no efforts", async () => {
    const result = await dispatch(
      { cmd: "db.effort.list", args: { taskId: "sessions/test" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.efforts).toEqual([]);
  });

  it("should return efforts ordered by ordinal", async () => {
    await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "brainstorm" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "test" } },  { db } as unknown as RpcContext);

    const result = await dispatch(
      { cmd: "db.effort.list", args: { taskId: "sessions/test" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const efforts = result.data.efforts as Record<string, unknown>[];
    expect(efforts).toHaveLength(3);
    expect(efforts[0].skill).toBe("brainstorm");
    expect(efforts[0].ordinal).toBe(1);
    expect(efforts[1].skill).toBe("implement");
    expect(efforts[1].ordinal).toBe(2);
    expect(efforts[2].skill).toBe("test");
    expect(efforts[2].ordinal).toBe(3);
  });

  it("should return empty array for non-existent task", async () => {
    const result = await dispatch(
      { cmd: "db.effort.list", args: { taskId: "nonexistent" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.efforts).toEqual([]);
  });
});
