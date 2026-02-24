import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import { createTestContext } from "engine-shared/__tests__/test-context";
import "../../../../db/src/rpc/registry.js";
import "../../../../agent/src/rpc/registry.js";
import "../../../../commands/src/rpc/commands-effort-start.js";
import "../hooks-pre-tool-use.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

let db: DbConnection;
let ctx: RpcContext;
let effortId: number;
let sessionId: number;

/** Common base args for PreToolUse dispatch (snake_case — transformKeys converts to camelCase) */
const BASE = {
  session_id: "test-session",
  transcript_path: "/tmp/transcript.jsonl",
  cwd: "/proj",
  permission_mode: "default",
  hook_event_name: "PreToolUse",
  tool_use_id: "tu_1",
};

/** Helper: create standard project + task + effort + session */
async function setupStandardSession(meta?: Record<string, unknown>) {
  db = await createTestDb();
  ctx = createTestContext(db);
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, ctx);
  const er = await dispatch({
    cmd: "db.effort.start",
    args: { taskId: "sessions/test", skill: "implement", metadata: meta },
  }, ctx);
  effortId = ((er as any).data.effort as any).id;
  const sr = await dispatch({
    cmd: "db.session.start",
    args: { taskId: "sessions/test", effortId, pid: 123 },
  }, ctx);
  sessionId = ((sr as any).data.session as any).id;
}

afterEach(async () => { await db.close(); });

// ── 1. Active session → increments heartbeat counter ──────────────
describe("hooks.preToolUse — heartbeat increment", () => {
  beforeEach(() => setupStandardSession());

  it("should increment heartbeat counter and return count", async () => {
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
    expect(r.data.heartbeatCount).toBe(1);

    // Second call
    const r2 = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Edit", tool_input: {} },
    }, ctx);
    expect(r2.ok).toBe(true);
    if (!r2.ok) return;
    expect(r2.data.heartbeatCount).toBe(2);
  });
});

// ── 2. Counter at blockAfter threshold → allow=false ──────────────
describe("hooks.preToolUse — heartbeat block", () => {
  beforeEach(() => setupStandardSession());

  it("should return allow=false when counter reaches blockAfter threshold", async () => {
    // Pump counter to 9 (default blockAfter = 10)
    for (let i = 0; i < 9; i++) {
      await dispatch({ cmd: "hooks.preToolUse", args: { ...BASE, tool_name: "Read", tool_input: {} } }, ctx);
    }

    // 10th call should block
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(false);
    expect(r.data.reason).toBe("heartbeat-block");
    expect(r.data.heartbeatCount).toBe(10);
  });

  it("should respect custom blockAfter from effort metadata", async () => {
    await db.close();
    await setupStandardSession({ blockAfter: 5 });

    // Pump to 4
    for (let i = 0; i < 4; i++) {
      await dispatch({ cmd: "hooks.preToolUse", args: { ...BASE, tool_name: "Read", tool_input: {} } }, ctx);
    }

    // 5th call should block
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(false);
    expect(r.data.reason).toBe("heartbeat-block");
    expect(r.data.heartbeatCount).toBe(5);
  });
});

// ── 3. engine log command → resets counter ────────────────────────
describe("hooks.preToolUse — engine log bypass", () => {
  beforeEach(() => setupStandardSession());

  it("should reset heartbeat counter to 0 for 'engine log' commands", async () => {
    // Build up counter
    await dispatch({ cmd: "hooks.preToolUse", args: { ...BASE, tool_name: "Read", tool_input: {} } }, ctx);
    await dispatch({ cmd: "hooks.preToolUse", args: { ...BASE, tool_name: "Read", tool_input: {} } }, ctx);

    // engine log resets
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Bash", tool_input: { command: "engine log sessions/test/LOG.md <<'EOF'\n## entry\nEOF" } },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
    expect(r.data.heartbeatCount).toBe(0);

    // Verify DB was actually reset
    const row = await db.get<{ heartbeatCounter: number }>("SELECT heartbeat_counter FROM sessions WHERE id = ?", [sessionId]);
    expect(row!.heartbeatCounter).toBe(0);
  });
});

// ── 4. engine session command → bypass all guards ─────────────────
describe("hooks.preToolUse — engine session bypass", () => {
  beforeEach(() => setupStandardSession());

  it("should bypass all guards for 'engine session' commands", async () => {
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Bash", tool_input: { command: "engine session phase sessions/test '1: Setup'" } },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
  });

  it("should bypass all guards for any 'engine' command", async () => {
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Bash", tool_input: { command: "engine discover-directives sessions/test" } },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
  });
});

// ── 5. contextUsage no longer in schema — always null/false ───────
describe("hooks.preToolUse — overflow warning (contextUsage removed from schema)", () => {
  beforeEach(() => setupStandardSession());

  it("should return overflowWarning=false and contextUsage=null (contextUsage not in schema)", async () => {
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
    expect(r.data.overflowWarning).toBe(false);
    expect(r.data.contextUsage).toBeNull();
  });

  it("should return overflowWarning=false regardless of input", async () => {
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.overflowWarning).toBe(false);
  });

  it("should not update session context_usage (no longer tracked)", async () => {
    await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    const row = await db.get<{ contextUsage: number | null }>("SELECT context_usage FROM sessions WHERE id = ?", [sessionId]);
    expect(row!.contextUsage).toBeNull();
  });
});

// ── 6. loading=true → skip heartbeat enforcement ──────────────────
describe("hooks.preToolUse — loading bypass", () => {
  beforeEach(() => setupStandardSession({ loading: true }));

  it("should skip heartbeat enforcement when loading=true", async () => {
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);

    // Counter should NOT be incremented
    const row = await db.get<{ heartbeatCounter: number }>("SELECT heartbeat_counter FROM sessions WHERE id = ?", [sessionId]);
    expect(row!.heartbeatCounter).toBe(0);
  });
});

// ── 7. dehydrating=true → allow all tools ─────────────────────────
describe("hooks.preToolUse — dehydrating bypass", () => {
  beforeEach(() => setupStandardSession({ dehydrating: true }));

  it("should allow all tools when dehydrating=true", async () => {
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
  });
});

// ── 8. guards rules that match → returns firedRules ───────────────
describe("hooks.preToolUse — guards evaluation", () => {
  beforeEach(() =>
    setupStandardSession({
      guards: [
        {
          ruleId: "warn-large-context",
          condition: { field: "context_usage", op: "gte", value: 0.80 },
          payload: { message: "Context is getting large" },
        },
        {
          ruleId: "block-after-5",
          condition: { field: "heartbeat_counter", op: "gte", value: 5 },
          payload: { message: "Log more often" },
        },
      ],
    })
  );

  it("should return matching guard rules in firedRules (heartbeat-based only, context_usage is null)", async () => {
    // context_usage guard won't fire (context_usage is always null in state)
    // heartbeat_counter guard fires after increment (counter becomes 1, which >= 1 is false...
    // wait: the guard is gte 5 for heartbeat. After 1 call, counter=1, which is < 5. So no guards fire.
    // Let's pump heartbeat to 5 so block-after-5 fires.
    for (let i = 0; i < 4; i++) {
      await dispatch({ cmd: "hooks.preToolUse", args: { ...BASE, tool_name: "Read", tool_input: {} } }, ctx);
    }
    // 5th call: counter=5, block-after-5 guard fires
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.firedRules).toHaveLength(1);
    expect(r.data.firedRules[0].ruleId).toBe("block-after-5");
    expect(r.data.firedRules[0].payload).toEqual({ message: "Log more often" });
  });
});

// ── 9. No guards match → empty firedRules ─────────────────────────
describe("hooks.preToolUse — no guards match", () => {
  beforeEach(() =>
    setupStandardSession({
      guards: [
        {
          ruleId: "block-high-context",
          condition: { field: "context_usage", op: "gte", value: 0.99 },
          payload: { message: "Context critical" },
        },
      ],
    })
  );

  it("should return empty firedRules when no guards match", async () => {
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {}, context_usage: 0.50 },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.firedRules).toEqual([]);
  });
});

// ── Edge cases ────────────────────────────────────────────────────
describe("hooks.preToolUse — fail-open", () => {
  beforeEach(async () => {
    db = await createTestDb();
    ctx = createTestContext(db);
    await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, ctx);
  });

  it("should return allow=true when effort not found", async () => {
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, cwd: "/nonexistent", tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
  });

  it("should return allow=true when session not found", async () => {
    // Create effort but no session — resolveEngineIds will find effort but no session
    const er = await dispatch({
      cmd: "db.effort.start",
      args: { taskId: "sessions/test", skill: "implement" },
    }, ctx);
    // Use cwd that resolves to project with effort but no session
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
  });

  // ── Hardening: guard rule references nonexistent field ─────────
  it("should skip guard rules that reference nonexistent state fields", async () => {
    await db.close();
    await setupStandardSession({
      guards: [
        {
          ruleId: "bad-field-rule",
          condition: { field: "nonexistent_field", op: "gte", value: 1 },
          payload: { message: "Should never fire" },
        },
      ],
    });

    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {}, context_usage: 0.5 },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
    expect(r.data.firedRules).toEqual([]);
  });

  // ── Hardening: blockAfter = 0 (every call blocks) ────────────
  it("should block on first non-whitelisted call when blockAfter is 0", async () => {
    await db.close();
    await setupStandardSession({ blockAfter: 0 });

    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    // Counter becomes 1 which is >= 0, so should block
    expect(r.data.allow).toBe(false);
    expect(r.data.reason).toBe("heartbeat-block");
  });

  // ── Hardening: empty/null metadata ────────────────────────────
  it("should use defaults when effort metadata is null", async () => {
    await db.close();
    db = await createTestDb();
    ctx = createTestContext(db);
    await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, ctx);
    // Create effort with explicitly null metadata
    const er = await dispatch({
      cmd: "db.effort.start",
      args: { taskId: "sessions/test", skill: "implement" },
    }, ctx);
    effortId = ((er as any).data.effort as any).id;
    // Clear metadata to null
    await db.run("UPDATE efforts SET metadata = NULL WHERE id = ?", [effortId]);
    const sr = await dispatch({
      cmd: "db.session.start",
      args: { taskId: "sessions/test", effortId, pid: 123 },
    }, ctx);
    sessionId = ((sr as any).data.session as any).id;

    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
    expect(r.data.heartbeatCount).toBe(1);
    expect(r.data.firedRules).toEqual([]);
  });

  it("should return allow=true when effort lifecycle is finished", async () => {
    await db.close();
    await setupStandardSession();
    // Manually set effort to finished
    await db.run("UPDATE efforts SET lifecycle = 'finished' WHERE id = ?", [effortId]);
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
  });
});

// ── 10. Phase 0→1 boundary: create effort from taskName proof ────────
describe("hooks.preToolUse — phase 0→1 effort creation", () => {
  beforeEach(async () => {
    // Setup project only — NO effort, NO session (simulates phase 0 where no effort exists yet)
    db = await createTestDb();
    ctx = createTestContext(db);
    await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
    // Cache a skill in DB (FleetStart would do this normally)
    await dispatch({
      cmd: "db.skills.upsert",
      args: {
        projectId: 1,
        name: "implement",
        phases: [
          { label: "0", name: "Setup" },
          { label: "1", name: "Strategy" },
          { label: "2", name: "Execution" },
        ],
      },
    }, ctx);
  });

  it("should create effort when engine session phase has taskName proof and no active effort", async () => {
    const cmd = `engine session phase sessions/TEST_TASK "1: Strategy" <<'EOF'\n{"taskName": "TEST_TASK", "description": "Test task", "keywords": "test,effort"}\nEOF`;
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: {
        ...BASE,
        tool_name: "Bash",
        tool_input: { command: cmd },
      },
    }, ctx);

    expect(r.ok).toBe(true);
    if (!r.ok) return;
    // Should allow the phase command to proceed
    expect(r.data.allow).toBe(true);

    // Verify effort was created
    const efforts = await db.all("SELECT * FROM efforts WHERE task_id = '/proj/.tasks/test_task'");
    expect(efforts.length).toBe(1);
    expect((efforts[0] as any).skill).toBe("implement");
    expect((efforts[0] as any).lifecycle).toBe("active");
  });

  it("should NOT create effort when engine session phase has no taskName proof", async () => {
    const cmd = `engine session phase sessions/TEST_TASK "1: Strategy"`;
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: {
        ...BASE,
        tool_name: "Bash",
        tool_input: { command: cmd },
      },
    }, ctx);

    expect(r.ok).toBe(true);
    if (!r.ok) return;
    // Should still allow (fail-open)
    expect(r.data.allow).toBe(true);

    // No effort created
    const efforts = await db.all("SELECT * FROM efforts");
    expect(efforts.length).toBe(0);
  });

  it("should skip effort creation when active effort already exists", async () => {
    // Create a task and effort first
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "/proj/.tasks/test_task", projectId: 1 } }, ctx);
    const er = await dispatch({
      cmd: "db.effort.start",
      args: { taskId: "/proj/.tasks/test_task", skill: "implement" },
    }, ctx);
    const existingEffortId = ((er as any).data.effort as any).id;
    await dispatch({
      cmd: "db.session.start",
      args: { taskId: "/proj/.tasks/test_task", effortId: existingEffortId, pid: 123 },
    }, ctx);

    const cmd = `engine session phase sessions/TEST_TASK "1: Strategy" <<'EOF'\n{"taskName": "TEST_TASK"}\nEOF`;
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: {
        ...BASE,
        tool_name: "Bash",
        tool_input: { command: cmd },
      },
    }, ctx);

    expect(r.ok).toBe(true);
    if (!r.ok) return;
    // Normal allow — existing effort handles it
    expect(r.data.allow).toBe(true);

    // Still only 1 effort (not 2)
    const efforts = await db.all("SELECT * FROM efforts");
    expect(efforts.length).toBe(1);
  });
});

// ── 11. Utility skill — no effort lifecycle ──────────────────────────
describe("hooks.preToolUse — utility skill detection", () => {
  beforeEach(async () => {
    db = await createTestDb();
    ctx = createTestContext(db);
    await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
  });

  it("should not create effort for phase transitions without taskName proof (utility skill)", async () => {
    // Utility skill phase transition — proof has no taskName
    const cmd = `engine session phase sessions/QUICK_TASK "1: Work" <<'EOF'\n{"intent_reported": "true"}\nEOF`;
    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: {
        ...BASE,
        tool_name: "Bash",
        tool_input: { command: cmd },
      },
    }, ctx);

    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);

    // No efforts created
    const efforts = await db.all("SELECT * FROM efforts");
    expect(efforts.length).toBe(0);
  });
});

// ── Coverage expansion: multiple guards + boundary + combined bypasses ─

describe("hooks.preToolUse — coverage expansion", () => {
  it("should return all matching guard rules when multiple fire (heartbeat-based)", async () => {
    await setupStandardSession({
      guards: [
        {
          ruleId: "warn-heartbeat-low",
          condition: { field: "heartbeat_counter", op: "gte", value: 1 },
          payload: { message: "Heartbeat started" },
        },
        {
          ruleId: "warn-heartbeat-high",
          condition: { field: "heartbeat_counter", op: "gte", value: 1 },
          payload: { message: "Heartbeat high" },
        },
        {
          ruleId: "no-match-rule",
          condition: { field: "heartbeat_counter", op: "gte", value: 99 },
          payload: { message: "Should not fire" },
        },
      ],
    });

    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.firedRules).toHaveLength(2);
    expect(r.data.firedRules.map((f: any) => f.ruleId)).toEqual(["warn-heartbeat-low", "warn-heartbeat-high"]);
  });

  it("should always return overflowWarning=false and contextUsage=null", async () => {
    await setupStandardSession();

    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.overflowWarning).toBe(false);
    expect(r.data.contextUsage).toBeNull();
  });

  it("should allow when both loading=true AND dehydrating=true", async () => {
    await setupStandardSession({ loading: true, dehydrating: true });

    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.allow).toBe(true);
    const row = await db.get<{ heartbeatCounter: number }>("SELECT heartbeat_counter FROM sessions WHERE id = ?", [sessionId]);
    expect(row!.heartbeatCounter).toBe(0);
  });

  it("should not fire guard rule with unknown operator", async () => {
    await setupStandardSession({
      guards: [
        {
          ruleId: "unknown-op",
          condition: { field: "heartbeat_counter", op: "between", value: 1 },
          payload: { message: "Should never fire" },
        },
      ],
    });

    const r = await dispatch({
      cmd: "hooks.preToolUse",
      args: { ...BASE, tool_name: "Read", tool_input: {} },
    }, ctx);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.firedRules).toEqual([]);
  });
});
