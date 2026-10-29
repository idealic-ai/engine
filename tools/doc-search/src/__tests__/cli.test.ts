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
function run(
  args: readonly string[],
  dbPath: string,
  extraEnv: NodeJS.ProcessEnv = {}
): Promise<{ status: number | null; out: string; err: string }> {
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
    let err = "";
    child.stdout.on("data", (d: Buffer) => { out += d.toString(); });
    child.stderr.on("data", (d: Buffer) => { out += d.toString(); err += d.toString(); });
    child.on("close", (status) => resolve({ status, out, err }));
  });
}

function writeConfig(cfg: unknown): void {
  fs.mkdirSync(path.join(dir, ".claude"), { recursive: true });
  fs.writeFileSync(path.join(dir, ".claude", "doc-search.json"), JSON.stringify(cfg));
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

describe("cli index reads the configured roots (IDE-333)", () => {
  it("finds the files the project's config names, not the default globs", async () => {
    // docs/A.md is there from beforeEach; the config adds handbook/ and a
    // package README, which the default globs would never reach.
    fs.mkdirSync(path.join(dir, ".claude"), { recursive: true });
    fs.mkdirSync(path.join(dir, "handbook"), { recursive: true });
    fs.writeFileSync(path.join(dir, "handbook", "H.md"), "# H\n\n## S\nHandbook.\n");
    fs.mkdirSync(path.join(dir, "pkg"), { recursive: true });
    fs.writeFileSync(path.join(dir, "pkg", "README.md"), "# P\n\n## S\nPackage.\n");
    fs.writeFileSync(
      path.join(dir, ".claude", "doc-search.json"),
      JSON.stringify({ roots: [{ name: "proj", path: ".", globs: ["docs/**/*.md", "handbook/**/*.md", "*/README.md"] }] })
    );
    const dbPath = path.join(dir, "cache", ".doc-search.local.db");
    // The embed endpoint is closed, so the run fails after scanning; the scan is what is checked.
    const r = await run(["index"], dbPath);
    expect(r.out).toMatch(/Roots from: .*\.claude\/doc-search\.json/);
    expect(r.out).toMatch(/\[proj\] .*  3 files/);
    expect(r.out).toMatch(/Found 3 markdown files/);
  }, 130_000);
});

describe("cli roots wiring (IDE-333 round 3)", () => {
  it("index --path reads that one glob, not the roots the project's config names", async () => {
    fs.mkdirSync(path.join(dir, "handbook"), { recursive: true });
    fs.writeFileSync(path.join(dir, "handbook", "H.md"), "# H\n\n## S\nHandbook.\n");
    fs.writeFileSync(path.join(dir, "handbook", "I.md"), "# I\n\n## S\nHandbook.\n");
    writeConfig({ roots: [{ name: "proj", path: ".", globs: ["handbook/**/*.md"] }] });
    const r = await run(["index", "--path", "docs/**/*.md"], path.join(dir, "cache", ".doc-search.local.db"));
    expect(r.out).toMatch(/Roots from: --path/);
    expect(r.out).not.toMatch(/\[proj\]/);
    expect(r.out).toMatch(/Found 1 markdown files/);
  }, 130_000);

  it("roots prints NOT IN GIT, and index warns on stderr, with git's reason, for a tracked root outside git", async () => {
    writeConfig({ roots: [{ name: "proj", path: ".", globs: ["docs/**/*.md"], tracked: true }] });
    const r = await run(["roots"], path.join(dir, "cache", ".doc-search.local.db"));
    expect(r.status).toBe(0);
    expect(r.out).toMatch(/NOT IN GIT: .*not a git repository/i);
    // index says the same on stderr, where a background run's log would show it.
    const i = await run(["index"], path.join(dir, "cache", ".doc-search.local.db"));
    expect(i.err).toMatch(/is marked "tracked" but git could not list it \(.*not a git repository/i);
  }, 130_000);

  it("a tracked root whose git cannot run says why, not 'not a git work tree'", async () => {
    // PATH holds node and nothing else, so `git` cannot be spawned.
    const bin = path.join(dir, "bin");
    fs.mkdirSync(bin);
    fs.symlinkSync(process.execPath, path.join(bin, "node"));
    writeConfig({ roots: [{ name: "proj", path: ".", globs: ["docs/**/*.md"], tracked: true }] });
    const r = await run(["roots"], path.join(dir, "cache", ".doc-search.local.db"), { PATH: bin });
    expect(r.out).toMatch(/NOT IN GIT: .*ENOENT/);
  }, 130_000);

  it("index warns on stderr, naming the root, when a root's folder exists but its globs match nothing", async () => {
    writeConfig({
      roots: [
        { name: "typo", path: ".", globs: ["handbok/**/*.md"] },
        { name: "docs", path: ".", globs: ["docs/**/*.md"] },
      ],
    });
    const r = await run(["index"], path.join(dir, "cache", ".doc-search.local.db"));
    expect(r.err).toMatch(/root "typo" .*matched no files/);
    expect(r.err).not.toMatch(/root "docs" .*matched no files/);
    expect(r.out).toMatch(/Found 1 markdown files/);
  }, 130_000);
});
