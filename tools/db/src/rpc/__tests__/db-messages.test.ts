import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-skills-upsert.js";
import "../db-effort-start.js";
import "../db-session-start.js";
import "../db-messages-append.js";
import "../db-messages-list.js";
import { createTestDb } from "../../__tests__/helpers.js";

let db: Database;
let sessionId: number;

beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
  dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/t1", projectId: 1 } }, db);
  dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, db);
  dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/t1", skill: "implement" } }, db);
  const sessionResult = dispatch({
    cmd: "db.session.start",
    args: { taskId: "sessions/t1", effortId: 1, pid: 1234 },
  }, db);
  if (sessionResult.ok) {
    sessionId = (sessionResult.data.session as Record<string, unknown>).id as number;
  }
});
afterEach(() => {
  db.close();
});

describe("db.messages.append", () => {
  it("should append a message to a session", () => {
    const result = dispatch({
      cmd: "db.messages.append",
      args: { sessionId, role: "user", content: "Hello world" },
    }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const msg = result.data.message as Record<string, unknown>;
    expect(msg.role).toBe("user");
    expect(msg.content).toBe("Hello world");
    expect(msg.session_id).toBe(sessionId);
  });

  it("should store optional tool_name", () => {
    const result = dispatch({
      cmd: "db.messages.append",
      args: { sessionId, role: "assistant", content: "Reading file", toolName: "Read" },
    }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const msg = result.data.message as Record<string, unknown>;
    expect(msg.tool_name).toBe("Read");
  });

  it("should reject non-existent sessionId (FK)", () => {
    const result = dispatch({
      cmd: "db.messages.append",
      args: { sessionId: 999, role: "user", content: "test" },
    }, db);

    expect(result.ok).toBe(false);
  });
});

describe("db.messages.list", () => {
  it("should list messages for a session ordered by timestamp", () => {
    dispatch({ cmd: "db.messages.append", args: { sessionId, role: "user", content: "First" } }, db);
    dispatch({ cmd: "db.messages.append", args: { sessionId, role: "assistant", content: "Second" } }, db);
    dispatch({ cmd: "db.messages.append", args: { sessionId, role: "user", content: "Third" } }, db);

    const result = dispatch({ cmd: "db.messages.list", args: { sessionId } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const messages = result.data.messages as Record<string, unknown>[];
    expect(messages).toHaveLength(3);
    expect(messages[0].content).toBe("First");
    expect(messages[2].content).toBe("Third");
  });

  it("should respect limit parameter", () => {
    dispatch({ cmd: "db.messages.append", args: { sessionId, role: "user", content: "A" } }, db);
    dispatch({ cmd: "db.messages.append", args: { sessionId, role: "user", content: "B" } }, db);
    dispatch({ cmd: "db.messages.append", args: { sessionId, role: "user", content: "C" } }, db);

    const result = dispatch({ cmd: "db.messages.list", args: { sessionId, limit: 2 } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.messages).toHaveLength(2);
  });

  it("should return empty array for session with no messages", () => {
    const result = dispatch({ cmd: "db.messages.list", args: { sessionId } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.messages).toEqual([]);
  });
});
