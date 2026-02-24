/**
 * hooks.stop — Stop hook RPC.
 * Fires when the main Claude Code agent finishes responding (inactivity).
 * Updates agents.status to 'done'. Does NOT end the session.
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
  stopHookActive: z.boolean(),
  lastAssistantMessage: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ agentUpdated: boolean }>> {
  const { effortId } = await resolveEngineIds(args.cwd, ctx);

  if (!effortId) {
    return { ok: true, data: { agentUpdated: false } };
  }

  // Find agent bound to this effort
  const result = await ctx.db.agents.findByEffort({ effortId });
  if (!result.agent) {
    return { ok: true, data: { agentUpdated: false } };
  }
  const agent = result.agent;

  // Update status to 'done' (agent stopped responding)
  await ctx.db.agents.updateStatus({ id: agent.id, status: "done" });

  return { ok: true, data: { agentUpdated: true } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.stop": typeof handler;
  }
}

registerCommand("hooks.stop", { schema, handler });
