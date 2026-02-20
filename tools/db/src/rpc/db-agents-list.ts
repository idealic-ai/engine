/**
 * db.agents.list — List all registered fleet agents.
 *
 * Returns all agent rows. No filtering — the agents table is small
 * (typically <10 entries for a fleet).
 *
 * Callers: fleet.sh status, coordinator overview, dispatch-daemon.
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({});

type Args = z.infer<typeof schema>;

function handler(_args: Args, db: Database): RpcResponse {
  const result = db.exec("SELECT * FROM agents ORDER BY id");

  if (result.length === 0) {
    return { ok: true, data: { agents: [] } };
  }

  const { columns, values } = result[0];
  const agents = values.map((row) => {
    const obj: Record<string, unknown> = {};
    for (let i = 0; i < columns.length; i++) {
      obj[columns[i]] = row[i];
    }
    return obj;
  });

  return { ok: true, data: { agents } };
}

registerCommand("db.agents.list", { schema, handler });
