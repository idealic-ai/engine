import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import { createTestDb, queryRow, queryCount, queryRows } from "../../__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
  await dispatch(
    { cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },
      { db } as unknown as RpcContext
  );
});
afterEach(async () => {
  await db.close();
});

describe("db.effort.start", () => {
  it("should create an effort with ordinal 1 for first effort", async () => {
    const result = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.taskId).toBe("sessions/test");
    expect(effort.skill).toBe("implement");
    expect(effort.ordinal).toBe(1);
    expect(effort.lifecycle).toBe("active");
    expect(effort.createdAt).toBeTruthy();
  });

  it("should auto-increment ordinal for subsequent efforts", async () => {
    await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "brainstorm" },
      },
      { db } as unknown as RpcContext
    );
    const result = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.ordinal).toBe(2);
  });

  it("should store mode when provided", async () => {
    const result = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement", mode: "tdd" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.mode).toBe("tdd");
  });

  it("should store JSONB metadata", async () => {
    const metadata = { taskSummary: "Build feature X", scope: "code changes" };
    const result = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement", metadata },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const row = await queryRow(
      db,
      "SELECT json_extract(metadata, '$.taskSummary') as summary FROM efforts WHERE id = 1"
    );
    expect(row!.summary).toBe("Build feature X");
  });

  it("should reject missing taskId (FK enforcement)", async () => {
    const result = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "nonexistent", skill: "implement" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("HANDLER_ERROR");
  });

  it("should handle ordinal correctly after effort gaps", async () => {
    // Create effort 1 and 2
    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "brainstorm" } },
      { db } as unknown as RpcContext
    );
    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      { db } as unknown as RpcContext
    );

    // Delete effort 2 (simulating a gap)
    await db.run("DELETE FROM efforts WHERE ordinal = 2 AND task_id = 'sessions/test'");

    // Next effort should be 3, not 2 (MAX-based)
    const result = await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "fix" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    // After deleting ordinal 2, MAX is 1, so next is 2
    expect(effort.ordinal).toBe(2);
  });

  it("should isolate ordinals per task", async () => {
    // Create another task
    await dispatch(
      { cmd: "db.task.upsert", args: { dirPath: "sessions/other", projectId: 1 } },
      { db } as unknown as RpcContext
    );

    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "impl" } },
      { db } as unknown as RpcContext
    );
    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "impl2" } },
      { db } as unknown as RpcContext
    );

    const result = await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/other", skill: "impl" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.ordinal).toBe(1); // First effort for this task
  });
});
