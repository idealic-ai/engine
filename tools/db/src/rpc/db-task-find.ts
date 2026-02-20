/**
 * db.task.find — Find a single task by dir_path with effort metadata.
 *
 * Returns the task row enriched with effort_count and last_activity
 * from the task_summary view. Returns { task: null } if not found.
 *
 * Callers: bash `engine task find`, session activation (task lookup).
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  dirPath: z.string(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const result = db.exec(
    "SELECT * FROM task_summary WHERE dir_path = ?",
    [args.dirPath]
  );

  if (result.length === 0 || result[0].values.length === 0) {
    return { ok: true, data: { task: null } };
  }

  const { columns, values } = result[0];
  const task: Record<string, unknown> = {};
  for (let i = 0; i < columns.length; i++) {
    task[columns[i]] = values[0][i];
  }

  return { ok: true, data: { task } };
}

registerCommand("db.task.find", { schema, handler });
