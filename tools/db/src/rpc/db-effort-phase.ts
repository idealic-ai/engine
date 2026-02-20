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
import type { Database } from "sql.js";
import { z } from "zod/v4";
import { registerCommand, type RpcResponse } from "./dispatch.js";
import { getEffortRow, getActiveSession, getSkillRow } from "./row-helpers.js";

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

function handler(args: Args, db: Database): RpcResponse {
  const effort = getEffortRow(db, args.effortId);
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

  const currentPhase = effort.current_phase as string | null;

  // Re-entering the same phase = true no-op
  if (currentPhase === args.phase) {
    const session = getActiveSession(db, args.effortId);
    return { ok: true, data: { effort, session } };
  }

  // Phase enforcement: read phases from skills table
  const taskId = effort.task_id as string;
  const task = db.exec("SELECT project_id FROM tasks WHERE dir_path = ?", [taskId]);
  if (task.length === 0 || task[0].values.length === 0) {
    return { ok: false, error: "TASK_NOT_FOUND", message: `Task ${taskId} not found` };
  }
  const projectId = task[0].values[0][0] as number;
  const skillName = effort.skill as string;
  const skillRow = getSkillRow(db, projectId, skillName);

  let phases: PhaseEntry[] | undefined;
  if (skillRow && skillRow.phases) {
    // JSONB — read via json()
    const phasesResult = db.exec(
      "SELECT json(phases) as phases FROM skills WHERE id = ?",
      [skillRow.id as number]
    );
    if (phasesResult.length > 0 && phasesResult[0].values[0][0]) {
      phases = JSON.parse(phasesResult[0].values[0][0] as string);
    }
  }

  // Also check effort metadata for phases (fallback)
  if (!phases && effort.metadata) {
    const metaResult = db.exec(
      "SELECT json(metadata) as metadata FROM efforts WHERE id = ?",
      [args.effortId]
    );
    if (metaResult.length > 0 && metaResult[0].values[0][0]) {
      const meta = JSON.parse(metaResult[0].values[0][0] as string);
      phases = meta.phases;
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

  db.exec("BEGIN");
  try {
    // Update effort phase
    db.run(
      "UPDATE efforts SET current_phase = ? WHERE id = ?",
      [args.phase, args.effortId]
    );

    // Append to phase_history (FK → efforts)
    db.run(
      "INSERT INTO phase_history (effort_id, phase_label, proof) VALUES (?, ?, jsonb(?))",
      [
        args.effortId,
        args.phase,
        args.proof ? JSON.stringify(args.proof) : null,
      ]
    );

    // Reset heartbeat counter on active session for this effort
    db.run(
      `UPDATE sessions SET heartbeat_counter = 0, last_heartbeat = datetime('now')
       WHERE effort_id = ? AND ended_at IS NULL`,
      [args.effortId]
    );

    // Update skill phases if auto-appended
    if (phasesModified && skillRow) {
      db.run(
        "UPDATE skills SET phases = jsonb(?), updated_at = datetime('now') WHERE id = ?",
        [JSON.stringify(phases), skillRow.id as number]
      );
    }

    const updatedEffort = getEffortRow(db, args.effortId);
    const session = getActiveSession(db, args.effortId);

    db.exec("COMMIT");
    return { ok: true, data: { effort: updatedEffort, session } };
  } catch (err: unknown) {
    db.exec("ROLLBACK");
    throw err;
  }
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

registerCommand("db.effort.phase", { schema, handler });
