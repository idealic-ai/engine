import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
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

let db: DbConnection;
let effortId: number;
let sessionId: number;

beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },  { db } as unknown as RpcContext);
  const er = await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },  { db } as unknown as RpcContext);
  effortId = ((er as any).data.effort as any).id;
  const sr = await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 123 } },  { db } as unknown as RpcContext);
  sessionId = ((sr as any).data.session as any).id;
});
afterEach(async () => { await db.close(); });

// ── session.start (step 4/1) ──────────────────────────
describe("db.session.start", () => {
  it("should create session with correct fields", async () => {
    const s = await queryRow(db, "SELECT * FROM sessions WHERE id = ?", [sessionId]);
    expect(s!.taskId).toBe("sessions/test");
    expect(s!.effortId).toBe(effortId);
    expect(s!.pid).toBe(123);
    expect(s!.endedAt).toBeNull();
  });

  it("should auto-end previous and link", async () => {
    const r = await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 456 } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const s2 = r.data.session as Record<string, unknown>;
    expect(s2.prevSessionId).toBe(sessionId);
    const s1 = await queryRow(db, "SELECT ended_at FROM sessions WHERE id = ?", [sessionId]);
    expect(s1!.endedAt).toBeTruthy();
  });

  it("should reject invalid effortId FK", async () => {
    const r = await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId: 999 } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(false);
  });
});

// ── session.finish (step 4/2) ─────────────────────────
describe("db.session.finish", () => {
  it("should end session and set ended_at", async () => {
    const r = await dispatch({ cmd: "db.session.finish", args: { sessionId } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const s = r.data.session as Record<string, unknown>;
    expect(s.endedAt).toBeTruthy();
  });

  it("should store dehydration payload", async () => {
    const payload = { summary: "test", nextSteps: ["step1"] };
    await dispatch({ cmd: "db.session.finish", args: { sessionId, dehydrationPayload: payload } },  { db } as unknown as RpcContext);
    const row = await queryRow(db, "SELECT json(dehydration_payload) as dp FROM sessions WHERE id = ?", [sessionId]);
    const dp = typeof row!.dp === "string" ? JSON.parse(row!.dp) : row!.dp;
    expect(dp).toEqual(payload);
  });

  it("should reject already-ended session", async () => {
    await dispatch({ cmd: "db.session.finish", args: { sessionId } },  { db } as unknown as RpcContext);
    const r = await dispatch({ cmd: "db.session.finish", args: { sessionId } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error).toBe("ALREADY_ENDED");
  });

  it("should reject non-existent session", async () => {
    const r = await dispatch({ cmd: "db.session.finish", args: { sessionId: 999 } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error).toBe("NOT_FOUND");
  });
});

// ── session.heartbeat (step 4/3) ──────────────────────
describe("db.session.heartbeat", () => {
  it("should increment counter and update timestamp", async () => {
    await dispatch({ cmd: "db.session.heartbeat", args: { sessionId } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.session.heartbeat", args: { sessionId } },  { db } as unknown as RpcContext);
    const r = await dispatch({ cmd: "db.session.heartbeat", args: { sessionId } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const s = r.data.session as Record<string, unknown>;
    expect(s.heartbeatCounter).toBe(3);
    expect(s.lastHeartbeat).toBeTruthy();
  });

  it("should reject non-existent session", async () => {
    const r = await dispatch({ cmd: "db.session.heartbeat", args: { sessionId: 999 } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(false);
  });
});

// ── session.updateContextUsage + updateLoadedFiles (step 4/4) ──
describe("db.session.updateContextUsage", () => {
  it("should store context usage float", async () => {
    const r = await dispatch({ cmd: "db.session.updateContextUsage", args: { sessionId, usage: 0.75 } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect((r.data.session as any).contextUsage).toBeCloseTo(0.75);
  });
});

describe("db.session.updateLoadedFiles", () => {
  it("should store JSONB file list", async () => {
    const files = ["src/schema.ts", "src/daemon.ts"];
    const r = await dispatch({ cmd: "db.session.updateLoadedFiles", args: { sessionId, files } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(true);
    const row = await queryRow(db, "SELECT json(loaded_files) as lf FROM sessions WHERE id = ?", [sessionId]);
    const lf = typeof row!.lf === "string" ? JSON.parse(row!.lf as string) : row!.lf;
    expect(lf).toEqual(files);
  });
});

// ── session.find (step 4/5) ───────────────────────────
describe("db.session.find", () => {
  it("should find active session for effort", async () => {
    const r = await dispatch({ cmd: "db.session.find", args: { effortId } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const s = r.data.session as Record<string, unknown>;
    expect(s.id).toBe(sessionId);
    expect(s.effortId).toBe(effortId);
  });

  it("should return null when no active session", async () => {
    await dispatch({ cmd: "db.session.finish", args: { sessionId } },  { db } as unknown as RpcContext);
    const r = await dispatch({ cmd: "db.session.find", args: { effortId } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.session).toBeNull();
  });

  it("should return null for effort with no sessions", async () => {
    await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "brainstorm" } },  { db } as unknown as RpcContext);
    const r = await dispatch({ cmd: "db.session.find", args: { effortId: 2 } },  { db } as unknown as RpcContext);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.session).toBeNull();
  });
});
