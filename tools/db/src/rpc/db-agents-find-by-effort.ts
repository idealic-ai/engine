/**
 * db.agents.findByEffort — Find the agent bound to an effort.
 *
 * Returns null (not an error) when no agent is found — callers use this
 * for fail-open patterns where a missing agent is expected.
 *
 * Callers: hook RPCs (stop, sessionEnd, postToolUseFailure, permissionRequest).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { AgentRow } from "./types.js";

const schema = z.object({
  effortId: z.number(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ agent: AgentRow | null }>> {
  const agent = await ctx.db.get<AgentRow>(
    "SELECT * FROM agents WHERE effort_id = ?",
    [args.effortId]
  );

  return { ok: true, data: { agent: agent ?? null } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.agents.findByEffort": typeof handler;
  }
}

registerCommand("db.agents.findByEffort", { schema, handler });
