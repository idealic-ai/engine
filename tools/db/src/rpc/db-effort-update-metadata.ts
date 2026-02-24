/**
 * db.effort.updateMetadata — Patch effort metadata via json_set/json_remove.
 *
 * Supports two operations in a single call:
 *   - remove: array of top-level keys to delete via json_remove
 *   - set: record of key/value pairs to upsert via json_set
 *
 * Operations execute in order: removes first, then sets. Returns the final
 * parsed metadata after all mutations.
 *
 * Callers: hooks.postToolUse (clear pendingInjections), commands.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  id: z.number(),
  remove: z.array(z.string()).optional(),
  set: z.record(z.string(), z.unknown()).optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ metadata: Record<string, unknown> | null }>> {
  const db = ctx.db;

  // Apply removes (coalesce NULL metadata to '{}' so json_remove works)
  if (args.remove) {
    for (const key of args.remove) {
      await db.run(
        `UPDATE efforts SET metadata = json_remove(COALESCE(metadata, '{}'), '$.' || ?) WHERE id = ?`,
        [key, args.id]
      );
    }
  }

  // Apply sets (coalesce NULL metadata to '{}' so json_set works)
  if (args.set) {
    for (const [key, value] of Object.entries(args.set)) {
      await db.run(
        `UPDATE efforts SET metadata = json_set(COALESCE(metadata, '{}'), '$.' || ?, json(?)) WHERE id = ?`,
        [key, JSON.stringify(value), args.id]
      );
    }
  }

  // Re-read and return
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
    "db.effort.updateMetadata": typeof handler;
  }
}

registerCommand("db.effort.updateMetadata", { schema, handler });
