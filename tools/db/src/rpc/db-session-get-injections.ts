/**
 * db.session.getInjections — Read pending injections from a session.
 *
 * Returns the current injection queue without modifying it.
 * Returns empty array if no injections are pending (null → []).
 *
 * Callers: PostToolUse (read before processing), diagnostics.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { Injection, SessionRow } from "./types.js";

const schema = z.object({
  sessionId: z.number(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ injections: Injection[] }>> {
  const db = ctx.db;
  const session = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }
  const injections: Injection[] = (session.pendingInjections as Injection[]) ?? [];
  return { ok: true, data: { injections } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.getInjections": typeof handler;
  }
}

registerCommand("db.session.getInjections", { schema, handler });
