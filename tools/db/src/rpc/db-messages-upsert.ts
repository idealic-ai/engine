/**
 * db.messages.upsert — Bulk insert transcript messages for a session.
 *
 * Inserts an array of messages in a single pass. Designed for batch
 * ingestion from JSONL transcript files. Each message maps to a row
 * in the messages table with FK to the session.
 *
 * Callers: agent.messages.ingest (transcript ingestion pipeline).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const messageSchema = z.object({
  role: z.string(),
  content: z.string(),
  toolName: z.string().optional(),
});

const schema = z.object({
  sessionId: z.number(),
  messages: z.array(messageSchema),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ inserted: number }>> {
  const db = ctx.db;

  if (args.messages.length === 0) {
    return { ok: true, data: { inserted: 0 } };
  }

  let inserted = 0;
  for (const msg of args.messages) {
    await db.run(
      `INSERT INTO messages (session_id, role, content, tool_name)
       VALUES (?, ?, ?, ?)`,
      [args.sessionId, msg.role, msg.content, msg.toolName ?? null]
    );
    inserted++;
  }

  return { ok: true, data: { inserted } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.messages.upsert": typeof handler;
  }
}

registerCommand("db.messages.upsert", { schema, handler });
