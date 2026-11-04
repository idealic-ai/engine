/**
 * AUTOWAKE: tell an ask's holder that it holds the ask, by one push to the holder's live session.
 *
 * Why it exists: `engine ask new` and `engine ask forward` only wrote the file, so a seat that was
 * idle never heard the ask it held, and managers sat for hours on asks nobody had told them about.
 * The operator's standing order for this one wake, ruled on ask meta:engine/ask-wakes-holder
 * (2026-11-04 ~10:02): "every new ask pushes a short notice to its holder's session, waking it if
 * idle; asks to you are never pushed." That ruling is the whole licence. This module adds no other
 * wake path and does not touch broadcast's wake rules; it is called only by the CLI's `new` and
 * `forward`, right after the file is written.
 *
 * How the seat is reached: the same way every ask push and WAKEBTN's wake reach a seat —
 * `pushToSeat` (deliver.ts), which runs `lookupSeat` over ~/.claude/sessions/<pid>.json and refuses
 * none or more than one live match rather than guessing. A socket push to an idle session wakes it.
 * "delivered" means the socket took the bytes, not that the seat read them.
 *
 * Who is never pushed: an ask whose holder (`to:`) is `operator`, in any spelling `isOperatorName`
 * accepts. The operator is not a seat and reads asks in the app; no record is written for it either.
 * Nor is the seat that moved the ask, when it moved it to itself.
 *
 * The record, beside the `delivery` stamps the store already writes (all in STAMP_FIELDS, so `new`
 * and `revise` refuse them):
 *   newDelivery: delivered | undelivered   newDeliverySeat: <the holder pushed>
 *   newDeliveryAt: <iso>                   newDeliveryNote: <why>, when undelivered
 * Only the latest holder's notice is kept. Writing it never moves `revision`: the question did not
 * change, so an answer form opened before the notice is not made stale by it.
 *
 * A failed push never fails the caller: the ask is already filed, and the outcome is returned and
 * recorded. Only a missing or unreadable ask file throws.
 *
 * The reserved-decline pass-up (store.ts answerAsk) already pushes its own `[ask-passed-up]` notice
 * to the next holder; it is not pushed twice, and it records its outcome with store.ts `recordNotice`.
 */
import fs from "node:fs";
import { pushToSeat, type DeliverOptions, type DeliveryResult } from "./deliver.ts";
import { isOperatorName, parseAskFile, seatEq, type ParsedAsk } from "./format.ts";
import { recordNotice, resolveAskPath } from "./store.ts";

/** The header fields this notice writes (defined in format.ts, where STAMP_FIELDS includes them). */
export { NOTICE_FIELDS } from "./format.ts";

export type HolderNoticeKind = "new" | "forward";

/** `operator`: the operator is never pushed. `self`: the seat that moved the ask took it itself. */
export type HolderNoticeResult = { seat: string; delivery: DeliveryResult } | { seat: string; skipped: "operator" | "self" };

/** The push the holder reads: who asked (or passed it on), which ask, and the commands to read it. */
export function holderNoticeMessage(o: { kind: HolderNoticeKind; seat: string; id: string; file: string; ask: ParsedAsk; holder: string; by: string }): string {
  const ref = `${o.seat}/${o.id}`;
  const title = o.ask.questions[0]?.title;
  const quoted = title ? ` "${title}"` : "";
  const head =
    o.kind === "new"
      ? `[ask-new] ${o.by} asked you: ${ref}${quoted}`
      : `[ask-forwarded] ${o.by} passed you ${ref}${quoted} (asked by ${o.ask.header.from ?? o.seat})`;
  return [
    head,
    `Read your open asks with \`engine ask list --to ${o.holder} --status open\`, then \`engine ask read ${ref}\`; answer it, decline it, or forward it. The file is the record:`,
    o.file,
  ].join("\n");
}

/**
 * Push one notice to whoever `<seat>/<id>` is now addressed to (`to:`), then record the outcome.
 * Returns `skipped: "operator"` when the holder is the operator, and `skipped: "self"` when `by` is
 * the holder (a parent that forwarded the ask to itself). A push that fails or throws is an
 * `undelivered` result, never an exception.
 */
export async function noticeHolder(
  root: string,
  seat: string,
  id: string,
  o: DeliverOptions & { kind: HolderNoticeKind; by: string; push?: typeof pushToSeat; now?: string },
): Promise<HolderNoticeResult> {
  const file = resolveAskPath(root, seat, id);
  const ask = parseAskFile(fs.readFileSync(file, "utf8"));
  const holder = ask.header.to?.trim() ?? "";
  const at = o.now ?? new Date().toISOString();
  const skipped = !holder || isOperatorName(holder) ? "operator" : seatEq(o.by, holder) ? "self" : undefined;
  if (skipped) {
    // Nobody is pushed: the operator reads asks in the app, and a parent that took a silent holder's
    // ask with `forward --to <itself>` is the seat acting, so it is not told about its own move. An
    // earlier seat's notice is cleared rather than left standing as if it were the current holder's.
    if (ask.header.newDelivery !== undefined || ask.header.newDeliverySeat !== undefined) await recordNotice(file, holder, undefined, at);
    return { seat: holder || "operator", skipped };
  }
  const push = o.push ?? pushToSeat;
  let delivery: DeliveryResult;
  try {
    delivery = await push(holder, holderNoticeMessage({ kind: o.kind, seat, id, file, ask, holder, by: o.by }), o);
  } catch (e) {
    delivery = { status: "undelivered", reason: String(e) };
  }
  const result: HolderNoticeResult = { seat: holder, delivery: { status: delivery.status, ...(delivery.reason ? { reason: delivery.reason } : {}) } };
  await recordNotice(file, holder, delivery, at);
  return result;
}
