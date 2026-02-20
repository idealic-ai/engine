import { describe, it, expect, beforeEach, afterEach } from "vitest";
import initSqlJs, { type Database } from "sql.js";
import { applySchema, SCHEMA_VERSION } from "../schema.js";

let db: Database;

beforeEach(async () => {
  const SQL = await initSqlJs();
  db = new SQL.Database();
});

afterEach(() => {
  db.close();
});

describe("applySchema v3", () => {
  // ── Table existence ──────────────────────────────────────

  it("should create all 9 tables", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    );
    const tables = result[0].values.map((r) => r[0]);

    expect(tables).toContain("projects");
    expect(tables).toContain("skills");
    expect(tables).toContain("tasks");
    expect(tables).toContain("efforts");
    expect(tables).toContain("sessions");
    expect(tables).toContain("phase_history");
    expect(tables).toContain("messages");
    expect(tables).toContain("agents");
    expect(tables).toContain("embeddings");
  });

  // ── Projects table ───────────────────────────────────────

  it("should create projects table with correct columns", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='projects'"
    );
    const sql = result[0].values[0][0] as string;

    expect(sql).toContain("id");
    expect(sql).toContain("path");
    expect(sql).toContain("UNIQUE");
    expect(sql).toContain("name");
  });

  // ── Skills table ─────────────────────────────────────────

  it("should create skills table with JSONB columns", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='skills'"
    );
    const sql = result[0].values[0][0] as string;

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

  it("should create tasks table without lifecycle column", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='tasks'"
    );
    const sql = result[0].values[0][0] as string;

    expect(sql).toContain("dir_path    TEXT PRIMARY KEY");
    expect(sql).toContain("project_id");
    expect(sql).toContain("REFERENCES projects(id)");
    expect(sql).toContain("workspace");
    expect(sql).toContain("keywords");
    // v3: NO lifecycle column on tasks (derived from efforts)
    expect(sql).not.toContain("lifecycle");
  });

  // ── Efforts table ────────────────────────────────────────

  it("should create efforts table with ordinal and lifecycle", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='efforts'"
    );
    const sql = result[0].values[0][0] as string;

    expect(sql).toContain("task_id");
    expect(sql).toContain("REFERENCES tasks(dir_path)");
    expect(sql).toContain("skill");
    expect(sql).toContain("ordinal");
    expect(sql).toContain("lifecycle");
    expect(sql).toContain("current_phase");
    expect(sql).toContain("UNIQUE(task_id, ordinal)");
  });

  // ── Sessions table ───────────────────────────────────────

  it("should create sessions table with effort_id NOT NULL", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'"
    );
    const sql = result[0].values[0][0] as string;

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

  it("should create phase_history with FK to efforts (not tasks)", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='phase_history'"
    );
    const sql = result[0].values[0][0] as string;

    expect(sql).toContain("effort_id");
    expect(sql).toContain("REFERENCES efforts(id)");
    // v3: FK to efforts, NOT tasks
    expect(sql).not.toContain("task_id");
  });

  // ── Messages table ───────────────────────────────────────

  it("should create messages table with FK to sessions", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='messages'"
    );
    const sql = result[0].values[0][0] as string;

    expect(sql).toContain("session_id");
    expect(sql).toContain("REFERENCES sessions(id)");
    expect(sql).toContain("role");
    expect(sql).toContain("content");
    expect(sql).toContain("tool_name");
  });

  // ── Agents table ─────────────────────────────────────────

  it("should create agents table with effort_id FK", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='agents'"
    );
    const sql = result[0].values[0][0] as string;

    expect(sql).toContain("id          TEXT PRIMARY KEY");
    expect(sql).toContain("effort_id");
    expect(sql).toContain("REFERENCES efforts(id)");
  });

  // ── Embeddings table ─────────────────────────────────────

  it("should create embeddings table", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='embeddings'"
    );
    const sql = result[0].values[0][0] as string;

    expect(sql).toContain("source_type");
    expect(sql).toContain("source_path");
    expect(sql).toContain("embedding");
  });

  // ── Views ────────────────────────────────────────────────

  it("should create fleet_status view", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='view' AND name='fleet_status'"
    );
    expect(result).toHaveLength(1);
  });

  it("should create task_summary view", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT sql FROM sqlite_master WHERE type='view' AND name='task_summary'"
    );
    expect(result).toHaveLength(1);
  });

  it("should create active_efforts view", () => {
    applySchema(db);

    // Insert test data
    db.run("INSERT INTO projects (path) VALUES ('/test')");
    db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    db.run(
      "INSERT INTO efforts (task_id, skill, ordinal, lifecycle) VALUES ('t1', 'implement', 1, 'active')"
    );
    db.run(
      "INSERT INTO efforts (task_id, skill, ordinal, lifecycle) VALUES ('t1', 'brainstorm', 2, 'finished')"
    );

    const result = db.exec("SELECT skill FROM active_efforts");
    expect(result).toHaveLength(1);
    expect(result[0].values).toHaveLength(1);
    expect(result[0].values[0][0]).toBe("implement");
  });

  it("should create stale_sessions view", () => {
    applySchema(db);

    db.run("INSERT INTO projects (path) VALUES ('/test')");
    db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );

    // Recent heartbeat — NOT stale
    db.run(
      "INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat) VALUES ('t1', 1, 1234, datetime('now'))"
    );
    // Old heartbeat — stale
    db.run(
      "INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat) VALUES ('t1', 1, 5678, datetime('now', '-10 minutes'))"
    );
    // Ended — NOT stale
    db.run(
      "INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat, ended_at) VALUES ('t1', 1, 9999, datetime('now', '-10 minutes'), datetime('now'))"
    );

    const result = db.exec("SELECT pid FROM stale_sessions");
    expect(result).toHaveLength(1);
    expect(result[0].values).toHaveLength(1);
    expect(result[0].values[0][0]).toBe(5678);
  });

  // ── Indexes ──────────────────────────────────────────────

  it("should create compound indexes", () => {
    applySchema(db);

    const result = db.exec(
      "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%' ORDER BY name"
    );
    const indexes = result[0].values.map((r) => r[0]);

    expect(indexes).toContain("idx_efforts_task_lifecycle");
    expect(indexes).toContain("idx_sessions_effort_ended");
    expect(indexes).toContain("idx_messages_session_ts");
  });

  // ── JSONB support ────────────────────────────────────────

  it("should support JSONB columns for round-trip storage", () => {
    applySchema(db);

    db.run("INSERT INTO projects (path) VALUES ('/test')");

    const phases = JSON.stringify([
      { label: "0", name: "Setup" },
      { label: "1", name: "Interrogation" },
    ]);
    db.run(
      "INSERT INTO skills (project_id, name, phases) VALUES (1, 'implement', jsonb(?))",
      [phases]
    );

    // Read back as JSON text
    const result = db.exec(
      "SELECT json(phases) FROM skills WHERE name = 'implement'"
    );
    expect(result).toHaveLength(1);
    const parsed = JSON.parse(result[0].values[0][0] as string);
    expect(parsed).toHaveLength(2);
    expect(parsed[0].name).toBe("Setup");
  });

  it("should support json_extract on JSONB columns", () => {
    applySchema(db);

    db.run("INSERT INTO projects (path) VALUES ('/test')");
    db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    db.run(
      "INSERT INTO efforts (task_id, skill, ordinal, metadata) VALUES ('t1', 'impl', 1, jsonb(?))",
      [JSON.stringify({ taskSummary: "test task", scope: "code changes" })]
    );

    const result = db.exec(
      "SELECT json_extract(metadata, '$.taskSummary') FROM efforts WHERE task_id = 't1'"
    );
    expect(result[0].values[0][0]).toBe("test task");
  });

  // ── FK enforcement ───────────────────────────────────────

  it("should enforce FK: task requires project", () => {
    applySchema(db);

    expect(() =>
      db.run(
        "INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 999)"
      )
    ).toThrow();
  });

  it("should enforce FK: effort requires task", () => {
    applySchema(db);

    expect(() =>
      db.run(
        "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('nonexistent', 'impl', 1)"
      )
    ).toThrow();
  });

  it("should enforce FK: session requires effort", () => {
    applySchema(db);

    db.run("INSERT INTO projects (path) VALUES ('/test')");
    db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");

    expect(() =>
      db.run(
        "INSERT INTO sessions (task_id, effort_id) VALUES ('t1', 999)"
      )
    ).toThrow();
  });

  // ── CASCADE deletes ──────────────────────────────────────

  it("should cascade delete efforts when task deleted", () => {
    applySchema(db);

    db.run("INSERT INTO projects (path) VALUES ('/test')");
    db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );

    db.run("DELETE FROM tasks WHERE dir_path = 't1'");
    const result = db.exec("SELECT COUNT(*) FROM efforts");
    expect(result[0].values[0][0]).toBe(0);
  });

  it("should cascade delete phase_history when effort deleted", () => {
    applySchema(db);

    db.run("INSERT INTO projects (path) VALUES ('/test')");
    db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );
    db.run(
      "INSERT INTO phase_history (effort_id, phase_label) VALUES (1, '0: Setup')"
    );

    db.run("DELETE FROM tasks WHERE dir_path = 't1'");
    const result = db.exec("SELECT COUNT(*) FROM phase_history");
    expect(result[0].values[0][0]).toBe(0);
  });

  it("should cascade delete messages when session deleted", () => {
    applySchema(db);

    db.run("INSERT INTO projects (path) VALUES ('/test')");
    db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );
    db.run("INSERT INTO sessions (task_id, effort_id, pid) VALUES ('t1', 1, 123)");
    db.run(
      "INSERT INTO messages (session_id, role, content) VALUES (1, 'user', 'hello')"
    );

    db.run("DELETE FROM tasks WHERE dir_path = 't1'");
    const result = db.exec("SELECT COUNT(*) FROM messages");
    expect(result[0].values[0][0]).toBe(0);
  });

  // ── Unique constraints ───────────────────────────────────

  it("should enforce UNIQUE(task_id, ordinal) on efforts", () => {
    applySchema(db);

    db.run("INSERT INTO projects (path) VALUES ('/test')");
    db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('t1', 1)");
    db.run(
      "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'impl', 1)"
    );

    expect(() =>
      db.run(
        "INSERT INTO efforts (task_id, skill, ordinal) VALUES ('t1', 'brainstorm', 1)"
      )
    ).toThrow();
  });

  it("should enforce UNIQUE(project_id, name) on skills", () => {
    applySchema(db);

    db.run("INSERT INTO projects (path) VALUES ('/test')");
    db.run("INSERT INTO skills (project_id, name) VALUES (1, 'implement')");

    expect(() =>
      db.run("INSERT INTO skills (project_id, name) VALUES (1, 'implement')")
    ).toThrow();
  });

  // ── Schema version ──────────────────────────────────────

  it("should set schema version to 4", () => {
    applySchema(db);

    const result = db.exec("PRAGMA user_version");
    expect(result[0].values[0][0]).toBe(SCHEMA_VERSION);
    expect(SCHEMA_VERSION).toBe(4);
  });

  // ── Idempotency ──────────────────────────────────────────

  it("should be idempotent — applying twice does not error", () => {
    applySchema(db);
    expect(() => applySchema(db)).not.toThrow();
  });
});
