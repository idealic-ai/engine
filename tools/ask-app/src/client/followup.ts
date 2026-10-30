/**
 * ASKFOLLOW: the card's "Send follow-up" — a question back to the asker, or "do this first, then
 * revise the ask", optionally about one fork and carrying the operator's current picks. The server
 * (POST /api/followup, ASKFOLLOWUP) writes a `## Follow-up <n>` entry, bumps the revision and pushes
 * `[ask-followup]` to the asker; the ask stays open. What each handler decides lives here, pure.
 */
import { currentRevision, isOperatorName, questionKey, type AnswerMap, type AskFollowup, type FollowupKind, type ParsedAsk } from "../lib/format.ts";
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
      : `Follow-up ${n} is in the file, but ${d.status}${d.reason ? ` (${d.reason})` : ""}. The asker's /next picks it up from the file.`;
  return { sent: true, revision: Number(json?.revision), text };
}

/**
 * A 409 from /api/followup. Superseded and withdrawn are conflictStep's (same payloads as /api/answer);
 * an ask settled since it was read is said as such, its text kept here, and reloaded. SHOULD-3: a stale
 * revision is a follow-up NOT SENT (nothing was being saved, and nothing moved): re-read, then send again.
 */
export function followupConflict(json: Parameters<typeof conflictStep>[0] & { error?: string }, here: string, openKey: string): ConflictStep {
  const s = json?.status;
  if (typeof s === "string" && s !== "superseded" && s !== "withdrawn" && s !== "open") {
    return { text: `Not sent: this ask is ${s} now, and a follow-up goes only to an open ask. Your text is kept here.`, keepUnder: here, reload: true };
  }
  if (s === "superseded" || s === "withdrawn") return conflictStep(json, here, openKey);
  const rev = json?.revision;
  const now = rev !== undefined && rev !== null && String(rev) !== "" ? ` (now revision ${rev})` : "";
  return { text: `Not sent: the ask changed${now}. Re-read it, then send again.`, reload: true };
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

/** The card's unsent copy moved to `revision`, without the follow-up it sent (text, kind, fork, attach box). */
export function rebaseAfterFollowup(u: Unsent, revision: number): Unsent {
  const { followup: _t, followKind: _k, followFork: _f, followAttach: _a, ...rest } = u;
  return { ...rest, revision: String(revision) };
}

/** Shown while the post is out, on this card and on one that remounts meanwhile (NIT-C: it claims no write). */
export const FOLLOWUP_PENDING = "Sending the follow-up to the asker…";

/**
 * Delta SHOULD-A/B, option (b): the follow-ups that made the ask's CURRENT revision, read from the
 * `revisions:` tail writeFollowup writes (`<rev>@<at>:followup <k>`). Delta 2: walked back over
 * consecutive follow-up entries, so `from` is the revision before the first of them; `n` and `text`
 * are the last one's. Undefined when the tail names another revision (forward and act bump without a
 * `revisions:` entry) or another change. A missing `revision:` is 0, as the server reads it (NIT-B).
 */
export function followupBumpOf(ask: ParsedAsk): { from: string; n: number; text?: string } | undefined {
  const cur = currentRevision(ask);
  const entries = (ask.header.revisions ?? "").split(";").map((s) => s.trim()).filter(Boolean);
  let at = cur;
  let last: number | undefined;
  for (let i = entries.length - 1; i >= 0; i--) {
    const m = entries[i].match(/^(\d+)@.*:followup (\d+)$/);
    if (!m || Number(m[1]) !== at) break;
    if (last === undefined) last = Number(m[2]);
    at--;
  }
  if (last === undefined) return undefined;
  const n = last;
  return { from: String(at), n, text: (ask.followups ?? []).find((f) => f.n === n)?.text };
}

/**
 * MUST-FIX-1 and delta SHOULD-A/B: a copy saved before a run of follow-ups is still current (they change
 * neither the questions nor the body; writeFollowup re-bases the operator's draft for the same reason).
 * Delta 2 SHOULD-A: a kept text equal to ANY operator follow-up already on the ask was sent, whatever
 * the revision, so it is dropped with its settings; adoption only decides whether the picks stand.
 */
export function adoptAfterFollowup(kept: Unsent | undefined, ask: ParsedAsk): Unsent | undefined {
  if (!kept) return kept;
  const t = kept.followup?.trim();
  const sent = !!t && (ask.followups ?? []).some((f) => isOperatorName(f.by) && f.text?.trim() === t);
  const b = followupBumpOf(ask);
  const k = Number(kept.revision || "0");
  const adopt = !!b && k >= Number(b.from) && k < currentRevision(ask);
  if (!sent && !adopt) return kept;
  const base = sent ? rebaseAfterFollowup(kept, k) : kept;
  return adopt ? { ...base, revision: String(currentRevision(ask)) } : { ...base, revision: kept.revision };
}

/** Delta SHOULD-A: a card writes its copy only when no newer card has saved one since. */
export function keepsOver(stored: Unsent | undefined, revision: string): boolean {
  return !stored || !(Number(stored.revision) > Number(revision));
}

/** Delta SHOULD-C: opening the panel on blank text takes the fork in focus now; typed text keeps its fork. */
export function forkOnOpen(text: string, focusedKey: string | undefined, current: string): string {
  return text.trim() ? current : focusedKey ?? "";
}

/**
 * The result line, kept per ask for the card at the revision it names, and subscribable: a card that
 * remounted before the 200 (MUST-FIX-1) still gets the line when it lands.
 */
const results = new Map<string, { revisions: string[]; text: string }>();
const listeners = new Set<() => void>();
const changed = () => listeners.forEach((l) => l());
export function subscribeFollowupResults(l: () => void): () => void {
  listeners.add(l);
  return () => void listeners.delete(l);
}
export function rememberFollowupResult(ref: string, revision: number | string | (number | string)[], text: string) {
  results.set(ref, { revisions: (Array.isArray(revision) ? revision : [revision]).map(String), text });
  changed();
}
export function forgetFollowupResult(ref: string) {
  if (results.delete(ref)) changed();
}
export function followupResultFor(ref: string, revision: string): string | undefined {
  const r = results.get(ref);
  return r && r.revisions.includes(revision) ? r.text : undefined;
}
