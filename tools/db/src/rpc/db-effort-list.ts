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
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { EffortRow } from "./types.js";

const schema = z.object({
  taskId: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ efforts: EffortRow[] }>> {
  const db = ctx.db;
  const efforts = await db.all<EffortRow>(
    "SELECT * FROM efforts WHERE task_id = ? ORDER BY ordinal",
    [args.taskId]
  );
  return { ok: true, data: { efforts } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.effort.list": typeof handler;
  }
}

registerCommand("db.effort.list", { schema, handler });
