/**
 * db.session.heartbeat — Liveness signal from an active agent.
 *
 * Increments heartbeat_counter and updates last_heartbeat timestamp.
 * Called by the PreToolUse hook on every tool call — this is the highest-
 * frequency RPC in the system.
 *
 * Two consumers read this data:
 *   - Heartbeat hook: uses the counter to enforce logging cadence (warns at
 *     threshold, blocks if agent hasn't logged recently)
 *   - stale_sessions view: detects stuck agents by checking
 *     last_heartbeat > 5 minutes ago
 *
 * Note: effort.phase resets the counter to 0 on phase transitions, giving
 * the agent a fresh heartbeat budget for each new phase.
 *
 * Callers: PreToolUse hook (hooks.preToolUse batched RPC).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SessionRow } from "./types.js";

const schema = z.object({
  sessionId: z.number(),
  action: z.enum(["increment", "reset"]).optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ session: SessionRow }>> {
  const db = ctx.db;
  const session = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }

  const action = args.action ?? "increment";

  if (action === "reset") {
    await db.run(
      `UPDATE sessions SET heartbeat_counter = 0, last_heartbeat = datetime('now')
       WHERE id = ?`,
      [args.sessionId]
    );
  } else {
    await db.run(
      `UPDATE sessions SET heartbeat_counter = heartbeat_counter + 1, last_heartbeat = datetime('now')
       WHERE id = ?`,
      [args.sessionId]
    );
  }

  const updated = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  return { ok: true, data: { session: updated! } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.heartbeat": typeof handler;
  }
}

registerCommand("db.session.heartbeat", { schema, handler });
