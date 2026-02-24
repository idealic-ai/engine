/**
 * Tests for lifecycle hook RPCs:
 *   hooks.stop, hooks.sessionEnd, hooks.postToolUseFailure,
 *   hooks.permissionRequest, hooks.subagentStart, hooks.subagentStop,
 *   hooks.teammateIdle, hooks.taskCompleted
 */
import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import "../../../../db/src/rpc/registry.js";
import "../hooks-stop.js";
import "../hooks-session-end.js";
import "../hooks-post-tool-use-failure.js";
import "../hooks-permission-request.js";
import "../hooks-subagent-start.js";
import "../hooks-subagent-stop.js";
import "../hooks-teammate-idle.js";
import "../hooks-task-completed.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";
import { createTestContext } from "engine-shared/__tests__/test-context";

let db: DbConnection;
let ctx: RpcContext;

// Test scaffolding: project + task + effort + session + agent
let effortId: number;
let sessionId: number;
const AGENT_ID = "test-agent";

/** Common hook base fields (snake_case — transformKeys converts to camelCase) */
const HOOK_BASE = {
  session_id: "test-session",
  transcript_path: "/tmp/transcript.jsonl",
  cwd: "/proj",
  permission_mode: "default",
};

beforeEach(async () => {
  db = await createTestDb();
  ctx = createTestContext(db);

  // Setup: project → task → effort → session → agent
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, ctx);
  await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, ctx);

  const effortResult = await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } }, ctx);
  if (!effortResult.ok) throw new Error("effort.start failed");
  effortId = (effortResult.data as Record<string, unknown>).effort
    ? ((effortResult.data as Record<string, unknown>).effort as Record<string, unknown>).id as number
    : 1;

  const sessionResult = await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId } }, ctx);
  if (!sessionResult.ok) throw new Error("session.start failed");
  sessionId = ((sessionResult.data as Record<string, unknown>).session as Record<string, unknown>).id as number;

  await dispatch({ cmd: "db.agents.register", args: { id: AGENT_ID, label: "Worker", effortId } }, ctx);
});

afterEach(async () => {
  await db.close();
});

// ── helpers ────────────────────────────────────────────────

async function getAgentStatus(): Promise<string | null> {
  const result = await dispatch({ cmd: "db.agents.get", args: { id: AGENT_ID } }, ctx);
  if (!result.ok) return null;
  const agent = (result.data as Record<string, unknown>).agent as Record<string, unknown> | null;
  return agent ? (agent.status as string | null) : null;
}

// ── hooks.stop ─────────────────────────────────────────────

describe("hooks.stop", () => {
  it("should set agent status to done", async () => {
    const result = await dispatch({
      cmd: "hooks.stop",
      args: { ...HOOK_BASE, hook_event_name: "Stop", stop_hook_active: true, last_assistant_message: "done" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(true);
    expect(await getAgentStatus()).toBe("done");
  });

  it("should fail-open when no effort found via cwd", async () => {
    const result = await dispatch({
      cmd: "hooks.stop",
      args: { ...HOOK_BASE, hook_event_name: "Stop", cwd: "/nonexistent", stop_hook_active: true, last_assistant_message: "" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(false);
  });

  it("should fail-open when no agent bound to effort", async () => {
    // Create a project with no agent
    await dispatch({ cmd: "db.project.upsert", args: { path: "/other" } }, ctx);
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/other", projectId: 2 } }, ctx);
    const er = await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/other", skill: "implement" } }, ctx);
    await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/other", effortId: (er as any).data.effort.id } }, ctx);

    const result = await dispatch({
      cmd: "hooks.stop",
      args: { ...HOOK_BASE, hook_event_name: "Stop", cwd: "/other", stop_hook_active: true, last_assistant_message: "" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(false);
  });
});

// ── hooks.sessionEnd ───────────────────────────────────────

describe("hooks.sessionEnd", () => {
  it("should end session and set agent status to done", async () => {
    const result = await dispatch({
      cmd: "hooks.sessionEnd",
      args: { ...HOOK_BASE, hook_event_name: "SessionEnd", reason: "user_exit" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.sessionEnded).toBe(true);
    expect(data.agentUpdated).toBe(true);
    expect(await getAgentStatus()).toBe("done");
  });

  it("should handle already-ended session gracefully", async () => {
    // End it once
    await dispatch({
      cmd: "hooks.sessionEnd",
      args: { ...HOOK_BASE, hook_event_name: "SessionEnd", reason: "user_exit" },
    }, ctx);
    // End it again — should fail-open
    const result = await dispatch({
      cmd: "hooks.sessionEnd",
      args: { ...HOOK_BASE, hook_event_name: "SessionEnd", reason: "user_exit" },
    }, ctx);
    expect(result.ok).toBe(true);
  });
});

// ── hooks.postToolUseFailure ───────────────────────────────

describe("hooks.postToolUseFailure", () => {
  it("should set agent status to error and log message", async () => {
    const result = await dispatch({
      cmd: "hooks.postToolUseFailure",
      args: { ...HOOK_BASE, hook_event_name: "PostToolUseFailure", tool_name: "Bash", tool_input: {}, tool_use_id: "tu_1", error: "Command failed" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.agentUpdated).toBe(true);
    expect(data.messageLogged).toBe(true);
    expect(await getAgentStatus()).toBe("error");
  });

  it("should fail-open when no effort found via cwd", async () => {
    const result = await dispatch({
      cmd: "hooks.postToolUseFailure",
      args: { ...HOOK_BASE, hook_event_name: "PostToolUseFailure", cwd: "/nonexistent", tool_name: "Bash", tool_input: {}, tool_use_id: "tu_1", error: "oops" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(false);
    expect((result.data as Record<string, unknown>).messageLogged).toBe(false);
  });

  it("should handle missing session gracefully", async () => {
    // Create project/effort with no session at a different path
    await dispatch({ cmd: "db.project.upsert", args: { path: "/nosession" } }, ctx);
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/nosession", projectId: 2 } }, ctx);
    const er = await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/nosession", skill: "implement" } }, ctx);
    const noSessionEffortId = (er as any).data.effort.id as number;
    // Register agent for this effort
    await dispatch({ cmd: "db.agents.register", args: { id: "agent-nosession", label: "Worker", effortId: noSessionEffortId } }, ctx);

    const result = await dispatch({
      cmd: "hooks.postToolUseFailure",
      args: { ...HOOK_BASE, hook_event_name: "PostToolUseFailure", cwd: "/nosession", tool_name: "Bash", tool_input: {}, tool_use_id: "tu_1", error: "crash" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(true);
    expect((result.data as Record<string, unknown>).messageLogged).toBe(false);
  });
});

// ── hooks.permissionRequest ────────────────────────────────

describe("hooks.permissionRequest", () => {
  it("should set agent status to attention", async () => {
    const result = await dispatch({
      cmd: "hooks.permissionRequest",
      args: { ...HOOK_BASE, hook_event_name: "PermissionRequest", tool_name: "Bash", tool_input: {} },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(true);
    expect(await getAgentStatus()).toBe("attention");
  });

  it("should fail-open when no effort found via cwd", async () => {
    const result = await dispatch({
      cmd: "hooks.permissionRequest",
      args: { ...HOOK_BASE, hook_event_name: "PermissionRequest", cwd: "/nonexistent", tool_name: "Bash", tool_input: {} },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(false);
  });
});

// ── hooks.subagentStart ────────────────────────────────────

describe("hooks.subagentStart", () => {
  it("should create a new session linked to parent effort", async () => {
    const result = await dispatch({
      cmd: "hooks.subagentStart",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStart", agent_id: "sub-1", agent_type: "builder" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.sessionId).toBeTypeOf("number");
    expect(data.effortId).toBe(effortId);
    // New session should be different from parent
    expect(data.sessionId).not.toBe(sessionId);
  });

  it("should fail-open when no parent info resolved from cwd", async () => {
    const result = await dispatch({
      cmd: "hooks.subagentStart",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStart", cwd: "/nonexistent", agent_id: "sub-1", agent_type: "builder" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.sessionId).toBeNull();
  });

  it("should derive effortId from parent session via cwd", async () => {
    const result = await dispatch({
      cmd: "hooks.subagentStart",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStart", agent_id: "sub-2", agent_type: "builder" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).effortId).toBe(effortId);
  });
});

// ── hooks.subagentStop ─────────────────────────────────────

describe("hooks.subagentStop", () => {
  it("should end the sub-agent session", async () => {
    // Create sub-agent session first
    const startResult = await dispatch({
      cmd: "hooks.subagentStart",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStart", agent_id: "sub-stop-1", agent_type: "builder" },
    }, ctx);
    if (!startResult.ok) throw new Error("subagentStart failed");
    const subSessionId = (startResult.data as Record<string, unknown>).sessionId as number;

    // For subagentStop, the cwd still resolves to the same project/effort/session
    const result = await dispatch({
      cmd: "hooks.subagentStop",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStop", stop_hook_active: false, agent_id: "sub-stop-1", agent_type: "builder", agent_transcript_path: "/tmp/sub.jsonl", last_assistant_message: "done" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).sessionEnded).toBe(true);
  });

  it("should fail-open when no session resolved from cwd", async () => {
    const result = await dispatch({
      cmd: "hooks.subagentStop",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStop", cwd: "/nonexistent", stop_hook_active: false, agent_id: "sub-1", agent_type: "builder", agent_transcript_path: "/tmp/sub.jsonl", last_assistant_message: "" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).sessionEnded).toBe(false);
  });
});

// ── hooks.teammateIdle ─────────────────────────────────────

describe("hooks.teammateIdle", () => {
  it("should log teammate idle event to messages", async () => {
    const result = await dispatch({
      cmd: "hooks.teammateIdle",
      args: { ...HOOK_BASE, hook_event_name: "TeammateIdle", teammate_name: "Worker-2", team_name: "auth" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).messageLogged).toBe(true);
  });

  it("should fail-open when no session resolved from cwd", async () => {
    const result = await dispatch({
      cmd: "hooks.teammateIdle",
      args: { ...HOOK_BASE, hook_event_name: "TeammateIdle", cwd: "/nonexistent", teammate_name: "W", team_name: "T" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).messageLogged).toBe(false);
  });
});

// ── hooks.taskCompleted ────────────────────────────────────

describe("hooks.taskCompleted", () => {
  it("should log task completion to messages", async () => {
    const result = await dispatch({
      cmd: "hooks.taskCompleted",
      args: { ...HOOK_BASE, hook_event_name: "TaskCompleted", task_id: "task-123", task_subject: "Build feature X" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).messageLogged).toBe(true);
  });

  it("should fail-open when no session resolved from cwd", async () => {
    const result = await dispatch({
      cmd: "hooks.taskCompleted",
      args: { ...HOOK_BASE, hook_event_name: "TaskCompleted", cwd: "/nonexistent", task_id: "t", task_subject: "s" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).messageLogged).toBe(false);
  });
});

// ── Coverage expansion: hooks.stop idempotency ────────────

describe("hooks.stop — coverage expansion", () => {
  it("should be idempotent (stop twice is safe)", async () => {
    await dispatch({
      cmd: "hooks.stop",
      args: { ...HOOK_BASE, hook_event_name: "Stop", stop_hook_active: true, last_assistant_message: "" },
    }, ctx);
    const result = await dispatch({
      cmd: "hooks.stop",
      args: { ...HOOK_BASE, hook_event_name: "Stop", stop_hook_active: true, last_assistant_message: "" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(true);
    expect(await getAgentStatus()).toBe("done");
  });

  it("should update status from error→done", async () => {
    await dispatch({ cmd: "db.agents.updateStatus", args: { id: AGENT_ID, status: "error" } }, ctx);
    expect(await getAgentStatus()).toBe("error");
    const result = await dispatch({
      cmd: "hooks.stop",
      args: { ...HOOK_BASE, hook_event_name: "Stop", stop_hook_active: true, last_assistant_message: "" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(await getAgentStatus()).toBe("done");
  });

  it("should update status from attention→done", async () => {
    await dispatch({ cmd: "db.agents.updateStatus", args: { id: AGENT_ID, status: "attention" } }, ctx);
    const result = await dispatch({
      cmd: "hooks.stop",
      args: { ...HOOK_BASE, hook_event_name: "Stop", stop_hook_active: true, last_assistant_message: "" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(await getAgentStatus()).toBe("done");
  });
});

// ── Coverage expansion: hooks.sessionEnd resilience ───────

describe("hooks.sessionEnd — coverage expansion", () => {
  it("should be idempotent for agent status on re-end", async () => {
    await dispatch({
      cmd: "hooks.sessionEnd",
      args: { ...HOOK_BASE, hook_event_name: "SessionEnd", reason: "exit" },
    }, ctx);
    expect(await getAgentStatus()).toBe("done");
    // End again
    const result = await dispatch({
      cmd: "hooks.sessionEnd",
      args: { ...HOOK_BASE, hook_event_name: "SessionEnd", reason: "exit" },
    }, ctx);
    expect(result.ok).toBe(true);
  });

  it("should handle nonexistent project cwd gracefully", async () => {
    const result = await dispatch({
      cmd: "hooks.sessionEnd",
      args: { ...HOOK_BASE, hook_event_name: "SessionEnd", cwd: "/nonexistent", reason: "exit" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).sessionEnded).toBe(false);
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(false);
  });
});

// ── Coverage expansion: hooks.postToolUseFailure ──────────

describe("hooks.postToolUseFailure — coverage expansion", () => {
  it("should be idempotent for agent already in error state", async () => {
    await dispatch({
      cmd: "hooks.postToolUseFailure",
      args: { ...HOOK_BASE, hook_event_name: "PostToolUseFailure", tool_name: "Bash", tool_input: {}, tool_use_id: "tu_1", error: "first" },
    }, ctx);
    expect(await getAgentStatus()).toBe("error");
    const result = await dispatch({
      cmd: "hooks.postToolUseFailure",
      args: { ...HOOK_BASE, hook_event_name: "PostToolUseFailure", tool_name: "Bash", tool_input: {}, tool_use_id: "tu_2", error: "second" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(await getAgentStatus()).toBe("error");
  });

  it("should handle null toolName gracefully", async () => {
    const result = await dispatch({
      cmd: "hooks.postToolUseFailure",
      args: { ...HOOK_BASE, hook_event_name: "PostToolUseFailure", tool_name: "unknown", tool_input: {}, tool_use_id: "tu_1", error: "crash" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).agentUpdated).toBe(true);
    expect((result.data as Record<string, unknown>).messageLogged).toBe(true);
  });
});

// ── Coverage expansion: hooks.permissionRequest ───────────

describe("hooks.permissionRequest — coverage expansion", () => {
  it("should be idempotent for agent already in attention", async () => {
    await dispatch({
      cmd: "hooks.permissionRequest",
      args: { ...HOOK_BASE, hook_event_name: "PermissionRequest", tool_name: "Bash", tool_input: {} },
    }, ctx);
    expect(await getAgentStatus()).toBe("attention");
    const result = await dispatch({
      cmd: "hooks.permissionRequest",
      args: { ...HOOK_BASE, hook_event_name: "PermissionRequest", tool_name: "Write", tool_input: {} },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(await getAgentStatus()).toBe("attention");
  });
});

// ── Coverage expansion: hooks.subagentStart ───────────────

describe("hooks.subagentStart — coverage expansion", () => {
  it("should use effort from cwd when resolved", async () => {
    const result = await dispatch({
      cmd: "hooks.subagentStart",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStart", agent_id: "sub-exp-1", agent_type: "builder" },
    }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.effortId).toBe(effortId);
    expect(data.sessionId).toBeTypeOf("number");
  });
});

// ── Coverage expansion: hooks.subagentStop ────────────────

describe("hooks.subagentStop — coverage expansion", () => {
  it("should be idempotent for already-ended sessions", async () => {
    // Create and end a sub-agent session
    const startResult = await dispatch({
      cmd: "hooks.subagentStart",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStart", agent_id: "sub-idem-1", agent_type: "builder" },
    }, ctx);
    if (!startResult.ok) throw new Error("subagentStart failed");

    await dispatch({
      cmd: "hooks.subagentStop",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStop", stop_hook_active: false, agent_id: "sub-idem-1", agent_type: "builder", agent_transcript_path: "/tmp/sub.jsonl", last_assistant_message: "" },
    }, ctx);
    // End again
    const result = await dispatch({
      cmd: "hooks.subagentStop",
      args: { ...HOOK_BASE, hook_event_name: "SubagentStop", stop_hook_active: false, agent_id: "sub-idem-1", agent_type: "builder", agent_transcript_path: "/tmp/sub.jsonl", last_assistant_message: "" },
    }, ctx);
    expect(result.ok).toBe(true);
  });
});
