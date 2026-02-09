import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const LOCK_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes

export interface LockInfo {
  pid: number;
  hostname: string;
  timestamp: string;
}

/**
 * Get the lock file path for the doc-search database.
 * Lock lives next to the database file.
 */
export function getLockPath(dbPath: string): string {
  const dir = path.dirname(dbPath);
  return path.join(dir, ".doc-search.lock");
}

/**
 * Read the current lock info from the lock file.
 * Returns null if lock doesn't exist or is unreadable.
 */
export function readLock(lockPath: string): LockInfo | null {
  try {
    const content = fs.readFileSync(lockPath, "utf-8");
    return JSON.parse(content) as LockInfo;
  } catch {
    return null;
  }
}

/**
 * Check if a lock is stale (older than LOCK_TIMEOUT_MS).
 */
export function isLockStale(lockInfo: LockInfo): boolean {
  const lockTime = new Date(lockInfo.timestamp).getTime();
  const now = Date.now();
  return now - lockTime > LOCK_TIMEOUT_MS;
}

/**
 * Check if the process that holds the lock is still alive.
 * Only works if the lock was acquired by a process on this machine.
 */
export function isProcessAlive(lockInfo: LockInfo): boolean {
  // If different hostname, assume alive (can't check)
  if (lockInfo.hostname !== os.hostname()) {
    return true;
  }

  try {
    // Signal 0 checks if process exists without actually sending a signal
    process.kill(lockInfo.pid, 0);
    return true;
  } catch {
    return false;
  }
}

/**
 * Acquire the advisory lock for indexing.
 *
 * Algorithm:
 * 1. Check if lock file exists
 * 2. If exists: check if stale (> 5 min) or process dead
 *    - If stale or dead: break lock
 *    - If fresh and alive: return false (can't acquire)
 * 3. Write new lock file with current PID, hostname, timestamp
 * 4. Return true (lock acquired)
 */
export function acquireLock(dbPath: string): boolean {
  const lockPath = getLockPath(dbPath);

  const existing = readLock(lockPath);
  if (existing) {
    const stale = isLockStale(existing);
    const alive = isProcessAlive(existing);

    if (!stale && alive) {
      // Lock is held by an active process
      return false;
    }

    // Lock is stale or process is dead — break it
    console.log(
      `Breaking stale lock (PID: ${existing.pid}, host: ${existing.hostname}, time: ${existing.timestamp})`
    );
  }

  // Ensure parent directory exists
  const lockDir = path.dirname(lockPath);
  if (!fs.existsSync(lockDir)) {
    fs.mkdirSync(lockDir, { recursive: true });
  }

  // Write new lock
  const lockInfo: LockInfo = {
    pid: process.pid,
    hostname: os.hostname(),
    timestamp: new Date().toISOString(),
  };

  fs.writeFileSync(lockPath, JSON.stringify(lockInfo, null, 2), "utf-8");
  return true;
}

/**
 * Release the advisory lock.
 * Only removes the lock if it's owned by this process.
 */
export function releaseLock(dbPath: string): void {
  const lockPath = getLockPath(dbPath);

  const existing = readLock(lockPath);
  if (!existing) {
    // No lock to release
    return;
  }

  // Only release if we own it
  if (existing.pid === process.pid && existing.hostname === os.hostname()) {
    try {
      fs.unlinkSync(lockPath);
    } catch {
      // Ignore errors (file might be already deleted)
    }
  }
}

/**
 * Wait for lock to become available, with timeout.
 * Polls every second until lock is acquired or timeout.
 */
export async function waitForLock(
  dbPath: string,
  timeoutMs: number = LOCK_TIMEOUT_MS
): Promise<boolean> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    if (acquireLock(dbPath)) {
      return true;
    }

    // Wait 1 second before retrying
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  return false;
}
