import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-skills-upsert.js";
import "../db-effort-start.js";
import "../db-agents-register.js";
import "../db-agents-get.js";
import "../db-agents-list.js";
import "../db-agents-update-status.js";
import "../db-agents-find-by-effort.js";
import { createTestDb, queryCount } from "../../__tests__/helpers.js";

let db: DbConnection;
beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
});
afterEach(async () => {
  await db.close();
});

describe("db.agents.register", () => {
  it("should register a new agent", async () => {
    const result = await dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "auth:Worker-1", claims: "implementation,fix" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const agent = result.data.agent as Record<string, unknown>;
    expect(agent.id).toBe("worker-1");
    expect(agent.label).toBe("auth:Worker-1");
    expect(agent.claims).toBe("implementation,fix");
  });

  it("should upsert on duplicate id", async () => {
    await dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "old-label", claims: "fix" },
    },  { db } as unknown as RpcContext);
    await dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "new-label", claims: "implementation" },
    },  { db } as unknown as RpcContext);

    expect(await queryCount(db, "SELECT COUNT(*) FROM agents")).toBe(1);
    const result = await dispatch({ cmd: "db.agents.get", args: { id: "worker-1" } },  { db } as unknown as RpcContext);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const agent = result.data.agent as Record<string, unknown>;
    expect(agent.label).toBe("new-label");
    expect(agent.claims).toBe("implementation");
  });

  it("should register with optional effortId FK", async () => {
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/t1", projectId: 1 } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/t1", skill: "implement" } },  { db } as unknown as RpcContext);

    const result = await dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", effortId: 1 },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agent).toHaveProperty("effortId", 1);
  });
});

describe("db.agents.get", () => {
  it("should return agent by id", async () => {
    await dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "main:Worker" },
    },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.agents.get", args: { id: "worker-1" } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agent).toHaveProperty("id", "worker-1");
    expect(result.data.agent).toHaveProperty("label", "main:Worker");
  });

  it("should return null for non-existent agent", async () => {
    const result = await dispatch({ cmd: "db.agents.get", args: { id: "ghost" } },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agent).toBeNull();
  });
});

describe("db.agents.list", () => {
  it("should list all agents", async () => {
    await dispatch({ cmd: "db.agents.register", args: { id: "w1", label: "Worker-1" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.agents.register", args: { id: "w2", label: "Worker-2" } },  { db } as unknown as RpcContext);

    const result = await dispatch({ cmd: "db.agents.list", args: {} },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agents).toHaveLength(2);
  });

  it("should return empty array when no agents", async () => {
    const result = await dispatch({ cmd: "db.agents.list", args: {} },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agents).toEqual([]);
  });
});

describe("db.agents.register — status field", () => {
  it("should register with optional status", async () => {
    const result = await dispatch({
      cmd: "db.agents.register",
      args: { id: "w1", label: "Worker", status: "working" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const agent = result.data.agent as Record<string, unknown>;
    expect(agent.status).toBe("working");
  });

  it("should default status to null when not provided", async () => {
    const result = await dispatch({
      cmd: "db.agents.register",
      args: { id: "w1", label: "Worker" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const agent = result.data.agent as Record<string, unknown>;
    expect(agent.status).toBeNull();
  });
});

describe("db.agents.updateStatus", () => {
  it("should update an existing agent's status", async () => {
    await dispatch({ cmd: "db.agents.register", args: { id: "w1", label: "Worker" } },  { db } as unknown as RpcContext);

    const result = await dispatch({
      cmd: "db.agents.updateStatus",
      args: { id: "w1", status: "working" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const agent = result.data.agent as Record<string, unknown>;
    expect(agent.id).toBe("w1");
    expect(agent.status).toBe("working");
  });

  it("should transition between valid statuses", async () => {
    await dispatch({ cmd: "db.agents.register", args: { id: "w1" } },  { db } as unknown as RpcContext);

    for (const status of ["working", "idle", "attention", "error", "done"] as const) {
      const result = await dispatch({
        cmd: "db.agents.updateStatus",
        args: { id: "w1", status },
      },  { db } as unknown as RpcContext);
      expect(result.ok).toBe(true);
      if (!result.ok) return;
      expect((result.data.agent as Record<string, unknown>).status).toBe(status);
    }
  });

  it("should return NOT_FOUND for unknown agent", async () => {
    const result = await dispatch({
      cmd: "db.agents.updateStatus",
      args: { id: "ghost", status: "done" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("NOT_FOUND");
  });

  it("should reject invalid status values", async () => {
    await dispatch({ cmd: "db.agents.register", args: { id: "w1" } },  { db } as unknown as RpcContext);

    const result = await dispatch({
      cmd: "db.agents.updateStatus",
      args: { id: "w1", status: "invalid-status" },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(false);
  });
});

describe("db.agents.findByEffort", () => {
  async function setupEffort() {
    await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/t1", projectId: 1 } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement" } },  { db } as unknown as RpcContext);
    const effortResult = await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/t1", skill: "implement" } },  { db } as unknown as RpcContext);
    return effortResult;
  }

  it("should find agent bound to an effort", async () => {
    await setupEffort();
    await dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "main:Worker", effortId: 1 },
    },  { db } as unknown as RpcContext);

    const result = await dispatch({
      cmd: "db.agents.findByEffort",
      args: { effortId: 1 },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agent).not.toBeNull();
    expect((result.data.agent as Record<string, unknown>).id).toBe("worker-1");
  });

  it("should return null when no agent for effort", async () => {
    await setupEffort();

    const result = await dispatch({
      cmd: "db.agents.findByEffort",
      args: { effortId: 1 },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agent).toBeNull();
  });

  it("should return first agent when multiple agents for same effort", async () => {
    await setupEffort();
    await dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-1", label: "Worker-1", effortId: 1 },
    },  { db } as unknown as RpcContext);
    await dispatch({
      cmd: "db.agents.register",
      args: { id: "worker-2", label: "Worker-2", effortId: 1 },
    },  { db } as unknown as RpcContext);

    const result = await dispatch({
      cmd: "db.agents.findByEffort",
      args: { effortId: 1 },
    },  { db } as unknown as RpcContext);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.agent).not.toBeNull();
    // db.get returns first row — either agent is acceptable
    expect(["worker-1", "worker-2"]).toContain((result.data.agent as Record<string, unknown>).id);
  });
});
