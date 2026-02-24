/**
 * hooks.fleet-start — Parse and cache SKILL.md files at fleet/daemon startup.
 *
 * Called once at startup. Iterates over provided SKILL.md paths,
 * parses each via agent.skills.parse, and caches in DB via db.skills.upsert.
 *
 * This ensures the daemon can read skill data (phases, modes, templates)
 * from the DB without filesystem access (INV_DAEMON_IS_PURE_DB).
 *
 * Graceful: individual parse failures are collected as errors, not thrown.
 * The hook always succeeds — partial caching is better than none.
 */
import { z } from "zod/v4";
import { registerCommand, dispatch } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  projectPath: z.string(),
  skillPaths: z.array(z.string()),
});

type Args = z.infer<typeof schema>;

interface FleetStartData {
  cached: number;
  errors: string[];
}

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<FleetStartData>> {
  // Ensure project exists
  const projResult = await dispatch(
    { cmd: "db.project.upsert", args: { path: args.projectPath } },
    ctx
  );
  if (!projResult.ok) {
    return { ok: false, error: "PROJECT_ERROR", message: `Failed to upsert project: ${projResult.message}` };
  }
  const projectId = (projResult.data.project as { id: number }).id;

  let cached = 0;
  const errors: string[] = [];

  for (const skillPath of args.skillPaths) {
    // Parse SKILL.md
    const parseResult = await dispatch(
      { cmd: "agent.skills.parse", args: { skillPath } },
      ctx
    );

    if (!parseResult.ok) {
      errors.push(`${skillPath}: ${parseResult.message ?? parseResult.error}`);
      continue;
    }

    const skill = parseResult.data.skill as Record<string, unknown>;
    const name = skill.name as string | null;
    if (!name) {
      errors.push(`${skillPath}: no skill name found in frontmatter`);
      continue;
    }

    // Cache in DB
    const templates = skill.templates as Record<string, unknown> | null;
    const upsertResult = await dispatch(
      {
        cmd: "db.skills.upsert",
        args: {
          projectId,
          name,
          phases: skill.phases ?? undefined,
          modes: skill.modes ?? undefined,
          templates: templates ?? undefined,
          nextSkills: skill.nextSkills ?? undefined,
          directives: skill.directives ?? undefined,
          version: (skill.version as string) ?? undefined,
          description: (skill.description as string) ?? undefined,
        },
      },
      ctx
    );

    if (!upsertResult.ok) {
      errors.push(`${skillPath}: db.skills.upsert failed — ${upsertResult.message ?? upsertResult.error}`);
      continue;
    }

    cached++;
  }

  return { ok: true, data: { cached, errors } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.fleet-start": typeof handler;
  }
}

registerCommand("hooks.fleet-start", { schema, handler });
