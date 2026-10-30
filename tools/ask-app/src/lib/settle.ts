/**
 * ASKLIST: whether an ask still needs somebody, stated once on the server so the list can hide what
 * nothing waits on.
 *
 * An ask is SETTLED when nobody owes anything on it: it was answered or declined and the answer
 * reached its asker, or it was withdrawn or superseded. Reading is not part of it. `delivery:
 * delivered` means the push was queued, and `readAt` stays the asker's own read signal (store.ts,
 * stampDelivery; cli.ts lifeOf); neither is redefined here, and a push never stamps `readAt`.
 *
 * Two things keep an answered ask unsettled, each named in `owed`. What `by` names depends on the kind:
 * - `delivery`: the push did not land (`undelivered`, `partial`) or is still `pending`. `by` names the
 *   seats the push MISSED, read from `deliveryNote` (`combine()` in store.ts writes it as
 *   `<seat>: <reason>; <seat>: <reason>`), or the asker when the note names none (a `pending` push).
 *   A missed forwarder can be the only gap while the asker has the answer, so once the asker has read
 *   it (`readAt`, the asker's own read) the row is settled: a forwarder relays and owes nothing more.
 * - `follow-up`: a provisional answer (a `request:` line or the draft line in the note, `isProvisional`),
 *   whose asker owes a second round. `by` is the asker. It is closed by a later ask from the same asker
 *   naming it (the client's own `followUpOf` rule) or by the asker's own `acted` stamp. A forwarder's
 *   `acted` does not close it: a forwarder relays.
 *
 * This `settled` is not the client's `isSettled` (`answered|declined`): it means nothing is owed.
 *
 * The provisional and follow-up rules are the client's, imported rather than restated, so the list
 * and this field cannot disagree about which asks are provisional.
 */
import { seatEq, type ParsedAsk } from "./format.ts";
import { isProvisional } from "../client/loop.ts";
import { followUpOf } from "../client/model.ts";

export type Owed = { kind: "delivery" | "follow-up"; by: string; why: string };
export type Settlement = { settled: boolean; owed?: Owed };

type Ask = ParsedAsk & { seat: string };

const DONE = new Set(["withdrawn", "superseded"]);
const ANSWERED = new Set(["answered", "declined", "ruled", "answered-provisional"]);
const UNLANDED = new Set(["undelivered", "partial", "pending"]);

export function settlementOf<T extends Ask>(a: T, all: T[] = []): Settlement {
  const status = a.header.status?.trim() ?? "open";
  if (DONE.has(status)) return { settled: true };
  if (!ANSWERED.has(status)) return { settled: false };
  const asker = a.header.from?.trim() || a.seat;
  const delivery = a.header.delivery?.trim() ?? "";
  if (UNLANDED.has(delivery)) {
    if (a.header.readAt?.trim()) return { settled: true };
    const note = a.header.deliveryNote?.trim();
    const missed = missedSeats(note);
    return { settled: false, owed: { kind: "delivery", by: (missed.length ? missed : [asker]).join(", "), why: note ? `${delivery}: ${note}` : delivery } };
  }
  if (isProvisional(a) && !followUpOf(a, all) && !seatEq(a.header.actedBy?.trim(), asker)) {
    return { settled: false, owed: { kind: "follow-up", by: asker, why: "a provisional answer: the asker owes a follow-up ask" } };
  }
  return { settled: true };
}

/** The seats a push missed, from `combine()`'s note: `<seat>: <reason>` entries joined by `; `. */
export function missedSeats(note: string | undefined): string[] {
  const out: string[] = [];
  for (const part of (note ?? "").split("; ")) {
    const m = part.match(/^([\w.-]+(?::[\w.-]+)?): /);
    if (m && !out.includes(m[1])) out.push(m[1]);
  }
  return out;
}

/** Each ask with its settlement spread in: `settled` always, `owed` only when something is owed. */
export function withSettlement<T extends Ask>(asks: T[]): (T & Settlement)[] {
  return asks.map((a) => ({ ...a, ...settlementOf(a, asks) }));
}
