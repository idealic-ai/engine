/**
 * db.agents.get — Retrieve a fleet agent by id.
 *
 * Returns the full agent row or { agent: null } if not found.
 *
 * Callers: fleet coordination, session activation (agent lookup).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { AgentRow } from "./types.js";

const schema = z.object({
  id: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ agent: AgentRow | null }>> {
  const db = ctx.db;
  const agent = await db.get<AgentRow>("SELECT * FROM agents WHERE id = ?", [args.id]);
  return { ok: true, data: { agent: agent ?? null } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.agents.get": typeof handler;
  }
}

registerCommand("db.agents.get", { schema, handler });
