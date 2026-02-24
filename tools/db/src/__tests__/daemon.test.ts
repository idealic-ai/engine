import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as net from "node:net";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { startDaemon, stopDaemon } from "../../../daemon/src/daemon.js";

const TEST_DIR = path.join(os.tmpdir(), `engine-db-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
const SOCKET_PATH = path.join(TEST_DIR, "test.sock");
const DB_PATH = path.join(TEST_DIR, "test.db");

beforeEach(() => {
  fs.mkdirSync(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await stopDaemon();
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
});

async function send(payload: Record<string, unknown>): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const client = net.createConnection(SOCKET_PATH, () => {
      client.write(JSON.stringify(payload) + "\n");
    });
    let data = "";
    client.on("data", (chunk) => {
      data += chunk.toString();
      if (data.includes("\n")) {
        client.end();
        try { resolve(JSON.parse(data.trim())); }
        catch { reject(new Error(`Invalid JSON: ${data}`)); }
      }
    });
    client.on("error", reject);
    client.setTimeout(5000, () => { client.destroy(); reject(new Error("Timeout")); });
  });
}

async function query(request: {
  sql: string;
  params?: (string | number | null)[];
  format?: "json" | "tsv" | "scalar";
  single?: boolean;
}): Promise<unknown> {
  return send({
    sql: request.sql,
    params: request.params ?? [],
    format: request.format ?? "json",
    single: request.single ?? false,
  });
}

describe("daemon — raw SQL", () => {
  it("should start and accept connections on Unix socket", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    expect(fs.existsSync(SOCKET_PATH)).toBe(true);
    const result = await query({ sql: "SELECT 1 AS value" });
    expect(result).toEqual({ ok: true, rows: [{ value: 1 }] });
  });

  it("should execute SELECT queries and return JSON rows", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    // v3: must create project → task chain
    await query({ sql: "INSERT INTO projects (path) VALUES (?)", params: ["/test"] });
    await query({
      sql: "INSERT INTO tasks (dir_path, project_id, title) VALUES (?, ?, ?)",
      params: ["s1", 1, "Test Task"],
    });
    const result = await query({
      sql: "SELECT dir_path, title FROM tasks WHERE dir_path = ?",
      params: ["s1"],
    }) as { ok: boolean; rows: Record<string, unknown>[] };
    expect(result.ok).toBe(true);
    expect(result.rows).toHaveLength(1);
    expect(result.rows[0]).toMatchObject({ dir_path: "s1", title: "Test Task" });
  });

  it("should execute INSERT/UPDATE and return changes count", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    await query({ sql: "INSERT INTO projects (path) VALUES (?)", params: ["/test"] });
    const ins = await query({
      sql: "INSERT INTO tasks (dir_path, project_id) VALUES (?, ?)",
      params: ["s1", 1],
    }) as { ok: boolean; changes: number };
    expect(ins.ok).toBe(true);
    expect(ins.changes).toBe(1);

    const upd = await query({
      sql: "UPDATE tasks SET title = ? WHERE dir_path = ?",
      params: ["Updated", "s1"],
    }) as { ok: boolean; changes: number };
    expect(upd.ok).toBe(true);
    expect(upd.changes).toBe(1);
  });

  it("should return --single format", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    await query({ sql: "INSERT INTO projects (path) VALUES (?)", params: ["/test"] });
    await query({ sql: "INSERT INTO tasks (dir_path, project_id) VALUES (?, ?)", params: ["s1", 1] });
    const result = await query({
      sql: "SELECT dir_path FROM tasks WHERE dir_path = ?",
      params: ["s1"],
      single: true,
    }) as { ok: boolean; row: Record<string, unknown> };
    expect(result.ok).toBe(true);
    expect(result.row).toMatchObject({ dir_path: "s1" });
  });

  it("should return --format=scalar", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    const result = await query({ sql: "SELECT COUNT(*) FROM tasks", format: "scalar" }) as { ok: boolean; value: unknown };
    expect(result.ok).toBe(true);
    expect(result.value).toBe(0);
  });

  it("should handle SQL errors gracefully", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    const result = await query({ sql: "SELECT * FROM nonexistent_table" }) as { ok: boolean; error: string };
    expect(result.ok).toBe(false);
    expect(result.error).toBeTruthy();
  });

  it("should persist DB to disk on shutdown", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    await query({ sql: "INSERT INTO projects (path) VALUES (?)", params: ["/persist"] });
    await stopDaemon();
    expect(fs.existsSync(DB_PATH)).toBe(true);
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    const result = await query({
      sql: "SELECT path FROM projects WHERE path = ?",
      params: ["/persist"],
    }) as { ok: boolean; rows: Record<string, unknown>[] };
    expect(result.ok).toBe(true);
    expect(result.rows).toHaveLength(1);
  });

  it("should clean up stale socket file on startup", async () => {
    fs.writeFileSync(SOCKET_PATH, "stale");
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    const result = await query({ sql: "SELECT 1 AS value" });
    expect(result).toEqual({ ok: true, rows: [{ value: 1 }] });
  });
});

describe("daemon — RPC dispatch", () => {
  it("should route {cmd} messages to v3 RPC handlers", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    const result = await send({
      cmd: "db.project.upsert",
      args: { path: "/rpc-test", name: "RPC Test" },
    }) as { ok: boolean; data: Record<string, unknown> };
    expect(result.ok).toBe(true);
    expect(result.data.project).toBeDefined();
    expect((result.data.project as any).path).toBe("/rpc-test");
  });

  it("should return UNKNOWN_COMMAND for unregistered RPCs", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    const result = await send({ cmd: "db.nonexistent.command" }) as { ok: boolean; error: string };
    expect(result.ok).toBe(false);
    expect(result.error).toBe("UNKNOWN_COMMAND");
  });

  it("should return VALIDATION_ERROR for bad args", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    const result = await send({
      cmd: "db.project.upsert",
      args: {},
    }) as { ok: boolean; error: string };
    expect(result.ok).toBe(false);
    expect(result.error).toBe("VALIDATION_ERROR");
  });

  it("should support full v3 lifecycle: project → task → effort → phase → session", async () => {
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });

    // Project
    const p = await send({ cmd: "db.project.upsert", args: { path: "/lifecycle" } }) as any;
    expect(p.ok).toBe(true);

    // Task
    const t = await send({ cmd: "db.task.upsert", args: { dirPath: "sessions/lc", projectId: 1 } }) as any;
    expect(t.ok).toBe(true);

    // Skills (for phase enforcement)
    await send({
      cmd: "db.skills.upsert",
      args: {
        projectId: 1,
        name: "implement",
        phases: [{ label: "0", name: "Setup" }, { label: "1", name: "Build" }],
      },
    });

    // Effort
    const e = await send({ cmd: "db.effort.start", args: { taskId: "sessions/lc", skill: "implement" } }) as any;
    expect(e.ok).toBe(true);
    const effortId = e.data.effort.id;

    // Session
    const s = await send({ cmd: "db.session.start", args: { taskId: "sessions/lc", effortId, pid: 1 } }) as any;
    expect(s.ok).toBe(true);

    // Phase transitions
    const ph0 = await send({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } }) as any;
    expect(ph0.ok).toBe(true);
    const ph1 = await send({ cmd: "db.effort.phase", args: { effortId, phase: "1: Build" } }) as any;
    expect(ph1.ok).toBe(true);

    // Finish effort
    const fin = await send({ cmd: "db.effort.finish", args: { effortId } }) as any;
    expect(fin.ok).toBe(true);
    expect(fin.data.effort.lifecycle).toBe("finished");
  });
});
