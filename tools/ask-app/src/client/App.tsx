import { Fragment, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, type Ref } from "react";
import {
  answeredByText,
  cardFor,
  draftAuthor,
  isOperatorName,
  questionKey,
  relayerOf,
  ticketKeys,
  visibleAsks,
  dependsOnDeclined,
  visibleQuestions,
  type AskAnswer,
  type AnswerValue,
  type AskOption,
  type AskQuestion,
  type Card,
  type ParsedAsk,
  type PanelRead,
  type FollowupKind,
} from "../lib/format.ts";
import {
  acceptAll,
  ageOf,
  answerInWords,
  answererText,
  grantClassOf,
  earlierAnswers,
  acceptListed,
  suggestionList,
  batchConfirmation,
  ruledBelow,
  restoreUnsent,
  sendConfirmation,
  unansweredForks,
  visibleSuggestionsFor,
  type Unsent,
  askRef,
  askRow,
  buildAnswers,
  clickPicks,
  forkLabel,
  groupRows,
  isSettled,
  leanCodeFor,
  leanFor,
  leanReason,
  nextFork,
  parseHash,
  resolveFork,
  saysMore,
  sortRows,
  suggestionsFor,
  tradeoff,
  type Filter,
  DIM_LABEL,
  type Dim,
  type GroupBy,
  type Row,
  type StoredAsk,
  type Values,
} from "./model.ts";
import { briefFor, isLocalOnly, paneTrust, proofLinks, proofOriginsFromEnv, type Brief, type Trust } from "./related.ts";
import { Inline, PaneContext, Rich, TicketLink, inlineTokens } from "./rich.tsx";
import { CodeBlock } from "./highlight.tsx";
import { batchOutcome, noticeFor, postSendStep, sendOutcome, type SentNotice } from "./next.ts";
import { createRouteNav, createUrlSync } from "./urlsync.ts";
import { blocks, displayTitle } from "./md.ts";
import { RELOAD_RESTARTED, RELOAD_UPDATED, authedFetch, recordBuild, refreshToken, type Authed } from "./token.ts";
import { barStep, cardUnsent, clearUnsent, copyText, forgetWords, keptDraftLines, keptSentence, loadUnsent, saveUnsent, type BarEvent, type BarState } from "./unsent.ts";
import { SCROLL_ROOT, scrollRootOf, scrollToId, scrollWithin } from "./scroll.ts";
import { Grip, Split, SIDE_MAX, SIDE_MIN, SIDE_SLIM, clampRatio, clampSide, sideDefault, useStoredNumber } from "./layout.tsx";
import { pushEsc } from "./esc.ts";
import { applyConflict, conflictStep, hopWords, pathOf, supersededInfo, supersedesList, withdrawnInfo, withdrawnWords, type PathHop, type Withdrawn } from "./supersede.ts";
import { DRAFT_NOTE, REQUEST_KINDS, clickPlan, composeNote, stripLoopLines, type SendKind, dialogueOf, earlierRounds, isProvisional, priorPicks, provisionalAnswers, requestLine, sendProvisional, type RoundView } from "./loop.ts";
import { isNavigation, parseRoute, serializeRoute, type Route } from "./route.ts";
import { highlight, isTypingTarget, searchTerms, sidebarView, snippet, type Hay } from "./search.ts";
import { FOLLOWUP_KIND_OPTIONS, FOLLOWUP_PENDING, adoptAfterFollowup, followupBody, followupConflict, followupLine, followupOutcome, followupResultFor, followupsOf, forkOnOpen, isAddressed, keepsOver, mayFollowUp, rememberFollowupResult, subscribeFollowupResults } from "./followup.ts";
import { CHANGE_WORDING, OVERRULE_WORDING, cancelDiscards, changeAnswerStart, changeMode, draftBody, mayChangeAnswer, overruleBody, overruleOutcome, planClick, requestSend, sendRoute, staleChangeKeys, unsentKey, withoutGrant, type CardAction } from "./reanswer.ts";
import { BroadcastFeed, BroadcastRows, ProofRows, ProofStatus, useBroadcasts, useProofs } from "./feeds.tsx";

export { ticketKeys };
type Pane = { url: string; label: string; source: Brief["source"] | "link"; trust: Trust };
type Theme = "auto" | "light" | "dark";
type View = "asks" | "proofs" | "broadcasts";
const FILTERS: Filter[] = ["open", "ruled", "settled", "all"];
const FILTER_LABEL: Record<Filter, string> = { open: "Open", ruled: "Ruled below you", settled: "Settled", all: "All" };

const valueOf = (o: AskOption) => o.code ?? o.label;
/** Proof hosts besides loopback :9440, set at build time (VITE_PROOF_ORIGINS); :9440 needs no entry. */
const PROOF_ORIGINS = proofOriginsFromEnv((import.meta as unknown as { env?: Record<string, string> }).env?.VITE_PROOF_ORIGINS);
const store = {
  get(k: string): string | null {
    try {
      return localStorage.getItem(k);
    } catch {
      return null;
    }
  },
  set(k: string, v: string | null) {
    try {
      if (v === null) localStorage.removeItem(k);
      else localStorage.setItem(k, v);
    } catch {
      /* private window: the choice lasts until reload */
    }
  },
};

/** A write with the token; a token rejected after a server restart is refreshed and retried once (token.ts). */
async function post(url: string, body: unknown, beforeRetry?: () => void): Promise<Authed> {
  return authedFetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(withoutGrant(body)) }, { beforeRetry });
}

function useMedia(q: string): boolean {
  const [on, setOn] = useState(() => typeof matchMedia !== "undefined" && matchMedia(q).matches);
  useEffect(() => {
    const m = matchMedia(q);
    const f = () => setOn(m.matches);
    f();
    m.addEventListener("change", f);
    return () => m.removeEventListener("change", f);
  }, [q]);
  return on;
}

const paneFor = (url: string, label: string, source: Pane["source"]): Pane => ({ url, label, source, trust: paneTrust(url, location.origin, PROOF_ORIGINS) });

export function App() {
  const [root, setRoot] = useState("");
  const [asks, setAsks] = useState<StoredAsk[]>([]);
  const [route, setRoute] = useState<Route>(() => parseRoute(location.pathname, location.search, location.hash));
  const [live, setLive] = useState(false);
  const [batchResult, setBatchResult] = useState("");
  const [sending, setSending] = useState(false);
  const [batchConfirm, setBatchConfirm] = useState<string | undefined>();
  const [appNotice, setAppNotice] = useState("");
  // The drafts tray can be tucked away; the sidebar then shows "✎ N drafts" to bring it back. An old
  // ?filter=drafts link (now ?drafts=1) always shows it.
  const [trayHidden, setTrayHidden] = useState(() => !route.drafts && store.get("askclient.trayHidden") === "1");
  const hideTray = () => {
    setTrayHidden(true);
    store.set("askclient.trayHidden", "1");
    if (route.drafts) navigate({ drafts: undefined }, false);
  };
  const showTray = () => {
    setTrayHidden(false);
    store.set("askclient.trayHidden", null);
  };
  const [theme, setTheme] = useState<Theme>(() => (store.get("askclient.theme") as Theme) || "auto");
  const [dragging, setDragging] = useState(false);
  const { section: view, filter, group: groupBy } = route;
  const bcast = route.broadcast;
  const proofs = useProofs(view === "proofs");
  const broadcasts = useBroadcasts(view === "broadcasts");
  const portrait = useMedia("(orientation: portrait)");
  const [sideW, setSideW] = useStoredNumber("askclient.sideW", () => sideDefault(typeof innerWidth === "number" ? innerWidth : 1440), clampSide);
  const [ratioX, setRatioX] = useStoredNumber("askclient.splitX", () => 0.5, clampRatio);
  const [ratioY, setRatioY] = useStoredNumber("askclient.splitY", () => 0.55, clampRatio);
  const desk = useRef<HTMLDivElement>(null);
  const detail = useRef<HTMLElement>(null);

  const load = useCallback(async () => {
    const r = await fetch("/api/asks");
    const j = await r.json();
    setRoot(j.root);
    setAsks(j.asks);
  }, []);

  useEffect(() => {
    load();
    void recordBuild();
    // SF-3: a server that keeps `provisional` will say so in /api/health; until then the flag is absent.
    fetch("/api/health").then((r) => r.json()).then((h) => h?.provisional === true && noteServerKeepsProvisional(true)).catch(() => undefined);
    const es = new EventSource("/api/events");
    let hellos = 0;
    // A second hello is a reconnect: the server may have restarted with a new token, so re-read it now,
    // before the operator's next write, and reload the asks.
    es.addEventListener("hello", () => {
      setLive(true);
      if (hellos++ === 0) return;
      void refreshToken().then((r) => setAppNotice(!r.ok && r.updated ? RELOAD_UPDATED : ""));
      load();
    });
    es.addEventListener("change", () => load());
    es.onerror = () => setLive(false);
    return () => es.close();
  }, [load]);

  // Back and Forward restore the screen from the URL; a legacy #seat/id link is rewritten in place.
  // SHOULD-1 (ASKSEARCH): the URL is written outside the state updater, through a writer that
  // debounces a keystroke's write and drops a write the browser throws on (WebKit's rate limit).
  const urlSync = useMemo(
    () => createUrlSync({ pushState: (d, u, url) => history.pushState(d, u, url), replaceState: (d, u, url) => history.replaceState(d, u, url) }, { set: (fn, ms) => setTimeout(fn, ms), clear: (h) => clearTimeout(h as ReturnType<typeof setTimeout>) }),
    [],
  );
  // The flush-before-push and cancel-on-Back rules live in createRouteNav (tested in search-review.test.ts).
  const nav = useMemo(() => createRouteNav(urlSync, route, { serialize: serializeRoute, isNavigation, onChange: setRoute }), []); // eslint-disable-line react-hooks/exhaustive-deps
  const routeNow = useMemo(() => ({ get current() { return nav.get(); } }), [nav]);
  useEffect(() => {
    const pop = () => nav.pop(parseRoute(location.pathname, location.search, location.hash));
    addEventListener("popstate", pop);
    const canonical = serializeRoute(route);
    if (canonical !== location.pathname + location.search + location.hash) urlSync.now(canonical, false);
    return () => {
      removeEventListener("popstate", pop);
      urlSync.flush();
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  /**
   * Move to a new state: pushed when Back should undo it (or when asked), replaced otherwise. The
   * state changes at once; with `typing` the URL write waits for a pause in the keystrokes.
   */
  const navigate = useCallback((patch: Partial<Route>, push?: boolean, typing = false) => nav.navigate(patch, push, typing), [nav]);
  const setFilter = (f: Filter) => navigate({ filter: f });
  const setGroupBy = (g: GroupBy) => navigate({ group: g });
  // IDE-304: the search text lives in ?q=; a keystroke replaces the history entry, never pushes one.
  // NIT-3: with no ask named in the URL, typing names the ask on screen, so the reading pane stays put.
  const query = route.q ?? "";
  const shownAsk = useRef<string | undefined>(undefined);
  const setQuery = useCallback((v: string) => {
    const pin = !routeNow.current.ask && routeNow.current.section === "asks" && shownAsk.current ? { ask: shownAsk.current } : {};
    navigate({ q: v || undefined, ...pin }, false, true);
  }, [navigate]);
  const searchBox = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const onSlash = (e: KeyboardEvent) => {
      if (e.key !== "/" || e.metaKey || e.ctrlKey || e.altKey || isTypingTarget(document.activeElement as HTMLElement | null)) return;
      if (!searchBox.current) return;
      e.preventDefault();
      searchBox.current.focus();
      searchBox.current.select();
    };
    document.addEventListener("keydown", onSlash);
    return () => document.removeEventListener("keydown", onSlash);
  }, []);

  useEffect(() => {
    if (theme === "auto") delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = theme;
    store.set("askclient.theme", theme === "auto" ? null : theme);
  }, [theme]);

  const shown = useMemo(() => visibleAsks(asks), [asks]);
  // Round 2 NIT F: a change in progress on an ask that can no longer be changed is dropped.
  useEffect(() => staleChangeKeys(asks).forEach((k) => clearUnsent(k)), [asks]);
  const hiddenCount = asks.length - shown.length;
  const drafts = trayDrafts(shown);
  const now = Date.now();
  const allRows = useMemo(() => sortRows(shown.map((a) => askRow(a, now, asks))), [shown, asks]); // eslint-disable-line react-hooks/exhaustive-deps
  // IDE-304: the search narrows the rows first, so the filters, their counts and the groups all read it.
  const terms = useMemo(() => searchTerms(route.q), [route.q]);
  // `rows` is what the list and every count read: the searched rows (all of them when ?q= is empty).
  // SF-4: the list and its count read one predicate, so they cannot disagree. Ruled below you lists
  // the newest ruling first; the other filters keep the waiting-on-you order. SHOULD-2: sidebarView
  // owns which set each reads (tested in search.test.ts); the header's waiting count reads allRows.
  // SHOULD-3: the seat counts as shown only when the row renders it.
  const seatShown = !(sideW < SIDE_SLIM) && groupBy !== "seat";
  const { rows, inFilter, count, waiting } = useMemo(() => sidebarView(allRows, shown, route.q, filter, { seat: seatShown }), [allRows, shown, route.q, filter, seatShown]);
  const extraOf = useMemo(() => new Map(rows.map((r) => [r.ref, r.extra])), [rows]);
  const loaded = root !== "";
  const named = route.ask;
  const current = named ? asks.find((a) => askRef(a) === named) : view === "asks" ? asks.find((a) => askRef(a) === inFilter[0]?.ref) : undefined;
  const currentRef = current ? askRef(current) : undefined;
  shownAsk.current = currentRef;
  // MUST-FIX-1 (ASKHL): the post-send line lives here, keyed by the sent ref, so the card's
  // ref+revision remount after the reload does not drop it; it goes once another ask is on screen.
  const [sentNotice, setSentNotice] = useState<SentNotice | undefined>();
  useEffect(() => {
    if (sentNotice && sentNotice.ref !== currentRef) setSentNotice(undefined);
  }, [currentRef]); // eslint-disable-line react-hooks/exhaustive-deps
  const askMissing = loaded && !!named && !current;
  const brief = current ? briefFor(current) : undefined;
  const proofHit = route.proof ? proofs.list?.proofs.find((p) => p.key === route.proof) : undefined;
  const proofMissing = !!route.proof && !!proofs.list?.ok && !proofHit;

  // The pane follows the URL: ?pane=off closes it, ?pane=<url> shows that page, and with neither a
  // chosen proof shows, else the ask's brief, but only from a trusted host (M2).
  const pane: Pane | null = useMemo(() => {
    if (route.pane === "off") return null;
    if (route.pane) {
      const named = current ? proofLinks(current).find((l) => l.url === route.pane)?.label : undefined;
      const fromList = proofs.list?.proofs.find((p) => p.url === route.pane)?.title;
      return paneFor(route.pane, named ?? fromList ?? "Linked page", brief?.url === route.pane ? brief.source : "link");
    }
    if (view === "proofs" && proofHit) return paneFor(proofHit.url, proofHit.title, "link");
    if (brief) {
      const p = paneFor(brief.url, brief.source === "brief" ? "Brief" : "Linked proof", brief.source);
      return p.trust === "auto" ? p : null;
    }
    return null;
  }, [route.pane, view, proofHit, brief, current, proofs.list]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (detail.current) detail.current.scrollTop = 0;
  }, [currentRef]);

  const pick = (ref: string) => navigate({ section: "asks", ask: ref, fork: undefined, pane: undefined });
  // NIT-1: the search box lives in the asks view only, so ?q= is dropped on the way to proofs or broadcasts.
  const setView = (v: View) => navigate({ section: v, ask: currentRef, proof: undefined, broadcast: undefined, pane: undefined, fork: undefined, ...(v === "asks" ? {} : { q: undefined }) });
  const openInPane = useCallback((url: string) => navigate({ pane: url }, true), [navigate]);
  const closePane = () => navigate({ pane: "off" }, false);
  const toggleBrief = () => {
    if (!current || !brief) return;
    if (pane) closePane();
    else navigate({ pane: paneFor(brief.url, "", brief.source).trust === "auto" ? undefined : brief.url }, false);
  };
  const setForkHash = useCallback((label: string) => navigate({ fork: label }, false), [navigate]);

  /** MF-1: each draft in the batch is settled whole; a draft that leaves forks unpicked is confirmed first. */
  function askSendBatch() {
    const msg = batchConfirmation(drafts, (a) => askRef(a as StoredAsk));
    if (msg) setBatchConfirm(msg);
    else sendBatch();
  }

  async function sendBatch() {
    setBatchConfirm(undefined);
    setSending(true);
    // SHOULD-1 (ASKWITHDRAWN delta): every word is next.ts batchOutcome's, written once; a withdrawal gets its
    // own line. NIT-5 (ASKFOLLOW critique): the old line is hidden while sending, and a throw replaces it.
    let line = "";
    try {
      const out = batchOutcome(await post("/api/send", { refs: drafts.map(askRef) }));
      line = out.line;
      if (out.reload) load();
    } catch (e) {
      line = `Error: ${(e as Error).message}`;
    } finally {
      setSending(false);
      setBatchResult(line);
    }
  }

  const slim = sideW < SIDE_SLIM;
  return (
    <PaneContext.Provider value={openInPane}>
      <div className={`app${dragging ? " dragging" : ""}`}>
        <header className="top">
          <h1>Asks</h1>
          <div className="seg views" role="tablist" aria-label="View">
            {(["asks", "proofs", "broadcasts"] as View[]).map((v) => (
              <button key={v} role="tab" aria-selected={view === v} aria-pressed={view === v} onClick={() => setView(v)}>
                {v === "asks" ? <>Asks <span className="n">{waiting}</span></> : v === "proofs" ? "Proofs" : "Broadcasts"}
              </button>
            ))}
          </div>
          <span className="sub">{waiting} waiting on you</span>
          <span className="spacer" />
          <span className={`live ${live ? "on" : ""}`} title={root}>{live ? "Live" : "Offline"}</span>
          <button className="iconbtn" onClick={() => setTheme(theme === "auto" ? "dark" : theme === "dark" ? "light" : "auto")} aria-label={`Theme: ${theme}. Change theme`}>
            {theme === "dark" ? "☾ Dark" : theme === "light" ? "☀ Light" : "◐ Auto"}
          </button>
        </header>
        {route.drafts && loaded && drafts.length === 0 && <p className="tray-result" role="status">No drafts are saved. (The Drafts tab is now “Ruled below you”; drafts show here when you save one.)</p>}
        {drafts.length > 0 && !trayHidden && (
          <div className="tray" role="region" aria-label="Drafts ready to send">
            <span>
              <b>{drafts.length}</b> draft{drafts.length === 1 ? "" : "s"} saved in {drafts.length === 1 ? "its file" : "their files"}, not sent:{" "}
              {drafts.map((d) => (
                <button key={askRef(d)} className="linkish" onClick={() => pick(askRef(d))}>{askRef(d)}</button>
              ))}
            </span>
            <span className="tray-actions">
              <button className="btn primary" disabled={sending} onClick={askSendBatch}>Send batch · one message per seat</button>
              <button className="btn quiet" onClick={hideTray} title="Tuck the tray away; the list keeps a ✎ drafts link">Hide</button>
            </span>
          </div>
        )}
        {drafts.length > 0 && batchConfirm && (
          <div className="tray confirm" role="alertdialog" aria-label="Confirm sending a partial batch">
            <span>{batchConfirm}</span>
            <button className="btn primary" disabled={sending} onClick={sendBatch}>Send anyway</button>
            <button className="btn" onClick={() => setBatchConfirm(undefined)}>Keep answering</button>
          </div>
        )}
        {appNotice && <p className="tray-result" role="alert">{appNotice} <button className="linkish" onClick={() => location.reload()}>Reload</button></p>}
        {batchResult && !sending && <p className="tray-result" role="status">{batchResult}</p>}
        <div className="desk" ref={desk} style={{ gridTemplateColumns: `${sideW}px 8px minmax(0, 1fr)` }}>
          <nav className={`side${slim ? " slim" : ""}`} {...{ [SCROLL_ROOT]: "" }} id="asklist" aria-label={view === "asks" ? "Asks" : view === "proofs" ? "Proof pages" : "Broadcasts"}>
            {view === "proofs" && (
              <ProofRows list={proofs.list} busy={proofs.busy} onReload={proofs.reload} slim={slim} current={pane?.url} onOpen={(p) => navigate({ proof: p.key, pane: undefined }, true)} />
            )}
            {view === "broadcasts" && <BroadcastRows list={broadcasts.list} error={broadcasts.error} current={bcast} onPick={(id) => navigate({ broadcast: id }, true)} slim={slim} />}
            {view === "asks" && <>
            <div className="side-tools">
              <AskSearch q={query} onQuery={setQuery} slim={slim} inputRef={searchBox} />
              {slim ? (
                <select aria-label="Show" value={filter} onChange={(e) => setFilter(e.target.value as Filter)} id="filter-slim">
                  {FILTERS.map((f) => <option key={f} value={f}>{FILTER_LABEL[f]} {count(f)}</option>)}
                </select>
              ) : (
                <>
                  <div className="seg" role="group" aria-label="Show">
                    {FILTERS.map((f) => (
                      <button key={f} aria-pressed={filter === f} onClick={() => setFilter(f)}>
                        {FILTER_LABEL[f]} <span className="n">{count(f)}</span>
                      </button>
                    ))}
                  </div>
                  <label className="groupby">
                    Group
                    <select value={groupBy} onChange={(e) => setGroupBy(e.target.value as GroupBy)} id="groupby">
                      <option value="none">none</option>
                      <option value="seat">by seat</option>
                      <option value="topic">by topic</option>
                    </select>
                  </label>
                </>
              )}
            </div>
            {drafts.length > 0 && trayHidden && (
              <p className="side-drafts"><button className="linkish" onClick={showTray}>✎ {drafts.length} draft{drafts.length === 1 ? "" : "s"}</button> <span className="muted">saved, not sent</span></p>
            )}
            {inFilter.length === 0 && terms.length > 0 && <SearchEmpty q={query.trim()} onClear={() => setQuery("")} />}
            {inFilter.length === 0 && terms.length === 0 && <p className="muted pad">{filter === "ruled" ? "No seat has ruled on an ask in your place." : `No ${filter === "all" ? "" : filter} asks.`}</p>}
            {groupRows(inFilter, slim ? "none" : groupBy).map((g) => (
              <section key={g.name || "all"} className="group" aria-label={g.name || undefined}>
                {g.name && <h2 className="group-name">{g.name} <span className="n">{g.rows.length}</span></h2>}
                <ul className="rows">
                  {g.rows.map((r) => (
                    <li key={r.ref}>
                      <AskRowButton r={r} slim={slim} groupBy={slim ? "none" : groupBy} current={r.ref === currentRef} onPick={() => pick(r.ref)} terms={terms} extra={extraOf.get(r.ref)} />
                    </li>
                  ))}
                </ul>
              </section>
            ))}
            {hiddenCount > 0 && !slim && <p className="muted pad">{hiddenCount} ask{hiddenCount === 1 ? " is" : "s are"} hidden until the ask {hiddenCount === 1 ? "it depends" : "they depend"} on is settled.</p>}
            </>}
          </nav>
          <Grip
            orientation="vertical"
            label="Resize the ask list"
            value={sideW}
            min={SIDE_MIN}
            max={SIDE_MAX}
            step={24}
            absolute
            container={() => desk.current}
            onChange={(v) => setSideW(v)}
            onDragging={setDragging}
          />
          <Split
            mode={portrait ? "rows" : "columns"}
            ratio={portrait ? ratioY : ratioX}
            onRatio={portrait ? setRatioY : setRatioX}
            onDragging={setDragging}
            main={
              <main className="detail" ref={detail} {...{ [SCROLL_ROOT]: "" }}>
                {proofMissing && view === "proofs" && <p className="chip warn notice" role="status">No proof page “{route.proof}” in the store. The list on the left still works.</p>}
                {view === "broadcasts" ? (
                  <BroadcastFeed list={broadcasts.list} error={broadcasts.error} current={bcast} />
                ) : askMissing ? (
                  <p className="chip warn notice" role="status">No ask “{named}” here. It may have been moved to another seat, renamed or deleted; pick one from the list.</p>
                ) : current ? (
                  <AskDetail
                    key={askRef(current) + current.header.revision}
                    ask={current}
                    all={asks}
                    onChanged={load}
                    brief={brief}
                    paneOpen={!!pane && !!brief && pane.url === brief.url}
                    onToggleBrief={toggleBrief}
                    focusFork={route.fork}
                    onForkHash={setForkHash}
                    onOpenAsk={pick}
                    sentNotice={noticeFor(sentNotice, currentRef)}
                    onSent={(text, next) => {
                      // Read when the send resolves: the operator may have opened another ask meanwhile.
                      const step = postSendStep({ sentRef: askRef(current), text, next, routeAsk: routeNow.current.ask, shownRef: shownAsk.current, rows: inFilter });
                      if (step.go) return pick(step.go);
                      if (step.notice) setSentNotice(step.notice);
                      if (step.pin) navigate({ ask: step.pin }, false);
                    }}
                  />
                ) : (
                  view === "proofs" && proofs.list && (!proofs.list.ok || proofs.list.total === 0) ? (
                    <ProofStatus list={proofs.list} />
                  ) : (
                    <p className="muted">{view === "proofs" ? "Pick a proof page on the left; it opens beside this area." : "Nothing selected."}</p>
                  )
                )}
              </main>
            }
            pane={pane ? <RelatedPane key={pane.url} pane={pane} onClose={closePane} /> : null}
          />
        </div>
      </div>
    </PaneContext.Provider>
  );
}

/** A title inside a button: code spans keep their look, links and tickets become plain text. */
/** Text with the search's hits wrapped in <mark>; unchanged when nothing matches. */
function Marked({ text, terms }: { text: string; terms: string[] }) {
  if (terms.length === 0) return <>{text}</>;
  return <>{highlight(text, terms).map((p, i) => (p.hit ? <mark key={i}>{p.text}</mark> : <Fragment key={i}>{p.text}</Fragment>))}</>;
}

const HIT_LABEL: Record<Hay["field"], string> = { title: "title", why: "why", id: "id", seat: "seat", question: "question", option: "option", answer: "answer", note: "note" };

/**
 * IDE-304: the search box at the top of the ask list. Esc clears it; `/` elsewhere focuses it (App).
 * At the slim width it takes the full row above the filter select.
 */
export function AskSearch({ q, onQuery, slim, inputRef }: { q: string; onQuery: (v: string) => void; slim: boolean; inputRef?: Ref<HTMLInputElement> }) {
  return (
    <div className={`search${slim ? " slim" : ""}`} role="search">
      <input
        ref={inputRef}
        type="search"
        value={q}
        placeholder={slim ? "Search" : "Search asks  /"}
        aria-label="Search asks"
        aria-keyshortcuts="/"
        autoComplete="off"
        spellCheck={false}
        onChange={(e) => onQuery(e.target.value)}
        onKeyDown={(e) => {
          if (e.key !== "Escape") return;
          e.preventDefault();
          if (q) onQuery("");
          else e.currentTarget.blur();
        }}
      />
      {q && <button type="button" className="search-clear" aria-label="Clear search" title="Clear search (Esc)" onClick={() => onQuery("")}>×</button>}
    </div>
  );
}

/** IDE-304: nothing matched; say what was searched for and offer the way back. */
export function SearchEmpty({ q, onClear }: { q: string; onClear: () => void }) {
  return (
    <p className="muted pad search-empty" role="status">
      No asks match “{q}”. <button type="button" className="linkish" onClick={onClear}>Clear search</button>
    </p>
  );
}

function Plain({ text, terms = [] }: { text: string; terms?: string[] }) {
  const h = (v: string) => <Marked text={v} terms={terms} />;
  return <>{inlineTokens(displayTitle(text)).map((t, i) => (t.t === "code" ? <code key={i} className="ic">{h(t.v)}</code> : t.t === "strong" ? <b key={i}>{h(t.v)}</b> : t.t === "em" ? <i key={i}>{h(t.v)}</i> : <span key={i}>{h(t.t === "text" ? t.v : t.t === "ticket" ? t.key : t.label)}</span>))}</>;
}

/**
 * One compact line per ask (operator 01:42): the title (two lines at most), then one meta line,
 * seat · age · "N of M left". Who it waits on is the row's STYLE, never a repeated chip: an ask waiting
 * on you is bold with an accent bar, one waiting on someone else is muted. Reserved and draft are small
 * marks with their words in the title and the accessible label. The seat is left out when the list is
 * grouped by seat, since the group heading already says it.
 */
export function AskRowButton({ r, current, onPick, slim, groupBy = "none", terms = [], extra }: { r: Row; current: boolean; onPick: () => void; slim: boolean; groupBy?: GroupBy; terms?: string[]; extra?: Hay }) {
  const left = r.status === "withdrawn" ? withdrawnWords({ actor: r.withdrawnBy }) : r.ruledBy ? `ruled by ${r.ruledBy}${r.ruledClass ? ` · class ${r.ruledClass}` : ""}${r.ruledAt ? ` · ${ageOf(Date.parse(r.ruledAt), Date.now())} ago` : ""}` : r.status === "open" ? `${r.left} of ${r.total} left` : r.status;
  const marks: [string, string, string][] = [
    ...(r.reserved === "operator" ? [["res", "◆", "Reserved for you: only you may answer; seats may forward it"] as [string, string, string]] : []),
    ...(r.reserved && r.reserved !== "operator" ? [["res other", "◇", `Reserved for ${r.reserved}`] as [string, string, string]] : []),
    ...(r.draft ? [["draft", "✎", "Your draft is saved, not sent"] as [string, string, string]] : []),
    ...(r.seatDraft ? [["sdraft", "✎", `${r.seatDraft} holds a draft here`] as [string, string, string]] : []),
    // Round 5: a provisional answer is with its asker; a small mark, like the others, never a chip.
    // IDE-339: an answer that overruled a seat's ruling says whose, as quietly as the other marks.
    ...(r.overruled ? [["ovr", "↺", `Overruled ${r.overruled}’s ruling`] as [string, string, string]] : []),
    ...(r.draftSent ? [["sent", "⏳", "Draft sent: your provisional answer is with the asker, who should come back with a second round"] as [string, string, string]] : []),
  ];
  const tone = r.waitingOnYou ? "you" : "other";
  return (
    <button className={`row ${tone}`} aria-current={current} onClick={onPick} title={slim ? `${r.title} · ${r.seat} · ${left}` : undefined}>
      <span className="row-top">
        {r.high && <span className="imp" title="High importance" aria-label="High importance">!</span>}
        <span className="row-title"><Plain text={r.title} terms={terms} /></span>
      </span>
      {extra && terms.length > 0 && (
        <span className="row-hit" title={`Matched in the ${HIT_LABEL[extra.field]}`}>
          <span className="row-hit-field">{HIT_LABEL[extra.field]}</span> <Marked text={snippet(extra.text, terms, slim ? 12 : 30)} terms={terms} />
        </span>
      )}
      <span className="row-meta">
        {!slim && groupBy !== "seat" && <span className="seat"><Marked text={r.seat} terms={terms} /></span>}
        {!slim && r.age && <span className="age" title={new Date(r.created).toLocaleString()}>{r.age}</span>}
        {!slim && marks.map(([c, g, t]) => <span key={c} className={`mk-i ${c}`} title={t} aria-label={t}>{g}</span>)}
        <span className={`left${r.left === 0 ? " zero" : ""}${r.ruledBy ? " ruled" : ""}`} title={r.ruledAt ? new Date(r.ruledAt).toLocaleString() : undefined}>{left}</span>
      </span>
    </button>
  );
}

// ── the related pane ─────────────────────────────────────

export type Probe = { state: "checking" | "ok" | "silent" | "notfound" | "noframe" | "error"; code?: number };

/**
 * One HEAD request per pane open (N5): reachable, 404, or a framing refusal. A failed request cannot
 * tell "down" from "does not allow this check", so it is reported as not answering, with Load anyway.
 */
export async function probePage(url: string): Promise<Probe> {
  const c = new AbortController();
  const t = setTimeout(() => c.abort(), 6000);
  try {
    const r = await fetch(url, { method: "HEAD", mode: "cors", signal: c.signal, cache: "no-store" });
    if (r.status === 404) return { state: "notfound", code: 404 };
    if (!r.ok) return { state: "error", code: r.status };
    const xfo = r.headers.get("x-frame-options") ?? "";
    const csp = r.headers.get("content-security-policy") ?? "";
    if (/deny|sameorigin/i.test(xfo) || /frame-ancestors\s+('none'|'self')/i.test(csp)) return { state: "noframe" };
    return { state: "ok" };
  } catch {
    return { state: "silent" };
  } finally {
    clearTimeout(t);
  }
}

/** The proof page is framed with scripts and its own origin, and may open new tabs; no forms, no top navigation. */
export const PANE_SANDBOX = "allow-scripts allow-same-origin allow-popups";

/**
 * SF-2: the probe gate, as a function the effect calls, so a test can inject the probe. Nothing is
 * fetched while the page is not allowed (an "ask" host before its click) or refused. Returns the
 * effect's cleanup, or undefined when nothing was started.
 */
export function runProbe(
  pane: Pick<Pane, "url" | "trust">,
  allowed: boolean,
  on: { probe: (url: string) => Promise<Probe>; result: (p: Probe) => void; slow: () => void },
): (() => void) | undefined {
  if (!allowed || pane.trust === "refuse") return undefined;
  let live = true;
  on.probe(pane.url).then((p) => live && on.result(p));
  const t = setTimeout(() => live && on.slow(), 9000);
  return () => {
    live = false;
    clearTimeout(t);
  };
}

/** SF-2: whether the frame is drawn: allowed, not refused, and the check passed (or Load anyway). */
export function paneFramed(trust: Trust, allowed: boolean, force: boolean, probe: Probe["state"]): boolean {
  return allowed && trust !== "refuse" && (force || probe === "ok");
}

/** The one iframe the app draws: always sandboxed (no top navigation, no forms), never a referrer. */
export function PaneFrame({ url, title, onLoad }: { url: string; title: string; onLoad?: () => void }) {
  return <iframe title={title} src={url} onLoad={onLoad} referrerPolicy="no-referrer" sandbox={PANE_SANDBOX} />;
}

/** `initialProbe` is a test seam: server rendering runs no effects, so a test states the check's result. */
export function RelatedPane({ pane, onClose, initialProbe }: { pane: Pane; onClose: () => void; initialProbe?: Probe }) {
  const [allowed, setAllowed] = useState(pane.trust === "auto");
  const [probe, setProbe] = useState<Probe>(initialProbe ?? { state: "checking" });
  const [force, setForce] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [slow, setSlow] = useState(false);
  const [copied, setCopied] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    if (!allowed || pane.trust === "refuse") return;
    setProbe({ state: "checking" });
    setLoaded(false);
    setSlow(false);
    setForce(false);
    return runProbe(pane, allowed, { probe: probePage, result: setProbe, slow: () => setSlow(true) });
  }, [pane.url, pane.trust, attempt, allowed]); // eslint-disable-line react-hooks/exhaustive-deps
  const local = isLocalOnly(pane.url);
  const host = (() => {
    try {
      return new URL(pane.url).host;
    } catch {
      return pane.url;
    }
  })();
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(pane.url);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  };
  const failure =
    pane.trust === "refuse"
      ? { title: "The app does not show this page in the pane", body: "It is on the app's own address or is not a web page. A framed page from the app's own address could read the app's answer token." }
      : !allowed || force
        ? undefined
        : probe.state === "silent"
          ? local
            ? { title: "This page opens only on this machine", body: `Its server, ${host}, did not answer the app's check. It may be down, you may not be on the machine that runs it, or it may not allow the check.` }
            : { title: "The page did not answer", body: `${host} did not answer the app's check, or does not allow it.` }
          : probe.state === "notfound"
            ? { title: "Not found", body: `${host} answered 404: the page is not there. It may have been deleted or never published.` }
            : probe.state === "noframe"
              ? { title: "This page refuses to be shown inside another page", body: "Its server forbids framing. Open it in a new tab to read it." }
              : probe.state === "error"
                ? { title: `The page answered ${probe.code}`, body: "It could not be shown." }
                : undefined;
  const sourceNote = pane.source === "brief" ? "the ask's brief" : pane.source === "first proof link" ? "first proof page the ask links" : "opened from a link";
  const framed = paneFramed(pane.trust, allowed, force, probe.state);
  return (
    <aside className="pane" aria-label="Linked page">
      <div className="pane-head">
        <div className="pane-title">
          <b>{pane.label}</b>
          {failure ? <span className="pane-sub bad">{failure.title}</span> : <span className="muted">{sourceNote} · {host}</span>}
        </div>
        <div className="pane-actions">
          {pane.trust !== "refuse" && (
            <a className="iconbtn" href={pane.url} target="_blank" rel="noreferrer" aria-label="Open in new tab"><span className="nt-long">Open in new tab </span>↗</a>
          )}
          <button className="iconbtn" onClick={onClose} aria-label="Close the linked page">✕</button>
        </div>
      </div>
      <div className="pane-body">
        {!allowed && pane.trust === "ask" && (
          <div className="pane-fail" role="status">
            <b>This page is on {host}</b>
            <p>The app opens pages from this machine's proof server by itself. Pages on other hosts open only when you ask, so nothing has been fetched from {host} yet.</p>
            <code className="url">{pane.url}</code>
            <p className="actions">
              <button className="btn primary" onClick={() => setAllowed(true)}>Open in pane</button>
              <a className="btn" href={pane.url} target="_blank" rel="noreferrer">Open in new tab</a>
              <button className="btn" onClick={onClose}>Close</button>
            </p>
          </div>
        )}
        {allowed && !failure && probe.state === "checking" && !force && <p className="muted pad">Checking {host}…</p>}
        {failure && (
          <div className="pane-fail" role="status">
            <b>{failure.title}</b>
            <p>{failure.body}</p>
            <code className="url">{pane.url}</code>
            <p className="actions">
              {pane.trust !== "refuse" && probe.state !== "noframe" && <button className="btn" onClick={() => setAttempt(attempt + 1)}>Retry</button>}
              {probe.state === "silent" && <button className="btn" onClick={() => setForce(true)}>Load it anyway</button>}
              <button className="btn" onClick={copy}>{copied ? "Copied" : "Copy link"}</button>
              {probe.state === "noframe" && <a className="btn primary" href={pane.url} target="_blank" rel="noreferrer">Open in new tab</a>}
              <button className="btn" onClick={onClose}>Close</button>
            </p>
            <p className="muted">You can answer the ask without this page.</p>
          </div>
        )}
        {framed && (
          <>
            {slow && !loaded && <p className="muted pad note">Still loading. If it never appears, the page may refuse framing: open it in a new tab.</p>}
            <PaneFrame title={pane.label} url={pane.url} onLoad={() => setLoaded(true)} />
          </>
        )}
      </div>
    </aside>
  );
}

// ── answer state ─────────────────────────────────────────

/** queued → read → acted. A delivered push is QUEUED; only `readAt` makes it read. */
function lifeStage(h: Record<string, string | undefined>): string {
  if (h.acted) return "acted";
  if (h.readAt) return "read";
  if (h.delivery === "delivered") return "queued";
  return h.delivery ?? "";
}
function Life({ h }: { h: Record<string, string | undefined> }) {
  const steps: [string, boolean, string | undefined][] = [
    ["queued", h.delivery === "delivered" || !!h.readAt || !!h.acted, h.delivery === "delivered" ? "the seat's socket took it; that is not a read" : h.delivery ? `${h.delivery}${h.deliveryNote ? `: ${h.deliveryNote}` : ""}` : undefined],
    ["read", !!h.readAt, h.readAt ? `${h.readBy ?? ""} at ${h.readAt}` : "waiting for engine ask read"],
    ["acted", !!h.acted, h.acted ? `${h.acted}${h.actedAt ? ` (${h.actedAt})` : ""}` : undefined],
  ];
  return (
    <ol className="life" aria-label={`Answer state: ${lifeStage(h) || "not sent"}`}>
      {steps.map(([name, on, note]) => (
        <li key={name} className={on ? "on" : ""}>
          <b>{name}</b>
          {note && <span> · {note}</span>}
        </li>
      ))}
    </ol>
  );
}

/**
 * What the card starts filled with: the recorded answer, or the OPERATOR's own draft. A seat's draft
 * (MUST-2) is never shown as the operator's choice. A lean is never a value here (M1): it is shown
 * as a suggestion beside the values, and joins them only when the operator clicks it.
 */
export function initialValues(ask: ParsedAsk): { values: Values; text: Record<string, string>; note: string } {
  const own = ask.draft && draftAuthor(ask.draft) === "operator" ? ask.draft : undefined;
  const src = own ?? ask.answer;
  const values: Values = {};
  const text: Record<string, string> = {};
  for (const [k, v] of Object.entries(src?.answers ?? {})) {
    if (k.endsWith(".other")) text[k.slice(0, -6)] = String(v);
    else values[k] = v;
  }
  // SF-2: a draft left by a failed provisional send does not hand its draft or request line to the next send.
  return { values, text, note: own ? stripLoopLines(src?.note ?? "") : src?.note ?? "" };
}

/**
 * Whether this server keeps `provisional` (SF-3): learned from a read-back that showed the flag, or
 * from a `provisional: true` in /api/health once the server says so. Until then, false.
 */
let provisionalKeptSeen = false;
export function noteServerKeepsProvisional(v: boolean) {
  provisionalKeptSeen = v;
}


export function AskDetail({
  ask, all, onChanged, brief, paneOpen, onToggleBrief, focusFork, onForkHash, provisionalKept, onOpenAsk, startChanging, onSent, sentNotice,
}: { ask: StoredAsk; all: StoredAsk[]; onChanged: () => void; brief?: Brief; paneOpen?: boolean; onToggleBrief?: () => void; focusFork?: string; onForkHash?: (label: string) => void; provisionalKept?: boolean; onOpenAsk?: (ref: string) => void; /** Open the card already changing its answer (IDE-304). */ startChanging?: boolean; /** Called once /api/send accepted this ask, with the delivery line; `next` for Send & next. App moves on or keeps the line. */ onSent?: (text: string, next: boolean) => void; /** App's post-send line for this ask (it outlives this card's remount). */ sentNotice?: string }) {
  const [replacedBy, setReplacedBy] = useState<string | undefined>();
  const superseded = supersededInfo(ask.header);
  const withdrawn = withdrawnInfo(ask.header);
  const replaces = supersedesList(ask.header);
  const path = pathOf(ask.header);
  // NIT: an ask with no status line is open, as the list and the server read it.
  const open = (ask.header.status ?? "open") === "open";
  // IDE-304: the operator may reopen their own recorded answer and send a new one in its place.
  const mayChange = mayChangeAnswer(ask);
  // IDE-339: on a seat's ruling the same form is an overrule: Send goes straight to /api/answer, and
  // (ASKFOLLOWUP) Save draft keeps the operator's draft over the ruling, which Send batch then overrules with.
  const overrule = changeMode(ask) === "overrule";
  const ref = askRef(ask);
  // A change in progress survives a remount: its unsent edits, or the operator's saved change draft.
  const [changing, setChanging] = useState(() => mayChange && (!!startChanging || !!loadUnsent(unsentKey(ref, true)) || (!!ask.draft && draftAuthor(ask.draft) === "operator")));
  const editable = open || changing;
  const keyFor = (c: boolean) => unsentKey(ref, c);
  const revision = String(ask.header.revision ?? "");
  const keys = ask.questions.map((q, i) => questionKey(q, i));
  // Delta SHOULD-A/B (b): the open form's kept copy, adopted when the one revision since it was a follow-up.
  const [openKept] = useState(() => (open ? adoptAfterFollowup(loadUnsent(ref), ask) : undefined));
  const start = useMemo(() => {
    if (changing) return restoreUnsent(changeAnswerStart(ask), loadUnsent(keyFor(true)), revision, keys);
    const init = initialValues(ask);
    return open ? restoreUnsent(init, openKept, revision, keys) : { ...init, notice: "" };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps -- the card is keyed by ref+revision
  const [values, setValues] = useState<Values>(start.values);
  const [text, setText] = useState<Record<string, string>>(start.text);
  const [note, setNote] = useState(start.note);
  const [result, setResult] = useState("");
  // ASKFOLLOW MUST-FIX-1: a follow-up remounts this card at the next revision, often before its 200;
  // every line it says is left for both revisions and read by subscription, so it shows whenever it lands.
  const readFollowResult = () => followupResultFor(ref, revision);
  const followResult = useSyncExternalStore(subscribeFollowupResults, readFollowResult, readFollowResult);
  const [busy, setBusy] = useState(false);
  const [sendingFollowup, setSendingFollowup] = useState(false);
  const [notice, setNotice] = useState("");
  const [changedUnder, setChangedUnder] = useState(start.notice);
  const [confirmSend, setConfirmSend] = useState<{ msg: string; kind: SendKind; next?: boolean } | undefined>();
  // MF-1: the request typed in "Need something first" is kept with the picks, and comes back on a remount.
  const [keptNeed] = useState(() => (open && !changing ? openKept?.need ?? "" : ""));
  const [needOpen, setNeedOpen] = useState(!!keptNeed);
  // NIT-A: the request's kind comes back with its text.
  const [needKind, setNeedKind] = useState(() => (open && !changing ? openKept?.needKind : undefined) ?? "proof:best");
  const [needText, setNeedText] = useState(keptNeed);
  // ASKFOLLOW: the follow-up's text is kept with the picks too, so a remount or a reload brings it back.
  const followable = mayFollowUp(ask);
  // SHOULD-2: its kind, fork and attach box come back with it; else the fork is the one in focus, and
  // the picks go along, so the asker knows what you are talking about.
  const [keptCopy] = useState(() => (followable ? openKept : undefined));
  const keptFollow = keptCopy?.followup ?? "";
  const focused = focusFork === undefined ? undefined : resolveFork(ask, focusFork);
  const [followOpen, setFollowOpen] = useState(!!keptFollow);
  const [followKind, setFollowKind] = useState<FollowupKind>(keptCopy?.followKind === "first" ? "first" : "question");
  const [followFork, setFollowFork] = useState(keptCopy?.followFork !== undefined && (keptCopy.followFork === "" || keys.includes(keptCopy.followFork)) ? keptCopy.followFork : focused !== undefined ? keys[focused] : "");
  const [followText, setFollowText] = useState(keptFollow);
  const [attachPicks, setAttachPicks] = useState(keptCopy?.followAttach ?? true);
  /** The one copy every save writes: picks, notes, the request text and the follow-up text. */
  const snap = () => cardUnsent(revision, { values, text, note, need: needText, needKind, followup: followText, followKind, followFork, followAttach: attachPicks });
  useEffect(() => {
    if (editable) saveUnsent(keyFor(changing), snap());
  }, [editable, changing, ref, revision, values, text, note, needText, needKind, followText, followKind, followFork, attachPicks]); // eslint-disable-line react-hooks/exhaustive-deps
  /**
   * S-1: a 409, as supersede.ts conflictStep words it. App adds nothing: it keeps where the step says
   * (a withdrawal under the open form's key, which WithdrawnBar reads, NIT-2), names a replacement,
   * reloads so a withdrawn card redraws with the kept copy in sight, and shows the step's text.
   */
  const conflictDeps = { save: (k: string) => saveUnsent(k, snap()), setReplacedBy, reload: onChanged, setResult };
  const onConflict = (json: Parameters<typeof conflictStep>[0], here: string) => applyConflict(conflictStep(json, here, unsentKey(ref, false)), conflictDeps);

  // Only questions visible under the answers so far are sent, repeated until stable, so a hidden
  // dependent's stale pick is dropped. A suggestion is never an answer, so it never unhides one.
  let visible = visibleQuestions(ask.questions, {});
  let answers = buildAnswers(ask, values, text, visible);
  for (let pass = 0; pass < ask.questions.length; pass++) {
    const next = visibleQuestions(ask.questions, answers);
    if (next.length === visible.length) break;
    visible = next;
    answers = buildAnswers(ask, values, text, visible);
  }
  // A later round suggests the operator's picks from the round before; elsewhere, the asker's lean.
  // MF-1: ONE list, with one "unpicked" test (filled: [] is unpicked), drives the label, the dashed
  // cards and Accept all, so Accept all accepts exactly what its label names.
  const prior = useMemo(() => (open ? priorPicks(ask, all) : {}), [ask, all, open]);
  const visibleSuggestions = suggestionList(ask, values, visible, prior);
  const suggestions: Record<string, string> = Object.fromEntries(visibleSuggestions.map((v) => [v.key, v.code]));
  const fromPrior = visibleSuggestions.some((v) => v.from === "prior");
  const provisional = isProvisional(ask);
  const rounds = useMemo(() => earlierRounds(ask, all), [ask, all]);
  const dialogue = useMemo(() => dialogueOf(ask), [ask]);
  const turns = dialogue.turns;
  const kept = provisionalKept ?? provisionalKeptSeen;
  const dep = ask.header.dependsOn?.trim();
  const depMissing = dep && !all.some((a) => a.header.id === dep);
  const depDeclined = dependsOnDeclined(ask, all);
  const headerTickets = [...(ask.header.tickets ?? "").matchAll(/\b([A-Z][A-Z0-9]{1,9}-\d{1,6})\b/g)].map((m) => m[1]);
  const proofs = proofLinks(ask);
  const row = askRow(ask, Date.now(), all);
  const forkId = (i: number) => `fork-${ask.header.id}-${forkLabel(ask.questions[i], i)}`;

  const scrollToFork = (i: number | undefined) => {
    const el = i === undefined ? document.getElementById(`answerbar-${ask.header.id}`) : document.getElementById(forkId(i));
    scrollWithin(scrollRootOf(el), el, { behavior: "smooth" });
    if (i !== undefined) onForkHash?.(forkLabel(ask.questions[i], i));
  };

  // #Q2, #q2 and #f2 open that fork; an unknown one says so and shows the first.
  useEffect(() => {
    if (!focusFork) return setNotice("");
    const i = resolveFork(ask, focusFork);
    if (i === undefined) {
      setNotice(`No fork “${focusFork}” in this ask; showing ${forkLabel(ask.questions[0] ?? {}, 0)}.`);
      scrollToId(forkId(0));
    } else {
      setNotice("");
      scrollToId(forkId(i));
    }
  }, [focusFork, ask]); // eslint-disable-line react-hooks/exhaustive-deps

  /**
   * ASKFOLLOW: Send follow-up. The server writes the file, then pushes, then answers, and the page hears
   * the write (SSE) first, so the card may remount at the next revision before any answer. Nothing is
   * re-based ahead of the post (delta SHOULD-A/B): the card at N+1 adopts this copy only when the ask
   * says a follow-up made N+1 (adoptAfterFollowup). Every line is said for N and N+1, so whichever card
   * shows says it; `keep` never writes over a copy a newer card saved (keepsOver).
   */
  async function sendFollowup() {
    setBusy(true);
    // NIT-A (delta 2): the answer inputs wait too, so `keep`'s click-time snapshot cannot undo later edits.
    setSendingFollowup(true);
    const next = Number(revision) + 1;
    // NIT-C (delta 2): a line is left for N+1 only where a write may have happened.
    const say = (t: string, mayHaveWritten = true) => {
      setResult(t);
      rememberFollowupResult(ref, mayHaveWritten ? [revision, next] : [revision], t);
    };
    const keep = () => {
      if (keepsOver(loadUnsent(keyFor(false)), revision)) saveUnsent(keyFor(false), snap());
    };
    say(FOLLOWUP_PENDING);
    try {
      const r = await post("/api/followup", followupBody(ask, { kind: followKind, fork: followFork, text: followText, attachPicks }, answers), keep);
      if (r.restarted) {
        keep();
        return say(r.restarted === "updated" ? RELOAD_UPDATED : RELOAD_RESTARTED);
      }
      if (r.status === 409) {
        keep();
        const step = followupConflict(r.json, keyFor(false), unsentKey(ref, false));
        rememberFollowupResult(ref, [revision, next], step.text);
        return applyConflict(step, conflictDeps);
      }
      const out = followupOutcome(ask, r.status, r.json);
      if (!out.sent) {
        keep();
        return say(out.text, r.status >= 500);
      }
      say(out.text);
      onChanged();
    } catch (e) {
      keep();
      say(`Error: ${(e as Error).message}. Reload to see whether the follow-up was sent.`);
    } finally {
      setBusy(false);
      setSendingFollowup(false);
    }
  }

  /** IDE-339: an overrule's Send and decline go at once through /api/answer, which also clears a saved overrule draft. */
  async function sendOverrule(kind: "send" | "decline", next = false) {
    setConfirmSend(undefined);
    setBusy(true);
    setResult("");
    const keep = () => saveUnsent(keyFor(true), snap());
    try {
      const r = await post("/api/answer", overruleBody(ask, kind, { answers, note }), keep);
      if (r.restarted) return setResult(r.restarted === "updated" ? RELOAD_UPDATED : RELOAD_RESTARTED);
      if (r.status === 409) return onConflict(r.json, keyFor(true));
      // Send's after-send path (ASKHL SHOULD-1/2): a failed overrule keeps its copy and stays; an
      // accepted one hands App the line, which moves on for Send & next only while this ask is still shown.
      const out = overruleOutcome(ask, r.status, r.json);
      if (!out.sent) {
        keep();
        setResult(out.text);
        return onChanged();
      }
      clearUnsent(keyFor(true));
      onChanged();
      if (onSent) onSent(out.text, next);
      else if (out.text) setResult(out.text);
    } finally {
      setBusy(false);
    }
  }

  async function act(kind: CardAction, next = false) {
    const route = sendRoute(overrule, kind, next);
    if (route.endpoint === "/api/answer") return sendOverrule(route.kind, route.next);
    setConfirmSend(undefined);
    setBusy(true);
    setResult("");
    // Operator 01:29: a token refused after a server restart is refreshed and the request retried once;
    // the picks and notes are saved in this browser first, so even a reload keeps them.
    const keep = () => saveUnsent(keyFor(changing), snap());
    const gaveUp = (r: Authed) => (r.restarted ? (setResult(r.restarted === "updated" ? RELOAD_UPDATED : RELOAD_RESTARTED), true) : false);
    try {
      if (kind === "discard") {
        const r = await post(route.endpoint, { seat: ask.seat, id: ask.header.id }, keep);
        if (gaveUp(r)) return;
        setResult(r.status === 200 ? "Draft discarded." : `Error: ${r.json.error}`);
        return onChanged();
      }
      const r = await post(route.endpoint, draftBody(ask, kind, { answers, note }), keep);
      if (gaveUp(r)) return;
      // A superseded ask names its replacement; a withdrawn one redraws with the kept copy (onConflict).
      if (r.status === 409) return onConflict(r.json, keyFor(changing));
      if (r.status !== 200) return setResult(`Error: ${r.json.error}`);
      if (kind === "send-now") {
        const s = await post("/api/send", { refs: [askRef(ask)] }, keep);
        if (gaveUp(s)) return;
        // SHOULD-1 (ASKHL): only a 200 with nothing refused is sent. Anything else shows the server's
        // words, keeps the unsent copy, and never moves on.
        const out = sendOutcome(s.status, s.json);
        if (!out.sent) {
          keep();
          setResult(out.text);
          return onChanged();
        }
        clearUnsent(keyFor(changing));
        onChanged();
        if (onSent) onSent(out.text, next);
        else if (out.text) setResult(out.text);
        return;
      } else setResult("Draft saved in the file. Nothing has been sent: use Send batch at the top.");
      onChanged();
    } finally {
      setBusy(false);
    }
  }

  /** Send as draft and Send request: provisional and partial on purpose (see clickPlan for when they confirm). */
  async function provisionalSend(answersToSend: Record<string, AnswerValue>, noteText: string) {
    setConfirmSend(undefined);
    setBusy(true);
    setResult("");
    const keep = () => saveUnsent(keyFor(changing), snap());
    let restarted: Authed["restarted"];
    // The token refresh and the restart notice, as act() has them: edits are kept before a retry.
    const poster = async (url: string, body: unknown) => {
      const r = await post(url, body, keep);
      if (r.restarted) restarted = r.restarted;
      return r;
    };
    try {
      const out = await sendProvisional(poster, async () => {
        const j = await (await fetch("/api/asks")).json();
        return (j.asks as StoredAsk[]).find((x) => askRef(x) === askRef(ask));
      }, { seat: ask.seat, id: ask.header.id ?? "", expectedRevision: Number(ask.header.revision), answers: answersToSend, note: noteText });
      if (restarted) {
        keep();
        return setResult(restarted === "updated" ? RELOAD_UPDATED : RELOAD_RESTARTED);
      }
      if (out.supersededBy !== undefined || /was replaced/.test(out.message)) {
        keep();
        setReplacedBy(out.supersededBy ?? "");
      }
      if (out.withdrawn) keep();
      if (out.ok) {
        clearUnsent(keyFor(changing));
        setNeedText("");
        setNeedOpen(false);
        if (out.flagStored) provisionalKeptSeen = true;
      }
      setResult(out.message);
      onChanged();
    } catch (e) {
      setResult(`Error: ${(e as Error).message}. Reload to see whether anything was sent.`);
    } finally {
      setBusy(false);
    }
  }
  /** Change answer: the form starts from the recorded answer without its loop lines. Cancel puts the record back. */
  const beginChange = () => {
    const s0 = changeAnswerStart(ask);
    setValues(s0.values);
    setText(s0.text);
    setNote(s0.note);
    setResult("");
    setChanging(true);
  };
  const cancelChange = () => {
    clearUnsent(keyFor(true));
    // Round 2 NIT C: the change draft it saved goes too, or the card reopens changing.
    if (cancelDiscards(ask)) void act("discard");
    const s0 = initialValues(ask);
    setValues(s0.values);
    setText(s0.text);
    setNote(s0.note);
    setResult("");
    setChanging(false);
  };
  const sendDraft = () => provisionalSend(answers, composeNote(DRAFT_NOTE, note));
  const sendRequest = () => {
    const r = requestSend(ask, answers, note, needKind, needText);
    return provisionalSend(r.answers, r.note);
  };

  const picked = Object.keys(answers).filter((k) => !k.endsWith(".other")).length;
  const nothing = Object.keys(answers).length === 0;
  const unanswered = unansweredForks(ask, answers, visible);
  /** MF-1: a send settles the whole ask, so a send that leaves visible forks unpicked asks first. */
  // Every send button goes through clickPlan: a final partial send confirms; Send as draft and Send
  // request confirm only while the server does not keep `provisional` (SF-3).
  const runSend = (kind: SendKind, next = false) => (kind === "send" ? act("send-now", next) : kind === "draft" ? sendDraft() : sendRequest());
  const clickSend = (kind: SendKind, next = false) => {
    const plan = planClick(kind, { ask, answers, visible, provisionalKept: kept });
    if (plan.confirm) setConfirmSend({ msg: plan.confirm, kind, next });
    else runSend(kind, next);
  };
  const askSend = () => clickSend("send");
  return (
    <article className="ask">
      <header className="ask-head">
        <p className="ask-route">
          <span className="seat">{ask.header.from || ask.seat}</span> <span className="muted">→ {ask.header.to}</span>
          {row.age && <span className="muted"> · {row.age} ago</span>}
          {row.high && <span className="chip danger">! High importance</span>}
          {ask.header["reserved-for"] && <span className="chip" title="Only this party may answer; others may forward it">reserved for {ask.header["reserved-for"]}</span>}
          {ask.header.round && <span className="chip quiet">round {ask.header.round}</span>}
          {ask.header.overruled?.trim() && <span className="chip quiet overruled">Overruled {ask.header.overruled.trim()}’s ruling</span>}
          <span className="chip quiet">{provisional ? "draft sent" : ask.header.status === "open" ? `${row.left} of ${row.total} left` : ask.header.status}</span>
        </p>
        {superseded && (
          <p className="superseded" role="note">
            <b>Replaced by</b> {superseded.by ? <AskLink to={superseded.by} onOpen={onOpenAsk} /> : <span>a newer ask</span>}
            {superseded.actor && <> · {superseded.actor}</>}
            {superseded.at && <> · <time dateTime={superseded.at} title={new Date(superseded.at).toLocaleString()}>{superseded.at.replace("T", " ").slice(0, 16)}</time></>}
            <span className="muted"> · read-only; answer the new ask</span>
          </p>
        )}
        {withdrawn && (
          <p className="superseded withdrawn" role="note">
            <b>Withdrawn</b>
            {withdrawn.actor && <> by {withdrawn.actor}</>}
            {withdrawn.at && <> · <time dateTime={withdrawn.at} title={new Date(withdrawn.at).toLocaleString()}>{withdrawn.at.replace("T", " ").slice(0, 16)}</time></>}
            {withdrawn.reason && <>: {withdrawn.reason}</>}
            <span className="muted"> · read-only; nothing to answer</span>
          </p>
        )}
        {replaces.length > 0 && (
          <p className="replaces muted">Replaces {replaces.map((r, i) => <Fragment key={r}>{i > 0 && ", "}<AskLink to={r} onOpen={onOpenAsk} /></Fragment>)}</p>
        )}
        {path.length > 0 && <PathLine path={path} />}
        {rounds.length > 0 && <EarlierRounds rounds={rounds} />}
        {turns.length > 0 && (
          <section className="dialogue" aria-label="Dialogue so far">
            <span className="lg-label">Dialogue so far</span>
            <ol>{turns.map((t, i) => <li key={i}><b>{t.who}</b> <TurnText text={t.text} /></li>)}</ol>
          </section>
        )}
        {ask.header.why && <p className="ask-why"><Inline text={ask.header.why} /></p>}
        {(headerTickets.length > 0 || proofs.length > 0 || brief) && (
          <div className="ask-links">
            {headerTickets.length > 0 && (
              <span className="linkgroup">
                <span className="lg-label">Tickets</span>
                {headerTickets.map((t) => <TicketLink key={t} k={t} />)}
              </span>
            )}
            {proofs.length > 0 && (
              <span className="linkgroup">
                <span className="lg-label">Proofs</span>
                {proofs.map((p) => <ProofChip key={p.url} url={p.url} label={p.label} />)}
              </span>
            )}
            {brief && onToggleBrief && (
              <button className={`chip toggle${paneOpen ? " on" : ""}`} aria-pressed={paneOpen} onClick={onToggleBrief} title={brief.source === "brief" ? "The ask's brief page" : "No brief: field; this is the first proof page the ask links"}>
                ◧ {brief.source === "brief" ? "Brief" : "Linked proof"} {paneOpen ? "on" : "off"}
              </button>
            )}
          </div>
        )}
        {notice && <p className="chip warn notice" role="status">{notice}</p>}
        {changedUnder && editable && (
          <p className="chip warn notice" role="status">
            {changedUnder} <button className="linkish" onClick={() => setChangedUnder("")}>Dismiss</button>
          </p>
        )}
        {visibleSuggestions.length > 0 && (
          <div className="suggest-bar">
            <p>
              <b>Suggested picks</b> {fromPrior ? "are your picks from the last round where they still fit, and the asker's leans elsewhere" : "are the asker's leans"}, shown dashed. They are not your answer: nothing is saved or sent until you click. Click a suggested option to confirm it and move to the next fork.
            </p>
            <button className="btn" onClick={() => setValues(acceptListed(ask, values, visibleSuggestions))}>
              Accept all {visibleSuggestions.length} suggestion{visibleSuggestions.length === 1 ? "" : "s"}: {visibleSuggestions.map((s) => `${s.label} ${s.code}`).join(" · ")}
            </button>
          </div>
        )}
      </header>
      {depMissing && <p className="chip warn">depends on {dep}, which is not in this root</p>}
      {depDeclined && <p className="chip warn">depends on {dep}, which was declined</p>}
      {ask.questions.map((q, i) => {
        const k = questionKey(q, i);
        return (
          <Fragment key={k}>
            <QuestionCard
              ask={ask}
              q={q}
              index={i}
              domId={forkId(i)}
              waiting={!visible.includes(q)}
              value={values[k]}
              suggestion={suggestions[k]}
              onValue={(v) => setValues((cur) => ({ ...cur, [k]: v }))}
              onConfirm={(v) => {
                setValues((cur) => ({ ...cur, [k]: v }));
                scrollToFork(nextFork(ask, i, visible));
              }}
              note={text[k] ?? ""}
              onNote={(t) => setText({ ...text, [k]: t })}
              readOnly={!editable || sendingFollowup}
            />
            {/* Prose written after a fork's options, before the next heading, sits between the cards. */}
            <ForkProse text={q.proseAfter} between />
          </Fragment>
        );
      })}

      <section className="answerbar" id={`answerbar-${ask.header.id}`}>
        {withdrawn && <WithdrawnBar ask={ask} w={withdrawn} />}
        <FollowupList ask={ask} />
        {(isSettled(ask) || provisional) && !changing && (
          <>
            {ruledBelow(ask) ? (
              <p className="ruled-by" role="note">
                <b>Ruled by {answererText(ask.answer)}</b>
                {ask.answer?.answeredAt && <> · <time dateTime={ask.answer.answeredAt} title={new Date(ask.answer.answeredAt).toLocaleString()}>{ask.answer.answeredAt.replace("T", " ").slice(0, 16)} ({ageOf(Date.parse(ask.answer.answeredAt), Date.now())} ago)</time></>}
                {/* ASKOVR fix 2: say Overrule only where the card offers it; a seat an ask was reserved for answered in its own place. */}
                {overrule ? (
                  <span className="muted"> · a seat answered in your place{ask.header.status === "declined" ? " and declined" : ""}. Overrule it to answer in its place.</span>
                ) : ask.header["reserved-for"]?.trim() ? (
                  <span className="muted"> · it was reserved for that seat, which answered{ask.header.status === "declined" ? " and declined" : ""}.</span>
                ) : null}
              </p>
            ) : null}
            <h3>{provisional ? (row.followedBy ? "Draft sent; the asker came back" : "Waiting on the asker: draft sent") : ask.header.status === "declined" ? "Declined" : "Answered"} · revision {ask.header.revision}</h3>
            {provisional && !row.followedBy && <p className="muted">This answer is not final. The asker comes back with a second round, which opens here as a new ask.</p>}
            {row.followedBy && <p className="followed-up muted">followed up by <AskLink to={row.followedBy} onOpen={onOpenAsk} /></p>}
            <AnsweredBy answer={ask.answer} />
            {ask.answer?.note && <p className="answer-note"><Inline text={ask.answer.note} /></p>}
            <Life h={ask.header} />
            {ask.header.status !== "declined" && <AnswerWords ask={ask} />}
            <EarlierAnswers ask={ask} />
            <details className="raw-answer">
              <summary>Recorded answer block</summary>
              <RecordedAnswer answer={ask.answer} />
            </details>
            {mayChange && (
              <p className="actions">
                {overrule
                  ? <button className="btn" disabled={busy} onClick={beginChange} title={`Answer in place of ${ask.answer?.answeredBy || "the seat"}; the asker is told the ruling was overruled`}>Overrule</button>
                  : <button className="btn" disabled={busy} onClick={beginChange} title="Reopen your answer and send a new one in its place">Change answer</button>}
              </p>
            )}
          </>
        )}
        {editable && (
          <>
            {changing && <h3>{overrule ? `Overrule ${ask.answer?.answeredBy || "the seat"}` : "Change your answer"} · revision {ask.header.revision}</h3>}
            {changing && <p className="muted sends">{overrule ? OVERRULE_WORDING : CHANGE_WORDING}</p>}
            <p className="muted sends">
              {nothing
                ? "Nothing picked yet. Suggestions are not sent."
                : `Sending settles this ask: the asker gets ${picked} of ${visible.length} fork${visible.length === 1 ? "" : "s"} answered${Object.keys(answers).length > picked ? " and your notes" : ""}${unanswered.length ? `, and ${unanswered.join(", ")} reach${unanswered.length === 1 ? "es" : ""} the asker unanswered. The ask closes; nothing here is left open` : ""}.${overrule ? " Save draft keeps it in the file and sends nothing; sending that draft overrules." : " Save draft keeps it in the file and sends nothing."}`}
            </p>
            <label className="field-label" htmlFor={`${changing ? "change-note" : "note"}-${ask.header.id}`}>Note to the asker</label>
            <textarea id={`${changing ? "change-note" : "note"}-${ask.header.id}`} rows={2} placeholder="Optional. To decline, write the reason here." value={note} disabled={sendingFollowup} onChange={(e) => setNote(e.target.value)} />
            <p className="actions">
              <button className="btn primary" disabled={busy || nothing} onClick={askSend}>{nothing ? "Send answers" : picked ? `Send ${picked} answer${picked === 1 ? "" : "s"}` : "Send your notes"}</button>
              {onSent && <button className="btn" disabled={busy || nothing} onClick={() => clickSend("send", true)} title="Sends exactly as Send does, then opens the next ask in the list that is waiting on you">Send &amp; next</button>}
              {/* Partial on purpose: never the "N questions unanswered" confirm; while the server does not keep `provisional`, an honest confirm instead. */}
              {/* IDE-339: Send as draft and Need something first are provisional rounds, so both stay off an
                  overrule; its decline is sent at once, as "Send a decline". ASKFOLLOWUP widened
                  writeDraft to the operator over a seat's ruling, so Save draft is offered on one. */}
              {!overrule && <button className="btn" disabled={busy || nothing} onClick={() => clickSend("draft")} title={kept ? "Sends your picks marked as not final, with a note saying so; the ask stays open for a second round" : "Today this closes the ask with your picks and a 'not final' note; the asker should come back with a second round"}>Send as draft</button>}
              {!overrule && <button className="btn" disabled={busy} aria-expanded={needOpen} aria-controls={`need-${ask.header.id}`} onClick={() => setNeedOpen(!needOpen)}>Need something first ▾</button>}
              <button className="btn quiet" disabled={busy || nothing} onClick={() => act("draft")}>{ask.draft ? "Update draft" : "Save draft"}</button>
              {/* One decline button: on an overrule sendRoute sends it at once through /api/answer; elsewhere it is drafted. */}
              <button className="btn" disabled={busy || !note.trim()} title="Declining needs a reason: write it in the note" onClick={() => act("draft-decline")}>{overrule ? "Send a decline" : "Draft a decline"}</button>
              {ask.draft && <button className="btn" disabled={busy} onClick={() => act("discard")}>Discard draft</button>}
              {changing && <button className="btn quiet" disabled={busy} onClick={cancelChange}>Cancel</button>}
              {followable && <button className="btn" disabled={busy} aria-expanded={followOpen} aria-controls={`followup-${ask.header.id}`} onClick={() => {
                    if (!followOpen) setFollowFork(forkOnOpen(followText, focused === undefined ? undefined : keys[focused], followFork));
                    setFollowOpen(!followOpen);
                  }} title="Ask the asker something, or ask it to do something first; the ask stays open">Send follow-up ▾</button>}
            </p>
            {confirmSend && (
              <div className="confirm-send" role="alertdialog" aria-label="Confirm sending a partial answer">
                <p>{confirmSend.msg}</p>
                <p className="actions">
                  <button className="btn primary" disabled={busy} onClick={() => runSend(confirmSend.kind, confirmSend.next)}>{confirmSend.kind === "send" ? "Send anyway" : confirmSend.kind === "draft" ? "Send as draft anyway" : "Send request anyway"}</button>
                  <button className="btn" onClick={() => setConfirmSend(undefined)}>Keep answering</button>
                </p>
              </div>
            )}
            {needOpen && (
              <div className="need" id={`need-${ask.header.id}`}>
                <label className="field-label" htmlFor={`need-kind-${ask.header.id}`}>What do you need before you answer?</label>
                <select id={`need-kind-${ask.header.id}`} value={needKind} disabled={sendingFollowup} onChange={(e) => setNeedKind(e.target.value)}>
                  {[...new Set(REQUEST_KINDS.map((k) => k.group))].map((g) => (
                    <optgroup key={g} label={g}>
                      {REQUEST_KINDS.filter((k) => k.group === g).map((k) => <option key={k.kind} value={k.kind}>{k.label}</option>)}
                    </optgroup>
                  ))}
                </select>
                <label className="field-label" htmlFor={`need-text-${ask.header.id}`}>In your words</label>
                <textarea id={`need-text-${ask.header.id}`} rows={2} placeholder="For example: is BIND worth the migration?" value={needText} disabled={sendingFollowup} onChange={(e) => setNeedText(e.target.value)} />
                <p className="muted need-preview">
                  Sends <code>{needText.trim() ? requestLine(needKind, needText) : `request: ${needKind} — …`}</code> as the first line of the note
                  {picked ? `, with your ${picked} pick${picked === 1 ? "" : "s"}${Object.keys(answers).length > picked ? " and your fork notes" : ""} as a draft answer.` : `. With no picks it also goes in as ${forkLabel(ask.questions[0] ?? {}, 0)}'s answer text, since an empty answer is refused.`}
                </p>
                <p className="actions">
                  <button className="btn primary" disabled={busy || !needText.trim()} onClick={() => clickSend("request")} title={kept ? "Sends the request as a provisional answer" : "Today this closes the ask with the request line in the note; the asker should come back with a second round"}>Send request</button>
                  <button className="btn quiet" onClick={() => setNeedOpen(false)}>Cancel</button>
                </p>
              </div>
            )}
            {followable && followOpen && (
              <div className="need followup" id={`followup-${ask.header.id}`}>
                <span className="field-label">Follow up with the asker</span>
                <span className="followup-kinds" role="radiogroup" aria-label="Kind of follow-up">
                  {FOLLOWUP_KIND_OPTIONS.map((o) => (
                    <label key={o.kind} title={o.hint}>
                      <input type="radio" name={`followup-kind-${ask.header.id}`} value={o.kind} checked={followKind === o.kind} disabled={busy} onChange={() => setFollowKind(o.kind)} />
                      <span>{o.label}</span>
                    </label>
                  ))}
                </span>
                <label className="field-label" htmlFor={`followup-fork-${ask.header.id}`}>Which question you mean</label>
                <select id={`followup-fork-${ask.header.id}`} value={followFork} disabled={busy} onChange={(e) => setFollowFork(e.target.value)}>
                  <option value="">The whole ask</option>
                  {ask.questions.map((q, i) => <option key={questionKey(q, i)} value={questionKey(q, i)}>{`${forkLabel(q, i)}: ${q.title}`}</option>)}
                </select>
                <label className="field-label" htmlFor={`followup-text-${ask.header.id}`}>In your words</label>
                <textarea id={`followup-text-${ask.header.id}`} rows={2} placeholder={followKind === "first" ? "For example: run the dry-run migration and say what breaks" : "For example: what does NO hold the release for?"} value={followText} disabled={busy} onChange={(e) => setFollowText(e.target.value)} />
                <label className="followup-picks">
                  <input type="checkbox" checked={attachPicks && !nothing} disabled={busy || nothing} onChange={(e) => setAttachPicks(e.target.checked)} />
                  <span>{nothing ? "No picks to attach yet" : `Attach your current picks (${picked} pick${picked === 1 ? "" : "s"}${Object.keys(answers).length > picked ? " and your fork notes" : ""}) as context`}</span>
                </label>
                <p className="muted need-preview">
                  {FOLLOWUP_KIND_OPTIONS.find((o) => o.kind === followKind)?.hint} Nothing is answered: your picks stay unsent here.
                </p>
                <p className="actions">
                  <button className="btn primary" disabled={busy || !followText.trim()} onClick={() => void sendFollowup()}>Send follow-up</button>
                  <button className="btn quiet" onClick={() => setFollowOpen(false)}>Cancel</button>
                </p>
              </div>
            )}
            {ask.draft && (
              <p className="muted">
                {draftAuthor(ask.draft) === "operator"
                  ? <>Draft saved {ask.draft.savedAt} against revision {ask.draft.basedOn}{ask.draft.declined ? `, a decline: ${ask.draft.reason}` : ""}. Not sent.</>
                  : <>{draftAuthor(ask.draft)} holds an unsent draft here ({ask.draft.savedAt}); it is not shown as your choice. Saving your own draft replaces it.</>}
              </p>
            )}
          </>
        )}
        {result && <p className="result" role="status">{result}</p>}
        {!result && followResult && <p className="result" role="status">{followResult}</p>}
        {sentNotice && <p className="result sent-notice" role="status">{sentNotice}</p>}
        {replacedBy && <p className="result"><AskLink to={replacedBy} onOpen={onOpenAsk}>Open the new ask: {replacedBy}</AskLink></p>}
        <AskDetails ask={ask} />
      </section>
    </article>
  );
}

/** IDE-304 item 5: the recorded answer read out fork by fork, above the raw block (which stays closed). */
export function AnswerWords({ ask, answer = ask.answer, label = "The answer, fork by fork" }: { ask: StoredAsk; answer?: AskAnswer; label?: string }) {
  const lines = answerInWords(ask, answer);
  if (!lines.length) return null;
  return (
    <dl className="answer-words" aria-label={label}>
      {lines.map((l) => (
        <div key={l.label}>
          <dt><span className="flabel">{l.label}</span> <Inline text={l.title} /></dt>
          <dd>
            {l.unanswered ? <span className="muted">not answered</span> : <b>{l.picks.join(", ")}</b>}
            {l.note && <span className="aw-note"> — <Inline text={l.note} /></span>}
          </dd>
        </div>
      ))}
    </dl>
  );
}

/** A time as the card shows it: "2026-10-29 10:30", the full local time on hover. */
function When({ at }: { at?: string }) {
  if (!at) return null;
  return <time dateTime={at} title={new Date(at).toLocaleString()}>{at.replace("T", " ").slice(0, 16)}</time>;
}

/**
 * IDE-339: every answer this one replaced, newest first, collapsed: who answered (with the grant class),
 * when, via what, the picks in words and the note. The old server sends only the one-line `replaced:`.
 */
export function EarlierAnswers({ ask }: { ask: StoredAsk }) {
  const list = earlierAnswers(ask);
  // ASKOVR NIT-3: the server names a history fence it could not read, and refuses a second answer until it is fixed.
  const bad = ask.historyError && (
    <p className="history-error" role="note">
      The earlier answers could not be read: {ask.historyError}. The server takes no new answer here until someone fixes the history block: fix or remove it by hand.
    </p>
  );
  if (!list.length) return bad || null;
  return (
    <>
    {bad}
    <details className="earlier-answers">
      <summary>Earlier answers ({list.length})</summary>
      <ol>
        {list.map((e, i) =>
          e.kind === "summary" ? (
            <li key={i} className="muted">{e.text}</li>
          ) : (
            <li key={i}>
              <p className="ea-head">
                <span className="muted">revision {String(e.answer.revision ?? "?")}</span> · <b>{answererText(e.answer)}</b>
                {e.answer.answeredAt && <> · <When at={e.answer.answeredAt} /></>}
                {e.answer.answeredVia && <span className="muted"> · via {e.answer.answeredVia}</span>}
              </p>
              {e.answer.declined ? <p>declined: <Inline text={e.answer.reason ?? ""} /></p> : <AnswerWords ask={ask} answer={e.answer} label={`Revision ${String(e.answer.revision ?? "?")}, fork by fork`} />}
              {e.answer.note && <p className="answer-note"><Inline text={e.answer.note} /></p>}
            </li>
          ),
        )}
      </ol>
    </details>
    </>
  );
}

/** ASKFOLLOW: the follow-ups sent on this ask, oldest first, each with its delivery and whether the asker addressed it. */
export function FollowupList({ ask }: { ask: StoredAsk }) {
  const list = followupsOf(ask);
  if (!list.length) return null;
  const open = list.filter((f) => !isAddressed(f)).length;
  return (
    <details className="followups" open={open > 0}>
      <summary>Follow-ups ({list.length}){open ? ` · ${open} not addressed yet` : ""}</summary>
      <ol>
        {list.map((f) => (
          <li key={f.n} className={isAddressed(f) ? "addressed" : "pending"}>
            <p className="muted">{followupLine(ask, f)}{f.at && <> · <When at={f.at} /></>}</p>
            <p><TurnText text={f.text} /></p>
          </li>
        ))}
      </ol>
    </details>
  );
}

/** A link to another ask: a real URL, opened in place when the app can. */
function AskLink({ to, onOpen, children }: { to: string; onOpen?: (ref: string) => void; children?: React.ReactNode }) {
  const href = serializeRoute({ section: "asks", ask: to, filter: "open", group: "none" });
  return (
    <a className="asklink" href={href} onClick={(e) => { if (onOpen && !e.metaKey && !e.ctrlKey && !e.shiftKey) { e.preventDefault(); onOpen(to); } }}>
      {children ?? to}
    </a>
  );
}

/** "Path: seat → seat → you", with a declined hop marked and its reason on hover and in the label. */
export function PathLine({ path }: { path: PathHop[] }) {
  const who = (s: string) => (s === "operator" ? "you" : s);
  return (
    <p className="path" aria-label={`Path: ${path.map(hopWords).join("; ")}`}>
      <span className="lg-label">Path</span> {who(path[0].from)}
      {path.map((p, i) => (
        <Fragment key={i}>
          {p.reason ? (
            <span className="hop declined" title={hopWords(p)}> declined →</span>
          ) : (
            <span className="hop" title={`${p.from} → ${p.to}${p.at ? ` · ${p.at}` : ""}`}> →</span>
          )}{" "}
          {who(p.to)}
        </Fragment>
      ))}
    </p>
  );
}

/** Earlier rounds of this ask, oldest first, each collapsed with the answers it got. */
function EarlierRounds({ rounds }: { rounds: RoundView[] }) {
  return (
    <div className="rounds" aria-label="Earlier rounds">
      {rounds.map((r) => (
        <details key={r.ref} className="round">
          <summary>
            Round {r.round} · <span className="muted">{r.ref}</span> · {r.provisional ? "draft sent" : r.status}
          </summary>
          {r.title && <p className="round-q"><Inline text={r.title} /></p>}
          {r.lines.length ? <ul>{r.lines.map((l, i) => <li key={i}><Inline text={l} /></li>)}</ul> : <p className="muted">{r.status === "not in this root" ? "That round is not in this root." : "No answers recorded."}</p>}
          {r.note && <Rich text={r.note} />}
        </details>
      ))}
    </div>
  );
}

function ProofChip({ url, label }: { url: string; label: string }) {
  return (
    <PaneContext.Consumer>
      {(open) => (
        <a className="chip proof" href={url} target="_blank" rel="noreferrer" onClick={(e) => { if (open && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey) { e.preventDefault(); open(url, label); } }}>
          ◧ {label}
        </a>
      )}
    </PaneContext.Consumer>
  );
}

function AskDetails({ ask }: { ask: StoredAsk }) {
  return (
    <details className="askmeta">
      <summary>Ask header and file</summary>
      <dl className="ctx">
        {Object.entries(ask.header).filter(([, v]) => v).map(([k, v]) => (
          <div key={k} style={{ display: "contents" }}>
            <dt>{k}</dt>
            <dd>{v}</dd>
          </div>
        ))}
        <dt>file</dt>
        <dd><code>{ask.file}</code></dd>
      </dl>
    </details>
  );
}

const OPTIONAL: [keyof Card, string][] = [
  ["confidence", "Confidence"], ["reversible", "Reversible"], ["verify", "Verify"], ["falsifier", "Falsifier"],
  ["ifUnanswered", "If unanswered"], ["neededBy", "Needed by"], ["blocks", "Blocks"], ["askedBy", "Asked by"],
];
const KIND_LABEL: Record<string, string> = { "choose-one": "choose one", choose: "choose any", rank: "rank all", text: "free text", number: "a number", date: "a date", yesno: "yes or no" };

/** Ticket keys written in this one fork: its title, prose, card lines, evidence and options. */
function forkTickets(q: AskQuestion): string[] {
  const opt = (os: AskOption[]): string[] => os.flatMap((o) => [o.label, o.description ?? "", o.cost ?? "", ...opt(o.children ?? [])]);
  const text = [q.title, q.prose ?? "", ...Object.values(q.meta), ...q.evidence, ...opt(q.options)].join("\n");
  return [...new Set([...text.matchAll(/\b([A-Z][A-Z0-9]{1,9}-\d{1,6})\b/g)].map((m) => m[1]))];
}

function QuestionCard(p: {
  ask: StoredAsk; q: AskQuestion; index: number; domId: string; waiting: boolean; readOnly: boolean;
  value: AnswerValue | undefined; suggestion?: string;
  onValue: (v: AnswerValue | undefined) => void; onConfirm: (v: AnswerValue) => void; note: string; onNote: (t: string) => void;
}) {
  const { ask, q, index } = p;
  const card = cardFor(ask, index);
  const k = questionKey(q, index);
  const label = forkLabel(q, index);
  const total = ask.questions.length;
  const leanCode = leanCodeFor(ask, index);
  const lean = leanFor(ask, index);
  const trade = tradeoff(q.options, leanCode);
  const tickets = forkTickets(q);
  const high = ask.header.importance?.trim().toLowerCase() === "high";
  const choice = q.kind === "choose-one" || q.kind === "choose" || q.kind === "yesno";
  const preamble = index === 0 ? dialogueOf(ask).preamble : "";
  return (
    <article className="fork" id={p.domId} data-kind={q.kind}>
      <div className="fork-head">
        <span className="eyebrow">
          <b className="flabel">{label}</b>
          {` · ${index + 1} of ${total}`}
          {card.rank && ` · rank ${card.rank}`}
          <span className="kind"> · {KIND_LABEL[q.kind]}</span>
          {card.topic && <span className="topic"> · {card.topic}</span>}
        </span>
        <span className="fork-aff">
          {high && <span className="chip danger" title="The ask is marked high importance; it applies to every fork">! High importance</span>}
          {tickets.length > 0 && <span className="chip quiet" title={tickets.join(", ")}>{tickets.length} ticket{tickets.length === 1 ? "" : "s"}</span>}
          {card.reservedFor && <span className="chip" title="Only this party may answer; others may forward it">reserved · {card.reservedFor}</span>}
          <a className="perma" href={`#${askRef(ask)}/${label}`} aria-label={`Link to ${label}`}>¶</a>
        </span>
      </div>

      <h3 className="fork-q"><Inline text={displayTitle(q.title)} /></h3>
      {index === 0 && preamble.trim() && <Rich text={preamble.trim()} className="rich preamble" />}
      {card.context && <Rich text={card.context} className="rich context" />}
      <ForkProse text={q.prose} />

      {(card.stake || card.unblocks) && (
        <dl className="stakes">
          {card.stake && <div><dt>At stake</dt><dd><Inline text={card.stake} /></dd></div>}
          {card.unblocks && <div><dt>Deciding this unblocks</dt><dd><Inline text={card.unblocks} /></dd></div>}
        </dl>
      )}
      {card.evidence.length > 0 && (
        <details className="evidence">
          <summary>Evidence <span className="n">{card.evidence.length}</span></summary>
          <ul>{card.evidence.map((e, i) => <li key={i}><Inline text={e} /></li>)}</ul>
        </details>
      )}

      {p.waiting ? (
        <p className="waiting">Waiting on ASK_{q.dependsOn?.ask}{q.dependsOn?.code ? ` = ${q.dependsOn.code}` : ""}.</p>
      ) : (
        <>
          {choice && q.options.length > 1 && trade.shown.length > 0 && <TradeLegend trade={trade} />}
          <Input q={q} card={card} lean={leanCode} leanText={lean?.text} trade={trade} radioBase={`${askRef(ask)}#${k}`} value={p.value} suggestion={p.suggestion} onValue={p.onValue} onConfirm={p.onConfirm} readOnly={p.readOnly} />
        </>
      )}
      {lean && !leanCode && leanReason(lean.text) && (
        <p className="lean-line"><b>Lean:</b> <Inline text={leanReason(lean.text)} />{card.counter && <> <b>Strongest counter:</b> <Inline text={card.counter} /></>}</p>
      )}
      {leanCode && card.counter && <p className="lean-line"><b>Strongest counter to the lean:</b> <Inline text={card.counter} /></p>}
      {q.panel.length > 0 && (
        <p className="panel-line">
          <span className="lg-label">Panel read</span> {q.panel.length} lens{q.panel.length === 1 ? "" : "es"} ·{" "}
          {q.panel.map((r, i) => <span key={i} className="pl">{r.lens} → <code>{r.pick}</code>{i < q.panel.length - 1 ? " · " : ""}</span>)}
          <span className="muted"> · a read, not a vote</span>
        </p>
      )}
      {OPTIONAL.some(([f]) => card[f]) && (
        <dl className="cardmeta">
          {OPTIONAL.filter(([f]) => card[f]).map(([f, l]) => (
            <div key={f}><dt>{l}</dt><dd><Inline text={card[f] as string} /></dd></div>
          ))}
        </dl>
      )}
      {card.related && (
        <details className="evidence">
          <summary>Related, not asked here</summary>
          <Rich text={card.related} />
        </details>
      )}
      {!p.waiting && (
        <textarea
          className="fork-note"
          rows={1}
          disabled={p.readOnly}
          aria-label={`Your note on ${label}`}
          placeholder={`Your note on ${label}: a different answer, a condition, or a question back. Optional.`}
          value={p.note}
          onChange={(e) => p.onNote(e.target.value)}
        />
      )}
      <div className="fork-foot">
        <span>{card.provenance ?? `asked by ${card.askedBy ?? ask.header.from}`}</span>
        {card.asOf && <span>as of {card.asOf}</span>}
        <span className="ref">{card.sourceRef ?? `${ask.seat}/${ask.header.id}#${label}`}</span>
        {q.dependsOn && <span>after ASK_{q.dependsOn.ask}{q.dependsOn.code ? `=${q.dependsOn.code}` : ""}</span>}
      </div>
    </article>
  );
}

type Trade = ReturnType<typeof tradeoff>;
const LEGEND: Record<Dim, string> = { blast: "△ ◭ ▲", effort: "Ⓢ Ⓜ Ⓛ", cost: "one line", lean: "★ the asker's lean" };
function TradeLegend({ trade }: { trade: Trade }) {
  return (
    <p className="legend" aria-label="What the marks on the options mean">
      <span className="lg-label">Compare</span>
      {trade.shown.map((d) => (
        <span key={d} className={trade.same.includes(d) ? "same" : undefined}>{d === "lean" ? LEGEND.lean : `${DIM_LABEL[d]} ${LEGEND[d]}`}</span>
      ))}
      <span className="muted">faded: the same for every option{trade.shown.some((d) => d !== "lean" && Object.values(trade.rows).some((r) => !r[d])) ? " · – not given" : ""}</span>
    </p>
  );
}

/** Kept for the old import: the author's prose under a fork's heading, rendered as markdown. */
export function ForkProse({ text, between }: { text?: string; between?: boolean }) {
  if (!text?.trim()) return null;
  return <Rich text={text} className={between ? "fork-prose between-forks" : "fork-prose"} />;
}

// ── inputs by kind ────────────────────────────────────────

type InputProps = {
  q: AskQuestion; card: Card; lean?: string; leanText?: string; trade: Trade; radioBase: string;
  value: AnswerValue | undefined; suggestion?: string;
  onValue: (v: AnswerValue | undefined) => void; onConfirm: (v: AnswerValue) => void; readOnly: boolean;
};

function Input(p: InputProps) {
  const { q, value, onValue, readOnly } = p;
  if (q.kind === "text") {
    return <textarea className="answer-text" rows={3} disabled={readOnly} placeholder="Your answer" value={typeof value === "string" ? value : ""} onChange={(e) => onValue(e.target.value)} />;
  }
  if (q.kind === "number") {
    const n = q.number ?? {};
    return (
      <p className="answer-num">
        <input type="number" disabled={readOnly} min={n.min} max={n.max} value={typeof value === "number" ? value : ""} onChange={(e) => onValue(e.target.value === "" ? undefined : Number(e.target.value))} />
        {n.unit && <span> {n.unit}</span>}
        {(n.min !== undefined || n.max !== undefined) && <span className="muted"> between {n.min ?? "−∞"} and {n.max ?? "∞"}</span>}
      </p>
    );
  }
  if (q.kind === "date") {
    return <p><input type="date" disabled={readOnly} value={typeof value === "string" ? value : ""} onChange={(e) => onValue(e.target.value || undefined)} /></p>;
  }
  if (q.kind === "rank") return <RankInput {...p} value={Array.isArray(value) ? value : undefined} />;
  const picks = Array.isArray(value) ? value : [];
  return (
    <>
      <OptionTree {...p} options={q.options} picks={picks} name={`${p.radioBase}/top`} onPicks={(v, confirm) => (confirm ? p.onConfirm(v) : onValue(v.length ? v : undefined))} />
      {!readOnly && picks.length > 0 && (
        <button className="linkish clear" onClick={() => onValue(undefined)}>Clear this pick</button>
      )}
    </>
  );
}

const glyphOr = (c: { glyph: string; text: string } | undefined) => (c ? c.glyph || c.text : "–");
function Strip({ trade, cells }: { trade: Trade; cells: Trade["rows"][string] | undefined }) {
  const show = trade.shown.filter((d) => d !== "cost");
  if (show.length === 0) return null;
  return (
    <span className="strip" aria-label={show.flatMap((d) => (d === "lean" ? (cells?.lean ? ["the asker's lean"] : []) : [`${DIM_LABEL[d]}: ${cells?.[d]?.text ?? "not given"}`])).join("; ")}>
      {show.map((d) =>
        d === "lean" ? (
          cells?.lean ? <span key={d} className="g g-lean" title="the asker's lean" aria-label="the asker's lean">★</span> : <span key={d} className="g g-lean blank" aria-hidden="true" />
        ) : (
          <span key={d} className={`g g-${d}${trade.same.includes(d) ? " same" : ""}${cells?.[d] ? "" : " none"}`} title={`${DIM_LABEL[d]}: ${cells?.[d]?.text ?? "not given"}`}>
            {cells?.[d]?.glyph ? cells[d]!.glyph : <span className="gtext">{glyphOr(cells?.[d])}</span>}
          </span>
        ),
      )}
    </span>
  );
}

function OptionBody({ o, card, q, lean, leanText, trade, suggested }: { o: AskOption; card: Card; q: AskQuestion; lean?: string; leanText?: string; trade: Trade; suggested?: boolean }) {
  const isLean = !!lean && lean === o.code;
  const marks = q.panel.filter((r) => r.pick === o.code || r.pick === o.label);
  const cells = trade.rows[o.code ?? o.label];
  const label = o.label.replace(/\s*\(lean\)\s*$/i, "");
  const costSame = trade.same.includes("cost");
  const extra = [
    o.effort && cells?.effort?.glyph && saysMore(o.effort) ? ["Effort", o.effort] : undefined,
    o.blastRadius && cells?.blast?.glyph && saysMore(o.blastRadius) ? ["Blast radius", o.blastRadius] : undefined,
  ].filter(Boolean) as [string, string][];
  return (
    <span className="opt-body">
      {/* Operator 00:30: one top row, [CODE] label …… [risk effort ★]; the ★ is the one lean marker. */}
      <span className="opt-label">
        {o.code && <code className="okey">{o.code}</code>}
        <span className="opt-text"><Inline text={label} /></span>
        {suggested && <span className="sr-only">Suggested by the asker, not picked. Click to confirm.</span>}
        <Strip trade={trade} cells={cells} />
      </span>
      {o.description && <OptionDescription text={o.description} />}
      {o.cost && <span className={`opt-cost${costSame ? " same" : ""}`}><b>Cost</b> <Inline text={o.cost} /></span>}
      {extra.length > 0 && (
        <span className="opt-dims">
          {extra.map(([l, v]) => <span key={l}><b>{l}</b> {v}</span>)}
        </span>
      )}
      {isLean && leanReason(leanText) && <span className="opt-lean"><b>Why the lean</b> <Inline text={leanReason(leanText)} /></span>}
      {q.panel.length > 0 && (
        <span className="lens-row">
          {marks.length ? marks.map((m, i) => <LensMark key={i} read={m} id={`lens-${q.askName ?? "q"}-${o.code ?? i}-${i}`} />) : <span className="muted lens-none">No lens picked this</span>}
        </span>
      )}
    </span>
  );
}

/**
 * "◆ Lens picks this" as a button: hover or focus shows the lens's reasoning as a tooltip, which
 * stays while hovered and closes on Esc (S3). A click or Enter pins it as a small non-modal dialog
 * with a Close button (S4). The body is the Panel: line's text; a longer read needs parser support.
 */
type Rect = { left: number; right: number; top: number; bottom: number };
/**
 * Fence round, item 5: where a popover goes so it stays inside its column (the ask pane no longer
 * scrolls sideways, so a popover past its right edge was clipped). `dx` shifts it left (never past the
 * left edge); `above` flips it over its trigger when it would run past the bottom and fits above.
 */
export function fitPopover(pop: Rect, bounds: Rect, anchor: Rect, margin = 8): { dx: number; above: boolean } {
  const height = pop.bottom - pop.top;
  const over = pop.right - (bounds.right - margin);
  const dx = over > 0 ? -Math.min(over, Math.max(0, pop.left - (bounds.left + margin))) : 0;
  const above = pop.bottom > bounds.bottom - margin && anchor.top - height - margin >= bounds.top;
  return { dx, above };
}

const useIsoLayout = typeof window === "undefined" ? useEffect : useLayoutEffect;

export function LensMark({ read, id }: { read: PanelRead; id: string }) {
  const [hover, setHover] = useState(false);
  const [pinned, setPinned] = useState(false);
  const [fit, setFit] = useState({ dx: 0, above: false });
  const ref = useRef<HTMLSpanElement>(null);
  const pop = useRef<HTMLSpanElement>(null);
  const show = hover || pinned;
  useIsoLayout(() => {
    if (!show || !pop.current || !ref.current) return setFit({ dx: 0, above: false });
    // Measured from the unshifted position: reset, read, then place.
    pop.current.style.transform = "";
    const root = scrollRootOf(ref.current);
    const b = root ? root.getBoundingClientRect() : { left: 0, top: 0, right: innerWidth, bottom: innerHeight };
    setFit(fitPopover(pop.current.getBoundingClientRect(), b, ref.current.getBoundingClientRect()));
  }, [show, pinned]);
  useEffect(() => {
    if (!show) return;
    return pushEsc(() => {
      setPinned(false);
      setHover(false);
    });
  }, [show]);
  useEffect(() => {
    if (!pinned) return;
    const away = (e: Event) => ref.current && !ref.current.contains(e.target as Node) && setPinned(false);
    document.addEventListener("pointerdown", away);
    return () => document.removeEventListener("pointerdown", away);
  }, [pinned]);
  return (
    <span className="lens" ref={ref} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}>
      <button
        type="button"
        className="lens-mark"
        aria-describedby={id}
        onFocus={() => setHover(true)}
        onBlur={() => !pinned && setHover(false)}
        onClick={(e) => {
          e.preventDefault();
          setPinned(!pinned);
        }}
      >
        ◆ <b>{read.lens}</b> picks this
      </button>
      <span
        ref={pop}
        className={`lens-pop${pinned ? " pinned" : ""}${fit.above ? " above" : ""}`}
        style={fit.dx ? { transform: `translateX(${fit.dx}px)` } : undefined}
        role={pinned ? "dialog" : "tooltip"}
        aria-label={pinned ? `${read.lens}'s read` : undefined}
        id={id}
        hidden={!show}
      >
        <span className="lp-head"><b>{read.lens}</b> picks <code>{read.pick}</code></span>
        <span className="lp-h">Why</span>
        <span className="lp-body"><Inline text={read.why} /></span>
        <span className="lp-foot muted">From the fork's Panel: line. One line is all the ask file holds for this lens.</span>
        {pinned && <button type="button" className="lp-close" onClick={() => setPinned(false)}>Close</button>}
      </span>
    </span>
  );
}

/** The answer block exactly as it was recorded, shown as highlighted JSON. */
export function RecordedAnswer({ answer }: { answer: unknown }) {
  return <CodeBlock code={JSON.stringify(answer, null, 2) ?? ""} lang="json" />;
}

/** A dialogue turn: inline prose, or its blocks when the turn carries a fenced code block. */
export function TurnText({ text }: { text: string }) {
  return /^\s*(?:`{3,}|~{3,})/m.test(text) ? <Rich text={text} className="rich turn-md" /> : <Inline text={text} />;
}

/**
 * An option's description (fence round). One paragraph renders exactly as before, inline; anything
 * more (paragraphs, a fenced code block kept verbatim by the parser) goes through the block renderer.
 */
export function OptionDescription({ text }: { text: string }) {
  const bs = blocks(text);
  if (bs.length <= 1 && (bs[0]?.t ?? "p") === "p") return <span className="opt-desc"><Inline text={text} /></span>;
  return <span className="opt-desc opt-desc-blocks"><Rich text={text} className="rich" /></span>;
}

/**
 * A click inside an option's label selects the option, except (fence round) a click inside a code
 * block, or one that ends a text selection: reading or copying code never picks the option. The click
 * the label forwards to its own input (target: the input) always passes.
 */
export function ignoreOptionClick(target: Element | null, selection: string): boolean {
  if (!target || target.tagName === "INPUT") return false;
  return !!target.closest?.("pre") || selection.trim().length > 0;
}

/** Collect every value in a subtree, so un-picking a branch also un-picks what was chosen under it. */
function subtreeValues(o: AskOption): string[] {
  return [valueOf(o), ...(o.children ?? []).flatMap(subtreeValues)];
}

/**
 * IDE-304 item 3: an option input's click handlers. The click is NOT default-prevented. A prevented
 * click on a radio or checkbox makes the browser put the native checked state back after the handler
 * returns, which is after React's synchronous re-render, so the tick stayed empty until some later
 * render (a focus change, the next keystroke). Letting the native toggle stand, the browser and React
 * agree in the same frame: the pick is synchronous local state, with no request in between.
 */
export function optionInputHandlers(click: () => void): { onChange: () => void; onClick: (e: { preventDefault(): void }) => void } {
  return { onChange: () => {}, onClick: () => click() };
}

function OptionTree(p: InputProps & { options: AskOption[]; picks: string[]; name: string; onPicks: (v: string[], confirm: boolean) => void }) {
  const { q, options, picks, readOnly, suggestion } = p;
  const untouched = picks.length === 0;
  return (
    <div className="options" role={q.multiSelect ? "group" : "radiogroup"}>
      {options.map((o) => {
        const v = valueOf(o);
        const on = picks.includes(v);
        const suggested = untouched && !!suggestion && suggestion === v;
        const click = () => {
          if (readOnly) return;
          // Clicking the suggested option confirms it and moves on; it never clears it (hands-2 B1).
          if (suggested) return p.onPicks([v], true);
          const r = clickPicks(picks, v, q.multiSelect, options.flatMap(subtreeValues), subtreeValues(o));
          p.onPicks(r.picks, r.confirm);
        };
        return (
          <div key={v} className={`optwrap${on ? " on" : ""}${suggested ? " suggested" : ""}${p.lean === o.code ? " is-lean" : ""}${readOnly ? " readonly" : ""}`}>
            <label
              className="opt"
              title={suggested ? "Suggested by the asker · click to confirm" : undefined}
              onClick={(e) => {
                if (ignoreOptionClick(e.target as Element, typeof getSelection === "function" ? String(getSelection() ?? "") : "")) e.preventDefault();
              }}
            >
              <input
                type={q.multiSelect ? "checkbox" : "radio"}
                name={p.name}
                disabled={readOnly}
                checked={on}
                aria-checked={on}
                {...optionInputHandlers(click)}
              />
              <OptionBody o={o} card={p.card} q={q} lean={p.lean} leanText={p.leanText} trade={p.trade} suggested={suggested} />
            </label>
            {on && o.children && (
              <div className="nested">
                {/* S5: each level has its own radio group, so a picked parent stays checked. */}
                <OptionTree {...p} options={o.children} name={`${p.name}/${v}`} suggestion={undefined} />
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function RankInput(p: InputProps & { value: string[] | undefined }) {
  const { q, value, onValue, readOnly } = p;
  const order = value ?? q.options.map(valueOf);
  const move = (i: number, d: number) => {
    const next = [...order];
    const [x] = next.splice(i, 1);
    next.splice(i + d, 0, x);
    onValue(next);
  };
  return (
    <div className="rank">
      <ol className="options">
        {order.map((v, i) => {
          const o = q.options.find((x) => valueOf(x) === v)!;
          return (
            <li key={v} className="opt rank-row">
              <span className="rank-n">{i + 1}</span>
              <OptionBody o={o} card={p.card} q={q} lean={p.lean} leanText={p.leanText} trade={p.trade} />
              {!readOnly && (
                <span className="rank-btns">
                  <button className="btn" aria-label={`Move ${o.label} up`} disabled={i === 0} onClick={() => move(i, -1)}>↑</button>
                  <button className="btn" aria-label={`Move ${o.label} down`} disabled={i === order.length - 1} onClick={() => move(i, 1)}>↓</button>
                </span>
              )}
            </li>
          );
        })}
      </ol>
      {!readOnly && !value && <button className="btn" onClick={() => onValue(order)}>Use this order as my ranking</button>}
      {!readOnly && value && <p className="muted">Ranking set. Move items to change it.</p>}
    </div>
  );
}

/**
 * Who answered, with a relay made visible: an answer a seat RECORDED for the operator says so in
 * plain words, so the operator can spot a relay it never gave.
 */
/**
 * ASKWITHDRAW: the answer bar of a withdrawn ask. No controls; the operator's unsent picks and notes
 * on it (unsent.ts, under the open form's key) are listed as kept, with Copy and Forget, so a
 * withdrawal mid-draft never drops them without a word. A saved draft the withdrawal discarded
 * (`withdrawn-draft-of`) is named when it was the operator's.
 */
export function WithdrawnBar({ ask, w, seed }: { ask: StoredAsk; w: Withdrawn; seed?: { copy?: "ok" | "failed"; confirming?: boolean } }) {
  const ref = askRef(ask);
  const [kept, setKept] = useState(() => loadUnsent(unsentKey(ref, false)));
  // S-2: "Copied." only once the clipboard took the text; otherwise say so and show it to select by hand.
  // P13: every step is unsent.ts barStep's; only "yes" clears the kept copy.
  const [bar, setBar] = useState<BarState>({ ...(seed?.copy ? { copy: seed.copy } : {}), confirming: !!seed?.confirming });
  const { copy, confirming } = bar;
  const dispatch = (ev: BarEvent) => {
    const r = barStep(bar, ev);
    if (r.clear) {
      clearUnsent(unsentKey(ref, false));
      setKept(undefined);
    }
    setBar(r.state);
  };
  const lines = kept ? keptDraftLines(ask, kept) : [];
  const all = lines.join("\n");
  const ownDraft = !!w.draftOf && isOperatorName(w.draftOf);
  const doCopy = () => void copyText(all).then((ok) => dispatch({ copied: ok }));
  return (
    <>
      <h3>Withdrawn · revision {ask.header.revision}</h3>
      <p className="muted">This ask was {withdrawnWords(w)}. Nobody is waiting on an answer, and nothing here can be sent.</p>
      {lines.length > 0 ? (
        <div className="chip warn notice kept-draft" role="status">
          <p>
            You were answering this ask when it was withdrawn. Nothing was sent.{ownDraft ? " The draft saved in the file was discarded;" : ""} {kept ? keptSentence(kept) : ""}
          </p>
          <ul>{lines.map((l, i) => <li key={i}>{l}</li>)}</ul>
          {copy === "failed" && <pre className="kept-copy" tabIndex={0}>{all}</pre>}
          {confirming ? (
            <p className="actions">
              <span>{forgetWords(copy === "ok")}</span>{" "}
              <button className="btn quiet" onClick={() => dispatch("yes")}>Yes, forget them</button>
              <button className="btn quiet" onClick={() => dispatch("keep")}>Keep them</button>
            </p>
          ) : (
            <p className="actions">
              <button className="btn quiet" onClick={doCopy}>Copy</button>
              <button className="btn quiet" onClick={() => dispatch("forget")}>Forget them…</button>
              {copy && <span className="muted"> {copy === "ok" ? "Copied." : "Copy failed; select the lines below by hand."}</span>}
            </p>
          )}
        </div>
      ) : ownDraft ? (
        <p className="chip warn notice" role="status">Your saved draft on this ask was discarded when it was withdrawn. Nothing was sent.</p>
      ) : null}
    </>
  );
}

export function AnsweredBy({ answer }: { answer?: AskAnswer }) {
  if (!answer) return null;
  const relayer = relayerOf(answer);
  return (
    <p className="answered-by">
      by <b>{answer.answeredBy || "unknown"}</b>
      {grantClassOf(answer) && <> <span className="chip quiet grant" title="The grant class the answering manager gave this answer">class {grantClassOf(answer)}</span></>}
      {relayer ? (
        <span className="chip warn relay" title={`${relayer} recorded this as the operator's answer${answer.note ? `: ${answer.note}` : ""}`}>
          relayed by {relayer}
        </span>
      ) : answer.answeredVia ? (
        <span className="muted"> via {answer.answeredVia}</span>
      ) : null}
      <span className="sr-only">{answeredByText(answer)}</span>
    </p>
  );
}

/** The tray: the operator's own drafts only (by author — a seat's relay draft is the relayer's). */
export function trayDrafts<T extends ParsedAsk>(asks: T[]): T[] {
  return asks.filter((a) => a.draft && draftAuthor(a.draft) === "operator");
}
