/**
 * hooks.subagentStop — SubagentStop hook RPC.
 * Fires when a Task tool sub-agent completes.
 * Ends the sub-agent's session.
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
  agentId: z.string(),
  agentType: z.string(),
  agentTranscriptPath: z.string(),
  lastAssistantMessage: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ sessionEnded: boolean }>> {
  const { engineSessionId } = await resolveEngineIds(args.cwd, ctx);

  if (!engineSessionId) {
    return { ok: true, data: { sessionEnded: false } };
  }

  const { session } = await ctx.db.session.get({ id: engineSessionId });

  if (!session || session.endedAt) {
    return { ok: true, data: { sessionEnded: false } };
  }

  await ctx.db.session.finish({ sessionId: engineSessionId });

  return { ok: true, data: { sessionEnded: true } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.subagentStop": typeof handler;
  }
}

registerCommand("hooks.subagentStop", { schema, handler });
