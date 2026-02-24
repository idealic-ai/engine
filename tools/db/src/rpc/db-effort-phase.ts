/**
 * db.effort.phase — Phase transition with sequential enforcement.
 *
 * The most complex RPC in the daemon. Implements the phase enforcement engine
 * that ensures skills progress through their declared phases in order.
 *
 * Enforcement rules:
 *   - Sequential forward (N → N+1): always allowed
 *   - Re-enter same phase: true no-op (returns current state)
 *   - Skip forward or go backward: requires `reason` (= --user-approved)
 *   - Sub-phase skip (N.X → (N+1).0): allowed without approval
 *   - Unknown phase: rejected unless auto-appendable as sub-phase
 *
 * Sub-phase auto-append: If the target phase isn't declared but matches
 * pattern N.M (same major, higher minor than current), it's spliced into
 * the phases array. Enables dynamic sub-phases without pre-declaration.
 *
 * Phase source resolution (two-level fallback):
 *   1. Skills table (cached SKILL.md parse) — primary
 *   2. Effort metadata.phases — fallback for skills without DB cache
 *
 * Side effects on successful transition:
 *   - Updates effort.current_phase
 *   - Appends to phase_history (audit trail, FK → efforts not tasks)
 *   - Resets heartbeat_counter on active session (fresh count per phase)
 *   - Updates skills table if phases were auto-appended
 *
 * Callers: bash `engine session phase` compound command.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "./dispatch.js";
import type { TypedRpcResponse } from "engine-shared/rpc-types";
import type { EffortRow, SkillRow, SessionRow } from "./types.js";

const schema = z.object({
  effortId: z.number(),
  phase: z.string(),
  proof: z.record(z.string(), z.unknown()).optional(),
  reason: z.string().optional(), // presence = user-approved for non-sequential
});

type Args = z.infer<typeof schema>;

interface PhaseEntry {
  label: string;
  name: string;
}

async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ effort: EffortRow; session: SessionRow | null }>> {
  const db = ctx.db;
  const effort = await db.get<EffortRow>("SELECT * FROM efforts WHERE id = ?", [args.effortId]);
  if (!effort) {
    return {
      ok: false,
      error: "NOT_FOUND",
      message: `Effort ${args.effortId} not found`,
    };
  }

  if (effort.lifecycle === "finished") {
    return {
      ok: false,
      error: "EFFORT_FINISHED",
      message: `Effort ${args.effortId} is already finished`,
    };
  }

  const currentPhase = effort.currentPhase;

  // Re-entering the same phase = true no-op
  if (currentPhase === args.phase) {
    const session = await db.get<SessionRow>(
      "SELECT * FROM sessions WHERE effort_id = ? AND ended_at IS NULL ORDER BY id DESC LIMIT 1",
      [args.effortId]
    );
    return { ok: true, data: { effort: effort!, session: session ?? null } };
  }

  // Phase enforcement: read phases from skills table
  const taskId = effort.taskId;
  const taskRow = await db.get<{ projectId: number }>("SELECT project_id as project_id FROM tasks WHERE dir_path = ?", [taskId]);
  if (!taskRow) {
    return { ok: false, error: "TASK_NOT_FOUND", message: `Task ${taskId} not found` };
  }
  const projectId = taskRow.projectId;
  const skillName = effort.skill;
  const skillRow = await db.get<SkillRow>(
    "SELECT * FROM skills WHERE project_id = ? AND name = ?",
    [projectId, skillName]
  );

  let phases: PhaseEntry[] | undefined;
  if (skillRow && skillRow.phases) {
    // JSONB — read via json(); db-wrapper auto-parses the JSON string
    const phasesRow = await db.get<{ phases: unknown }>(
      "SELECT json(phases) as phases FROM skills WHERE id = ?",
      [skillRow.id]
    );
    if (phasesRow?.phases) {
      phases = phasesRow.phases as PhaseEntry[];
    }
  }

  // Also check effort metadata for phases (fallback)
  if (!phases && effort.metadata) {
    const metaRow = await db.get<{ metadata: Record<string, unknown> | null }>(
      "SELECT json(metadata) as metadata FROM efforts WHERE id = ?",
      [args.effortId]
    );
    if (metaRow?.metadata) {
      phases = metaRow.metadata.phases as PhaseEntry[] | undefined;
    }
  }

  // Track whether we need to update skill phases (auto-append)
  let phasesModified = false;

  if (phases && phases.length > 0) {
    const currentIndex = currentPhase
      ? phases.findIndex((p) => phaseLabel(p) === currentPhase)
      : -1;
    const targetIndex = phases.findIndex((p) => phaseLabel(p) === args.phase);

    if (targetIndex === -1) {
      const autoAppended = tryAutoAppendSubPhase(phases, args.phase, currentIndex);
      if (autoAppended) {
        phasesModified = true;
      } else {
        return {
          ok: false,
          error: "UNKNOWN_PHASE",
          message: `Phase '${args.phase}' not found in declared phases`,
        };
      }
    } else {
      const expectedNext = currentIndex + 1;
      const isSubPhaseSkip = isAllowedSubPhaseSkip(phases, currentIndex, targetIndex);

      if (targetIndex !== expectedNext && !isSubPhaseSkip && !args.reason) {
        const expectedLabel =
          expectedNext < phases.length ? phaseLabel(phases[expectedNext]) : "(end)";
        return {
          ok: false,
          error: "PHASE_NOT_SEQUENTIAL",
          message: `Expected '${expectedLabel}', got '${args.phase}'. Use reason field for non-sequential transitions.`,
          details: { expected: expectedLabel, actual: args.phase },
        };
      }
    }
  }

    // Update effort phase
    await db.run(
      "UPDATE efforts SET current_phase = ? WHERE id = ?",
      [args.phase, args.effortId]
    );

    // Append to phase_history (FK → efforts)
    await db.run(
      "INSERT INTO phase_history (effort_id, phase_label, proof) VALUES (?, ?, json(?))",
      [
        args.effortId,
        args.phase,
        args.proof ? JSON.stringify(args.proof) : null,
      ]
    );

    // Reset heartbeat counter on active session for this effort
    await db.run(
      `UPDATE sessions SET heartbeat_counter = 0, last_heartbeat = datetime('now')
       WHERE effort_id = ? AND ended_at IS NULL`,
      [args.effortId]
    );

    // Update skill phases if auto-appended
    if (phasesModified && skillRow) {
      await db.run(
        "UPDATE skills SET phases = json(?), updated_at = datetime('now') WHERE id = ?",
        [JSON.stringify(phases), skillRow.id]
      );
    }

    const updatedEffort = await db.get<EffortRow>("SELECT * FROM efforts WHERE id = ?", [args.effortId]);
    const session = await db.get<SessionRow>(
      "SELECT * FROM sessions WHERE effort_id = ? AND ended_at IS NULL ORDER BY id DESC LIMIT 1",
      [args.effortId]
    );

    return { ok: true, data: { effort: updatedEffort!, session: session ?? null } };

}

// ── Phase label utilities ───────────────────────────────
// Phase entries have { label: "2.A", name: "Operation" } → "2.A: Operation".
// parsePhaseParts extracts major.minor numbers for enforcement comparison.
// Letter labels (A, B, C) are converted to numeric minor values (1, 2, 3).

function phaseLabel(entry: PhaseEntry): string {
  return `${entry.label}: ${entry.name}`;
}

function parsePhaseParts(label: string): { major: number; minor: number } | null {
  const labelPart = label.split(":")[0].trim();
  const parts = labelPart.split(".");
  const major = parseInt(parts[0], 10);
  if (isNaN(major)) return null;
  if (parts.length === 1) return { major, minor: 0 };
  const minorPart = parts[1];
  if (/^[A-Z]$/.test(minorPart)) {
    return { major, minor: minorPart.charCodeAt(0) - 64 };
  }
  const numericMinor = parseInt(minorPart.replace(/[A-Z]$/, ""), 10);
  return { major, minor: isNaN(numericMinor) ? 0 : numericMinor };
}

// ── Sub-phase auto-append ────────────────────────────────
// When a target phase like "3.A: Operation" isn't in the declared phases array,
// check if it qualifies as an auto-appendable sub-phase: same major number as
// current phase, higher minor number. If so, splice it into the array at the
// right position. This enables skills to declare major phases upfront and let
// sub-phases appear dynamically during execution.

function tryAutoAppendSubPhase(
  phases: PhaseEntry[],
  targetPhaseStr: string,
  currentIndex: number
): boolean {
  const targetParts = parsePhaseParts(targetPhaseStr);
  if (!targetParts || targetParts.minor === 0) return false;
  if (currentIndex >= 0) {
    const currentLabel = phaseLabel(phases[currentIndex]);
    const currentParts = parsePhaseParts(currentLabel);
    if (!currentParts || currentParts.major !== targetParts.major) return false;
    if (targetParts.minor <= currentParts.minor) return false;
  }
  const colonIdx = targetPhaseStr.indexOf(":");
  const name = colonIdx >= 0 ? targetPhaseStr.slice(colonIdx + 2).trim() : targetPhaseStr;
  const labelPart = colonIdx >= 0 ? targetPhaseStr.slice(0, colonIdx).trim() : targetPhaseStr;
  let insertIdx = phases.length;
  for (let i = phases.length - 1; i >= 0; i--) {
    const p = parsePhaseParts(phaseLabel(phases[i]));
    if (p && p.major === targetParts.major) {
      insertIdx = i + 1;
      break;
    }
  }
  phases.splice(insertIdx, 0, { label: labelPart, name });
  return true;
}

// ── Sub-phase skip rules ─────────────────────────────────
// Sub-phases are optional execution paths, not mandatory steps.
// Skipping from N.X → (N+1).0 is always allowed (exit sub-phase to next major).
// This means choosing inline execution (3.A) doesn't block reaching synthesis (4.0)
// even if agent handoff (3.B) is declared between them.

function isAllowedSubPhaseSkip(
  phases: PhaseEntry[],
  currentIndex: number,
  targetIndex: number
): boolean {
  if (currentIndex < 0 || targetIndex <= currentIndex) return false;
  const currentParts = parsePhaseParts(phaseLabel(phases[currentIndex]));
  const targetParts = parsePhaseParts(phaseLabel(phases[targetIndex]));
  if (!currentParts || !targetParts) return false;
  if (targetParts.major === currentParts.major + 1 && targetParts.minor === 0) return true;
  if (currentParts.minor === 0 && targetParts.major === currentParts.major + 1 && targetParts.minor === 0) return true;
  return false;
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "db.effort.phase": typeof handler;
  }
}

registerCommand("db.effort.phase", { schema, handler });
