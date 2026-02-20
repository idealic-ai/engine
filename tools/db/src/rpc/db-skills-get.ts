/**
 * db.skills.get — Retrieve a cached skill definition by project and name.
 *
 * Returns the full skill row with JSONB columns (phases, modes, templates, etc.)
 * deserialized to JS objects. Returns { skill: null } if not found.
 *
 * The JSONB→JSON conversion is necessary because sql.js stores JSONB as binary
 * internally — we use `json(column)` in the SELECT to get readable text, then
 * JSON.parse to get JS objects.
 *
 * Primary consumer: db.effort.phase reads phases from this table to enforce
 * sequential phase progression without touching the filesystem.
 *
 * Callers: effort.phase (phase enforcement), bash compound commands (skill lookup).
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  projectId: z.number(),
  name: z.string(),
});

type Args = z.infer<typeof schema>;

const JSONB_COLUMNS = [
  "phases",
  "modes",
  "templates",
  "cmd_dependencies",
  "next_skills",
  "directives",
];

function handler(args: Args, db: Database): RpcResponse {
  // Use json() to convert JSONB columns to readable JSON text
  const jsonSelects = JSONB_COLUMNS.map(
    (col) => `json(${col}) as ${col}`
  ).join(", ");

  const result = db.exec(
    `SELECT id, project_id, name, ${jsonSelects}, updated_at
     FROM skills WHERE project_id = ? AND name = ?`,
    [args.projectId, args.name]
  );

  if (result.length === 0 || result[0].values.length === 0) {
    return { ok: true, data: { skill: null } };
  }

  const { columns, values } = result[0];
  const skill: Record<string, unknown> = {};
  for (let i = 0; i < columns.length; i++) {
    const col = columns[i];
    const val = values[0][i];
    // Parse JSONB columns into JS objects
    if (JSONB_COLUMNS.includes(col) && typeof val === "string") {
      skill[col] = JSON.parse(val);
    } else {
      skill[col] = val;
    }
  }

  return { ok: true, data: { skill } };
}

registerCommand("db.skills.get", { schema, handler });
