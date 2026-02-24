/**
 * agent.directives.discover — Walk-up .directives/ scanning with patterns filter.
 *
 * Ports discover-directives.sh logic. Scans target directories and ancestors
 * for directive files in .directives/ subfolders, respecting project root boundary.
 *
 * FS Migration: uses ctx.fs.files.stat, ctx.fs.dirs.list, ctx.fs.paths.resolve
 * instead of node:fs.
 */
import * as path from "node:path";
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const CORE_DIRECTIVES = ["AGENTS.md", "INVARIANTS.md", "ARCHITECTURE.md", "COMMANDS.md"];
const SKILL_DIRECTIVES = ["TESTING.md", "PITFALLS.md", "CONTRIBUTING.md", "TEMPLATE.md", "CHECKLIST.md"];
const ALL_DIRECTIVES = [...CORE_DIRECTIVES, ...SKILL_DIRECTIVES];

const schema = z.object({
  dirs: z.array(z.string()).min(1),
  walkUp: z.boolean().optional().default(true),
  patterns: z.array(z.string()).optional(),
  root: z.string().optional(),
});

type Args = z.infer<typeof schema>;

interface DiscoveredFile {
  path: string;
  type: "soft" | "hard";
  source: string;
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

async function isDirectory(p: string, ctx: RpcContext): Promise<boolean> {
  try {
    const result = await ctx.fs.files.stat({ path: p });
    return result.exists as boolean && result.type === "directory";
  } catch {
    return false;
  }
}

async function scanDir(
  dir: string,
  fileList: string[],
  seen: Set<string>,
  ctx: RpcContext,
): Promise<DiscoveredFile[]> {
  const results: DiscoveredFile[] = [];
  const realDir = await resolveReal(dir, ctx);

  for (const filename of fileList) {
    // Check .directives/FILENAME first (preferred)
    const directivePath = path.join(realDir, ".directives", filename);
    if (await fileExists(directivePath, ctx)) {
      const real = await resolveReal(directivePath, ctx);
      if (!seen.has(real)) {
        seen.add(real);
        results.push({ path: real, type: "soft", source: realDir });
      }
      continue;
    }

    // Fallback: check dir/FILENAME (legacy flat layout)
    const flatPath = path.join(realDir, filename);
    if (await fileExists(flatPath, ctx)) {
      const real = await resolveReal(flatPath, ctx);
      if (!seen.has(real)) {
        seen.add(real);
        results.push({ path: real, type: "soft", source: realDir });
      }
    }
  }

  // Also discover CMD_*.md files in .directives/commands/
  const cmdDir = path.join(realDir, ".directives", "commands");
  if (await isDirectory(cmdDir, ctx)) {
    try {
      const { entries } = await ctx.fs.dirs.list({ path: cmdDir });
      const dirEntries = entries as Array<{ name: string; type: string }>;
      for (const entry of dirEntries) {
        if (entry.name.startsWith("CMD_") && entry.name.endsWith(".md")) {
          const cmdPath = await resolveReal(path.join(cmdDir, entry.name), ctx);
          if (!seen.has(cmdPath)) {
            seen.add(cmdPath);
            results.push({ path: cmdPath, type: "soft", source: realDir });
          }
        }
      }
    } catch {
      // Can't read commands dir — skip
    }
  }

  return results;
}

export async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ files: DiscoveredFile[] }>> {
  const root = args.root ? await resolveReal(args.root, ctx) : await resolveReal(process.cwd(), ctx);

  // Build file list based on patterns filter
  let fileList: string[];
  if (args.patterns && args.patterns.length > 0) {
    // Core directives + filtered skill directives
    fileList = [
      ...CORE_DIRECTIVES,
      ...SKILL_DIRECTIVES.filter((f) => args.patterns!.includes(f)),
    ];
  } else {
    fileList = ALL_DIRECTIVES;
  }

  const seen = new Set<string>();
  const allResults: DiscoveredFile[] = [];

  for (const dir of args.dirs) {
    const realDir = await resolveReal(dir, ctx);

    // Scan the target directory
    allResults.push(...await scanDir(realDir, fileList, seen, ctx));

    // Walk up if enabled
    if (args.walkUp) {
      let current = path.dirname(realDir);
      while (true) {
        // Stop at root boundary or filesystem root
        if (current.length < root.length || current === "/" || current === path.dirname(current)) {
          break;
        }

        allResults.push(...await scanDir(current, fileList, seen, ctx));
        current = path.dirname(current);
      }
    }
  }

  return { ok: true, data: { files: allResults } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "agent.directives.discover": typeof handler;
  }
}

registerCommand("agent.directives.discover", { schema, handler });
