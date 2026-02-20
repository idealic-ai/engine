/**
 * db.session.finish — End a context window, optionally preserving state.
 *
 * Marks the session as ended with a timestamp. If context overflow triggered
 * the end, the dehydration payload captures a snapshot of the agent's state
 * (summary, next steps, required files) for the next session to pick up.
 *
 * The dehydration_payload replaces the v2 dehydration_snapshots table — one
 * dehydration per session is sufficient (stored as JSONB on the session row).
 *
 * Guards: NOT_FOUND if session doesn't exist, ALREADY_ENDED if session was
 * already finished (prevents double-close).
 *
 * Callers: overflow hook (with dehydration payload), natural session end
 * (without payload), session.start auto-cleanup (ends previous session).
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getSessionRow } from "./row-helpers.js";

const schema = z.object({
  sessionId: z.number(),
  dehydrationPayload: z.record(z.string(), z.unknown()).optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const session = getSessionRow(db, args.sessionId);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }
  if (session.ended_at) {
    return { ok: false, error: "ALREADY_ENDED", message: `Session ${args.sessionId} is already ended` };
  }

  db.exec("BEGIN");
  try {
    const dehydJson = args.dehydrationPayload
      ? JSON.stringify(args.dehydrationPayload)
      : null;

    db.run(
      `UPDATE sessions SET ended_at = datetime('now'), dehydration_payload = jsonb(?)
       WHERE id = ?`,
      [dehydJson, args.sessionId]
    );

    const updated = getSessionRow(db, args.sessionId);
    db.exec("COMMIT");
    return { ok: true, data: { session: updated } };
  } catch (err: unknown) {
    db.exec("ROLLBACK");
    throw err;
  }
}

registerCommand("db.session.finish", { schema, handler });
