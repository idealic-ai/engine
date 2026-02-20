import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-skills-upsert.js";
import "../db-skills-get.js";
import { createTestDb, queryRow, queryCount } from "../../__tests__/helpers.js";

let db: Database;
beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
});
afterEach(() => {
  db.close();
});

describe("db.skills.upsert", () => {
  it("should create a skill with name only", () => {
    const result = dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement" },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    expect(skill.name).toBe("implement");
    expect(skill.project_id).toBe(1);
    expect(skill.id).toBe(1);
  });

  it("should create a skill with JSONB fields", () => {
    const phases = [
      { label: "0", name: "Setup" },
      { label: "1", name: "Interrogation" },
    ];
    const modes = { tdd: { label: "TDD", description: "Test-driven" } };
    const nextSkills = ["/test", "/document"];
    const directives = ["TESTING.md", "PITFALLS.md"];

    const result = dispatch(
      {
        cmd: "db.skills.upsert",
        args: {
          projectId: 1,
          name: "implement",
          phases,
          modes,
          nextSkills,
          directives,
        },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    // JSONB columns are stored as binary — read back via json()
    const row = queryRow(
      db,
      "SELECT json(phases) as phases, json(modes) as modes, json(next_skills) as next_skills, json(directives) as directives FROM skills WHERE id = 1"
    );
    expect(JSON.parse(row!.phases as string)).toEqual(phases);
    expect(JSON.parse(row!.modes as string)).toEqual(modes);
    expect(JSON.parse(row!.next_skills as string)).toEqual(nextSkills);
    expect(JSON.parse(row!.directives as string)).toEqual(directives);
  });

  it("should be idempotent — upsert same (projectId, name)", () => {
    dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement" },
      },
      db
    );
    const result = dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement" },
      },
      db
    );

    expect(result.ok).toBe(true);
    expect(queryCount(db, "SELECT COUNT(*) FROM skills")).toBe(1);
  });

  it("should update JSONB fields on re-upsert", () => {
    dispatch(
      {
        cmd: "db.skills.upsert",
        args: {
          projectId: 1,
          name: "implement",
          phases: [{ label: "0", name: "Setup" }],
        },
      },
      db
    );

    const newPhases = [
      { label: "0", name: "Setup" },
      { label: "1", name: "Build" },
    ];
    dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement", phases: newPhases },
      },
      db
    );

    const row = queryRow(
      db,
      "SELECT json(phases) as phases FROM skills WHERE id = 1"
    );
    expect(JSON.parse(row!.phases as string)).toEqual(newPhases);
  });

  it("should preserve JSONB fields when re-upsert omits them", () => {
    const phases = [{ label: "0", name: "Setup" }];
    dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement", phases },
      },
      db
    );
    dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement" },
      },
      db
    );

    const row = queryRow(
      db,
      "SELECT json(phases) as phases FROM skills WHERE id = 1"
    );
    expect(JSON.parse(row!.phases as string)).toEqual(phases);
  });

  it("should reject non-existent projectId (FK)", () => {
    const result = dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 999, name: "implement" },
      },
      db
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("HANDLER_ERROR");
  });

  it("should allow different skills for same project", () => {
    dispatch(
      { cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } },
      db
    );
    dispatch(
      { cmd: "db.skills.upsert", args: { projectId: 1, name: "brainstorm" } },
      db
    );

    expect(queryCount(db, "SELECT COUNT(*) FROM skills")).toBe(2);
  });
});

describe("db.skills.get", () => {
  it("should return skill by projectId and name", () => {
    dispatch(
      {
        cmd: "db.skills.upsert",
        args: {
          projectId: 1,
          name: "implement",
          phases: [{ label: "0", name: "Setup" }],
        },
      },
      db
    );

    const result = dispatch(
      { cmd: "db.skills.get", args: { projectId: 1, name: "implement" } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    expect(skill.name).toBe("implement");
    expect(skill.project_id).toBe(1);
  });

  it("should return null for non-existent skill", () => {
    const result = dispatch(
      { cmd: "db.skills.get", args: { projectId: 1, name: "nonexistent" } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.skill).toBeNull();
  });

  it("should return JSONB fields as parsed JSON", () => {
    const phases = [{ label: "0", name: "Setup" }];
    dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement", phases },
      },
      db
    );

    const result = dispatch(
      { cmd: "db.skills.get", args: { projectId: 1, name: "implement" } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    // skills.get should parse JSONB columns into JS objects
    expect(skill.phases).toEqual(phases);
  });
});
