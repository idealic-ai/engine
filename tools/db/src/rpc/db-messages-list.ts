/**
 * db.messages.list — List messages for a session.
 *
 * Returns messages ordered by id (insertion order). Supports optional
 * limit parameter for pagination. Messages are the conversation transcript
 * — user prompts, assistant responses, and tool calls.
 *
 * Callers: session review, transcript export, context reconstruction.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  sessionId: z.number(),
  limit: z.number().optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const limitClause = args.limit !== undefined ? "LIMIT ?" : "";
  const params: (number)[] = [args.sessionId];
  if (args.limit !== undefined) params.push(args.limit);

  const result = db.exec(
    `SELECT * FROM messages WHERE session_id = ? ORDER BY id ${limitClause}`,
    params
  );

  if (result.length === 0) {
    return { ok: true, data: { messages: [] } };
  }

  const { columns, values } = result[0];
  const messages = values.map((row) => {
    const obj: Record<string, unknown> = {};
    for (let i = 0; i < columns.length; i++) {
      obj[columns[i]] = row[i];
    }
    return obj;
  });

  return { ok: true, data: { messages } };
}

registerCommand("db.messages.list", { schema, handler });
