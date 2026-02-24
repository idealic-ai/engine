/**
 * db.agents.updateStatus — Update an agent's visual status.
 *
 * Valid statuses: working, idle, attention, error, done.
 * Guards: NOT_FOUND if agent doesn't exist.
 *
 * Callers: hook RPCs (stop, sessionEnd, postToolUseFailure, permissionRequest).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { AgentRow } from "./types.js";

const VALID_STATUSES = ["working", "idle", "attention", "error", "done"] as const;

const schema = z.object({
  id: z.string(),
  status: z.enum(VALID_STATUSES),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ agent: AgentRow }>> {
  const db = ctx.db;

  // Guard: agent must exist
  const existing = await db.get<AgentRow>("SELECT * FROM agents WHERE id = ?", [args.id]);
  if (!existing) {
    return { ok: false, error: "NOT_FOUND", message: `Agent '${args.id}' not found` };
  }

  await db.run("UPDATE agents SET status = ? WHERE id = ?", [args.status, args.id]);

  const agent = await db.get<AgentRow>("SELECT * FROM agents WHERE id = ?", [args.id]);
  return { ok: true, data: { agent: agent! } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.agents.updateStatus": typeof handler;
  }
}

registerCommand("db.agents.updateStatus", { schema, handler });
