import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";
import { dbPathFromEnv } from "../../shared/db-path.js";

const TOOL_DIR = path.dirname(fileURLToPath(import.meta.url));

export const DB_FILENAME = ".doc-search.db";

/**
 * Find the project root by looking for .claude directory.
 * Falls back to git root, then cwd.
 *
 * Priority:
 * 1. Directory containing .claude/ (Claude Code project marker)
 * 2. Git repository root
 * 3. Current working directory
 */
export function getProjectRoot(): string {
  // 1. Walk up looking for .claude directory
  let dir = process.cwd();
  const root = path.parse(dir).root;
  while (dir !== root) {
    if (fs.existsSync(path.join(dir, ".claude"))) {
      return dir;
    }
    dir = path.dirname(dir);
  }

  // 2. Fall back to git root
  try {
    const gitRoot = execSync("git rev-parse --show-toplevel", {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    if (gitRoot) return gitRoot;
  } catch {
    // Not a git repo
  }

  // 3. Fall back to cwd
  return process.cwd();
}

/**
 * Where this run should read and write the DB.
 *
 * Lives in its own module (rather than cli.ts) because cli.ts calls main() at
 * import time — importing it from a test would execute the CLI.
 */
export function getDbPath(): string {
  const fromWrapper = dbPathFromEnv();
  if (fromWrapper) return fromWrapper;

  const sessionsDir = path.join(getProjectRoot(), "sessions");
  if (fs.existsSync(sessionsDir)) {
    return path.join(sessionsDir, DB_FILENAME);
  }
  // Fallback to tool dir if sessions/ doesn't exist
  return path.join(TOOL_DIR, "..", DB_FILENAME);
}
