/**
 * IDE-334 (RAGPROOFS): keeping the index fresh without a timer.
 *
 * The operator ruled timers out, so a pass runs only when something asks for one:
 *   - on server start;
 *   - when /api/search finds the last full pass older than `staleMs` (ASK_SEARCH_STALE_MS, default five
 *     minutes). The search answers at once from the index as it is, and the pass runs behind it. A failed
 *     pass is not retried before another `staleMs` has gone by, so a down embedder is not hammered;
 *   - when an ask file changes (the server's existing watcher): an asks-only pass, debounced by
 *     `debounceMs` (ASK_SEARCH_DEBOUNCE_MS, default 2 s), so `ask new`, `answer`, `revise`, `withdraw` and
 *     a browser answer are searchable seconds later. That covers every writer, the CLI and the browser alike.
 *
 * ASK_SEARCH_AUTO=0 (the test config sets it) turns off the start pass and the ask-change pass in the
 * server, so a test's server never embeds through a real runner; the stale pass behind a search stays.
 *
 * One pass at a time: a request while a pass runs is folded into one more pass after it. Across processes
 * the index lock (indexer.ts) keeps a CLI `index` and the server from both writing; the loser skips.
 */
import type { EmbeddingClient } from "../../../embed-local/src/index.ts";
import { getMeta, type SearchDb } from "./db.ts";
import { indexSources, tryIndexLock, type IndexReport } from "./indexer.ts";
import type { Source } from "./sources.ts";

export type RefresherOptions = {
  db: SearchDb;
  dbFile: string;
  /** Every source, for a full pass. */
  sources: () => Source[];
  /** The asks source alone, for the pass an ask change triggers. */
  askSources: () => Source[];
  embedder: EmbeddingClient;
  staleMs?: number;
  debounceMs?: number;
  now?: () => number;
  log?: (line: string) => void;
};

export type RefresherState = {
  running: "full" | "asks" | null;
  indexedAt: string | null;
  lastAttemptAt: string | null;
  lastReport: IndexReport | null;
  skippedLocked: number;
};

export function createRefresher(o: RefresherOptions) {
  const staleMs = o.staleMs ?? Number(process.env.ASK_SEARCH_STALE_MS || 5 * 60_000);
  const debounceMs = o.debounceMs ?? Number(process.env.ASK_SEARCH_DEBOUNCE_MS || 2000);
  const now = o.now ?? Date.now;
  const log = o.log ?? (() => {});
  let running: Promise<void> | null = null;
  let runningKind: "full" | "asks" | null = null;
  let queued: "full" | "asks" | null = null;
  let lastAttempt = 0;
  let lastReport: IndexReport | null = null;
  let skippedLocked = 0;
  let debounce: NodeJS.Timeout | undefined;

  async function pass(kind: "full" | "asks") {
    const release = tryIndexLock(o.dbFile);
    if (!release) {
      skippedLocked++;
      log(`ask-search: ${kind} pass skipped, another indexer holds the lock`);
      return;
    }
    try {
      if (kind === "full") lastAttempt = now();
      const r = await indexSources(o.db, kind === "full" ? o.sources() : o.askSources(), o.embedder, kind === "asks" ? { stampKey: "last_asks_index_at" } : {});
      lastReport = r;
      log(`ask-search: ${kind} pass ${r.error ? `failed (${r.error})` : "done"}: +${r.added} ~${r.changed} -${r.deleted} =${r.unchanged} dup ${r.duplicates}, embedded ${r.embeddingsCreated}, pruned ${r.embeddingsPruned}, ${r.ms} ms`);
    } catch (e) {
      log(`ask-search: ${kind} pass threw: ${(e as Error).message}`);
    } finally {
      release();
    }
  }

  /** Start a pass now, or fold it into the one after the pass that is running. Resolves when it has run. */
  function run(kind: "full" | "asks"): Promise<void> {
    if (running) {
      if (queued !== "full") queued = kind;
      return running;
    }
    runningKind = kind;
    running = pass(kind).finally(() => {
      running = null;
      runningKind = null;
      const next = queued;
      queued = null;
      if (next) void run(next);
    });
    return running;
  }

  function indexedAt(): string | null {
    try {
      return getMeta(o.db, "last_index_at") ?? null;
    } catch {
      return null;
    }
  }

  return {
    /** The pass a server start runs. */
    start(): Promise<void> {
      return run("full");
    },
    /** Called by /api/search: start a full pass behind the answer when the index is stale. True when one started. */
    ensureFresh(): boolean {
      if (running) return false;
      const at = indexedAt();
      const age = at ? now() - Date.parse(at) : Infinity;
      if (age < staleMs) return false;
      if (now() - lastAttempt < staleMs) return false;
      void run("full");
      return true;
    },
    /** Called by the asks-root watcher: an asks-only pass, debounced. */
    asksChanged(): void {
      clearTimeout(debounce);
      debounce = setTimeout(() => void run("asks"), debounceMs);
      debounce.unref?.();
    },
    /** Resolves when no pass is running or queued (tests). */
    async idle(): Promise<void> {
      while (running) await running;
    },
    state(): RefresherState {
      return { running: runningKind, indexedAt: indexedAt(), lastAttemptAt: lastAttempt ? new Date(lastAttempt).toISOString() : null, lastReport, skippedLocked };
    },
  };
}

export type Refresher = ReturnType<typeof createRefresher>;
