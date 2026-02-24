/**
 * fs.dirs.list — List directory entries with optional type filtering.
 *
 * Returns entries with name and type (file/directory/symlink).
 * Used by agent.* handlers to replace direct fs.readdirSync calls.
 */
import * as fs from "node:fs";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  path: z.string(),
  /** Filter to only return entries of this type */
  type: z.enum(["file", "directory", "all"]).optional().default("all"),
});

type Args = z.infer<typeof schema>;

interface DirEntry {
  name: string;
  type: "file" | "directory" | "symlink" | "other";
}

export function handler(args: Args): TypedRpcResponse<{ entries: DirEntry[] }> {
  const { path: dirPath, type: filterType } = args;

  // Check existence
  let stat: fs.Stats;
  try {
    stat = fs.statSync(dirPath);
  } catch (err: any) {
    if (err.code === "ENOENT") {
      return { ok: false, error: "FS_NOT_FOUND", message: `Directory not found: ${dirPath}` };
    }
    if (err.code === "EACCES") {
      return { ok: false, error: "FS_PERMISSION", message: `Permission denied: ${dirPath}` };
    }
    throw err;
  }

  if (!stat.isDirectory()) {
    return { ok: false, error: "FS_NOT_DIRECTORY", message: `Path is not a directory: ${dirPath}` };
  }

  let rawEntries: fs.Dirent[];
  try {
    rawEntries = fs.readdirSync(dirPath, { withFileTypes: true });
  } catch (err: any) {
    if (err.code === "EACCES") {
      return { ok: false, error: "FS_PERMISSION", message: `Permission denied reading: ${dirPath}` };
    }
    throw err;
  }

  const entries: DirEntry[] = [];
  for (const entry of rawEntries) {
    const entryType: DirEntry["type"] = entry.isDirectory()
      ? "directory"
      : entry.isSymbolicLink()
        ? "symlink"
        : entry.isFile()
          ? "file"
          : "other";

    if (filterType === "all" || filterType === entryType) {
      entries.push({ name: entry.name, type: entryType });
    }
  }

  return { ok: true, data: { entries } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "fs.dirs.list": typeof handler;
  }
}

registerCommand("fs.dirs.list", { schema, handler });
