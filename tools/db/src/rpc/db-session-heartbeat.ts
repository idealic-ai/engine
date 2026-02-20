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
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getSessionRow } from "./row-helpers.js";

const schema = z.object({
  sessionId: z.number(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const session = getSessionRow(db, args.sessionId);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }

  db.run(
    `UPDATE sessions SET heartbeat_counter = heartbeat_counter + 1, last_heartbeat = datetime('now')
     WHERE id = ?`,
    [args.sessionId]
  );

  const updated = getSessionRow(db, args.sessionId);
  return { ok: true, data: { session: updated } };
}

registerCommand("db.session.heartbeat", { schema, handler });
