/**
 * RAGSEARCH-UI: the sidebar's search bar also asks the server's semantic search (GET /api/search,
 * IDE-334; the contract is at the top of src/server.ts) once the typing pauses. The text filter
 * (search.ts) keeps narrowing the list at every keystroke; this adds one results panel that merges
 * both: asks first (meaning hits in the server's order, then word-only matches), then proof pages and
 * broadcasts.
 *
 * When the server cannot answer (a 503 with its `reason`, a request that fails, a body that is not a
 * list), the answer is a refusal naming why, and the panel shows only that note: the text filter is
 * what the sidebar falls back to. A refusal is never turned into an empty list.
 *
 * Everything here is a plain function or a small controller over injected fetch and timers, so it is
 * tested without a DOM (ragsearch-ui.test.ts).
 */
import type { SearchHit, UnavailableReason } from "../search/query.ts";
import { ageOf, type Row } from "./model.ts";
import { parseRoute, type Route } from "./route.ts";
import type { Hay } from "./search.ts";
import { authedFetch } from "./token.ts";

type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

/** The pause after the last keystroke before the server is asked (the URL write waits 300ms). */
export const SEMANTIC_DEBOUNCE_MS = 350;
/** Hits asked for. */
export const SEMANTIC_LIMIT = 20;
/** A query shorter than this (trimmed) is not worth an embedding; the text filter alone answers it. */
export const SEMANTIC_MIN_CHARS = 2;
/**
 * SEARCHFIX: the floor the sidebar asks for. The server's default (0.40, query.ts) hides relevant asks
 * on short queries. Sent as written.
 */
export const SEMANTIC_MIN_SCORE = "0.30";
/** Word-only asks listed in the panel; the rest stay in the list below it. */
export const WORD_CAP = 10;

/** SEARCHFIX: the 503 reasons the server sends, cause before symptom; `index-missing` is no longer one. */
const SERVER_REASONS: readonly UnavailableReason[] = ["index-error", "embedder-unavailable", "index-empty"];
/** A 503's `code` is shown in the note, so only a short plain token is kept. */
const CODE_RE = /^[\w.:-]{1,40}$/;

/**
 * Why there is no answer: one of the server's 503 reasons, or a client-side one —
 * `request-failed` (no response), `token-rejected` (the token is refused and none fresher could be had),
 * `app-updated` (the server now runs another build), `bad-response` (a 200 that is not a list of hits),
 * `unavailable` (a 503 naming no known reason), `http-<status>`.
 */
export type Unavailable = UnavailableReason | "request-failed" | "token-rejected" | "app-updated" | "bad-response" | "unavailable" | `http-${number}`;

export type SemanticAnswer =
  // SEARCHFIX: `minScore` is the floor the server applied (x-search-min-score), when it says.
  | { ok: true; q: string; hits: SearchHit[]; indexedAt: string | null; refreshing: boolean; minScore?: string }
  // SEARCHFIX: a 503 says whether a pass is building the index (`indexing`) and may name a `code`.
  | { ok: false; q: string; reason: Unavailable; code?: string; indexing?: boolean };

export type SemanticState = { phase: "idle" } | { phase: "waiting"; q: string } | { phase: "done"; answer: SemanticAnswer };

/** One GET /api/search with the page token (refreshed and retried once on a rejection, token.ts). */
/** A hit as far as the panel relies on it: an object with a string kind and id (S2: anything else is a bad response). */
const isHit = (h: unknown): h is SearchHit => !!h && typeof h === "object" && typeof (h as SearchHit).kind === "string" && typeof (h as SearchHit).id === "string";

export async function fetchSemantic(q: string, deps: { fetch?: Fetch; limit?: number; signal?: AbortSignal } = {}): Promise<SemanticAnswer> {
  const url = `/api/search?${new URLSearchParams({ q, limit: String(deps.limit ?? SEMANTIC_LIMIT), minScore: SEMANTIC_MIN_SCORE })}`;
  let r: Awaited<ReturnType<typeof authedFetch>>;
  try {
    r = await authedFetch(url, { cache: "no-store", ...(deps.signal ? { signal: deps.signal } : {}) }, { fetch: deps.fetch, withHeaders: true });
  } catch {
    return { ok: false, q, reason: "request-failed" };
  }
  if (r.restarted) return { ok: false, q, reason: r.restarted === "updated" ? "app-updated" : "token-rejected" };
  if (r.status === 503) {
    const reason = r.json?.reason;
    if (!SERVER_REASONS.includes(reason)) return { ok: false, q, reason: "unavailable" };
    const code = r.json?.code;
    return {
      ok: false,
      q,
      reason,
      ...(typeof code === "string" && CODE_RE.test(code) ? { code } : {}),
      ...(typeof r.json?.indexing === "boolean" ? { indexing: r.json.indexing } : {}),
    };
  }
  if (r.status !== 200) return { ok: false, q, reason: `http-${r.status}` };
  if (!Array.isArray(r.json) || !r.json.every(isHit)) return { ok: false, q, reason: "bad-response" };
  const indexedAt = r.headers?.get("x-search-indexed-at") || null;
  const minScore = r.headers?.get("x-search-min-score")?.trim();
  return { ok: true, q, hits: r.json as SearchHit[], indexedAt, refreshing: r.headers?.get("x-search-refreshing") === "1", ...(minScore ? { minScore } : {}) };
}

/** The note the sidebar shows in place of results. */
export function unavailableNote(reason: string, o: { code?: string; indexing?: boolean } = {}): string {
  // SEARCHFIX: an empty index while a pass runs is not broken, only not built yet.
  if (reason === "index-empty" && o.indexing) return "search index is being built";
  const why = o.code ? `${reason} (${o.code})` : reason;
  return `semantic search unavailable: ${why}${reason === "token-rejected" || reason === "app-updated" ? " (reload the app)" : ""}`;
}

/** The text the asks view searches by meaning; the other views search nothing (the box lives in the asks view). */
export const semanticQueryFor = (view: string, q: string | undefined): string => (view === "asks" ? q ?? "" : "");

/** "indexed 5m ago", from x-search-indexed-at; "not indexed yet" when it is absent (before the first pass), empty or unreadable. */
export function indexAgeText(indexedAt: string | null, now: number): string {
  const t = indexedAt ? Date.parse(indexedAt) : NaN;
  return Number.isFinite(t) ? `indexed ${ageOf(t, now)} ago` : "not indexed yet";
}

export type Timers = { set(fn: () => void, ms: number): unknown; clear(handle: unknown): void };

/**
 * Debounced: `query` restarts the wait; only the latest query's answer is ever reported, so a slow
 * answer to an earlier text cannot replace a later one. A run that throws is a `request-failed` refusal.
 * A new query (or dispose) aborts the request still in flight, so the server stops embedding for it.
 */
export function createSemanticSearch(o: { run: (q: string, signal: AbortSignal) => Promise<SemanticAnswer>; timers: Timers; onState: (s: SemanticState) => void; delay?: number }) {
  let pending: unknown;
  let gen = 0;
  let inflight: AbortController | undefined;
  const clear = () => {
    if (pending !== undefined) o.timers.clear(pending);
    pending = undefined;
    inflight?.abort();
    inflight = undefined;
  };
  return {
    query(raw: string) {
      clear();
      const mine = ++gen;
      const q = raw.trim();
      if (q.length < SEMANTIC_MIN_CHARS) return o.onState({ phase: "idle" });
      o.onState({ phase: "waiting", q });
      pending = o.timers.set(() => {
        pending = undefined;
        const c = new AbortController();
        inflight = c;
        o.run(q, c.signal).then(
          (answer) => mine === gen && o.onState({ phase: "done", answer }),
          () => mine === gen && o.onState({ phase: "done", answer: { ok: false, q, reason: "request-failed" } }),
        );
      }, o.delay ?? SEMANTIC_DEBOUNCE_MS);
    },
    dispose() {
      clear();
      gen++;
    },
  };
}

export type Match = "word" | "meaning" | "both";
export type ResultItem = {
  /** `seat/id` for an ask (its ref), `<kind>:<id>` otherwise. */
  key: string;
  kind: SearchHit["kind"];
  title: string;
  seat: string;
  status: string;
  match: Match;
  /** The server's excerpt and the fork or section it came from (a meaning hit). */
  excerpt?: string;
  section?: string;
  /** The field a word-only ask matched in, outside its title and seat (search.ts). */
  extra?: Hay;
  url?: string | null;
  appPath?: string | null;
};

/**
 * One list: meaning hits on asks in the server's order (marked `both` when the text filter also kept
 * the ask), then word-only asks (at most WORD_CAP; `moreWords` counts the rest), then proof pages and
 * broadcasts in the server's order.
 */
export function mergeResults(words: (Row & { extra?: Hay })[], hits: SearchHit[]): { items: ResultItem[]; moreWords: number } {
  const wordBy = new Map(words.map((r) => [r.ref, r]));
  const seen = new Set<string>();
  const asks: ResultItem[] = [];
  hits = hits.filter(isHit);
  for (const h of hits) {
    if (h.kind !== "ask") continue;
    const key = `${h.seat}/${h.id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const w = wordBy.get(key);
    asks.push({ key, kind: "ask", title: w?.title ?? h.title, seat: h.seat, status: h.status, match: w ? "both" : "meaning", excerpt: h.excerpt, section: h.section });
  }
  const wordOnly = words.filter((r) => !seen.has(r.ref));
  for (const r of wordOnly.slice(0, WORD_CAP)) asks.push({ key: r.ref, kind: "ask", title: r.title, seat: r.seat, status: r.status, match: "word", ...(r.extra ? { extra: r.extra } : {}) });
  const rest: ResultItem[] = hits
    .filter((h) => h.kind !== "ask")
    .map((h) => ({ key: `${h.kind}:${h.id}`, kind: h.kind, title: h.title, seat: h.seat, status: h.status, match: "meaning", excerpt: h.excerpt, section: h.section, url: h.url, appPath: h.appPath }));
  return { items: [...asks, ...rest], moreWords: Math.max(0, wordOnly.length - WORD_CAP) };
}

/** Where a result opens: an ask by its ref, else the in-app path, else the page's web address, else nowhere. */
export function openTarget(i: ResultItem): { ask: string } | { app: string } | { url: string } | null {
  if (i.kind === "ask") return { ask: i.key };
  if (i.appPath) return { app: i.appPath };
  // A hit's url is indexed data and goes to window.open: only a web address may.
  if (i.url && /^https?:\/\//i.test(i.url)) return { url: i.url };
  return null;
}

/**
 * The route fields for an in-app path. Outside the asks the ask on screen is kept beside the list and
 * ?q= is dropped, as switching section does (NIT-1); Back returns to the search.
 */
export function resultRoute(appPath: string, currentAsk: string | undefined): Partial<Route> {
  const r = parseRoute(appPath);
  if (r.section === "asks") return { section: "asks", ask: r.ask, fork: undefined, pane: undefined };
  return { section: r.section, ask: currentAsk, proof: r.proof, broadcast: r.broadcast, pane: undefined, fork: undefined, q: undefined };
}

/** What a key in the search box does to the results; null leaves the key to the box. */
export function searchKeyAction(key: string, selected: number, items: ResultItem[]): { type: "move"; to: number } | { type: "open"; item: ResultItem } | null {
  if (key === "ArrowDown" || key === "ArrowUp") return items.length ? { type: "move", to: stepSelection(selected, key, items.length) } : null;
  if (key === "Enter" && items[selected]) return { type: "open", item: items[selected] };
  return null;
}

/** The excerpt without the section's own text at its start (the panel shows the section beside it). */
export function excerptAfterSection(section: string | undefined, excerpt: string): string {
  if (!section || !excerpt.startsWith(section)) return excerpt;
  const rest = excerpt.slice(section.length);
  return rest === "" || /^\s/.test(rest) ? rest.trimStart() : excerpt;
}

/** ArrowDown/ArrowUp over `n` results; -1 is "none selected" (focus stays in the box). */
export function stepSelection(cur: number, key: string, n: number): number {
  if (n <= 0) return -1;
  const c = Math.min(cur, n - 1);
  if (key === "ArrowDown") return Math.min(n - 1, c + 1);
  if (key === "ArrowUp") return Math.max(-1, c - 1);
  return c;
}
