/**
 * db.skills.get — Retrieve a cached skill definition by project and name.
 *
 * Returns the full skill row with JSONB columns (phases, modes, templates, etc.)
 * deserialized to JS objects. Returns { skill: null } if not found.
 *
 * The JSONB→JSON conversion is necessary because wa-sqlite stores JSONB as binary
 * internally — we use `json(column)` in the SELECT to get readable text, then
 * JSON.parse to get JS objects.
 *
 * Primary consumer: db.effort.phase reads phases from this table to enforce
 * sequential phase progression without touching the filesystem.
 *
 * Callers: effort.phase (phase enforcement), bash compound commands (skill lookup).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SkillRow } from "./types.js";

const schema = z.object({
  projectId: z.number(),
  name: z.string(),
});

type Args = z.infer<typeof schema>;

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ skill: SkillRow | null }>> {
  const db = ctx.db;
  // Use json() to convert JSONB columns to readable JSON text
  // db-wrapper auto-parses JSON strings and camelCases keys
  const row = await db.get<SkillRow>(
    `SELECT id, project_id, name,
       json(phases) as phases, json(modes) as modes, json(templates) as templates,
       json(cmd_dependencies) as cmd_dependencies, json(next_skills) as next_skills,
       json(directives) as directives, version, description, updated_at
     FROM skills WHERE project_id = ? AND name = ?`,
    [args.projectId, args.name]
  );

  if (!row) {
    return { ok: true, data: { skill: null } };
  }

  return { ok: true, data: { skill: row } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.skills.get": typeof handler;
  }
}

registerCommand("db.skills.get", { schema, handler });
