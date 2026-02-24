/**
 * Integration test — registers fs.* and agent.* handlers in shared dispatch,
 * sends RPC requests through dispatch(), verifies responses.
 *
 * NOTE: Does NOT start the full daemon (db.* handlers have a missing dependency
 * from a separate sqlite migration). Instead, tests the dispatch layer directly
 * with only fs.* and agent.* registries loaded — proving cross-namespace
 * dispatch works correctly.
 */
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { dispatch, clearRegistry, getRegistry, type RpcRequest } from "../dispatch.js";
import type { RpcContext } from "../context.js";
import { buildNamespace } from "../namespace-builder.js";

// Import registries — side-effect imports that register handlers
import "engine-fs/rpc/registry";
import "engine-agent/rpc/registry";

const TEST_DIR = path.join(os.tmpdir(), `rpc-int-${process.pid}`);
const FIXTURE_DIR = path.join(TEST_DIR, "fixtures");
const DIRECTIVES_DIR = path.join(FIXTURE_DIR, ".directives");

beforeAll(() => {
  fs.mkdirSync(DIRECTIVES_DIR, { recursive: true });

  fs.writeFileSync(path.join(FIXTURE_DIR, "test.txt"), "hello world");
  fs.writeFileSync(
    path.join(DIRECTIVES_DIR, "TESTING.md"),
    "# Testing Directives\nSome content about testing."
  );
  fs.writeFileSync(
    path.join(FIXTURE_DIR, "refs.md"),
    "Use §CMD_APPEND_LOG and §CMD_REPORT_INTENT here.\n`§CMD_ESCAPE_THIS` should be ignored."
  );

  // Minimal SKILL.md fixture
  fs.writeFileSync(
    path.join(FIXTURE_DIR, "SKILL.md"),
    [
      "---",
      "name: test-fixture",
      'description: "A test skill"',
      "version: 1.0",
      "tier: protocol",
      "---",
      "",
      "# Test Protocol",
      "",
      "```json",
      "{",
      '  "taskType": "TESTING",',
      '  "phases": [',
      '    {"label": "0", "name": "Setup", "steps": [], "proof": [], "gate": false},',
      '    {"label": "1", "name": "Work", "steps": [], "proof": []}',
      "  ],",
      '  "nextSkills": ["/analyze"],',
      '  "directives": ["TESTING.md"]',
      "}",
      "```",
    ].join("\n")
  );
});

afterAll(() => {
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
});

/** Build a test ctx with fs namespace proxies + env. */
const testCtx = (() => {
  const ctx = {} as RpcContext;
  const registry = getRegistry();
  ctx.env = { CWD: "/tmp/test", AGENT_ID: "default" };
  ctx.fs = buildNamespace("fs", registry, ctx) as unknown as RpcContext["fs"];
  return ctx;
})();

/** Shorthand: dispatch an RPC request with fs ctx. */
async function rpc(cmd: string, args: Record<string, unknown> = {}) {
  return dispatch({ cmd, args } as RpcRequest, testCtx);
}

describe("integration: fs.* RPCs via shared dispatch", () => {
  it("fs.paths.resolve — resolves paths with existence check", async () => {
    const testFile = path.join(FIXTURE_DIR, "test.txt");
    const result = await rpc("fs.paths.resolve", {
      paths: [testFile, "/nonexistent/path"],
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data as { resolved: Array<{ original: string; resolved: string; exists: boolean }> }).resolved;
    expect(resolved).toHaveLength(2);
    expect(resolved[0].exists).toBe(true);
    expect(resolved[1].exists).toBe(false);
  });

  it("fs.files.read — reads file content", async () => {
    const testFile = path.join(FIXTURE_DIR, "test.txt");
    const result = await rpc("fs.files.read", { path: testFile });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const data = result.data as { content: string; size: number };
    expect(data.content).toBe("hello world");
    expect(data.size).toBe(11);
  });

  it("fs.files.read — returns error for nonexistent file", async () => {
    const result = await rpc("fs.files.read", { path: "/nonexistent/file.txt" });
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("FS_NOT_FOUND");
  });
});

describe("integration: agent.* RPCs via shared dispatch", () => {
  it("agent.directives.discover — finds .directives/ files", async () => {
    const result = await rpc("agent.directives.discover", {
      dirs: [FIXTURE_DIR],
      root: FIXTURE_DIR,
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const files = (result.data as { files: Array<{ path: string }> }).files;
    expect(files.length).toBeGreaterThanOrEqual(1);
    expect(files.some((f) => f.path.includes("TESTING.md"))).toBe(true);
  });

  it("agent.directives.dereference — extracts bare refs, ignores backticked", async () => {
    const content = fs.readFileSync(path.join(FIXTURE_DIR, "refs.md"), "utf-8");
    const result = await rpc("agent.directives.dereference", { content });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const refs = (result.data as { refs: Array<{ name: string }> }).refs;
    const names = refs.map((r) => r.name);
    expect(names).toContain("CMD_APPEND_LOG");
    expect(names).toContain("CMD_REPORT_INTENT");
    expect(names).not.toContain("CMD_ESCAPE_THIS");
  });

  it("agent.directives.resolve — resolves refs via walk-up", async () => {
    // Create a commands dir with a CMD file
    const cmdDir = path.join(DIRECTIVES_DIR, "commands");
    fs.mkdirSync(cmdDir, { recursive: true });
    fs.writeFileSync(path.join(cmdDir, "CMD_TEST.md"), "# Test Command");

    const result = await rpc("agent.directives.resolve", {
      refs: [{ prefix: "CMD", name: "CMD_TEST" }],
      startDir: FIXTURE_DIR,
      projectRoot: FIXTURE_DIR,
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data as { resolved: Array<{ ref: string; path: string | null }> }).resolved;
    expect(resolved).toHaveLength(1);
    expect(resolved[0].path).toContain("CMD_TEST.md");
  });

  it("agent.skills.parse — parses SKILL.md JSON block", async () => {
    const skillPath = path.join(FIXTURE_DIR, "SKILL.md");
    const result = await rpc("agent.skills.parse", { skillPath });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = (result.data as { skill: Record<string, unknown> }).skill;
    expect(skill.name).toBe("test-fixture");
    expect(skill.description).toBe("A test skill");
    expect((skill.phases as unknown[]).length).toBe(2);
    expect(skill.nextSkills).toEqual(["/analyze"]);
  });

  it("agent.skills.list — discovers skills in directory", async () => {
    // Create a mock skills dir
    const skillsDir = path.join(TEST_DIR, "skills");
    const mockSkill = path.join(skillsDir, "mock-skill");
    fs.mkdirSync(mockSkill, { recursive: true });
    fs.copyFileSync(path.join(FIXTURE_DIR, "SKILL.md"), path.join(mockSkill, "SKILL.md"));

    const result = await rpc("agent.skills.list", { searchDirs: [skillsDir] });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = (result.data as { skills: Array<{ name: string; path: string; tier: string }> }).skills;
    expect(skills.length).toBeGreaterThanOrEqual(1);
    expect(skills.some((s) => s.name === "mock-skill")).toBe(true);
  });
});

describe("integration: dispatch error handling", () => {
  it("unknown command — returns UNKNOWN_COMMAND error", async () => {
    const result = await rpc("nonexistent.command", {});
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("UNKNOWN_COMMAND");
  });

  it("validation error — returns VALIDATION_ERROR for missing required field", async () => {
    const result = await rpc("fs.files.read", {});
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });
});
