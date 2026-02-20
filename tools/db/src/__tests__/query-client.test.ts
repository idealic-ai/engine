import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { startDaemon, stopDaemon } from "../daemon.js";
import { sendQuery } from "../query-client.js";

const TEST_DIR = path.join(os.tmpdir(), `engine-query-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
const SOCKET_PATH = path.join(TEST_DIR, "test.sock");
const DB_PATH = path.join(TEST_DIR, "test.db");

beforeEach(async () => {
  fs.mkdirSync(TEST_DIR, { recursive: true });
  await startDaemon({ socketPath: SOCKET_PATH, dbPath: DB_PATH });
});

afterEach(async () => {
  await stopDaemon();
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
});

describe("sendQuery", () => {
  it("should connect to daemon and execute a query", async () => {
    const result = await sendQuery(SOCKET_PATH, {
      sql: "SELECT 1 AS value",
      params: [],
      format: "json",
      single: false,
    });

    expect(result.ok).toBe(true);
    expect(result.rows).toEqual([{ value: 1 }]);
  });

  it("should pass positional params correctly", async () => {
    await sendQuery(SOCKET_PATH, {
      sql: "INSERT INTO projects (path, name) VALUES (?, ?)",
      params: ["/proj", "test"],
      format: "json",
      single: false,
    });
    await sendQuery(SOCKET_PATH, {
      sql: "INSERT INTO tasks (dir_path, project_id, title) VALUES (?, ?, ?)",
      params: ["test_task", 1, "Test Task"],
      format: "json",
      single: false,
    });

    const result = await sendQuery(SOCKET_PATH, {
      sql: "SELECT title FROM tasks WHERE dir_path = ?",
      params: ["test_task"],
      format: "json",
      single: true,
    });

    expect(result.ok).toBe(true);
    expect(result.row).toMatchObject({ title: "Test Task" });
  });

  it("should throw when daemon is not running", async () => {
    await stopDaemon();

    await expect(
      sendQuery(SOCKET_PATH, {
        sql: "SELECT 1",
        params: [],
        format: "json",
        single: false,
      })
    ).rejects.toThrow();
  });

  it("should support --single flag", async () => {
    await sendQuery(SOCKET_PATH, {
      sql: "INSERT INTO projects (path, name) VALUES (?, ?)",
      params: ["/proj", "test"],
      format: "json",
      single: false,
    });
    await sendQuery(SOCKET_PATH, {
      sql: "INSERT INTO tasks (dir_path, project_id) VALUES (?, ?)",
      params: ["t1", 1],
      format: "json",
      single: false,
    });

    const result = await sendQuery(SOCKET_PATH, {
      sql: "SELECT * FROM tasks WHERE dir_path = ?",
      params: ["t1"],
      format: "json",
      single: true,
    });

    expect(result.ok).toBe(true);
    expect(result.row).toBeDefined();
    expect((result.row as Record<string, unknown>).dir_path).toBe("t1");
    expect(result.rows).toBeUndefined();
  });

  it("should support --format=scalar", async () => {
    await sendQuery(SOCKET_PATH, {
      sql: "INSERT INTO projects (path, name) VALUES (?, ?)",
      params: ["/proj", "test"],
      format: "json",
      single: false,
    });
    await sendQuery(SOCKET_PATH, {
      sql: "INSERT INTO tasks (dir_path, project_id) VALUES (?, ?)",
      params: ["t1", 1],
      format: "json",
      single: false,
    });

    const result = await sendQuery(SOCKET_PATH, {
      sql: "SELECT COUNT(*) FROM tasks",
      params: [],
      format: "scalar",
      single: false,
    });

    expect(result.ok).toBe(true);
    expect(result.value).toBe(1);
  });

  it("should support --format=tsv", async () => {
    await sendQuery(SOCKET_PATH, {
      sql: "INSERT INTO projects (path, name) VALUES (?, ?)",
      params: ["/proj", "test"],
      format: "json",
      single: false,
    });
    await sendQuery(SOCKET_PATH, {
      sql: "INSERT INTO tasks (dir_path, project_id, title) VALUES (?, ?, ?)",
      params: ["t1", 1, "implement"],
      format: "json",
      single: false,
    });

    const result = await sendQuery(SOCKET_PATH, {
      sql: "SELECT dir_path, title FROM tasks",
      params: [],
      format: "tsv",
      single: false,
    });

    expect(result.ok).toBe(true);
    expect(result.tsv).toContain("dir_path\ttitle");
    expect(result.tsv).toContain("t1\timplement");
  });
});
