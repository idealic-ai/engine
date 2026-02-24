/**
 * transformHookInput — Pre-processes raw Claude Code hook JSON for Zod validation.
 *
 * Claude Code sends hook input with snake_case keys (tool_name, transcript_path, etc).
 * Our Zod schemas expect camelCase keys (toolName, transcriptPath, etc).
 * This transform bridges the gap, reusing the same snakeToCamel function from db-wrapper.
 *
 * Used as a Zod z.preprocess() step before schema validation.
 */

/** snake_case → camelCase (same algorithm as db-wrapper) */
export function snakeToCamel(s: string): string {
  return s.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());
}

/**
 * Recursively transform all keys in an object from snake_case to camelCase.
 * Leaves non-object values untouched.
 */
export function transformKeys(input: unknown): unknown {
  if (input === null || input === undefined) return input;
  if (Array.isArray(input)) return input.map(transformKeys);
  if (typeof input === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(input as Record<string, unknown>)) {
      out[snakeToCamel(k)] = v; // Only transform top-level keys, don't recurse into values
    }
    return out;
  }
  return input;
}
