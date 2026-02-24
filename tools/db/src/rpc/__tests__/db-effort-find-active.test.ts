import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-effort-start.js";
import "../db-effort-find-active.js";
import "../db-agents-register.js";
import { createTestDb } from "../../__tests__/helpers.js";

let db: DbConnection;
let ctx: RpcContext;

beforeEach(async () => {
  db = await createTestDb();
  ctx = { db } as unknown as RpcContext;
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, ctx);
  await dispatch(
    { cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },
    ctx
  );
});

afterEach(async () => {
  await db.close();
});

describe("db.effort.findActive", () => {
  it("should return nulls when no active effort exists", async () => {
    const result = await dispatch(
      { cmd: "db.effort.findActive", args: { projectId: 1 } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.effort).toBeNull();
    expect(result.data.taskDir).toBeNull();
  });

  it("should return the latest active effort for solo/default (no agentId)", async () => {
    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      ctx
    );

    const result = await dispatch(
      { cmd: "db.effort.findActive", args: { projectId: 1 } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.effort).not.toBeNull();
    expect(result.data.effort!.skill).toBe("implement");
    expect(result.data.effort!.lifecycle).toBe("active");
    expect(result.data.taskDir).toBe("sessions/test");
  });

  it("should return agent-specific effort when agentId matches", async () => {
    // Create effort and bind agent separately
    const startResult = await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      ctx
    );
    expect(startResult.ok).toBe(true);
    await dispatch(
      { cmd: "db.agents.register", args: { id: "worker-1", effortId: 1 } },
      ctx
    );

    const result = await dispatch(
      { cmd: "db.effort.findActive", args: { projectId: 1, agentId: "worker-1" } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.effort).not.toBeNull();
    expect(result.data.effort!.skill).toBe("implement");
  });

  it("should fall back to latest effort when agentId doesn't match any agent", async () => {
    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      ctx
    );

    const result = await dispatch(
      { cmd: "db.effort.findActive", args: { projectId: 1, agentId: "nonexistent-agent" } },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    // Falls through agent lookup (no match) to non-fleet fallback
    expect(result.data.effort).not.toBeNull();
    expect(result.data.effort!.skill).toBe("implement");
  });

  it("should isolate agents to their own efforts in multi-agent scenario", async () => {
    // Create second task for second agent
    await dispatch(
      { cmd: "db.task.upsert", args: { dirPath: "sessions/test2", projectId: 1 } },
      ctx
    );

    // Effort 1 + bind agent-1
    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      ctx
    );
    await dispatch(
      { cmd: "db.agents.register", args: { id: "agent-1", effortId: 1 } },
      ctx
    );

    // Effort 2 + bind agent-2
    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test2", skill: "brainstorm" } },
      ctx
    );
    await dispatch(
      { cmd: "db.agents.register", args: { id: "agent-2", effortId: 2 } },
      ctx
    );

    // Agent 1 should resolve to effort 1 (implement)
    const result1 = await dispatch(
      { cmd: "db.effort.findActive", args: { projectId: 1, agentId: "agent-1" } },
      ctx
    );
    expect(result1.ok).toBe(true);
    if (!result1.ok) return;
    expect(result1.data.effort!.skill).toBe("implement");

    // Agent 2 should resolve to effort 2 (brainstorm)
    const result2 = await dispatch(
      { cmd: "db.effort.findActive", args: { projectId: 1, agentId: "agent-2" } },
      ctx
    );
    expect(result2.ok).toBe(true);
    if (!result2.ok) return;
    expect(result2.data.effort!.skill).toBe("brainstorm");
  });

  it("should return latest effort when no agentId in multi-agent scenario", async () => {
    await dispatch(
      { cmd: "db.task.upsert", args: { dirPath: "sessions/test2", projectId: 1 } },
      ctx
    );

    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },
      ctx
    );
    await dispatch(
      { cmd: "db.agents.register", args: { id: "agent-1", effortId: 1 } },
      ctx
    );
    await dispatch(
      { cmd: "db.effort.start", args: { taskId: "sessions/test2", skill: "brainstorm" } },
      ctx
    );
    await dispatch(
      { cmd: "db.agents.register", args: { id: "agent-2", effortId: 2 } },
      ctx
    );

    // No agentId → returns latest (brainstorm, created second)
    const result = await dispatch(
      { cmd: "db.effort.findActive", args: { projectId: 1 } },
      ctx
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.effort!.skill).toBe("brainstorm");
  });
});
