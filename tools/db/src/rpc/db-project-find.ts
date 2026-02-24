/**
 * db.project.find — Find a project by filesystem path.
 *
 * Returns the full ProjectRow or null if no project is registered at the
 * given path. Used during session startup to resolve the project identity
 * before looking up efforts.
 *
 * Callers: hooks.sessionStart, commands.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { ProjectRow } from "./types.js";

const schema = z.object({
  path: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ project: ProjectRow | null }>> {
  const db = ctx.db;
  const project = await db.get<ProjectRow>("SELECT * FROM projects WHERE path = ?", [args.path]);
  return { ok: true, data: { project: project ?? null } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.project.find": typeof handler;
  }
}

registerCommand("db.project.find", { schema, handler });
