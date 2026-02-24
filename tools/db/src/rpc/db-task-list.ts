/**
 * db.task.list — List tasks with optional filters.
 *
 * Returns tasks from the task_summary view (includes effort_count and
 * last_activity). Supports filtering by projectId and limiting results.
 * Ordered by most recent activity first.
 *
 * Callers: bash `engine task list`, session search, fleet overview.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { TaskRow } from "./types.js";

const schema = z.object({
  projectId: z.number().optional(),
  limit: z.number().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ tasks: TaskRow[] }>> {
  const db = ctx.db;
  const conditions: string[] = [];
  const params: (string | number)[] = [];

  if (args.projectId !== undefined) {
    conditions.push("project_id = ?");
    params.push(args.projectId);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const limit = args.limit !== undefined ? `LIMIT ?` : "";
  if (args.limit !== undefined) params.push(args.limit);

  const tasks = await db.all<TaskRow>(
    `SELECT * FROM task_summary ${where} ORDER BY last_activity DESC NULLS LAST ${limit}`,
    params
  );

  return { ok: true, data: { tasks } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.task.list": typeof handler;
  }
}

registerCommand("db.task.list", { schema, handler });
