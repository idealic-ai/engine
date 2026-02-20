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
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getActiveSession } from "./row-helpers.js";

const schema = z.object({
  effortId: z.number(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const session = getActiveSession(db, args.effortId);
  return { ok: true, data: { session } };
}

registerCommand("db.session.find", { schema, handler });
