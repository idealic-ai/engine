/**
 * db.effort.list — List all efforts for a task, ordered by ordinal.
 *
 * Returns the full history of skill invocations on a task. Used for
 * cross-effort discovery: when a new effort starts, the bash compound
 * command queries prior efforts to find their debrief files and include
 * them as context for the new skill invocation.
 *
 * Ordering by ordinal preserves chronological sequence (brainstorm #1,
 * implement #2, brainstorm #3, etc.).
 *
 * Callers: bash `engine effort start` (cross-effort context discovery).
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getEffortRows } from "./row-helpers.js";

const schema = z.object({
  taskId: z.string(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const efforts = getEffortRows(db, args.taskId);
  return { ok: true, data: { efforts } };
}

registerCommand("db.effort.list", { schema, handler });
