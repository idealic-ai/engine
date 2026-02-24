/**
 * hook-base-schema — Shared Zod schema for Claude Code hook stdin JSON.
 *
 * Claude Code sends these common fields on stdin for ALL hook events
 * (snake_case, transformed to camelCase by transformKeys).
 *
 * Event-specific handlers extend this base with their own fields via hookSchema().
 */
import { z } from "zod/v4";
import { transformKeys } from "./transform-hook-input.js";

/** Common fields present in ALL Claude Code hook events */
export const hookBase = z.object({
  sessionId: z.string(),       // Claude's session UUID string — NOT engine's numeric ID
  transcriptPath: z.string(),
  cwd: z.string(),
  permissionMode: z.string().optional(),  // Not sent by SessionStart
  hookEventName: z.string(),
});

export type HookBaseInput = z.infer<typeof hookBase>;

/**
 * Build a Zod schema for a hook event by extending the base with event-specific fields.
 * Applies snake_case→camelCase preprocessing automatically.
 */
export function hookSchema<T extends z.ZodRawShape>(shape: T) {
  return z.preprocess(transformKeys, hookBase.extend(shape));
}
