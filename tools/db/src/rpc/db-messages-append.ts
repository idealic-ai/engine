/**
 * db.messages.append — Store a conversation transcript entry.
 *
 * Appends a message to the messages table with FK to a session.
 * Messages are ordered by auto-incrementing PK (id) which preserves
 * insertion order. Optional tool_name tracks which tool was used.
 *
 * Callers: hook scripts (transcript capture), session logging.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { MessageRow } from "./types.js";

const schema = z.object({
  sessionId: z.number(),
  role: z.string(),
  content: z.string(),
  toolName: z.string().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ message: MessageRow }>> {
  const db = ctx.db;
  const { lastID } = await db.run(
    `INSERT INTO messages (session_id, role, content, tool_name)
     VALUES (?, ?, ?, ?)`,
    [args.sessionId, args.role, args.content, args.toolName ?? null]
  );

  const message = await db.get<MessageRow>("SELECT * FROM messages WHERE id = ?", [lastID]);
  return { ok: true, data: { message: message! } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.messages.append": typeof handler;
  }
}

registerCommand("db.messages.append", { schema, handler });
