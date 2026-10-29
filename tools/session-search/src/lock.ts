/**
 * session-search's index lock: the shared advisory lock in
 * tools/shared/index-lock.ts, bound to `.session-search.lock` beside the DB.
 *
 * Its own file name, so session-search and doc-search never block each other
 * even when both DBs sit in one directory.
 */
import { createIndexLock } from "../../shared/index-lock.js";

export {
  readLock,
  isLockStale,
  isProcessAlive,
  LOCK_TIMEOUT_MS,
  LOCK_HEARTBEAT_MS,
  lockHeartbeatMsFromEnv,
  type LockInfo,
} from "../../shared/index-lock.js";

export const LOCK_FILENAME = ".session-search.lock";

export const { getLockPath, acquireLock, refreshLock, startLockHeartbeat, releaseLock } =
  createIndexLock(LOCK_FILENAME);
