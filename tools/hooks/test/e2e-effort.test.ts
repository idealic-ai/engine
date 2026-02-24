/**
 * E2E tests with active effort in daemon DB.
 *
 * Sets up real DB state (project, task, effort, session) via engine-rpc,
 * then invokes Claude with --plugin-dir. Uses the universal debug JSON
 * schema to verify what hooks inject. Verifies DB state for all mutations.
 *
 * Tests run concurrently — each uses a unique task dir to avoid DB conflicts.
 *
 * Run: npm run test:e2e
 * Requires: ANTHROPIC_API_KEY and `claude` CLI on PATH.
 */
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import {
  runClaudeJson,
  createTempSessionsDir,
  cleanupSessions,
  createIsolatedProject,
  readHookDebugLog,
  setupEffort,
  teardownEffort,
  listEfforts,
  rpcCall,
  debugSchema,
  DEBUG_PROMPT,
  type DebugReport,
  type EffortRow,
  type SessionRow,
  type RpcResponse,
} from "./helpers.js";

// ── Suite lifecycle ──────────────────────────────────────────

beforeAll(() => {
  createTempSessionsDir();
});

afterAll(() => {
  cleanupSessions();
});

/** Generate a unique task dir per test to avoid DB conflicts in concurrent runs */
let testCounter = 0;
function uniqueTaskDir(prefix: string): string {
  return `sessions/${prefix}_${Date.now()}_${testCounter++}`;
}

// ── Tests: active effort context (concurrent) ────────────────

describe.concurrent("e2e: active effort context", () => {
  it("SessionStart injects session context with active effort", async () => {
    // Each concurrent test gets its own project dir to avoid effort collisions
    const projectDir = createIsolatedProject();
    const taskDir = uniqueTaskDir("ctx");
    const { effort, session } = setupEffort(taskDir, "implement", { projectPath: projectDir });
    try {
      const schema = debugSchema({
        hasSessionContextLine: {
          type: "string",
          enum: ["yes", "no"],
          description: "Is there a '[Session Context]' line in your context? Answer 'yes' or 'no'.",
        },
        sessionSkill: {
          type: "string",
          enum: ["implement", "test", "fix", "brainstorm", "none"],
          description: "What skill name appears in the [Session Context] line? 'none' if no session context.",
        },
      });

      const { data, raw } = await runClaudeJson<DebugReport & { hasSessionContextLine: string; sessionSkill: string }>(
        DEBUG_PROMPT,
        schema,
        { cwd: projectDir },
      );

      expect(raw.exitCode).toBe(0);
      expect(data).not.toBeNull();

      // Ground truth: effort still active in DB
      const postEfforts = listEfforts(taskDir);
      expect(postEfforts.find(e => e.lifecycle === "active")).toBeDefined();

      // Model saw the session context
      expect(data!.hookEventsFired).toContain("SessionStart");
      expect(data!.hasSessionContextLine).toBe("yes");
      expect(data!.sessionSkill).toBe("implement");
    } finally {
      teardownEffort(effort.id, session.id);
    }
  });

  it("heartbeat counter increments on tool calls", async () => {
    const projectDir = createIsolatedProject();
    const taskDir = uniqueTaskDir("hb");
    const { effort, session } = setupEffort(taskDir, "test", { projectPath: projectDir });
    try {
      const schema = debugSchema({
        bashResult: {
          type: "string",
          description: "The output of running 'echo HEARTBEAT_CHECK' in bash",
        },
      });

      const { data, raw } = await runClaudeJson<DebugReport & { bashResult: string }>(
        "First run 'echo HEARTBEAT_CHECK' in bash. Then " + DEBUG_PROMPT + " Also report the bash output.",
        schema,
        { cwd: projectDir },
      );

      expect(raw.exitCode).toBe(0);
      expect(data).not.toBeNull();
      expect(data!.bashResult).toContain("HEARTBEAT_CHECK");

      // Verify heartbeat was incremented in DB
      const sessResp = rpcCall<RpcResponse<{ session: SessionRow | null }>>(
        "db.session.find", { effortId: effort.id },
      );
      const sessData = (sessResp as unknown as { data: { session: SessionRow } }).data;
      expect(sessData?.session).toBeDefined();
      expect(sessData.session.heartbeatCounter).toBeGreaterThanOrEqual(1);
    } finally {
      teardownEffort(effort.id, session.id);
    }
  });
});

// ── Tests: effort lifecycle (fast, no Claude invocation) ─────

describe("e2e: effort lifecycle", () => {
  it("effort finish sets lifecycle to finished", () => {
    const projectDir = createIsolatedProject();
    const taskDir = uniqueTaskDir("lc");
    const { effort, session } = setupEffort(taskDir, "brainstorm", { projectPath: projectDir });

    // Verify active
    let efforts = listEfforts(taskDir);
    expect(efforts.find(x => x.id === effort.id)?.lifecycle).toBe("active");

    // Finish
    teardownEffort(effort.id, session.id);

    // Verify finished
    efforts = listEfforts(taskDir);
    expect(efforts.find(x => x.id === effort.id)?.lifecycle).toBe("finished");
  });
});

// ── Tests: effort skill invocation from Claude ───────────────

describe("e2e: effort skill invocation", () => {
  it("PreToolUse intercepts Skill(effort start) and creates effort in DB", async () => {
    const projectDir = createIsolatedProject();
    const taskDir = uniqueTaskDir("invoke");

    // Ask Claude to invoke the effort skill. The PreToolUse hook intercepts
    // the Skill tool call and creates the effort via commands.effort.start RPC.
    // Claude may or may not see the additionalContext response, but the DB
    // mutation is the ground truth we verify.
    const { raw } = await runClaudeJson<DebugReport>(
      `Invoke the skill named "effort" with arguments: start ${taskDir} implement\n\nThen report what happened.`,
      debugSchema(),
      { cwd: projectDir },
    );

    expect(raw.exitCode).toBe(0);

    // Dump hook debug log to see what events fired
    console.log("Hook debug log:\n" + readHookDebugLog(projectDir));

    // Ground truth: check DB for the effort created by PreToolUse interceptor
    const efforts = listEfforts(taskDir);
    console.log("Efforts found for", taskDir, ":", efforts.length, efforts.map(e => `${e.skill}/${e.lifecycle}`));
    const created = efforts.find(e => e.skill === "implement");
    expect(created).toBeDefined();
    expect(created!.lifecycle).toBe("active");
    // Cleanup
    teardownEffort(created!.id, 0);
  });
});
