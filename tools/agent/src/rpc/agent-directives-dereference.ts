/**
 * agent.directives.dereference — Extract §CMD_* / §FMT_* / §INV_* references from content.
 *
 * Ports the extraction step of resolve_refs() from lib.sh.
 * Two-pass filter: (1) strip code fences and backtick spans, (2) extract bare § references.
 *
 * This is the "dereference" step — it tells you WHAT refs exist in a file.
 * The "resolve" step (agent.directives.resolve) finds WHERE those refs live on disk.
 */
import * as fs from "node:fs";
import { z } from "zod/v4";
import { registerCommand } from "engine-shared/dispatch";
import type { TypedRpcResponse } from "engine-shared/rpc-types";

const schema = z.object({
  path: z.string().optional(),
  content: z.string().optional(),
}).refine((data) => data.path || data.content, {
  message: "Either path or content must be provided",
});

type Args = z.infer<typeof schema>;

/** Strip code fences (``` blocks) and inline backtick spans from text */
function stripCodeBlocks(text: string): string {
  const lines = text.split("\n");
  const result: string[] = [];
  let inFence = false;

  for (const line of lines) {
    if (line.startsWith("```")) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    // Strip inline backtick spans
    result.push(line.replace(/`[^`]*`/g, ""));
  }

  return result.join("\n");
}

/** Extract bare §(CMD|FMT|INV)_NAME references from cleaned text */
function extractRefs(text: string): Array<{ sigil: string; prefix: string; name: string; raw: string }> {
  const pattern = /§(CMD|FMT|INV)_([A-Z][A-Z0-9_]*)/g;
  const seen = new Set<string>();
  const refs: Array<{ sigil: string; prefix: string; name: string; raw: string }> = [];

  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text)) !== null) {
    const raw = match[0];
    if (seen.has(raw)) continue;
    seen.add(raw);

    refs.push({
      sigil: "§",
      prefix: match[1],
      name: `${match[1]}_${match[2]}`,
      raw,
    });
  }

  return refs;
}

export function handler(args: Args): TypedRpcResponse<{ refs: Array<{ sigil: string; prefix: string; name: string; raw: string }> }> {
  let content: string;

  if (args.content) {
    content = args.content;
  } else if (args.path) {
    try {
      content = fs.readFileSync(args.path, "utf-8");
    } catch (err: any) {
      if (err.code === "ENOENT") {
        return { ok: false, error: "FS_NOT_FOUND", message: `File not found: ${args.path}` };
      }
      throw err;
    }
  } else {
    return { ok: false, error: "VALIDATION_ERROR", message: "Either path or content must be provided" };
  }

  const cleaned = stripCodeBlocks(content);
  const refs = extractRefs(cleaned);

  return { ok: true, data: { refs } };
}

declare module "engine-shared/rpc-types" {
  interface Registered {
    "agent.directives.dereference": typeof handler;
  }
}

registerCommand("agent.directives.dereference", { schema, handler });
