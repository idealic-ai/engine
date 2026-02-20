/**
 * db.skills.find — Search cached skill definitions by name substring.
 *
 * Uses SQL LIKE for case-insensitive substring matching on the name column.
 * Returns full skill rows with JSONB columns deserialized.
 *
 * Callers: bash `engine skills find`, daemon-side skill discovery.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  projectId: z.number(),
  query: z.string(),
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
     FROM skills WHERE project_id = ? AND name LIKE ? ORDER BY name`,
    [args.projectId, `%${args.query}%`]
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

registerCommand("db.skills.find", { schema, handler });
