import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import { createTestDb, queryRow, queryCount, queryRows } from "../../__tests__/helpers.js";

let db: Database;
beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
  dispatch(
    { cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },
    db
  );
});
afterEach(() => {
  db.close();
});

describe("db.effort.start", () => {
  it("should create an effort with ordinal 1 for first effort", () => {
    const result = dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.task_id).toBe("sessions/test");
    expect(effort.skill).toBe("implement");
    expect(effort.ordinal).toBe(1);
    expect(effort.lifecycle).toBe("active");
    expect(effort.created_at).toBeTruthy();
  });

  it("should auto-increment ordinal for subsequent efforts", () => {
    dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "brainstorm" },
      },
      db
    );
    const result = dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.ordinal).toBe(2);
  });

  it("should store mode when provided", () => {
    const result = dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement", mode: "tdd" },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.mode).toBe("tdd");
  });

  it("should store JSONB metadata", () => {
    const metadata = { taskSummary: "Build feature X", scope: "code changes" };
    const result = dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement", metadata },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const row = queryRow(
      db,
      "SELECT json_extract(metadata, '$.taskSummary') as summary FROM efforts WHERE id = 1"
    );
    expect(row!.summary).toBe("Build feature X");
  });

  it("should reject missing taskId (FK enforcement)", () => {
    const result = dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "nonexistent", skill: "implement" },
      },
      db
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("HANDLER_ERROR");
  });

  it("should handle ordinal correctly after effort gaps", () => {
    // Create effort 1 and 2
    dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "brainstorm" } },
      db
    );
    dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      db
    );

    // Delete effort 2 (simulating a gap)
    db.run("DELETE FROM efforts WHERE ordinal = 2 AND task_id = 'sessions/test'");

    // Next effort should be 3, not 2 (MAX-based)
    const result = dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "fix" } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    // After deleting ordinal 2, MAX is 1, so next is 2
    expect(effort.ordinal).toBe(2);
  });

  it("should isolate ordinals per task", () => {
    // Create another task
    dispatch(
      { cmd: "db.task.upsert", args: { dirPath: "sessions/other", projectId: 1 } },
      db
    );

    dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "impl" } },
      db
    );
    dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "impl2" } },
      db
    );

    const result = dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/other", skill: "impl" } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.ordinal).toBe(1); // First effort for this task
  });
});
