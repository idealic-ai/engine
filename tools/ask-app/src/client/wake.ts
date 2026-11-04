/**
 * WAKEUI: the client half of WAKEBTN. The server (src/lib/wake.ts) decides whether a wake is allowed
 * and records it; these pure rules say what the button and its line show from the row /api/asks sent
 * and from a click's own answer. The shapes are lib/wake.ts's (WakeView, WakeResult), imported as types.
 *
 * What is never said: that the seat read anything. "delivered" means the seat's session took the bytes;
 * its `engine ask read` stamp is the read, and the ask app does not show that here.
 */
import type { WakeResult, WakeView } from "../lib/wake.ts";

/** A row's wake fields as /api/asks sends them; all absent from a server that predates WAKEBTN. */
export type WakeRow = Partial<WakeView>;

// AUTOWAKE: the holder-notice fields too, all absent when no notice was pushed.
const KEYS = ["wakeTarget", "wokenAt", "wokenBy", "wokenSeat", "wakeDelivery", "wakeDeliveryNote", "wakeAfter", "wakeBlocked", "wakeBlockedReason", "noticedAt", "noticedSeat", "noticeDelivery", "noticeDeliveryNote"] as const;

/** The wake fields a listed ask carries, and only those it carries. */
export function wakeFields(a: object): WakeRow {
  const src = a as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const k of KEYS) if (src[k] !== undefined) out[k] = src[k];
  return out as WakeRow;
}

/** The route, for the ask's own folder seat and id, each encoded. */
export const wakeUrl = (seat: string, id: string) => `/api/asks/${encodeURIComponent(seat)}/${encodeURIComponent(id)}/wake`;

export const WAKE_WORDS = {
  notARead: "Delivered means the seat's session took the message, not that the seat read it. Its read stamp on the ask is the read.",
  /** AUTOWAKE: the holder notice's tooltip; "told" claims no more than a delivery. */
  noticeNotARead: "The server pushed the holder a notice of this ask. Told means the seat's session took it, not that the seat read it. A notice starts no cooldown.",
  refused: {
    closed: "the ask is no longer open",
    operator: "the ask waits on the operator, who is not a seat",
    cooldown: "it was woken less than five minutes ago",
    "no-pane": "no single live session holds that seat",
  } as Record<string, string>,
};

/** m:ss, never negative. */
export function countdown(ms: number): string {
  const s = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function ago(ms: number): string {
  const m = Math.floor(Math.max(0, ms) / 60_000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  return h < 48 ? `${h}h ago` : `${Math.floor(h / 24)}d ago`;
}

export type WakeStatus = { tone: "ok" | "warn" | "muted"; text: string; title: string };
export type WakeUi = { show: boolean; label: string; disabled: boolean; title: string; counting?: string; reason?: string; status?: WakeStatus; notice?: WakeStatus };

/**
 * AUTOWAKE: the holder notice the server pushed, in one quiet line: "<seat> told 3m ago" when it was
 * delivered, "<seat> not told: <note>" when it was not; nothing when no notice was pushed.
 */
export function noticeOf(w: WakeRow, now: number): WakeStatus | undefined {
  const at = Date.parse(w.noticedAt ?? "");
  if (!Number.isFinite(at)) return undefined;
  const seat = w.noticedSeat || w.wakeTarget || "the seat";
  const title = WAKE_WORDS.noticeNotARead;
  if (w.noticeDelivery === "delivered") return { tone: "muted", text: `${seat} told ${ago(now - at)}`, title };
  if (w.noticeDelivery === "undelivered") return { tone: "warn", text: `${seat} not told: ${w.noticeDeliveryNote || "no reason recorded"}`, title };
  return undefined;
}

/** The latest wake, in words that claim no more than its record says. */
function statusOf(w: WakeRow, now: number): WakeStatus | undefined {
  const at = Date.parse(w.wokenAt ?? "");
  if (!Number.isFinite(at)) return undefined;
  const seat = w.wokenSeat || w.wakeTarget || "the seat";
  const when = ago(now - at);
  const title = WAKE_WORDS.notARead;
  switch (w.wakeDelivery) {
    case "delivered":
      return { tone: "ok", text: `${seat} woken ${when}`, title };
    case "undelivered":
      return { tone: "warn", text: `${seat} not delivered ${when}: ${w.wakeDeliveryNote || "no reason recorded"}`, title };
    case "partial":
      return { tone: "warn", text: `${seat} partly delivered ${when}${w.wakeDeliveryNote ? `: ${w.wakeDeliveryNote}` : ""}`, title };
    default:
      return { tone: "muted", text: `waking ${seat}: started ${when}, delivery not confirmed`, title };
  }
}

/**
 * The tooltip while a cooldown runs, worded by the delivery record: the server holds a cooldown for a
 * pending or partial wake too, so "woken" is said only of one that was delivered. On a sidebar row
 * this is the only wording shown.
 */
function cooldownTitle(w: WakeRow, target: string, counting: string): string {
  const seat = w.wokenSeat || target;
  const again = `It can be woken again in ${counting}.`;
  if (w.wakeDelivery === "delivered") return `${seat} was woken for this ask; it can be woken again in ${counting}.`;
  if (w.wakeDelivery === "partial") return `Wake partly delivered to ${seat}. ${again}`;
  return `Wake sent to ${seat}; delivery not confirmed. ${again}`;
}

/** SHOULD-1: a row draws its bell unless the ask is closed or waits on the operator, which no click gets past. */
export function showsRowBell(w: WakeRow | undefined): w is WakeRow {
  return !!w && w.wakeBlocked !== "closed" && w.wakeBlocked !== "operator";
}

/**
 * NIT 1: a 409 cooldown's `wakeAfter`, laid over the row so the count restarts when this browser's
 * clock had let it go early. A later cooldown the row already holds, and any other block, are kept.
 */
export function holdCooldown(row: WakeRow, wakeAfter: string): WakeRow {
  if (Date.parse(row.wakeAfter ?? "") >= Date.parse(wakeAfter)) return row;
  return { ...row, wakeAfter, ...(row.wakeBlocked && row.wakeBlocked !== "cooldown" ? {} : { wakeBlocked: "cooldown" as const }) };
}

/** NIT 3: a gate that opens once per key, so one cooldown's end reloads the list once, from whichever button saw it first. */
export function expiryGate(): (key: string) => boolean {
  const seen = new Set<string>();
  return (key) => {
    if (seen.has(key)) return false;
    if (seen.size > 500) seen.clear();
    seen.add(key);
    return true;
  };
}

/**
 * What the button shows at `now`. A cooldown is counted from `wakeAfter` and holds only until then:
 * nothing changes the file when it ends, so no SSE refreshes the row, and a `wakeBlocked: cooldown`
 * that has run out no longer disables. Any other block holds until the server says otherwise.
 */
export function wakeUi(w: WakeRow, now: number, o: { busy?: boolean } = {}): WakeUi {
  if (w.wakeTarget === undefined) return { show: false, label: "", disabled: true, title: "" };
  const target = w.wakeTarget.trim();
  const name = target ? `Wake ${target}` : "Wake";
  const left = Date.parse(w.wakeAfter ?? "") - now;
  const counting = left > 0 ? countdown(left) : undefined;
  const blocked = !!w.wakeBlocked && w.wakeBlocked !== "cooldown";
  const reason = blocked ? w.wakeBlockedReason || WAKE_WORDS.refused[w.wakeBlocked!] || w.wakeBlocked : undefined;
  const label = o.busy ? `Waking ${target || "the seat"}…` : counting ? `${name} in ${counting}` : name;
  const title = reason ?? (counting ? cooldownTitle(w, target, counting) : `Push ${target} a message asking it to read its asks. ${WAKE_WORDS.notARead}`);
  const status = statusOf(w, now);
  // AUTOWAKE: a notice is shown, never counted: it disables nothing.
  const notice = noticeOf(w, now);
  return { show: true, label, disabled: !!o.busy || blocked || !!counting, title, ...(counting ? { counting } : {}), ...(reason ? { reason } : {}), ...(status ? { status } : {}), ...(notice ? { notice } : {}) };
}

/**
 * A click's 200, laid over the row until the listing catches up. The listing wins once it records this
 * wake's outcome or a later wake (a forward may have moved the target since). An undelivered push
 * starts no cooldown, so it lifts the pending claim's; any other block the row holds stays.
 */
export function mergeResult(row: WakeRow, r: WakeResult): WakeRow {
  const rowAt = Date.parse(row.wokenAt ?? "");
  const resAt = Date.parse(r.wokenAt);
  if (rowAt > resAt || (rowAt === resAt && row.wakeDelivery !== "pending")) return row;
  const out: WakeRow = { ...row, wokenAt: r.wokenAt, wokenBy: r.wokenBy, wokenSeat: r.target, wakeDelivery: r.delivery.status };
  if (r.delivery.reason) out.wakeDeliveryNote = r.delivery.reason;
  else delete out.wakeDeliveryNote;
  if (r.wakeAfter) {
    out.wakeAfter = r.wakeAfter;
    if (!out.wakeBlocked) {
      out.wakeBlocked = "cooldown";
      out.wakeBlockedReason = `woken at ${r.wokenAt}; it can be woken again at ${r.wakeAfter}`;
    }
  } else {
    delete out.wakeAfter;
    if (out.wakeBlocked === "cooldown") {
      delete out.wakeBlocked;
      delete out.wakeBlockedReason;
    }
  }
  return out;
}

/** What the route's answer becomes: a result to lay over the row, a line to show, and whether to reload the list. */
export function wakeOutcome(status: number, json: any, restarted?: "updated" | "failed"): { result?: WakeResult; text?: string; refresh: boolean; wakeAfter?: string } {
  if (restarted) return { text: restarted === "updated" ? "The app was updated: reload to wake." : "The app restarted: reload to wake.", refresh: false };
  if (status === 200) return { result: json as WakeResult, refresh: true };
  const said = json?.error ? String(json.error) : `HTTP ${status}`;
  if (status === 409) {
    const why = WAKE_WORDS.refused[String(json?.code)];
    return { text: why ? `Not woken: ${why} (${said})` : `Not woken: ${said}`, refresh: true, ...(typeof json?.wakeAfter === "string" ? { wakeAfter: json.wakeAfter } : {}) };
  }
  return { text: `Not woken: ${said}`, refresh: status === 404 };
}

/** The click takes nothing else with it: no row selection, no option pick, no form submit. */
export function clickWake(e: { preventDefault(): void; stopPropagation(): void }, fire: () => void): void {
  e.preventDefault();
  e.stopPropagation();
  fire();
}
