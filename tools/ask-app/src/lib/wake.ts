/**
 * WAKEBTN: wake the seat an ask is waiting on, on the operator's click in the ask app.
 *
 * Why it exists: a new ask tells its holder once, when it is written or forwarded (AUTOWAKE,
 * lib/holder-notice.ts, on the operator's ruling ask-wakes-holder), and never again on its own. When
 * the holder still has not answered, this button is how the operator wakes it again. The operator's
 * standing rule is "no --wake without the operator's order"; a click on this button IS that order,
 * given for one ask and one seat. Nothing else calls this: no timer, no hook, no CLI verb.
 *
 * The holder's notice is shown beside the wake state (`noticedAt`, `noticedSeat`, `noticeDelivery`,
 * `noticeDeliveryNote` on WakeView, read from the ask's `newDelivery*` stamps), so a client can say
 * "holder told 2 min ago" next to the button. A notice starts no cooldown: only a wake does.
 *
 * How a seat is found and woken: the same way every ask push reaches a seat. `lookupSeat`
 * (deliver.ts) matches the seat name in ~/.claude/sessions/<pid>.json against a live pid; none or
 * more than one is refused, never guessed between. The push is `pushToSeat` (deliver.ts), the same
 * function `engine broadcast --wake-reason` runs for its live push (broadcast.sh `deliver`). A
 * socket push to an idle session wakes it. "delivered" means the socket took the bytes, not that the
 * seat read them: its `engine ask read` stamp is the read.
 *
 * The record is four header fields, beside the `delivery` stamps the store already writes:
 *   wokenAt: <iso>   wokenBy: operator   wokenSeat: <the seat woken>
 *   wakeDelivery: pending | delivered | undelivered   (wakeDeliveryNote: <why>, when undelivered)
 * Only the latest wake is kept. A wake never moves `revision`: the ask's question and answer did not
 * change, so an answer form opened before the wake is not made stale by it.
 */
import fs from "node:fs";
import { lookupSeat, pushToSeat, type DeliverOptions, type DeliveryResult, type SeatLookup } from "./deliver.ts";
import { AskFormatError, forwardChain, isOperatorName, parseAskFile, removeHeaderField, seatEq, setHeaderField, type ParsedAsk } from "./format.ts";
import { atomicWrite, resolveAskPath, SeatRenamedError, withFileLock } from "./store.ts";

/**
 * A second wake of the same ask, aimed at the same seat, is refused for this long after a wake that
 * was not undelivered. A forward moves the ask to a seat nobody woke, so the new holder is not held.
 */
export const WAKE_COOLDOWN_MS = 5 * 60_000;

/**
 * Why a wake is refused, as a stable code a client can switch on:
 * - `operator`: the ask waits on the operator, who is not a seat.
 * - `closed`: the ask is not open (answered, declined, superseded, withdrawn).
 * - `no-pane`: no single live session holds the seat (none, or more than one).
 * - `cooldown`: the ask's current holder was woken for it less than WAKE_COOLDOWN_MS ago; `wakeAfter` says when it may be again.
 */
export type WakeBlock = "operator" | "closed" | "no-pane" | "cooldown";

export class WakeRefused extends AskFormatError {
  readonly code: WakeBlock;
  readonly wakeAfter?: string;
  constructor(code: WakeBlock, message: string, wakeAfter?: string) {
    super(message);
    this.name = "WakeRefused";
    this.code = code;
    if (wakeAfter) this.wakeAfter = wakeAfter;
  }
}

/**
 * Who the ask is waiting on: the `to:` seat, which a forward rewrites, so after a pass-up it is the
 * newest `forwards:` hop's target. Read from the hop only when `to:` is empty.
 */
export function wakeTarget(ask: ParsedAsk): string {
  const to = ask.header.to?.trim();
  if (to) return to;
  return forwardChain(ask.header).at(-1)?.to ?? "";
}

const isOpen = (ask: ParsedAsk) => ask.header.status === "open" || ask.header.status === undefined;

/**
 * When the latest wake's cooldown ends, or undefined when there is none running at `now`. It runs
 * only while the seat that wake reached is still the one the ask waits on (`target`).
 */
function cooldownUntil(ask: ParsedAsk, now: number, target: string): string | undefined {
  const at = Date.parse(ask.header.wokenAt ?? "");
  if (!Number.isFinite(at) || ask.header.wakeDelivery === "undelivered") return undefined;
  if (!seatEq(ask.header.wokenSeat, target)) return undefined;
  const until = at + WAKE_COOLDOWN_MS;
  return now < until ? new Date(until).toISOString() : undefined;
}

function noPaneReason(seat: string, found: SeatLookup): string | undefined {
  if (found.kind === "none") return `no live session holds ${seat}: there is nothing to wake`;
  if (found.kind === "ambiguous") return `more than one live session answers to ${seat} (pids ${found.pids.join(", ")}): not guessing which to wake`;
  return undefined;
}

/** The first refusal that applies, in the order a reader would ask: is it open, who holds it, how recently woken, is anyone there. */
function refusalOf(ref: string, ask: ParsedAsk, target: string, now: number, lookup: (seat: string) => SeatLookup): WakeRefused | undefined {
  if (!isOpen(ask)) return new WakeRefused("closed", `${ref} is ${ask.header.status}: only an open ask waits on anybody`);
  if (!target) return new WakeRefused("no-pane", `${ref} names no seat it is waiting on`);
  if (isOperatorName(target)) return new WakeRefused("operator", `${ref} is waiting on the operator, who is not a seat to wake`);
  const after = cooldownUntil(ask, now, target);
  if (after) return new WakeRefused("cooldown", `${ref} was woken at ${ask.header.wokenAt}; it can be woken again at ${after}`, after);
  const why = noPaneReason(target, lookup(target));
  if (why) return new WakeRefused("no-pane", why);
  return undefined;
}

/** What /api/asks shows on a row: known without trying, so the client can disable the button up front. */
export type WakeView = {
  wakeTarget: string;
  wokenAt?: string;
  wokenBy?: string;
  wokenSeat?: string;
  wakeDelivery?: string;
  wakeDeliveryNote?: string;
  /** When the running cooldown ends; absent when none is running. */
  wakeAfter?: string;
  /** Why the button would be refused right now; absent when a wake would be attempted. */
  wakeBlocked?: WakeBlock;
  wakeBlockedReason?: string;
  /** AUTOWAKE: when the holder's notice was pushed (`newDeliveryAt`); absent when none was. */
  noticedAt?: string;
  /** The seat that notice went to (`newDeliverySeat`). */
  noticedSeat?: string;
  /** `delivered` (queued at that seat, not read) or `undelivered` (`newDelivery`). */
  noticeDelivery?: string;
  /** Why it was not delivered (`newDeliveryNote`). */
  noticeDeliveryNote?: string;
};

/** WakeView's names for the holder-notice stamps (format.ts NOTICE_FIELDS). */
const NOTICE_VIEW = { newDeliveryAt: "noticedAt", newDeliverySeat: "noticedSeat", newDelivery: "noticeDelivery", newDeliveryNote: "noticeDeliveryNote" } as const;

/**
 * The wake state of one ask at `now`. `lookup` defaults to lookupSeat over `sessionsDir`; a lister
 * passes a memoized one so a seat holding many asks is looked up once per listing.
 */
export function wakeView(ask: ParsedAsk, o: { now?: number; sessionsDir?: string; lookup?: (seat: string) => SeatLookup } = {}): WakeView {
  const now = o.now ?? Date.now();
  const lookup = o.lookup ?? ((s: string) => lookupSeat(s, { sessionsDir: o.sessionsDir }));
  const h = ask.header;
  const target = wakeTarget(ask);
  const v: WakeView = { wakeTarget: target };
  for (const k of ["wokenAt", "wokenBy", "wokenSeat", "wakeDelivery", "wakeDeliveryNote"] as const) if (h[k]) v[k] = h[k];
  for (const [k, name] of Object.entries(NOTICE_VIEW) as [keyof typeof NOTICE_VIEW, (typeof NOTICE_VIEW)[keyof typeof NOTICE_VIEW]][]) if (h[k]) v[name] = h[k];
  const after = isOpen(ask) ? cooldownUntil(ask, now, target) : undefined;
  if (after) v.wakeAfter = after;
  const no = refusalOf(`${h.from ?? ""}/${h.id ?? ""}`, ask, target, now, lookup);
  if (no) {
    v.wakeBlocked = no.code;
    v.wakeBlockedReason = no.message;
  }
  return v;
}

/** A lookup that reads the session registry once per seat: one listing, many asks, few seats. */
export function memoLookup(o: { sessionsDir?: string } = {}): (seat: string) => SeatLookup {
  const seen = new Map<string, SeatLookup>();
  return (seat) => {
    const k = seat.toLowerCase();
    if (!seen.has(k)) seen.set(k, lookupSeat(seat, { sessionsDir: o.sessionsDir }));
    return seen.get(k)!;
  };
}

/** The push the woken seat reads: who woke it, for which ask, and what to do. */
export function wakeMessage(seat: string, id: string, file: string, ask: ParsedAsk, target: string, by: string): string {
  const title = ask.questions[0]?.title;
  return [
    `[ask-wake] ${by} woke you for ask ${seat}/${id}: it is waiting on you. Please read your asks.`,
    ...(title ? [`Its first question: ${title}`] : []),
    `Read them with \`engine ask list --to ${target} --status open\`, then \`engine ask read ${seat}/${id}\` and answer it. The file is the record:`,
    file,
  ].join("\n");
}

export type WakeResult = {
  ref: string;
  target: string;
  wokenAt: string;
  wokenBy: string;
  delivery: DeliveryResult;
  /** When this ask may be woken again; absent when the push failed, since a failed wake starts no cooldown. */
  wakeAfter?: string;
};

/**
 * Wake whoever `<seat>/<id>` is waiting on. Only the ask app's server calls this, for the operator's
 * own click (see the module header); `by` is the server's stamp, never a request body's.
 *
 * Order: under the file lock, refuse (WakeRefused, with its code) or claim the wake by writing the
 * record with `wakeDelivery: pending`, so two clicks cannot both push; then push outside the lock;
 * then stamp the outcome, if the record is still this call's. Throws ENOENT for a missing ask and
 * AskFormatError for an invalid seat or id.
 */
export async function wakeAsk(
  root: string,
  seat: string,
  id: string,
  o: DeliverOptions & { by: string; now?: number; push?: typeof pushToSeat },
): Promise<WakeResult> {
  const file = resolveAskPath(root, seat, id);
  const ref = `${seat}/${id}`;
  const now = o.now ?? Date.now();
  const wokenAt = new Date(now).toISOString();
  const claimed = await withFileLock(file, () => {
    const text = fs.readFileSync(file, "utf8");
    const ask = parseAskFile(text);
    const target = wakeTarget(ask);
    const no = refusalOf(ref, ask, target, now, (s) => lookupSeat(s, o));
    if (no) throw no;
    let after = setHeaderField(text, "wokenAt", wokenAt);
    after = setHeaderField(after, "wokenBy", o.by);
    after = setHeaderField(after, "wokenSeat", target);
    after = setHeaderField(after, "wakeDelivery", "pending");
    after = removeHeaderField(after, "wakeDeliveryNote");
    atomicWrite(file, after);
    return { ask, target };
  });
  const push = o.push ?? pushToSeat;
  let delivery: DeliveryResult;
  try {
    delivery = await push(claimed.target, wakeMessage(seat, id, file, claimed.ask, claimed.target, o.by), o);
  } catch (e) {
    delivery = { status: "undelivered", reason: String(e) };
  }
  const stamp = (f: string) =>
    withFileLock(f, () => {
      const text = fs.readFileSync(f, "utf8");
      if (parseAskFile(text).header.wokenAt !== wokenAt) return; // a later wake owns the record
      let after = setHeaderField(text, "wakeDelivery", delivery.status);
      after = delivery.reason ? setHeaderField(after, "wakeDeliveryNote", delivery.reason.replace(/\n/g, " ")) : removeHeaderField(after, "wakeDeliveryNote");
      atomicWrite(f, after);
    });
  // The push has happened, so its outcome is the answer whatever the stamp does. As answerAsk does:
  // a seat renamed meanwhile gets the stamp at its new path; any other failure leaves the record
  // `pending`, which reads as a live wake until its cooldown ends, and is never reported as a failed wake.
  try {
    await stamp(file);
  } catch (e) {
    if (e instanceof SeatRenamedError) {
      try {
        await stamp(resolveAskPath(root, e.to, id));
      } catch {
        // left pending, as above
      }
    }
  }
  const result: WakeResult = { ref, target: claimed.target, wokenAt, wokenBy: o.by, delivery: { status: delivery.status, ...(delivery.reason ? { reason: delivery.reason } : {}) } };
  if (delivery.status !== "undelivered") result.wakeAfter = new Date(now + WAKE_COOLDOWN_MS).toISOString();
  return result;
}
