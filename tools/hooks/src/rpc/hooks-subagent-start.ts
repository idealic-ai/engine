/**
 * hooks.subagentStart — SubagentStart hook RPC.
 * Fires when a Task tool sub-agent spawns.
 * Creates a new session for the sub-agent, linked to the parent's effort.
 *
 * INV_DAEMON_IS_PURE_DB: no filesystem I/O.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import { hookSchema } from "./hook-base-schema.js";
import { resolveEngineIds } from "./resolve-engine-ids.js";

const schema = hookSchema({
  agentId: z.string(),
  agentType: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ sessionId: number | null; effortId: number | null }>> {
  const { effortId, engineSessionId } = await resolveEngineIds(args.cwd, ctx);

  let resolvedEffortId = effortId;
  let taskId: string | null = null;

  // Get parent session info
  if (engineSessionId) {
    const { session } = await ctx.db.session.get({ id: engineSessionId });
    if (session) {
      resolvedEffortId = resolvedEffortId ?? session.effortId;
      taskId = session.taskId;
    }
  }

  if (!resolvedEffortId) {
    return { ok: true, data: { sessionId: null, effortId: null } };
  }

  // Get taskId from effort if not from session
  if (!taskId) {
    const { effort } = await ctx.db.effort.get({ id: resolvedEffortId });
    if (!effort) {
      return { ok: true, data: { sessionId: null, effortId: null } };
    }
    taskId = effort.taskId;
  }

  // Create sub-agent session linked to same effort (uses lastID internally — no MAX(id) race)
  const { session: newSession } = await ctx.db.session.start({
    taskId,
    effortId: resolvedEffortId,
    prevSessionId: engineSessionId ?? undefined,
  });

  return {
    ok: true,
    data: {
      sessionId: newSession.id,
      effortId: resolvedEffortId,
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.subagentStart": typeof handler;
  }
}

registerCommand("hooks.subagentStart", { schema, handler });
