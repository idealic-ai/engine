import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-session-start.js";
import "../db-session-finish.js";
import "../db-session-heartbeat.js";
import "../db-session-update-context.js";
import "../db-session-update-files.js";
import "../db-session-find.js";
import { createTestDb, queryRow } from "../../__tests__/helpers.js";

let db: Database;
let effortId: number;
let sessionId: number;

beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
  dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, db);
  const er = dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } }, db);
  effortId = ((er as any).data.effort as any).id;
  const sr = dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 123 } }, db);
  sessionId = ((sr as any).data.session as any).id;
});
afterEach(() => { db.close(); });

// ── session.start (step 4/1) ──────────────────────────
describe("db.session.start", () => {
  it("should create session with correct fields", () => {
    const s = queryRow(db, "SELECT * FROM sessions WHERE id = ?", [sessionId]);
    expect(s!.task_id).toBe("sessions/test");
    expect(s!.effort_id).toBe(effortId);
    expect(s!.pid).toBe(123);
    expect(s!.ended_at).toBeNull();
  });

  it("should auto-end previous and link", () => {
    const r = dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 456 } }, db);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const s2 = r.data.session as Record<string, unknown>;
    expect(s2.prev_session_id).toBe(sessionId);
    const s1 = queryRow(db, "SELECT ended_at FROM sessions WHERE id = ?", [sessionId]);
    expect(s1!.ended_at).toBeTruthy();
  });

  it("should reject invalid effortId FK", () => {
    const r = dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId: 999 } }, db);
    expect(r.ok).toBe(false);
  });
});

// ── session.finish (step 4/2) ─────────────────────────
describe("db.session.finish", () => {
  it("should end session and set ended_at", () => {
    const r = dispatch({ cmd: "db.session.finish", args: { sessionId } }, db);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const s = r.data.session as Record<string, unknown>;
    expect(s.ended_at).toBeTruthy();
  });

  it("should store dehydration payload", () => {
    const payload = { summary: "test", nextSteps: ["step1"] };
    dispatch({ cmd: "db.session.finish", args: { sessionId, dehydrationPayload: payload } }, db);
    const row = queryRow(db, "SELECT json(dehydration_payload) as dp FROM sessions WHERE id = ?", [sessionId]);
    expect(JSON.parse(row!.dp as string)).toEqual(payload);
  });

  it("should reject already-ended session", () => {
    dispatch({ cmd: "db.session.finish", args: { sessionId } }, db);
    const r = dispatch({ cmd: "db.session.finish", args: { sessionId } }, db);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error).toBe("ALREADY_ENDED");
  });

  it("should reject non-existent session", () => {
    const r = dispatch({ cmd: "db.session.finish", args: { sessionId: 999 } }, db);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error).toBe("NOT_FOUND");
  });
});

// ── session.heartbeat (step 4/3) ──────────────────────
describe("db.session.heartbeat", () => {
  it("should increment counter and update timestamp", () => {
    dispatch({ cmd: "db.session.heartbeat", args: { sessionId } }, db);
    dispatch({ cmd: "db.session.heartbeat", args: { sessionId } }, db);
    const r = dispatch({ cmd: "db.session.heartbeat", args: { sessionId } }, db);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const s = r.data.session as Record<string, unknown>;
    expect(s.heartbeat_counter).toBe(3);
    expect(s.last_heartbeat).toBeTruthy();
  });

  it("should reject non-existent session", () => {
    const r = dispatch({ cmd: "db.session.heartbeat", args: { sessionId: 999 } }, db);
    expect(r.ok).toBe(false);
  });
});

// ── session.updateContextUsage + updateLoadedFiles (step 4/4) ──
describe("db.session.updateContextUsage", () => {
  it("should store context usage float", () => {
    const r = dispatch({ cmd: "db.session.updateContextUsage", args: { sessionId, usage: 0.75 } }, db);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect((r.data.session as any).context_usage).toBeCloseTo(0.75);
  });
});

describe("db.session.updateLoadedFiles", () => {
  it("should store JSONB file list", () => {
    const files = ["src/schema.ts", "src/daemon.ts"];
    const r = dispatch({ cmd: "db.session.updateLoadedFiles", args: { sessionId, files } }, db);
    expect(r.ok).toBe(true);
    const row = queryRow(db, "SELECT json(loaded_files) as lf FROM sessions WHERE id = ?", [sessionId]);
    expect(JSON.parse(row!.lf as string)).toEqual(files);
  });
});

// ── session.find (step 4/5) ───────────────────────────
describe("db.session.find", () => {
  it("should find active session for effort", () => {
    const r = dispatch({ cmd: "db.session.find", args: { effortId } }, db);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const s = r.data.session as Record<string, unknown>;
    expect(s.id).toBe(sessionId);
    expect(s.effort_id).toBe(effortId);
  });

  it("should return null when no active session", () => {
    dispatch({ cmd: "db.session.finish", args: { sessionId } }, db);
    const r = dispatch({ cmd: "db.session.find", args: { effortId } }, db);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.session).toBeNull();
  });

  it("should return null for effort with no sessions", () => {
    dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "brainstorm" } }, db);
    const r = dispatch({ cmd: "db.session.find", args: { effortId: 2 } }, db);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.session).toBeNull();
  });
});
