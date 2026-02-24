/**
 * agent.skills.parse — Parse SKILL.md JSON block and extract structured data.
 *
 * Ports the JSON extraction from resolve_phase_cmds() in lib.sh.
 * Reads SKILL.md via ctx.fs.files.read, finds the ```json block, parses it,
 * returns structured skill data.
 *
 * FS Migration: uses ctx.fs.files.read instead of node:fs.
 */
import type { RpcContext } from "engine-shared/context";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  skillPath: z.string(),
});

type Args = z.infer<typeof schema>;

/** Extract the JSON block between ```json and ``` markers from SKILL.md content */
function extractJsonBlock(content: string): string | null {
  const lines = content.split("\n");
  let inJson = false;
  const jsonLines: string[] = [];

  for (const line of lines) {
    if (line.trim() === "```json") {
      inJson = true;
      continue;
    }
    if (inJson && line.trim() === "```") {
      break;
    }
    if (inJson) {
      jsonLines.push(line);
    }
  }

  return jsonLines.length > 0 ? jsonLines.join("\n") : null;
}

export async function handler(args: Args, ctx: RpcContext): Promise<TypedRpcResponse<{ skill: Record<string, unknown> }>> {
  const { skillPath } = args;

  // Read SKILL.md via fs RPC
  let content: string;
  try {
    const readResult = await ctx.fs.files.read({ path: skillPath });
    content = readResult.content as string;
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes("FS_NOT_FOUND") || message.includes("not found")) {
      return { ok: false, error: "FS_NOT_FOUND", message: `SKILL.md not found: ${skillPath}` };
    }
    throw err;
  }

  // Extract frontmatter (--- delimited)
  const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
  const frontmatter: Record<string, string> = {};
  if (frontmatterMatch) {
    for (const line of frontmatterMatch[1].split("\n")) {
      const colonIdx = line.indexOf(":");
      if (colonIdx > 0) {
        const key = line.slice(0, colonIdx).trim();
        const val = line.slice(colonIdx + 1).trim().replace(/^["']|["']$/g, "");
        frontmatter[key] = val;
      }
    }
  }

  // Extract JSON block
  const jsonStr = extractJsonBlock(content);
  if (!jsonStr) {
    return {
      ok: true,
      data: {
        skill: {
          name: frontmatter.name ?? null,
          version: frontmatter.version ?? null,
          description: frontmatter.description ?? null,
          tier: frontmatter.tier ?? "utility",
          phases: null,
          modes: null,
          templates: null,
          nextSkills: null,
          directives: null,
        },
      },
    };
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(jsonStr);
  } catch {
    return { ok: false, error: "PARSE_ERROR", message: `Invalid JSON in SKILL.md: ${skillPath}` };
  }

  return {
    ok: true,
    data: {
      skill: {
        name: frontmatter.name ?? parsed.taskType ?? null,
        version: frontmatter.version ?? null,
        description: frontmatter.description ?? null,
        tier: frontmatter.tier ?? "protocol",
        phases: parsed.phases ?? null,
        modes: parsed.modes ?? null,
        templates: {
          plan: parsed.planTemplate ?? null,
          log: parsed.logTemplate ?? null,
          debrief: parsed.debriefTemplate ?? null,
          request: parsed.requestTemplate ?? null,
          response: parsed.responseTemplate ?? null,
        },
        nextSkills: parsed.nextSkills ?? null,
        directives: parsed.directives ?? null,
      },
    },
  };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "agent.skills.parse": typeof handler;
  }
}

registerCommand("agent.skills.parse", { schema, handler });
