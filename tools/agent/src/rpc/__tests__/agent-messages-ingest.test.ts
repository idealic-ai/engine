import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch, getRegistry } from "engine-shared/dispatch";
import { buildNamespace } from "engine-shared/namespace-builder";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";
import "../../../../db/src/rpc/registry.js";
import "../agent-messages-ingest.js";

let db: DbConnection;
let ctx: RpcContext;
let sessionId: number;
let tmpDir: string;

function buildFullContext(database: DbConnection): RpcContext {
  const context = {} as RpcContext;
  const registry = getRegistry();
  const dbNs = buildNamespace("db", registry, context);
  context.db = Object.assign(database as object, dbNs) as unknown as RpcContext["db"];
  const agentNs = buildNamespace("agent", registry, context);
  context.agent = agentNs as unknown as RpcContext["agent"];
  return context;
}

function writeJsonl(filePath: string, lines: object[]): void {
  const content = lines.map((l) => JSON.stringify(l)).join("\n") + "\n";
  fs.writeFileSync(filePath, content, "utf8");
}

beforeEach(async () => {
  db = await createTestDb();
  ctx = buildFullContext(db);
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ingest-test-"));

  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, ctx);
  await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, ctx);
  await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } }, ctx);

  const sessionRes = await dispatch({
    cmd: "db.session.start",
    args: { taskId: "sessions/test", effortId: 1, pid: 1234 },
  }, ctx);
  sessionId = (sessionRes as any).data.session.id as number;
});

afterEach(async () => {
  await db.close();
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

describe("agent.messages.ingest", () => {
  it("should ingest JSONL lines and store as messages", async () => {
    const jsonlPath = path.join(tmpDir, "transcript.jsonl");
    writeJsonl(jsonlPath, [
      { type: "human", message: { content: [{ type: "text", text: "Hello" }] } },
      { type: "assistant", message: { content: [{ type: "text", text: "Hi there" }] } },
    ]);

    const result = await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId, transcriptPath: jsonlPath },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.ingested).toBe(2);
    expect(result.data.newOffset).toBeGreaterThan(0);

    // Verify messages in DB
    const listRes = await dispatch({
      cmd: "db.messages.list",
      args: { sessionId },
    }, ctx);
    expect(listRes.ok).toBe(true);
    if (!listRes.ok) return;
    const messages = listRes.data.messages as Record<string, unknown>[];
    expect(messages).toHaveLength(2);
    expect(messages[0].role).toBe("human");
    expect(messages[1].role).toBe("assistant");
  });

  it("should advance waterline and not re-ingest on second call", async () => {
    const jsonlPath = path.join(tmpDir, "transcript.jsonl");
    writeJsonl(jsonlPath, [
      { type: "human", message: { content: [{ type: "text", text: "First" }] } },
    ]);

    // First ingestion
    const res1 = await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId, transcriptPath: jsonlPath },
    }, ctx);
    expect(res1.ok).toBe(true);
    expect((res1 as any).data.ingested).toBe(1);

    // Second call — no new data
    const res2 = await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId },
    }, ctx);
    expect(res2.ok).toBe(true);
    expect((res2 as any).data.ingested).toBe(0);

    // Total messages should still be 1
    const listRes = await dispatch({
      cmd: "db.messages.list",
      args: { sessionId },
    }, ctx);
    expect((listRes as any).data.messages).toHaveLength(1);
  });

  it("should incrementally ingest new lines appended after first ingestion", async () => {
    const jsonlPath = path.join(tmpDir, "transcript.jsonl");
    writeJsonl(jsonlPath, [
      { type: "human", message: { content: [{ type: "text", text: "First" }] } },
    ]);

    // First ingestion
    await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId, transcriptPath: jsonlPath },
    }, ctx);

    // Append more content
    fs.appendFileSync(jsonlPath, JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text: "Second" }] } }) + "\n");
    fs.appendFileSync(jsonlPath, JSON.stringify({ type: "human", message: { content: [{ type: "text", text: "Third" }] } }) + "\n");

    // Second ingestion — should pick up only new lines
    const res2 = await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId },
    }, ctx);
    expect(res2.ok).toBe(true);
    expect((res2 as any).data.ingested).toBe(2);

    // Total should be 3
    const listRes = await dispatch({
      cmd: "db.messages.list",
      args: { sessionId },
    }, ctx);
    expect((listRes as any).data.messages).toHaveLength(3);
  });

  it("should handle missing file gracefully", async () => {
    const result = await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId, transcriptPath: "/tmp/nonexistent-file.jsonl" },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.ingested).toBe(0);
  });

  it("should handle partial trailing line (no newline at end)", async () => {
    const jsonlPath = path.join(tmpDir, "transcript.jsonl");
    // Write a complete line + a partial line (no trailing newline)
    const complete = JSON.stringify({ type: "human", message: { content: [{ type: "text", text: "Complete" }] } }) + "\n";
    const partial = '{"type":"assistant","message":{"content":[{"type":"text","te';
    fs.writeFileSync(jsonlPath, complete + partial, "utf8");

    const result = await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId, transcriptPath: jsonlPath },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    // Only the complete line should be ingested
    expect(result.data.ingested).toBe(1);

    // Offset should be at end of the complete line, not the partial
    expect(result.data.newOffset).toBe(Buffer.byteLength(complete, "utf8"));
  });

  it("should extract toolName from assistant tool_use blocks", async () => {
    const jsonlPath = path.join(tmpDir, "transcript.jsonl");
    writeJsonl(jsonlPath, [
      {
        type: "assistant",
        message: {
          content: [
            { type: "text", text: "Let me read that file." },
            { type: "tool_use", name: "Read", input: { file_path: "/tmp/test.ts" } },
          ],
        },
      },
    ]);

    await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId, transcriptPath: jsonlPath },
    }, ctx);

    const listRes = await dispatch({
      cmd: "db.messages.list",
      args: { sessionId },
    }, ctx);
    const messages = (listRes as any).data.messages;
    expect(messages[0].toolName).toBe("Read");
  });

  it("should store transcript_path on session row on first call", async () => {
    const jsonlPath = path.join(tmpDir, "transcript.jsonl");
    writeJsonl(jsonlPath, [{ type: "human", message: { content: [] } }]);

    await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId, transcriptPath: jsonlPath },
    }, ctx);

    // Verify path was stored
    const row = await db.get<{ transcript_path: string }>(
      "SELECT transcript_path FROM sessions WHERE id = ?",
      [sessionId]
    );
    expect(row!.transcriptPath).toBe(jsonlPath);
  });

  it("should return gracefully when session not found", async () => {
    const result = await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId: 9999 },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.ingested).toBe(0);
  });

  it("should return gracefully when no transcript path available", async () => {
    const result = await dispatch({
      cmd: "agent.messages.ingest",
      args: { sessionId },
    }, ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.ingested).toBe(0);
  });
});
