/**
 * db.messages.list — List messages for a session.
 *
 * Returns messages ordered by id (insertion order). Supports optional
 * limit parameter for pagination. Messages are the conversation transcript
 * — user prompts, assistant responses, and tool calls.
 *
 * Callers: session review, transcript export, context reconstruction.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { MessageRow } from "./types.js";

const schema = z.object({
  sessionId: z.number(),
  limit: z.number().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ messages: MessageRow[] }>> {
  const db = ctx.db;
  const limitClause = args.limit !== undefined ? "LIMIT ?" : "";
  const params: (number)[] = [args.sessionId];
  if (args.limit !== undefined) params.push(args.limit);

  const messages = await db.all<MessageRow>(
    `SELECT * FROM messages WHERE session_id = ? ORDER BY id ${limitClause}`,
    params
  );

  return { ok: true, data: { messages } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.messages.list": typeof handler;
  }
}

registerCommand("db.messages.list", { schema, handler });
