/**
 * db.skills.find — Search cached skill definitions by name substring.
 *
 * Uses SQL LIKE for case-insensitive substring matching on the name column.
 * Returns full skill rows with JSONB columns deserialized.
 *
 * Callers: bash `engine skills find`, daemon-side skill discovery.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  projectId: z.number(),
  query: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ skills: Record<string, unknown>[] }>> {
  const db = ctx.db;
  // db-wrapper auto-parses JSON strings and camelCases keys
  const rows = await db.all<Record<string, unknown>>(
    `SELECT id, project_id, name,
       json(phases) as phases, json(modes) as modes, json(templates) as templates,
       json(cmd_dependencies) as cmd_dependencies, json(next_skills) as next_skills,
       json(directives) as directives, version, description, updated_at
     FROM skills WHERE project_id = ? AND name LIKE ? ORDER BY name`,
    [args.projectId, `%${args.query}%`]
  );

  return { ok: true, data: { skills: rows } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.skills.find": typeof handler;
  }
}

registerCommand("db.skills.find", { schema, handler });
