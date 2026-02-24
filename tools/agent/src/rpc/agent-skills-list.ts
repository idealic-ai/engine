/**
 * agent.skills.list — List available skills from search directories.
 *
 * Scans skill directories for SKILL.md files. Uses config.get for SKILLS_DIRS
 * when available, falls back to default paths. All FS operations via ctx.fs.*.
 *
 * FS Migration: uses ctx.fs.dirs.list, ctx.fs.files.stat, ctx.fs.files.read
 * instead of node:fs.
 */
import type { RpcContext } from "engine-shared/context";
import * as path from "node:path";
import * as os from "node:os";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  searchDirs: z.array(z.string()).optional(),
  projectId: z.number().optional(),
});

type Args = z.infer<typeof schema>;

interface SkillEntry {
  name: string;
  path: string;
  tier: "protocol" | "utility";
}

async function detectTier(skillPath: string, ctx: RpcContext): Promise<"protocol" | "utility"> {
  try {
    const { content } = await ctx.fs.files.read({ path: skillPath });
    const text = content as string;
    // Check frontmatter for tier
    const frontmatterMatch = text.match(/^---\n([\s\S]*?)\n---/);
    if (frontmatterMatch) {
      const tierLine = frontmatterMatch[1].split("\n").find((l: string) => l.startsWith("tier:"));
      if (tierLine) {
        const val = tierLine.split(":")[1].trim();
        if (val === "protocol" || val === "utility") return val;
      }
    }
    // Heuristic: if it has a ```json block with phases, it's protocol
    if (text.includes('"phases"')) return "protocol";
    return "utility";
  } catch {
    return "utility";
  }
}

async function getDefaultDirs(ctx: RpcContext): Promise<string[]> {
  const homeDir = os.homedir();
  const pluginRoot = ctx.env?.CLAUDE_PLUGIN_ROOT ?? path.join(homeDir, ".claude", "engine");
  const cwd = ctx.env?.CWD ?? process.cwd();

  const dirs = [
    path.join(homeDir, ".claude", "skills"),
    path.join(pluginRoot, "skills"),
  ];

  // Add project-local skills if cwd has .claude/skills/
  const projectSkills = path.join(cwd, ".claude", "skills");
  try {
    const { exists } = await ctx.fs.files.stat({ path: projectSkills });
    if (exists) {
      dirs.push(projectSkills);
    }
  } catch {
    // Ignore
  }

  return dirs;
}

export async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ skills: SkillEntry[] }>> {
  const searchDirs = args.searchDirs ?? await getDefaultDirs(ctx);
  const skills: SkillEntry[] = [];
  const seen = new Set<string>();

  for (const dir of searchDirs) {
    // Check directory exists
    let entries: Array<{ name: string; type: string }>;
    try {
      const result = await ctx.fs.dirs.list({ path: dir, type: "directory" });
      entries = result.entries as Array<{ name: string; type: string }>;
    } catch {
      continue; // Directory doesn't exist or can't be read
    }

    for (const entry of entries) {
      if (seen.has(entry.name)) continue;

      const skillDir = path.join(dir, entry.name);
      const skillFile = path.join(skillDir, "SKILL.md");

      // Check SKILL.md exists
      try {
        const { exists } = await ctx.fs.files.stat({ path: skillFile });
        if (!exists) continue;
      } catch {
        continue;
      }

      seen.add(entry.name);
      skills.push({
        name: entry.name,
        path: skillFile,
        tier: await detectTier(skillFile, ctx),
      });
    }
  }

  // Sort alphabetically
  skills.sort((a, b) => a.name.localeCompare(b.name));

  return { ok: true, data: { skills } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "agent.skills.list": typeof handler;
  }
}

registerCommand("agent.skills.list", { schema, handler });
