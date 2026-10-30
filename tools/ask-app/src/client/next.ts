/**
 * Send & next (IDE-304, operator 15:45): after a send the server accepted, open the next ask in the
 * sidebar's current order (the filtered and searched list) that is waiting on the operator. Pure, so
 * the order and the "failed send stays put" rule are tested without a browser.
 */

export type NextRow = { ref: string; waitingOnYou: boolean };

/**
 * The next waiting ask after `currentRef` in `rows` order, wrapping round to the ones above it, never
 * `currentRef` itself (its row still says waiting until the list reloads). Undefined when no other
 * row waits, so "Nothing else is waiting on you" is only ever said when it is true of the list.
 */
export function nextWaiting(rows: readonly NextRow[], currentRef: string): string | undefined {
  const at = rows.findIndex((r) => r.ref === currentRef);
  const order = at === -1 ? rows : [...rows.slice(at + 1), ...rows.slice(0, at)];
  return order.find((r) => r.waitingOnYou && r.ref !== currentRef)?.ref;
}

export const NOTHING_WAITING = "Nothing else is waiting on you.";

/** What Send & next does once the send settles: a failed or refused send never navigates. */
export function afterSendNext(sent: boolean, rows: readonly NextRow[], currentRef: string): { go?: string; notice?: string } {
  if (!sent) return {};
  const go = nextWaiting(rows, currentRef);
  return go ? { go } : { notice: NOTHING_WAITING };
}

// ── after a send (ASKHL fix round 1) ─────────────────────────

/** A post-send line held by App, keyed by the sent ask's ref, so it outlives the card's ref+revision remount. */
export type SentNotice = { ref: string; text: string };

/** The notice for the ask on screen: by ref alone, so the revision a send bumps does not lose it. */
export function noticeFor(n: SentNotice | undefined, currentRef: string | undefined): string | undefined {
  return n && currentRef === n.ref ? n.text : undefined;
}

type Push = { seat: string; delivery: { status: string; reason?: string } };
/**
 * What a single-ask /api/send answered. Only a 200 with nothing refused is sent; a refusal or any
 * other status shows the server's words and keeps the browser's unsent copy (SHOULD-1).
 */
export function sendOutcome(status: number, json: { refused?: { error: string }[]; pushes?: Push[]; error?: string } | undefined): { sent: boolean; text: string } {
  if (json?.refused?.length) return { sent: false, text: `Refused: ${json.refused[0].error}` };
  if (status !== 200) return { sent: false, text: `Error: ${json?.error ?? `HTTP ${status}`}` };
  const p = json?.pushes?.[0];
  if (!p) return { sent: true, text: "" };
  return {
    sent: true,
    text: p.delivery.status === "delivered" ? `Queued at ${p.seat}, not read yet. It turns "read" when the seat runs engine ask read.` : `Saved, but ${p.delivery.status} (${p.delivery.reason ?? ""}). The asker's /next picks it up from the file.`,
  };
}

/**
 * App's step once a send is accepted. `routeAsk` and `shownRef` are read when the send resolves: if
 * the operator has since opened another ask, nothing moves and nothing is said there (SHOULD-2).
 * Otherwise Send & next goes on when an ask waits; else the notice is kept for the sent ask, and an
 * ask not named in the URL is named, so the list reload does not swap the card under it.
 */
export function postSendStep(o: { sentRef: string; text: string; next: boolean; routeAsk: string | undefined; shownRef: string | undefined; rows: readonly NextRow[] }): { go?: string; notice?: SentNotice; pin?: string } {
  const still = o.routeAsk ? o.routeAsk === o.sentRef : o.shownRef === o.sentRef;
  if (!still) return {};
  const r = o.next ? afterSendNext(true, o.rows, o.sentRef) : {};
  if (r.go) return { go: r.go };
  const text = [o.text, r.notice].filter(Boolean).join(" ");
  return { ...(text ? { notice: { ref: o.sentRef, text } } : {}), ...(o.routeAsk ? {} : { pin: o.sentRef }) };
}
