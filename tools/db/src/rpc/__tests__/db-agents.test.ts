import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-skills-upsert.js";
import "../db-effort-start.js";
import "../db-agents-register.js";
import "../db-agents-get.js";
import "../db-agents-list.js";
import { createTestDb, queryCount } from "../../__tests__/helpers.js";

let db: Database;
beforeEach(async () => {
  db = await createTestDb();
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
});
afterEach(() => {
  db.close();
});

describe("db.agents.register", () => {
  it("should register a new agent", () => {
    const result = dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "auth:Worker-1", claims: "implementation,fix" },
    }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const agent = result.data.agent as Record<string, unknown>;
    expect(agent.id).toBe("worker-1");
    expect(agent.label).toBe("auth:Worker-1");
    expect(agent.claims).toBe("implementation,fix");
  });

  it("should upsert on duplicate id", () => {
    dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "old-label", claims: "fix" },
    }, db);
    dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "new-label", claims: "implementation" },
    }, db);

    expect(queryCount(db, "SELECT COUNT(*) FROM agents")).toBe(1);
    const result = dispatch({ cmd: "db.agents.get", args: { id: "worker-1" } }, db);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const agent = result.data.agent as Record<string, unknown>;
    expect(agent.label).toBe("new-label");
    expect(agent.claims).toBe("implementation");
  });

  it("should register with optional effortId FK", () => {
    dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/t1", projectId: 1 } }, db);
    dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } }, db);
    dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/t1", skill: "implement" } }, db);

    const result = dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", effortId: 1 },
    }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agent).toHaveProperty("effort_id", 1);
  });
});

describe("db.agents.get", () => {
  it("should return agent by id", () => {
    dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "main:Worker" },
    }, db);

    const result = dispatch({ cmd: "db.agents.get", args: { id: "worker-1" } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agent).toHaveProperty("id", "worker-1");
    expect(result.data.agent).toHaveProperty("label", "main:Worker");
  });

  it("should return null for non-existent agent", () => {
    const result = dispatch({ cmd: "db.agents.get", args: { id: "ghost" } }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agent).toBeNull();
  });
});

describe("db.agents.list", () => {
  it("should list all agents", () => {
    dispatch({ cmd: "db.agents.register", args: { id: "w1", label: "Worker-1" } }, db);
    dispatch({ cmd: "db.agents.register", args: { id: "w2", label: "Worker-2" } }, db);

    const result = dispatch({ cmd: "db.agents.list", args: {} }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agents).toHaveLength(2);
  });

  it("should return empty array when no agents", () => {
    const result = dispatch({ cmd: "db.agents.list", args: {} }, db);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agents).toEqual([]);
  });
});
