/**
 * search.upsert — Insert or update a chunk and its embedding vector.
 *
 * Stores the embedding BLOB in the `embeddings` table (keyed by content_hash)
 * and the chunk metadata in the `chunks` table. Both are upserted atomically.
 *
 * The embedding array is stored as a Float32Array buffer (BLOB) for use with
 * sqlite-vec's vec_distance_cosine() function.
 *
 * Idempotent: re-upserting the same content_hash+sourcePath+sectionTitle is safe.
 * Content-hash dedup: multiple chunks can share the same embedding (same text).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  sourceType: z.string(),
  sourcePath: z.string(),
  sectionTitle: z.string(),
  chunkText: z.string(),
  contentHash: z.string(),
  embedding: z.array(z.number()),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ chunkId: number; contentHash: string; created: boolean }>> {
  const db = ctx.db;
  const embeddingBlob = Buffer.from(new Float32Array(args.embedding).buffer);

  await db.run("BEGIN");
  try {
    // Upsert embedding (content-hash keyed, shared across duplicate texts)
    await db.run(
      `INSERT INTO embeddings (content_hash, embedding, updated_at)
       VALUES (?, ?, datetime('now'))
       ON CONFLICT(content_hash) DO UPDATE SET
         embedding = excluded.embedding,
         updated_at = excluded.updated_at`,
      [args.contentHash, embeddingBlob]
    );

    // Check if chunk already existed
    const existing = await db.get<{ id: number }>(
      "SELECT id FROM chunks WHERE source_path = ? AND section_title = ?",
      [args.sourcePath, args.sectionTitle]
    );
    const created = !existing;

    // Upsert chunk (unique on source_path + section_title)
    await db.run(
      `INSERT INTO chunks (source_type, source_path, section_title, chunk_text, content_hash, updated_at)
       VALUES (?, ?, ?, ?, ?, datetime('now'))
       ON CONFLICT(source_path, section_title) DO UPDATE SET
         source_type   = excluded.source_type,
         chunk_text    = excluded.chunk_text,
         content_hash  = excluded.content_hash,
         updated_at    = excluded.updated_at`,
      [args.sourceType, args.sourcePath, args.sectionTitle, args.chunkText, args.contentHash]
    );

    const chunk = await db.get<{ id: number; contentHash: string }>(
      "SELECT id, content_hash FROM chunks WHERE source_path = ? AND section_title = ?",
      [args.sourcePath, args.sectionTitle]
    );

    await db.run("COMMIT");
    return {
      ok: true,
      data: {
        chunkId: chunk!.id,
        contentHash: chunk!.contentHash,
        created,
      },
    };
  } catch (err: unknown) {
    await db.run("ROLLBACK");
    throw err;
  }
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "search.upsert": typeof handler;
  }
}

registerCommand("search.upsert", { schema, handler });
