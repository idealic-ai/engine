/**
 * db.effort.findActive — Find the active effort for a project.
 *
 * Two-tier lookup:
 *   1. Agent mode: if agentId provided, find the effort claimed by that
 *      agent via the agents table join.
 *   2. Fallback: find any active effort for the project (solo/default).
 *
 * Returns the effort row plus the task's dir_path (needed for session context).
 * Returns nulls if no active effort exists.
 *
 * Callers: hooks.sessionStart (effort discovery), resolveEngineIds.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { EffortRow } from "./types.js";

const schema = z.object({
  projectId: z.number(),
  agentId: z.string().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ effort: EffortRow | null; taskDir: string | null }>> {
  const db = ctx.db;

  // Extended row type — includes taskDir from JOIN (auto-transformed from task_dir SQL alias)
  interface EffortWithTaskDir extends EffortRow {
    taskDir: string;
  }

  let row: EffortWithTaskDir | undefined;

  // 1. Agent-specific lookup (if agentId provided)
  if (args.agentId) {
    row = await db.get<EffortWithTaskDir>(
      `SELECT e.*, t.dir_path as task_dir FROM efforts e
       JOIN tasks t ON e.task_id = t.dir_path
       JOIN agents a ON a.effort_id = e.id
       WHERE t.project_id = ? AND e.lifecycle = 'active' AND a.id = ?
       ORDER BY e.id DESC LIMIT 1`,
      [args.projectId, args.agentId]
    );
  }

  // 2. Non-fleet fallback
  if (!row) {
    row = await db.get<EffortWithTaskDir>(
      `SELECT e.*, t.dir_path as task_dir FROM efforts e
       JOIN tasks t ON e.task_id = t.dir_path
       WHERE t.project_id = ? AND e.lifecycle = 'active'
       ORDER BY e.id DESC LIMIT 1`,
      [args.projectId]
    );
  }

  if (!row) {
    return { ok: true, data: { effort: null, taskDir: null } };
  }

  // Extract taskDir and return effort without the extra column
  const { taskDir: td, ...effortFields } = row;
  return { ok: true, data: { effort: effortFields as EffortRow, taskDir: td } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.effort.findActive": typeof handler;
  }
}

registerCommand("db.effort.findActive", { schema, handler });
