import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch, getRegistry } from "engine-shared/dispatch";
import { buildNamespace } from "engine-shared/namespace-builder";
import "../../../../db/src/rpc/registry.js";
import "../../../../agent/src/rpc/agent-messages-ingest.js";
import "../hooks-user-prompt.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

let db: DbConnection;
let ctx: RpcContext;

/** Common base args for UserPromptSubmit dispatch (snake_case) */
const BASE = {
  session_id: "test-session",
  transcript_path: "/tmp/transcript.jsonl",
  cwd: "/proj",
  permission_mode: "default",
  hook_event_name: "UserPromptSubmit",
  prompt: "test prompt",
};

function buildFullContext(database: DbConnection): RpcContext {
  const context = {} as RpcContext;
  const registry = getRegistry();
  const dbNs = buildNamespace("db", registry, context);
  context.db = Object.assign(database as object, dbNs) as unknown as RpcContext["db"];
  const agentNs = buildNamespace("agent", registry, context);
  context.agent = agentNs as unknown as RpcContext["agent"];
  context.env = { CWD: "/proj", AGENT_ID: "default" } as RpcContext["env"];
  return context;
}

beforeEach(async () => {
  db = await createTestDb();
  ctx = buildFullContext(db);
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
  await dispatch(
    { cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },
    ctx
  );
});
afterEach(async () => {
  // Allow fire-and-forget ingestion promises to settle before closing DB
  await new Promise((r) => setTimeout(r, 50));
  await db.close();
});

describe("hooks.userPrompt", () => {
  it("returns formatted context line with skill, phase, heartbeat for active effort+session", async () => {
    const effortRes = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;

    await dispatch(
      {
        cmd: "db.effort.phase",
        args: { effortId, phase: "3: Execution" },
      },
      ctx
    );

    await dispatch(
      {
        cmd: "db.session.start",
        args: { taskId: "sessions/test", effortId, pid: 1234 },
      },
      ctx
    );

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;

    expect(data.effortId).toBe(effortId);
    expect(data.sessionId).toBeTypeOf("number");
    expect(data.taskDir).toBe("sessions/test");
    expect(data.skill).toBe("implement");
    expect(data.phase).toBe("3: Execution");
    expect(data.heartbeat).toBe("0/10");
    expect(data.sessionContext).toContain("sessions/test");
    expect(data.sessionContext).toContain("implement");
    expect(data.sessionContext).toContain("3: Execution");
    expect(data.sessionContext).toContain("0/10");
  });

  it("returns empty context when no active effort exists", async () => {
    // Use a cwd with no effort
    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE, cwd: "/nonexistent" } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;

    expect(data.sessionContext).toBe("");
    expect(data.effortId).toBeNull();
    expect(data.sessionId).toBeNull();
    expect(data.taskDir).toBeNull();
    expect(data.skill).toBeNull();
    expect(data.phase).toBeNull();
    expect(data.heartbeat).toBe("0/10");
  });

  it("includes phase in context line when effort has a phase", async () => {
    const effortRes = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "analyze" },
      },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;

    await dispatch(
      {
        cmd: "db.effort.phase",
        args: { effortId, phase: "2: Planning" },
      },
      ctx
    );

    await dispatch(
      {
        cmd: "db.session.start",
        args: { taskId: "sessions/test", effortId },
      },
      ctx
    );

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;

    expect(data.phase).toBe("2: Planning");
    expect(data.sessionContext).toContain("Phase: 2: Planning");
  });

  it("formats heartbeat as N/M pattern", async () => {
    const effortRes = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;

    await dispatch(
      {
        cmd: "db.session.start",
        args: { taskId: "sessions/test", effortId },
      },
      ctx
    );

    // Manually bump heartbeat_counter to 3
    await db.run(
      "UPDATE sessions SET heartbeat_counter = 3 WHERE effort_id = ? AND ended_at IS NULL",
      [effortId]
    );

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;

    expect(data.heartbeat).toBe("3/10");
    expect(data.sessionContext).toContain("3/10");
  });

  // ── Hardening: negative blockAfter in metadata ─────────────────
  it("handles negative blockAfter by using it as-is (documents behavior)", async () => {
    const effortRes = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;

    await dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId } },
      ctx
    );

    await db.run(
      "UPDATE efforts SET metadata = json(?) WHERE id = ?",
      [JSON.stringify({ blockAfter: -5 }), effortId]
    );

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    // Documents that negative blockAfter is used as-is
    expect(data.heartbeat).toBe("0/-5");
  });

  // ── Hardening: multiple active sessions (race condition) ──────
  it("picks most recent session when multiple are active", async () => {
    const effortRes = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;

    // Create first session
    const s1 = await dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 100 } },
      ctx
    );
    const sessionId1 = (s1 as any).data.session.id as number;

    // Create second session (simulating race — don't end first)
    await db.run(
      `INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat)
       VALUES ('sessions/test', ?, 200, datetime('now'))`,
      [effortId]
    );
    const s2Row = await db.get<{ id: number }>("SELECT MAX(id) as id FROM sessions");
    const sessionId2 = s2Row!.id;

    // Set different heartbeat counters to distinguish
    await db.run("UPDATE sessions SET heartbeat_counter = 3 WHERE id = ?", [sessionId1]);
    await db.run("UPDATE sessions SET heartbeat_counter = 7 WHERE id = ?", [sessionId2]);

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    // Should pick the most recent (higher id = sessionId2 with counter 7)
    expect(data.sessionId).toBe(sessionId2);
    expect(data.heartbeat).toContain("7/");
  });

  // ── Hardening: malformed metadata JSON string ─────────────────
  it("falls back to default blockAfter when metadata is corrupt JSON", async () => {
    const effortRes = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;

    await dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId } },
      ctx
    );

    // Set corrupt metadata
    await db.run(
      "UPDATE efforts SET metadata = ? WHERE id = ?",
      ["this-is-not-json{{{", effortId]
    );

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    // Should fall back to DEFAULT_BLOCK_AFTER (10)
    expect(data.heartbeat).toBe("0/10");
  });

  it("should pass through null heartbeat_counter without coalescing (documents behavior)", async () => {
    const effortRes = await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;
    await dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId } },
      ctx
    );
    // Force heartbeat_counter to NULL
    await db.run("UPDATE sessions SET heartbeat_counter = NULL WHERE effort_id = ?", [effortId]);

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    // Documents: null heartbeat_counter is NOT coalesced to 0 in the format string
    expect(result.data.heartbeat).toBe("null/10");
  });

  it("should handle effort with no session (effort exists, session missing)", async () => {
    const effortRes = await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;
    // No session created — session.find returns null

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.sessionId).toBeNull();
    expect(result.data.heartbeat).toBe("0/10");
    expect(result.data.sessionContext).toContain("Heartbeat: 0/10");
  });

  it("should format heartbeat with blockAfter=0", async () => {
    const effortRes = await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;
    await dispatch(
      { cmd: "db.session.start", args: { taskId: "sessions/test", effortId } },
      ctx
    );
    await db.run(
      "UPDATE efforts SET metadata = json(?) WHERE id = ?",
      [JSON.stringify({ blockAfter: 0 }), effortId]
    );

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.heartbeat).toBe("0/0");
  });

  it("uses custom threshold from effort metadata", async () => {
    const effortRes = await dispatch(
      {
        cmd: "db.effort.start",
        args: { taskId: "sessions/test", skill: "implement" },
      },
      ctx
    );
    const effortId = (effortRes as any).data.effort.id as number;

    await dispatch(
      {
        cmd: "db.session.start",
        args: { taskId: "sessions/test", effortId },
      },
      ctx
    );

    // Set custom threshold in effort metadata
    await db.run(
      "UPDATE efforts SET metadata = json(?) WHERE id = ?",
      [JSON.stringify({ blockAfter: 5 }), effortId]
    );

    // Set heartbeat to 2
    await db.run(
      "UPDATE sessions SET heartbeat_counter = 2 WHERE effort_id = ? AND ended_at IS NULL",
      [effortId]
    );

    const result = await dispatch(
      { cmd: "hooks.userPrompt", args: { ...BASE } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;

    expect(data.heartbeat).toBe("2/5");
    expect(data.sessionContext).toContain("2/5");
  });
});
