/**
 * The CLI end to end, as session.sh runs it: a child process with
 * ENGINE_SEARCH_DB_PATH set. The embed endpoint points at a closed port, so no
 * test here can reach a real runner.
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { spawn } from "node:child_process";
import http from "node:http";
import type { AddressInfo } from "node:net";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { getLockPath, readLock } from "../lock.js";

const TOOL_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const TSX = path.join(TOOL_DIR, "node_modules", ".bin", "tsx");
const CLI = path.join(TOOL_DIR, "src", "cli.ts");

let dir: string;
let sessionsDir: string;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "session-search-cli-"));
  sessionsDir = path.join(dir, "sessions");
  fs.mkdirSync(path.join(sessionsDir, "2026_10_29_X"), { recursive: true });
  fs.writeFileSync(path.join(sessionsDir, "2026_10_29_X", "LOG.md"), "# Log\n\n## Entry\nSomething happened.\n");
});

afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

/** Async, not spawnSync: a blocked worker misses vitest's RPC deadline under load. */
function run(
  args: readonly string[],
  dbPath: string,
  extraEnv: Record<string, string> = {},
  onOutput?: (out: string) => void
): Promise<{ status: number | null; out: string }> {
  return new Promise((resolve) => {
    const child = spawn(TSX, [CLI, ...args], {
      cwd: dir,
      env: {
        ...process.env,
        ENGINE_SEARCH_DB_PATH: dbPath,
        ENGINE_EMBED_ENDPOINT: "http://127.0.0.1:1",
        ENGINE_EMBED_TIMEOUT_MS: "2000",
        ...extraEnv,
      },
    });
    let out = "";
    const add = (d: Buffer) => { out += d.toString(); onOutput?.(out); };
    child.stdout.on("data", add);
    child.stderr.on("data", add);
    child.on("close", (status) => resolve({ status, out }));
  });
}

describe("cli refuses Gemini-era file names (M1)", () => {
  for (const [label, args] of [
    ["index", ["index", "SESSIONS"]],
    ["query", ["query", "anything"]],
  ] as const) {
    it(`${label}: exits 1 with the refusal, no stack, and creates nothing`, async () => {
      const dbPath = path.join(dir, "cache", ".session-search.db");
      const r = await run(args.map((a) => (a === "SESSIONS" ? sessionsDir : a)), dbPath);
      expect(r.status).toBe(1);
      expect(r.out).toMatch(/\[session-search\] Refusing .*\.session-search\.db is a Gemini-era file name/);
      expect(r.out).not.toMatch(/Fatal error|at .*\.ts:\d+/);
      expect(fs.existsSync(dbPath)).toBe(false);
      expect(fs.existsSync(getLockPath(dbPath))).toBe(false);
    }, 130_000);
  }
});

describe("cli index lock (M2)", () => {
  it("a second index exits 0 at once while a live process holds the lock, leaving its lock alone", async () => {
    const dbPath = path.join(dir, "cache", ".session-search.local.db");
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    // This test process is alive, so its pid makes a live foreign holder.
    const held = { pid: process.pid, hostname: os.hostname(), timestamp: new Date().toISOString() };
    fs.writeFileSync(getLockPath(dbPath), JSON.stringify(held), "utf-8");

    const r = await run(["index", sessionsDir], dbPath);
    expect(r.out).toMatch(/Another process is indexing — skipping this run\./);
    expect(r.status).toBe(0);
    expect(readLock(getLockPath(dbPath))).toEqual(held);
    expect(fs.existsSync(dbPath)).toBe(false);
  }, 130_000);

  it("a run that takes the lock releases it, even when embedding fails", async () => {
    const dbPath = path.join(dir, "cache", ".session-search.local.db");
    const r = await run(["index", sessionsDir], dbPath);
    expect(r.out).toMatch(/\[embed-local\] (RUNNER_ABSENT|PROVIDER_ERROR)/);
    expect(fs.existsSync(getLockPath(dbPath))).toBe(false);
  }, 130_000);

  // The live case of 2026-10-29 in kit: four close-triggered `index` runs in one
  // project, started 08:43, 09:16, 12:03 and 13:23, all ran at once. The lock
  // was written once and judged stale after 5 minutes although its holder was
  // alive, so each later run broke it. Here: run A holds the lock mid-embed, its
  // lock is aged past the timeout on disk (what 5 minutes without a refresh
  // leaves), A's heartbeat gets a chance to land, then run B starts in the same
  // project. Only A may run.
  it("two index runs in one project: the second skips even after the first has run past the stale timeout", async () => {
    const dbPath = path.join(dir, "cache", ".session-search.local.db");
    let embedRequests = 0;
    let releaseRunner: () => void = () => {};
    const runnerReleased = new Promise<void>((r) => { releaseRunner = r; });
    const server = http.createServer((req, res) => {
      let body = "";
      req.on("data", (d: Buffer) => { body += d.toString(); });
      req.on("end", () => {
        embedRequests++;
        const n = (JSON.parse(body) as { input: string[] }).input.length;
        void runnerReleased.then(() => {
          res.setHeader("content-type", "application/json");
          res.end(JSON.stringify({ embeddings: Array.from({ length: n }, () => Array(768).fill(0.01)) }));
        });
      });
    });
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
    const endpoint = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    const env = { ENGINE_EMBED_ENDPOINT: endpoint, ENGINE_EMBED_TIMEOUT_MS: "120000", ENGINE_SEARCH_LOCK_HEARTBEAT_MS: "200" };

    try {
      const a = run(["index", sessionsDir], dbPath, env);
      const deadline = Date.now() + 110_000;
      while (embedRequests === 0) {
        if (Date.now() > deadline) throw new Error("run A never reached the runner");
        await new Promise((r) => setTimeout(r, 50));
      }
      const holder = readLock(getLockPath(dbPath));
      expect(holder).not.toBeNull();
      const aged = new Date(Date.now() - 6 * 60 * 1000).toISOString();
      fs.writeFileSync(getLockPath(dbPath), JSON.stringify({ ...holder, timestamp: aged }), "utf-8");
      await new Promise((r) => setTimeout(r, 1500));

      // B either skips and exits, or breaks the lock and reaches the runner too.
      let bResult: { status: number | null; out: string } | null = null;
      const b = run(["index", sessionsDir], dbPath, env).then((r) => { bResult = r; return r; });
      const bDeadline = Date.now() + 110_000;
      while (bResult === null && embedRequests < 2 && Date.now() < bDeadline) {
        await new Promise((r) => setTimeout(r, 50));
      }
      expect(embedRequests).toBe(1);
      expect(bResult).not.toBeNull();
      expect(bResult!.out).toMatch(/Another process is indexing — skipping this run\./);
      expect(bResult!.status).toBe(0);

      releaseRunner();
      await b;
      const ra = await a;
      expect(ra.status).toBe(0);
      expect(ra.out).toMatch(/Inserted: 1/);
      expect(fs.existsSync(getLockPath(dbPath))).toBe(false);
    } finally {
      releaseRunner();
      server.close();
    }
  }, 300_000);
});
