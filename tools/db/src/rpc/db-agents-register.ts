/**
 * db.agents.register — Upsert a fleet agent identity.
 *
 * Agents table uses TEXT PK (id). INSERT OR REPLACE semantics — the full
 * row is replaced on conflict. Optionally links to an active effort via
 * effort_id FK.
 *
 * Callers: fleet.sh start (registers pane agents), run.sh (self-register).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { AgentRow } from "./types.js";

const schema = z.object({
  id: z.string(),
  label: z.string().optional(),
  claims: z.string().optional(),
  targetedClaims: z.string().optional(),
  manages: z.string().optional(),
  parent: z.string().optional(),
  effortId: z.number().optional(),
  status: z.string().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ agent: AgentRow }>> {
  const db = ctx.db;
  await db.run(
    `INSERT OR REPLACE INTO agents (id, label, claims, targeted_claims, manages, parent, effort_id, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [args.id, args.label ?? null, args.claims ?? null, args.targetedClaims ?? null, args.manages ?? null, args.parent ?? null, args.effortId ?? null, args.status ?? null]
  );

  const agent = await db.get<AgentRow>("SELECT * FROM agents WHERE id = ?", [args.id]);
  if (!agent) {
    return { ok: false, error: "HANDLER_ERROR", message: "Agent not found after insert" };
  }

  return { ok: true, data: { agent } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.agents.register": typeof handler;
  }
}

registerCommand("db.agents.register", { schema, handler });
