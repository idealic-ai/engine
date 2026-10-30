/**
 * ASKFOLLOW: the card's "Send follow-up" — a question back to the asker, or "do this first, then
 * revise the ask", optionally about one fork and carrying the operator's current picks. The server
 * (POST /api/followup, ASKFOLLOWUP) writes a `## Follow-up <n>` entry, bumps the revision and pushes
 * `[ask-followup]` to the asker; the ask stays open. What each handler decides lives here, pure.
 */
import { questionKey, type AnswerMap, type AskFollowup, type FollowupKind, type ParsedAsk } from "../lib/format.ts";
import { forkLabel, type StoredAsk, type Unsent } from "./model.ts";
import { conflictStep, type ConflictStep } from "./supersede.ts";

/** The two kinds, in the operator's words; `hint` is said beside the choice. */
export const FOLLOWUP_KIND_OPTIONS: readonly { kind: FollowupKind; label: string; hint: string }[] = [
  { kind: "question", label: "Ask a question", hint: "The asker answers it and revises the ask; you answer afterwards." },
  { kind: "first", label: "Do this first", hint: "The asker does it, then revises the ask with what it found." },
];

export const kindLabel = (k: FollowupKind | string) => FOLLOWUP_KIND_OPTIONS.find((o) => o.kind === k)?.label ?? String(k);

/** A follow-up goes only to an open ask: the server refuses a closed, superseded or withdrawn one. */
export function mayFollowUp(a: ParsedAsk): boolean {
  return (a.header.status ?? "open") === "open";
}

export type FollowupForm = { kind: FollowupKind; fork: string; text: string; attachPicks: boolean };

/** The /api/followup body. A blank fork is omitted (the whole ask); picks only when attached and present. */
export function followupBody(ask: StoredAsk, f: FollowupForm, picks: AnswerMap) {
  return {
    seat: ask.seat,
    id: ask.header.id,
    expectedRevision: Number(ask.header.revision),
    kind: f.kind,
    ...(f.fork ? { fork: f.fork } : {}),
    text: f.text,
    ...(f.attachPicks && Object.keys(picks).length ? { picks } : {}),
  };
}

type FollowupJson = { revision?: number; followup?: { n?: number }; delivery?: { status: string; reason?: string }; error?: string } | undefined;

/** What /api/followup said, other than a 409 (followupConflict reads those). */
export function followupOutcome(ask: StoredAsk, status: number, json: FollowupJson): { sent: true; revision: number; text: string } | { sent: false; text: string } {
  if (status !== 200) return { sent: false, text: `Not sent: ${json?.error ?? `HTTP ${status}`}` };
  const n = json?.followup?.n ?? "";
  const seat = ask.header.from?.trim() || ask.seat;
  const d = json?.delivery;
  const text =
    !d || d.status === "delivered"
      ? `Follow-up ${n} sent to ${seat}: delivered. The ask stays open; answer it as usual.`
      : `Follow-up ${n} is in the file, but ${d.status} (${d.reason ?? ""}). The asker's /next picks it up from the file.`;
  return { sent: true, revision: Number(json?.revision), text };
}

/**
 * A 409 from /api/followup. Superseded, withdrawn and stale are conflictStep's (same payloads as
 * /api/answer); an ask settled since it was read is said as such, its text kept here, and reloaded.
 */
export function followupConflict(json: Parameters<typeof conflictStep>[0] & { error?: string }, here: string, openKey: string): ConflictStep {
  const s = json?.status;
  if (typeof s === "string" && s !== "superseded" && s !== "withdrawn" && s !== "open") {
    return { text: `Not sent: this ask is ${s} now, and a follow-up goes only to an open ask. Your text is kept here.`, keepUnder: here, reload: true };
  }
  return conflictStep(json, here, openKey);
}

/**
 * The ask's follow-ups, oldest first: /api/asks' `history` entries of `type: "followup"`, or the
 * parsed `followups` when the history carries none (a server before ASKFOLLOWUP's history).
 */
export function followupsOf(a: ParsedAsk): AskFollowup[] {
  const h = (Array.isArray(a.history) ? a.history : []) as unknown[];
  const fromHistory = h.filter((e): e is AskFollowup & { type: "followup" } => !!e && typeof e === "object" && (e as { type?: unknown }).type === "followup");
  if (fromHistory.length) return fromHistory.map(({ type: _t, ...f }) => f as AskFollowup);
  return Array.isArray(a.followups) ? a.followups : [];
}

export const isAddressed = (f: AskFollowup) => f.addressedIn !== undefined && f.addressedIn !== null;

/** One follow-up in words: number, kind, fork, picks, delivery, addressed state. */
export function followupLine(a: ParsedAsk, f: AskFollowup): string {
  const qi = f.fork === undefined ? -1 : a.questions.findIndex((q, i) => questionKey(q, i) === f.fork);
  const fork = qi >= 0 ? `about ${forkLabel(a.questions[qi], qi)}: ${a.questions[qi].title}` : f.fork ? `about ${f.fork}` : "";
  const picks = Object.entries(f.picks ?? {}).map(([k, v]) => `${k} ${Array.isArray(v) ? v.join("+") : String(v)}`).join(", ");
  const delivery = !f.delivery ? "" : f.delivery === "delivered" || f.delivery === "pending" ? f.delivery : `${f.delivery}${f.deliveryNote ? ` (${f.deliveryNote})` : ""}`;
  const addressed = isAddressed(f) ? `addressed in revision ${f.addressedIn}${f.addressedBy ? ` by ${f.addressedBy}` : ""}` : "not addressed yet";
  return [`Follow-up ${f.n}`, kindLabel(f.kind), fork, picks ? `with your picks ${picks}` : "", delivery, addressed].filter(Boolean).join(" · ");
}

/**
 * After a 200 the revision moved. The card's unsent copy saved at the revision the follow-up was sent
 * from moves to the new one (the server re-bases the operator's draft the same way); a copy already
 * stale stays stale. The sent text is dropped either way.
 */
export function rebaseAfterFollowup(u: Unsent, sentFrom: string, revision: number): Unsent {
  const { followup: _sent, ...rest } = u;
  return rest.revision === sentFrom && Number.isFinite(revision) ? { ...rest, revision: String(revision) } : rest;
}

/** The result line, kept for the card that remounts at the new revision (the card is keyed by it). */
const results = new Map<string, { revision: string; text: string }>();
export function rememberFollowupResult(ref: string, revision: number | string, text: string) {
  results.set(ref, { revision: String(revision), text });
}
export function followupResultFor(ref: string, revision: string): string | undefined {
  const r = results.get(ref);
  return r && r.revision === revision ? r.text : undefined;
}
