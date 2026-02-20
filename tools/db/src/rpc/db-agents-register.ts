/**
 * db.agents.register — Upsert a fleet agent identity.
 *
 * Agents table uses TEXT PK (id). INSERT OR REPLACE semantics — the full
 * row is replaced on conflict. Optionally links to an active effort via
 * effort_id FK.
 *
 * Callers: fleet.sh start (registers pane agents), run.sh (self-register).
 */
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";

const schema = z.object({
  id: z.string(),
  label: z.string().optional(),
  claims: z.string().optional(),
  effortId: z.number().optional(),
});

type Args = z.infer<typeof schema>;

function handler(args: Args, db: Database): RpcResponse {
  db.run(
    `INSERT OR REPLACE INTO agents (id, label, claims, effort_id)
     VALUES (?, ?, ?, ?)`,
    [args.id, args.label ?? null, args.claims ?? null, args.effortId ?? null]
  );

  const result = db.exec("SELECT * FROM agents WHERE id = ?", [args.id]);
  if (result.length === 0 || result[0].values.length === 0) {
    return { ok: false, error: "HANDLER_ERROR", message: "Agent not found after insert" };
  }

  const { columns, values } = result[0];
  const agent: Record<string, unknown> = {};
  for (let i = 0; i < columns.length; i++) {
    agent[columns[i]] = values[0][i];
  }

  return { ok: true, data: { agent } };
}

registerCommand("db.agents.register", { schema, handler });
