/**
 * Markdown formatting utilities for compound command output.
 *
 * All compound commands return pre-formatted markdown matching
 * the existing bash CLI output format (drop-in replacement).
 */

export interface EffortRow {
  id: number;
  taskId: string;
  skill: string;
  mode: string | null;
  ordinal: number;
  lifecycle: string;
  currentPhase: string | null;
  metadata: Record<string, unknown> | null;
  createdAt: string;
  finishedAt: string | null;
}

export interface SessionRow {
  id: number;
  taskId: string;
  effortId: number;
  prevSessionId: number | null;
  pid: number | null;
  heartbeatCounter: number;
  lastHeartbeat: string | null;
  contextUsage: number | null;
  loadedFiles: string | null;
  dehydrationPayload: Record<string, unknown> | null;
  createdAt: string;
  endedAt: string | null;
}

export interface PhaseEntry {
  label: string;
  name: string;
  steps?: string[];
  commands?: string[];
  proof?: string[];
  gate?: boolean;
}

export interface SkillRow {
  id: number;
  name: string;
  phases: PhaseEntry[] | null;
  modes: Record<string, unknown> | null;
  templates: Record<string, string> | null;
  nextSkills: string[] | null;
  directives: string[] | null;
}

export interface SearchResult {
  sourcePath: string;
  distance: number;
  chunkText?: string;
}

export interface DirectiveFile {
  path: string;
  type: "soft" | "hard";
  source: string;
}

/** Format the activation confirmation line */
export function formatConfirmation(
  sessionDir: string,
  skill: string,
  pid?: number
): string {
  const pidStr = pid ? `, pid: ${pid}` : "";
  return `Session activated: ${sessionDir} (skill: ${skill}${pidStr})`;
}

/** Format the continuation confirmation line */
export function formatContinuation(
  sessionDir: string,
  skill: string,
  phase: string
): string {
  return `Session continued: ${sessionDir}\n  Skill: ${skill}\n  Phase: ${phase}`;
}

/** Format phase info block (steps, commands, proof) */
export function formatPhaseInfo(
  skill: SkillRow,
  currentPhase: string
): string {
  if (!skill.phases) return "";
  const phase = skill.phases.find(
    (p) => `${p.label}: ${p.name}` === currentPhase
  );
  if (!phase) return "";

  const lines: string[] = [];

  if (phase.steps?.length) {
    lines.push("Steps:");
    for (const step of phase.steps) {
      const stepLabel = `${phase.label}.${phase.steps.indexOf(step) + 1}`;
      lines.push(`  ${stepLabel}: ${step}`);
    }
  }

  if (phase.commands?.length) {
    lines.push("Commands:");
    for (const cmd of phase.commands) {
      lines.push(`  - ${cmd}`);
    }
  }

  if (phase.proof?.length) {
    lines.push("Proof required to leave this phase:");
    for (const field of phase.proof) {
      lines.push(`  - ${field}`);
    }
  }

  if (phase.gate !== undefined) {
    lines.push(`Gate: ${phase.gate}`);
  }

  return lines.join("\n");
}

/** Format a ## SRC_ section with search results */
export function formatSearchSection(
  heading: string,
  results: SearchResult[]
): string {
  if (!results.length) return `## ${heading}\n(none)`;
  const items = results
    .map((r) => `  ${r.sourcePath} (${r.distance.toFixed(4)})`)
    .join("\n");
  return `## ${heading}\n${items}`;
}

/** Format directive discovery results */
export function formatDirectives(files: DirectiveFile[]): string {
  if (!files.length) return "";
  const items = files.map((f) => `  ${f.path} [${f.type}]`).join("\n");
  return `## Discovered Directives\n${items}`;
}

/** Format artifacts list for session continue */
export function formatArtifacts(artifacts: string[]): string {
  if (!artifacts.length) return "";
  return `## Artifacts\n${artifacts.map((a) => `  ${a}`).join("\n")}`;
}

/** Format next skills list */
export function formatNextSkills(skills: string[]): string {
  if (!skills.length) return "";
  return `## Next Skills\n${skills.join("\n")}`;
}

/** Format the log file path for an effort */
export function formatLogPath(
  sessionDir: string,
  skill: string
): string {
  return `${sessionDir}/${skill.toUpperCase()}_LOG.md`;
}
