import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { dispatch } from "engine-shared/dispatch";
import { createTestCtx } from "./test-ctx.js";

import "../agent-skills-parse.js";
import "../agent-skills-list.js";

const ctx = createTestCtx();

describe("agent.skills.parse", () => {
  let tmpDir: string;
  beforeEach(() => { tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "skills-parse-test-")); });
  afterEach(() => { fs.rmSync(tmpDir, { recursive: true, force: true }); });

  it("parses a full SKILL.md with frontmatter and JSON block", async () => {
    const skillContent = `---\nname: test-skill\ndescription: "A test skill"\nversion: 1.0\ntier: protocol\n---\n\n# Test Skill Protocol\n\n### Session Parameters\n\`\`\`json\n{"taskType": "TESTING", "phases": [{"label": "0", "name": "Setup"}, {"label": "1", "name": "Work"}], "nextSkills": ["/implement", "/fix"], "directives": ["TESTING.md"], "planTemplate": "assets/PLAN.md", "logTemplate": "assets/LOG.md", "debriefTemplate": "assets/DEBRIEF.md"}\n\`\`\`\n`;
    const skillPath = path.join(tmpDir, "SKILL.md");
    fs.writeFileSync(skillPath, skillContent);
    const result = await dispatch({ cmd: "agent.skills.parse", args: { skillPath } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as any;
    expect(skill.name).toBe("test-skill");
    expect(skill.tier).toBe("protocol");
    expect(skill.phases).toHaveLength(2);
    expect(skill.nextSkills).toEqual(["/implement", "/fix"]);
    expect(skill.templates.plan).toBe("assets/PLAN.md");
  });

  it("handles SKILL.md without JSON block (utility tier)", async () => {
    const skillContent = "---\nname: simple\ntier: utility\n---\n\n# Simple Skill\nJust does stuff.\n";
    const skillPath = path.join(tmpDir, "SKILL.md");
    fs.writeFileSync(skillPath, skillContent);
    const result = await dispatch({ cmd: "agent.skills.parse", args: { skillPath } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as any;
    expect(skill.name).toBe("simple");
    expect(skill.tier).toBe("utility");
    expect(skill.phases).toBeNull();
  });

  it("returns FS_NOT_FOUND for missing file", async () => {
    const result = await dispatch({ cmd: "agent.skills.parse", args: { skillPath: "/nonexistent/SKILL.md" } }, ctx);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("FS_NOT_FOUND");
  });

  // ── Category G: Error & Edge Cases ──────────────────────────

  it("G/1: returns PARSE_ERROR for malformed JSON block", async () => {
    const skillContent = `---\nname: broken\ntier: protocol\n---\n\n# Broken\n\n\`\`\`json\n{ this is not valid JSON }\n\`\`\`\n`;
    const skillPath = path.join(tmpDir, "SKILL.md");
    fs.writeFileSync(skillPath, skillContent);
    const result = await dispatch({ cmd: "agent.skills.parse", args: { skillPath } }, ctx);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("PARSE_ERROR");
  });

  it("G/2: extracts modes object from JSON block", async () => {
    const skillContent = `---\nname: modal\ntier: protocol\n---\n\n# Modal Skill\n\n\`\`\`json\n{"taskType": "TEST", "modes": {"tdd": {"label": "TDD", "description": "Test-driven", "file": "modes/tdd.md"}, "custom": {"label": "Custom", "description": "User-defined", "file": "modes/custom.md"}}}\n\`\`\`\n`;
    const skillPath = path.join(tmpDir, "SKILL.md");
    fs.writeFileSync(skillPath, skillContent);
    const result = await dispatch({ cmd: "agent.skills.parse", args: { skillPath } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as any;
    expect(skill.modes).toBeDefined();
    expect(skill.modes.tdd).toBeDefined();
    expect(skill.modes.tdd.label).toBe("TDD");
    expect(skill.modes.custom).toBeDefined();
  });

  it("G/3: handles SKILL.md without frontmatter", async () => {
    const skillContent = `# No Frontmatter Skill\n\n\`\`\`json\n{"taskType": "BARE", "phases": [{"label": "0", "name": "Setup"}]}\n\`\`\`\n`;
    const skillPath = path.join(tmpDir, "SKILL.md");
    fs.writeFileSync(skillPath, skillContent);
    const result = await dispatch({ cmd: "agent.skills.parse", args: { skillPath } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as any;
    // No frontmatter — name falls back to taskType from JSON
    expect(skill.name).toBe("BARE");
    // tier defaults to "protocol" when JSON block is present
    expect(skill.tier).toBe("protocol");
    expect(skill.phases).toHaveLength(1);
  });
});

describe("agent.skills.list", () => {
  let tmpDir: string;
  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "skills-list-test-"));
  });
  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("discovers skills from search directories", async () => {
    const skill1 = path.join(tmpDir, "implement");
    const skill2 = path.join(tmpDir, "analyze");
    fs.mkdirSync(skill1);
    fs.mkdirSync(skill2);
    fs.writeFileSync(path.join(skill1, "SKILL.md"), "---\nname: implement\ntier: protocol\n---\n# Impl\n```json\n{\"phases\": []}\n```");
    fs.writeFileSync(path.join(skill2, "SKILL.md"), "---\nname: analyze\ntier: protocol\n---\n# Analyze");
    const result = await dispatch({ cmd: "agent.skills.list", args: { searchDirs: [tmpDir] } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as any[];
    expect(skills).toHaveLength(2);
    expect(skills[0].name).toBe("analyze");
    expect(skills[1].name).toBe("implement");
  });

  it("ignores directories without SKILL.md", async () => {
    const noSkill = path.join(tmpDir, "not-a-skill");
    fs.mkdirSync(noSkill);
    fs.writeFileSync(path.join(noSkill, "README.md"), "Not a skill");
    const result = await dispatch({ cmd: "agent.skills.list", args: { searchDirs: [tmpDir] } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.skills as any[])).toHaveLength(0);
  });

  it("discovers real skills from ~/.claude/skills/", async () => {
    const result = await dispatch({ cmd: "agent.skills.list", args: {} }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as any[];
    expect(skills.length).toBeGreaterThan(0);
    expect(skills.map((s: any) => s.name)).toContain("implement");
  });

  // ── Category H: Edge Cases ──────────────────────────────────

  it("H/1: skips nonexistent search directories", async () => {
    const result = await dispatch({ cmd: "agent.skills.list", args: { searchDirs: ["/nonexistent/dir/that/does/not/exist"] } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.skills).toEqual([]);
  });

  it("H/2: deduplicates skills across multiple search dirs", async () => {
    // Create two dirs with the same skill name
    const dir1 = path.join(tmpDir, "dir1", "myskill");
    const dir2 = path.join(tmpDir, "dir2", "myskill");
    fs.mkdirSync(dir1, { recursive: true });
    fs.mkdirSync(dir2, { recursive: true });
    fs.writeFileSync(path.join(dir1, "SKILL.md"), "---\nname: myskill\ntier: utility\n---\n# First");
    fs.writeFileSync(path.join(dir2, "SKILL.md"), "---\nname: myskill\ntier: utility\n---\n# Second");

    const result = await dispatch({ cmd: "agent.skills.list", args: {
      searchDirs: [path.join(tmpDir, "dir1"), path.join(tmpDir, "dir2")],
    } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as any[];
    const myskills = skills.filter((s: any) => s.name === "myskill");
    expect(myskills).toHaveLength(1);
    // First occurrence wins
    expect(myskills[0].path).toContain("dir1");
  });

  it("H/3: detects tier via heuristic when no explicit tier in frontmatter", async () => {
    // Skill with "phases" in JSON but no tier in frontmatter
    const skillDir = path.join(tmpDir, "heuristic-skill");
    fs.mkdirSync(skillDir);
    const skillContent = `---\nname: heuristic\ndescription: "No tier"\nversion: 1.0\n---\n\n# Heuristic\n\n\`\`\`json\n{"phases": [{"label": "0", "name": "Setup"}]}\n\`\`\`\n`;
    fs.writeFileSync(path.join(skillDir, "SKILL.md"), skillContent);

    const result = await dispatch({ cmd: "agent.skills.list", args: { searchDirs: [tmpDir] } }, ctx);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as any[];
    const found = skills.find((s: any) => s.name === "heuristic-skill");
    expect(found).toBeDefined();
    // Heuristic: content has "phases" → protocol
    expect(found!.tier).toBe("protocol");
  });
});
