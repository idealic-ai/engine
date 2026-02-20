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
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getSessionRow } from "./row-helpers.js";

const schema = z.object({
  sessionId: z.number(),
  usage: z.number(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const session = getSessionRow(db, args.sessionId);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }

  db.run("UPDATE sessions SET context_usage = ? WHERE id = ?", [args.usage, args.sessionId]);
  const updated = getSessionRow(db, args.sessionId);
  return { ok: true, data: { session: updated } };
}

registerCommand("db.session.updateContextUsage", { schema, handler });
