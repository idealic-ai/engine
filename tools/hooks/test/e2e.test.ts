/**
 * E2E tests for the engine tools plugin (no active effort).
 *
 * Uses the universal debug JSON schema to probe what hooks inject
 * into Claude's context. All assertions are on structured data.
 *
 * Run: npm run test:e2e
 * Requires: ANTHROPIC_API_KEY and `claude` CLI on PATH.
 */
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import {
  runClaude,
  runClaudeJson,
  createTempSessionsDir,
  cleanupSessions,
  debugSchema,
  DEBUG_PROMPT,
  type DebugReport,
} from "./helpers.js";

// ── Suite lifecycle ──────────────────────────────────────────

beforeAll(() => {
  createTempSessionsDir();
});

afterAll(() => {
  cleanupSessions();
});

// ── Baseline: no active effort ───────────────────────────────

describe("e2e: baseline (no effort)", () => {
  it("plugin loads and returns structured debug report", async () => {
    const { data, raw } = await runClaudeJson<DebugReport>(
      DEBUG_PROMPT,
      debugSchema(),
    );

    expect(raw.exitCode).toBe(0);
    expect(data).not.toBeNull();
    console.log("Baseline debug report:", JSON.stringify(data, null, 2));

    // System reminders exist (Claude Code always injects some)
    expect(data!.systemReminderCount).toBeGreaterThan(0);

    // No session context without an active effort
    expect(data!.sessionContextLine).toBe("none");
    expect(data!.skillName).toBe("none");
    expect(data!.currentPhase).toBe("none");

    // No preloaded files without an active effort
    expect(data!.preloadedFiles).toEqual([]);

    // Plugin skill "effort" should be discoverable
    // (tools/skills/effort/SKILL.md + .claude-plugin/plugin.json)
    console.log("Plugin skills found:", data!.pluginSkillsDiscovered);
  });
});

// ── Tool use pipeline ────────────────────────────────────────

describe("e2e: tool use through hooks", () => {
  it("Bash tool works with PreToolUse/PostToolUse hooks", async () => {
    // Simple prompt — just run bash, no debug report (avoids timeout)
    const result = await runClaude(
      "Run 'echo PLUGIN_BASH_OK' in bash and reply with the output.",
    );

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("PLUGIN_BASH_OK");
  });

  it("multiple tool calls succeed (heartbeat fail-open)", async () => {
    const result = await runClaude(
      "Do these 3 things in order: (1) Run 'echo S1' in bash, (2) Run 'echo S2' in bash, (3) Reply 'ALL_DONE'.",
    );
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("ALL_DONE");
  });
});
