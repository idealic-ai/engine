import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-skills-upsert.js";
import "../db-effort-start.js";
import "../db-session-start.js";
import "../db-messages-upsert.js";
import "../db-messages-list.js";
import "../db-session-set-transcript.js";
import { createTestDb } from "../../__tests__/helpers.js";

let db: DbConnection;
let sessionId: number;

beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, { db } as unknown as RpcContext);
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/t1", projectId: 1 } }, { db } as unknown as RpcContext);
  await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, { db } as unknown as RpcContext);
  await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/t1", skill: "implement" } }, { db } as unknown as RpcContext);
  const sessionResult = await dispatch({
    cmd: "db.session.start",
    args: { taskId: "sessions/t1", effortId: 1, pid: 1234 },
  }, { db } as unknown as RpcContext);
  if (sessionResult.ok) {
    sessionId = (sessionResult.data.session as Record<string, unknown>).id as number;
  }
});
afterEach(async () => {
  await db.close();
});

describe("db.messages.upsert", () => {
  it("should bulk insert multiple messages", async () => {
    const result = await dispatch({
      cmd: "db.messages.upsert",
      args: {
        sessionId,
        messages: [
          { role: "human", content: '{"type":"human","message":"Hello"}' },
          { role: "assistant", content: '{"type":"assistant","message":"Hi"}' },
          { role: "human", content: '{"type":"human","message":"Thanks"}' },
        ],
      },
    }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.inserted).toBe(3);

    // Verify via messages.list
    const listResult = await dispatch({
      cmd: "db.messages.list",
      args: { sessionId },
    }, { db } as unknown as RpcContext);
    expect(listResult.ok).toBe(true);
    if (!listResult.ok) return;
    const messages = listResult.data.messages as Record<string, unknown>[];
    expect(messages).toHaveLength(3);
    expect(messages[0].role).toBe("human");
    expect(messages[1].role).toBe("assistant");
  });

  it("should handle empty messages array", async () => {
    const result = await dispatch({
      cmd: "db.messages.upsert",
      args: { sessionId, messages: [] },
    }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.inserted).toBe(0);
  });

  it("should store optional toolName", async () => {
    const result = await dispatch({
      cmd: "db.messages.upsert",
      args: {
        sessionId,
        messages: [
          { role: "assistant", content: '{"type":"assistant"}', toolName: "Read" },
        ],
      },
    }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);

    const listResult = await dispatch({
      cmd: "db.messages.list",
      args: { sessionId },
    }, { db } as unknown as RpcContext);
    if (!listResult.ok) return;
    const messages = listResult.data.messages as Record<string, unknown>[];
    expect(messages[0].toolName).toBe("Read");
  });

  it("should reject non-existent sessionId (FK)", async () => {
    const result = await dispatch({
      cmd: "db.messages.upsert",
      args: {
        sessionId: 999,
        messages: [{ role: "human", content: "test" }],
      },
    }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(false);
  });
});

describe("db.session.setTranscript", () => {
  it("should set transcript_path on a session", async () => {
    const result = await dispatch({
      cmd: "db.session.setTranscript",
      args: { sessionId, transcriptPath: "/tmp/abc123.jsonl" },
    }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.updated).toBe(true);

    const row = await db.get<{ transcript_path: string }>(
      "SELECT transcript_path FROM sessions WHERE id = ?",
      [sessionId]
    );
    expect(row!.transcriptPath).toBe("/tmp/abc123.jsonl");
  });

  it("should update transcript_offset", async () => {
    await dispatch({
      cmd: "db.session.setTranscript",
      args: { sessionId, transcriptOffset: 4096 },
    }, { db } as unknown as RpcContext);

    const row = await db.get<{ transcript_offset: number }>(
      "SELECT transcript_offset FROM sessions WHERE id = ?",
      [sessionId]
    );
    expect(row!.transcriptOffset).toBe(4096);
  });

  it("should update both path and offset together", async () => {
    await dispatch({
      cmd: "db.session.setTranscript",
      args: { sessionId, transcriptPath: "/tmp/xyz.jsonl", transcriptOffset: 1024 },
    }, { db } as unknown as RpcContext);

    const row = await db.get<{ transcript_path: string; transcript_offset: number }>(
      "SELECT transcript_path, transcript_offset FROM sessions WHERE id = ?",
      [sessionId]
    );
    expect(row!.transcriptPath).toBe("/tmp/xyz.jsonl");
    expect(row!.transcriptOffset).toBe(1024);
  });

  it("should return updated=false when no fields provided", async () => {
    const result = await dispatch({
      cmd: "db.session.setTranscript",
      args: { sessionId },
    }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.updated).toBe(false);
  });
});
