/**
 * The CLI end to end, as session.sh runs it: a child process with
 * ENGINE_SEARCH_DB_PATH set and the embed endpoint on a closed port.
 */
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { getLockPath, readLock } from "../lock.js";

const TOOL_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const TSX = path.join(TOOL_DIR, "node_modules", ".bin", "tsx");
const CLI = path.join(TOOL_DIR, "src", "cli.ts");

let dir: string;
beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "doc-search-cli-"));
  fs.mkdirSync(path.join(dir, "docs"), { recursive: true });
  fs.writeFileSync(path.join(dir, "docs", "A.md"), "# A\n\n## Section\nSome text.\n");
});
afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

/** Async, not spawnSync: a blocked worker misses vitest's RPC deadline under load. */
function run(args: readonly string[], dbPath: string): Promise<{ status: number | null; out: string }> {
  return new Promise((resolve) => {
    const child = spawn(TSX, [CLI, ...args], {
      cwd: dir,
      env: {
        ...process.env,
        ENGINE_SEARCH_DB_PATH: dbPath,
        ENGINE_EMBED_ENDPOINT: "http://127.0.0.1:1",
        ENGINE_EMBED_TIMEOUT_MS: "2000",
      },
    });
    let out = "";
    child.stdout.on("data", (d: Buffer) => { out += d.toString(); });
    child.stderr.on("data", (d: Buffer) => { out += d.toString(); });
    child.on("close", (status) => resolve({ status, out }));
  });
}

describe("cli refuses Gemini-era file names (M1)", () => {
  for (const args of [["index"], ["query", "anything"], ["status"]] as const) {
    it(`${args[0]}: exits 1 with the refusal, no stack, and creates nothing`, async () => {
      const dbPath = path.join(dir, "cache", ".doc-search.db");
      const r = await run(args, dbPath);
      expect(r.status).toBe(1);
      expect(r.out).toMatch(/\[doc-search\] Refusing .*\.doc-search\.db is a Gemini-era file name/);
      expect(r.out).not.toMatch(/Fatal error|at .*\.ts:\d+/);
      expect(fs.existsSync(dbPath)).toBe(false);
      expect(fs.existsSync(getLockPath(dbPath))).toBe(false);
    }, 130_000);
  }
});

describe("cli index lock (M2)", () => {
  it("a second index stops at once while a live process holds the lock, leaving its lock alone", async () => {
    const dbPath = path.join(dir, "cache", ".doc-search.local.db");
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    const held = { pid: process.pid, hostname: os.hostname(), timestamp: new Date().toISOString() };
    fs.writeFileSync(getLockPath(dbPath), JSON.stringify(held), "utf-8");

    const r = await run(["index"], dbPath);
    expect(r.out).toMatch(/Could not acquire lock\. Another process may be indexing\./);
    expect(r.out).not.toMatch(/Scanning:/);
    expect(readLock(getLockPath(dbPath))).toEqual(held);
    expect(fs.existsSync(dbPath)).toBe(false);
  }, 130_000);
});
