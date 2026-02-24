import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import { createTestContext } from "engine-shared/__tests__/test-context";
import "../../../../db/src/rpc/registry.js";
import "../hooks-session-start.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

let db: DbConnection;
let ctx: RpcContext;

/** Common base args for SessionStart dispatch (snake_case) */
const BASE = {
  session_id: "test-session",
  transcript_path: "/tmp/transcript.jsonl",
  permission_mode: "default",
  hook_event_name: "SessionStart",
  source: "startup",
};

/**
 * Helper: insert effort directly via SQL to avoid jsonb() which wa-sqlite doesn't support.
 * Returns the effort id.
 */
async function insertEffort(
  d: DbConnection,
  taskId: string,
  skill: string,
  opts?: { mode?: string; phase?: string; discoveredDirectives?: string[] }
): Promise<number> {
  await d.run(
    `INSERT INTO efforts (task_id, skill, mode, ordinal, lifecycle, current_phase, discovered_directives)
     VALUES (?, ?, ?, 1, 'active', ?, ?)`,
    [
      taskId,
      skill,
      opts?.mode ?? null,
      opts?.phase ?? null,
      opts?.discoveredDirectives ? JSON.stringify(opts.discoveredDirectives) : null,
    ]
  );
  const row = await d.get<{ id: number }>("SELECT MAX(id) AS id FROM efforts");
  return row!.id;
}

/**
 * Helper: insert skill directly via SQL to avoid jsonb().
 */
async function insertSkill(
  d: DbConnection,
  projectId: number,
  name: string,
  config: {
    phases?: unknown;
    modes?: unknown;
    templates?: unknown;
    nextSkills?: unknown;
    directives?: unknown;
  }
): Promise<void> {
  await d.run(
    `INSERT INTO skills (project_id, name, phases, modes, templates, next_skills, directives, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))`,
    [
      projectId,
      name,
      config.phases ? JSON.stringify(config.phases) : null,
      config.modes ? JSON.stringify(config.modes) : null,
      config.templates ? JSON.stringify(config.templates) : null,
      config.nextSkills ? JSON.stringify(config.nextSkills) : null,
      config.directives ? JSON.stringify(config.directives) : null,
    ]
  );
}

beforeEach(async () => {
  db = await createTestDb();
  ctx = createTestContext(db);
  // Use raw SQL for project+task to avoid any jsonb issues
  await db.run("INSERT INTO projects (path, name) VALUES ('/proj', 'proj')");
  await db.run("INSERT INTO tasks (dir_path, project_id) VALUES ('sessions/test', 1)");
});
afterEach(async () => {
  await db.close();
});

describe("hooks.sessionStart", () => {
  it("returns effort, session, and skillConfig for an active effort+session", async () => {
    const effortId = await insertEffort(db, "sessions/test", "implement", {
      phase: "3: Execution",
    });

    // Create session via raw SQL too
    await db.run(
      `INSERT INTO sessions (task_id, effort_id, pid, last_heartbeat)
       VALUES ('sessions/test', ?, 1234, datetime('now'))`,
      [effortId]
    );

    await insertSkill(db, 1, "implement", {
      phases: [{ major: 0, minor: 0, name: "Setup" }],
      modes: { tdd: { label: "TDD" } },
      templates: {
        log: "~/.claude/skills/implement/assets/TEMPLATE_LOG.md",
        debrief: "~/.claude/skills/implement/assets/TEMPLATE.md",
      },
      nextSkills: ["test", "fix"],
      directives: ["TESTING.md", "PITFALLS.md"],
    });

    const result = await dispatch(
      {
        cmd: "hooks.sessionStart",
        args: { ...BASE, cwd: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;

    expect(data.found).toBe(true);
    expect(data.effortId).toBe(effortId);
    expect(data.sessionId).toBeTypeOf("number");
    expect(data.taskDir).toBe("sessions/test");
    expect(data.skill).toBe("implement");
    expect(data.phase).toBe("3: Execution");
    expect(data.skillConfig).toBeTruthy();
    expect((data.skillConfig as any)!.phases).toEqual([{ major: 0, minor: 0, name: "Setup" }]);
    expect((data.skillConfig as any)!.nextSkills).toEqual(["test", "fix"]);
    expect((data.sessionContext as string)).toContain("implement");
    expect((data.sessionContext as string)).toContain("sessions/test");
  });

  it("returns filesToPreload with template paths from skill config", async () => {
    const effortId = await insertEffort(db, "sessions/test", "implement");

    await db.run(
      `INSERT INTO sessions (task_id, effort_id, last_heartbeat)
       VALUES ('sessions/test', ?, datetime('now'))`,
      [effortId]
    );

    await insertSkill(db, 1, "implement", {
      templates: {
        log: "~/.claude/skills/implement/assets/TEMPLATE_LOG.md",
        debrief: "~/.claude/skills/implement/assets/TEMPLATE.md",
        plan: "~/.claude/skills/implement/assets/TEMPLATE_PLAN.md",
      },
    });

    const result = await dispatch(
      {
        cmd: "hooks.sessionStart",
        args: { ...BASE, cwd: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    const files = data.filesToPreload as string[];

    expect(files).toContain("~/.claude/skills/implement/assets/TEMPLATE_LOG.md");
    expect(files).toContain("~/.claude/skills/implement/assets/TEMPLATE.md");
    expect(files).toContain("~/.claude/skills/implement/assets/TEMPLATE_PLAN.md");
  });

  it("returns dehydratedContext when session has dehydration_payload", async () => {
    const effortId = await insertEffort(db, "sessions/test", "implement");

    await db.run(
      `INSERT INTO sessions (task_id, effort_id, last_heartbeat, dehydration_payload)
       VALUES ('sessions/test', ?, datetime('now'), ?)`,
      [
        effortId,
        JSON.stringify({
          summary: "Working on auth",
          nextSteps: ["finish validation"],
        }),
      ]
    );

    const result = await dispatch(
      {
        cmd: "hooks.sessionStart",
        args: { ...BASE, cwd: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;

    expect(data.dehydratedContext).toEqual({
      summary: "Working on auth",
      nextSteps: ["finish validation"],
    });
  });

  it("returns { found: false } when no active effort exists", async () => {
    const result = await dispatch(
      {
        cmd: "hooks.sessionStart",
        args: { ...BASE, cwd: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.found).toBe(false);
  });

  // ── Hardening: malformed JSONB in discovered_directives ────────
  it("handles corrupt discovered_directives gracefully (not valid JSON array)", async () => {
    const effortId = await insertEffort(db, "sessions/test", "implement");
    // Corrupt the discovered_directives column directly
    await db.run(
      "UPDATE efforts SET discovered_directives = ? WHERE id = ?",
      ["not-valid-json{{{", effortId]
    );

    await db.run(
      `INSERT INTO sessions (task_id, effort_id, last_heartbeat)
       VALUES ('sessions/test', ?, datetime('now'))`,
      [effortId]
    );

    const result = await dispatch(
      { cmd: "hooks.sessionStart", args: { ...BASE, cwd: "/proj" } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.found).toBe(true);
    // filesToPreload should not include corrupt data, but should not crash
    const files = data.filesToPreload as string[];
    expect(Array.isArray(files)).toBe(true);
  });

  // ── Hardening: fresh project with zero efforts ────────────────
  it("returns { found: false } for project with tasks but no efforts", async () => {
    // project and task exist from beforeEach, but no effort created
    const result = await dispatch(
      { cmd: "hooks.sessionStart", args: { ...BASE, cwd: "/proj" } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).found).toBe(false);
  });

  // ── Hardening: duplicate filesToPreload entries ────────────────
  it("includes template paths and directive paths (documenting dedup behavior)", async () => {
    const sharedPath = "/proj/.directives/TESTING.md";
    const effortId = await insertEffort(db, "sessions/test", "implement", {
      discoveredDirectives: [sharedPath, "/proj/.directives/PITFALLS.md"],
    });

    await db.run(
      `INSERT INTO sessions (task_id, effort_id, last_heartbeat)
       VALUES ('sessions/test', ?, datetime('now'))`,
      [effortId]
    );

    // Skill templates that include the same path as a discovered directive
    await insertSkill(db, 1, "implement", {
      templates: { testing: sharedPath },
    });

    const result = await dispatch(
      { cmd: "hooks.sessionStart", args: { ...BASE, cwd: "/proj" } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    const files = data.filesToPreload as string[];
    // Documents current behavior: duplicates ARE present (no dedup)
    const sharedCount = files.filter((f) => f === sharedPath).length;
    expect(sharedCount).toBe(2);
  });

  it("should handle skill without templates gracefully", async () => {
    const effortId = await insertEffort(db, "sessions/test", "implement");
    await db.run(
      `INSERT INTO sessions (task_id, effort_id, last_heartbeat)
       VALUES ('sessions/test', ?, datetime('now'))`,
      [effortId]
    );
    // Skill exists but has null templates
    await insertSkill(db, 1, "implement", {});

    const result = await dispatch(
      { cmd: "hooks.sessionStart", args: { ...BASE, cwd: "/proj" } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.found).toBe(true);
    const files = data.filesToPreload as string[];
    expect(Array.isArray(files)).toBe(true);
    expect(files).toHaveLength(0);
  });

  it("should handle effort with null phase", async () => {
    const effortId = await insertEffort(db, "sessions/test", "implement");
    await db.run(
      `INSERT INTO sessions (task_id, effort_id, last_heartbeat)
       VALUES ('sessions/test', ?, datetime('now'))`,
      [effortId]
    );

    const result = await dispatch(
      { cmd: "hooks.sessionStart", args: { ...BASE, cwd: "/proj" } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.phase).toBeNull();
    expect(data.sessionContext).toContain("Phase: none");
  });

  it("should create session when effort exists but no session yet", async () => {
    const effortId = await insertEffort(db, "sessions/test", "implement", {
      phase: "0: Setup",
    });
    // No session inserted — sessionStart should create one

    const result = await dispatch(
      { cmd: "hooks.sessionStart", args: { ...BASE, cwd: "/proj", pid: 5678 } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    expect(data.found).toBe(true);
    expect(data.sessionId).toBeTypeOf("number");
    expect(data.effortId).toBe(effortId);
  });

  it("should return { found: false } for unknown project path", async () => {
    const result = await dispatch(
      { cmd: "hooks.sessionStart", args: { ...BASE, cwd: "/nonexistent" } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data as Record<string, unknown>).found).toBe(false);
  });

  it("includes discovered_directives from effort in filesToPreload", async () => {
    const effortId = await insertEffort(db, "sessions/test", "implement", {
      discoveredDirectives: [
        "/proj/.directives/TESTING.md",
        "/proj/.directives/PITFALLS.md",
      ],
    });

    await db.run(
      `INSERT INTO sessions (task_id, effort_id, last_heartbeat)
       VALUES ('sessions/test', ?, datetime('now'))`,
      [effortId]
    );

    const result = await dispatch(
      {
        cmd: "hooks.sessionStart",
        args: { ...BASE, cwd: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as Record<string, unknown>;
    const files = data.filesToPreload as string[];

    expect(files).toContain("/proj/.directives/TESTING.md");
    expect(files).toContain("/proj/.directives/PITFALLS.md");
  });
});
