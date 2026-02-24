/**
 * fs.files.stat — Check file/directory existence and type.
 *
 * Returns exists, type, size, mtime. Lightweight alternative to fs.files.read
 * when you only need metadata.
 */
import * as fs from "node:fs";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  path: z.string(),
});

type Args = z.infer<typeof schema>;

export function handler(args: Args): TypedRpcResponse<{ exists: boolean; type?: string; size?: number; mtime?: string }> {
  const { path: filePath } = args;

  let stat: fs.Stats;
  try {
    stat = fs.statSync(filePath);
  } catch (err: any) {
    if (err.code === "ENOENT") {
      return { ok: true, data: { exists: false } };
    }
    if (err.code === "EACCES") {
      return { ok: false, error: "FS_PERMISSION", message: `Permission denied: ${filePath}` };
    }
    throw err;
  }

  const type = stat.isDirectory() ? "directory" : stat.isFile() ? "file" : stat.isSymbolicLink() ? "symlink" : "other";

  return {
    ok: true,
    data: {
      exists: true,
      type,
      size: stat.size,
      mtime: stat.mtime.toISOString(),
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "fs.files.stat": typeof handler;
  }
}

registerCommand("fs.files.stat", { schema, handler });
