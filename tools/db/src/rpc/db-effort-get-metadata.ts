/**
 * db.effort.getMetadata — Read parsed JSON metadata from an effort.
 *
 * SQLite stores metadata as a JSON text column. This handler extracts it via
 * json() for canonical formatting and parses it into a JS object. Returns null
 * if the effort doesn't exist or has no metadata.
 *
 * Callers: hooks.preToolUse (guard rules, lifecycle flags), commands.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  id: z.number(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ metadata: Record<string, unknown> | null }>> {
  const db = ctx.db;
  const row = await db.get<{ metadata: Record<string, unknown> | null }>(
    "SELECT json(metadata) as metadata FROM efforts WHERE id = ?",
    [args.id]
  );
  if (!row) return { ok: true, data: { metadata: null } };
  if (!row.metadata) return { ok: true, data: { metadata: null } };
  return { ok: true, data: { metadata: row.metadata } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.effort.getMetadata": typeof handler;
  }
}

registerCommand("db.effort.getMetadata", { schema, handler });
