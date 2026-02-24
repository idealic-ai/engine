import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-session-start.js";
import { createTestDb, queryRow, queryCount } from "../../__tests__/helpers.js";

let db: DbConnection;
let effortId: number;

beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },  { db } as unknown as RpcContext);
  const r = await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },  { db } as unknown as RpcContext);
  effortId = ((r as any).data.effort as any).id;
});
afterEach(async () => { await db.close(); });

describe("db.session.start", () => {
  it("should create a session", async () => {
    const result = await dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 1234 } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const session = result.data.session as Record<string, unknown>;
    expect(session.taskId).toBe("sessions/test");
    expect(session.effortId).toBe(effortId);
    expect(session.pid).toBe(1234);
    expect(session.endedAt).toBeNull();
    expect(session.heartbeatCounter).toBe(0);
  });

  it("should auto-end previous session for same effort", async () => {
    await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 111 } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 222 } },  { db } as unknown as RpcContext);

    // First session should be ended
    const s1 = await queryRow(db, "SELECT ended_at FROM sessions WHERE id = 1");
    expect(s1!.endedAt).toBeTruthy();

    // Second should be active
    const s2 = await queryRow(db, "SELECT ended_at, pid FROM sessions WHERE id = 2");
    expect(s2!.endedAt).toBeNull();
    expect(s2!.pid).toBe(222);
  });

  it("should set prev_session_id from auto-ended session", async () => {
    await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId } },  { db } as unknown as RpcContext);
    const result = await dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const session = result.data.session as Record<string, unknown>;
    expect(session.prevSessionId).toBe(1);
  });

  it("should use explicit prevSessionId over auto-detected", async () => {
    // Create two sessions — s1 (auto-ended by s2), s2 (active)
    await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId } },  { db } as unknown as RpcContext);
    // s2 auto-detected prev=1. Now create s3 with explicit prev=1 (not auto-detected s2)
    const result = await dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId, prevSessionId: 1 } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const session = result.data.session as Record<string, unknown>;
    expect(session.prevSessionId).toBe(1);
  });

  it("should reject non-existent effortId (FK)", async () => {
    const result = await dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId: 999 } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(false);
  });
});
