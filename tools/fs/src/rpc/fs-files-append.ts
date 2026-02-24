/**
 * fs.files.append — Append content to a file with auto-mkdir.
 *
 * Creates parent directories if they don't exist.
 * Creates the file if it doesn't exist.
 * Appends with configurable separator (default: newline for existing files).
 *
 * Error taxonomy:
 *   FS_PERMISSION   — permission denied
 *   FS_IS_DIRECTORY — path is a directory, not a file
 */
import * as fs from "node:fs";
import * as path from "node:path";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  path: z.string(),
  content: z.string(),
  separator: z.string().optional(),
});

type Args = z.infer<typeof schema>;

export function handler(args: Args): TypedRpcResponse<{ path: string; size: number }> {
  const { path: filePath, content, separator } = args;

  // Ensure parent directory exists
  const dir = path.dirname(filePath);
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch (err: any) {
    if (err.code === "EACCES") {
      return { ok: false, error: "FS_PERMISSION", message: `Permission denied: ${dir}` };
    }
    throw err;
  }

  // Check if target is a directory
  try {
    const stat = fs.statSync(filePath);
    if (stat.isDirectory()) {
      return { ok: false, error: "FS_IS_DIRECTORY", message: `Path is a directory: ${filePath}` };
    }
  } catch {
    // File doesn't exist — that's fine, we'll create it
  }

  // Determine separator
  const fileExists = fs.existsSync(filePath);
  const sep = separator ?? (fileExists ? "\n" : "");

  // Append
  try {
    fs.appendFileSync(filePath, sep + content + "\n");
  } catch (err: any) {
    if (err.code === "EACCES") {
      return { ok: false, error: "FS_PERMISSION", message: `Permission denied: ${filePath}` };
    }
    throw err;
  }

  const stat = fs.statSync(filePath);

  return {
    ok: true,
    data: {
      path: filePath,
      size: stat.size,
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "fs.files.append": typeof handler;
  }
}

registerCommand("fs.files.append", { schema, handler });
