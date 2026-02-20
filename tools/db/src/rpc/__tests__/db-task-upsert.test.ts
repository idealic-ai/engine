import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import { createTestDb, queryRow, queryCount } from "../../__tests__/helpers.js";

let db: Database;
beforeEach(async () => {
  db = await createTestDb();
  // Seed a project for FK
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
});
afterEach(() => {
  db.close();
});

describe("db.task.upsert", () => {
  it("should create a task", () => {
    const result = dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/2026_test", projectId: 1 },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.dir_path).toBe("sessions/2026_test");
    expect(task.project_id).toBe(1);
    expect(task.created_at).toBeTruthy();
  });

  it("should create a task with all optional fields", () => {
    const result = dispatch(
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
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.workspace).toBe("apps/viewer");
    expect(task.title).toBe("Fix Bug");
    expect(task.description).toBe("A detailed description");
  });

  it("should be idempotent — upsert same dirPath returns same task", () => {
    dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1 },
      },
      db
    );
    const result = dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1 },
      },
      db
    );

    expect(result.ok).toBe(true);
    expect(queryCount(db, "SELECT COUNT(*) FROM tasks")).toBe(1);
  });

  it("should update title on re-upsert", () => {
    dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1, title: "Old" },
      },
      db
    );
    const result = dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1, title: "New" },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.title).toBe("New");
  });

  it("should preserve fields when re-upsert omits them", () => {
    dispatch(
      {
        cmd: "db.task.upsert",
        args: {
          dirPath: "sessions/test",
          projectId: 1,
          workspace: "ws",
          title: "Keep",
        },
      },
      db
    );
    const result = dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 1 },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const task = result.data.task as Record<string, unknown>;
    expect(task.workspace).toBe("ws");
    expect(task.title).toBe("Keep");
  });

  it("should reject missing projectId", () => {
    const result = dispatch(
      { cmd: "db.task.upsert", args: { dirPath: "sessions/test" } },
      db
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });

  it("should reject non-existent projectId (FK enforcement)", () => {
    const result = dispatch(
      {
        cmd: "db.task.upsert",
        args: { dirPath: "sessions/test", projectId: 999 },
      },
      db
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("HANDLER_ERROR");
  });
});
