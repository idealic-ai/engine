/**
 * hooks.sessionStart — SessionStart hook RPC.
 *
 * Called by the SessionStart bash hook at Claude process startup.
 * Orchestrates finding an active effort+session for the project and
 * assembles all context the agent needs: skill config, files to preload,
 * dehydration payload, and a session context string.
 *
 * Read-only for effort lookup; may CREATE a session if one doesn't exist
 * for the active effort (auto-end previous, link via prev_session_id).
 *
 * Returns { found: false } when no active effort exists — effort creation
 * stays external (bash `engine effort start`).
 *
 * Input:  hookSchema({ source, model?, agentType? })
 *
 * INV_DAEMON_IS_PURE_DB: no filesystem I/O — returns paths only.
 * INV_RPC_GUARD_BEFORE_MUTATE: validates effort exists before session INSERT.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { SkillRow } from "engine-db/rpc/types";
import { hookSchema } from "./hook-base-schema.js";

const schema = hookSchema({
  source: z.string(),
  model: z.string().optional(),
  agentType: z.string().optional(),
});

type Args = z.infer<typeof schema>;

/** SessionStart hook response — uses hookSpecificOutput for Claude Code context injection */
interface SessionStartResponse {
  found: boolean;
  effortId?: number;
  sessionId?: number;
  taskDir?: string;
  skill?: string;
  phase?: string | null;
  filesToPreload?: string[];
  dehydratedContext?: unknown;
  sessionContext?: string;
  skillConfig?: SkillRow | null;
  hookSpecificOutput?: {
    hookEventName: string;
    additionalContext?: string;
  };
}

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<SessionStartResponse>> {
  // 1. Find project by path
  const { project } = await ctx.db.project.find({ path: args.cwd });
  if (!project) {
    return { ok: true, data: { found: false } };
  }
  const projectId = project.id;

  // 2. Find active effort for this project (agent-aware via per-request env)
  const rawAgentId = ctx.env.AGENT_ID;
  const agentId = rawAgentId === "default" ? undefined : rawAgentId;

  const { effort: effortRow, taskDir: foundTaskDir } = await ctx.db.effort.findActive({
    projectId,
    agentId: agentId ?? undefined,
  });

  // 3. No active effort → early return
  if (!effortRow) {
    return { ok: true, data: { found: false } };
  }

  const effortId = effortRow.id;
  const taskDir = foundTaskDir ?? effortRow.taskId;
  const skill = effortRow.skill;
  const phase = effortRow.currentPhase ?? null;

  // 4. Find or create active session for this effort
  const { session: existingSession } = await ctx.db.session.find({ effortId });

  let session = existingSession;

  if (!session) {
    // Create a new session via namespace method (handles auto-cleanup internally)
    const { session: newSession } = await ctx.db.session.start({
      taskId: taskDir,
      effortId,
    });
    session = newSession;
  }

  const sessionId = session!.id;

  // 5. Load skill config from skills table
  const { skill: skillConfig } = await ctx.db.skills.get({ projectId, name: skill });

  // 6. Collect filesToPreload
  const filesToPreload: string[] = [];

  // Add skill templates
  if (skillConfig?.templates) {
    for (const path of Object.values(skillConfig.templates)) {
      if (path.length > 0) {
        filesToPreload.push(path);
      }
    }
  }

  // Add discovered_directives from effort (stored as JSON array column)
  const discoveredDirectives = (effortRow as unknown as Record<string, unknown>).discoveredDirectives;
  if (Array.isArray(discoveredDirectives)) {
    for (const directive of discoveredDirectives) {
      if (typeof directive === "string") {
        filesToPreload.push(directive);
      }
    }
  }

  // 7. Check for dehydration_payload
  const dehydratedContext = session!.dehydrationPayload ?? null;

  // 8. Build sessionContext string
  const heartbeatCounter = session!.heartbeatCounter ?? 0;
  const now = new Date().toISOString();
  const sessionContext = `[Session Context] Time: ${now} | Session: ${taskDir} | Skill: ${skill} | Phase: ${phase ?? "none"} | Heartbeat: ${heartbeatCounter}/10`;

  // 9. Build additionalContext for Claude Code injection
  const contextParts: string[] = [sessionContext];

  if (filesToPreload.length > 0) {
    contextParts.push("");
    contextParts.push("[Files to preload]:");
    for (const f of filesToPreload) {
      contextParts.push(`  - ${f}`);
    }
  }

  if (dehydratedContext) {
    contextParts.push("");
    contextParts.push("## Session Recovery (Dehydrated Context)");
    contextParts.push(typeof dehydratedContext === "string"
      ? dehydratedContext
      : JSON.stringify(dehydratedContext, null, 2));
  }

  const additionalContext = contextParts.join("\n");

  // 10. Return aggregated result with hookSpecificOutput for Claude Code
  return {
    ok: true,
    data: {
      found: true,
      effortId,
      sessionId,
      taskDir,
      skill,
      phase,
      filesToPreload,
      dehydratedContext,
      sessionContext,
      skillConfig,
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext,
      },
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.sessionStart": typeof handler;
  }
}

registerCommand("hooks.sessionStart", { schema, handler });
