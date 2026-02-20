/**
 * db.session.start — Create a new context window for an effort.
 *
 * Sessions are ephemeral: one Claude Code instance's lifetime, from creation
 * to context overflow or natural end. Each session serves exactly one effort
 * (effort_id NOT NULL).
 *
 * Auto-cleanup: if another active session exists for the same effort, it's
 * automatically ended (prevents orphan sessions from crashed instances).
 * The new session links to the previous one via prev_session_id, forming
 * a continuation chain for context overflow recovery.
 *
 * PID is informational only — not used for ownership. Agent-based ownership
 * lives in the agents table (agents.effort_id FK).
 *
 * Callers: bash `engine effort start` (initial), `engine session continue`
 * (overflow recovery — creates new session with prev_session_id link).
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getSessionRow, getActiveSession, getLastInsertId } from "./row-helpers.js";

const schema = z.object({
  taskId: z.string(),
  effortId: z.number(),
  pid: z.number().optional(),
  prevSessionId: z.number().optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  db.exec("BEGIN");
  try {
    // Auto-end previous session for same effort, preserving dehydration payload
    const prevSession = getActiveSession(db, args.effortId);
    let prevId = args.prevSessionId ?? null;

    if (prevSession) {
      db.run(
        "UPDATE sessions SET ended_at = datetime('now') WHERE id = ?",
        [prevSession.id as number]
      );
      // Link to previous session if not explicitly provided
      if (!prevId) {
        prevId = prevSession.id as number;
      }
    }

    db.run(
      `INSERT INTO sessions (task_id, effort_id, prev_session_id, pid, last_heartbeat)
       VALUES (?, ?, ?, ?, datetime('now'))`,
      [args.taskId, args.effortId, prevId, args.pid ?? null]
    );

    const sessionId = getLastInsertId(db);
    const session = getSessionRow(db, sessionId);

    db.exec("COMMIT");
    return { ok: true, data: { session } };
  } catch (err: unknown) {
    db.exec("ROLLBACK");
    throw err;
  }
}

registerCommand("db.session.start", { schema, handler });
