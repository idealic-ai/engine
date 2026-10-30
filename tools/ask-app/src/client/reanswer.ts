/**
 * IDE-304: changing an answer the operator already gave. The change reuses the open form: the same
 * sends (Send, Send as draft, a request, a decline), the same confirms, the same /api/draft then
 * /api/send path. The store takes the operator's draft over their own answer, and a second answer
 * tells the asker it CHANGED and what it replaced. What each handler decides lives here, pure.
 */
import { clickPlan, composeNote, isProvisional, provisionalAnswers, requestLine, stripLoopLines, type SendKind } from "./loop.ts";
import { askRef, isSettled, sendConfirmation, unansweredForks, type StoredAsk } from "./model.ts";
import { loadUnsent } from "./unsent.ts";
import { sendOutcome } from "./next.ts";
import { draftAuthor, isOperatorAnswer, type AnswerMap, type AnswerValue, type ParsedAsk } from "../lib/format.ts";

/** What sending a changed answer does, said beside the sends. */
export const CHANGE_WORDING =
  "Sending replaces your earlier answer. The asker is told the answer changed and what it replaced, and gets the new one unread.";

/**
 * What the operator may do to a recorded answer: change their own ("change", the store's rule, which
 * ruledBelow reads too), or overrule a seat's ruling ("overrule", IDE-339). Never on a superseded ask.
 */
export function changeMode(a: ParsedAsk): "change" | "overrule" | undefined {
  if (a.header.status === "superseded" || a.header.status === "withdrawn" || !a.answer) return undefined;
  if (!isSettled(a) && !isProvisional(a)) return undefined;
  if (isOperatorAnswer(a.answer)) return "change";
  // ASKOVR SHOULD-1: the store's assertMayAnswer (store.ts, not exported) refuses any answerer but the
  // one an ask is reserved for, so an ask reserved for a seat is never the operator's to overrule.
  const reserved = a.header["reserved-for"]?.trim();
  return reserved && reserved !== "operator" ? undefined : "overrule";
}

/** Change answer or Overrule is offered: a settled or provisional ask, not superseded. */
export function mayChangeAnswer(a: ParsedAsk): boolean {
  return changeMode(a) !== undefined;
}

/** What sending an overrule does, said beside the sends. */
export const OVERRULE_WORDING =
  "Sending replaces this seat's ruling with your answer. The asker and the seat that ruled are told it was overruled, and the ruling is kept under Earlier answers.";

/**
 * IDE-339: the /api/answer body for an overrule. The store takes no draft over a seat's answer
 * (writeDraft accepts one only over the operator's own), so an overrule is sent at once, never drafted.
 */
export function overruleBody(ask: StoredAsk, kind: "send" | "decline", s: { answers: AnswerMap; note: string }) {
  const plain = stripLoopLines(s.note);
  const base = { seat: ask.seat, id: ask.header.id, expectedRevision: Number(ask.header.revision) };
  return kind === "decline" ? { ...base, decline: plain.trim() } : { ...base, answers: s.answers, ...(plain ? { note: plain } : {}) };
}

/**
 * IDE-339: what /api/answer said to an overrule, read as sendOutcome reads /api/send, so an overrule
 * takes Send's after-send path: only a 200 is sent, its delivery line names the asker. A 409 is read
 * before this, by conflictMessage, as every send reads one.
 */
export function overruleOutcome(ask: StoredAsk, status: number, json: { delivery?: { status: string; reason?: string }; error?: string } | undefined): { sent: boolean; text: string } {
  const seat = ask.header.from?.trim() || ask.seat;
  const out = sendOutcome(status, status === 200 ? { pushes: json?.delivery ? [{ seat, delivery: json.delivery }] : [] } : json);
  return out.sent ? { sent: true, text: ["Overruled.", out.text].filter(Boolean).join(" ") } : out;
}

/**
 * IDE-339: a grant class is the answering manager's, written from the CLI; the server refuses one from
 * the browser. Every request body leaves through this, so no send path can carry one.
 */
export function withoutGrant<T>(body: T): T {
  if (!body || typeof body !== "object" || Array.isArray(body) || !("grantClass" in body)) return body;
  const rest = { ...(body as Record<string, unknown>) };
  delete rest.grantClass;
  return rest as T;
}

/**
 * The change form's starting state: the operator's saved change draft if there is one, else the
 * recorded answer. Draft and request lines are taken out; a decline's reason goes in the note,
 * where the open form reads a decline's reason from.
 */
export function changeAnswerStart(a: ParsedAsk): { values: Record<string, AnswerValue>; text: Record<string, string>; note: string } {
  const own = a.draft && draftAuthor(a.draft) === "operator" ? a.draft : undefined;
  const src = own ?? a.answer;
  const values: Record<string, AnswerValue> = {};
  const text: Record<string, string> = {};
  for (const [k, v] of Object.entries(src?.answers ?? {})) {
    if (k.endsWith(".other")) {
      const t = stripLoopLines(String(v));
      if (t) text[k.slice(0, -6)] = t;
    } else values[k] = v;
  }
  // IDE-339: an overrule starts from the seat's picks, but its note and reason were the seat's words, not yours.
  const note = !own && !isOperatorAnswer(a.answer) ? "" : src?.declined ? src.reason ?? "" : src?.note ?? "";
  return { values, text, note: stripLoopLines(note) };
}

/** Where a card keeps its unsent edits: a change apart from the open form's, so neither restores the other. */
export const unsentKey = (ref: string, changing: boolean) => (changing ? `change:${ref}` : ref);

/** A card's send verbs, for the open form, a change and an overrule alike. */
export type CardAction = "draft" | "draft-decline" | "discard" | "send-now";

/** Where a card's send goes: /api/answer at once for an overrule, else the draft path (Send then posts /api/send). */
export type SendRoute =
  | { endpoint: "/api/answer"; kind: "send" | "decline"; next: boolean }
  | { endpoint: "/api/draft" | "/api/discard"; kind: CardAction; next: boolean };

/**
 * IDE-339 (ASKOVR SHOULD-3): the one place a card send picks its endpoint. An overrule's Send, Send &
 * next and decline go to /api/answer, because the store takes no draft over a seat's answer; every
 * other send drafts first. App's act() dispatches its sends on this. Send as draft and Send request do
 * not come here: they go sendDraft / sendRequest → provisionalSend (loop.ts), which posts /api/draft
 * itself, and neither is offered on an overrule. An overrule's Save draft is hidden too; if reached it
 * takes the draft path, where the store refuses it, rather than going out as a final answer.
 */
export function sendRoute(overrule: boolean, kind: CardAction, next = false): SendRoute {
  if (overrule && kind === "send-now") return { endpoint: "/api/answer", kind: "send", next };
  if (overrule && kind === "draft-decline") return { endpoint: "/api/answer", kind: "decline", next: false };
  return { endpoint: kind === "discard" ? "/api/discard" : "/api/draft", kind, next };
}

/** The /api/draft body for Save draft, Draft a decline and Send (which then posts /api/send). */
export function draftBody(ask: StoredAsk, kind: "draft" | "draft-decline" | "send-now", s: { answers: AnswerMap; note: string }) {
  // SF-2: an ordinary save or send never carries the draft or request line along.
  const plain = stripLoopLines(s.note);
  const base = { seat: ask.seat, id: ask.header.id, expectedRevision: Number(ask.header.revision), note: plain || undefined };
  return kind === "draft-decline" ? { ...base, decline: s.note.trim() } : { ...base, answers: s.answers };
}

/** What a click on a send button does first, for the open form and a change alike. */
export function planClick(kind: SendKind, ctx: { ask: ParsedAsk; answers: AnswerMap; visible: ParsedAsk["questions"]; provisionalKept: boolean }): { confirm?: string } {
  return clickPlan(kind, { unanswered: unansweredForks(ctx.ask, ctx.answers, ctx.visible), provisionalKept: ctx.provisionalKept, confirmText: sendConfirmation });
}

/** Send request: the request line first, then the operator's own note (never an earlier request line). */
export function requestSend(ask: ParsedAsk, answers: AnswerMap, note: string, kind: string, words: string): { answers: AnswerMap; note: string } {
  const line = requestLine(kind, words);
  return { answers: provisionalAnswers(ask, answers, line), note: composeNote(line, stripLoopLines(note)) };
}

/** The asker came back: see model.ts followUpOf (the sidebar reads it there). */
export { followUpOf } from "./model.ts";

/** Cancel on a change drops the change draft the operator saved, so the card does not reopen changing. */
export function cancelDiscards(a: ParsedAsk): boolean {
  const open = (a.header.status ?? "open") === "open";
  return !open && !!a.draft && draftAuthor(a.draft) === "operator";
}

/** The `change:<ref>` entries of asks that can no longer be changed (superseded, re-ruled, reopened). */
export function staleChangeKeys(asks: StoredAsk[], has: (key: string) => boolean = (k) => !!loadUnsent(k)): string[] {
  return asks.filter((a) => !mayChangeAnswer(a)).map((a) => unsentKey(askRef(a), true)).filter(has);
}
