/**
 * db.skills.upsert — Cache a parsed SKILL.md definition in the database.
 *
 * The skills table is a CACHE, not a source of truth. Bash parses SKILL.md
 * from the filesystem and feeds the structured data here. On resume, the
 * skill's current SKILL.md is re-parsed — no stale snapshots.
 *
 * Stores phases, modes, templates, cmd_dependencies, next_skills, and
 * directives as JSONB columns. Per-project namespace (UNIQUE on project_id + name).
 *
 * Why cache in DB: So the daemon can answer "what phases does this skill have?"
 * during effort.phase enforcement without reading the filesystem
 * (INV_DAEMON_IS_PURE_DB — zero FS access).
 *
 * Callers: bash `engine effort start` after parsing SKILL.md from FS.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getSkillRow } from "./row-helpers.js";

const schema = z.object({
  projectId: z.number(),
  name: z.string(),
  phases: z.unknown().optional(),
  modes: z.unknown().optional(),
  templates: z.unknown().optional(),
  cmdDependencies: z.unknown().optional(),
  nextSkills: z.unknown().optional(),
  directives: z.unknown().optional(),
  version: z.string().optional(),
  description: z.string().optional(),
});

type Args = z.infer<typeof schema>;

function toJsonb(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  return JSON.stringify(value);
}

function handler(args: Args, db: Database): RpcResponse {
  db.exec("BEGIN");
  try {
    db.run(
      `INSERT INTO skills (project_id, name, phases, modes, templates, cmd_dependencies, next_skills, directives, version, description, updated_at)
       VALUES (?, ?, jsonb(?), jsonb(?), jsonb(?), jsonb(?), jsonb(?), jsonb(?), ?, ?, datetime('now'))
       ON CONFLICT(project_id, name) DO UPDATE SET
         phases = COALESCE(jsonb(excluded.phases), skills.phases),
         modes = COALESCE(jsonb(excluded.modes), skills.modes),
         templates = COALESCE(jsonb(excluded.templates), skills.templates),
         cmd_dependencies = COALESCE(jsonb(excluded.cmd_dependencies), skills.cmd_dependencies),
         next_skills = COALESCE(jsonb(excluded.next_skills), skills.next_skills),
         directives = COALESCE(jsonb(excluded.directives), skills.directives),
         version = COALESCE(excluded.version, skills.version),
         description = COALESCE(excluded.description, skills.description),
         updated_at = datetime('now')`,
      [
        args.projectId,
        args.name,
        toJsonb(args.phases),
        toJsonb(args.modes),
        toJsonb(args.templates),
        toJsonb(args.cmdDependencies),
        toJsonb(args.nextSkills),
        toJsonb(args.directives),
        args.version ?? null,
        args.description ?? null,
      ]
    );

    const skill = getSkillRow(db, args.projectId, args.name);
    db.exec("COMMIT");
    return { ok: true, data: { skill } };
  } catch (err: unknown) {
    db.exec("ROLLBACK");
    throw err;
  }
}

registerCommand("db.skills.upsert", { schema, handler });
