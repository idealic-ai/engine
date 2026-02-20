import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-session-start.js";
import { createTestDb, queryRow, queryCount } from "../../__tests__/helpers.js";

let db: Database;
let effortId: number;

beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
  dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, db);
  const r = dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } }, db);
  effortId = ((r as any).data.effort as any).id;
});
afterEach(() => { db.close(); });

describe("db.session.start", () => {
  it("should create a session", () => {
    const result = dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 1234 } },
      db
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const session = result.data.session as Record<string, unknown>;
    expect(session.task_id).toBe("sessions/test");
    expect(session.effort_id).toBe(effortId);
    expect(session.pid).toBe(1234);
    expect(session.ended_at).toBeNull();
    expect(session.heartbeat_counter).toBe(0);
  });

  it("should auto-end previous session for same effort", () => {
    dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 111 } }, db);
    dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 222 } }, db);

    // First session should be ended
    const s1 = queryRow(db, "SELECT ended_at FROM sessions WHERE id = 1");
    expect(s1!.ended_at).toBeTruthy();

    // Second should be active
    const s2 = queryRow(db, "SELECT ended_at, pid FROM sessions WHERE id = 2");
    expect(s2!.ended_at).toBeNull();
    expect(s2!.pid).toBe(222);
  });

  it("should set prev_session_id from auto-ended session", () => {
    dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId } }, db);
    const result = dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const session = result.data.session as Record<string, unknown>;
    expect(session.prev_session_id).toBe(1);
  });

  it("should use explicit prevSessionId over auto-detected", () => {
    // Create two sessions — s1 (auto-ended by s2), s2 (active)
    dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId } }, db);
    dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId } }, db);
    // s2 auto-detected prev=1. Now create s3 with explicit prev=1 (not auto-detected s2)
    const result = dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId, prevSessionId: 1 } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const session = result.data.session as Record<string, unknown>;
    expect(session.prev_session_id).toBe(1);
  });

  it("should reject non-existent effortId (FK)", () => {
    const result = dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId: 999 } },
      db
    );
    expect(result.ok).toBe(false);
  });
});
