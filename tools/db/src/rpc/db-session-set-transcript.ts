/**
 * db.session.setTranscript — Store or update transcript path and offset on a session.
 *
 * Used by the ingestion pipeline to:
 *   1. Record which JSONL file belongs to this session (first call)
 *   2. Advance the byte-offset waterline after each ingestion batch
 *
 * Either field can be updated independently — omitted fields are left unchanged.
 *
 * Callers: agent.messages.ingest.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  sessionId: z.number(),
  transcriptPath: z.string().optional(),
  transcriptOffset: z.number().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ updated: boolean }>> {
  const db = ctx.db;

  const sets: string[] = [];
  const params: (string | number)[] = [];

  if (args.transcriptPath !== undefined) {
    sets.push("transcript_path = ?");
    params.push(args.transcriptPath);
  }
  if (args.transcriptOffset !== undefined) {
    sets.push("transcript_offset = ?");
    params.push(args.transcriptOffset);
  }

  if (sets.length === 0) {
    return { ok: true, data: { updated: false } };
  }

  params.push(args.sessionId);
  const { changes } = await db.run(
    `UPDATE sessions SET ${sets.join(", ")} WHERE id = ?`,
    params
  );

  return { ok: true, data: { updated: changes > 0 } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.session.setTranscript": typeof handler;
  }
}

registerCommand("db.session.setTranscript", { schema, handler });
