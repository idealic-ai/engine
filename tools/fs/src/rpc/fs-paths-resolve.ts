/**
 * fs.paths.resolve — Path normalization: tilde expansion, symlink resolution, existence check.
 *
 * Ports the path normalization logic from lib.sh's normalize_preload_path().
 * Handles: ~ expansion, symlink resolution (macOS /var → /private/var),
 * relative-to-absolute conversion, and existence checking.
 *
 * Callers: bash layer, other RPC handlers that need normalized paths.
 */
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  paths: z.array(z.string()).min(1),
  cwd: z.string().optional(),
});

type Args = z.infer<typeof schema>;

export function handler(args: Args): TypedRpcResponse<{ resolved: Array<{ original: string; resolved: string; exists: boolean }> }> {
  const cwd = args.cwd ?? process.cwd();
  const homeDir = os.homedir();

  const resolved = args.paths.map((inputPath) => {
    let p = inputPath;

    // Tilde expansion
    if (p.startsWith("~/") || p === "~") {
      p = path.join(homeDir, p.slice(1));
    }

    // Relative to absolute
    if (!path.isAbsolute(p)) {
      p = path.resolve(cwd, p);
    }

    // Normalize (remove . and ..)
    p = path.normalize(p);

    // Symlink resolution (handles macOS /var → /private/var, /tmp → /private/tmp)
    let realPath = p;
    try {
      realPath = fs.realpathSync(p);
    } catch {
      // Path doesn't exist — use the normalized path
      realPath = p;
    }

    const exists = fs.existsSync(realPath);

    return {
      original: inputPath,
      resolved: realPath,
      exists,
    };
  });

  return { ok: true, data: { resolved } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "fs.paths.resolve": typeof handler;
  }
}

registerCommand("fs.paths.resolve", { schema, handler });
