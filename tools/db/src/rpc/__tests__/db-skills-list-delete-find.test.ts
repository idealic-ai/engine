import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-skills-upsert.js";
import "../db-skills-get.js";
// These will be created next:
import "../db-skills-list.js";
import "../db-skills-delete.js";
import "../db-skills-find.js";
import { createTestDb, queryCount } from "../../__tests__/helpers.js";

let db: Database;
beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
});
afterEach(() => {
  db.close();
});

// ── db.skills.list ──────────────────────────────────────

describe("db.skills.list", () => {
  it("should return all skills for a project", () => {
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, db);
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "brainstorm" } }, db);
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "test" } }, db);

    const result = dispatch({ cmd: "db.skills.list", args: { projectId: 1 } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as Record<string, unknown>[];
    expect(skills).toHaveLength(3);
    expect(skills.map((s) => s.name)).toEqual(
      expect.arrayContaining(["implement", "brainstorm", "test"])
    );
  });

  it("should return empty array when no skills exist", () => {
    const result = dispatch({ cmd: "db.skills.list", args: { projectId: 1 } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.skills).toEqual([]);
  });

  it("should return full JSONB columns parsed as objects", () => {
    const phases = [{ label: "0", name: "Setup" }];
    dispatch({
      cmd: "db.skills.upsert",
      args: { projectId: 1, name: "implement", phases },
    }, db);

    const result = dispatch({ cmd: "db.skills.list", args: { projectId: 1 } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as Record<string, unknown>[];
    expect(skills[0].phases).toEqual(phases);
  });
});

// ── db.skills.delete ────────────────────────────────────

describe("db.skills.delete", () => {
  it("should delete an existing skill", () => {
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, db);

    const result = dispatch({
      cmd: "db.skills.delete",
      args: { projectId: 1, name: "implement" },
    }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.deleted).toBe(true);
    expect(queryCount(db, "SELECT COUNT(*) FROM skills")).toBe(0);
  });

  it("should return deleted=false for non-existent skill", () => {
    const result = dispatch({
      cmd: "db.skills.delete",
      args: { projectId: 1, name: "nonexistent" },
    }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.deleted).toBe(false);
  });
});

// ── db.skills.find ──────────────────────────────────────

describe("db.skills.find", () => {
  it("should find skills by name substring", () => {
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, db);
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "brainstorm" } }, db);
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "improve-protocol" } }, db);

    const result = dispatch({
      cmd: "db.skills.find",
      args: { projectId: 1, query: "impl" },
    }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as Record<string, unknown>[];
    expect(skills).toHaveLength(1);
    expect(skills[0].name).toBe("implement");
  });

  it("should return empty array when no match", () => {
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, db);

    const result = dispatch({
      cmd: "db.skills.find",
      args: { projectId: 1, query: "zzz" },
    }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.skills).toEqual([]);
  });
});

// ── version & description columns ───────────────────────

describe("skills version and description columns", () => {
  it("should store and retrieve version via upsert/get", () => {
    dispatch({
      cmd: "db.skills.upsert",
      args: { projectId: 1, name: "implement", version: "3.0", description: "Drives feature implementation" },
    }, db);

    const result = dispatch({ cmd: "db.skills.get", args: { projectId: 1, name: "implement" } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    expect(skill.version).toBe("3.0");
    expect(skill.description).toBe("Drives feature implementation");
  });

  it("should preserve version/description on re-upsert without them", () => {
    dispatch({
      cmd: "db.skills.upsert",
      args: { projectId: 1, name: "implement", version: "3.0", description: "Original" },
    }, db);
    dispatch({
      cmd: "db.skills.upsert",
      args: { projectId: 1, name: "implement" },
    }, db);

    const result = dispatch({ cmd: "db.skills.get", args: { projectId: 1, name: "implement" } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    expect(skill.version).toBe("3.0");
    expect(skill.description).toBe("Original");
  });
});
