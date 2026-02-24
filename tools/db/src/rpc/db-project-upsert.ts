/**
 * db.project.upsert — Create or update an engine project.
 *
 * Projects are the root entity: one per codebase (keyed by absolute path).
 * A shared daemon serves multiple projects — this table tracks them.
 *
 * Idempotent: ON CONFLICT updates name only if a new value is provided
 * (COALESCE preserves existing data on null).
 *
 * Lifecycle position: Called first during `engine effort start` compound flow.
 * The project must exist before tasks, skills, or efforts can reference it.
 *
 * Callers: bash `engine effort start` → db.task.upsert depends on project_id.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { ProjectRow } from "./types.js";

const schema = z.object({
  path: z.string(),
  name: z.string().optional(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ project: ProjectRow }>> {
  const db = ctx.db;
    await db.run(
      `INSERT INTO projects (path, name)
       VALUES (?, ?)
       ON CONFLICT(path) DO UPDATE SET
         name = COALESCE(excluded.name, projects.name)`,
      [args.path, args.name ?? null]
    );

    const project = await db.get<ProjectRow>("SELECT * FROM projects WHERE path = ?", [args.path]);
    return { ok: true, data: { project: project! } };

}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.project.upsert": typeof handler;
  }
}

registerCommand("db.project.upsert", { schema, handler });
