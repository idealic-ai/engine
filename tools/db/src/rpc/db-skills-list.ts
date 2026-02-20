/**
 * db.skills.list — List all cached skill definitions for a project.
 *
 * Returns the full skill rows with JSONB columns deserialized to JS objects.
 * Used by bash compound commands for skill discovery and fleet coordination.
 *
 * Callers: bash `engine skills list`, fleet coordinator (skill availability).
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  projectId: z.number(),
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
  const jsonSelects = JSONB_COLUMNS.map(
    (col) => `json(${col}) as ${col}`
  ).join(", ");

  const result = db.exec(
    `SELECT id, project_id, name, ${jsonSelects}, version, description, updated_at
     FROM skills WHERE project_id = ? ORDER BY name`,
    [args.projectId]
  );

  if (result.length === 0) {
    return { ok: true, data: { skills: [] } };
  }

  const { columns, values } = result[0];
  const skills = values.map((row) => {
    const obj: Record<string, unknown> = {};
    for (let i = 0; i < columns.length; i++) {
      const col = columns[i];
      const val = row[i];
      if (JSONB_COLUMNS.includes(col) && typeof val === "string") {
        obj[col] = JSON.parse(val);
      } else {
        obj[col] = val;
      }
    }
    return obj;
  });

  return { ok: true, data: { skills } };
}

registerCommand("db.skills.list", { schema, handler });
