/**
 * COMMSUI: the Comms tab, the communication log between seats. It reads TELL's GET /api/comms
 * (src/lib/comms.ts, CommsRow): one row per tell, broadcast or ask, newest first. Read-only.
 *
 * Each row shows from → to, the tier, the subject and when; a withdrawn message is struck through
 * with who withdrew it, when and why; an align tell links the managers' "these two are talking"
 * notice (and the notice links back); an ask links into the ask. Filters by seat and tier live in
 * the URL (route.ts). The feed reloads on the SSE `change` the other views reload on.
 *
 * A failure is never shown as an empty feed: an error with nothing read says the feed could not be
 * read, an error over rows read earlier says those rows are as last read, and an empty answer says
 * whether the feed or the filters are why. A state read for another query (the filter just changed)
 * shows as loading, never as this filter's rows or emptiness; a request that hangs ends as an error
 * after COMMS_TIMEOUT_MS. Of two loads in flight, only the newest is applied.
 */
import { Fragment, useCallback, useEffect, useReducer, useRef, useState } from "react";
import type { CommsRow, SeatState, Tier } from "../lib/comms.ts";
import { ageOf } from "./model.ts";
import { COMMS_KINDS, COMMS_TIERS, parseRoute, serializeRoute, type CommsKind, type Route } from "./route.ts";
import { scrollToId } from "./scroll.ts";
import { authedFetch, type Authed } from "./token.ts";

type Answer = Pick<Authed, "status" | "json" | "restarted">;
type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
/** How long a comms read may take before it is reported as not answered (MF-1). */
export const COMMS_TIMEOUT_MS = 15000;

/** `ids`, when given, asks for exactly those rows; the server then ignores every other filter. */
export type CommsFilter = { seat?: string; tier?: Tier[]; kind?: CommsKind[]; ids?: string[] };
/** What the tab knows: the query it last asked, its rows (undefined until one answer came), the error, when read. */
export type CommsState = { query: string; rows: CommsRow[] | undefined; error: string; at: string };

/** The request for a filter: `seat`, the tiers and kinds as comma lists, nothing when unfiltered; by id, only the ids. */
export function commsQuery(f: CommsFilter): string {
  const q = new URLSearchParams();
  if (f.ids?.length) {
    q.set("id", f.ids.join(","));
    return `/api/comms?${q.toString()}`;
  }
  if (f.seat) q.set("seat", f.seat);
  if (f.tier?.length) q.set("tier", f.tier.join(","));
  if (f.kind?.length) q.set("kind", f.kind.join(","));
  const s = q.toString();
  return `/api/comms${s ? `?${s}` : ""}`;
}

/**
 * One answer folded into the state. Only a 200 carrying a `rows` array is rows; anything else is an
 * error. On an error the rows read earlier for the same query are kept (with their own read time),
 * and rows read for another query are dropped rather than shown under the wrong filter.
 */
export function commsResult(query: string, r: Answer, at: string, prev?: CommsState): CommsState {
  if (r.status === 200 && Array.isArray(r.json?.rows)) return { query, rows: r.json.rows as CommsRow[], error: "", at };
  const error = r.restarted
    ? r.restarted === "updated"
      ? "the app was updated: reload to continue"
      : "the app restarted: reload to continue"
    : r.status === 200
      ? "the server's answer carried no rows list"
      : (r.json?.error as string | undefined) || `HTTP ${r.status}`;
  if (prev && prev.query === query && prev.rows) return { query, rows: prev.rows, error, at: prev.at };
  return { query, rows: undefined, error, at };
}

/** Every seat a row names, for the seat box's suggestions. */
export function seatsOf(rows: CommsRow[]): string[] {
  return rows.flatMap((r) => [r.from, r.sentBy, ...r.to, ...r.forSeats]).filter(Boolean);
}

/** One read of the feed, with the token, ended after `timeoutMs` so a hung request reports as an error (MF-1). */
export async function fetchComms(query: string, deps: { fetch?: Fetch; timeoutMs?: number } = {}): Promise<Answer> {
  const ms = deps.timeoutMs ?? COMMS_TIMEOUT_MS;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), ms);
  try {
    return await authedFetch(query, { signal: ctl.signal }, deps.fetch ? { fetch: deps.fetch } : {});
  } catch {
    return { status: 0, json: { error: ctl.signal.aborted ? `the app server did not answer within ${Math.round(ms / 1000) || ms / 1000}s` : "the app server did not answer" } };
  } finally {
    clearTimeout(timer);
  }
}

/** Loads in order of asking: an answer is applied only if no later load started (N-3), whatever its query. */
export function createCommsLoader(deps: { fetch: (query: string) => Promise<Answer>; apply: (query: string, r: Answer) => void }) {
  let seq = 0;
  return {
    async load(query: string): Promise<boolean> {
      const mine = ++seq;
      const r = await deps.fetch(query);
      if (mine !== seq) return false;
      deps.apply(query, r);
      return true;
    },
  };
}

/** Distinct keys for a list that may repeat a value (N-5): the second "a" is "a~1". */
export function uniqueKeys(xs: string[]): string[] {
  const seen = new Map<string, number>();
  return xs.map((x) => {
    const n = seen.get(x) ?? 0;
    seen.set(x, n + 1);
    return n ? `${x}~${n}` : x;
  });
}

const route = (r: Partial<Route>): Route => ({ section: "asks", filter: "open", group: "none", ...r });
/** A Comms row's in-app href, serialized like every other route (S-3). */
export function commHref(id: string): string {
  return serializeRoute(route({ section: "comms", comm: id }));
}
/**
 * An ask row's link (S-3): its `ref` must be an in-app ask path, `/a/<seat>/<id>` with no query,
 * fragment, scheme, host or space; it is parsed and serialized again. Anything else gets no link.
 */
export function askLink(r: CommsRow): { ask: string; href: string } | null {
  if (r.kind !== "ask" || !/^\/a\/[^/?#\s:][^/?#\s]*\/[^?#\s]+$/.test(r.ref)) return null;
  const parsed = parseRoute(r.ref);
  if (!parsed.ask) return null;
  return { ask: parsed.ask, href: serializeRoute(route({ ask: parsed.ask })) };
}

/**
 * The events the feed reloads on: `change` (an ask file moved) and `comms` (the server's word that a
 * tell, an ack or a withdrawal landed in the broadcast dir, TELL as landed). `hello` is the caller's.
 */
export function listenComms(es: Pick<EventTarget, "addEventListener">, bump: () => void) {
  es.addEventListener("change", () => bump());
  es.addEventListener("comms", () => bump());
}

/** The picked row is not among this query's rows, once those are read: the case for a lookup by id. */
export function commsMissing(state: CommsState | undefined, query: string, current: string | undefined): boolean {
  return !!current && !!state && state.query === query && !!state.rows && !state.rows.some((r) => r.id === current);
}

const STATE_LABEL: Record<string, string> = {
  withdrawn: "withdrawn",
  read: "read by every recipient",
  queued: "queued, not shown yet",
  delivered: "delivered",
  undelivered: "not delivered",
  "not-attempted": "not attempted",
};
const SEAT_LABEL: Record<SeatState, string> = { read: "read", queued: "queued", delivered: "delivered", undelivered: "not delivered", "not-attempted": "not attempted" };
/** A tell's or broadcast's state in words; an ask's own status as the ask store says it. */
export function stateLabel(r: Pick<CommsRow, "kind" | "state">): string {
  return r.kind === "ask" ? r.state : STATE_LABEL[r.state] ?? r.state;
}
export function seatStateLabel(s: SeatState): string {
  return SEAT_LABEL[s] ?? s;
}

/** Rows looked up by id (a notice or its tell the filter hides), reloaded on `tick`. Nothing asked: undefined. */
export type PinnedAction = { type: "query"; query: string } | { type: "answer"; query: string; r: Answer; at: string };
/**
 * The lookup's state (N-3): a change of lookup query (another id, or none while a filter loads)
 * starts fresh, so an answer from a superseded lookup is never shown again; an answer is taken only
 * for the current query, and a failed refresh keeps the earlier rows with their read time (commsResult).
 */
export function pinnedReducer(state: CommsState | undefined, a: PinnedAction): CommsState | undefined {
  if (a.type === "query") return state && state.query === a.query ? state : undefined;
  if (state && state.query !== a.query) return state;
  return commsResult(a.query, a.r, a.at, state);
}

export function usePinned(ids: string[], tick: number) {
  const query = ids.length ? commsQuery({ ids }) : "";
  const [state, dispatch] = useReducer(pinnedReducer, undefined);
  const current = useRef(query);
  current.current = query;
  const loader = useRef<ReturnType<typeof createCommsLoader>>();
  loader.current ??= createCommsLoader({ fetch: (q) => fetchComms(q), apply: (q, r) => q === current.current && dispatch({ type: "answer", query: q, r, at: new Date().toISOString() }) });
  useEffect(() => {
    dispatch({ type: "query", query });
    if (query) void loader.current!.load(query);
  }, [query, tick]);
  return query ? forQuery(state, query) ?? { query, rows: undefined, error: "", at: "" } : undefined;
}

export type ScrollMemo = { id?: string; done: boolean };
/**
 * When to scroll the feed to the picked card (S-3): once per pick, when its card is first present
 * (in the feed, or in the pinned lookup once that returns); never again on later reloads of the
 * same pick. Picking another row, or the same one again after another, scrolls anew.
 */
export function scrollStep(memo: ScrollMemo, current: string | undefined, present: boolean): { scroll: boolean; memo: ScrollMemo } {
  const m = current === memo.id ? memo : { id: current, done: false };
  if (!current || m.done || !present) return { scroll: false, memo: m };
  return { scroll: true, memo: { id: current, done: true } };
}

const SEAT_ORDER: SeatState[] = ["read", "delivered", "queued", "undelivered", "not-attempted"];
/** Per-seat counts when the recipients do not share one state ("2 read · 1 queued"); empty when they do (S-4). */
export function seatCounts(r: Pick<CommsRow, "seats">): string {
  const n = new Map<SeatState, number>();
  for (const s of r.seats) n.set(s.state, (n.get(s.state) ?? 0) + 1);
  if (n.size < 2) return "";
  return SEAT_ORDER.filter((k) => n.has(k)).map((k) => `${n.get(k)} ${seatStateLabel(k)}`).join(" · ");
}

/** The feed for a filter, loaded when the tab is shown and again each time `tick` moves (the SSE `change` or `comms`). */
export function useComms(enabled: boolean, filter: CommsFilter, tick: number) {
  const query = commsQuery(filter);
  const [state, setState] = useState<CommsState | undefined>();
  const [busy, setBusy] = useState(false);
  const [seats, setSeats] = useState<string[]>([]);
  const loader = useRef<ReturnType<typeof createCommsLoader>>();
  loader.current ??= createCommsLoader({
    fetch: (q) => fetchComms(q),
    apply: (q, r) => {
      setBusy(false);
      setState((prev) => commsResult(q, r, new Date().toISOString(), prev));
      if (r.status === 200 && Array.isArray(r.json?.rows)) setSeats((s) => [...new Set([...s, ...seatsOf(r.json.rows)])].sort());
    },
  });
  const load = useCallback(async () => {
    setBusy(true);
    await loader.current!.load(query);
  }, [query]);
  useEffect(() => {
    if (enabled) void load();
  }, [enabled, load, tick]);
  return { state, query, busy, seats, reload: load };
}

const isAsk = (r: CommsRow) => r.kind === "ask";
const timeOf = (iso: string, now: number) => (iso && Number.isFinite(Date.parse(iso)) ? `${ageOf(Date.parse(iso), now)} ago` : "no time");

/** The filters above the list: a seat box with the seats seen, the tiers as toggles, Refresh and when it was read. */
const TIER_HINT = "Asks ride no tier, so a tier filter leaves them out.";

export function CommsFilters({ seat, tier, kind, seats, onSeat, onTier, onKind, onReload, busy, at }: { seat?: string; tier?: Tier[]; kind?: CommsKind[]; seats: string[]; onSeat: (s?: string) => void; onTier: (t?: Tier[]) => void; onKind: (k?: CommsKind[]) => void; onReload: () => void; busy: boolean; at?: string }) {
  const kinds = new Set(kind ?? []);
  const toggleKind = (k: CommsKind) => {
    const next = COMMS_KINDS.filter((x) => (x === k ? !kinds.has(x) : kinds.has(x)));
    onKind(next.length ? next : undefined);
  };
  const [text, setText] = useState(seat ?? "");
  useEffect(() => setText(seat ?? ""), [seat]);
  const on = new Set(tier ?? []);
  const toggle = (t: Tier) => {
    const next = COMMS_TIERS.filter((x) => (x === t ? !on.has(x) : on.has(x)));
    onTier(next.length ? next : undefined);
  };
  return (
    <div className="side-tools comms-filters">
      <form
        className="comms-seat"
        role="search"
        aria-label="Filter by seat"
        onSubmit={(e) => {
          e.preventDefault();
          onSeat(text.trim() || undefined);
        }}
      >
        <input type="search" list="comms-seats" placeholder="Seat (from or to)" aria-label="Seat (from or to)" value={text} onChange={(e) => setText(e.target.value)} onBlur={() => (text.trim() || undefined) !== seat && onSeat(text.trim() || undefined)} />
        <datalist id="comms-seats">
          {seats.map((s) => (
            <option key={`seat-${s}`} value={s} />
          ))}
        </datalist>
        {seat && <button type="button" className="linkish" onClick={() => onSeat(undefined)}>Clear</button>}
      </form>
      <div className="seg comms-kinds" role="group" aria-label="Kind">
        <button className={`chip toggle${kinds.size ? "" : " on"}`} aria-pressed={!kinds.size} onClick={() => onKind(undefined)}>every kind</button>
        {COMMS_KINDS.map((k) => (
          <button key={k} className={`chip toggle${kinds.has(k) ? " on" : ""}`} aria-pressed={kinds.has(k)} onClick={() => toggleKind(k)}>{k}</button>
        ))}
      </div>
      <div className="seg comms-tiers" role="group" aria-label="Tier" title={TIER_HINT}>
        <button className={`chip toggle${on.size ? "" : " on"}`} aria-pressed={!on.size} onClick={() => onTier(undefined)}>every tier</button>
        {COMMS_TIERS.map((t) => (
          <button key={t} className={`chip toggle${on.has(t) ? " on" : ""}`} aria-pressed={on.has(t)} onClick={() => toggle(t)}>{t}</button>
        ))}
      </div>
      {on.size > 0 && <p className="muted comms-hint">{TIER_HINT}</p>}
      <div className="feed-tools">
        <span className="muted" title={at}>{at ? `read at ${new Date(at).toLocaleTimeString()}` : "not read yet"}</span>
        <button className="linkish" onClick={onReload} disabled={busy}>{busy ? "Refreshing…" : "Refresh"}</button>
      </div>
    </div>
  );
}

/** What the list says when it has no rows to show, or rows that may be stale. */
function Status({ state, filtered, pad }: { state?: CommsState; filtered: boolean; pad: string }) {
  if (!state) return <p className={`muted ${pad}`}>Loading messages…</p>;
  if (state.error && !state.rows) {
    return (
      <div className={`feed-status ${pad}`} role="alert">
        <b>The comms feed could not be read</b>
        <p>The app server said: <code>{state.error}</code></p>
        <p className="muted">This is not an empty feed. Refresh tries again.</p>
      </div>
    );
  }
  if (state.error) {
    return (
      <p className={`feed-error ${pad}`} role="alert" title={state.at}>
        {`The comms feed could not be read: ${state.error}. These are the messages as last read at ${new Date(state.at).toLocaleTimeString()}.`}
      </p>
    );
  }
  if (!state.rows?.length) return <p className={`muted ${pad}`}>{filtered ? "No messages match these filters." : "The feed answered with no messages."}</p>;
  return null;
}

/** The state to show for `query`: none (loading) when it was read for another query (MF-1). */
const forQuery = (state: CommsState | undefined, query: string) => (state && state.query === query ? state : undefined);

/** The sidebar list: one line per message; a pick scrolls the feed to it. Its error line is not an alert: the feed's is (N-4). */
export function CommsRows({ state: anyState, query, filtered, current, onPick, slim, now = Date.now() }: { state?: CommsState; query: string; filtered: boolean; current?: string; onPick: (id: string) => void; slim: boolean; now?: number }) {
  const state = forQuery(anyState, query);
  const rows = state?.rows ?? [];
  const keys = uniqueKeys(rows.map((r) => r.id));
  return (
    <>
      {!state ? (
        <p className="muted pad">Loading messages…</p>
      ) : state.error ? (
        <p className="feed-error pad">{state.rows ? "Comms could not be read; showing the last read. See the feed." : "The comms feed could not be read. See the feed."}</p>
      ) : !rows.length ? (
        <p className="muted pad">{filtered ? "No messages match these filters." : "No messages."}</p>
      ) : null}
      <ul className="rows">
        {rows.map((r, i) => (
          <li key={keys[i]}>
            <button className={`row comm-row${r.withdrawn ? " withdrawn" : ""}`} aria-current={r.id === current} onClick={() => onPick(r.id)} title={r.subject}>
              <span className="row-top"><span className="row-title">{r.withdrawn ? <s>{r.subject || r.id}</s> : r.subject || r.id}</span></span>
              <span className="row-meta">
                {!slim && <span className="seat">{`${r.from} → ${r.to.join(", ") || "nobody"}`}</span>}
                {r.tier ? <span className={`tier tier-${r.tier}`}>{r.tier}</span> : <span className="kind">{r.kind}</span>}
                <span className="age" title={r.at}>{timeOf(r.at, now)}</span>
              </span>
            </button>
          </li>
        ))}
      </ul>
    </>
  );
}

/** A seat name that, clicked, filters the feed to it. */
function SeatPick({ seat, onSeat }: { seat: string; onSeat: (s: string) => void }) {
  return <button type="button" className="linkish seat-pick" title={`Show only ${seat}'s messages`} onClick={() => onSeat(seat)}>{seat}</button>;
}

/** An in-app link: a real href (so it opens in a new tab), with a click handled in place. */
function Go({ href, onGo, children }: { href: string; onGo: () => void; children: React.ReactNode }) {
  return (
    <a
      href={href}
      onClick={(e) => {
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
        e.preventDefault();
        onGo();
      }}
    >
      {children}
    </a>
  );
}

/** "Open the ask", only for a ref that parses as an in-app ask path (S-3). */
function AskGo({ r, onOpenAsk }: { r: CommsRow; onOpenAsk: (ref: string) => void }) {
  const link = askLink(r);
  if (!link) return <span>the ask has no readable link</span>;
  return <span><Go href={link.href} onGo={() => onOpenAsk(link.ask)}>Open the ask</Go></span>;
}

type CardProps = { r: CommsRow; current?: string; now: number; onComm: (id: string) => void; onOpenAsk: (ref: string) => void; onSeat: (seat: string) => void };

/** One message as a card. */
function Card({ r, current, now, onComm, onOpenAsk, onSeat }: CardProps) {
  // S-4: an aggregate state over recipients in different states says "mixed" and shows the counts.
  const mixed = r.kind !== "ask" && !r.withdrawn ? seatCounts(r) : "";
  return (
    <article id={`cm-${r.id}`} className={`fork comm${r.withdrawn ? " withdrawn" : ""}${r.id === current ? " current" : ""}`}>
      <div className="fork-head">
        <span className="eyebrow">
          <SeatPick seat={r.from} onSeat={onSeat} /> → {r.to.length ? uniqueKeys(r.to).map((k, j) => (
            <Fragment key={k}>{j > 0 && ", "}<SeatPick seat={r.to[j]} onSeat={onSeat} /></Fragment>
          )) : <span className="muted">nobody</span>}
        </span>
        <span className="fork-aff">
          {r.tier && <span className={`chip tier tier-${r.tier}`}>{r.tier}</span>}
          <span className="chip quiet">{r.kind}</span>
          <span className="chip quiet" title={r.seats.map((s) => `${s.seat}: ${seatStateLabel(s.state)}`).join("\n") || undefined}>{mixed ? "mixed" : stateLabel(r)}</span>
          {mixed && <span className="comm-counts">{mixed}</span>}
          <span className="age" title={r.at}>{timeOf(r.at, now)}</span>
        </span>
      </div>
      <p className="comm-subject">{r.withdrawn ? <s>{r.subject || r.id}</s> : r.subject || <span className="muted">{r.id}</span>}</p>
      {r.withdrawn && (
        <p className="comm-withdrawn">
          Withdrawn by <b>{r.withdrawn.by || "someone unrecorded"}</b> <span title={r.withdrawn.at ?? undefined}>{r.withdrawn.at ? timeOf(r.withdrawn.at, now) : "at an unrecorded time"}</span>{`: ${r.withdrawn.reason || "no reason recorded"}`}
        </p>
      )}
      {(r.sentBy && r.sentBy !== r.from) || r.forSeats.length || r.notice || r.noticeOf || isAsk(r) ? (
        <p className="comm-links muted">
          {r.sentBy && r.sentBy !== r.from && <span>{`sent by ${r.sentBy}`}</span>}
          {r.forSeats.length > 0 && <span>{`meant for ${r.forSeats.join(", ")}`}</span>}
          {r.notice && <span><Go href={commHref(r.notice)} onGo={() => onComm(r.notice!)}>the managers&apos; notice</Go></span>}
          {r.noticeOf && <span>about <Go href={commHref(r.noticeOf)} onGo={() => onComm(r.noticeOf!)}>{r.noticeOf}</Go></span>}
          {isAsk(r) && <AskGo r={r} onOpenAsk={onOpenAsk} />}
        </p>
      ) : null}
    </article>
  );
}

/**
 * The picked message when this filter hides it: looked up by id (the server ignores the filters for
 * `id=`) and shown under the feed as outside these filters. A lookup that fails says so; only an
 * answer with no rows says the message does not exist.
 */
/** The rows of a lookup that are the picked id (N-2): a lookup for "a,b" shows neither as the pick. */
const pinnedOf = (pinned: CommsState | undefined, id: string | undefined) => (id && pinned?.rows ? pinned.rows.filter((r) => r.id === id) : []);

function Pinned({ id, pinned, filtered, ...card }: { id: string; pinned?: CommsState; filtered: boolean } & Omit<CardProps, "r" | "current">) {
  // S-2: unfiltered, a message the page does not carry is older than the newest the feed returns.
  const why = filtered ? "which these filters hide" : "older than this page";
  const title = filtered ? "Outside these filters" : "Older than this page";
  if (!pinned || (!pinned.rows && !pinned.error)) return <p className="muted notice" role="status">{`Looking up “${id}”, ${why}…`}</p>;
  const rows = pinnedOf(pinned, id);
  // S-1: a failed lookup says so first; earlier rows stay only as last read, and an earlier empty answer is not "none".
  if (pinned.error && !rows.length) return <p className="chip warn notice" role="status">{`“${id}” could not be looked up: ${pinned.error}`}</p>;
  if (!rows.length) return <p className="chip warn notice" role="status">{`No message “${id}” exists.`}</p>;
  const keys = uniqueKeys(rows.map((r) => r.id));
  return (
    <section className="comms-pinned" aria-label={title}>
      <h3 className="group-name">{title}</h3>
      {pinned.error && <p className="chip warn notice" role="status" title={pinned.at}>{`“${id}” could not be looked up again: ${pinned.error}. Shown as last read ${new Date(pinned.at).toLocaleTimeString()}.`}</p>}
      {rows.map((r, i) => <Card key={keys[i]} r={r} current={id} {...card} />)}
    </section>
  );
}

/** The feed in full: each message as a card, newest first. */
export function CommsFeed({ state: anyState, query, current, filtered = false, pinned, onComm, onOpenAsk, onSeat, now = Date.now() }: { state?: CommsState; query: string; current?: string; filtered?: boolean; pinned?: CommsState; onComm: (id: string) => void; onOpenAsk: (ref: string) => void; onSeat: (seat: string) => void; now?: number }) {
  const state = forQuery(anyState, query);
  const rows = state?.rows ?? [];
  const keys = uniqueKeys(rows.map((r) => r.id));
  const withdrawn = rows.filter((r) => r.withdrawn).length;
  const missing = commsMissing(state, query, current);
  const pinnedRows = missing ? pinnedOf(pinned, current) : [];
  // S-3: scroll once per pick, when its card first appears (here or in the lookup), not on every reload.
  const scrolled = useRef<ScrollMemo>({ done: false });
  useEffect(() => {
    const present = !!current && (rows.some((r) => r.id === current) || pinnedRows.length > 0);
    const step = scrollStep(scrolled.current, current, present);
    scrolled.current = step.memo;
    if (step.scroll) scrollToId(`cm-${current}`);
  }, [current, state?.rows, pinnedRows]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <section className="feed" aria-label="Comms">
      <h2 className="feed-title">Comms {state?.rows && <span className="n">{`${rows.length}${withdrawn ? `, ${withdrawn} withdrawn` : ""}`}</span>}</h2>
      <Status state={state} filtered={filtered} pad="" />
      {rows.map((r, i) => (
        <Card key={keys[i]} r={r} current={current} now={now} onComm={onComm} onOpenAsk={onOpenAsk} onSeat={onSeat} />
      ))}
      {missing && <Pinned id={current!} pinned={pinned} filtered={filtered} now={now} onComm={onComm} onOpenAsk={onOpenAsk} onSeat={onSeat} />}
    </section>
  );
}
