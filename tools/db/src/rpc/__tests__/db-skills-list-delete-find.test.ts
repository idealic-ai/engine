import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-skills-upsert.js";
import "../db-skills-get.js";
// These will be created next:
import "../db-skills-list.js";
import "../db-skills-delete.js";
import "../db-skills-find.js";
import { createTestDb, queryCount } from "../../__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
});
afterEach(async () => {
  await db.close();
});

// ── db.skills.list ──────────────────────────────────────

describe("db.skills.list", () => {
  it("should return all skills for a project", async () => {
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "brainstorm" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "test" } },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.skills.list", args: { projectId: 1 } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as Record<string, unknown>[];
    expect(skills).toHaveLength(3);
    expect(skills.map((s) => s.name)).toEqual(
      expect.arrayContaining(["implement", "brainstorm", "test"])
    );
  });

  it("should return empty array when no skills exist", async () => {
    const result = await dispatch({ cmd: "db.skills.list", args: { projectId: 1 } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.skills).toEqual([]);
  });

  it("should return full JSONB columns parsed as objects", async () => {
    const phases = [{ label: "0", name: "Setup" }];
    await dispatch({
      cmd: "db.skills.upsert",
      args: { projectId: 1, name: "implement", phases },
    },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.skills.list", args: { projectId: 1 } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as Record<string, unknown>[];
    expect(skills[0].phases).toEqual(phases);
  });
});

// ── db.skills.delete ────────────────────────────────────

describe("db.skills.delete", () => {
  it("should delete an existing skill", async () => {
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } },  { db } as unknown as RpcContext);

    const result = await dispatch({
      cmd: "db.skills.delete",
      args: { projectId: 1, name: "implement" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.deleted).toBe(true);
    expect(await queryCount(db, "SELECT COUNT(*) FROM skills")).toBe(0);
  });

  it("should return deleted=false for non-existent skill", async () => {
    const result = await dispatch({
      cmd: "db.skills.delete",
      args: { projectId: 1, name: "nonexistent" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.deleted).toBe(false);
  });
});

// ── db.skills.find ──────────────────────────────────────

describe("db.skills.find", () => {
  it("should find skills by name substring", async () => {
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "brainstorm" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "improve-protocol" } },  { db } as unknown as RpcContext);

    const result = await dispatch({
      cmd: "db.skills.find",
      args: { projectId: 1, query: "impl" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skills = result.data.skills as Record<string, unknown>[];
    expect(skills).toHaveLength(1);
    expect(skills[0].name).toBe("implement");
  });

  it("should return empty array when no match", async () => {
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } },  { db } as unknown as RpcContext);

    const result = await dispatch({
      cmd: "db.skills.find",
      args: { projectId: 1, query: "zzz" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.skills).toEqual([]);
  });
});

// ── version & description columns ───────────────────────

describe("skills version and description columns", () => {
  it("should store and retrieve version via upsert/get", async () => {
    await dispatch({
      cmd: "db.skills.upsert",
      args: { projectId: 1, name: "implement", version: "3.0", description: "Drives feature implementation" },
    },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.skills.get", args: { projectId: 1, name: "implement" } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    expect(skill.version).toBe("3.0");
    expect(skill.description).toBe("Drives feature implementation");
  });

  it("should preserve version/description on re-upsert without them", async () => {
    await dispatch({
      cmd: "db.skills.upsert",
      args: { projectId: 1, name: "implement", version: "3.0", description: "Original" },
    },  { db } as unknown as RpcContext);
    await dispatch({
      cmd: "db.skills.upsert",
      args: { projectId: 1, name: "implement" },
    },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.skills.get", args: { projectId: 1, name: "implement" } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const skill = result.data.skill as Record<string, unknown>;
    expect(skill.version).toBe("3.0");
    expect(skill.description).toBe("Original");
  });
});
