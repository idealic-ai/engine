/**
 * db.skills.delete — Remove a cached skill definition by project and name.
 *
 * Returns { deleted: true } if a row was removed, { deleted: false } if
 * the skill didn't exist. No error on missing — idempotent delete.
 *
 * Callers: bash cleanup scripts, skill removal workflows.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  projectId: z.number(),
  name: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ deleted: boolean }>> {
  const db = ctx.db;
  const { changes } = await db.run(
    "DELETE FROM skills WHERE project_id = ? AND name = ?",
    [args.projectId, args.name]
  );
  return { ok: true, data: { deleted: changes > 0 } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.skills.delete": typeof handler;
  }
}

registerCommand("db.skills.delete", { schema, handler });
