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
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { EffortRow } from "./types.js";

const schema = z.object({
  effortId: z.number(),
  keywords: z.string().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ effort: EffortRow }>> {
  const db = ctx.db;
  const effort = await db.get<EffortRow>("SELECT * FROM efforts WHERE id = ?", [args.effortId]);
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

    await db.run(
      `UPDATE efforts SET lifecycle = 'finished', finished_at = datetime('now')
       WHERE id = ?`,
      [args.effortId]
    );

    // Propagate keywords to task if provided
    if (args.keywords) {
      await db.run(
        "UPDATE tasks SET keywords = ? WHERE dir_path = ?",
        [args.keywords, effort.taskId]
      );
    }

    const updated = await db.get<EffortRow>("SELECT * FROM efforts WHERE id = ?", [args.effortId]);
    return { ok: true, data: { effort: updated! } };

}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.effort.finish": typeof handler;
  }
}

registerCommand("db.effort.finish", { schema, handler });
