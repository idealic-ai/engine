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
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { TaskRow } from "./types.js";

const schema = z.object({
  dirPath: z.string(),
  projectId: z.number(),
  workspace: z.string().optional(),
  title: z.string().optional(),
  description: z.string().optional(),
  keywords: z.string().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ task: TaskRow }>> {
  const db = ctx.db;
    await db.run(
      `INSERT INTO tasks (dir_path, project_id, workspace, title, description, keywords)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(dir_path) DO UPDATE SET
         project_id = excluded.project_id,
         workspace = COALESCE(excluded.workspace, tasks.workspace),
         title = COALESCE(excluded.title, tasks.title),
         description = COALESCE(excluded.description, tasks.description),
         keywords = COALESCE(excluded.keywords, tasks.keywords)`,
      [
        args.dirPath,
        args.projectId,
        args.workspace ?? null,
        args.title ?? null,
        args.description ?? null,
        args.keywords ?? null,
      ]
    );

    const task = await db.get<TaskRow>("SELECT * FROM tasks WHERE dir_path = ?", [args.dirPath]);
    return { ok: true, data: { task: task! } };

}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.task.upsert": typeof handler;
  }
}

registerCommand("db.task.upsert", { schema, handler });
