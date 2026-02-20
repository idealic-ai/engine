import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Database } from "sql.js";
import { dispatch } from "../dispatch.js";
import "../db-project-upsert.js";
import "../db-task-upsert.js";
import "../db-skills-upsert.js";
import "../db-effort-start.js";
import "../db-effort-phase.js";
import "../db-session-start.js";
import { createTestDb, queryRow, queryRows, queryCount } from "../../__tests__/helpers.js";

let db: Database;
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
  dispatch({ cmd: "db.project.upsert", args: { path: "/proj" } }, db);
  dispatch({ cmd: "db.task.upsert", args: { dirPath: "sessions/test", projectId: 1 } }, db);
  dispatch({ cmd: "db.skills.upsert", args: { projectId: 1, name: "implement", phases: PHASES } }, db);
  const r = dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "implement" } }, db);
  effortId = ((r as any).data.effort as any).id;
});
afterEach(() => { db.close(); });

describe("db.effort.phase", () => {
  it("should set initial phase (from null)", () => {
    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },
      db
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const effort = result.data.effort as Record<string, unknown>;
    expect(effort.current_phase).toBe("0: Setup");
  });

  it("should allow sequential progression", () => {
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } }, db);
    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "1: Interrogation" } },
      db
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect((result.data.effort as any).current_phase).toBe("1: Interrogation");
  });

  it("should reject non-sequential without reason", () => {
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } }, db);
    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "2: Planning" } },
      db
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("PHASE_NOT_SEQUENTIAL");
  });

  it("should allow non-sequential with reason", () => {
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } }, db);
    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "2: Planning", reason: "User approved skip" } },
      db
    );
    expect(result.ok).toBe(true);
  });

  it("should be no-op when re-entering same phase", () => {
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } }, db);
    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },
      db
    );
    expect(result.ok).toBe(true);
    // Should not duplicate phase_history
    expect(queryCount(db, "SELECT COUNT(*) FROM phase_history WHERE effort_id = ?", [effortId])).toBe(1);
  });

  it("should store proof in phase_history", () => {
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } }, db);
    dispatch({
      cmd: "db.effort.phase",
      args: { effortId, phase: "1: Interrogation", proof: { depthChosen: "Short", roundsCompleted: 3 } },
    }, db);

    const row = queryRow(
      db,
      "SELECT json(proof) as proof FROM phase_history WHERE phase_label = '1: Interrogation'"
    );
    const proof = JSON.parse(row!.proof as string);
    expect(proof.depthChosen).toBe("Short");
    expect(proof.roundsCompleted).toBe(3);
  });

  it("should allow sub-phase skip: 3.A→4 (exit sub-phase to next major)", () => {
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } }, db);
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "1: Interrogation" } }, db);
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "2: Planning" } }, db);
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "3: Execution" } }, db);
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "3.A: Build Loop" } }, db);

    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "4: Synthesis" } },
      db
    );
    expect(result.ok).toBe(true);
  });

  it("should auto-append undeclared sub-phase", () => {
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } }, db);
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "1: Interrogation" } }, db);
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "2: Planning" } }, db);
    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "3: Execution" } }, db);

    // 3.B is not in original phases — should auto-append
    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "3.B: Agent Handoff" } },
      db
    );
    expect(result.ok).toBe(true);
  });

  it("should reset heartbeat on active session", () => {
    // Create a session for the effort
    dispatch({ cmd: "db.session.start", args: { taskId: "sessions/test", effortId, pid: 123 } }, db);
    // Bump heartbeat manually
    db.run("UPDATE sessions SET heartbeat_counter = 5 WHERE effort_id = ?", [effortId]);

    dispatch({ cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } }, db);

    const session = queryRow(
      db,
      "SELECT heartbeat_counter FROM sessions WHERE effort_id = ? AND ended_at IS NULL",
      [effortId]
    );
    expect(session!.heartbeat_counter).toBe(0);
  });

  it("should reject non-existent effort", () => {
    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId: 999, phase: "0: Setup" } },
      db
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("NOT_FOUND");
  });

  it("should reject phase on finished effort", () => {
    db.run("UPDATE efforts SET lifecycle = 'finished', finished_at = datetime('now') WHERE id = ?", [effortId]);
    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId, phase: "0: Setup" } },
      db
    );
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("EFFORT_FINISHED");
  });

  it("should work without skills table phases (no enforcement)", () => {
    // Create effort for a skill with no phases
    dispatch({ cmd: "db.effort.start", args: { taskId: "sessions/test", skill: "do" } }, db);
    const result = dispatch(
      { cmd: "db.effort.phase", args: { effortId: 2, phase: "5: Anything" } },
      db
    );
    expect(result.ok).toBe(true);
  });
});
