import { describe, it, expect, beforeEach, afterEach } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  acquireLock,
  releaseLock,
  readLock,
  refreshLock,
  startLockHeartbeat,
  getLockPath,
  isLockStale,
  isProcessAlive,
  LOCK_HEARTBEAT_MS,
  LOCK_TIMEOUT_MS,
} from "../lock.js";
import { getLockPath as docLockPath } from "../../../doc-search/src/lock.js";

let dir: string;
let dbPath: string;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "session-search-lock-"));
  dbPath = path.join(dir, ".session-search.db");
});

afterEach(() => {
  fs.rmSync(dir, { recursive: true, force: true });
});

/** A lock file as some other process would have left it. */
function writeForeignLock(overrides: Partial<{ pid: number; hostname: string; timestamp: string }> = {}) {
  const info = {
    pid: 999999, // never live
    hostname: os.hostname(),
    timestamp: new Date().toISOString(),
    ...overrides,
  };
  fs.writeFileSync(getLockPath(dbPath), JSON.stringify(info), "utf-8");
  return info;
}

describe("index lock", () => {
  it("does not use doc-search's lock file", () => {
    expect(path.basename(getLockPath(dbPath))).toBe(".session-search.lock");
  });

  it("keeps the lock beside the database so it moves with it", () => {
    expect(path.dirname(getLockPath(dbPath))).toBe(path.dirname(dbPath));
  });

  it("grants the lock when none is held", () => {
    expect(acquireLock(dbPath)).toBe(true);
    expect(readLock(getLockPath(dbPath))?.pid).toBe(process.pid);
  });

  // The leak: many detached indexers launch at once, all reach the DB, and
  // without this every loser stays resident instead of exiting.
  it("refuses a second holder while a live process indexes", () => {
    writeForeignLock({ pid: process.pid });
    expect(acquireLock(dbPath)).toBe(false);
  });

  it("breaks a lock whose holder has exited", () => {
    writeForeignLock();
    expect(acquireLock(dbPath)).toBe(true);
    expect(readLock(getLockPath(dbPath))?.pid).toBe(process.pid);
  });

  it("breaks a lock older than the timeout even if the pid is reused", () => {
    const old = new Date(Date.now() - 6 * 60 * 1000).toISOString();
    writeForeignLock({ pid: process.pid, timestamp: old });
    expect(acquireLock(dbPath)).toBe(true);
  });

  it("treats a lock from another machine as held", () => {
    const info = { pid: process.pid, hostname: "some-other-host", timestamp: new Date().toISOString() };
    expect(isProcessAlive(info)).toBe(true);
    expect(isLockStale(info)).toBe(false);
  });

  it("releases its own lock", () => {
    acquireLock(dbPath);
    releaseLock(dbPath);
    expect(fs.existsSync(getLockPath(dbPath))).toBe(false);
  });

  // A process that lost its lock to a stale-break must not delete the winner's.
  it("does not release a lock owned by another process", () => {
    writeForeignLock({ pid: 12345 });
    releaseLock(dbPath);
    expect(readLock(getLockPath(dbPath))?.pid).toBe(12345);
  });

  it("survives a corrupt lock file rather than throwing", () => {
    fs.writeFileSync(getLockPath(dbPath), "not json", "utf-8");
    expect(readLock(getLockPath(dbPath))).toBeNull();
    expect(acquireLock(dbPath)).toBe(true);
  });

  it("creates the lock directory when the db path does not exist yet", () => {
    const nested = path.join(dir, "deep", "nested", ".session-search.db");
    expect(acquireLock(nested)).toBe(true);
    expect(fs.existsSync(getLockPath(nested))).toBe(true);
  });

  // The rebuild case: a live holder outlasting LOCK_TIMEOUT_MS must not look stale.
  it("refreshLock renews a lock this process owns", () => {
    acquireLock(dbPath);
    const old = new Date(Date.now() - 6 * 60 * 1000).toISOString();
    fs.writeFileSync(getLockPath(dbPath), JSON.stringify({ pid: process.pid, hostname: os.hostname(), timestamp: old }));
    expect(isLockStale(readLock(getLockPath(dbPath))!)).toBe(true);
    expect(refreshLock(dbPath)).toBe(true);
    expect(isLockStale(readLock(getLockPath(dbPath))!)).toBe(false);
  });

  it("refreshLock never touches another process's lock", () => {
    const info = writeForeignLock({ pid: 12345, timestamp: new Date(0).toISOString() });
    expect(refreshLock(dbPath)).toBe(false);
    expect(readLock(getLockPath(dbPath))).toEqual(info);
  });

  it("the heartbeat keeps a long holder's lock fresh, so a later run cannot break it", async () => {
    acquireLock(dbPath);
    const stop = startLockHeartbeat(dbPath, 20);
    try {
      const old = new Date(Date.now() - 6 * 60 * 1000).toISOString();
      fs.writeFileSync(getLockPath(dbPath), JSON.stringify({ pid: process.pid, hostname: os.hostname(), timestamp: old }));
      await new Promise((r) => setTimeout(r, 120));
      expect(isLockStale(readLock(getLockPath(dbPath))!)).toBe(false);
    } finally {
      stop();
    }
  });

  it("the heartbeat interval is well inside the stale timeout", () => {
    expect(LOCK_HEARTBEAT_MS * 4).toBeLessThanOrEqual(LOCK_TIMEOUT_MS);
  });

  it("doc-search binds the same lock to its own file, so the two tools never block each other", () => {
    expect(path.basename(docLockPath(dbPath))).toBe(".doc-search.lock");
    expect(path.dirname(docLockPath(dbPath))).toBe(path.dirname(dbPath));
  });

  // The burst: session.sh backgrounds an index on every close, so contenders
  // arrive in the same instant. Exactly one may win.
  for (const [label, modulePath] of [
    ["session-search", "../lock.ts"],
    ["doc-search", "../../../doc-search/src/lock.ts"],
  ] as const) {
    it(`${label}: of 6 contenders released in the same instant, exactly one takes the lock`, async () => {
      const here = path.dirname(fileURLToPath(import.meta.url));
      const tsx = path.resolve(here, "../../node_modules/.bin/tsx");
      const contender = path.join(here, "fixtures", "lock-contender.ts");
      const lockModule = path.resolve(here, modulePath);
      const goFile = path.join(dir, "go");

      const children = Array.from({ length: 6 }, () => {
        const child = spawn(tsx, [contender, lockModule, dbPath, goFile], { stdio: ["ignore", "pipe", "inherit"] });
        let out = "";
        child.stdout.on("data", (d: Buffer) => { out += d.toString(); });
        const ready = new Promise<void>((resolve) => {
          const check = () => (out.includes("ready") ? resolve() : setTimeout(check, 5));
          check();
        });
        const done = new Promise<string>((resolve) => child.on("close", () => resolve(out)));
        return { ready, done };
      });

      await Promise.all(children.map((c) => c.ready));
      fs.writeFileSync(goFile, "");
      const outs = await Promise.all(children.map((c) => c.done));
      expect(outs.filter((o) => o.includes("won"))).toHaveLength(1);
      expect(outs.filter((o) => o.includes("lost"))).toHaveLength(5);
    }, 180_000);
  }
});
