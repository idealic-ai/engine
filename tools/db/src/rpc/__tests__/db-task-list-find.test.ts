import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-skills-upsert.js";
import "../db-task-list.js";
import "../db-task-find.js";
import { createTestDb } from "../../__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
});
afterEach(async () => {
  await db.close();
});

describe("db.task.list", () => {
  it("should return all tasks", async () => {
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/task_a", projectId: 1, title: "Task A" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/task_b", projectId: 1, title: "Task B" } },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.task.list", args: {} },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const tasks = result.data.tasks as Record<string, unknown>[];
    expect(tasks).toHaveLength(2);
  });

  it("should respect limit parameter", async () => {
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/a", projectId: 1 } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/b", projectId: 1 } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/c", projectId: 1 } },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.task.list", args: { limit: 2 } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.tasks).toHaveLength(2);
  });

  it("should filter by projectId", async () => {
    await dispatch({ cmd: "db.project.upsert", args: { path: "/proj2" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/a", projectId: 1 } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/b", projectId: 2 } },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.task.list", args: { projectId: 1 } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.tasks).toHaveLength(1);
  });

  it("should return empty array when no tasks", async () => {
    const result = await dispatch({ cmd: "db.task.list", args: {} },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.tasks).toEqual([]);
  });
});

describe("db.task.find", () => {
  it("should find task by dirPath with effort count", async () => {
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/task_a", projectId: 1, title: "Task A" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/task_a", skill: "implement" } },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.task.find", args: { dirPath: "sessions/task_a" } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.dirPath).toBe("sessions/task_a");
    expect(task.title).toBe("Task A");
    expect(task.effortCount).toBe(1);
  });

  it("should return null for non-existent task", async () => {
    const result = await dispatch({ cmd: "db.task.find", args: { dirPath: "sessions/nonexistent" } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.task).toBeNull();
  });
});
