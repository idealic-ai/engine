/**
 * Integration tests for hook RPCs over the real daemon socket.
 *
 * Tests the full pipeline: Unix socket → NDJSON → handleQuery → dispatch → Zod → handler → response.
 * Verifies response contracts match what bash hooks parse (ok, data, error fields).
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as net from "node:net";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { startDaemon, stopDaemon } from "../daemon.js";

const TEST_DIR = path.join(os.tmpdir(), `edb-hooks-int-${process.pid}`);
const SOCKET_PATH = `/tmp/edb-hooks-int-${process.pid}.sock`;
const DB_PATH = path.join(TEST_DIR, "test.db");

/** Common hook fields Claude Code always sends (snake_case — transformed by pipeline) */
function hookArgs(event: string, extra: Record<string, unknown> = {}) {
  return {
    session_id: "test-session",
    transcript_path: "/tmp/transcript.jsonl",
    cwd: "/proj",
    permission_mode: "default",
    hook_event_name: event,
    ...extra,
  };
}

/**
 * Send an RPC command over the Unix socket (same NDJSON protocol as bash hooks).
 */
function sendRpc(cmd: string, args: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const client = net.createConnection(SOCKET_PATH, () => {
      client.write(JSON.stringify({ cmd, args }) + "\n");
    });

    let data = "";
    client.on("data", (chunk) => {
      data += chunk.toString();
      if (data.includes("\n")) {
        client.end();
        try {
          resolve(JSON.parse(data.trim()));
        } catch {
          reject(new Error(`Invalid JSON response: ${data}`));
        }
      }
    });

    client.on("error", reject);
    client.setTimeout(10000, () => {
      client.destroy();
      reject(new Error("RPC timed out"));
    });
  });
}

/**
 * Send raw bytes over the socket (for protocol-level tests).
 */
function sendRaw(payload: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const client = net.createConnection(SOCKET_PATH, () => {
      client.write(payload);
    });

    let data = "";
    client.on("data", (chunk) => {
      data += chunk.toString();
      if (data.includes("\n")) {
        client.end();
        resolve(data.trim());
      }
    });

    client.on("error", reject);
    client.setTimeout(5000, () => {
      client.destroy();
      reject(new Error("Raw send timed out"));
    });
  });
}

// ── Scaffolding ─────────────────────────────────────────────

let effortId: number;
let sessionId: number;

beforeEach(async () => {
  fs.mkdirSync(TEST_DIR, { recursive: true });
  await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });

  // Seed: project → task → skill → effort → session → agent
  await sendRpc("db.project.upsert", { path: "/proj" });
  await sendRpc("db.task.upsert", { dirPath: "sessions/test", projectId: 1 });
  await sendRpc("db.skills.upsert", { projectId: 1, name: "implement" });

  const effortRes = await sendRpc("db.effort.start", { taskId: "sessions/test", skill: "implement" });
  effortId = (effortRes.data as any).effort.id;

  const sessionRes = await sendRpc("db.session.start", { taskId: "sessions/test", effortId, pid: process.pid });
  sessionId = (sessionRes.data as any).session.id;

  await sendRpc("db.agents.register", { id: "test-agent", label: "Worker", effortId });
});

afterEach(async () => {
  await stopDaemon();
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
  fs.rmSync(SOCKET_PATH, { force: true });
});

// ── 1. Transport layer ──────────────────────────────────────

describe("transport: NDJSON protocol", () => {
  it("should return error for invalid JSON", async () => {
    const raw = await sendRaw("this is not json\n");
    const parsed = JSON.parse(raw);
    expect(parsed.ok).toBe(false);
    expect(parsed.error).toContain("Invalid JSON");
  });

  it("should return error for unknown RPC command", async () => {
    const result = await sendRpc("hooks.nonExistentCommand", {});
    expect(result.ok).toBe(false);
    expect(result.error).toBe("UNKNOWN_COMMAND");
  });

  it("should return validation error for missing required args", async () => {
    // hooks.preToolUse requires session_id, cwd, tool_name, etc.
    const result = await sendRpc("hooks.preToolUse", {});
    expect(result.ok).toBe(false);
    expect(result.error).toBe("VALIDATION_ERROR");
  });
});

// ── 2. hooks.sessionStart — full round-trip ─────────────────

describe("integration: hooks.sessionStart", () => {
  it("should return effort, session, and skill info over socket", async () => {
    const result = await sendRpc("hooks.sessionStart", hookArgs("SessionStart", { source: "startup" }));
    expect(result.ok).toBe(true);

    const data = result.data as Record<string, unknown>;
    expect(data.found).toBe(true);
    expect(data.effortId).toBe(effortId);
    expect(data.sessionId).toBeTypeOf("number");
    expect(data.skill).toBe("implement");
    expect(data.taskDir).toBe("sessions/test");
  });

  it("should return { found: false } for unknown project", async () => {
    const result = await sendRpc("hooks.sessionStart", hookArgs("SessionStart", { cwd: "/nonexistent", source: "startup" }));
    expect(result.ok).toBe(true);
    expect((result.data as any).found).toBe(false);
  });
});

// ── 3. hooks.preToolUse — heartbeat + guards ─────────────────

describe("integration: hooks.preToolUse", () => {
  it("should increment heartbeat and return allow=true", async () => {
    const result = await sendRpc("hooks.preToolUse", hookArgs("PreToolUse", {
      tool_name: "Read", tool_input: {}, tool_use_id: "tu_1",
    }));
    expect(result.ok).toBe(true);

    const data = result.data as Record<string, unknown>;
    expect(data.allow).toBe(true);
    expect(data.heartbeatCount).toBe(1);
    expect(data.overflowWarning).toBe(false);
    expect(data.firedRules).toEqual([]);
  });

  it("should reset heartbeat on engine log command", async () => {
    // Bump counter
    await sendRpc("hooks.preToolUse", hookArgs("PreToolUse", { tool_name: "Read", tool_input: {}, tool_use_id: "tu_1" }));
    await sendRpc("hooks.preToolUse", hookArgs("PreToolUse", { tool_name: "Read", tool_input: {}, tool_use_id: "tu_2" }));

    // engine log resets
    const result = await sendRpc("hooks.preToolUse", hookArgs("PreToolUse", {
      tool_name: "Bash",
      tool_input: { command: "engine log sessions/test/LOG.md <<'EOF'\n## entry\nEOF" },
      tool_use_id: "tu_3",
    }));
    expect(result.ok).toBe(true);
    expect((result.data as any).heartbeatCount).toBe(0);
  });
});

// ── 4. hooks.postToolUse — dialogue + injections ────────────

describe("integration: hooks.postToolUse", () => {
  it("should return defaults for non-AskUserQuestion tool", async () => {
    const result = await sendRpc("hooks.postToolUse", hookArgs("PostToolUse", {
      tool_name: "Read", tool_input: {}, tool_response: {}, tool_use_id: "tu_1",
    }));

    expect(result.ok).toBe(true);

    const data = result.data as Record<string, unknown>;
    expect(data.heartbeatCount).toBeTypeOf("number");
    expect(data.pendingInjections).toEqual([]);
    expect(data.dialogueEntry).toBeNull();
  });

  it("should format AskUserQuestion dialogue entry", async () => {
    const toolInput = {
      questions: [{ question: "Proceed?", options: [{ label: "Yes" }, { label: "No" }] }],
    };
    const toolResponse = JSON.stringify([{ question: "Proceed?", answer: "Yes" }]);

    const result = await sendRpc("hooks.postToolUse", hookArgs("PostToolUse", {
      tool_name: "AskUserQuestion", tool_input: toolInput, tool_response: toolResponse, tool_use_id: "tu_1",
    }));
    expect(result.ok).toBe(true);

    const entry = (result.data as any).dialogueEntry;
    expect(entry).not.toBeNull();
    expect(entry.preamble).toBe("");
    expect(entry.questions[0].answer).toBe("Yes");
    expect(entry.questions[0].options).toEqual(["Yes", "No"]);
  });
});

// ── 5. hooks.userPrompt — session context line ──────────────

describe("integration: hooks.userPrompt", () => {
  it("should return formatted session context", async () => {
    const result = await sendRpc("hooks.userPrompt", hookArgs("UserPromptSubmit", { prompt: "test" }));

    expect(result.ok).toBe(true);

    const data = result.data as Record<string, unknown>;
    expect(data.effortId).toBe(effortId);
    expect(data.sessionId).toBeTypeOf("number");
    expect(data.skill).toBe("implement");
    expect(data.heartbeat).toBe("0/10");
    expect(data.sessionContext).toContain("implement");
    expect(data.sessionContext).toContain("sessions/test");
    expect(data.sessionContext).toContain("0/10");
  });
});

// ── 6. hooks.stop + hooks.sessionEnd — lifecycle over socket ─

describe("integration: lifecycle hooks", () => {
  it("should stop agent via hooks.stop", async () => {
    const result = await sendRpc("hooks.stop", hookArgs("Stop", {
      stop_hook_active: false, last_assistant_message: "Done.",
    }));
    expect(result.ok).toBe(true);
    expect((result.data as any).agentUpdated).toBe(true);

    // Verify agent is done
    const agentResult = await sendRpc("db.agents.get", { id: "test-agent" });
    expect((agentResult.data as any).agent.status).toBe("done");
  });

  it("should end session via hooks.sessionEnd", async () => {
    const result = await sendRpc("hooks.sessionEnd", hookArgs("SessionEnd", { reason: "other" }));
    expect(result.ok).toBe(true);
    expect((result.data as any).sessionEnded).toBe(true);
    expect((result.data as any).agentUpdated).toBe(true);
  });
});

// ── 7. Concurrent connections ───────────────────────────────

describe("integration: concurrent connections", () => {
  it("should handle multiple simultaneous RPC calls", async () => {
    const results = await Promise.all([
      sendRpc("hooks.preToolUse", hookArgs("PreToolUse", { tool_name: "Read", tool_input: {}, tool_use_id: "tu_1" })),
      sendRpc("hooks.userPrompt", hookArgs("UserPromptSubmit", { prompt: "test" })),
      sendRpc("hooks.postToolUse", hookArgs("PostToolUse", { tool_name: "Bash", tool_input: {}, tool_response: {}, tool_use_id: "tu_2" })),
    ]);

    for (const result of results) {
      expect(result.ok).toBe(true);
    }
  });
});
