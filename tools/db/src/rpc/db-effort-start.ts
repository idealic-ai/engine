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
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { EffortRow } from "./types.js";

const schema = z.object({
  taskId: z.string(),
  skill: z.string(),
  mode: z.string().optional(),
  metadata: z.record(z.string(), z.unknown()).optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ effort: EffortRow }>> {
  const db = ctx.db;
    // Compute next ordinal atomically
    const ordRow = await db.get<{ nextOrd: number }>(
      "SELECT COALESCE(MAX(ordinal), 0) + 1 AS next_ord FROM efforts WHERE task_id = ?",
      [args.taskId]
    );
    const nextOrdinal = ordRow?.nextOrd ?? 1;

    const metadataJson = args.metadata
      ? JSON.stringify(args.metadata)
      : null;

    const { lastID } = await db.run(
      `INSERT INTO efforts (task_id, skill, mode, ordinal, metadata)
       VALUES (?, ?, ?, ?, json(?))`,
      [
        args.taskId,
        args.skill,
        args.mode ?? null,
        nextOrdinal,
        metadataJson,
      ]
    );

    const effort = await db.get<EffortRow>("SELECT * FROM efforts WHERE id = ?", [lastID]);

    return { ok: true, data: { effort: effort! } };

}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.effort.start": typeof handler;
  }
}

registerCommand("db.effort.start", { schema, handler });
