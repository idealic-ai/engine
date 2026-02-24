/**
 * RpcContext — typed context proxy for inter-namespace RPC calls.
 *
 * Namespace types are derived automatically from Registered keys via AllNamespaces.
 * Special cases (e.g., db = DbConnection & NamespaceOf) use NamespaceOverrides.
 *
 * Usage (in a handler):
 *   async function handler(args: Args, ctx: RpcContext): Promise<RpcResponse> {
 *     const session = await ctx.db.session.start({ taskId: "...", effortId: 1 });
 *     const embedding = await ctx.ai.embed({ text: "..." });
 *   }
 */
import type { AllNamespaces } from "./rpc-types.js";
import { z } from "zod/v4";

/** Zod schema for per-request environment variables injected by rpc-cli. */
export const rpcEnvSchema = z.object({
  // ── Defaulted (present after Zod parse, may be absent in raw input) ──
  /** Working directory of the calling process. Defaults to daemon's cwd. */
  CWD: z.string().default(process.cwd()),
  /** Agent identifier. Solo: "default". Fleet: "window:label". */
  AGENT_ID: z.string().default("default"),

  // ── Optional (fleet-only, absent for solo users) ───────
  /** Plugin root directory (e.g., ~/.claude/engine). */
  CLAUDE_PLUGIN_ROOT: z.string().optional(),
  /** Untargeted skill types this agent accepts (comma-separated nouns). */
  AGENT_CLAIMS: z.string().optional(),
  /** Targeted skill types with %pane-id (comma-separated nouns). */
  AGENT_TARGETED_CLAIMS: z.string().optional(),
  /** Child pane labels this agent monitors (comma-separated window:label). */
  AGENT_MANAGES: z.string().optional(),
  /** Parent pane label for escalation signaling. */
  AGENT_PARENT: z.string().optional(),
});

export type RpcEnv = z.infer<typeof rpcEnvSchema>;

export interface RpcContext extends AllNamespaces {
  /** Per-request environment variables injected by rpc-cli from the caller's process.env */
  env: RpcEnv;
}

/**
 * A namespace initializer returns the runtime methods object
 * that gets attached to ctx under its namespace key.
 */
export type NamespaceInitializer = (...args: unknown[]) => Record<string, unknown>;
