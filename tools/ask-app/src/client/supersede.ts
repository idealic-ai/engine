/**
 * `engine ask supersede` and the decline pass-up, as the client reads them:
 * - a superseded ask: `status: superseded`, `superseded-by`, `superseded-at`, `superseded-actor`;
 * - the ask that replaces it: `supersedes: <seat>/<id> ; <seat>/<id>`;
 * - a 409 from /api/draft or /api/answer with `{status: "superseded", supersededBy}`;
 * - a passed-up decline: a `forwards:` hop ending in ` [declined: <reason>]`.
 */
import { forwardChain, type AskHeader } from "../lib/format.ts";

export type Superseded = { by: string; at?: string; actor?: string };

export function supersededInfo(h: AskHeader): Superseded | undefined {
  if (h.status !== "superseded") return undefined;
  const by = h["superseded-by"]?.trim() ?? "";
  return { by, ...(h["superseded-at"]?.trim() ? { at: h["superseded-at"].trim() } : {}), ...(h["superseded-actor"]?.trim() ? { actor: h["superseded-actor"].trim() } : {}) };
}

export function supersedesList(h: AskHeader): string[] {
  return (h.supersedes ?? "").split(/\s;\s|;/).map((s) => s.trim()).filter(Boolean);
}

/**
 * What a 409 from a write means. A superseded ask names its replacement; anything else is the ask
 * having moved on, and only then is a revision quoted (never "revision undefined").
 */
export function conflictMessage(json: { status?: string; supersededBy?: string; revision?: number | string } | undefined): { text: string; supersededBy?: string } {
  if (json?.status === "superseded") {
    const by = json.supersededBy?.trim();
    return by
      ? { text: `This ask was replaced by ${by}. Your picks are kept here; open the new ask to answer.`, supersededBy: by }
      : { text: "This ask was replaced by a newer ask. Your picks are kept here; open the new ask to answer." };
  }
  const rev = json?.revision;
  return { text: rev !== undefined && rev !== null && String(rev) !== "" ? `Not saved: the ask moved (now revision ${rev}). Read the current state before answering again.` : "Not saved: the ask moved. Read the current state before answering again." };
}

export type PathHop = { from: string; to: string; at: string; reason?: string };

const HOP_RE = /^(.+?)→(.+?)@(\S+?)(?:\s+\[declined:\s*([\s\S]*?)\])?$/;

/**
 * The forward chain with each hop's decline reason. Uses `Hop.reason` from forwardChain when the
 * engine provides it; until then reads the ` [declined: …]` tail itself.
 */
export function pathOf(h: AskHeader): PathHop[] {
  const engine = forwardChain(h) as (ReturnType<typeof forwardChain>[number] & { reason?: string })[];
  if (engine.some((x) => x.reason)) return engine.map((x) => ({ from: x.from, to: x.to, at: x.at, ...(x.reason ? { reason: x.reason } : {}) }));
  return (h.forwards ?? "")
    .split(/\s;\s/)
    .map((x) => x.trim().match(HOP_RE))
    .filter((m): m is RegExpMatchArray => !!m)
    .map((m) => ({ from: m[1].trim(), to: m[2].trim(), at: m[3], ...(m[4]?.trim() ? { reason: m[4].trim() } : {}) }));
}

/** One hop in words: "manager:meta declined: <reason> → passed up to operator", or "a → b". */
export function hopWords(p: PathHop): string {
  return p.reason ? `${p.from} declined: ${p.reason} → passed up to ${p.to}` : `${p.from} → ${p.to}`;
}
