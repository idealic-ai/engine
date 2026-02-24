/**
 * db.session.updatePreloadedFiles — Track files injected via additionalContext.
 *
 * Appends new paths to preloaded_files, deduplicating against both
 * preloaded_files (already injected) and loaded_files (already Read by agent).
 * A file that was Read doesn't need preloading, and vice versa.
 *
 * Returns the final deduplicated preloaded_files array.
 *
 * Callers: PostToolUse (after processing preload-mode injections),
 *          SessionStart (after injecting discovered directives).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SessionRow } from "./types.js";

const schema = z.object({
  sessionId: z.number(),
  add: z.array(z.string()),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ preloadedFiles: string[] }>> {
  const db = ctx.db;
  const session = await db.get<SessionRow>("SELECT * FROM sessions WHERE id = ?", [args.sessionId]);
  if (!session) {
    return { ok: false, error: "NOT_FOUND", message: `Session ${args.sessionId} not found` };
  }

  const existing = (session.preloadedFiles as string[]) ?? [];
  const loaded = (session.loadedFiles as string[]) ?? [];
  const alreadyKnown = new Set([...existing, ...loaded]);

  const newFiles = args.add.filter((f) => !alreadyKnown.has(f));
  const merged = [...existing, ...newFiles];

  await db.run(
    "UPDATE sessions SET preloaded_files = json(?) WHERE id = ?",
    [JSON.stringify(merged), args.sessionId],
  );

  return { ok: true, data: { preloadedFiles: merged } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.updatePreloadedFiles": typeof handler;
  }
}

registerCommand("db.session.updatePreloadedFiles", { schema, handler });
