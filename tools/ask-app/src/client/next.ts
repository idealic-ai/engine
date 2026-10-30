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
