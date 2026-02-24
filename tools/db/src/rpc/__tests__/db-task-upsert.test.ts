import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import { createTestDb, queryRow, queryCount } from "../../__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
  // Seed a project for FK
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
});
afterEach(async () => {
  await db.close();
});

describe("db.task.upsert", () => {
  it("should create a task", async () => {
    const result = await dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/2026_test", projectId: 1 },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.dirPath).toBe("sessions/2026_test");
    expect(task.projectId).toBe(1);
    expect(task.createdAt).toBeTruthy();
  });

  it("should create a task with all optional fields", async () => {
    const result = await dispatch(
      {
        cmd: "db.task.upsert",
        args: {
          dirPath: "sessions/test",
          projectId: 1,
          workspace: "apps/viewer",
          title: "Fix Bug",
          description: "A detailed description",
        },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.workspace).toBe("apps/viewer");
    expect(task.title).toBe("Fix Bug");
    expect(task.description).toBe("A detailed description");
  });

  it("should be idempotent — upsert same dirPath returns same task", async () => {
    await dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1 },
      },
      { db } as unknown as RpcContext
    );
    const result = await dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1 },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    expect(await queryCount(db, "SELECT COUNT(*) FROM tasks")).toBe(1);
  });

  it("should update title on re-upsert", async () => {
    await dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1, title: "Old" },
      },
      { db } as unknown as RpcContext
    );
    const result = await dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1, title: "New" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.title).toBe("New");
  });

  it("should preserve fields when re-upsert omits them", async () => {
    await dispatch(
      {
        cmd: "db.task.upsert",
        args: {
          dirPath: "sessions/test",
          projectId: 1,
          workspace: "ws",
          title: "Keep",
        },
      },
      { db } as unknown as RpcContext
    );
    const result = await dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1 },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.workspace).toBe("ws");
    expect(task.title).toBe("Keep");
  });

  it("should reject missing projectId", async () => {
    const result = await dispatch(
      { cmd: "db.task.upsert", args: { dirPath: "sessions/test" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });

  it("should reject non-existent projectId (FK enforcement)", async () => {
    const result = await dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 999 },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("HANDLER_ERROR");
  });
});
