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
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getSessionRow } from "./row-helpers.js";

const schema = z.object({
  sessionId: z.number(),
  files: z.array(z.string()),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const session = getSessionRow(db, args.sessionId);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }

  db.run(
    "UPDATE sessions SET loaded_files = jsonb(?) WHERE id = ?",
    [JSON.stringify(args.files), args.sessionId]
  );
  const updated = getSessionRow(db, args.sessionId);
  return { ok: true, data: { session: updated } };
}

registerCommand("db.session.updateLoadedFiles", { schema, handler });
