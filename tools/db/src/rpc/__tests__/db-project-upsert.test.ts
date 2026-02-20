import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import { createTestDb, queryRow, queryCount } from "../../__tests__/helpers.js";

let db: Database;
beforeEach(async () => {
  db = await createTestDb();
});
afterEach(() => {
  db.close();
});

describe("db.project.upsert", () => {
  it("should create a project with path", () => {
    const result = dispatch(
      { cmd: "db.project.upsert", args: { path: "/home/user/myproject" } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.project).toBeDefined();
    const project = result.data.project as Record<string, unknown>;
    expect(project.path).toBe("/home/user/myproject");
    expect(project.id).toBe(1);
    expect(project.created_at).toBeTruthy();
  });

  it("should create a project with path and name", () => {
    const result = dispatch(
      {
        cmd: "db.project.upsert",
        args: { path: "/home/user/myproject", name: "My Project" },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const project = result.data.project as Record<string, unknown>;
    expect(project.path).toBe("/home/user/myproject");
    expect(project.name).toBe("My Project");
  });

  it("should be idempotent — upsert same path returns same project", () => {
    dispatch(
      { cmd: "db.project.upsert", args: { path: "/home/user/proj" } },
      db
    );
    const result = dispatch(
      { cmd: "db.project.upsert", args: { path: "/home/user/proj" } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const project = result.data.project as Record<string, unknown>;
    expect(project.id).toBe(1);
    expect(queryCount(db, "SELECT COUNT(*) FROM projects")).toBe(1);
  });

  it("should update name on re-upsert", () => {
    dispatch(
      {
        cmd: "db.project.upsert",
        args: { path: "/proj", name: "Old Name" },
      },
      db
    );
    const result = dispatch(
      {
        cmd: "db.project.upsert",
        args: { path: "/proj", name: "New Name" },
      },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const project = result.data.project as Record<string, unknown>;
    expect(project.name).toBe("New Name");
  });

  it("should preserve name when re-upsert omits it", () => {
    dispatch(
      {
        cmd: "db.project.upsert",
        args: { path: "/proj", name: "Keep Me" },
      },
      db
    );
    const result = dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj" } },
      db
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const project = result.data.project as Record<string, unknown>;
    expect(project.name).toBe("Keep Me");
  });

  it("should create distinct projects for different paths", () => {
    dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj1" } },
      db
    );
    dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj2" } },
      db
    );

    expect(queryCount(db, "SELECT COUNT(*) FROM projects")).toBe(2);
  });

  it("should reject missing path", () => {
    const result = dispatch(
      { cmd: "db.project.upsert", args: {} },
      db
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("VALIDATION_ERROR");
  });
});
