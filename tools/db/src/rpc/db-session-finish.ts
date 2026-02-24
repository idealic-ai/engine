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
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SessionRow } from "./types.js";

const schema = z.object({
  sessionId: z.number(),
  dehydrationPayload: z.record(z.string(), z.unknown()).optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ session: SessionRow }>> {
  const db = ctx.db;
  const session = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }
  if (session.endedAt) {
    return { ok: false, error: "ALREADY_ENDED", message: `Session ${args.sessionId} is already ended` };
  }

    const dehydJson = args.dehydrationPayload
      ? JSON.stringify(args.dehydrationPayload)
      : null;

    await db.run(
      `UPDATE sessions SET ended_at = datetime('now'), dehydration_payload = json(?)
       WHERE id = ?`,
      [dehydJson, args.sessionId]
    );

    const updated = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
    return { ok: true, data: { session: updated! } };

}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.finish": typeof handler;
  }
}

registerCommand("db.session.finish", { schema, handler });
