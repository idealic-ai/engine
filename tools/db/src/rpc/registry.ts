/**
 * RPC Command Registry — side-effect barrel file.
 *
 * Importing this module registers all RPC handlers into the dispatch map.
 * Each import below triggers a top-level `registerCommand()` call in the
 * imported file. Order doesn't matter — registration is idempotent.
 *
 * Entry point: daemon.ts imports this once at startup.
 * Adding a new RPC: create the handler file, add an import line here.
 *
 * Namespaces (v3 three-layer model):
 *   db.project.*  — engine installation identity
 *   db.task.*     — persistent work containers
 *   db.skills.*   — cached SKILL.md parse
 *   db.effort.*   — skill invocations (the core v3 entity)
 *   db.session.*  — ephemeral context windows
 */

// v3 RPCs — project, task, skills, effort, session namespaces
import "./db-project-upsert.js";
import "./db-task-upsert.js";
import "./db-skills-upsert.js";
import "./db-skills-get.js";
import "./db-effort-start.js";
import "./db-effort-finish.js";
import "./db-effort-phase.js";
import "./db-effort-list.js";
import "./db-session-start.js";
import "./db-session-finish.js";
import "./db-session-heartbeat.js";
import "./db-session-update-context.js";
import "./db-session-update-files.js";
import "./db-session-find.js";
