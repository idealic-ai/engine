/**
 * ASKSEARCH SHOULD-1 (IDE-304): the URL is written outside React's state updater, a search keystroke's
 * write is debounced, and a write that throws is dropped. WebKit throws a SecurityError past its
 * pushState/replaceState rate limit; uncaught inside an updater, with no error boundary, that would
 * unmount the app. The state itself never waits on the URL.
 */

export type HistoryLike = { pushState(data: unknown, unused: string, url: string): void; replaceState(data: unknown, unused: string, url: string): void };
export type Timers = { set(fn: () => void, ms: number): unknown; clear(handle: unknown): void };

export const URL_DEBOUNCE_MS = 300;

export function createUrlSync(history: HistoryLike, timers: Timers, delay = URL_DEBOUNCE_MS) {
  let pending: unknown;
  let pendingUrl: string | undefined;
  const write = (url: string, push: boolean) => {
    try {
      if (push) history.pushState(null, "", url);
      else history.replaceState(null, "", url);
    } catch {
      // Rate-limited (WebKit) or refused: the screen is already right; the next write catches the URL up.
    }
  };
  const cancel = () => {
    if (pending !== undefined) timers.clear(pending);
    pending = undefined;
    pendingUrl = undefined;
  };
  return {
    /** Write now (a pick, a filter, Back-worthy moves); any debounced write is superseded by it. */
    now(url: string, push: boolean) {
      cancel();
      write(url, push);
    },
    /** Replace the entry once typing pauses; a later call restarts the wait with its own URL. */
    later(url: string) {
      if (pending !== undefined) timers.clear(pending);
      pendingUrl = url;
      pending = timers.set(() => {
        const u = pendingUrl!;
        pending = undefined;
        pendingUrl = undefined;
        write(u, false);
      }, delay);
    },
    /** Drop a pending write (Back or Forward already set the URL). */
    cancel,
    /** Write a pending URL immediately (before a push, so the replaced entry holds the latest query). */
    flush() {
      const u = pendingUrl;
      cancel();
      if (u !== undefined) write(u, false);
    },
  };
}
