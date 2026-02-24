/**
 * hooks.postToolUseFailure — PostToolUseFailure hook RPC.
 * Fires after a tool execution fails or is interrupted.
 * Updates agents.status to 'error' and logs failure to messages table.
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
  toolUseId: z.string(),
  error: z.string(),
  isInterrupt: z.boolean().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ agentUpdated: boolean; messageLogged: boolean }>> {
  const { effortId, engineSessionId } = await resolveEngineIds(args.cwd, ctx);

  let agentUpdated = false;
  let messageLogged = false;

  // 1. Update agent status to 'error'
  if (effortId) {
    const { agent } = await ctx.db.agents.findByEffort({ effortId });
    if (agent) {
      await ctx.db.agents.updateStatus({ id: agent.id, status: "error" });
      agentUpdated = true;
    }
  }

  // 2. Log failure to messages table
  if (engineSessionId) {
    try {
      await ctx.db.messages.append({
        sessionId: engineSessionId,
        role: "system",
        content: JSON.stringify({ event: "tool_use_failure", toolName: args.toolName ?? null, error: args.error ?? null }),
        toolName: args.toolName,
      });
      messageLogged = true;
    } catch (err) {
      // Fail-open — session FK may not exist, but log so failures are visible
      console.error(`[hooks.postToolUseFailure] message insert failed for session ${engineSessionId}:`, err);
    }
  }

  return { ok: true, data: { agentUpdated, messageLogged } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.postToolUseFailure": typeof handler;
  }
}

registerCommand("hooks.postToolUseFailure", { schema, handler });
