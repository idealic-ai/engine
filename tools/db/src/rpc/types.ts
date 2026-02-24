/**
 * db namespace row types — camelCase interfaces as returned by db.get/db.all.
 *
 * db-wrapper.ts auto-transforms snake_case DB columns → camelCase keys and
 * auto-parses JSONB strings → JS objects. These interfaces reflect the
 * transformed shape that handlers receive.
 *
 * Handler types are registered per-file via declare module augmentation on Registered.
 */
// ── Row types (camelCase — post-transform) ───────────────

export interface Project {
  id: number;
  path: string;
  name: string | null;
  createdAt: string;
}

export interface Task {
  id: number;
  dirPath: string;
  projectId: number;
  workspace: string | null;
  title: string | null;
  description: string | null;
  createdAt: string;
}

export interface Effort {
  id: number;
  taskId: string;
  skill: string;
  mode: string | null;
  ordinal: number;
  lifecycle: string;
  currentPhase: string | null;
  metadata: Record<string, unknown> | null;
  discoveredDirectives: string[] | null;
  discoveredDirectories: string[] | null;
  createdAt: string;
  finishedAt: string | null;
}

export interface Injection {
  ruleId: string;
  content: string;
  mode: "preload" | "message";
  path?: string;
}

export interface Session {
  id: number;
  taskId: string;
  effortId: number;
  prevSessionId: number | null;
  pid: number | null;
  heartbeatCounter: number;
  heartbeatInterval: number;
  lastHeartbeat: string | null;
  contextUsage: number | null;
  loadedFiles: string[] | null;
  preloadedFiles: string[] | null;
  pendingInjections: Injection[] | null;
  discoveredDirectives: string[] | null;
  discoveredDirectories: string[] | null;
  dehydrationPayload: Record<string, unknown> | null;
  transcriptPath: string | null;
  transcriptOffset: number;
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

export interface Skill {
  id: number;
  name: string;
  projectId: number;
  phases: PhaseEntry[] | null;
  modes: Record<string, unknown> | null;
  templates: Record<string, string> | null;
  nextSkills: string[] | null;
  directives: string[] | null;
  cmdDependencies: string[] | null;
  version: string | null;
  description: string | null;
}

export interface Agent {
  id: string;
  label: string | null;
  claims: string | null;
  targetedClaims: string | null;
  manages: string | null;
  parent: string | null;
  effortId: number | null;
  status: string | null;
  createdAt: string;
}

export interface Message {
  id: number;
  sessionId: number;
  role: string;
  content: string;
  toolName: string | null;
  createdAt: string;
}

// ── Backward-compat aliases ────────────────────────────

export type ProjectRow = Project;
export type TaskRow = Task;
export type EffortRow = Effort;
export type SessionRow = Session;
export type SkillRow = Skill;
export type AgentRow = Agent;
export type MessageRow = Message;
