/**
 * db.effort.start — Create a new skill invocation on a task.
 *
 * Efforts are the core v3 entity: each `/brainstorm`, `/implement`, or `/fix`
 * invocation creates one. Multiple efforts per task allowed, including repeated
 * skills (brainstorm → implement → brainstorm again).
 *
 * Ordinal assignment is atomic: MAX(ordinal WHERE task_id) + 1, serialized by
 * the single-threaded daemon (INV_DAEMON_IS_THE_LOCK). The ordinal drives
 * artifact naming: `{ordinal}_{SKILL}_LOG.md`, `{ordinal}_{SKILL}_PLAN.md`.
 *
 * Lifecycle: starts as 'active'. Transitions to 'finished' via effort.finish.
 * Binary only — no intermediate states.
 *
 * Metadata: stores taskSummary, scope, directoriesOfInterest, and other session
 * parameters as a JSONB blob. Fallback source for phases if skills table is empty.
 *
 * Callers: bash `engine effort start` compound flow, after project + task upsert.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getEffortRow, getLastInsertId } from "./row-helpers.js";

const schema = z.object({
  taskId: z.string(),
  skill: z.string(),
  mode: z.string().optional(),
  metadata: z.record(z.string(), z.unknown()).optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  db.exec("BEGIN");
  try {
    // Compute next ordinal atomically
    const ordResult = db.exec(
      "SELECT COALESCE(MAX(ordinal), 0) + 1 AS next_ord FROM efforts WHERE task_id = ?",
      [args.taskId]
    );
    const nextOrdinal = ordResult[0].values[0][0] as number;

    const metadataJson = args.metadata
      ? JSON.stringify(args.metadata)
      : null;

    db.run(
      `INSERT INTO efforts (task_id, skill, mode, ordinal, metadata)
       VALUES (?, ?, ?, ?, jsonb(?))`,
      [
        args.taskId,
        args.skill,
        args.mode ?? null,
        nextOrdinal,
        metadataJson,
      ]
    );

    const effortId = getLastInsertId(db);
    const effort = getEffortRow(db, effortId);

    db.exec("COMMIT");
    return { ok: true, data: { effort } };
  } catch (err: unknown) {
    db.exec("ROLLBACK");
    throw err;
  }
}

registerCommand("db.effort.start", { schema, handler });
