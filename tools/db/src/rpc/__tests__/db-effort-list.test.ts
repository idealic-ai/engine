import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-effort-list.js";
import { createTestDb } from "../../__tests__/helpers.js";

let db: Database;
beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
  dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, db);
});
afterEach(() => { db.close(); });

describe("db.effort.list", () => {
  it("should return empty array for task with no efforts", () => {
    const result = dispatch(
      { cmd: "db.effort.list", args: { taskId: "sessions/test" } },
      db
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.efforts).toEqual([]);
  });

  it("should return efforts ordered by ordinal", () => {
    dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "brainstorm" } }, db);
    dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } }, db);
    dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "test" } }, db);

    const result = dispatch(
      { cmd: "db.effort.list", args: { taskId: "sessions/test" } },
      db
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

  it("should return empty array for non-existent task", () => {
    const result = dispatch(
      { cmd: "db.effort.list", args: { taskId: "nonexistent" } },
      db
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.efforts).toEqual([]);
  });
});
