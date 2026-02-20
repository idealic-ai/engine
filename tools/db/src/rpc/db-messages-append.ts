/**
 * db.messages.append — Store a conversation transcript entry.
 *
 * Appends a message to the messages table with FK to a session.
 * Messages are ordered by auto-incrementing PK (id) which preserves
 * insertion order. Optional tool_name tracks which tool was used.
 *
 * Callers: hook scripts (transcript capture), session logging.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  sessionId: z.number(),
  role: z.string(),
  content: z.string(),
  toolName: z.string().optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  db.run(
    `INSERT INTO messages (session_id, role, content, tool_name)
     VALUES (?, ?, ?, ?)`,
    [args.sessionId, args.role, args.content, args.toolName ?? null]
  );

  const id = db.exec("SELECT last_insert_rowid() AS id")[0].values[0][0] as number;
  const result = db.exec("SELECT * FROM messages WHERE id = ?", [id]);

  const { columns, values } = result[0];
  const message: Record<string, unknown> = {};
  for (let i = 0; i < columns.length; i++) {
    message[columns[i]] = values[0][i];
  }

  return { ok: true, data: { message } };
}

registerCommand("db.messages.append", { schema, handler });
