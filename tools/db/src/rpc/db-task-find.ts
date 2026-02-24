/**
 * db.task.find — Find a single task by dir_path with effort metadata.
 *
 * Returns the task row enriched with effort_count and last_activity
 * from the task_summary view. Returns { task: null } if not found.
 *
 * Callers: bash `engine task find`, session activation (task lookup).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { TaskRow } from "./types.js";

const schema = z.object({
  dirPath: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ task: TaskRow | null }>> {
  const db = ctx.db;
  const task = await db.get<TaskRow>(
    "SELECT * FROM task_summary WHERE dir_path = ?",
    [args.dirPath]
  );

  return { ok: true, data: { task: task ?? null } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.task.find": typeof handler;
  }
}

registerCommand("db.task.find", { schema, handler });
