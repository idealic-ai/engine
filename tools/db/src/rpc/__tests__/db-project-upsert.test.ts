import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import { createTestDb, queryRow, queryCount } from "../../__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
});
afterEach(async () => {
  await db.close();
});

describe("db.project.upsert", () => {
  it("should create a project with path", async () => {
    const result = await dispatch(
      { cmd: "db.project.upsert", args: { path: "/home/user/myproject" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.project).toBeDefined();
    const project = result.data.project as Record<string, unknown>;
    expect(project.path).toBe("/home/user/myproject");
    expect(project.id).toBe(1);
    expect(project.createdAt).toBeTruthy();
  });

  it("should create a project with path and name", async () => {
    const result = await dispatch(
      {
        cmd: "db.project.upsert",
        args: { path: "/home/user/myproject", name: "My Project" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const project = result.data.project as Record<string, unknown>;
    expect(project.path).toBe("/home/user/myproject");
    expect(project.name).toBe("My Project");
  });

  it("should be idempotent — upsert same path returns same project", async () => {
    await dispatch(
      { cmd: "db.project.upsert", args: { path: "/home/user/proj" } },
      { db } as unknown as RpcContext
    );
    const result = await dispatch(
      { cmd: "db.project.upsert", args: { path: "/home/user/proj" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const project = result.data.project as Record<string, unknown>;
    expect(project.id).toBe(1);
    expect(await queryCount(db, "SELECT COUNT(*) FROM projects")).toBe(1);
  });

  it("should update name on re-upsert", async () => {
    await dispatch(
      {
        cmd: "db.project.upsert",
        args: { path: "/proj", name: "Old Name" },
      },
      { db } as unknown as RpcContext
    );
    const result = await dispatch(
      {
        cmd: "db.project.upsert",
        args: { path: "/proj", name: "New Name" },
      },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const project = result.data.project as Record<string, unknown>;
    expect(project.name).toBe("New Name");
  });

  it("should preserve name when re-upsert omits it", async () => {
    await dispatch(
      {
        cmd: "db.project.upsert",
        args: { path: "/proj", name: "Keep Me" },
      },
      { db } as unknown as RpcContext
    );
    const result = await dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj" } },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const project = result.data.project as Record<string, unknown>;
    expect(project.name).toBe("Keep Me");
  });

  it("should create distinct projects for different paths", async () => {
    await dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj1" } },
      { db } as unknown as RpcContext
    );
    await dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj2" } },
      { db } as unknown as RpcContext
    );

    expect(await queryCount(db, "SELECT COUNT(*) FROM projects")).toBe(2);
  });

  it("should reject missing path", async () => {
    const result = await dispatch(
      { cmd: "db.project.upsert", args: {} },
      { db } as unknown as RpcContext
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });
});
