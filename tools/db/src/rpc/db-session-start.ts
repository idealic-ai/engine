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
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SessionRow } from "./types.js";

const schema = z.object({
  taskId: z.string(),
  effortId: z.number(),
  pid: z.number().optional(),
  prevSessionId: z.number().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ session: SessionRow }>> {
  const db = ctx.db;
    // Auto-end previous session for same effort, preserving dehydration payload
    const prevSession = await db.get<SessionRow>(
      "SELECT * FROM sessions WHERE effort_id = ? AND ended_at IS NULL ORDER BY id DESC LIMIT 1",
      [args.effortId]
    );
    let prevId = args.prevSessionId ?? null;

    if (prevSession) {
      await db.run(
        "UPDATE sessions SET ended_at = datetime('now') WHERE id = ?",
        [prevSession.id]
      );
      if (!prevId) {
        prevId = prevSession.id;
      }
    }

    // Inherit discovered_directives/directories from previous session (rehydration continuity)
    let inheritedDirectives: string | null = null;
    let inheritedDirectories: string | null = null;
    if (prevSession) {
      const directives = prevSession.discoveredDirectives;
      const directories = prevSession.discoveredDirectories;
      if (directives) inheritedDirectives = JSON.stringify(directives);
      if (directories) inheritedDirectories = JSON.stringify(directories);
    }

    const { lastID } = await db.run(
      `INSERT INTO sessions (task_id, effort_id, prev_session_id, pid, last_heartbeat, discovered_directives, discovered_directories)
       VALUES (?, ?, ?, ?, datetime('now'), json(?), json(?))`,
      [args.taskId, args.effortId, prevId, args.pid ?? null, inheritedDirectives, inheritedDirectories]
    );

    const session = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [lastID]);

    return { ok: true, data: { session: session! } };

}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.start": typeof handler;
  }
}

registerCommand("db.session.start", { schema, handler });
