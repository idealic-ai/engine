/**
 * E2E test helpers — invokes real Claude CLI with --plugin-dir
 * to test the full hook pipeline end-to-end.
 *
 * Pipeline: claude CLI → hooks.json → engine-rpc → daemon → RPC handler → response
 */
import { spawn, execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, mkdirSync, writeFileSync, readFileSync, existsSync, realpathSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

// ── Constants ────────────────────────────────────────────────

/** Root of the tools directory — also the plugin directory (contains hooks.json, bin/, plugin/skills/) */
const TOOLS_DIR = join(import.meta.dirname, "../..");

/** Plugin directory for --plugin-dir flag (same as TOOLS_DIR — tools/ IS the plugin root) */
const PLUGIN_DIR = TOOLS_DIR;

/** Claude CLI binary — assumes `claude` is on PATH */
const CLAUDE_BIN = "claude";

/** Default model for e2e tests */
const DEFAULT_MODEL = "claude-sonnet-4-6";

/** Max spend per invocation (sonnet needs more budget for tool-use tests) */
const DEFAULT_BUDGET = "2.00";

/** Default timeout for claude invocations (ms) — 90s for concurrent sonnet */
const DEFAULT_TIMEOUT = 90_000;

// ── Types ────────────────────────────────────────────────────

export interface RunClaudeOptions {
  /** Model override (default: haiku) */
  model?: string;
  /** Max budget in USD (default: 0.10) */
  maxBudget?: string;
  /** Timeout in ms (default: 60s) */
  timeout?: number;
  /** Extra env vars to set */
  env?: Record<string, string>;
  /** Working directory override */
  cwd?: string;
  /** JSON Schema for structured output — forces --output-format json */
  jsonSchema?: Record<string, unknown>;
  /** Extra CLI flags to append */
  extraArgs?: string[];
}

export interface RunClaudeResult {
  stdout: string;
  stderr: string;
  exitCode: number;
  /** Extracted system-reminder blocks from stdout */
  systemReminders: string[];
  /** Raw duration in ms */
  durationMs: number;
}

// ── Universal Debug Schema ────────────────────────────────────

/**
 * Base JSON schema for structured Claude output. Every e2e test uses this
 * (or an extension of it) to probe what hooks injected into Claude's context.
 *
 * Usage: `runClaudeJson(DEBUG_PROMPT, debugSchema())` for base,
 *        `runClaudeJson(DEBUG_PROMPT, debugSchema({ extra fields }))` for extensions.
 */
export const BASE_DEBUG_SCHEMA = {
  type: "object" as const,
  properties: {
    hookEventsFired: {
      type: "array",
      items: { type: "string", enum: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart", "Stop", "none"] },
      description: "Which hook event names appear in system-reminder tags in your context? List each unique hook event name. Use 'none' if no hook events are visible.",
    },
    sessionContextLine: {
      type: "string",
      description: "Copy the EXACT '[Session Context] ...' line from your context. If no such line exists, write 'none'.",
    },
    skillName: {
      type: "string",
      description: "The skill name from the [Session Context] line (e.g. 'implement', 'test'). Write 'none' if no session context exists.",
    },
    currentPhase: {
      type: "string",
      description: "The phase value from the [Session Context] line (e.g. 'none', '2.A: Testing Loop'). Write 'none' if no session context exists.",
    },
    preloadedFiles: {
      type: "array",
      items: { type: "string" },
      description: "List ALL file paths from [Preloaded: /path/to/file] markers in your context. Empty array if none.",
    },
    directiveFiles: {
      type: "array",
      items: { type: "string" },
      description: "List file paths from .directives/ folders mentioned in your context. Empty array if none.",
    },
    pluginSkillsDiscovered: {
      type: "array",
      items: { type: "string" },
      description: "List any plugin-specific skill names (NOT standard Claude skills) you see available. 'effort' would be a plugin skill. Empty array if none.",
    },
    systemReminderCount: {
      type: "number",
      description: "How many <system-reminder> blocks are present in your context? Count them all.",
    },
  },
  required: [
    "hookEventsFired", "sessionContextLine", "skillName", "currentPhase",
    "preloadedFiles", "directiveFiles", "pluginSkillsDiscovered", "systemReminderCount",
  ],
};

/** TypeScript interface matching BASE_DEBUG_SCHEMA */
export interface DebugReport {
  hookEventsFired: string[];
  sessionContextLine: string;
  skillName: string;
  currentPhase: string;
  preloadedFiles: string[];
  directiveFiles: string[];
  pluginSkillsDiscovered: string[];
  systemReminderCount: number;
  [key: string]: unknown; // allow extensions
}

/**
 * Build a debug schema, optionally extending with extra properties.
 * Extra properties are merged into the base schema.
 */
export function debugSchema(
  extra?: Record<string, unknown>,
  extraRequired?: string[],
): Record<string, unknown> {
  if (!extra) return BASE_DEBUG_SCHEMA;
  return {
    ...BASE_DEBUG_SCHEMA,
    properties: { ...BASE_DEBUG_SCHEMA.properties, ...extra },
    required: [...BASE_DEBUG_SCHEMA.required, ...(extraRequired ?? Object.keys(extra))],
  };
}

/** Standard prompt that pairs with the debug schema */
export const DEBUG_PROMPT = `Inspect your ENTIRE context window carefully. Report ALL of the following:
1. Which hook event names appear in <system-reminder> tags? (SessionStart, PreToolUse, etc.)
2. Is there a [Session Context] line? If so, copy it exactly.
3. What skill and phase are mentioned in the session context?
4. List ALL [Preloaded: ...] file paths.
5. List ALL .directives/ file paths mentioned.
6. Are there any plugin-specific skills (like 'effort') available beyond the standard set?
7. Count the total number of <system-reminder> blocks.
Be thorough and precise. Report 'none' or empty arrays when items are absent.`;

// ── Temp directory management ─────────────────────────────────

let tempSessionsDir: string | null = null;
let tempProjectDir: string | null = null;
const isolatedProjects: string[] = [];

/**
 * Scaffold a project directory with .claude/settings.json containing native hooks.
 * Native hooks work around the plugin additionalContext bug (#16538).
 */
function scaffoldProjectDir(projectDir: string): void {
  const engineRpcAbsolute = join(TOOLS_DIR, "bin/engine-rpc");
  const claudeDir = join(projectDir, ".claude");
  mkdirSync(claudeDir, { recursive: true });

  const realProjectDir = process.cwd();
  const debugLog = join(projectDir, "hook-debug.log");
  const wrapperScript = join(projectDir, "hook-wrapper.sh");
  writeFileSync(wrapperScript, [
    "#!/bin/bash",
    `export CLAUDE_PROJECT_DIR="${realProjectDir}"`,
    `export CLAUDE_PLUGIN_ROOT="${TOOLS_DIR}"`,
    `HOOK_EVENT="$1"; shift`,
    `STDIN_DATA=$(cat)`,
    `TOOL=$(echo "$STDIN_DATA" | grep -o '"tool_name":"[^"]*"' | head -1)`,
    `echo "[$(date +%H:%M:%S)] $HOOK_EVENT $TOOL" >> "${debugLog}"`,
    `RESULT=$(echo "$STDIN_DATA" | "${engineRpcAbsolute}" "$@" 2>"${debugLog}.err")`,
    `ERR=$(cat "${debugLog}.err" 2>/dev/null)`,
    `echo "[$(date +%H:%M:%S)] $HOOK_EVENT result: \${RESULT:0:200} err: \${ERR:0:200}" >> "${debugLog}"`,
    `echo "$RESULT"`,
  ].join("\n"), { mode: 0o755 });

  const hookEvents = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PostToolUseFailure", "Stop", "SubagentStart", "SubagentStop",
  ];
  const hooks: Record<string, unknown[]> = {};
  for (const event of hookEvents) {
    const cmdName = `hooks.${event.charAt(0).toLowerCase() + event.slice(1)}`;
    hooks[event] = [{
      matcher: "",
      hooks: [{
        type: "command",
        command: `${wrapperScript} ${event} ${cmdName}`,
        timeout: 10,
      }],
    }];
  }

  writeFileSync(
    join(claudeDir, "settings.json"),
    JSON.stringify({ hooks }, null, 2),
  );
}

/**
 * Create temp directories for test isolation:
 * - tempSessionsDir: for session artifacts
 * - tempProjectDir: default isolated CWD with .claude/settings.json containing native hooks
 *
 * Call once in beforeAll. Cleaned up by cleanupSessions().
 */
export function createTempSessionsDir(): string {
  tempSessionsDir = realpathSync(mkdtempSync(join(tmpdir(), "engine-e2e-sessions-")));
  tempProjectDir = realpathSync(mkdtempSync(join(tmpdir(), "engine-e2e-project-")));
  scaffoldProjectDir(tempProjectDir);
  return tempSessionsDir;
}

/**
 * Create a per-test isolated project directory with its own hooks.
 * Each concurrent test should call this to avoid effort collisions —
 * efforts are keyed by project path, so shared CWDs cause races.
 *
 * Cleaned up automatically by cleanupSessions().
 */
export function createIsolatedProject(): string {
  const dir = realpathSync(mkdtempSync(join(tmpdir(), "engine-e2e-iso-")));
  scaffoldProjectDir(dir);
  isolatedProjects.push(dir);
  return dir;
}

/** Get the default isolated project CWD. */
export function getIsolatedCwd(): string {
  if (!tempProjectDir) throw new Error("Call createTempSessionsDir() first");
  return tempProjectDir;
}

/** Read the hook debug log from a project dir. */
export function readHookDebugLog(projectDir?: string): string {
  const dir = projectDir ?? tempProjectDir;
  if (!dir) return "(no temp dir)";
  const logPath = join(dir, "hook-debug.log");
  if (!existsSync(logPath)) return "(no hook-debug.log)";
  return readFileSync(logPath, "utf-8");
}

/** Remove all temp directories. Call in afterAll. */
export function cleanupSessions(): void {
  if (tempSessionsDir) {
    rmSync(tempSessionsDir, { recursive: true, force: true });
    tempSessionsDir = null;
  }
  if (tempProjectDir) {
    rmSync(tempProjectDir, { recursive: true, force: true });
    tempProjectDir = null;
  }
  for (const dir of isolatedProjects) {
    rmSync(dir, { recursive: true, force: true });
  }
  isolatedProjects.length = 0;
}

// ── Claude invocation ────────────────────────────────────────

/**
 * Invoke Claude CLI with the engine plugin and return structured results.
 *
 * Uses: --plugin-dir, --dangerously-skip-permissions, --no-session-persistence,
 *       --model haiku, --max-budget-usd, -p <prompt>
 */
export function runClaude(
  prompt: string,
  opts: RunClaudeOptions = {},
): Promise<RunClaudeResult> {
  const {
    model = DEFAULT_MODEL,
    maxBudget = DEFAULT_BUDGET,
    timeout = DEFAULT_TIMEOUT,
    env: extraEnv = {},
    cwd,
    jsonSchema,
    extraArgs = [],
  } = opts;

  const args = [
    "--plugin-dir", PLUGIN_DIR,
    "--dangerously-skip-permissions",
    "--no-session-persistence",
    "--model", model,
    "--max-budget-usd", maxBudget,
  ];

  if (jsonSchema) {
    args.push("--output-format", "json", "--json-schema", JSON.stringify(jsonSchema));
  }

  args.push(...extraArgs, "-p", prompt);

  const start = Date.now();

  // Use the isolated temp CWD (no .claude/ folder) so only --plugin-dir hooks fire.
  // Falls back to process.cwd() if createTempSessionsDir() hasn't been called.
  const effectiveCwd = cwd ?? tempProjectDir ?? process.cwd();

  // Build a clean env: delete CLAUDE* vars that trigger nesting detection,
  // but KEEP CLAUDE_PROJECT_DIR and CLAUDE_PLUGIN_ROOT so hooks connect
  // to the same daemon instance as the test process.
  const env = { ...process.env, ...extraEnv };
  const keepVars = new Set(["CLAUDE_PROJECT_DIR", "CLAUDE_PLUGIN_ROOT"]);
  for (const key of Object.keys(env)) {
    if (key.startsWith("CLAUDE") && !keepVars.has(key)) delete env[key];
  }
  // Set project dir to the REAL project (for daemon socket resolution)
  // but CWD to the isolated temp dir (no .claude/ hooks).
  env.CLAUDE_PROJECT_DIR ??= process.cwd();

  return new Promise((resolve) => {
    // CRITICAL: stdin must be 'ignore' — execFile keeps stdin open as a pipe,
    // which causes Claude CLI to hang indefinitely waiting for input to close.
    const proc = spawn(CLAUDE_BIN, args, {
      cwd: effectiveCwd,
      env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    proc.stdout.on("data", (d: Buffer) => { stdout += d.toString(); });
    proc.stderr.on("data", (d: Buffer) => { stderr += d.toString(); });

    const timer = setTimeout(() => { proc.kill(); }, timeout);

    proc.on("close", (code, signal) => {
      clearTimeout(timer);
      const durationMs = Date.now() - start;
      resolve({
        stdout,
        stderr,
        exitCode: signal ? 1 : (code ?? 1),
        systemReminders: extractSystemReminders(stdout),
        durationMs,
      });
    });

    proc.on("error", (err) => {
      clearTimeout(timer);
      const durationMs = Date.now() - start;
      resolve({
        stdout,
        stderr: stderr + "\n" + err.message,
        exitCode: 1,
        systemReminders: [],
        durationMs,
      });
    });
  });
}

/**
 * Run Claude with --json-schema and parse the JSON result.
 * Returns the parsed object or null if parsing fails.
 */
export async function runClaudeJson<T = unknown>(
  prompt: string,
  schema: Record<string, unknown>,
  opts: Omit<RunClaudeOptions, "jsonSchema"> = {},
): Promise<{ data: T | null; raw: RunClaudeResult }> {
  const raw = await runClaude(prompt, { ...opts, jsonSchema: schema });
  if (raw.exitCode !== 0) return { data: null, raw };
  try {
    // --output-format json returns {"type":"result","structured_output":{...},...}
    const outer = JSON.parse(raw.stdout);

    // Try structured_output first, then result — skip empty strings
    let data = outer.structured_output;
    if (data === undefined || data === null || data === "") {
      data = outer.result;
    }
    if (data === undefined || data === null || data === "") {
      return { data: null, raw };
    }

    const inner = typeof data === "string" ? JSON.parse(data) : data;
    return { data: inner as T, raw };
  } catch {
    return { data: null, raw };
  }
}

// ── Parsing helpers ──────────────────────────────────────────

/**
 * Extract <system-reminder> blocks from Claude's output.
 * These are injected by hooks and appear in the model's context.
 */
function extractSystemReminders(output: string): string[] {
  const pattern = /<system-reminder>([\s\S]*?)<\/system-reminder>/g;
  const reminders: string[] = [];
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(output)) !== null) {
    reminders.push(match[1].trim());
  }
  return reminders;
}

/**
 * Check if Claude's output contains evidence of a specific hook firing.
 * Looks for hook-related content in system-reminders or stdout.
 */
export function hasHookEvidence(
  result: RunClaudeResult,
  pattern: string | RegExp,
): boolean {
  const regex = typeof pattern === "string" ? new RegExp(pattern) : pattern;
  // Check system reminders
  if (result.systemReminders.some((r) => regex.test(r))) return true;
  // Check raw stdout (Claude may mention hook content)
  if (regex.test(result.stdout)) return true;
  return false;
}

// ── RPC helpers ──────────────────────────────────────────────

/** Path to engine-rpc binary (in tools root, not plugin dir) */
const ENGINE_RPC = join(TOOLS_DIR, "bin/engine-rpc");

/**
 * Call an engine-rpc command and return the parsed JSON response.
 * Uses CLAUDE_PROJECT_DIR to scope to the correct daemon/DB.
 */
export function rpcCall<T = unknown>(
  cmd: string,
  args: Record<string, unknown> = {},
  projectDir?: string,
): T {
  const env = {
    ...process.env,
    CLAUDE_PROJECT_DIR: projectDir ?? process.cwd(),
    CLAUDE_PLUGIN_ROOT: TOOLS_DIR,
  };
  const result = execFileSync(ENGINE_RPC, [cmd, JSON.stringify(args)], {
    env,
    encoding: "utf-8",
    timeout: 15_000,
  });
  return JSON.parse(result.trim()) as T;
}

/** Standard RPC response shape */
export interface RpcResponse<T = unknown> {
  ok: boolean;
  data: T;
  error?: string;
  message?: string;
}

/** Effort row from DB */
export interface EffortRow {
  id: number;
  taskId: string;
  ordinal: number;
  skill: string;
  lifecycle: string;
  currentPhase: string | null;
}

/** Session row from DB */
export interface SessionRow {
  id: number;
  taskId: string;
  effortId: number;
  pid: number | null;
  heartbeatCounter: number;
  dehydrationPayload: unknown;
}

/**
 * Set up a full effort in the daemon DB (project + task + effort + session).
 * Returns the effort and session IDs for verification.
 *
 * @param dirPath - Task directory (e.g. "sessions/test_e2e_effort")
 * @param skill - Skill name (e.g. "implement")
 * @param opts.projectPath - Path stored in DB as the project path.
 *   Should match the CWD that Claude's hook will report (e.g. tempProjectDir).
 * @param opts.socketDir - CLAUDE_PROJECT_DIR for daemon socket resolution.
 *   Defaults to process.cwd() (the real project dir).
 */
export function setupEffort(
  dirPath: string,
  skill: string,
  opts?: { projectPath?: string; socketDir?: string; metadata?: Record<string, unknown> },
): { effort: EffortRow; session: SessionRow } {
  const socketDir = opts?.socketDir ?? process.cwd();
  const projectPath = opts?.projectPath ?? socketDir;
  const resp = rpcCall<RpcResponse<{
    effort: EffortRow;
    session: SessionRow;
  }>>("commands.effort.start", {
    dirPath,
    skill,
    projectPath,
    pid: process.pid,
    skipSearch: true,
    metadata: opts?.metadata,
  }, socketDir);
  if (!resp.ok) {
    throw new Error(`setupEffort failed: ${resp.error} — ${resp.message}`);
  }
  const data = (resp as unknown as { data: { effort: EffortRow; session: SessionRow } }).data
    ?? (resp as unknown as { effort: EffortRow; session: SessionRow });
  return { effort: data.effort, session: data.session };
}

/**
 * Tear down an effort — finish session and effort.
 */
export function teardownEffort(
  effortId: number,
  sessionId: number,
  projectDir?: string,
): void {
  const cwd = projectDir ?? process.cwd();
  try {
    rpcCall("db.session.finish", { sessionId }, cwd);
  } catch { /* best-effort */ }
  try {
    rpcCall("db.effort.finish", { effortId }, cwd);
  } catch { /* best-effort */ }
}

/**
 * Query all projects in the DB — diagnostic helper.
 */
export function queryProjects(
  projectDir?: string,
): { id: number; path: string; name: string }[] {
  const cwd = projectDir ?? process.cwd();
  const resp = rpcCall<RpcResponse<{ projects: { id: number; path: string; name: string }[] }>>(
    "db.project.list", {}, cwd,
  );
  const data = (resp as unknown as { data: { projects: { id: number; path: string; name: string }[] } }).data
    ?? (resp as unknown as { projects: { id: number; path: string; name: string }[] });
  return data.projects ?? [];
}

/**
 * Find a specific project by path — diagnostic helper.
 */
export function findProject(
  path: string,
  projectDir?: string,
): { id: number; path: string; name: string } | null {
  const cwd = projectDir ?? process.cwd();
  const resp = rpcCall<RpcResponse<{ project: { id: number; path: string; name: string } | null }>>(
    "db.project.find", { path }, cwd,
  );
  const data = (resp as unknown as { data: { project: { id: number; path: string; name: string } | null } }).data
    ?? (resp as unknown as { project: { id: number; path: string; name: string } | null });
  return data?.project ?? null;
}

/**
 * Query the effort list for a task to verify DB state.
 */
export function listEfforts(
  taskId: string,
  projectDir?: string,
): EffortRow[] {
  const cwd = projectDir ?? process.cwd();
  const resp = rpcCall<RpcResponse<{ efforts: EffortRow[] }>>(
    "db.effort.list", { taskId }, cwd,
  );
  const data = (resp as unknown as { data: { efforts: EffortRow[] } }).data
    ?? (resp as unknown as { efforts: EffortRow[] });
  return data.efforts ?? [];
}
