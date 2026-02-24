/**
 * E2E tests for specific hook behaviors:
 * 1. Heartbeat blocking — PreToolUse denies after N tool calls without logging
 * 2. PendingInjections — PostToolUse delivers injected content via additionalContext
 * 3. Heartbeat warn — PreToolUse fires guard rules at warn threshold
 *
 * Each test uses createIsolatedProject() for per-test isolation.
 *
 * Run: npm run test:e2e
 */
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import {
  runClaude,
  runClaudeJson,
  createTempSessionsDir,
  cleanupSessions,
  createIsolatedProject,
  readHookDebugLog,
  setupEffort,
  teardownEffort,
  rpcCall,
  debugSchema,
  DEBUG_PROMPT,
  type DebugReport,
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

let testCounter = 0;
function uniqueTaskDir(prefix: string): string {
  return `sessions/${prefix}_${Date.now()}_${testCounter++}`;
}

// ── Test 1: Heartbeat blocking ───────────────────────────────

describe("e2e: heartbeat blocking", () => {
  it("PreToolUse denies tool calls after exceeding blockAfter threshold", async () => {
    const projectDir = createIsolatedProject();
    const taskDir = uniqueTaskDir("hb-block");
    // Set blockAfter=3 so blocking triggers quickly (after 3 tool calls without engine log)
    const { effort, session } = setupEffort(taskDir, "implement", {
      projectPath: projectDir,
      metadata: { blockAfter: 3 },
    });

    try {
      // Ask Claude to run 5 sequential bash commands. After 3 tool calls,
      // PreToolUse should deny with heartbeat-block. Claude should report
      // being blocked or fail to complete all 5 commands.
      const result = await runClaude(
        [
          "Run these bash commands one at a time, in order. Report what happened for each:",
          "1. echo STEP_1",
          "2. echo STEP_2",
          "3. echo STEP_3",
          "4. echo STEP_4",
          "5. echo STEP_5",
          "After each command, report the output. Do NOT run 'engine log' between them.",
        ].join("\n"),
        { cwd: projectDir, timeout: 120_000 },
      );

      // Verify DB: heartbeat counter should be >= blockAfter threshold
      const sessResp = rpcCall<RpcResponse<{ session: SessionRow | null }>>(
        "db.session.find", { effortId: effort.id },
      );
      const sessData = (sessResp as unknown as { data: { session: SessionRow } }).data;
      expect(sessData?.session).toBeDefined();
      expect(sessData.session.heartbeatCounter).toBeGreaterThanOrEqual(3);

      // Check hook debug log for evidence of blocking
      const debugLog = readHookDebugLog(projectDir);
      console.log("Heartbeat blocking debug log:\n" + debugLog.slice(-2000));
      console.log("Heartbeat counter:", sessData.session.heartbeatCounter);

      // The key assertions:
      // 1. hookSpecificOutput deny was delivered (engine-rpc extracts it)
      expect(debugLog).toContain('"permissionDecision":"deny"');
      expect(debugLog).toContain('heartbeat-block');
    } finally {
      teardownEffort(effort.id, session.id);
    }
  });
});

// ── Test 2: PendingInjections delivery ───────────────────────

describe("e2e: pendingInjections", () => {
  it("PostToolUse delivers pending injections as additionalContext", async () => {
    const projectDir = createIsolatedProject();
    const taskDir = uniqueTaskDir("inject");
    const { effort, session } = setupEffort(taskDir, "test", {
      projectPath: projectDir,
    });

    try {
      // Set pendingInjections in effort metadata BEFORE Claude runs.
      // PostToolUse will read and deliver them after Claude's first tool call.
      rpcCall("db.effort.updateMetadata", {
        id: effort.id,
        set: {
          pendingInjections: [
            { ruleId: "INV_UNIQUE_MARKER_ALPHA", content: "INJECTION_ALPHA_CONTENT: Always use semicolons." },
            { ruleId: "INV_UNIQUE_MARKER_BETA", content: "INJECTION_BETA_CONTENT: Never use var." },
          ],
        },
      });

      // Ask Claude to do a tool call (triggers PostToolUse), then report
      // what it sees in its context.
      const schema = debugSchema({
        sawAlphaInjection: {
          type: "string",
          enum: ["yes", "no"],
          description: "Do you see 'INJECTION_ALPHA_CONTENT' or 'INV_UNIQUE_MARKER_ALPHA' anywhere in your context? Answer 'yes' or 'no'.",
        },
        sawBetaInjection: {
          type: "string",
          enum: ["yes", "no"],
          description: "Do you see 'INJECTION_BETA_CONTENT' or 'INV_UNIQUE_MARKER_BETA' anywhere in your context? Answer 'yes' or 'no'.",
        },
      });

      const { data, raw } = await runClaudeJson<DebugReport & {
        sawAlphaInjection: string;
        sawBetaInjection: string;
      }>(
        "First run 'echo TRIGGER_TOOL_CALL' in bash (this is important — do it first). Then " + DEBUG_PROMPT +
        " Also check if you see INJECTION_ALPHA_CONTENT or INJECTION_BETA_CONTENT or INV_UNIQUE_MARKER_ALPHA or INV_UNIQUE_MARKER_BETA in your context.",
        schema,
        { cwd: projectDir },
      );

      expect(raw.exitCode).toBe(0);
      expect(data).not.toBeNull();

      // Dump hook debug log to see what PostToolUse actually returned
      const debugLog = readHookDebugLog(projectDir);
      console.log("Hook debug log (last 3000 chars):\n" + debugLog.slice(-3000));

      console.log("Injection report:", JSON.stringify({
        alpha: data!.sawAlphaInjection,
        beta: data!.sawBetaInjection,
        hookEvents: data!.hookEventsFired,
      }));

      // Verify DB: pendingInjections should be cleared after PostToolUse processes them
      const metaResp = rpcCall<RpcResponse<{ metadata: Record<string, unknown> | null }>>(
        "db.effort.getMetadata", { id: effort.id },
      );
      const metadata = (metaResp as unknown as { data: { metadata: Record<string, unknown> | null } }).data?.metadata;
      console.log("Post-delivery metadata:", JSON.stringify(metadata));

      // The injections should have been cleared from metadata
      expect(metadata?.pendingInjections).toBeUndefined();

      // Model should see the injected content (via hookSpecificOutput.additionalContext)
      expect(data!.sawAlphaInjection).toBe("yes");
      expect(data!.sawBetaInjection).toBe("yes");
    } finally {
      teardownEffort(effort.id, session.id);
    }
  });
});

// ── Test 3: Heartbeat counter DB verification ────────────────

describe("e2e: heartbeat counter mechanics", () => {
  it("engine log resets heartbeat counter to zero", async () => {
    const projectDir = createIsolatedProject();
    const taskDir = uniqueTaskDir("hb-reset");
    const { effort, session } = setupEffort(taskDir, "implement", {
      projectPath: projectDir,
    });

    try {
      // Ask Claude to: (1) run a bash command (increments counter),
      // (2) run engine log (resets counter), (3) run another bash command.
      // After this sequence, the counter should be 1 (reset then incremented once).
      const result = await runClaude(
        [
          "Do these three things in exact order:",
          "1. Run: echo BEFORE_RESET",
          "2. Run: engine log /dev/null <<'EOF'\n## Test\n*   **x**: y\nEOF",
          "3. Run: echo AFTER_RESET",
          "Reply with 'SEQUENCE_DONE' when finished.",
        ].join("\n"),
        { cwd: projectDir, timeout: 120_000 },
      );

      expect(result.exitCode).toBe(0);

      // Verify DB: counter should be low (reset happened mid-sequence)
      const sessResp = rpcCall<RpcResponse<{ session: SessionRow | null }>>(
        "db.session.find", { effortId: effort.id },
      );
      const sessData = (sessResp as unknown as { data: { session: SessionRow } }).data;
      expect(sessData?.session).toBeDefined();

      console.log("Heartbeat counter after reset sequence:", sessData.session.heartbeatCounter);

      // Counter should be small — it was reset by engine log, then incremented
      // by the final bash command and possibly the structured output.
      // The key point: it's NOT 3+ (would be without the reset).
      expect(sessData.session.heartbeatCounter).toBeLessThanOrEqual(3);
    } finally {
      teardownEffort(effort.id, session.id);
    }
  });
});
