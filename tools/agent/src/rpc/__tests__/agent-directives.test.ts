import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { dispatch, clearRegistry } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";
import { createTestCtx } from "./test-ctx.js";

import "../agent-directives-dereference.js";
import "../agent-directives-discover.js";
import "../agent-directives-resolve.js";

const ctx = createTestCtx();

describe("agent.directives.dereference", () => {
  it("extracts bare §CMD_ references from content", async () => {
    const content = "Execute §CMD_APPEND_LOG to log progress.\nThen run §CMD_GENERATE_DEBRIEF.";
    const result = await dispatch({ cmd: "agent.directives.dereference", args: { content } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const refs = result.data.refs as any[];
    expect(refs).toHaveLength(2);
    expect(refs[0].name).toBe("CMD_APPEND_LOG");
    expect(refs[1].name).toBe("CMD_GENERATE_DEBRIEF");
  });

  it("ignores backtick-escaped references", async () => {
    const content = "Use `§CMD_APPEND_LOG` for logging. But §CMD_DEHYDRATE is real.";
    const result = await dispatch({ cmd: "agent.directives.dereference", args: { content } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const refs = result.data.refs as any[];
    expect(refs).toHaveLength(1);
    expect(refs[0].name).toBe("CMD_DEHYDRATE");
  });

  it("ignores references inside code fences", async () => {
    const content = "Real: §CMD_REAL\n```\n§CMD_INSIDE_FENCE\n```\nAlso real: §INV_SOMETHING";
    const result = await dispatch({ cmd: "agent.directives.dereference", args: { content } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const refs = result.data.refs as any[];
    expect(refs).toHaveLength(2);
    expect(refs.map((r: any) => r.name)).toEqual(["CMD_REAL", "INV_SOMETHING"]);
  });

  it("deduplicates repeated references", async () => {
    const result = await dispatch({ cmd: "agent.directives.dereference", args: { content: "§CMD_FOO and §CMD_FOO again" } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.refs as any[]).length).toBe(1);
  });

  it("reads from file path when provided", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "deref-test-"));
    const filePath = path.join(tmpDir, "test.md");
    fs.writeFileSync(filePath, "Use §FMT_LIGHT_LIST here.");
    try {
      const result = await dispatch({ cmd: "agent.directives.dereference", args: { path: filePath } }, ctx);
      expect(result.ok).toBe(true);
      if (!result.ok) return;
      const refs = result.data.refs as any[];
      expect(refs).toHaveLength(1);
      expect(refs[0].prefix).toBe("FMT");
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  // ── Category D: Sigil Completeness ──────────────────────────

  it("D/1: extracts §FMT_ references", async () => {
    const content = "Use §FMT_LIGHT_LIST for formatting.";
    const result = await dispatch({ cmd: "agent.directives.dereference", args: { content } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const refs = result.data.refs as any[];
    expect(refs).toHaveLength(1);
    expect(refs[0].prefix).toBe("FMT");
    expect(refs[0].name).toBe("FMT_LIGHT_LIST");
  });

  it("D/2: extracts §INV_ references", async () => {
    const content = "Follow §INV_PHASE_ENFORCEMENT strictly.";
    const result = await dispatch({ cmd: "agent.directives.dereference", args: { content } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const refs = result.data.refs as any[];
    expect(refs).toHaveLength(1);
    expect(refs[0].prefix).toBe("INV");
    expect(refs[0].name).toBe("INV_PHASE_ENFORCEMENT");
  });

  it("D/3: returns empty refs for content with no sigils", async () => {
    const content = "Just regular text with no references.";
    const result = await dispatch({ cmd: "agent.directives.dereference", args: { content } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.refs).toEqual([]);
  });

  it("D/4: returns VALIDATION_ERROR when neither path nor content provided", async () => {
    const result = await dispatch({ cmd: "agent.directives.dereference", args: {} }, ctx);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });

  it("D/5: handles mixed code fence markers (e.g. ```typescript)", async () => {
    const content = "Real: §CMD_REAL\n```typescript\n§CMD_INSIDE_FENCE\n```\nAlso real: §INV_OUTSIDE";
    const result = await dispatch({ cmd: "agent.directives.dereference", args: { content } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const refs = result.data.refs as any[];
    const names = refs.map((r: any) => r.name);
    expect(names).toContain("CMD_REAL");
    expect(names).toContain("INV_OUTSIDE");
    expect(names).not.toContain("CMD_INSIDE_FENCE");
  });
});

describe("agent.directives.discover", () => {
  let tmpDir: string;
  beforeEach(() => { tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "discover-test-")); });
  afterEach(() => { fs.rmSync(tmpDir, { recursive: true, force: true }); });

  it("discovers directives in .directives/ subfolder", async () => {
    const directives = path.join(tmpDir, ".directives");
    fs.mkdirSync(directives);
    fs.writeFileSync(path.join(directives, "AGENTS.md"), "# Agents");
    fs.writeFileSync(path.join(directives, "TESTING.md"), "# Testing");
    const result = await dispatch({ cmd: "agent.directives.discover", args: { dirs: [tmpDir], walkUp: false, root: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const names = (result.data.files as any[]).map((f: any) => path.basename(f.path));
    expect(names).toContain("AGENTS.md");
    expect(names).toContain("TESTING.md");
  });

  it("walks up to parent directories", async () => {
    const directives = path.join(tmpDir, ".directives");
    fs.mkdirSync(directives);
    fs.writeFileSync(path.join(directives, "INVARIANTS.md"), "# Invariants");
    const child = path.join(tmpDir, "child");
    fs.mkdirSync(child);
    const result = await dispatch({ cmd: "agent.directives.discover", args: { dirs: [child], walkUp: true, root: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const names = (result.data.files as any[]).map((f: any) => path.basename(f.path));
    expect(names).toContain("INVARIANTS.md");
  });

  it("respects patterns filter", async () => {
    const directives = path.join(tmpDir, ".directives");
    fs.mkdirSync(directives);
    fs.writeFileSync(path.join(directives, "AGENTS.md"), "# Agents");
    fs.writeFileSync(path.join(directives, "TESTING.md"), "# Testing");
    fs.writeFileSync(path.join(directives, "PITFALLS.md"), "# Pitfalls");
    const result = await dispatch({ cmd: "agent.directives.discover", args: { dirs: [tmpDir], walkUp: false, root: tmpDir, patterns: ["TESTING.md"] } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const names = (result.data.files as any[]).map((f: any) => path.basename(f.path));
    expect(names).toContain("AGENTS.md");
    expect(names).toContain("TESTING.md");
    expect(names).not.toContain("PITFALLS.md");
  });

  it("discovers CMD_*.md files in .directives/commands/", async () => {
    const cmdDir = path.join(tmpDir, ".directives", "commands");
    fs.mkdirSync(cmdDir, { recursive: true });
    fs.writeFileSync(path.join(cmdDir, "CMD_FOO.md"), "# Foo");
    fs.writeFileSync(path.join(cmdDir, "CMD_BAR.md"), "# Bar");
    const result = await dispatch({ cmd: "agent.directives.discover", args: { dirs: [tmpDir], walkUp: false, root: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const names = (result.data.files as any[]).map((f: any) => path.basename(f.path));
    expect(names).toContain("CMD_FOO.md");
    expect(names).toContain("CMD_BAR.md");
  });

  // ── Category E: Boundaries ──────────────────────────────────

  it("E/1: falls back to legacy flat layout when no .directives/ exists", async () => {
    // Place AGENTS.md at root level (no .directives/ subfolder)
    fs.writeFileSync(path.join(tmpDir, "AGENTS.md"), "# Agents flat");
    const result = await dispatch({ cmd: "agent.directives.discover", args: { dirs: [tmpDir], walkUp: false, root: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const names = (result.data.files as any[]).map((f: any) => path.basename(f.path));
    expect(names).toContain("AGENTS.md");
  });

  it("E/2: returns empty array when no directives exist", async () => {
    const result = await dispatch({ cmd: "agent.directives.discover", args: { dirs: [tmpDir], walkUp: false, root: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.files).toEqual([]);
  });

  it("E/3: deduplicates files reachable from multiple dirs", async () => {
    // Parent has a directive
    const directives = path.join(tmpDir, ".directives");
    fs.mkdirSync(directives);
    fs.writeFileSync(path.join(directives, "AGENTS.md"), "# Agents");
    // Two child dirs — both walk up to find the same AGENTS.md
    const child1 = path.join(tmpDir, "child1");
    const child2 = path.join(tmpDir, "child2");
    fs.mkdirSync(child1);
    fs.mkdirSync(child2);
    const result = await dispatch({ cmd: "agent.directives.discover", args: { dirs: [child1, child2], walkUp: true, root: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const agentsFiles = (result.data.files as any[]).filter((f: any) => path.basename(f.path) === "AGENTS.md");
    expect(agentsFiles).toHaveLength(1);
  });

  it("E/4: discovers deeply nested walk-up (3+ levels)", async () => {
    // Place directives at root
    const directives = path.join(tmpDir, ".directives");
    fs.mkdirSync(directives);
    fs.writeFileSync(path.join(directives, "INVARIANTS.md"), "# Invariants");
    // Create 3-level nesting: root/a/b/c
    const deep = path.join(tmpDir, "a", "b", "c");
    fs.mkdirSync(deep, { recursive: true });
    const result = await dispatch({ cmd: "agent.directives.discover", args: { dirs: [deep], walkUp: true, root: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const names = (result.data.files as any[]).map((f: any) => path.basename(f.path));
    expect(names).toContain("INVARIANTS.md");
  });
});

describe("agent.directives.resolve", () => {
  let tmpDir: string;
  beforeEach(() => { tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "resolve-test-")); });
  afterEach(() => { fs.rmSync(tmpDir, { recursive: true, force: true }); });

  it("resolves CMD refs via walk-up", async () => {
    const cmdDir = path.join(tmpDir, ".directives", "commands");
    fs.mkdirSync(cmdDir, { recursive: true });
    fs.writeFileSync(path.join(cmdDir, "CMD_FOO.md"), "# Foo");
    const childDir = path.join(tmpDir, "child");
    fs.mkdirSync(childDir);
    const result = await dispatch({ cmd: "agent.directives.resolve", args: { refs: [{ prefix: "CMD", name: "CMD_FOO" }], startDir: childDir, projectRoot: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.resolved as any[])[0].path).toContain("CMD_FOO.md");
  });

  it("falls back to engine .directives/ for known CMDs", async () => {
    const result = await dispatch({ cmd: "agent.directives.resolve", args: { refs: [{ prefix: "CMD", name: "CMD_DEHYDRATE" }], startDir: tmpDir, projectRoot: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.resolved as any[])[0].path).toContain("CMD_DEHYDRATE.md");
  });

  it("returns null for unknown refs", async () => {
    const result = await dispatch({ cmd: "agent.directives.resolve", args: { refs: [{ prefix: "CMD", name: "CMD_NONEXISTENT_XYZ" }], startDir: tmpDir, projectRoot: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.resolved as any[])[0].path).toBeNull();
  });

  // ── Category F: Completeness ──────────────────────────────

  it("F/1: returns null path for unknown prefix (not CMD/FMT/INV)", async () => {
    const result = await dispatch({ cmd: "agent.directives.resolve", args: { refs: [{ prefix: "UNKNOWN", name: "UNKNOWN_FOO" }], startDir: tmpDir, projectRoot: tmpDir } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data.resolved as any[])[0];
    expect(resolved.path).toBeNull();
    expect(resolved.searchedDirs).toEqual([]);
  });

  it("F/2: resolves multiple refs in single call", async () => {
    // Create a local CMD ref
    const cmdDir = path.join(tmpDir, ".directives", "commands");
    fs.mkdirSync(cmdDir, { recursive: true });
    fs.writeFileSync(path.join(cmdDir, "CMD_LOCAL.md"), "# Local");

    const result = await dispatch({ cmd: "agent.directives.resolve", args: {
      refs: [
        { prefix: "CMD", name: "CMD_LOCAL" },          // found locally
        { prefix: "CMD", name: "CMD_DEHYDRATE" },      // found via engine fallback
        { prefix: "UNKNOWN", name: "UNKNOWN_BAR" },    // unknown prefix
      ],
      startDir: tmpDir,
      projectRoot: tmpDir,
    } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = result.data.resolved as any[];
    expect(resolved).toHaveLength(3);
    expect(resolved[0].path).toContain("CMD_LOCAL.md");
    expect(resolved[1].path).toContain("CMD_DEHYDRATE.md");
    expect(resolved[2].path).toBeNull();
  });

  it("F/3: prefers local override over engine fallback", async () => {
    // Create a local CMD_DEHYDRATE.md — should be found before the engine one
    const cmdDir = path.join(tmpDir, ".directives", "commands");
    fs.mkdirSync(cmdDir, { recursive: true });
    fs.writeFileSync(path.join(cmdDir, "CMD_DEHYDRATE.md"), "# Local override");

    const result = await dispatch({ cmd: "agent.directives.resolve", args: {
      refs: [{ prefix: "CMD", name: "CMD_DEHYDRATE" }],
      startDir: tmpDir,
      projectRoot: tmpDir,
    } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data.resolved as any[])[0];
    // Should point to our local override, not the engine's copy
    expect(resolved.path).toContain(tmpDir);
    expect(resolved.path).not.toContain(".claude/engine");
  });

  it("F/4: records searchedDirs audit trail", async () => {
    // Walk-up from child to tmpDir looking for a ref that doesn't exist locally
    const child = path.join(tmpDir, "sub");
    fs.mkdirSync(child);
    const result = await dispatch({ cmd: "agent.directives.resolve", args: {
      refs: [{ prefix: "CMD", name: "CMD_NONEXISTENT_AUDIT" }],
      startDir: child,
      projectRoot: tmpDir,
    } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const resolved = (result.data.resolved as any[])[0];
    // searchedDirs should contain the child dir, tmpDir, and the engine dir
    expect(resolved.searchedDirs.length).toBeGreaterThanOrEqual(2);
    // The child dir should be first (start of walk-up)
    expect(resolved.searchedDirs[0]).toContain("sub");
  });
});
