import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-effort-finish.js";
import { createTestDb, queryRow } from "../../__tests__/helpers.js";

let db: Database;
let effortId: number;

beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
  dispatch(
    { cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },
    db
  );
  const r = dispatch(
    { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
    db
  );
  effortId = (r as { ok: true; data: Record<string, unknown> }).data.effort
    ? ((r as { ok: true; data: Record<string, unknown> }).data.effort as Record<string, unknown>).id as number
    : 1;
});
afterEach(() => {
  db.close();
});

describe("db.effort.finish", () => {
  it("should set lifecycle to finished and set finished_at", () => {
    const result = dispatch(
      { cmd: "db.effort.finish", args: { effortId } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.lifecycle).toBe("finished");
    expect(effort.finished_at).toBeTruthy();
  });

  it("should propagate keywords to task", () => {
    const result = dispatch(
      {
        cmd: "db.effort.finish",
        args: { effortId, keywords: "auth,login,middleware" },
      },
      db
    );

    expect(result.ok).toBe(true);
    const task = queryRow(db, "SELECT keywords FROM tasks WHERE dir_path = 'sessions/test'");
    expect(task!.keywords).toBe("auth,login,middleware");
  });

  it("should reject already-finished effort", () => {
    dispatch({ cmd: "db.effort.finish", args: { effortId } }, db);
    const result = dispatch(
      { cmd: "db.effort.finish", args: { effortId } },
      db
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("ALREADY_FINISHED");
  });

  it("should reject non-existent effort", () => {
    const result = dispatch(
      { cmd: "db.effort.finish", args: { effortId: 999 } },
      db
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("NOT_FOUND");
  });
});
