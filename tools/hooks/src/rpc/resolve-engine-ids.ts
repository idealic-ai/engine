/**
 * resolve-engine-ids — Resolves Claude Code's cwd into engine's numeric IDs.
 *
 * Claude Code sends cwd (project path) on every hook event. The engine
 * stores projects, efforts, and sessions with numeric IDs. This utility
 * bridges the gap: cwd → projectId → effortId → engineSessionId.
 *
 * Agent-aware: reads AGENT_ID from ctx.env (injected per-request by rpc-cli)
 * to resolve agent-specific efforts in multi-agent fleet scenarios.
 * Falls back to latest effort when no AGENT_ID is set (solo/default).
 *
 * Fail-open: returns nulls for any unresolvable ID.
 */
import type { RpcContext } from "engine-shared/context";

export interface ResolvedIds {
  projectId: number | null;
  effortId: number | null;
  engineSessionId: number | null;
}

const EMPTY: ResolvedIds = { projectId: null, effortId: null, engineSessionId: null };

/**
 * Resolve cwd → project → active effort → active session.
 * Reads AGENT_ID from ctx.env for agent-specific effort resolution.
 * Returns nulls for any unresolvable link in the chain.
 */
export async function resolveEngineIds(
  cwd: string,
  ctx: RpcContext,
): Promise<ResolvedIds> {
  try {
    const { project } = await ctx.db.project.find({ path: cwd });
    if (!project) return EMPTY;

    const projectId = project.id;

    // Read AGENT_ID from per-request env (injected by rpc-cli, defaults to "default")
    const rawAgentId = ctx.env.AGENT_ID;
    const agentId = rawAgentId === "default" ? undefined : rawAgentId;

    const { effort } = await ctx.db.effort.findActive({
      projectId,
      agentId,
    });
    if (!effort) return { projectId, effortId: null, engineSessionId: null };

    const effortId = effort.id;
    const { session } = await ctx.db.session.find({ effortId });
    const engineSessionId = session?.id ?? null;

    return { projectId, effortId, engineSessionId };
  } catch {
    return EMPTY;
  }
}
