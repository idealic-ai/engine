/**
 * db.effort.finish — Mark a skill invocation as complete.
 *
 * Sets lifecycle='finished' and records finished_at timestamp. Once finished,
 * an effort cannot be restarted — start a new effort instead.
 *
 * Keyword propagation: optionally updates the parent task's keywords field,
 * enabling search indexing. Keywords are comma-separated tags that accumulate
 * across efforts (each effort can add to the task's keyword set).
 *
 * Guards: returns NOT_FOUND if effort doesn't exist, ALREADY_FINISHED if
 * the effort was already completed (idempotency safety).
 *
 * Callers: bash `engine session idle`/`deactivate` during synthesis close.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getEffortRow } from "./row-helpers.js";

const schema = z.object({
  effortId: z.number(),
  keywords: z.string().optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const effort = getEffortRow(db, args.effortId);
  if (!effort) {
    return {
      ok: false,
      error: "NOT_FOUND",
      message: `Effort ${args.effortId} not found`,
    };
  }

  if (effort.lifecycle === "finished") {
    return {
      ok: false,
      error: "ALREADY_FINISHED",
      message: `Effort ${args.effortId} is already finished`,
    };
  }

  db.exec("BEGIN");
  try {
    db.run(
      `UPDATE efforts SET lifecycle = 'finished', finished_at = datetime('now')
       WHERE id = ?`,
      [args.effortId]
    );

    // Propagate keywords to task if provided
    if (args.keywords) {
      db.run(
        "UPDATE tasks SET keywords = ? WHERE dir_path = ?",
        [args.keywords, effort.task_id as string]
      );
    }

    const updated = getEffortRow(db, args.effortId);
    db.exec("COMMIT");
    return { ok: true, data: { effort: updated } };
  } catch (err: unknown) {
    db.exec("ROLLBACK");
    throw err;
  }
}

registerCommand("db.effort.finish", { schema, handler });
