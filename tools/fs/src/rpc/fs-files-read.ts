/**
 * fs.files.read — Generic file read with encoding support.
 *
 * Reads a file from the filesystem with clean error taxonomy:
 *   FS_NOT_FOUND    — file does not exist
 *   FS_PERMISSION   — permission denied
 *   FS_IS_DIRECTORY — path is a directory, not a file
 *   FS_TOO_LARGE    — file exceeds size limit (default 10MB)
 *
 * Callers: bash layer, agent.* handlers that need file content.
 */
import * as fs from "node:fs";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB

const schema = z.object({
  path: z.string(),
  encoding: z.enum(["utf-8", "base64"]).optional().default("utf-8"),
  maxSize: z.number().optional(),
});

type Args = z.infer<typeof schema>;

export function handler(args: Args): TypedRpcResponse<{ content: string; size: number; mtime: string }> {
  const { path: filePath, encoding, maxSize } = args;
  const limit = maxSize ?? MAX_FILE_SIZE;

  // Check existence
  let stat: fs.Stats;
  try {
    stat = fs.statSync(filePath);
  } catch (err: any) {
    if (err.code === "ENOENT") {
      return {
        ok: false,
        error: "FS_NOT_FOUND",
        message: `File not found: ${filePath}`,
      };
    }
    if (err.code === "EACCES") {
      return {
        ok: false,
        error: "FS_PERMISSION",
        message: `Permission denied: ${filePath}`,
      };
    }
    throw err;
  }

  // Check it's a file
  if (stat.isDirectory()) {
    return {
      ok: false,
      error: "FS_IS_DIRECTORY",
      message: `Path is a directory: ${filePath}`,
    };
  }

  // Check size
  if (stat.size > limit) {
    return {
      ok: false,
      error: "FS_TOO_LARGE",
      message: `File too large: ${stat.size} bytes (limit: ${limit})`,
      details: { size: stat.size, limit },
    };
  }

  // Read
  const bufferEncoding = encoding === "base64" ? "base64" : "utf-8";
  const content = fs.readFileSync(filePath, { encoding: bufferEncoding });

  return {
    ok: true,
    data: {
      content,
      size: stat.size,
      mtime: stat.mtime.toISOString(),
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "fs.files.read": typeof handler;
  }
}

registerCommand("fs.files.read", { schema, handler });
