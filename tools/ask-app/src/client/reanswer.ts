/**
 * IDE-304: changing an answer the operator already gave. The change reuses the open form: the same
 * sends (Send, Send as draft, a request, a decline), the same confirms, the same /api/draft then
 * /api/send path. The store takes the operator's draft over their own answer, and a second answer
 * tells the asker it CHANGED and what it replaced. What each handler decides lives here, pure.
 */
import { clickPlan, composeNote, isProvisional, provisionalAnswers, requestLine, stripLoopLines, type SendKind } from "./loop.ts";
import { askRef, isSettled, sendConfirmation, unansweredForks, type StoredAsk } from "./model.ts";
import { loadUnsent } from "./unsent.ts";
import { draftAuthor, isOperatorAnswer, type AnswerMap, type AnswerValue, type ParsedAsk } from "../lib/format.ts";

/** What sending a changed answer does, said beside the sends. */
export const CHANGE_WORDING =
  "Sending replaces your earlier answer. The asker is told the answer changed and what it replaced, and gets the new one unread.";

/**
 * Change answer is offered on a settled or provisional ask whose recorded answer is the operator's
 * own (the store's rule, which ruledBelow reads too): not one a seat ruled, never a superseded ask.
 */
export function mayChangeAnswer(a: ParsedAsk): boolean {
  if (a.header.status === "superseded" || !a.answer) return false;
  if (!isSettled(a) && !isProvisional(a)) return false;
  return isOperatorAnswer(a.answer);
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
  const note = src?.declined ? src.reason ?? "" : src?.note ?? "";
  return { values, text, note: stripLoopLines(note) };
}

/** Where a card keeps its unsent edits: a change apart from the open form's, so neither restores the other. */
export const unsentKey = (ref: string, changing: boolean) => (changing ? `change:${ref}` : ref);

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
