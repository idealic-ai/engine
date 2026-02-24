import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import type { DbConnection } from "engine-db/db-wrapper";
import { dispatch } from "engine-shared/dispatch";
import type { RpcContext } from "engine-shared/context";
import { createTestContext } from "engine-shared/__tests__/test-context";
import "engine-db/rpc/registry";
import "engine-agent/rpc/registry";
import "../../../../fs/src/rpc/fs-files-append.js";
import "../commands-effort-start.js";
import "../commands-log-append.js";
import { createTestDb } from "engine-db/__tests__/helpers";
import { injectTimestamp } from "../commands-log-append.js";

let db: DbConnection;
let ctx: RpcContext;
let tmpDir: string;

beforeEach(async () => {
  db = await createTestDb();
  ctx = createTestContext(db);
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "cmd-log-"));
});

afterEach(async () => {
  await db.close();
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

describe("commands.log.append", () => {
  /** Create effort and return the derived taskDir (also creates it on disk) */
  async function setupEffortInTmp(taskName: string) {
    const result = await dispatch(
      {
        cmd: "commands.effort.start",
        args: {
          taskName,
          skill: "implement",
          projectPath: tmpDir,
          skipSearch: true,
        },
      },
      ctx
    );
    if (!result.ok) throw new Error(`Setup failed: ${JSON.stringify(result)}`);
    const taskDir = path.join(tmpDir, ".tasks", taskName.toLowerCase());
    fs.mkdirSync(taskDir, { recursive: true });
    return { ...result.data, taskDir };
  }

  it("should append to effort-prefixed log file", async () => {
    const { taskDir } = await setupEffortInTmp("LOG_TEST_1");

    const result = await dispatch(
      {
        cmd: "commands.log.append",
        args: {
          dirPath: taskDir,
          content: "## Progress\n*   **Task**: Built auth\n*   **Status**: done",
        },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const filePath = result.data.filePath as string;
    expect(filePath).toContain("1_IMPLEMENT_LOG.md");
    expect(result.data.effortOrdinal).toBe(1);

    // Verify file was written
    const content = fs.readFileSync(filePath, "utf-8");
    expect(content).toContain("## [");
    expect(content).toContain("Progress");
    expect(content).toContain("Built auth");
  });

  it("should append with separator to existing file", async () => {
    const { taskDir } = await setupEffortInTmp("LOG_TEST_2");

    // First append
    await dispatch(
      {
        cmd: "commands.log.append",
        args: { dirPath: taskDir, content: "## Entry 1\n*   First" },
      },
      ctx
    );

    // Second append
    await dispatch(
      {
        cmd: "commands.log.append",
        args: { dirPath: taskDir, content: "## Entry 2\n*   Second" },
      },
      ctx
    );

    const filePath = path.join(taskDir, "1_IMPLEMENT_LOG.md");
    const content = fs.readFileSync(filePath, "utf-8");

    // Both entries present, separated by newline
    expect(content).toContain("Entry 1");
    expect(content).toContain("Entry 2");
    expect(content).toContain("First");
    expect(content).toContain("Second");
  });

  it("should fail when no active effort exists", async () => {
    // Create project + task but no effort
    await dispatch(
      { cmd: "db.project.upsert", args: { path: "/proj" } },
      ctx
    );
    await dispatch(
      { cmd: "db.task.upsert", args: { dirPath: "sessions/no_effort", projectId: 1 } },
      ctx
    );

    const result = await dispatch(
      {
        cmd: "commands.log.append",
        args: { dirPath: "sessions/no_effort", content: "## Test\n*   data" },
      },
      ctx
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("NO_ACTIVE_EFFORT");
  });

  it("should use custom logType", async () => {
    const { taskDir } = await setupEffortInTmp("LOG_TEST_3");

    const result = await dispatch(
      {
        cmd: "commands.log.append",
        args: {
          dirPath: taskDir,
          content: "## Test Plan\n*   Step 1",
          logType: "PLAN",
        },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.data.filePath).toContain("1_IMPLEMENT_PLAN.md");
  });

  // --- Hardening: 5/1 — Finished effort only ---
  it("should return NO_ACTIVE_EFFORT when only finished efforts exist", async () => {
    const { taskDir, effort } = await setupEffortInTmp("LOG_FINISHED");
    const effortId = (effort as Record<string, unknown>).id as number;
    await dispatch({ cmd: "db.effort.finish", args: { effortId } }, ctx);

    const result = await dispatch(
      {
        cmd: "commands.log.append",
        args: { dirPath: taskDir, content: "## Test\n*   data" },
      },
      ctx
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toBe("NO_ACTIVE_EFFORT");
  });

  // --- Hardening: 5/2 — Content without ## heading ---
  it("should append content without heading (no timestamp injection)", async () => {
    const { taskDir } = await setupEffortInTmp("LOG_NO_HEADING");

    const result = await dispatch(
      {
        cmd: "commands.log.append",
        args: { dirPath: taskDir, content: "Plain text without heading" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const filePath = result.data.filePath as string;
    const content = fs.readFileSync(filePath, "utf-8");
    expect(content).toContain("Plain text without heading");
    // No timestamp injected (no ## heading)
    expect(content).not.toContain("[20");
  });

  // --- Hardening: 5/3 — Empty content string ---
  it("should handle empty content string without crash", async () => {
    const { taskDir } = await setupEffortInTmp("LOG_EMPTY");

    const result = await dispatch(
      {
        cmd: "commands.log.append",
        args: { dirPath: taskDir, content: "" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const filePath = result.data.filePath as string;
    // File exists (created by fs.files.append)
    expect(fs.existsSync(filePath)).toBe(true);
  });

  // --- Hardening: 5/4 — Heartbeat reset when session already ended ---
  it("should append log even when session already ended", async () => {
    const { taskDir, session } = await setupEffortInTmp("LOG_ENDED");
    const sessionId = (session as Record<string, unknown>).id as number;

    // End the session
    await dispatch({ cmd: "db.session.finish", args: { sessionId } }, ctx);

    // Append should still work (effort is active, session end is silent for heartbeat)
    const result = await dispatch(
      {
        cmd: "commands.log.append",
        args: { dirPath: taskDir, content: "## After End\n*   Still logging" },
      },
      ctx
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const filePath = result.data.filePath as string;
    const content = fs.readFileSync(filePath, "utf-8");
    expect(content).toContain("Still logging");
  });
});

describe("injectTimestamp", () => {
  it("should inject timestamp into first ## heading", () => {
    const input = "## My Heading\nContent here";
    const result = injectTimestamp(input, "2026-02-21 02:45:00");
    expect(result).toBe("## [2026-02-21 02:45:00] My Heading\nContent here");
  });

  it("should only inject into first heading", () => {
    const input = "## First\n## Second";
    const result = injectTimestamp(input, "2026-02-21 02:45:00");
    expect(result).toBe("## [2026-02-21 02:45:00] First\n## Second");
  });

  it("should handle content without heading", () => {
    const input = "No heading here";
    const result = injectTimestamp(input, "2026-02-21 02:45:00");
    expect(result).toBe("No heading here");
  });
});
