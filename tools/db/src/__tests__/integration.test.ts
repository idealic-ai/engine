import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { startDaemon, stopDaemon } from "../daemon.js";
import { sendQuery, type QueryResult } from "../query-client.js";

const TEST_DIR = path.join(os.tmpdir(), `edb-int-${process.pid}`);
const SOCKET_PATH = `/tmp/edb-int-${process.pid}.sock`;
const DB_PATH = path.join(TEST_DIR, "test.db");

beforeEach(async () => {
  fs.mkdirSync(TEST_DIR, { recursive: true });
  await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
});

afterEach(async () => {
  await stopDaemon();
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
  fs.rmSync(SOCKET_PATH, { force: true });
});

function q(sql: string, params: (string | number | null)[] = [], opts?: { single?: boolean; format?: "json" | "tsv" | "scalar" }): Promise<QueryResult> {
  return sendQuery(SOCKET_PATH, {
    sql,
    params,
    format: opts?.format ?? "json",
    single: opts?.single ?? false,
  });
}

describe("integration: v3 lifecycle via raw SQL", () => {
  it("should create project → task → effort → session chain", async () => {
    await q("INSERT INTO projects (path) VALUES (?)", ["/test"]);
    await q("INSERT INTO tasks (dir_path, project_id, title) VALUES (?, ?, ?)", ["t1", 1, "Test"]);
    await q("INSERT INTO efforts (task_id, skill, ordinal) VALUES (?, ?, ?)", ["t1", "implement", 1]);
    await q("INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat) VALUES (?, ?, ?, datetime('now'))", ["t1", 1, 123]);

    const efforts = await q("SELECT skill, ordinal FROM efforts WHERE task_id = ?", ["t1"]) as QueryResult & { rows: Record<string, unknown>[] };
    expect(efforts.rows).toHaveLength(1);
    expect(efforts.rows[0].skill).toBe("implement");

    const sessions = await q("SELECT pid FROM sessions WHERE effort_id = ? AND ended_at IS NULL", [1]) as QueryResult & { rows: Record<string, unknown>[] };
    expect(sessions.rows).toHaveLength(1);
    expect(sessions.rows[0].pid).toBe(123);
  });

  it("should store and retrieve JSONB metadata on efforts", async () => {
    await q("INSERT INTO projects (path) VALUES (?)", ["/test"]);
    await q("INSERT INTO tasks (dir_path, project_id) VALUES (?, ?)", ["t1", 1]);
    const metadata = JSON.stringify({ taskSummary: "Build daemon", scope: "Code Changes" });
    await q("INSERT INTO efforts (task_id, skill, ordinal, metadata) VALUES (?, ?, ?, jsonb(?))", ["t1", "impl", 1, metadata]);

    const result = await q(
      "SELECT json_extract(metadata, '$.taskSummary') as summary FROM efforts WHERE task_id = ?",
      ["t1"],
      { single: true }
    ) as QueryResult & { row: Record<string, unknown> };
    expect(result.row.summary).toBe("Build daemon");
  });

  it("should detect stale sessions via view", async () => {
    await q("INSERT INTO projects (path) VALUES (?)", ["/test"]);
    await q("INSERT INTO tasks (dir_path, project_id) VALUES (?, ?)", ["t1", 1]);
    await q("INSERT INTO efforts (task_id, skill, ordinal) VALUES (?, ?, ?)", ["t1", "impl", 1]);
    await q("INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat) VALUES (?, ?, ?, datetime('now'))", ["t1", 1, 111]);
    await q("INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat) VALUES (?, ?, ?, datetime('now', '-10 minutes'))", ["t1", 1, 222]);

    const stale = await q("SELECT pid FROM stale_sessions") as QueryResult & { rows: Record<string, unknown>[] };
    expect(stale.rows).toHaveLength(1);
    expect(stale.rows[0].pid).toBe(222);
  });

  it("should persist across daemon restart", async () => {
    await q("INSERT INTO projects (path) VALUES (?)", ["/persist"]);
    await stopDaemon();
    await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
    const result = await q("SELECT path FROM projects WHERE path = ?", ["/persist"]) as QueryResult & { rows: Record<string, unknown>[] };
    expect(result.rows).toHaveLength(1);
  });

  it("should support TSV output", async () => {
    await q("INSERT INTO projects (path, name) VALUES (?, ?)", ["/p1", "One"]);
    await q("INSERT INTO projects (path, name) VALUES (?, ?)", ["/p2", "Two"]);
    const result = await q("SELECT path, name FROM projects ORDER BY path", [], { format: "tsv" }) as QueryResult & { tsv: string };
    const lines = result.tsv.split("\n").filter(Boolean);
    expect(lines[0]).toBe("path\tname");
    expect(lines[1]).toContain("/p1");
  });

  it("should handle active_efforts view", async () => {
    await q("INSERT INTO projects (path) VALUES (?)", ["/test"]);
    await q("INSERT INTO tasks (dir_path, project_id) VALUES (?, ?)", ["t1", 1]);
    await q("INSERT INTO efforts (task_id, skill, ordinal, lifecycle) VALUES (?, ?, ?, ?)", ["t1", "implement", 1, "active"]);
    await q("INSERT INTO efforts (task_id, skill, ordinal, lifecycle) VALUES (?, ?, ?, ?)", ["t1", "brainstorm", 2, "finished"]);

    const active = await q("SELECT skill FROM active_efforts") as QueryResult & { rows: Record<string, unknown>[] };
    expect(active.rows).toHaveLength(1);
    expect(active.rows[0].skill).toBe("implement");
  });
});
