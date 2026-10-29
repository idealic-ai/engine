/**
 * doc-search's index lock: the shared advisory lock in
 * tools/shared/index-lock.ts, bound to `.doc-search.lock` beside the DB.
 *
 * This replaced doc-search's own read-then-write lock, which let indexers
 * launched in the same burst all read "no lock" and all proceed, and which
 * judged a live holder stale after five minutes of a long rebuild.
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

export const LOCK_FILENAME = ".doc-search.lock";

export const { getLockPath, acquireLock, refreshLock, startLockHeartbeat, releaseLock } =
  createIndexLock(LOCK_FILENAME);
