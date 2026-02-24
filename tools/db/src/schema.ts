import type { DbConnection } from "./db-wrapper.js";

/**
 * Schema version — bump when table structure changes.
 * On open, if PRAGMA user_version doesn't match, tables are dropped and recreated.
 */
export const SCHEMA_VERSION = 9;

/**
 * Apply the engine v3 daemon schema to a database.
 * Idempotent — safe to call multiple times.
 *
 * 10 tables:
 *   projects       — engine installation identity
 *   skills         — cached SKILL.md parse (per-project)
 *   tasks          — persistent work containers (keyed by dir_path)
 *   efforts        — skill invocations (FK → tasks, ordinal-based)
 *   sessions       — ephemeral context windows (FK → tasks, efforts)
 *   phase_history  — audit trail (FK → efforts)
 *   messages       — conversation transcripts (FK → sessions)
 *   agents         — fleet agent identity
 *   chunks         — search chunk metadata (content-hash dedup)
 *   embeddings     — search vectors (keyed by content_hash)
 */
export async function applySchema(db: DbConnection): Promise<void> {
  await db.exec("PRAGMA foreign_keys = ON");

  await db.exec(`
    CREATE TABLE IF NOT EXISTS projects (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      path        TEXT NOT NULL UNIQUE,
      name        TEXT,
      created_at  TEXT DEFAULT (datetime('now'))
    )
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS skills (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      project_id      INTEGER NOT NULL REFERENCES projects(id),
      name            TEXT NOT NULL,
      phases          JSONB,
      modes           JSONB,
      templates       JSONB,
      cmd_dependencies JSONB,
      next_skills     JSONB,
      directives      JSONB,
      version         TEXT,
      description     TEXT,
      updated_at      TEXT DEFAULT (datetime('now')),
      UNIQUE(project_id, name)
    )
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS tasks (
      dir_path    TEXT PRIMARY KEY,
      project_id  INTEGER NOT NULL REFERENCES projects(id),
      workspace   TEXT,
      title       TEXT,
      description TEXT,
      keywords    TEXT,
      created_at  TEXT DEFAULT (datetime('now'))
    )
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS efforts (
      id                      INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id                 TEXT NOT NULL REFERENCES tasks(dir_path) ON DELETE CASCADE,
      skill                   TEXT NOT NULL,
      mode                    TEXT,
      ordinal                 INTEGER NOT NULL,
      lifecycle               TEXT NOT NULL DEFAULT 'active',
      current_phase           TEXT,
      discovered_directives   JSONB,
      discovered_directories  JSONB,
      metadata                JSONB,
      created_at              TEXT DEFAULT (datetime('now')),
      finished_at             TEXT,
      UNIQUE(task_id, ordinal)
    )
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS sessions (
      id                      INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id                 TEXT NOT NULL REFERENCES tasks(dir_path) ON DELETE CASCADE,
      effort_id               INTEGER NOT NULL REFERENCES efforts(id),
      prev_session_id         INTEGER REFERENCES sessions(id),
      pid                     INTEGER,
      heartbeat_counter       INTEGER DEFAULT 0,
      heartbeat_interval      INTEGER DEFAULT 10,
      last_heartbeat          TEXT,
      context_usage           REAL,
      loaded_files            JSONB,
      preloaded_files         JSONB,
      pending_injections      JSONB,
      discovered_directives   JSONB,
      discovered_directories  JSONB,
      dehydration_payload     JSONB,
      transcript_path         TEXT,
      transcript_offset       INTEGER DEFAULT 0,
      created_at              TEXT DEFAULT (datetime('now')),
      ended_at                TEXT
    )
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS phase_history (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      effort_id   INTEGER NOT NULL REFERENCES efforts(id) ON DELETE CASCADE,
      phase_label TEXT NOT NULL,
      proof       JSONB,
      created_at  TEXT DEFAULT (datetime('now'))
    )
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS messages (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      role        TEXT NOT NULL,
      content     TEXT NOT NULL,
      tool_name   TEXT,
      timestamp   TEXT DEFAULT (datetime('now'))
    )
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS agents (
      id                TEXT PRIMARY KEY,
      label             TEXT,
      claims            TEXT,
      targeted_claims   TEXT,
      manages           TEXT,
      parent            TEXT,
      effort_id         INTEGER REFERENCES efforts(id),
      status            TEXT
    )
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS chunks (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      source_type    TEXT NOT NULL,
      source_path    TEXT NOT NULL,
      section_title  TEXT NOT NULL,
      chunk_text     TEXT,
      content_hash   TEXT NOT NULL,
      updated_at     TEXT DEFAULT (datetime('now')),
      UNIQUE(source_path, section_title)
    )
  `);

  await db.exec(`
    CREATE TABLE IF NOT EXISTS embeddings (
      content_hash  TEXT PRIMARY KEY,
      embedding     BLOB,
      updated_at    TEXT DEFAULT (datetime('now'))
    )
  `);

  await db.exec(`
    CREATE VIEW IF NOT EXISTS fleet_status AS
      SELECT a.id AS agent, a.label, a.status, e.skill, e.current_phase,
             s.heartbeat_counter, s.context_usage
      FROM agents a
      JOIN efforts e ON a.effort_id = e.id
      JOIN tasks t ON e.task_id = t.dir_path
      LEFT JOIN sessions s ON s.effort_id = e.id AND s.ended_at IS NULL
  `);

  await db.exec(`
    CREATE VIEW IF NOT EXISTS task_summary AS
      SELECT t.*, COUNT(e.id) AS effort_count,
             MAX(e.created_at) AS last_activity
      FROM tasks t LEFT JOIN efforts e ON e.task_id = t.dir_path
      GROUP BY t.dir_path
  `);

  await db.exec(`
    CREATE VIEW IF NOT EXISTS active_efforts AS
      SELECT e.*
      FROM efforts e
      WHERE e.lifecycle = 'active'
  `);

  await db.exec(`
    CREATE VIEW IF NOT EXISTS stale_sessions AS
      SELECT s.*, t.dir_path AS task_dir
      FROM sessions s JOIN tasks t ON s.task_id = t.dir_path
      WHERE s.ended_at IS NULL
        AND s.last_heartbeat < datetime('now', '-5 minutes')
  `);

  await db.exec(
    "CREATE INDEX IF NOT EXISTS idx_efforts_task_lifecycle ON efforts(task_id, lifecycle)"
  );
  await db.exec(
    "CREATE INDEX IF NOT EXISTS idx_sessions_effort_ended ON sessions(effort_id, ended_at)"
  );
  await db.exec(
    "CREATE INDEX IF NOT EXISTS idx_messages_session_ts ON messages(session_id, timestamp)"
  );

  await db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
}
