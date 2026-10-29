/**
 * IDE-304: changing an answer the operator already gave. The store takes a second answer on a
 * settled ask (settle() replaces the answer block at the expected revision and clears the read and
 * acted marks), so the client only has to offer it, start the form from the recorded answer, and
 * post /api/answer at the revision it read.
 */
import { isProvisional, stripLoopLines, type Poster } from "./loop.ts";
import { conflictMessage } from "./supersede.ts";
import { isSettled, ruledBelow } from "./model.ts";
import type { AnswerMap, AnswerValue, ParsedAsk } from "../lib/format.ts";

/** What sending a changed answer does, said before the operator sends it. */
export const CHANGE_WORDING =
  "Sending replaces your earlier answer. The asker gets the new one as new and unread: the read and acted marks on the earlier answer are cleared.";

/**
 * Change answer is offered on a settled or provisional ask whose recorded answer is the operator's
 * own: not one a seat ruled, and never a superseded ask (the store refuses those anyway).
 */
export function mayChangeAnswer(a: ParsedAsk): boolean {
  if (a.header.status === "superseded" || !a.answer) return false;
  if (!isSettled(a) && !isProvisional(a)) return false;
  if (ruledBelow(a)) return false;
  return a.answer.answeredBy?.trim() === "operator";
}

/**
 * The form's starting state: the recorded picks, fork notes and note, with the draft and request
 * lines taken out (a changed answer is an ordinary answer; it does not inherit the loop's lines).
 */
export function changeAnswerStart(a: ParsedAsk): { values: Record<string, AnswerValue>; text: Record<string, string>; note: string } {
  const values: Record<string, AnswerValue> = {};
  const text: Record<string, string> = {};
  for (const [k, v] of Object.entries(a.answer?.answers ?? {})) {
    if (k.endsWith(".other")) {
      const t = stripLoopLines(String(v));
      if (t) text[k.slice(0, -6)] = t;
    } else values[k] = v;
  }
  return { values, text, note: stripLoopLines(a.answer?.note ?? "") };
}

export type ChangeOutcome = { ok: boolean; message: string; supersededBy?: string };

/** One write: /api/answer at the revision the card read. A 409 says the ask moved, or names its replacement. */
export async function sendChangedAnswer(
  post: Poster,
  args: { seat: string; id: string; expectedRevision: number; answers: AnswerMap; note: string },
): Promise<ChangeOutcome> {
  const plain = stripLoopLines(args.note);
  const r = await post("/api/answer", { seat: args.seat, id: args.id, expectedRevision: args.expectedRevision, answers: args.answers, ...(plain ? { note: plain } : {}) });
  if (r.status === 409) {
    const c = conflictMessage(r.json);
    return { ok: false, message: c.text, ...(c.supersededBy ? { supersededBy: c.supersededBy } : {}) };
  }
  if (r.status !== 200) return { ok: false, message: `Error: ${r.json?.error ?? r.status}` };
  const d = r.json?.delivery;
  const where = d?.status === "delivered" ? "queued at the asker, not read yet" : d?.status ? `saved, but ${d.status}${d.reason ? ` (${d.reason})` : ""}; the asker's /next picks it up from the file` : "saved";
  return { ok: true, message: `Answer changed (now revision ${r.json?.revision ?? "?"}): ${where}.` };
}
