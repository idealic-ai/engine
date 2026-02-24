/**
 * db.session.updateContextUsage — Track context window fill level.
 *
 * Updates the context_usage float (0.0 = empty, 1.0 = full). Pushed by the
 * status line at regular intervals, giving real-time visibility into how close
 * an agent is to context overflow.
 *
 * Consumers:
 *   - fleet_status view: includes context_usage for fleet dashboard
 *   - Overflow hook: uses this to trigger dehydration at threshold
 *
 * Callers: status line (periodic push), overflow detection hook.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SessionRow } from "./types.js";

const schema = z.object({
  sessionId: z.number(),
  usage: z.number(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ session: SessionRow }>> {
  const db = ctx.db;
  const session = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }

  await db.run("UPDATE sessions SET context_usage = ? WHERE id = ?", [args.usage, args.sessionId]);
  const updated = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  return { ok: true, data: { session: updated! } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.updateContextUsage": typeof handler;
  }
}

registerCommand("db.session.updateContextUsage", { schema, handler });
