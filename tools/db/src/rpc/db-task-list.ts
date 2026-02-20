/**
 * db.task.list — List tasks with optional filters.
 *
 * Returns tasks from the task_summary view (includes effort_count and
 * last_activity). Supports filtering by projectId and limiting results.
 * Ordered by most recent activity first.
 *
 * Callers: bash `engine task list`, session search, fleet overview.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  projectId: z.number().optional(),
  limit: z.number().optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const conditions: string[] = [];
  const params: (string | number)[] = [];

  if (args.projectId !== undefined) {
    conditions.push("project_id = ?");
    params.push(args.projectId);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const limit = args.limit !== undefined ? `LIMIT ?` : "";
  if (args.limit !== undefined) params.push(args.limit);

  const result = db.exec(
    `SELECT * FROM task_summary ${where} ORDER BY last_activity DESC NULLS LAST ${limit}`,
    params
  );

  if (result.length === 0) {
    return { ok: true, data: { tasks: [] } };
  }

  const { columns, values } = result[0];
  const tasks = values.map((row) => {
    const obj: Record<string, unknown> = {};
    for (let i = 0; i < columns.length; i++) {
      obj[columns[i]] = row[i];
    }
    return obj;
  });

  return { ok: true, data: { tasks } };
}

registerCommand("db.task.list", { schema, handler });
