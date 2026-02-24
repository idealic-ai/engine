import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../../../db/src/db-wrapper.js";
import { dispatch } from "../../../../db/src/rpc/dispatch.js";
import { getRegistry } from "engine-shared/dispatch";
import { buildNamespace } from "engine-shared/namespace-builder";
import { createTestContext } from "engine-shared/__tests__/test-context";
import "../../../../db/src/rpc/registry.js";
import "../../../../agent/src/rpc/registry.js";
import "../../../../fs/src/rpc/registry.js";
import "../hooks-fleet-start.js";
import { createTestDb } from "../../../../db/src/__tests__/helpers.js";

let db: DbConnection;
let ctx: RpcContext;

beforeEach(async () => {
  db = await createTestDb();
  ctx = createTestContext(db);
  // Add fs namespace for agent.skills.parse (reads SKILL.md from filesystem)
  const registry = getRegistry();
  ctx.fs = buildNamespace("fs", registry, ctx) as unknown as RpcContext["fs"];
});

afterEach(async () => {
  await db.close();
});

describe("hooks.fleet-start", () => {
  it("should parse SKILL.md files and cache via db.skills.upsert", async () => {
    // Ensure project exists
    await dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj" } },
      ctx
    );

    const result = await dispatch(
      {
        cmd: "hooks.fleet-start",
        args: {
          projectPath: "/proj",
          skillPaths: [
            // Use the actual implement SKILL.md as test fixture
            `${process.env.HOME}/.claude/skills/implement/SKILL.md`,
          ],
        },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.data.cached).toBe(1);
    expect(result.data.errors).toHaveLength(0);

    // Verify skill was cached in DB
    const skillResult = await dispatch(
      { cmd: "db.skills.get", args: { name: "implement", projectId: 1 } },
      ctx
    );
    expect(skillResult.ok).toBe(true);
    if (!skillResult.ok) return;

    const skill = skillResult.data.skill as Record<string, unknown>;
    expect(skill).not.toBeNull();
    expect(skill.name).toBe("implement");
    expect(skill.phases).toBeDefined();
    expect(skill.description).toBeDefined();
  });

  it("should handle missing SKILL.md gracefully", async () => {
    await dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj" } },
      ctx
    );

    const result = await dispatch(
      {
        cmd: "hooks.fleet-start",
        args: {
          projectPath: "/proj",
          skillPaths: ["/nonexistent/SKILL.md"],
        },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.data.cached).toBe(0);
    expect(result.data.errors).toHaveLength(1);
    expect(result.data.errors[0]).toContain("/nonexistent/SKILL.md");
  });

  it("should cache multiple skills", async () => {
    await dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj" } },
      ctx
    );

    const result = await dispatch(
      {
        cmd: "hooks.fleet-start",
        args: {
          projectPath: "/proj",
          skillPaths: [
            `${process.env.HOME}/.claude/skills/implement/SKILL.md`,
            `${process.env.HOME}/.claude/skills/test/SKILL.md`,
          ],
        },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.data.cached).toBe(2);
    expect(result.data.errors).toHaveLength(0);
  });
});
