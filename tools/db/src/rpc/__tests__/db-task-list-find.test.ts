import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-skills-upsert.js";
import "../db-task-list.js";
import "../db-task-find.js";
import { createTestDb } from "../../__tests__/helpers.js";

let db: Database;
beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
});
afterEach(() => {
  db.close();
});

describe("db.task.list", () => {
  it("should return all tasks", () => {
    dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/task_a", projectId: 1, title: "Task A" } }, db);
    dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/task_b", projectId: 1, title: "Task B" } }, db);

    const result = dispatch({ cmd: "db.task.list", args: {} }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const tasks = result.data.tasks as Record<string, unknown>[];
    expect(tasks).toHaveLength(2);
  });

  it("should respect limit parameter", () => {
    dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/a", projectId: 1 } }, db);
    dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/b", projectId: 1 } }, db);
    dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/c", projectId: 1 } }, db);

    const result = dispatch({ cmd: "db.task.list", args: { limit: 2 } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.tasks).toHaveLength(2);
  });

  it("should filter by projectId", () => {
    dispatch({ cmd: "db.project.upsert", args: { path: "/proj2" } }, db);
    dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/a", projectId: 1 } }, db);
    dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/b", projectId: 2 } }, db);

    const result = dispatch({ cmd: "db.task.list", args: { projectId: 1 } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.tasks).toHaveLength(1);
  });

  it("should return empty array when no tasks", () => {
    const result = dispatch({ cmd: "db.task.list", args: {} }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.tasks).toEqual([]);
  });
});

describe("db.task.find", () => {
  it("should find task by dirPath with effort count", () => {
    dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/task_a", projectId: 1, title: "Task A" } }, db);
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, db);
    dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/task_a", skill: "implement" } }, db);

    const result = dispatch({ cmd: "db.task.find", args: { dirPath: "sessions/task_a" } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.dir_path).toBe("sessions/task_a");
    expect(task.title).toBe("Task A");
    expect(task.effort_count).toBe(1);
  });

  it("should return null for non-existent task", () => {
    const result = dispatch({ cmd: "db.task.find", args: { dirPath: "sessions/nonexistent" } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.task).toBeNull();
  });
});
