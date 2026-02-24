/**
 * search.delete — Delete chunks by sourcePath and/or sourceType, then clean orphaned embeddings.
 *
 * At least one of sourcePath or sourceType must be provided.
 *
 * Orphan cleanup: after deleting chunks, any embeddings no longer referenced
 * by any chunk are removed (content_hash not in chunks.content_hash).
 *
 * Returns counts of deleted chunks and embeddings for observability.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z
  .object({
    sourcePath: z.string().optional(),
    sourceType: z.string().optional(),
  })
  .refine(
    (v) => v.sourcePath !== undefined || v.sourceType !== undefined,
    { message: "At least one of sourcePath or sourceType is required" }
  );

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ chunksDeleted: number; embeddingsDeleted: number }>> {
  const db = ctx.db;
  await db.run("BEGIN");
  try {
    // Build WHERE clause from provided filters
    const conditions: string[] = [];
    const params: unknown[] = [];

    if (args.sourcePath !== undefined) {
      conditions.push("source_path = ?");
      params.push(args.sourcePath);
    }
    if (args.sourceType !== undefined) {
      conditions.push("source_type = ?");
      params.push(args.sourceType);
    }

    const whereClause = conditions.join(" AND ");

    // Delete matching chunks
    const deleteResult = await db.run(
      `DELETE FROM chunks WHERE ${whereClause}`,
      params
    );
    const chunksDeleted = deleteResult.changes ?? 0;

    // Clean up orphaned embeddings (no chunks reference them)
    const orphanResult = await db.run(
      `DELETE FROM embeddings
       WHERE content_hash NOT IN (SELECT DISTINCT content_hash FROM chunks)`
    );
    const embeddingsDeleted = orphanResult.changes ?? 0;

    await db.run("COMMIT");
    return {
      ok: true,
      data: { chunksDeleted, embeddingsDeleted },
    };
  } catch (err: unknown) {
    await db.run("ROLLBACK");
    throw err;
  }
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "search.delete": typeof handler;
  }
}

registerCommand("search.delete", { schema, handler });
