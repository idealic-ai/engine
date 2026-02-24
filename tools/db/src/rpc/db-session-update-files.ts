/**
 * db.session.updateLoadedFiles — Track which files the agent has read.
 *
 * Replaces the loaded_files JSON array with the provided list. Called by the
 * PostToolUse hook whenever the Read tool is used — builds a running manifest
 * of files loaded into the agent's context window.
 *
 * Primary use: "don't re-read" optimization on session.continue. When a new
 * session resumes after overflow, it can check which files the previous session
 * already loaded and skip re-reading them (INV_TRUST_CACHED_CONTEXT).
 *
 * Callers: PostToolUse hook (hooks.postToolUse batched RPC on Read events).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SessionRow } from "./types.js";

const schema = z.object({
  sessionId: z.number(),
  files: z.array(z.string()),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ session: SessionRow }>> {
  const db = ctx.db;
  const session = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }

  await db.run(
    "UPDATE sessions SET loaded_files = json(?) WHERE id = ?",
    [JSON.stringify(args.files), args.sessionId]
  );
  const updated = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  return { ok: true, data: { session: updated! } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.updateLoadedFiles": typeof handler;
  }
}

registerCommand("db.session.updateLoadedFiles", { schema, handler });
