/**
 * db.session.find — Find the active (non-ended) session for an effort.
 *
 * Returns the most recent session where ended_at IS NULL for the given effort.
 * Returns { session: null } if no active session exists (effort may be between
 * context windows, or already finished).
 *
 * Used internally by effort.phase to reset the heartbeat counter on phase
 * transitions. Also available for external queries about session liveness.
 *
 * Callers: effort.phase (heartbeat reset), bash compound commands (session lookup).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SessionRow } from "./types.js";

const schema = z.object({
  effortId: z.number(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ session: SessionRow | null }>> {
  const db = ctx.db;
  const session = await db.get<SessionRow>(
    "SELECT * FROM sessions WHERE effort_id = ? AND ended_at IS NULL ORDER BY id DESC LIMIT 1",
    [args.effortId]
  );
  return { ok: true, data: { session: session ?? null } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.find": typeof handler;
  }
}

registerCommand("db.session.find", { schema, handler });
