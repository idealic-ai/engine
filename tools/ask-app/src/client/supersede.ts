/**
 * `engine ask supersede` and the decline pass-up, as the client reads them:
 * - a superseded ask: `status: superseded`, `superseded-by`, `superseded-at`, `superseded-actor`;
 * - the ask that replaces it: `supersedes: <seat>/<id> ; <seat>/<id>`;
 * - a 409 from /api/draft or /api/answer with `{status: "superseded", supersededBy}`;
 * - a withdrawn ask (ASKWITHDRAW): `status: withdrawn`, `withdrawn-actor`, `withdrawn-at`, `withdrawn-reason`,
 *   and its 409 `{status: "withdrawn", withdrawnBy, withdrawnAt, withdrawnReason}`;
 * - a passed-up decline: a `forwards:` hop ending in ` [declined: <reason>]`.
 */
import { forwardChain, type AskHeader } from "../lib/format.ts";

export type Superseded = { by: string; at?: string; actor?: string };

export function supersededInfo(h: AskHeader): Superseded | undefined {
  if (h.status !== "superseded") return undefined;
  const by = h["superseded-by"]?.trim() ?? "";
  return { by, ...(h["superseded-at"]?.trim() ? { at: h["superseded-at"].trim() } : {}), ...(h["superseded-actor"]?.trim() ? { actor: h["superseded-actor"].trim() } : {}) };
}

export type Withdrawn = { actor?: string; at?: string; reason?: string };

/** ASKWITHDRAW: who took the ask back, when and why; undefined for an ask that is not withdrawn. */
export function withdrawnInfo(h: AskHeader): Withdrawn | undefined {
  if (h.status !== "withdrawn") return undefined;
  const out: Withdrawn = {};
  for (const [k, f] of [["actor", "withdrawn-actor"], ["at", "withdrawn-at"], ["reason", "withdrawn-reason"]] as const) if (h[f]?.trim()) out[k] = h[f]!.trim();
  return out;
}

export function supersedesList(h: AskHeader): string[] {
  return (h.supersedes ?? "").split(/\s;\s|;/).map((s) => s.trim()).filter(Boolean);
}

/**
 * What a 409 from a write means. A superseded ask names its replacement; anything else is the ask
 * having moved on, and only then is a revision quoted (never "revision undefined").
 */
export function conflictMessage(
  json: { status?: string; supersededBy?: string; withdrawnBy?: string; withdrawnReason?: string; revision?: number | string } | undefined,
): { text: string; supersededBy?: string; withdrawn?: true } {
  // ASKWITHDRAW: the asker took it back; no ask replaces it, so there is nowhere else to answer.
  if (json?.status === "withdrawn") {
    const by = json.withdrawnBy?.trim();
    const why = json.withdrawnReason?.trim();
    return { text: `This ask was withdrawn${by ? ` by ${by}` : ""}${why ? ` (${why})` : ""}. There is nothing to answer; your picks are kept here.`, withdrawn: true };
  }
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

/** The forward chain with each hop's decline reason, as forwardChain reads it (unescaped). */
export function pathOf(h: AskHeader): PathHop[] {
  return forwardChain(h).map((x) => ({ from: x.from, to: x.to, at: x.at, ...(x.reason ? { reason: x.reason } : {}) }));
}

/** One hop in words: "manager:meta declined: <reason> → passed up to operator", or "a → b". */
export function hopWords(p: PathHop): string {
  return p.reason ? `${p.from} declined: ${p.reason} → passed up to ${p.to}` : `${p.from} → ${p.to}`;
}
