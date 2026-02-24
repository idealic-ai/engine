/**
 * hooks.sessionEnd — SessionEnd hook RPC.
 * Fires when a Claude session terminates (interrupt or natural end).
 * Ends the session (sets ended_at) and updates agents.status to 'done'.
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
  reason: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ sessionEnded: boolean; agentUpdated: boolean }>> {
  const { engineSessionId } = await resolveEngineIds(args.cwd, ctx);

  if (!engineSessionId) {
    return { ok: true, data: { sessionEnded: false, agentUpdated: false } };
  }

  // 1. Get session to find effortId before ending
  const { session } = await ctx.db.session.get({ id: engineSessionId });

  // 2. End the session
  let sessionEnded = false;
  if (session && !session.endedAt) {
    await ctx.db.session.finish({ sessionId: engineSessionId });
    sessionEnded = true;
  }

  // 3. Find agent via session's effort_id and update status
  let agentUpdated = false;
  if (session) {
    const { agent } = await ctx.db.agents.findByEffort({ effortId: session.effortId });
    if (agent) {
      await ctx.db.agents.updateStatus({ id: agent.id, status: "done" });
      agentUpdated = true;
    }
  }

  return { ok: true, data: { sessionEnded, agentUpdated } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.sessionEnd": typeof handler;
  }
}

registerCommand("hooks.sessionEnd", { schema, handler });
