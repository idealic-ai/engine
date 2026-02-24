/**
 * commands.efforts.resume — Effort resumption after context overflow.
 *
 * Efforts are the resumable entity (not sessions). When context overflows,
 * the old session ends but the effort persists. This command creates a new
 * session for the effort and returns context for the agent to resume.
 *
 * Flow:
 *   1. Find the relevant effort (by agentId or dirPath)
 *   2. Get effort + skill data
 *   3. Extract dehydration payload (if overflow recovery)
 *   4. db.session.start — new session with prev_session_id
 *   5. db.session.heartbeat — reset counter
 *   6. List session artifacts from FS
 *   7. Format continuation markdown
 */
import * as fs from "node:fs";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import {
  formatContinuation,
  formatArtifacts,
  formatNextSkills,
  formatLogPath,
  type EffortRow,
  type SessionRow,
  type SkillRow,
} from "../format.js";

const schema = z.object({
  dirPath: z.string().optional(),
  agentId: z.string().optional(),
  projectPath: z.string(),
}).refine(
  (args) => args.dirPath || args.agentId,
  { message: "Either dirPath or agentId is required" }
);

type Args = z.infer<typeof schema>;

interface EffortResumeData {
  session: SessionRow;
  effort: EffortRow;
  dehydration: Record<string, unknown> | null;
  markdown: string;
}

export async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<EffortResumeData>> {
  try {
    // 1. Find the relevant effort's last session
    let prevSession: SessionRow | null = null;
    let effort: EffortRow | null = null;
    let taskDir: string;

    if (args.agentId) {
      // Find via agent → effort → session
      const agentData = await ctx.db.agents.get({ id: args.agentId });
      const agent = agentData.agent;
      if (!agent?.effortId) {
        return { ok: false, error: "NO_ACTIVE_EFFORT", message: "No active effort found for agent" };
      }

      // Agent's effort_id points directly to efforts.id — use session query
      const sessionData = await ctx.db.session.find({ effortId: agent.effortId });
      prevSession = sessionData.session;
      if (!prevSession) {
        return { ok: false, error: "NO_ACTIVE_EFFORT", message: "No session found for agent's effort" };
      }
      taskDir = prevSession.taskId;
    } else {
      taskDir = args.dirPath!;
      // Find efforts for this task, then find the session for the most recent one
      const effortListData = await ctx.db.effort.list({ taskId: taskDir });
      const efforts = (effortListData.efforts as EffortRow[]) ?? [];
      if (!efforts.length) {
        return { ok: false, error: "NO_ACTIVE_EFFORT", message: `No efforts found for ${taskDir}` };
      }
      // Pick the most recent effort (last by ordinal)
      effort = efforts[efforts.length - 1];

      // Try to find active session (may be null if already ended by overflow)
      try {
        const sessionData = await ctx.db.session.find({ effortId: effort.id });
        prevSession = sessionData.session;
      } catch {
        // prevSession may be null — that's OK for overflow recovery
      }
    }

    // 2. Get effort data (if not already resolved via dirPath path above)
    if (!effort) {
      const effortListData = await ctx.db.effort.list({ taskId: taskDir });
      const efforts = (effortListData.efforts as EffortRow[]) ?? [];
      effort = efforts.find((e) => e.id === prevSession!.effortId) ?? null;
      if (!effort) {
        return { ok: false, error: "NO_ACTIVE_EFFORT", message: "Effort not found for session" };
      }
    }

    // Get skill data
    const projData = await ctx.db.project.upsert({ path: args.projectPath });
    const projectId = projData.project.id;
    let skill: SkillRow | null = null;
    try {
      const skillData = await ctx.db.skills.get({ name: effort.skill, projectId });
      skill = skillData.skill;
    } catch {
      // Skill not cached — continue without
    }

    // 3. Extract dehydration payload from previous session (if available)
    const dehydration = prevSession?.dehydrationPayload
      ? prevSession.dehydrationPayload as Record<string, unknown>
      : null;

    // 4. Create new session with continuation link
    // db.session.start auto-ends any active session for the same effort
    const newSessionData = await ctx.db.session.start({
      taskId: taskDir,
      effortId: effort.id,
      ...(prevSession ? { prevSessionId: prevSession.id } : {}),
    });
    const newSession = newSessionData.session;

    // 5. Heartbeat
    await ctx.db.session.heartbeat({ sessionId: newSession.id });

    // 6. List session artifacts from FS
    const artifacts = listArtifacts(taskDir);

    // 7. Format continuation markdown
    const currentPhase = effort.currentPhase ?? "0: Setup";
    const logPath = formatLogPath(taskDir, effort.skill);
    const nextSkills = skill?.nextSkills ?? [];

    const sections: string[] = [
      formatContinuation(taskDir, effort.skill, currentPhase),
      `  Log: ${logPath}`,
    ];

    if (artifacts.length) {
      sections.push("");
      sections.push(formatArtifacts(artifacts));
    }

    if (nextSkills.length) {
      sections.push("");
      sections.push(formatNextSkills(nextSkills));
    }

    const markdown = sections.join("\n");

    return {
      ok: true,
      data: {
        session: newSession,
        effort,
        dehydration,
        markdown,
      },
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return { ok: false, error: "COMMAND_ERROR", message };
  }
}

/** List .md artifacts in a session directory */
function listArtifacts(dirPath: string): string[] {
  try {
    const entries = fs.readdirSync(dirPath);
    return entries
      .filter((e) => e.endsWith(".md") && !e.startsWith("."))
      .sort();
  } catch {
    return [];
  }
}

registerCommand("commands.efforts.resume", { schema, handler });

declare module "engine-shared/rpc-types" {
  interface Registered {
    "commands.efforts.resume": typeof handler;
  }
}
