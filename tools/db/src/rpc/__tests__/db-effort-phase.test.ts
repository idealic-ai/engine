import type { RpcContext } from "engine-shared/context";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { DbConnection } from "../../db-wrapper.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-skills-upsert.js";
import "../db-effort-start.js";
import "../db-effort-phase.js";
import "../db-session-start.js";
import { createTestDb, queryRow, queryRows, queryCount } from "../../__tests__/helpers.js";

let db: DbConnection;
let effortId: number;

const PHASES = [
  { label: "0", name: "Setup" },
  { label: "1", name: "Interrogation" },
  { label: "2", name: "Planning" },
  { label: "3", name: "Execution" },
  { label: "3.A", name: "Build Loop" },
  { label: "4", name: "Synthesis" },
];

beforeEach(async () => {
  db = await createTestDb();
  await dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } },  { db } as unknown as RpcContext);
  await dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } },  { db } as unknown as RpcContext);
  await dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement", phases: PHASES } },  { db } as unknown as RpcContext);
  const r = await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } },  { db } as unknown as RpcContext);
  effortId = ((r as any).data.effort as any).id;
});
afterEach(async () => { await db.close(); });

describe("db.effort.phase", () => {
  it("should set initial phase (from null)", async () => {
    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.currentPhase).toBe("0: Setup");
  });

  it("should allow sequential progression", async () => {
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },  { db } as unknown as RpcContext);
    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "1: Interrogation" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.effort as any).currentPhase).toBe("1: Interrogation");
  });

  it("should reject non-sequential without reason", async () => {
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },  { db } as unknown as RpcContext);
    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "2: Planning" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("PHASE_NOT_SEQUENTIAL");
  });

  it("should allow non-sequential with reason", async () => {
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },  { db } as unknown as RpcContext);
    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "2: Planning", reason: "User approved skip" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
  });

  it("should be no-op when re-entering same phase", async () => {
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },  { db } as unknown as RpcContext);
    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
    // Should not duplicate phase_history
    expect(await queryCount(db, "SELECT COUNT(*) FROM phase_history WHERE effort_id = ?", [effortId])).toBe(1);
  });

  it("should store proof in phase_history", async () => {
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },  { db } as unknown as RpcContext);
    await dispatch({
      cmd: "db.effort.phase",
      args: { effortId, phase: "1: Interrogation", proof: { depthChosen: "Short", roundsCompleted: 3 } },
    },  { db } as unknown as RpcContext);

    const row = await queryRow(
      db,
      "SELECT json(proof) as proof FROM phase_history WHERE phase_label = '1: Interrogation'"
    );
    const proof = typeof row!.proof === "string" ? JSON.parse(row!.proof as string) : row!.proof as Record<string, unknown>;
    expect(proof.depthChosen).toBe("Short");
    expect(proof.roundsCompleted).toBe(3);
  });

  it("should allow sub-phase skip: 3.A→4 (exit sub-phase to next major)", async () => {
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "1: Interrogation" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "2: Planning" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "3: Execution" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "3.A: Build Loop" } },  { db } as unknown as RpcContext);

    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "4: Synthesis" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
  });

  it("should auto-append undeclared sub-phase", async () => {
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "1: Interrogation" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "2: Planning" } },  { db } as unknown as RpcContext);
    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "3: Execution" } },  { db } as unknown as RpcContext);

    // 3.B is not in original phases — should auto-append
    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "3.B: Agent Handoff" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
  });

  it("should reset heartbeat on active session", async () => {
    // Create a session for the effort
    await dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 123 } },  { db } as unknown as RpcContext);
    // Bump heartbeat manually
    await db.run("UPDATE sessions SET heartbeat_counter = 5 WHERE effort_id = ?", [effortId]);

    await dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },  { db } as unknown as RpcContext);

    const session = await queryRow(
      db,
      "SELECT heartbeat_counter FROM sessions WHERE effort_id = ? AND ended_at IS NULL",
      [effortId]
    );
    expect(session!.heartbeatCounter).toBe(0);
  });

  it("should reject non-existent effort", async () => {
    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId: 999, phase: "0: Setup" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("NOT_FOUND");
  });

  it("should reject phase on finished effort", async () => {
    await db.run("UPDATE efforts SET lifecycle = 'finished', finished_at = datetime('now') WHERE id = ?", [effortId]);
    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("EFFORT_FINISHED");
  });

  it("should work without skills table phases (no enforcement)", async () => {
    // Create effort for a skill with no phases
    await dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "do" } },  { db } as unknown as RpcContext);
    const result = await dispatch(
      { cmd: "db.effort.phase", args: { effortId: 2, phase: "5: Anything" } },
      { db } as unknown as RpcContext
    );
    expect(result.ok).toBe(true);
  });
});
