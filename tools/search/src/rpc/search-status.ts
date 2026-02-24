/**
 * search.status — Aggregate statistics over the search index.
 *
 * Returns total counts and per-source-type breakdown.
 * Useful for observability, health checks, and debugging index coverage.
 *
 * No arguments required — always returns full aggregate state.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({});

type Args = z.infer<typeof schema>;

async function handler(_args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ totalChunks: number; totalEmbeddings: number; bySourceType: Record<string, number>; uniquePaths: number }>> {
  const db = ctx.db;
  const [totalChunksRow, totalEmbeddingsRow, byTypeRows, uniquePathsRow] =
    await Promise.all([
      db.get<{ count: number }>("SELECT COUNT(*) AS count FROM chunks"),
      db.get<{ count: number }>("SELECT COUNT(*) AS count FROM embeddings"),
      db.all<{ sourceType: string; count: number }>(
        "SELECT source_type, COUNT(*) AS count FROM chunks GROUP BY source_type"
      ),
      db.get<{ count: number }>(
        "SELECT COUNT(DISTINCT source_path) AS count FROM chunks"
      ),
    ]);

  const bySourceType: Record<string, number> = {};
  for (const row of byTypeRows) {
    bySourceType[row.sourceType] = row.count;
  }

  return {
    ok: true,
    data: {
      totalChunks: totalChunksRow?.count ?? 0,
      totalEmbeddings: totalEmbeddingsRow?.count ?? 0,
      bySourceType,
      uniquePaths: uniquePathsRow?.count ?? 0,
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "search.status": typeof handler;
  }
}

registerCommand("search.status", { schema, handler });
