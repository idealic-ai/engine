/**
 * hooks.preToolUse — Centralized PreToolUse hook logic.
 *
 * Called by the PreToolUse bash hook on every tool call. Centralizes:
 *   - Heartbeat counter management (increment, reset on engine log)
 *   - Guards.json rule evaluation (custom rules in effort metadata)
 *   - Lifecycle bypasses (finished, loading, dehydrating)
 *   - Engine command bypasses (engine log/session/*)
 *
 * Fail-open design: if effort or session not found, returns allow=true.
 * One-strike destructive guard stays in bash (pattern matching, no DB).
 * Directive discovery is out of scope (separate agents.directives.* namespace).
 *
 * Input:  hookSchema({ toolName, toolInput, toolUseId })
 *
 * Callers: PreToolUse bash hook (pre-tool-use-one-strike.sh replacement path).
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand, dispatch } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import { hookSchema } from "./hook-base-schema.js";
import { resolveEngineIds } from "./resolve-engine-ids.js";

// ── Schema ──────────────────────────────────────────────────────────

const schema = hookSchema({
  toolName: z.string(),
  toolInput: z.record(z.string(), z.unknown()),
  toolUseId: z.string(),
});

type Args = z.infer<typeof schema>;

// ── Default thresholds ──────────────────────────────────────────────

const DEFAULT_WARN_AFTER = 3;
const DEFAULT_BLOCK_AFTER = 10;

// ── Guard rule evaluation ───────────────────────────────────────────

interface GuardRule {
  ruleId: string;
  condition: {
    field: string;
    op: string;
    value: number;
  };
  payload: Record<string, unknown>;
}

interface FiredRule {
  ruleId: string;
  payload: Record<string, unknown>;
}

function evaluateGuards(
  rules: GuardRule[],
  state: Record<string, number | null>
): FiredRule[] {
  const fired: FiredRule[] = [];
  for (const rule of rules) {
    const fieldValue = state[rule.condition.field];
    if (fieldValue === null || fieldValue === undefined) continue;

    let matches = false;
    switch (rule.condition.op) {
      case "gte":
        matches = fieldValue >= rule.condition.value;
        break;
      case "gt":
        matches = fieldValue > rule.condition.value;
        break;
      case "lte":
        matches = fieldValue <= rule.condition.value;
        break;
      case "lt":
        matches = fieldValue < rule.condition.value;
        break;
      case "eq":
        matches = fieldValue === rule.condition.value;
        break;
      default:
        break;
    }

    if (matches) {
      fired.push({ ruleId: rule.ruleId, payload: rule.payload });
    }
  }
  return fired;
}

// ── Response types ──────────────────────────────────────────────────

interface HeartbeatResponse {
  allow: boolean;
  heartbeatCount: number;
  contextUsage: number | null;
  overflowWarning: boolean;
  pendingPreloads: string[];
  firedRules: FiredRule[];
  reason?: string;
  hookSpecificOutput?: {
    hookEventName: string;
    permissionDecision: "allow" | "deny";
    permissionDecisionReason?: string;
  };
}

interface SkillInterceptResponse {
  hookSpecificOutput: {
    hookEventName: string;
    permissionDecision: "allow" | "deny";
    permissionDecisionReason?: string;
    additionalContext?: string;
  };
}

type PreToolUseResponse = HeartbeatResponse | SkillInterceptResponse;

// ── Allow response builder ──────────────────────────────────────────

function allowResponse(overrides?: Record<string, unknown>): TypedRpcResponse<HeartbeatResponse> {
  return {
    ok: true,
    data: {
      allow: true,
      heartbeatCount: 0,
      contextUsage: null,
      overflowWarning: false,
      pendingPreloads: [],
      firedRules: [],
      ...overrides,
    },
  };
}

// ── Handler ─────────────────────────────────────────────────────────

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<PreToolUseResponse>> {
  // 0. Skill interception — runs BEFORE effort guard because /effort start creates efforts
  if (args.toolName === "Skill") {
    const skillName = typeof args.toolInput?.skill === "string" ? args.toolInput.skill : "";
    // Match "effort" or "ideas:effort" (plugin namespace)
    if (skillName === "effort" || skillName.endsWith(":effort")) {
      return handleEffortSkill(args, ctx);
    }
  }

  // 1. Resolve engine IDs from cwd
  const { effortId, engineSessionId } = await resolveEngineIds(args.cwd, ctx);

  // 1.5. Phase 0→1 boundary: create effort from taskName proof when no active effort
  if (!effortId && args.toolName === "Bash") {
    const bashCmd = typeof args.toolInput?.command === "string" ? args.toolInput.command : "";
    if (bashCmd.startsWith("engine session phase")) {
      await maybeCreateEffortFromProof(bashCmd, args.cwd, ctx);
      return allowResponse();
    }
  }

  if (!effortId || !engineSessionId) return allowResponse();

  // 2. Get effort row. Fail-open if not found.
  let effort: Awaited<ReturnType<typeof ctx.db.effort.get>>["effort"];
  try {
    const result = await ctx.db.effort.get({ id: effortId });
    effort = result.effort;
  } catch (e) {
    // Fail-open on DB errors
    return allowResponse();
  }
  if (!effort) {
    return allowResponse();
  }

  // Get session row
  const { session } = await ctx.db.session.get({ id: engineSessionId });
  if (!session) {
    return allowResponse();
  }

  // 3. Lifecycle bypasses
  if (effort.lifecycle === "finished") {
    return allowResponse();
  }

  const { metadata } = await ctx.db.effort.getMetadata({ id: effortId });

  if (metadata?.loading === true) {
    return allowResponse();
  }

  if (metadata?.dehydrating === true) {
    return allowResponse();
  }

  // 3. Parse tool info for critical bypasses
  const cmd = typeof args.toolInput?.command === "string" ? (args.toolInput.command as string) : "";

  if (args.toolName === "Bash" && cmd.startsWith("engine log")) {
    // Reset heartbeat counter
    await ctx.db.session.heartbeat({ sessionId: engineSessionId, action: "reset" });
    return allowResponse({ heartbeatCount: 0 });
  }

  if (args.toolName === "Bash" && cmd.startsWith("engine session")) {
    return allowResponse();
  }

  if (args.toolName === "Bash" && cmd.startsWith("engine ")) {
    return allowResponse();
  }

  // 4. Increment heartbeat counter
  const { session: updated } = await ctx.db.session.heartbeat({ sessionId: engineSessionId, action: "increment" });
  const heartbeatCount = updated.heartbeatCounter ?? 0;

  // 5. Evaluate heartbeat threshold
  const blockAfter = (metadata?.blockAfter as number) ?? DEFAULT_BLOCK_AFTER;

  if (heartbeatCount >= blockAfter) {
    return {
      ok: true,
      data: {
        allow: false,
        reason: "heartbeat-block",
        heartbeatCount,
        contextUsage: null,
        overflowWarning: false,
        pendingPreloads: [],
        firedRules: [],
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny" as const,
          permissionDecisionReason: `heartbeat-block: ${heartbeatCount}/${blockAfter} tool calls without logging`,
        },
      },
    };
  }

  // 6. Evaluate guards.json rules
  const guards = (metadata?.guards as GuardRule[]) ?? [];
  const state: Record<string, number | null> = {
    heartbeat_counter: heartbeatCount,
    context_usage: null,
  };
  const firedRules = evaluateGuards(guards, state);

  // 7. Return full response
  return {
    ok: true,
    data: {
      allow: true,
      heartbeatCount,
      contextUsage: null,
      overflowWarning: false,
      pendingPreloads: [],
      firedRules,
    },
  };
}

// ── Phase 0→1 effort creation from proof ──────────────────────────

/**
 * Parse the heredoc body from an `engine session phase` command for taskName proof.
 * If found and no active effort exists, create one via commands.effort.start.
 * Fail-open: any error silently returns (the phase command proceeds without effort).
 */
async function maybeCreateEffortFromProof(cmd: string, cwd: string, ctx: RpcContext): Promise<void> {
  try {
    // Extract JSON from heredoc: everything between <<'EOF'\n...\nEOF (or <<EOF)
    const heredocMatch = cmd.match(/<<'?EOF'?\s*\n([\s\S]*?)\nEOF/);
    if (!heredocMatch) return;

    let proof: Record<string, unknown>;
    try {
      proof = JSON.parse(heredocMatch[1].trim());
    } catch {
      return; // Not valid JSON — skip
    }

    const taskName = typeof proof.taskName === "string" ? proof.taskName : "";
    if (!taskName) return;

    // Detect skill from the phase command: `engine session phase <sessionDir> "<phase>"`
    // We need to determine which skill is active. Look for cached skill matching the session dir pattern.
    // The session dir often encodes the task name. Use the project's skills to find the right one.
    // For now, extract skill from the session dir naming convention or find the only active skill.

    // Resolve project
    const { project } = await ctx.db.project.find({ path: cwd });
    if (!project) return;

    // Find the skill name from cached skills — pick the skill that has phases matching the target phase
    const targetPhaseMatch = cmd.match(/engine session phase\s+\S+\s+"([^"]+)"/);
    const targetPhase = targetPhaseMatch ? targetPhaseMatch[1] : "";

    // Get all cached skills for this project
    const skills = await ctx.db.all<{ name: string; phases: string | null }>(
      "SELECT name, json(phases) as phases FROM skills WHERE project_id = ?",
      [project.id]
    );

    let skillName: string | null = null;
    for (const s of skills) {
      if (!s.phases) continue;
      const phases = typeof s.phases === "string" ? JSON.parse(s.phases) : s.phases;
      if (Array.isArray(phases)) {
        const match = phases.some((p: { label: string; name: string }) =>
          `${p.label}: ${p.name}` === targetPhase
        );
        if (match) {
          skillName = s.name;
          break;
        }
      }
    }
    if (!skillName) return;

    // Create effort via compound command
    const description = typeof proof.description === "string" ? proof.description : undefined;
    const keywords = typeof proof.keywords === "string" ? proof.keywords : undefined;

    await dispatch.internal({
      cmd: "commands.effort.start",
      args: {
        taskName,
        skill: skillName,
        projectPath: cwd,
        pid: process.pid,
        description,
        keywords,
      },
    }, ctx);
  } catch {
    // Fail-open — effort creation is best-effort
  }
}

// ── Effort skill interception ──────────────────────────────────────

async function handleEffortSkill(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<SkillInterceptResponse>> {
  const rawArgs = typeof args.toolInput?.args === "string" ? args.toolInput.args : "";
  const parts = rawArgs.trim().split(/\s+/);
  const subcommand = parts[0] ?? "";
  const cwd = args.cwd ?? process.cwd();

  try {
    let result: Awaited<ReturnType<typeof dispatch>>;

    // Use dispatch.internal to skip middleware (avoids nested transaction error —
    // this handler is already inside the PreToolUse dispatch's transaction).
    switch (subcommand) {
      case "start": {
        // /effort start <taskName> <skill> [--mode <mode>]
        const taskName = parts[1];
        const skill = parts[2];
        if (!taskName || !skill) {
          return effortResponse("deny", "Usage: /effort start <taskName> <skill> [--mode <mode>]");
        }
        const modeIdx = parts.indexOf("--mode");
        const mode = modeIdx >= 0 ? parts[modeIdx + 1] : undefined;
        result = await dispatch.internal({
          cmd: "commands.effort.start",
          args: { taskName, skill, projectPath: cwd, pid: process.pid, mode },
        }, ctx);
        break;
      }

      case "resume": {
        // /effort resume [<dirPath>]
        const dirPath = parts[1];
        result = await dispatch.internal({
          cmd: "commands.efforts.resume",
          args: { dirPath, projectPath: cwd },
        }, ctx);
        break;
      }

      case "log": {
        // /effort log <content...>
        const content = parts.slice(1).join(" ");
        if (!content) {
          return effortResponse("deny", "Usage: /effort log <content>");
        }
        // Need active effort's dirPath — resolve from engine IDs
        const { effortId } = await resolveEngineIds(cwd, ctx);
        if (!effortId) {
          return effortResponse("deny", "No active effort found. Start one with /effort start");
        }
        const { effort } = await ctx.db.effort.get({ id: effortId });
        if (!effort) {
          return effortResponse("deny", "Effort not found");
        }
        result = await dispatch.internal({
          cmd: "commands.log.append",
          args: { dirPath: effort.taskId, content },
        }, ctx);
        break;
      }

      default:
        return effortResponse("deny", `Unknown subcommand "${subcommand}". Use: start, resume, or log`);
    }

    if (!result.ok) {
      return effortResponse("deny", `${(result as { error?: string }).error}: ${(result as { message?: string }).message}`);
    }

    // Return the command's markdown output as additionalContext
    const markdown = (result.data as Record<string, unknown>)?.markdown;
    const context = typeof markdown === "string" ? markdown : JSON.stringify(result.data);
    return effortResponse("allow", undefined, context);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return effortResponse("deny", `Effort command failed: ${msg}`);
  }
}

function effortResponse(
  decision: "allow" | "deny",
  reason?: string,
  additionalContext?: string,
): TypedRpcResponse<SkillInterceptResponse> {
  return {
    ok: true,
    data: {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: decision,
        ...(reason ? { permissionDecisionReason: reason } : {}),
        ...(additionalContext ? { additionalContext } : {}),
      },
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "hooks.preToolUse": typeof handler;
  }
}

registerCommand("hooks.preToolUse", { schema, handler });
