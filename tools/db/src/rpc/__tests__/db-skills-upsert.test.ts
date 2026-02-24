import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-skills-upsert.js";
import "../db-skills-get.js";
import { createTestDb, queryRow, queryCount } from "../../__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
});
afterEach(async () => {
  await db.close();
});

describe("db.skills.upsert", () => {
  it("should create a skill with name only", async () => {
    const result = await dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    expect(skill.name).toBe("implement");
    expect(skill.projectId).toBe(1);
    expect(skill.id).toBe(1);
  });

  it("should create a skill with JSONB fields", async () => {
    const phases = [
      { label: "0", name: "Setup" },
      { label: "1", name: "Interrogation" },
    ];
    const modes = { tdd: { label: "TDD", description: "Test-driven" } };
    const nextSkills = ["/test", "/document"];
    const directives = ["TESTING.md", "PITFALLS.md"];

    const result = await dispatch(
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
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    // JSONB columns are stored as binary — read back via json()
    const row = await queryRow(
      db,
      "SELECT json(phases) as phases, json(modes) as modes, json(next_skills) as next_skills, json(directives) as directives FROM skills WHERE id = 1"
    );
    const parse = (v: unknown) => typeof v === "string" ? JSON.parse(v) : v;
    expect(parse(row!.phases)).toEqual(phases);
    expect(parse(row!.modes)).toEqual(modes);
    expect(parse(row!.nextSkills)).toEqual(nextSkills);
    expect(parse(row!.directives)).toEqual(directives);
  });

  it("should be idempotent — upsert same (projectId, name)", async () => {
    await dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement" },
      },
      { db } as unknown as RpcContext
    );
    const result = await dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    expect(await queryCount(db, "SELECT COUNT(*) FROM skills")).toBe(1);
  });

  it("should update JSONB fields on re-upsert", async () => {
    await dispatch(
      {
        cmd: "db.skills.upsert",
        args: {
          projectId: 1,
          name: "implement",
          phases: [{ label: "0", name: "Setup" }],
        },
      },
      { db } as unknown as RpcContext
    );

    const newPhases = [
      { label: "0", name: "Setup" },
      { label: "1", name: "Build" },
    ];
    await dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement", phases: newPhases },
      },
      { db } as unknown as RpcContext
    );

    const row = await queryRow(
      db,
      "SELECT json(phases) as phases FROM skills WHERE id = 1"
    );
    const parse = (v: unknown) => typeof v === "string" ? JSON.parse(v) : v;
    expect(parse(row!.phases)).toEqual(newPhases);
  });

  it("should preserve JSONB fields when re-upsert omits them", async () => {
    const phases = [{ label: "0", name: "Setup" }];
    await dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement", phases },
      },
      { db } as unknown as RpcContext
    );
    await dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement" },
      },
      { db } as unknown as RpcContext
    );

    const row = await queryRow(
      db,
      "SELECT json(phases) as phases FROM skills WHERE id = 1"
    );
    const parse = (v: unknown) => typeof v === "string" ? JSON.parse(v) : v;
    expect(parse(row!.phases)).toEqual(phases);
  });

  it("should reject non-existent projectId (FK)", async () => {
    const result = await dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 999, name: "implement" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("HANDLER_ERROR");
  });

  it("should allow different skills for same project", async () => {
    await dispatch(
      { cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } },
      { db } as unknown as RpcContext
    );
    await dispatch(
      { cmd: "db.skills.upsert", args: { projectId: 1, name: "brainstorm" } },
      { db } as unknown as RpcContext
    );

    expect(await queryCount(db, "SELECT COUNT(*) FROM skills")).toBe(2);
  });
});

describe("db.skills.get", () => {
  it("should return skill by projectId and name", async () => {
    await dispatch(
      {
        cmd: "db.skills.upsert",
        args: {
          projectId: 1,
          name: "implement",
          phases: [{ label: "0", name: "Setup" }],
        },
      },
      { db } as unknown as RpcContext
    );

    const result = await dispatch(
      { cmd: "db.skills.get", args: { projectId: 1, name: "implement" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    expect(skill.name).toBe("implement");
    expect(skill.projectId).toBe(1);
  });

  it("should return null for non-existent skill", async () => {
    const result = await dispatch(
      { cmd: "db.skills.get", args: { projectId: 1, name: "nonexistent" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.skill).toBeNull();
  });

  it("should return JSONB fields as parsed JSON", async () => {
    const phases = [{ label: "0", name: "Setup" }];
    await dispatch(
      {
        cmd: "db.skills.upsert",
        args: { projectId: 1, name: "implement", phases },
      },
      { db } as unknown as RpcContext
    );

    const result = await dispatch(
      { cmd: "db.skills.get", args: { projectId: 1, name: "implement" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    // skills.get should parse JSONB columns into JS objects
    expect(skill.phases).toEqual(phases);
  });
});
