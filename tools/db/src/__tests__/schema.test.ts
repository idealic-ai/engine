import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { createTestDb } from "./helpers.js";
import { SCHEMA_VERSION } from "../schema.js";
import type { DbConnection } from "../db-wrapper.js";

let db: DbConnection;

beforeEach(async () => {
  db = await createTestDb();
});

afterEach(async () => {
  await db.close();
});

/** Helper: get CREATE TABLE sql for a given table name */
async function getTableSql(name: string): Promise<string> {
  const row = await db.get<{ sql: string }>(
    "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
    [name]
  );
  return row!.sql;
}

describe("applySchema v3", () => {
  // ── Table existence ──────────────────────────────────────

  it("should create all 10 tables", async () => {
    const rows = await db.all<{ name: string }>(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    );
    const tables = rows.map((r) => r.name);

    expect(tables).toContain("projects");
    expect(tables).toContain("skills");
    expect(tables).toContain("tasks");
    expect(tables).toContain("efforts");
    expect(tables).toContain("sessions");
    expect(tables).toContain("phase_history");
    expect(tables).toContain("messages");
    expect(tables).toContain("agents");
    expect(tables).toContain("chunks");
    expect(tables).toContain("embeddings");
  });

  // ── Projects table ───────────────────────────────────────

  it("should create projects table with correct columns", async () => {
    const sql = await getTableSql("projects");

    expect(sql).toContain("id");
    expect(sql).toContain("path");
    expect(sql).toContain("UNIQUE");
    expect(sql).toContain("name");
  });

  // ── Skills table ─────────────────────────────────────────

  it("should create skills table with JSONB columns", async () => {
    const sql = await getTableSql("skills");

    expect(sql).toContain("project_id");
    expect(sql).toContain("REFERENCES projects(id)");
    expect(sql).toContain("name");
    expect(sql).toContain("phases");
    expect(sql).toContain("modes");
    expect(sql).toContain("version");
    expect(sql).toContain("description");
    expect(sql).toContain("UNIQUE(project_id, name)");
  });

  // ── Tasks table ──────────────────────────────────────────

  it("should create tasks table without lifecycle column", async () => {
    const sql = await getTableSql("tasks");

    expect(sql).toContain("dir_path    TEXT PRIMARY KEY");
    expect(sql).toContain("project_id");
    expect(sql).toContain("REFERENCES projects(id)");
    expect(sql).toContain("workspace");
    expect(sql).toContain("keywords");
    // v3: NO lifecycle column on tasks (derived from efforts)
    expect(sql).not.toContain("lifecycle");
  });

  // ── Efforts table ────────────────────────────────────────

  it("should create efforts table with ordinal and lifecycle", async () => {
    const sql = await getTableSql("efforts");

    expect(sql).toContain("task_id");
    expect(sql).toContain("REFERENCES tasks(dir_path)");
    expect(sql).toContain("skill");
    expect(sql).toContain("ordinal");
    expect(sql).toContain("lifecycle");
    expect(sql).toContain("current_phase");
    expect(sql).toContain("UNIQUE(task_id, ordinal)");
  });

  // ── Sessions table ───────────────────────────────────────

  it("should create sessions table with effort_id NOT NULL", async () => {
    const sql = await getTableSql("sessions");

    expect(sql).toContain("effort_id");
    expect(sql).toContain("REFERENCES efforts(id)");
    expect(sql).toContain("prev_session_id");
    expect(sql).toContain("dehydration_payload");
    expect(sql).toContain("loaded_files");
    // v3: no preloaded_files, no touched_dirs, no pending_directives
    expect(sql).not.toContain("preloaded_files");
    expect(sql).not.toContain("touched_dirs");
    expect(sql).not.toContain("pending_directives");
  });

  // ── Phase history table ──────────────────────────────────

  it("should create phase_history with FK to efforts (not tasks)", async () => {
    const sql = await getTableSql("phase_history");

    expect(sql).toContain("effort_id");
    expect(sql).toContain("REFERENCES efforts(id)");
    // v3: FK to efforts, NOT tasks
    expect(sql).not.toContain("task_id");
  });

  // ── Messages table ───────────────────────────────────────

  it("should create messages table with FK to sessions", async () => {
    const sql = await getTableSql("messages");

    expect(sql).toContain("session_id");
    expect(sql).toContain("REFERENCES sessions(id)");
    expect(sql).toContain("role");
    expect(sql).toContain("content");
    expect(sql).toContain("tool_name");
  });

  // ── Agents table ─────────────────────────────────────────

  it("should create agents table with effort_id FK", async () => {
    const sql = await getTableSql("agents");

    expect(sql).toContain("TEXT PRIMARY KEY");
    expect(sql).toContain("targeted_claims");
    expect(sql).toContain("manages");
    expect(sql).toContain("parent");
    expect(sql).toContain("effort_id");
    expect(sql).toContain("REFERENCES efforts(id)");
  });

  // ── Embeddings table ─────────────────────────────────────

  it("should create chunks table with content_hash and unique constraint", async () => {
    const sql = await getTableSql("chunks");

    expect(sql).toContain("source_type");
    expect(sql).toContain("source_path");
    expect(sql).toContain("section_title");
    expect(sql).toContain("content_hash");
    expect(sql).toContain("UNIQUE(source_path, section_title)");
  });

  it("should create embeddings table keyed by content_hash", async () => {
    const sql = await getTableSql("embeddings");

    expect(sql).toContain("content_hash");
    expect(sql).toContain("embedding");
  });

  // ── Views ────────────────────────────────────────────────

  it("should create fleet_status view", async () => {
    const rows = await db.all<{ name: string }>(
      "SELECT name FROM sqlite_master WHERE type='view' AND name='fleet_status'"
    );
    expect(rows).toHaveLength(1);
  });

  it("should create task_summary view", async () => {
    const rows = await db.all<{ name: string }>(
      "SELECT name FROM sqlite_master WHERE type='view' AND name='task_summary'"
    );
    expect(rows).toHaveLength(1);
  });

  it("should create active_efforts view", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");
    await db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    await db.run(
      "INSERT INTO efforts (task_id, skill, ordinal, lifecycle) VALUES ('t1', 'implement', 1, 'active')"
    );
    await db.run(
      "INSERT INTO efforts (task_id, skill, ordinal, lifecycle) VALUES ('t1', 'brainstorm', 2, 'finished')"
    );

    const rows = await db.all<{ skill: string }>("SELECT skill FROM active_efforts");
    expect(rows).toHaveLength(1);
    expect(rows[0].skill).toBe("implement");
  });

  it("should create stale_sessions view", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");
    await db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    await db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );

    // Recent heartbeat — NOT stale
    await db.run(
      "INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat) VALUES ('t1', 1, 1234, datetime('now'))"
    );
    // Old heartbeat — stale
    await db.run(
      "INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat) VALUES ('t1', 1, 5678, datetime('now', '-10 minutes'))"
    );
    // Ended — NOT stale
    await db.run(
      "INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat, ended_at) VALUES ('t1', 1, 9999, datetime('now', '-10 minutes'), datetime('now'))"
    );

    const rows = await db.all<{ pid: number }>("SELECT pid FROM stale_sessions");
    expect(rows).toHaveLength(1);
    expect(rows[0].pid).toBe(5678);
  });

  // ── Indexes ──────────────────────────────────────────────

  it("should create compound indexes", async () => {
    const rows = await db.all<{ name: string }>(
      "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%' ORDER BY name"
    );
    const indexes = rows.map((r) => r.name);

    expect(indexes).toContain("idx_efforts_task_lifecycle");
    expect(indexes).toContain("idx_sessions_effort_ended");
    expect(indexes).toContain("idx_messages_session_ts");
  });

  // ── JSONB support ────────────────────────────────────────

  it("should support JSONB columns for round-trip storage", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");

    const phases = JSON.stringify([
      { label: "0", name: "Setup" },
      { label: "1", name: "Interrogation" },
    ]);
    await db.run(
      "INSERT INTO skills (project_id, name, phases) VALUES (1, 'implement', json(?))",
      [phases]
    );

    const row = await db.get<{ phases: unknown }>(
      "SELECT phases FROM skills WHERE name = 'implement'"
    );
    // wa-sqlite returns JSONB columns as already-parsed objects
    const parsed = typeof row!.phases === "string" ? JSON.parse(row!.phases) : row!.phases;
    expect(parsed).toHaveLength(2);
    expect(parsed[0].name).toBe("Setup");
  });

  it("should support json_extract on JSONB columns", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");
    await db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    await db.run(
      "INSERT INTO efforts (task_id, skill, ordinal, metadata) VALUES ('t1', 'impl', 1, json(?))",
      [JSON.stringify({ taskSummary: "test task", scope: "code changes" })]
    );

    const row = await db.get<{ val: string }>(
      "SELECT json_extract(metadata, '$.taskSummary') as val FROM efforts WHERE task_id = 't1'"
    );
    expect(row!.val).toBe("test task");
  });

  // ── FK enforcement ───────────────────────────────────────

  it("should enforce FK: task requires project", async () => {
    await expect(
      db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 999)")
    ).rejects.toThrow();
  });

  it("should enforce FK: effort requires task", async () => {
    await expect(
      db.run(
        "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('nonexistent', 'impl', 1)"
      )
    ).rejects.toThrow();
  });

  it("should enforce FK: session requires effort", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");
    await db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");

    await expect(
      db.run("INSERT INTO sessions (task_id, effort_id) VALUES ('t1', 999)")
    ).rejects.toThrow();
  });

  // ── CASCADE deletes ──────────────────────────────────────

  it("should cascade delete efforts when task deleted", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");
    await db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    await db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );

    await db.run("DELETE FROM tasks WHERE dir_path = 't1'");
    const row = await db.get<{ cnt: number }>("SELECT COUNT(*) as cnt FROM efforts");
    expect(row!.cnt).toBe(0);
  });

  it("should cascade delete phase_history when effort deleted", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");
    await db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    await db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );
    await db.run(
      "INSERT INTO phase_history (effort_id, phase_label) VALUES (1, '0: Setup')"
    );

    await db.run("DELETE FROM tasks WHERE dir_path = 't1'");
    const row = await db.get<{ cnt: number }>("SELECT COUNT(*) as cnt FROM phase_history");
    expect(row!.cnt).toBe(0);
  });

  it("should cascade delete messages when session deleted", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");
    await db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    await db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );
    await db.run("INSERT INTO sessions (task_id, effort_id, pid) VALUES ('t1', 1, 123)");
    await db.run(
      "INSERT INTO messages (session_id, role, content) VALUES (1, 'user', 'hello')"
    );

    await db.run("DELETE FROM tasks WHERE dir_path = 't1'");
    const row = await db.get<{ cnt: number }>("SELECT COUNT(*) as cnt FROM messages");
    expect(row!.cnt).toBe(0);
  });

  // ── Unique constraints ───────────────────────────────────

  it("should enforce UNIQUE(task_id, ordinal) on efforts", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");
    await db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    await db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );

    await expect(
      db.run(
        "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'brainstorm', 1)"
      )
    ).rejects.toThrow();
  });

  it("should enforce UNIQUE(project_id, name) on skills", async () => {
    await db.run("INSERT INTO projects (path) VALUES ('/test')");
    await db.run("INSERT INTO skills (project_id, name) VALUES (1, 'implement')");

    await expect(
      db.run("INSERT INTO skills (project_id, name) VALUES (1, 'implement')")
    ).rejects.toThrow();
  });

  // ── Schema version ──────────────────────────────────────

  it("should set schema version to 8", async () => {
    const row = await db.get<{ userVersion: number }>("PRAGMA user_version");
    expect(row!.userVersion).toBe(SCHEMA_VERSION);
    expect(SCHEMA_VERSION).toBe(8);
  });

  // ── Idempotency ──────────────────────────────────────────

  it("should be idempotent — applying twice does not error", async () => {
    const { applySchema } = await import("../schema.js");
    await expect(applySchema(db)).resolves.not.toThrow();
  });
});
