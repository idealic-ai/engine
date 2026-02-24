/**
 * db.agents.list — List all registered fleet agents.
 *
 * Returns all agent rows. No filtering — the agents table is small
 * (typically <10 entries for a fleet).
 *
 * Callers: fleet.sh status, coordinator overview, dispatch-daemon.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { AgentRow } from "./types.js";

const schema = z.object({});

type Args = z.infer<typeof schema>;

async function handler(_args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ agents: AgentRow[] }>> {
  const db = ctx.db;
  const agents = await db.all<AgentRow>("SELECT * FROM agents ORDER BY id");
  return { ok: true, data: { agents } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.agents.list": typeof handler;
  }
}

registerCommand("db.agents.list", { schema, handler });
