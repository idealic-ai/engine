/**
 * hooks.permissionRequest — PermissionRequest hook RPC.
 * Fires when Claude requests tool permission.
 * Updates agents.status to 'attention'.
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
  toolName: z.string(),
  toolInput: z.record(z.string(), z.unknown()),
  permissionSuggestions: z.array(z.unknown()).optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ agentUpdated: boolean }>> {
  const { effortId } = await resolveEngineIds(args.cwd, ctx);

  if (!effortId) {
    return { ok: true, data: { agentUpdated: false } };
  }

  const { agent } = await ctx.db.agents.findByEffort({ effortId });
  if (!agent) {
    return { ok: true, data: { agentUpdated: false } };
  }

  await ctx.db.agents.updateStatus({ id: agent.id, status: "attention" });

  return { ok: true, data: { agentUpdated: true } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.permissionRequest": typeof handler;
  }
}

registerCommand("hooks.permissionRequest", { schema, handler });
