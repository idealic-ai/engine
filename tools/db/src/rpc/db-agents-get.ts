/**
 * db.agents.get — Retrieve a fleet agent by id.
 *
 * Returns the full agent row or { agent: null } if not found.
 *
 * Callers: fleet coordination, session activation (agent lookup).
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  id: z.string(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  const result = db.exec("SELECT * FROM agents WHERE id = ?", [args.id]);

  if (result.length === 0 || result[0].values.length === 0) {
    return { ok: true, data: { agent: null } };
  }

  const { columns, values } = result[0];
  const agent: Record<string, unknown> = {};
  for (let i = 0; i < columns.length; i++) {
    agent[columns[i]] = values[0][i];
  }

  return { ok: true, data: { agent } };
}

registerCommand("db.agents.get", { schema, handler });
