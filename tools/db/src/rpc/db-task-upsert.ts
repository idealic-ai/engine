/**
 * db.task.upsert — Create or update a persistent work container.
 *
 * Tasks are the middle layer of the three-layer model (project → task → effort).
 * Keyed by dir_path (natural key: `sessions/2026_02_20_TOPIC`). Tasks NEVER
 * finish — their active/dormant status is DERIVED from whether any efforts
 * are active, not stored as a lifecycle column.
 *
 * Idempotent: ON CONFLICT updates workspace/title/description only when new
 * values are provided (COALESCE preserves existing on null).
 *
 * Lifecycle position: Called second during `engine effort start`, after project.upsert.
 * The task must exist before efforts or sessions can reference it.
 *
 * Callers: bash `engine effort start` compound flow.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getTaskRow } from "./row-helpers.js";

const schema = z.object({
  dirPath: z.string(),
  projectId: z.number(),
  workspace: z.string().optional(),
  title: z.string().optional(),
  description: z.string().optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  db.exec("BEGIN");
  try {
    db.run(
      `INSERT INTO tasks (dir_path, project_id, workspace, title, description)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(dir_path) DO UPDATE SET
         workspace = COALESCE(excluded.workspace, tasks.workspace),
         title = COALESCE(excluded.title, tasks.title),
         description = COALESCE(excluded.description, tasks.description)`,
      [
        args.dirPath,
        args.projectId,
        args.workspace ?? null,
        args.title ?? null,
        args.description ?? null,
      ]
    );

    const task = getTaskRow(db, args.dirPath);
    db.exec("COMMIT");
    return { ok: true, data: { task } };
  } catch (err: unknown) {
    db.exec("ROLLBACK");
    throw err;
  }
}

registerCommand("db.task.upsert", { schema, handler });
