import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-effort-finish.js";
import { createTestDb, queryRow } from "../../__tests__/helpers.js";

let db: DbConnection;
let effortId: number;

beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
  await dispatch(
    { cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },
      { db } as unknown as RpcContext
  );
  const r = await dispatch(
    { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      { db } as unknown as RpcContext
  );
  effortId = (r as { ok: true; data: Record<string, unknown> }).data.effort
    ? ((r as { ok: true; data: Record<string, unknown> }).data.effort as Record<string, unknown>).id as number
    : 1;
});
afterEach(async () => {
  await db.close();
});

describe("db.effort.finish", () => {
  it("should set lifecycle to finished and set finished_at", async () => {
    const result = await dispatch(
      { cmd: "db.effort.finish", args: { effortId } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.lifecycle).toBe("finished");
    expect(effort.finishedAt).toBeTruthy();
  });

  it("should propagate keywords to task", async () => {
    const result = await dispatch(
      {
        cmd: "db.effort.finish",
        args: { effortId, keywords: "auth,login,middleware" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    const task = await queryRow(db, "SELECT keywords FROM tasks WHERE dir_path = 'sessions/test'");
    expect(task!.keywords).toBe("auth,login,middleware");
  });

  it("should reject already-finished effort", async () => {
    await dispatch({ cmd: "db.effort.finish", args: { effortId } },  { db } as unknown as RpcContext);
    const result = await dispatch(
      { cmd: "db.effort.finish", args: { effortId } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("ALREADY_FINISHED");
  });

  it("should reject non-existent effort", async () => {
    const result = await dispatch(
      { cmd: "db.effort.finish", args: { effortId: 999 } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("NOT_FOUND");
  });
});
