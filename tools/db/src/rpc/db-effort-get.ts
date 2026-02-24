/**
 * db.effort.get — Fetch a single effort by ID.
 *
 * Returns the full EffortRow or null if not found. Simple primary-key lookup
 * used by hooks and commands that need effort state (lifecycle, phase, metadata).
 *
 * Callers: hooks.preToolUse, hooks.postToolUse, hooks.userPrompt, commands.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { EffortRow } from "./types.js";

const schema = z.object({
  id: z.number(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ effort: EffortRow | null }>> {
  const db = ctx.db;
  const effort = await db.get<EffortRow>("SELECT * FROM efforts WHERE id = ?", [args.id]);
  return { ok: true, data: { effort: effort ?? null } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.effort.get": typeof handler;
  }
}

registerCommand("db.effort.get", { schema, handler });
