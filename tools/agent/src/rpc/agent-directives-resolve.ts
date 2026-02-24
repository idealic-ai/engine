/**
 * agent.directives.resolve — Resolve reference names to file paths via walk-up + engine fallback.
 *
 * Ports the resolution step of resolve_refs() from lib.sh.
 * Given a list of refs (e.g., {prefix: "CMD", name: "CMD_DEHYDRATE"}),
 * walks up from startDir checking .directives/{folder}/ at each level,
 * then falls back to ~/.claude/engine/.directives/{folder}/.
 *
 * FS Migration: uses ctx.fs.files.stat and ctx.fs.paths.resolve instead of node:fs.
 */
import * as path from "node:path";
import * as os from "node:os";
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const PREFIX_TO_FOLDER: Record<string, string> = {
  CMD: "commands",
  FMT: "formats",
  INV: "invariants",
};

const schema = z.object({
  refs: z.array(z.object({
    prefix: z.string(),
    name: z.string(),
  })).min(1),
  startDir: z.string(),
  projectRoot: z.string().optional(),
});

type Args = z.infer<typeof schema>;

interface ResolvedRef {
  ref: string;
  path: string | null;
  searchedDirs: string[];
}

async function resolveReal(p: string, ctx: RpcContext): Promise<string> {
  try {
    const { resolved } = await ctx.fs.paths.resolve({ paths: [p] });
    const entries = resolved as Array<{ resolved: string }>;
    return entries[0].resolved;
  } catch {
    return path.resolve(p);
  }
}

async function fileExists(p: string, ctx: RpcContext): Promise<boolean> {
  try {
    const { exists } = await ctx.fs.files.stat({ path: p });
    return exists as boolean;
  } catch {
    return false;
  }
}

export async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ resolved: ResolvedRef[] }>> {
  const startDir = await resolveReal(args.startDir, ctx);
  const projectRoot = args.projectRoot ? await resolveReal(args.projectRoot, ctx) : await resolveReal(process.cwd(), ctx);
  const engineDir = path.join(os.homedir(), ".claude", "engine", ".directives");

  const resolved: ResolvedRef[] = [];

  for (const ref of args.refs) {
    const folder = PREFIX_TO_FOLDER[ref.prefix];
    if (!folder) {
      resolved.push({ ref: `§${ref.name}`, path: null, searchedDirs: [] });
      continue;
    }

    const filename = `${ref.name}.md`;
    const searchedDirs: string[] = [];
    let found: ResolvedRef | null = null;

    // Walk-up from startDir to projectRoot
    let current = startDir;
    while (true) {
      const candidate = path.join(current, ".directives", folder, filename);
      searchedDirs.push(current);

      if (await fileExists(candidate, ctx)) {
        found = { ref: `§${ref.name}`, path: await resolveReal(candidate, ctx), searchedDirs };
        break;
      }

      // Stop at project root or filesystem root
      if (current === projectRoot || current === "/" || current === path.dirname(current)) {
        break;
      }

      current = path.dirname(current);
    }

    if (found) {
      resolved.push(found);
      continue;
    }

    // Fallback to engine .directives/
    const engineCandidate = path.join(engineDir, folder, filename);
    searchedDirs.push(engineDir);
    if (await fileExists(engineCandidate, ctx)) {
      resolved.push({ ref: `§${ref.name}`, path: await resolveReal(engineCandidate, ctx), searchedDirs });
    } else {
      resolved.push({ ref: `§${ref.name}`, path: null, searchedDirs });
    }
  }

  return { ok: true, data: { resolved } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "agent.directives.resolve": typeof handler;
  }
}

registerCommand("agent.directives.resolve", { schema, handler });
