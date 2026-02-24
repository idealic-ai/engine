/**
 * db.session.get — Fetch a single session by ID.
 *
 * Returns the full SessionRow or null if not found. Simple primary-key lookup
 * used by hooks that need session state (heartbeat counter, context usage).
 *
 * Callers: hooks.preToolUse, hooks.postToolUse, commands.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SessionRow } from "./types.js";

const schema = z.object({
  id: z.number(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ session: SessionRow | null }>> {
  const db = ctx.db;
  const session = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.id]);
  return { ok: true, data: { session: session ?? null } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.get": typeof handler;
  }
}

registerCommand("db.session.get", { schema, handler });
