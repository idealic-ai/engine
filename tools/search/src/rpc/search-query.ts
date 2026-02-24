/**
 * search.query — Vector similarity search over stored chunks.
 *
 * Uses sqlite-vec's vec_distance_cosine() to find the closest embeddings
 * to the provided query vector. Optionally filters by source_type.
 *
 * The query embedding is converted to a Float32Array buffer (BLOB) before
 * being passed to the SQL function — same format as stored embeddings.
 *
 * Returns results sorted by cosine distance ASC (0 = identical, 1 = orthogonal).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  embedding: z.array(z.number()),
  sourceTypes: z.array(z.string()).optional(),
  limit: z.number().int().positive().optional(),
});

type Args = z.infer<typeof schema>;

interface SearchResult {
  sourceType: string;
  sourcePath: string;
  sectionTitle: string;
  chunkText: string;
  distance: number;
}

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ results: SearchResult[] }>> {
  const db = ctx.db;
  const limit = args.limit ?? 10;
  const queryBlob = Buffer.from(new Float32Array(args.embedding).buffer);

  let sql: string;
  let params: unknown[];

  if (args.sourceTypes && args.sourceTypes.length > 0) {
    const placeholders = args.sourceTypes.map(() => "?").join(", ");
    sql = `
      SELECT c.source_type    AS sourceType,
             c.source_path    AS sourcePath,
             c.section_title  AS sectionTitle,
             c.chunk_text     AS chunkText,
             vec_distance_cosine(e.embedding, ?) AS distance
      FROM chunks c
      JOIN embeddings e ON c.content_hash = e.content_hash
      WHERE c.source_type IN (${placeholders})
      ORDER BY distance ASC
      LIMIT ?
    `;
    params = [queryBlob, ...args.sourceTypes, limit];
  } else {
    sql = `
      SELECT c.source_type    AS sourceType,
             c.source_path    AS sourcePath,
             c.section_title  AS sectionTitle,
             c.chunk_text     AS chunkText,
             vec_distance_cosine(e.embedding, ?) AS distance
      FROM chunks c
      JOIN embeddings e ON c.content_hash = e.content_hash
      ORDER BY distance ASC
      LIMIT ?
    `;
    params = [queryBlob, limit];
  }

  const results = await db.all<SearchResult>(sql, params);

  return {
    ok: true,
    data: { results },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "search.query": typeof handler;
  }
}

registerCommand("search.query", { schema, handler });
