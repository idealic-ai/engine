/**
 * commands.effort.start — Compound command to start a new skill effort.
 *
 * Orchestrates multiple db.* and agent.* RPCs into a single user-facing command.
 * Replaces the bash `engine session activate` compound flow.
 *
 * Flow:
 *   1. db.project.upsert — ensure project exists
 *   2. db.task.upsert — ensure task exists
 *   3. db.skills.get — fetch cached skill data
 *   4. db.effort.start — create effort with atomic ordinal
 *   5. db.session.start — create context window
 *   6. db.agents.register — bind agent to effort (if agentId provided)
 *   7. db.effort.list — find prior effort debriefs for cross-effort context
 *   8. agent.directives.discover — find directive files
 *   9. search.query (×2) — session + doc RAG (if embedding provided)
 *  10. Format markdown output
 *
 * Design: calls dispatch() internally to invoke RPCs. No direct DB access.
 * FS I/O only for reading prior effort debrief files (step 7).
 */
import * as fs from "node:fs";
import * as path from "node:path";
import { z } from "zod/v4";
import { registerCommand, dispatch } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import {
  formatConfirmation,
  formatPhaseInfo,
  formatSearchSection,
  formatDirectives,
  formatNextSkills,
  formatLogPath,
  type EffortRow,
  type SessionRow,
  type SkillRow,
  type SearchResult,
  type DirectiveFile,
} from "../format.js";

const schema = z.object({
  taskName: z.string(),
  skill: z.string(),
  projectPath: z.string(),
  agentId: z.string().optional(),
  pid: z.number().optional(),
  mode: z.string().optional(),
  description: z.string().optional(),
  keywords: z.string().optional(),
  metadata: z.record(z.string(), z.unknown()).optional(),
  directoriesOfInterest: z.array(z.string()).optional(),
  directivePatterns: z.array(z.string()).optional(),
  embedding: z.array(z.number()).optional(),
  skipSearch: z.boolean().optional(),
});

type Args = z.infer<typeof schema>;

interface EffortStartData {
  effort: EffortRow;
  session: SessionRow;
  skill: SkillRow | null;
  markdown: string;
  resumed?: boolean;
}

export async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<EffortStartData>> {
  // Track created entities for rollback on failure
  let createdEffortId: number | null = null;
  let createdSessionId: number | null = null;

  // Derive dirPath from taskName
  const dirPath = path.join(args.projectPath, ".tasks", args.taskName.toLowerCase());

  try {
    // 1. Ensure project
    const projData = await ctx.db.project.upsert({ path: args.projectPath });

    // 2. Ensure task
    const projectId = projData.project.id;
    await ctx.db.task.upsert({
      dirPath,
      projectId,
      title: args.taskName,
      description: args.description,
      keywords: args.keywords,
    });

    // 3. Fetch cached skill data (graceful — null skill is OK)
    let skill: SkillRow | null = null;
    try {
      const skillData = await ctx.db.skills.get({
        name: args.skill,
        projectId,
      });
      skill = skillData.skill;
    } catch {
      // Skill not cached — continue without phase/nextSkills info
    }

    // 3.5. Check for existing active effort on same task+skill (inform and resume)
    try {
      const effortListData = await ctx.db.effort.list({ taskId: dirPath });
      const efforts = (effortListData.efforts as EffortRow[]) ?? [];
      const activeEffort = efforts.find(
        (e) => e.skill === args.skill && e.lifecycle === "active"
      );
      if (activeEffort) {
        // Resume: create a new session linked to this effort, return it
        const sessionData = await ctx.db.session.start({
          taskId: dirPath,
          effortId: activeEffort.id,
          pid: args.pid,
        });
        const session = sessionData.session;
        if (args.agentId) {
          await ctx.db.agents.register({ id: args.agentId, effortId: activeEffort.id });
        }
        const firstPhase = getFirstPhase(skill);
        const logPath = formatLogPath(dirPath, args.skill);
        const sections: string[] = [
          formatConfirmation(dirPath, args.skill, args.pid),
          "",
          `  Log: ${logPath}`,
        ];
        if (firstPhase) {
          sections.push("");
          sections.push(formatPhaseInfo(skill!, firstPhase));
        }
        return {
          ok: true,
          data: { effort: activeEffort, session, skill, markdown: sections.join("\n"), resumed: true },
        };
      }
    } catch {
      // List failed — proceed with normal creation
    }

    // 4. Create effort
    const effortData = await ctx.db.effort.start({
      taskId: dirPath,
      skill: args.skill,
      mode: args.mode,
      metadata: args.metadata,
    });
    const effort = effortData.effort;
    createdEffortId = effort.id;

    // 5. Create session
    const sessionData = await ctx.db.session.start({
      taskId: dirPath,
      effortId: effort.id,
      pid: args.pid,
    });
    const session = sessionData.session;
    createdSessionId = session.id;

    // 6. Bind agent (if provided)
    if (args.agentId) {
      await ctx.db.agents.register({
        id: args.agentId,
        effortId: effort.id,
      });
    }

    // 7. Find prior effort debriefs for cross-effort context
    const priorDebriefs = await findPriorDebriefs(dirPath, effort.ordinal, ctx);

    // 8. Discover directives (graceful — empty on failure)
    let directives: DirectiveFile[] = [];
    if (args.directoriesOfInterest?.length) {
      const dirResult = await dispatch({
        cmd: "agent.directives.discover",
        args: {
          dirs: args.directoriesOfInterest,
          patterns: args.directivePatterns,
          root: args.projectPath,
        },
      }, ctx);
      if (dirResult.ok) {
        directives = (dirResult.data.files as DirectiveFile[]) ?? [];
      }
    }

    // 9. RAG search (if embedding provided and not skipped)
    let sessionResults: SearchResult[] = [];
    let docResults: SearchResult[] = [];
    if (args.embedding && !args.skipSearch) {
      const [sessRes, docRes] = await Promise.all([
        dispatch({
          cmd: "search.query",
          args: { embedding: args.embedding, sourceTypes: ["session"], limit: 5 },
        }, ctx),
        dispatch({
          cmd: "search.query",
          args: { embedding: args.embedding, sourceTypes: ["doc"], limit: 5 },
        }, ctx),
      ]);
      if (sessRes.ok) sessionResults = (sessRes.data.results as SearchResult[]) ?? [];
      if (docRes.ok) docResults = (docRes.data.results as SearchResult[]) ?? [];
    }

    // 10. Format markdown output
    const firstPhase = getFirstPhase(skill);
    const logPath = formatLogPath(dirPath, args.skill);

    const sections: string[] = [
      formatConfirmation(dirPath, args.skill, args.pid),
      "",
      `  Log: ${logPath}`,
    ];

    if (firstPhase) {
      sections.push("");
      sections.push(formatPhaseInfo(skill!, firstPhase));
    }

    if (priorDebriefs.length) {
      sections.push("");
      sections.push("## Prior Efforts");
      for (const d of priorDebriefs) {
        sections.push(`  ${d}`);
      }
    }

    sections.push("");
    sections.push(formatSearchSection("SRC_PRIOR_SESSIONS", sessionResults));
    sections.push("");
    sections.push(formatSearchSection("SRC_RELEVANT_DOCS", docResults));

    if (directives.length) {
      sections.push("");
      sections.push(formatDirectives(directives));
    }

    if (skill?.nextSkills) {
      const nextSkills = skill.nextSkills ?? [];
      if (nextSkills.length) {
        sections.push("");
        sections.push(formatNextSkills(nextSkills));
      }
    }

    const markdown = sections.join("\n");

    return {
      ok: true,
      data: {
        effort,
        session,
        skill,
        markdown,
      },
    };
  } catch (err: unknown) {
    // Rollback: clean up any entities created before the failure
    await rollback(createdSessionId, createdEffortId, ctx);
    const message = err instanceof Error ? err.message : String(err);
    return { ok: false, error: "COMMAND_ERROR", message };
  }
}

/** Clean up partially-created entities on failure */
async function rollback(
  sessionId: number | null,
  effortId: number | null,
  ctx: RpcContext
): Promise<void> {
  // End session first (FK dependency: session → effort)
  if (sessionId != null) {
    try {
      await ctx.db.session.finish({ sessionId });
    } catch { /* best-effort cleanup */ }
  }
  // Then finish the effort
  if (effortId != null) {
    try {
      await ctx.db.effort.finish({ effortId });
    } catch { /* best-effort cleanup */ }
  }
}

/** Find debrief files from prior efforts on the same task */
async function findPriorDebriefs(
  dirPath: string,
  currentOrdinal: number,
  ctx: RpcContext
): Promise<string[]> {
  let efforts: EffortRow[];
  try {
    const listData = await ctx.db.effort.list({ taskId: dirPath });
    efforts = (listData.efforts as EffortRow[]) ?? [];
  } catch {
    return [];
  }
  const debriefs: string[] = [];

  for (const e of efforts) {
    if (e.ordinal >= currentOrdinal) continue;
    if (e.lifecycle !== "finished") continue;

    // Convention: {ordinal}_{SKILL_UPPER}.md
    const debriefName = `${e.ordinal}_${e.skill.toUpperCase()}.md`;
    const debriefPath = path.join(dirPath, debriefName);
    try {
      fs.accessSync(debriefPath, fs.constants.R_OK);
      debriefs.push(debriefName);
    } catch {
      // Debrief doesn't exist — skip
    }
  }

  return debriefs;
}

/** Get the first phase label from skill data */
function getFirstPhase(skill: SkillRow | null): string | null {
  if (!skill?.phases) return null;
  const phases = skill.phases ?? [];
  if (!phases.length) return null;
  return `${phases[0].label}: ${phases[0].name}`;
}

registerCommand("commands.effort.start", { schema, handler });

declare module "engine-shared/rpc-types" {
  interface Registered {
    "commands.effort.start": typeof handler;
  }
}
