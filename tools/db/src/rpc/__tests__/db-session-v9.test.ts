/**
 * Tests for session schema v9 — session-scoped state migration.
 *
 * New columns: heartbeat_interval, preloaded_files, pending_injections,
 * discovered_directives, discovered_directories.
 *
 * New RPCs: db.session.updateInjections, db.session.updatePreloadedFiles,
 * db.session.getInjections.
 */
import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-session-start.js";
import "../db-session-update-injections.js";
import "../db-session-update-preloaded-files.js";
import "../db-session-get-injections.js";
import { createTestDb, queryRow } from "../../__tests__/helpers.js";

let db: DbConnection;
let effortId: number;
let sessionId: number;

beforeEach(async () => {
  db = await createTestDb();
  const ctx = { db } as unknown as RpcContext;
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, ctx);
  const effortResult = await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } }, ctx);
  effortId = (effortResult as any).data.effort.id;
  const sessionResult = await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId } }, ctx);
  sessionId = (sessionResult as any).data.session.id;
});

afterEach(async () => { await db.close(); });

// ── Schema: new columns exist ────────────────────────────────

describe("schema v9: new session columns", () => {
  it("heartbeat_interval defaults to 10", async () => {
    const row = await queryRow(db, "SELECT heartbeat_interval FROM sessions WHERE id = ?", [sessionId]);
    expect(row).not.toBeNull();
    expect(row!.heartbeatInterval).toBe(10);
  });

  it("preloaded_files defaults to null", async () => {
    const row = await queryRow(db, "SELECT preloaded_files FROM sessions WHERE id = ?", [sessionId]);
    expect(row).not.toBeNull();
    expect(row!.preloadedFiles).toBeNull();
  });

  it("pending_injections defaults to null", async () => {
    const row = await queryRow(db, "SELECT pending_injections FROM sessions WHERE id = ?", [sessionId]);
    expect(row).not.toBeNull();
    expect(row!.pendingInjections).toBeNull();
  });

  it("discovered_directives defaults to null", async () => {
    const row = await queryRow(db, "SELECT discovered_directives FROM sessions WHERE id = ?", [sessionId]);
    expect(row).not.toBeNull();
    expect(row!.discoveredDirectives).toBeNull();
  });

  it("discovered_directories defaults to null", async () => {
    const row = await queryRow(db, "SELECT discovered_directories FROM sessions WHERE id = ?", [sessionId]);
    expect(row).not.toBeNull();
    expect(row!.discoveredDirectories).toBeNull();
  });
});

// ── db.session.updateInjections ──────────────────────────────

describe("db.session.updateInjections", () => {
  it("adds injections to empty queue", async () => {
    const result = await dispatch({
      cmd: "db.session.updateInjections",
      args: {
        sessionId,
        add: [
          { ruleId: "AGENTS", content: "Always use semicolons.", mode: "message" },
          { ruleId: "PITFALLS", content: "Watch for null.", mode: "preload", path: "/dir/PITFALLS.md" },
        ],
      },
    }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    const data = (result as any).data;
    expect(data.injections).toHaveLength(2);
    expect(data.injections[0].ruleId).toBe("AGENTS");
    expect(data.injections[1].mode).toBe("preload");
    expect(data.injections[1].path).toBe("/dir/PITFALLS.md");
  });

  it("appends to existing injections", async () => {
    const ctx = { db } as unknown as RpcContext;
    await dispatch({
      cmd: "db.session.updateInjections",
      args: { sessionId, add: [{ ruleId: "A", content: "first", mode: "message" }] },
    }, ctx);
    const result = await dispatch({
      cmd: "db.session.updateInjections",
      args: { sessionId, add: [{ ruleId: "B", content: "second", mode: "message" }] },
    }, ctx);

    expect(result.ok).toBe(true);
    expect((result as any).data.injections).toHaveLength(2);
  });

  it("removes processed injections by ruleId", async () => {
    const ctx = { db } as unknown as RpcContext;
    await dispatch({
      cmd: "db.session.updateInjections",
      args: {
        sessionId,
        add: [
          { ruleId: "A", content: "first", mode: "message" },
          { ruleId: "B", content: "second", mode: "message" },
          { ruleId: "C", content: "third", mode: "message" },
        ],
      },
    }, ctx);

    const result = await dispatch({
      cmd: "db.session.updateInjections",
      args: { sessionId, removeByRuleId: ["A", "C"] },
    }, ctx);

    expect(result.ok).toBe(true);
    const injections = (result as any).data.injections;
    expect(injections).toHaveLength(1);
    expect(injections[0].ruleId).toBe("B");
  });

  it("clears all injections", async () => {
    const ctx = { db } as unknown as RpcContext;
    await dispatch({
      cmd: "db.session.updateInjections",
      args: { sessionId, add: [{ ruleId: "X", content: "y", mode: "message" }] },
    }, ctx);

    const result = await dispatch({
      cmd: "db.session.updateInjections",
      args: { sessionId, clearAll: true },
    }, ctx);

    expect(result.ok).toBe(true);
    expect((result as any).data.injections).toEqual([]);
  });

  it("returns error for non-existent session", async () => {
    const result = await dispatch({
      cmd: "db.session.updateInjections",
      args: { sessionId: 999, add: [{ ruleId: "X", content: "y", mode: "message" }] },
    }, { db } as unknown as RpcContext);
    expect(result.ok).toBe(false);
  });
});

// ── db.session.getInjections ─────────────────────────────────

describe("db.session.getInjections", () => {
  it("returns empty array when no injections", async () => {
    const result = await dispatch({
      cmd: "db.session.getInjections",
      args: { sessionId },
    }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    expect((result as any).data.injections).toEqual([]);
  });

  it("returns current injections", async () => {
    const ctx = { db } as unknown as RpcContext;
    await dispatch({
      cmd: "db.session.updateInjections",
      args: { sessionId, add: [{ ruleId: "X", content: "test", mode: "preload", path: "/f.md" }] },
    }, ctx);

    const result = await dispatch({
      cmd: "db.session.getInjections",
      args: { sessionId },
    }, ctx);

    expect(result.ok).toBe(true);
    const injections = (result as any).data.injections;
    expect(injections).toHaveLength(1);
    expect(injections[0].ruleId).toBe("X");
    expect(injections[0].path).toBe("/f.md");
  });
});

// ── db.session.updatePreloadedFiles ──────────────────────────

describe("db.session.updatePreloadedFiles", () => {
  it("adds files to empty preloaded list", async () => {
    const result = await dispatch({
      cmd: "db.session.updatePreloadedFiles",
      args: { sessionId, add: ["/a.md", "/b.md"] },
    }, { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    expect((result as any).data.preloadedFiles).toEqual(["/a.md", "/b.md"]);
  });

  it("deduplicates against existing preloaded files", async () => {
    const ctx = { db } as unknown as RpcContext;
    await dispatch({
      cmd: "db.session.updatePreloadedFiles",
      args: { sessionId, add: ["/a.md", "/b.md"] },
    }, ctx);

    const result = await dispatch({
      cmd: "db.session.updatePreloadedFiles",
      args: { sessionId, add: ["/b.md", "/c.md"] },
    }, ctx);

    expect(result.ok).toBe(true);
    expect((result as any).data.preloadedFiles).toEqual(["/a.md", "/b.md", "/c.md"]);
  });

  it("deduplicates against loaded_files (Read tool)", async () => {
    const ctx = { db } as unknown as RpcContext;
    // Simulate Read tool tracking
    await db.run(
      "UPDATE sessions SET loaded_files = json(?) WHERE id = ?",
      [JSON.stringify(["/already-read.md"]), sessionId],
    );

    const result = await dispatch({
      cmd: "db.session.updatePreloadedFiles",
      args: { sessionId, add: ["/already-read.md", "/new.md"] },
    }, ctx);

    expect(result.ok).toBe(true);
    // /already-read.md should be excluded (already in loaded_files)
    expect((result as any).data.preloadedFiles).toEqual(["/new.md"]);
  });

  it("returns error for non-existent session", async () => {
    const result = await dispatch({
      cmd: "db.session.updatePreloadedFiles",
      args: { sessionId: 999, add: ["/a.md"] },
    }, { db } as unknown as RpcContext);
    expect(result.ok).toBe(false);
  });
});

// ── Session inheritance on rehydration ───────────────────────

describe("session inheritance via prev_session_id", () => {
  it("new session inherits discovered_directives from previous", async () => {
    const ctx = { db } as unknown as RpcContext;
    // Set directives on first session
    await db.run(
      "UPDATE sessions SET discovered_directives = json(?) WHERE id = ?",
      [JSON.stringify(["/dir/AGENTS.md", "/dir/PITFALLS.md"]), sessionId],
    );
    await db.run(
      "UPDATE sessions SET discovered_directories = json(?) WHERE id = ?",
      [JSON.stringify(["/packages/estimate"]), sessionId],
    );

    // Create new session (auto-ends previous, links via prev_session_id)
    const result = await dispatch({
      cmd: "db.session.start",
      args: { taskId: "sessions/test", effortId },
    }, ctx);

    expect(result.ok).toBe(true);
    const newSession = (result as any).data.session;
    expect(newSession.prevSessionId).toBe(sessionId);

    // New session should inherit directives and directories
    const row = await queryRow(db, "SELECT discovered_directives, discovered_directories FROM sessions WHERE id = ?", [newSession.id]);
    expect(row!.discoveredDirectives).toEqual(["/dir/AGENTS.md", "/dir/PITFALLS.md"]);
    expect(row!.discoveredDirectories).toEqual(["/packages/estimate"]);
  });

  it("new session starts with fresh loaded_files and preloaded_files", async () => {
    const ctx = { db } as unknown as RpcContext;
    // Populate files on first session
    await db.run(
      "UPDATE sessions SET loaded_files = json(?), preloaded_files = json(?) WHERE id = ?",
      [JSON.stringify(["/read.ts"]), JSON.stringify(["/preloaded.md"]), sessionId],
    );

    const result = await dispatch({
      cmd: "db.session.start",
      args: { taskId: "sessions/test", effortId },
    }, ctx);

    const newSession = (result as any).data.session;
    expect(newSession.loadedFiles).toBeNull();
    expect(newSession.preloadedFiles).toBeNull();
  });

  it("new session starts with empty pending_injections", async () => {
    const ctx = { db } as unknown as RpcContext;
    await dispatch({
      cmd: "db.session.updateInjections",
      args: { sessionId, add: [{ ruleId: "X", content: "leftover", mode: "message" }] },
    }, ctx);

    const result = await dispatch({
      cmd: "db.session.start",
      args: { taskId: "sessions/test", effortId },
    }, ctx);

    const newSession = (result as any).data.session;
    expect(newSession.pendingInjections).toBeNull();
  });
});
