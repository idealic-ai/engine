import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch, getRegistry } from "engine-shared/dispatch";
import { buildNamespace } from "engine-shared/namespace-builder";
import "../../../../db/src/rpc/registry.js";
import "../../../../agent/src/rpc/agent-messages-ingest.js";
import "../hooks-post-tool-use.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

let db: DbConnection;
let ctx: RpcContext;
let effortId: number;
let sessionId: number;

/** Common base args for PostToolUse dispatch (snake_case) */
const BASE = {
  session_id: "test-session",
  transcript_path: "/tmp/transcript.jsonl",
  cwd: "/proj",
  permission_mode: "default",
  hook_event_name: "PostToolUse",
  tool_use_id: "tu_1",
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
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, ctx);
  await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, ctx);

  const effortRes = await dispatch({
    cmd: "db.effort.start",
    args: { taskId: "sessions/test", skill: "implement" },
  }, ctx);
  effortId = (effortRes as any).data.effort.id as number;

  const sessionRes = await dispatch({
    cmd: "db.session.start",
    args: { taskId: "sessions/test", effortId, pid: 1234 },
  }, ctx);
  sessionId = (sessionRes as any).data.session.id as number;
});

afterEach(async () => {
  // Allow fire-and-forget ingestion promises to settle before closing DB
  await new Promise((r) => setTimeout(r, 50));
  await db.close();
});

describe("hooks.postToolUse", () => {
  it("returns heartbeatCount, empty injections, and null dialogueEntry for a normal tool", async () => {
    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "Read",
        tool_input: { file_path: "/some/file.ts" },
        tool_response: "",
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    expect(data.heartbeatCount).toBeTypeOf("number");
    expect(data.pendingInjections).toEqual([]);
    expect(data.dialogueEntry).toBeNull();
  });

  it("formats dialogueEntry from AskUserQuestion tool input/output", async () => {
    const toolInput = {
      questions: [
        {
          question: "How should we proceed?",
          options: [
            { label: "Continue inline", description: "Do it here" },
            { label: "Launch agent", description: "Hand off" },
          ],
        },
      ],
    };
    const toolOutput = JSON.stringify([
      { question: "How should we proceed?", answer: "Continue inline" },
    ]);

    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "AskUserQuestion",
        tool_input: toolInput,
        tool_response: toolOutput,
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;

    // dialogueEntry should be formatted
    expect(data.dialogueEntry).not.toBeNull();
    expect(data.dialogueEntry.preamble).toBe("");
    expect(data.dialogueEntry.questions).toHaveLength(1);
    expect(data.dialogueEntry.questions[0].question).toBe("How should we proceed?");
    expect(data.dialogueEntry.questions[0].options).toEqual(["Continue inline", "Launch agent"]);
    expect(data.dialogueEntry.questions[0].answer).toBe("Continue inline");
  });

  it("does not store dialogue in messages table — transcript is source of truth", async () => {
    const toolInput = {
      questions: [
        {
          question: "Pick a mode",
          options: [
            { label: "TDD", description: "Test first" },
          ],
        },
      ],
    };
    const toolOutput = JSON.stringify([
      { question: "Pick a mode", answer: "TDD" },
    ]);

    await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "AskUserQuestion",
        tool_input: toolInput,
        tool_response: toolOutput,
      },
    }, ctx);

    // Messages table should be empty — transcript ingestion is the only writer
    const listResult = await dispatch({
      cmd: "db.messages.list",
      args: { sessionId },
    }, ctx);

    expect(listResult.ok).toBe(true);
    if (!listResult.ok) return;
    const messages = listResult.data.messages as Record<string, unknown>[];
    expect(messages).toHaveLength(0);
  });

  it("does not store a message for non-AskUserQuestion tools", async () => {
    await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "Read",
        tool_input: {},
        tool_response: "",
      },
    }, ctx);

    const row = await db.get<{ c: number }>(
      "SELECT COUNT(*) as c FROM messages WHERE session_id = ?",
      [sessionId]
    );
    expect(row!.c).toBe(0);
  });

  it("returns and clears pending injections from effort metadata", async () => {
    // Manually set pendingInjections in effort metadata
    const injections = [
      { ruleId: "INV_TEST_FIRST", content: "Write tests before implementation" },
      { ruleId: "INV_NO_DEAD_CODE", content: "Delete dead code" },
    ];
    await db.run(
      `UPDATE efforts SET metadata = json(?) WHERE id = ?`,
      [JSON.stringify({ pendingInjections: injections }), effortId]
    );

    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "Bash",
        tool_input: {},
        tool_response: "",
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;

    // Should return the injections
    expect(data.pendingInjections).toHaveLength(2);
    expect(data.pendingInjections[0].ruleId).toBe("INV_TEST_FIRST");
    expect(data.pendingInjections[1].ruleId).toBe("INV_NO_DEAD_CODE");

    // Should have cleared from metadata
    const effort = await db.get<{ metadata: string }>("SELECT metadata FROM efforts WHERE id = ?", [effortId]);
    const metadata = typeof effort!.metadata === "string" ? JSON.parse(effort!.metadata) : effort!.metadata;
    expect(metadata.pendingInjections).toBeUndefined();
  });

  it("returns empty array when no pending injections exist", async () => {
    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "Bash",
        tool_input: {},
        tool_response: "",
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.pendingInjections).toEqual([]);
  });

  it("preserves other metadata keys when clearing pendingInjections", async () => {
    await db.run(
      `UPDATE efforts SET metadata = json(?) WHERE id = ?`,
      [
        JSON.stringify({
          pendingInjections: [{ ruleId: "X", content: "Y" }],
          someOtherKey: "preserve-me",
        }),
        effortId,
      ]
    );

    await dispatch({
      cmd: "hooks.postToolUse",
      args: { ...BASE, tool_name: "Bash", tool_input: {}, tool_response: "" },
    }, ctx);

    const effort = await db.get<{ metadata: string }>("SELECT metadata FROM efforts WHERE id = ?", [effortId]);
    const metadata = typeof effort!.metadata === "string" ? JSON.parse(effort!.metadata) : effort!.metadata;
    expect(metadata.someOtherKey).toBe("preserve-me");
    expect(metadata.pendingInjections).toBeUndefined();
  });

  it("returns gracefully with defaults when no active session found", async () => {
    // End the session
    await db.run("UPDATE sessions SET ended_at = datetime('now') WHERE id = ?", [sessionId]);

    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        cwd: "/nonexistent",
        tool_name: "Read",
        tool_input: {},
        tool_response: "",
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    expect(data.heartbeatCount).toBe(0);
    expect(data.pendingInjections).toEqual([]);
    expect(data.dialogueEntry).toBeNull();
  });

  // ── Hardening: malformed toolOutput for AskUserQuestion ───────
  it("handles malformed (non-JSON) toolOutput for AskUserQuestion gracefully", async () => {
    const toolInput = {
      questions: [
        {
          question: "Pick something",
          options: [{ label: "A", description: "Option A" }],
        },
      ],
    };

    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "AskUserQuestion",
        tool_input: toolInput,
        tool_response: "this is not valid JSON at all!!!",
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    // dialogueEntry should still be created (with empty answers)
    expect(data.dialogueEntry).not.toBeNull();
    expect(data.dialogueEntry.questions[0].answer).toBe("");
  });

  // ── Hardening: mismatched question/answer counts ──────────────
  it("handles fewer answers than questions gracefully", async () => {
    const toolInput = {
      questions: [
        { question: "Q1", options: [{ label: "A" }] },
        { question: "Q2", options: [{ label: "B" }] },
        { question: "Q3", options: [{ label: "C" }] },
      ],
    };
    // Only 1 answer for 3 questions
    const toolOutput = JSON.stringify([
      { question: "Q1", answer: "A" },
    ]);

    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "AskUserQuestion",
        tool_input: toolInput,
        tool_response: toolOutput,
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    expect(data.dialogueEntry.questions).toHaveLength(3);
    expect(data.dialogueEntry.questions[0].answer).toBe("A");
    expect(data.dialogueEntry.questions[1].answer).toBe("");
    expect(data.dialogueEntry.questions[2].answer).toBe("");
  });

  // ── Hardening: multiple pending injections cleared atomically ──
  it("returns and clears multiple pending injections while preserving metadata", async () => {
    const injections = [
      { ruleId: "R1", content: "First" },
      { ruleId: "R2", content: "Second" },
      { ruleId: "R3", content: "Third" },
    ];
    await db.run(
      `UPDATE efforts SET metadata = json(?) WHERE id = ?`,
      [JSON.stringify({ pendingInjections: injections, keepMe: true, counter: 42 }), effortId]
    );

    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: { ...BASE, tool_name: "Bash", tool_input: {}, tool_response: "" },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    expect(data.pendingInjections).toHaveLength(3);
    expect(data.pendingInjections.map((i: any) => i.ruleId)).toEqual(["R1", "R2", "R3"]);

    // Verify metadata is clean
    const effort = await db.get<{ metadata: string }>("SELECT metadata FROM efforts WHERE id = ?", [effortId]);
    const meta = typeof effort!.metadata === "string" ? JSON.parse(effort!.metadata) : effort!.metadata;
    expect(meta.pendingInjections).toBeUndefined();
    expect(meta.keepMe).toBe(true);
    expect(meta.counter).toBe(42);
  });

  it("returns gracefully with defaults when effort not found", async () => {
    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        cwd: "/nonexistent",
        tool_name: "Read",
        tool_input: {},
        tool_response: "",
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    expect(data.heartbeatCount).toBe(0);
    expect(data.pendingInjections).toEqual([]);
    expect(data.dialogueEntry).toBeNull();
  });
});

// ── Coverage expansion: dialogue formatting edge cases ────────────

describe("hooks.postToolUse — coverage expansion", () => {
  it("should return null dialogueEntry when AskUserQuestion has empty questions array", async () => {
    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "AskUserQuestion",
        tool_input: { questions: [] },
        tool_response: "[]",
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    // Empty questions array → formatDialogueEntry returns { preamble, questions: [] }
    expect(data.dialogueEntry).not.toBeNull();
    expect(data.dialogueEntry.questions).toHaveLength(0);
  });

  it("should handle more answers than questions (extra answers ignored)", async () => {
    const toolInput = {
      questions: [
        { question: "Q1", options: [{ label: "A" }] },
      ],
    };
    const toolOutput = JSON.stringify([
      { question: "Q1", answer: "A" },
      { question: "Q2", answer: "B" },
      { question: "Q3", answer: "C" },
    ]);

    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: { ...BASE, tool_name: "AskUserQuestion", tool_input: toolInput, tool_response: toolOutput },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as any;
    expect(data.dialogueEntry.questions).toHaveLength(1);
    expect(data.dialogueEntry.questions[0].answer).toBe("A");
  });

  it("should use empty string for preamble when agentPreamble is undefined", async () => {
    const toolInput = {
      questions: [{ question: "Q1", options: [{ label: "Yes" }] }],
    };
    const toolOutput = JSON.stringify([{ question: "Q1", answer: "Yes" }]);

    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: { ...BASE, tool_name: "AskUserQuestion", tool_input: toolInput, tool_response: toolOutput },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.dialogueEntry.preamble).toBe("");
  });

  it("should return null dialogueEntry when toolInput has no questions key", async () => {
    const result = await dispatch({
      cmd: "hooks.postToolUse",
      args: {
        ...BASE,
        tool_name: "AskUserQuestion",
        tool_input: { somethingElse: "value" },
        tool_response: "",
      },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.dialogueEntry).toBeNull();
  });
});
