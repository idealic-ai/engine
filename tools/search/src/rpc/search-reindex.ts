/**
 * search.reindex — STUB: Full reindex of source files.
 *
 * This command is a placeholder until fs.* and ai.* RPCs are available.
 * Once those exist, reindex will: scan source files, generate embeddings
 * via ai.embed, and upsert all chunks via search.upsert.
 *
 * Returns a not_implemented status — callers should check for this and skip
 * or handle gracefully.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  sourceTypes: z.array(z.string()).optional(),
});

type Args = z.infer<typeof schema>;

async function handler(_args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ status: string; message: string }>> {
  const db = ctx.db;
  return {
    ok: true,
    data: {
      status: "not_implemented",
      message: "Requires fs.* and ai.* RPCs",
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "search.reindex": typeof handler;
  }
}

registerCommand("search.reindex", { schema, handler });
