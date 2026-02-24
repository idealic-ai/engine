/**
 * db.session.updateInjections — Manage the pending injection queue on a session.
 *
 * Supports three operations (composable in a single call):
 *   - add: append new injections to the queue
 *   - removeByRuleId: remove specific injections by ruleId (after processing)
 *   - clearAll: wipe the entire queue
 *
 * Order: clearAll first, then removeByRuleId, then add.
 * Returns the final injection list after all mutations.
 *
 * Callers: directive discovery (add), PostToolUse (removeByRuleId after delivery).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { Injection, SessionRow } from "./types.js";

const injectionSchema = z.object({
  ruleId: z.string(),
  content: z.string(),
  mode: z.enum(["preload", "message"]),
  path: z.string().optional(),
});

const schema = z.object({
  sessionId: z.number(),
  add: z.array(injectionSchema).optional(),
  removeByRuleId: z.array(z.string()).optional(),
  clearAll: z.boolean().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ injections: Injection[] }>> {
  const db = ctx.db;
  const session = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }

  let injections: Injection[] = (session.pendingInjections as Injection[]) ?? [];

  // 1. Clear all (if requested)
  if (args.clearAll) {
    injections = [];
  }

  // 2. Remove by ruleId
  if (args.removeByRuleId?.length) {
    const toRemove = new Set(args.removeByRuleId);
    injections = injections.filter((i) => !toRemove.has(i.ruleId));
  }

  // 3. Add new
  if (args.add?.length) {
    injections.push(...args.add);
  }

  // Write back
  await db.run(
    "UPDATE sessions SET pending_injections = json(?) WHERE id = ?",
    [JSON.stringify(injections), args.sessionId],
  );

  return { ok: true, data: { injections } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.updateInjections": typeof handler;
  }
}

registerCommand("db.session.updateInjections", { schema, handler });
