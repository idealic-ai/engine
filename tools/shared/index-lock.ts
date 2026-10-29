/**
 * The advisory lock both search indexers take around `index`.
 *
 * Every `engine session idle` and `deactivate` backgrounds `session-search
 * index` and `doc-search index` (scripts/session.sh), so a fleet closing
 * sessions launches many indexers at once against one SQLite image. Each is a
 * local Ollama embedding job. The lock makes them coalesce: one run per DB file
 * does the work and the rest exit at once.
 *
 * The lock lives next to the DB file, so it moves with the DB, and each tool
 * names its own lock file so the two tools never block each other.
 *
 * Liveness: a holder refreshes the lock's timestamp every LOCK_HEARTBEAT_MS
 * while it runs (`startLockHeartbeat`). A lock is broken only when its holder
 * is gone (same host, pid not alive) or its timestamp is older than
 * LOCK_TIMEOUT_MS. Without the heartbeat a full rebuild, which takes tens of
 * minutes, would look stale after five and the next session close would start a
 * duplicate run beside it.
 */
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

/** A lock whose timestamp is older than this is abandoned, whatever its pid. */
export const LOCK_TIMEOUT_MS = 5 * 60 * 1000;
/** How often a live holder rewrites its timestamp. Well under LOCK_TIMEOUT_MS. */
export const LOCK_HEARTBEAT_MS = 30 * 1000;

/**
 * The heartbeat interval a CLI uses: ENGINE_SEARCH_LOCK_HEARTBEAT_MS when it is
 * a positive whole number below LOCK_TIMEOUT_MS, else LOCK_HEARTBEAT_MS. The
 * override exists so a test can watch a heartbeat land in well under 30 s.
 */
export function lockHeartbeatMsFromEnv(env: NodeJS.ProcessEnv = process.env): number {
  const raw = Number(env.ENGINE_SEARCH_LOCK_HEARTBEAT_MS);
  return Number.isInteger(raw) && raw > 0 && raw < LOCK_TIMEOUT_MS ? raw : LOCK_HEARTBEAT_MS;
}

export interface LockInfo {
  pid: number;
  hostname: string;
  timestamp: string;
}

export function readLock(lockPath: string): LockInfo | null {
  try {
    return JSON.parse(fs.readFileSync(lockPath, "utf-8")) as LockInfo;
  } catch {
    return null;
  }
}

export function isLockStale(lockInfo: LockInfo, now: number = Date.now()): boolean {
  const at = new Date(lockInfo.timestamp).getTime();
  // An unparseable timestamp cannot prove the holder is fresh.
  if (Number.isNaN(at)) return true;
  return now - at > LOCK_TIMEOUT_MS;
}

export function isProcessAlive(lockInfo: LockInfo): boolean {
  // A lock written on another machine can't be probed — assume the holder lives.
  if (lockInfo.hostname !== os.hostname()) {
    return true;
  }

  try {
    process.kill(lockInfo.pid, 0);
    return true;
  } catch {
    return false;
  }
}

function ownLockInfo(): LockInfo {
  return { pid: process.pid, hostname: os.hostname(), timestamp: new Date().toISOString() };
}

function ownsLock(existing: LockInfo | null): boolean {
  return existing !== null && existing.pid === process.pid && existing.hostname === os.hostname();
}

/**
 * Create the lock file, failing if it already exists.
 *
 * The `wx` flag makes create-if-absent one syscall. A read-then-write pair
 * cannot do this: indexers launched in the same millisecond all read "no lock"
 * and all write, which is precisely the burst this lock exists to stop.
 */
function writeLockExclusive(lockPath: string): boolean {
  const lockDir = path.dirname(lockPath);
  if (!fs.existsSync(lockDir)) {
    fs.mkdirSync(lockDir, { recursive: true });
  }

  try {
    fs.writeFileSync(lockPath, JSON.stringify(ownLockInfo(), null, 2), {
      encoding: "utf-8",
      flag: "wx",
    });
    return true;
  } catch {
    return false;
  }
}

export interface IndexLock {
  getLockPath(dbPath: string): string;
  /**
   * Take the lock, breaking one whose holder is gone or timed out.
   * Returns false when another live process is mid-index.
   */
  acquireLock(dbPath: string): boolean;
  /** Rewrite the timestamp of a lock this process owns. False when it does not own it. */
  refreshLock(dbPath: string): boolean;
  /**
   * Refresh the lock every `intervalMs` until the returned stop function is
   * called. The timer is unref'd, so it never keeps the process alive.
   */
  startLockHeartbeat(dbPath: string, intervalMs?: number): () => void;
  /** Release only a lock this process owns. */
  releaseLock(dbPath: string): void;
}

/** Bind the lock operations to one tool's lock file name, e.g. ".session-search.lock". */
export function createIndexLock(lockFileName: string): IndexLock {
  function getLockPath(dbPath: string): string {
    return path.join(path.dirname(dbPath), lockFileName);
  }

  function acquireLock(dbPath: string): boolean {
    const lockPath = getLockPath(dbPath);

    if (writeLockExclusive(lockPath)) {
      return true;
    }

    const existing = readLock(lockPath);
    if (existing && !isLockStale(existing) && isProcessAlive(existing)) {
      return false;
    }

    if (existing) {
      console.log(
        `Breaking stale lock (PID: ${existing.pid}, host: ${existing.hostname}, time: ${existing.timestamp})`
      );
    }

    // Unreadable or abandoned. Removing before the retry keeps the exclusive
    // create as the thing that decides the winner in the common case. One
    // window remains: two processes that both judged the SAME stale lock can
    // interleave unlink and create so both hold it. The cost is one duplicated
    // run (each save is an atomic rename, so the image is never corrupt).
    try {
      fs.unlinkSync(lockPath);
    } catch {
      // Another process broke it first; the retry below settles who wins.
    }

    return writeLockExclusive(lockPath);
  }

  function refreshLock(dbPath: string): boolean {
    const lockPath = getLockPath(dbPath);
    if (!ownsLock(readLock(lockPath))) return false;
    // Write-then-rename, so a reader never sees a half-written lock and breaks it.
    const tmpPath = `${lockPath}.${process.pid}.tmp`;
    try {
      fs.writeFileSync(tmpPath, JSON.stringify(ownLockInfo(), null, 2), "utf-8");
      fs.renameSync(tmpPath, lockPath);
      return true;
    } catch {
      try { fs.unlinkSync(tmpPath); } catch { /* nothing to clean up */ }
      return false;
    }
  }

  function startLockHeartbeat(dbPath: string, intervalMs: number = LOCK_HEARTBEAT_MS): () => void {
    const timer = setInterval(() => {
      refreshLock(dbPath);
    }, intervalMs);
    timer.unref();
    return () => clearInterval(timer);
  }

  function releaseLock(dbPath: string): void {
    const lockPath = getLockPath(dbPath);
    if (!ownsLock(readLock(lockPath))) return;
    try {
      fs.unlinkSync(lockPath);
    } catch {
      // Already gone.
    }
  }

  return { getLockPath, acquireLock, refreshLock, startLockHeartbeat, releaseLock };
}
