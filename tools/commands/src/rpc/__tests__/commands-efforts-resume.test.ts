import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "engine-db/db-wrapper";
import { dispatch } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";
import { createTestContext } from "engine-shared/__tests__/test-context";
import "engine-db/rpc/registry";
import "engine-agent/rpc/registry";
import "../commands-effort-start.js";
import "../commands-efforts-resume.js";
import { createTestDb } from "engine-db/__tests__/helpers";

let db: DbConnection;
let ctx: RpcContext;

beforeEach(async () => {
  db = await createTestDb();
  ctx = createTestContext(db);
});

afterEach(async () => {
  await db.close();
});

describe("commands.efforts.resume", () => {
  const startArgs = {
    taskName: "TEST_RESUME",
    skill: "implement",
    projectPath: "/proj",
    skipSearch: true,
  };

  async function setupEffort() {
    const result = await dispatch(
      { cmd: "commands.effort.start", args: startArgs },
      ctx
    );
    if (!result.ok) throw new Error("Setup failed");
    return result.data;
  }

  it("should create continuation session linked to previous", async () => {
    const { session: prevSession, effort } = await setupEffort();
    const prevId = (prevSession as Record<string, unknown>).id as number;

    const result = await dispatch(
      {
        cmd: "commands.efforts.resume",
        args: { dirPath: "/proj/.tasks/test_resume", projectPath: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const newSession = result.data.session as Record<string, unknown>;
    expect(newSession.prevSessionId).toBe(prevId);
    expect(newSession.effortId).toBe((effort as Record<string, unknown>).id);
  });

  it("should return continuation markdown with skill and phase", async () => {
    await setupEffort();

    const result = await dispatch(
      {
        cmd: "commands.efforts.resume",
        args: { dirPath: "/proj/.tasks/test_resume", projectPath: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const md = result.data.markdown as string;
    expect(md).toContain("Session continued: /proj/.tasks/test_resume");
    expect(md).toContain("Skill: implement");
  });

  it("should return null dehydration when session was not overflowed", async () => {
    const { session: prevSession } = await setupEffort();
    const prevId = (prevSession as Record<string, unknown>).id as number;

    const result = await dispatch(
      {
        cmd: "commands.efforts.resume",
        args: { dirPath: "/proj/.tasks/test_resume", projectPath: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.dehydration).toBeNull();
    const newSession = result.data.session as Record<string, unknown>;
    expect(newSession.prevSessionId).toBe(prevId);
  });

  it("should return NO_ACTIVE_EFFORT when no efforts exist", async () => {
    await dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj" } },
      ctx
    );
    await dispatch(
      { cmd: "db.task.upsert", args: { dirPath: "sessions/empty", projectId: 1 } },
      ctx
    );

    const result = await dispatch(
      {
        cmd: "commands.efforts.resume",
        args: { dirPath: "sessions/empty", projectPath: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("NO_ACTIVE_EFFORT");
  });

  it("should find effort by agentId", async () => {
    const { effort } = await setupEffort();
    const effortId = (effort as Record<string, unknown>).id as number;

    await dispatch(
      { cmd: "db.agents.register", args: { id: "agent-1", effortId } },
      ctx
    );

    const result = await dispatch(
      {
        cmd: "commands.efforts.resume",
        args: { agentId: "agent-1", projectPath: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const s = result.data.session as Record<string, unknown>;
    expect(s.effortId).toBe(effortId);
  });

  it("should reject when neither dirPath nor agentId provided", async () => {
    const result = await dispatch(
      {
        cmd: "commands.efforts.resume",
        args: { projectPath: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(false);
  });

  it("should return NO_ACTIVE_EFFORT when agent has no effort", async () => {
    await dispatch(
      { cmd: "db.agents.register", args: { id: "orphan" } },
      ctx
    );

    const result = await dispatch(
      {
        cmd: "commands.efforts.resume",
        args: { agentId: "orphan", projectPath: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("NO_ACTIVE_EFFORT");
  });

  it("should pick most recent effort by ordinal", async () => {
    for (let i = 0; i < 3; i++) {
      const r = await dispatch(
        { cmd: "commands.effort.start", args: startArgs },
        ctx
      );
      if (!r.ok) throw new Error("Setup failed");
      const eid = (r.data.effort as Record<string, unknown>).id as number;
      await dispatch({ cmd: "db.effort.finish", args: { effortId: eid } }, ctx);
    }

    const result = await dispatch(
      {
        cmd: "commands.efforts.resume",
        args: { dirPath: "/proj/.tasks/test_resume", projectPath: "/proj" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const e = result.data.effort as Record<string, unknown>;
    expect(e.ordinal).toBe(3);
  });
});
