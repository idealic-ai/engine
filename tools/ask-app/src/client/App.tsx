import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  answeredByText,
  cardFor,
  draftAuthor,
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
} from "../lib/format.ts";
import {
  acceptAll,
  askRef,
  askRow,
  buildAnswers,
  clickPicks,
  forkLabel,
  groupRows,
  isSettled,
  leanCodeFor,
  leanFor,
  nextFork,
  parseHash,
  resolveFork,
  saysMore,
  sortRows,
  suggestionsFor,
  tradeoff,
  DIM_LABEL,
  type Dim,
  type GroupBy,
  type Row,
  type StoredAsk,
  type Values,
} from "./model.ts";
import { briefFor, isLocalOnly, paneTrust, proofLinks, proofOriginsFromEnv, type Brief, type Trust } from "./related.ts";
import { Inline, PaneContext, Rich, TicketLink, inlineTokens } from "./rich.tsx";
import { Grip, Split, SIDE_MAX, SIDE_MIN, SIDE_SLIM, clampRatio, clampSide, sideDefault, useStoredNumber } from "./layout.tsx";
import { pushEsc } from "./esc.ts";

export { ticketKeys };
type Filter = "open" | "drafts" | "settled" | "all";
type Pane = { url: string; label: string; source: Brief["source"] | "link"; trust: Trust };
type Theme = "auto" | "light" | "dark";

const valueOf = (o: AskOption) => o.code ?? o.label;
const token = () => document.querySelector('meta[name="ask-token"]')?.getAttribute("content") ?? "";
/** Proof hosts besides loopback, set at build time (VITE_PROOF_ORIGINS); loopback needs no entry. */
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

async function post(url: string, body: unknown): Promise<{ status: number; json: any }> {
  const r = await fetch(url, { method: "POST", headers: { "content-type": "application/json", "x-ask-token": token() }, body: JSON.stringify(body) });
  return { status: r.status, json: await r.json().catch(() => ({})) };
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
  const [filter, setFilter] = useState<Filter>(() => (store.get("askclient.filter") as Filter) || "open");
  const [groupBy, setGroupBy] = useState<GroupBy>(() => (store.get("askclient.group") as GroupBy) || "none");
  const [hash, setHash] = useState(() => parseHash(location.hash));
  const [selected, setSelected] = useState<string | undefined>(() => parseHash(location.hash).ref);
  const [live, setLive] = useState(false);
  const [batchResult, setBatchResult] = useState("");
  const [sending, setSending] = useState(false);
  const [pane, setPane] = useState<Pane | null>(null);
  const [theme, setTheme] = useState<Theme>(() => (store.get("askclient.theme") as Theme) || "auto");
  const [dragging, setDragging] = useState(false);
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
    const es = new EventSource("/api/events");
    es.addEventListener("hello", () => setLive(true));
    es.addEventListener("change", () => load());
    es.onerror = () => setLive(false);
    return () => es.close();
  }, [load]);

  useEffect(() => {
    const h = () => {
      const p = parseHash(location.hash);
      setHash(p);
      if (p.ref) setSelected(p.ref);
    };
    addEventListener("hashchange", h);
    return () => removeEventListener("hashchange", h);
  }, []);

  useEffect(() => {
    if (theme === "auto") delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = theme;
    store.set("askclient.theme", theme === "auto" ? null : theme);
  }, [theme]);
  useEffect(() => store.set("askclient.filter", filter), [filter]);
  useEffect(() => store.set("askclient.group", groupBy), [groupBy]);

  const shown = useMemo(() => visibleAsks(asks), [asks]);
  const hiddenCount = asks.length - shown.length;
  const drafts = trayDrafts(shown);
  const now = Date.now();
  const rows = useMemo(() => sortRows(shown.map((a) => askRow(a, now))), [shown]); // eslint-disable-line react-hooks/exhaustive-deps
  const inFilter = rows.filter((r) =>
    filter === "all" ? true : filter === "drafts" ? r.draft : filter === "settled" ? r.status === "answered" || r.status === "declined" : r.status === "open",
  );
  const count = (f: Filter) =>
    f === "all" ? rows.length : f === "drafts" ? rows.filter((r) => r.draft).length : f === "settled" ? rows.filter((r) => r.status !== "open").length : rows.filter((r) => r.status === "open").length;
  const currentRef = asks.some((a) => askRef(a) === selected) ? selected : inFilter[0]?.ref;
  const current = asks.find((a) => askRef(a) === currentRef);
  const brief = current ? briefFor(current) : undefined;

  // A brief opens on its own beside the ask, unless it was closed on this ask before. Only a trusted
  // host opens by itself (M2): another host's page waits for a click and is not fetched before it.
  useEffect(() => {
    if (detail.current) detail.current.scrollTop = 0;
    if (!current) return setPane(null);
    const b = briefFor(current);
    const closed = store.get(`askclient.brief.closed.${askRef(current)}`) === "1";
    const p = b ? paneFor(b.url, b.source === "brief" ? "Brief" : "Linked proof", b.source) : null;
    setPane(p && !closed && p.trust === "auto" ? p : null);
  }, [currentRef]); // eslint-disable-line react-hooks/exhaustive-deps

  const pick = (ref: string) => {
    setSelected(ref);
    setHash({ ref });
    history.replaceState(null, "", `#${ref}`);
  };
  const openInPane = useCallback((url: string, label: string) => setPane(paneFor(url, label, "link")), []);
  const closePane = () => {
    if (current && pane && brief && pane.url === brief.url) store.set(`askclient.brief.closed.${askRef(current)}`, "1");
    setPane(null);
  };
  const toggleBrief = () => {
    if (!current || !brief) return;
    if (pane) closePane();
    else {
      store.set(`askclient.brief.closed.${askRef(current)}`, null);
      setPane(paneFor(brief.url, brief.source === "brief" ? "Brief" : "Linked proof", brief.source));
    }
  };
  const setForkHash = useCallback(
    (label: string) => {
      if (!currentRef) return;
      history.replaceState(null, "", `#${currentRef}/${label}`);
    },
    [currentRef],
  );

  async function sendBatch() {
    setSending(true);
    setBatchResult("");
    try {
      const { status, json } = await post("/api/send", { refs: drafts.map(askRef) });
      if (status !== 200) return setBatchResult(`Error: ${json.error}`);
      const pushes = (json.pushes as { seat: string; refs: string[]; delivery: { status: string; reason?: string } }[])
        .map((p) => `${p.seat}: ${p.delivery.status === "delivered" ? "queued, not read yet" : `${p.delivery.status}${p.delivery.reason ? ` (${p.delivery.reason})` : ""}`} — ${p.refs.length} answer${p.refs.length === 1 ? "" : "s"} in one message`)
        .join(" · ");
      const refused = (json.refused as { ref: string; error: string }[]).map((r) => `${r.ref}: ${r.error}`).join(" · ");
      setBatchResult(`Sent ${json.settled.length}. ${pushes}${refused ? ` · Refused: ${refused}` : ""}`);
      load();
    } finally {
      setSending(false);
    }
  }

  const waiting = rows.filter((r) => r.waitingOnYou).length;
  const slim = sideW < SIDE_SLIM;
  return (
    <PaneContext.Provider value={openInPane}>
      <div className={`app${dragging ? " dragging" : ""}`}>
        <header className="top">
          <h1>Asks</h1>
          <span className="sub">{waiting} waiting on you</span>
          <span className="spacer" />
          <span className={`live ${live ? "on" : ""}`} title={root}>{live ? "Live" : "Offline"}</span>
          <button className="iconbtn" onClick={() => setTheme(theme === "auto" ? "dark" : theme === "dark" ? "light" : "auto")} aria-label={`Theme: ${theme}. Change theme`}>
            {theme === "dark" ? "☾ Dark" : theme === "light" ? "☀ Light" : "◐ Auto"}
          </button>
        </header>
        {drafts.length > 0 && (
          <div className="tray" role="region" aria-label="Drafts ready to send">
            <span>
              <b>{drafts.length}</b> draft{drafts.length === 1 ? "" : "s"} saved in {drafts.length === 1 ? "its file" : "their files"}, not sent:{" "}
              {drafts.map((d) => (
                <button key={askRef(d)} className="linkish" onClick={() => pick(askRef(d))}>{askRef(d)}</button>
              ))}
            </span>
            <button className="btn primary" disabled={sending} onClick={sendBatch}>Send batch · one message per seat</button>
          </div>
        )}
        {batchResult && <p className="tray-result" role="status">{batchResult}</p>}
        <div className="desk" ref={desk} style={{ gridTemplateColumns: `${sideW}px 8px minmax(0, 1fr)` }}>
          <nav className={`side${slim ? " slim" : ""}`} id="asklist" aria-label="Asks">
            <div className="side-tools">
              {slim ? (
                <select aria-label="Show" value={filter} onChange={(e) => setFilter(e.target.value as Filter)} id="filter-slim">
                  {(["open", "drafts", "settled", "all"] as Filter[]).map((f) => <option key={f} value={f}>{f === "open" ? "Open" : f === "drafts" ? "Drafts" : f === "settled" ? "Settled" : "All"} {count(f)}</option>)}
                </select>
              ) : (
                <>
                  <div className="seg" role="group" aria-label="Show">
                    {(["open", "drafts", "settled", "all"] as Filter[]).map((f) => (
                      <button key={f} aria-pressed={filter === f} onClick={() => setFilter(f)}>
                        {f === "open" ? "Open" : f === "drafts" ? "Drafts" : f === "settled" ? "Settled" : "All"} <span className="n">{count(f)}</span>
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
            {inFilter.length === 0 && <p className="muted pad">No {filter === "all" ? "" : filter} asks.</p>}
            {groupRows(inFilter, slim ? "none" : groupBy).map((g) => (
              <section key={g.name || "all"} className="group" aria-label={g.name || undefined}>
                {g.name && <h2 className="group-name">{g.name} <span className="n">{g.rows.length}</span></h2>}
                <ul className="rows">
                  {g.rows.map((r) => (
                    <li key={r.ref}>
                      <AskRowButton r={r} slim={slim} current={r.ref === currentRef} onPick={() => pick(r.ref)} />
                    </li>
                  ))}
                </ul>
              </section>
            ))}
            {hiddenCount > 0 && !slim && <p className="muted pad">{hiddenCount} ask{hiddenCount === 1 ? " is" : "s are"} hidden until the ask {hiddenCount === 1 ? "it depends" : "they depend"} on is settled.</p>}
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
              <main className="detail" ref={detail}>
                {current ? (
                  <AskDetail
                    key={askRef(current) + current.header.revision}
                    ask={current}
                    all={asks}
                    onChanged={load}
                    brief={brief}
                    paneOpen={!!pane && !!brief && pane.url === brief.url}
                    onToggleBrief={toggleBrief}
                    focusFork={hash.fork}
                    onForkHash={setForkHash}
                  />
                ) : (
                  <p className="muted">Nothing selected.</p>
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
function Plain({ text }: { text: string }) {
  return <>{inlineTokens(text).map((t, i) => (t.t === "code" ? <code key={i} className="ic">{t.v}</code> : <span key={i}>{t.t === "text" ? t.v : t.t === "ticket" ? t.key : t.label}</span>))}</>;
}

function AskRowButton({ r, current, onPick, slim }: { r: Row; current: boolean; onPick: () => void; slim: boolean }) {
  const done = r.total - r.left;
  const left = r.status === "open" ? `${r.left} of ${r.total} left` : r.status;
  return (
    <button className="row" aria-current={current} onClick={onPick} title={slim ? `${r.title} · ${r.seat} · ${left}` : undefined}>
      <span className="row-top">
        {r.high && <span className="imp" title="High importance" aria-label="High importance">!</span>}
        <span className="row-title"><Plain text={r.title} /></span>
      </span>
      <span className="row-meta">
        {!slim && <span className="seat">{r.seat}</span>}
        {!slim && <span className="age" title={new Date(r.created).toLocaleString()}>{r.age}</span>}
        <span className={`left${r.left === 0 ? " zero" : ""}`}>{left}</span>
      </span>
      {!slim && r.total > 0 && (
        <span className="bar" aria-hidden="true"><span style={{ width: `${(done / r.total) * 100}%` }} /></span>
      )}
      {!slim && (r.waitingOnYou || r.reserved || r.draft || r.seatDraft) && (
        <span className="marks">
          {r.waitingOnYou && <span className="mk you">needs you</span>}
          {r.reserved && r.reserved !== "operator" && <span className="mk">reserved · {r.reserved}</span>}
          {r.reserved === "operator" && <span className="mk res" title="Only you may answer; seats may forward it">reserved for you</span>}
          {r.draft && <span className="mk draft">draft</span>}
          {r.seatDraft && <span className="mk">{r.seatDraft} draft</span>}
        </span>
      )}
    </button>
  );
}

// ── the related pane ─────────────────────────────────────

type Probe = { state: "checking" | "ok" | "silent" | "notfound" | "noframe" | "error"; code?: number };

/**
 * One HEAD request per pane open (N5): reachable, 404, or a framing refusal. A failed request cannot
 * tell "down" from "does not allow this check", so it is reported as not answering, with Load anyway.
 */
async function probePage(url: string): Promise<Probe> {
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

export function RelatedPane({ pane, onClose }: { pane: Pane; onClose: () => void }) {
  const [allowed, setAllowed] = useState(pane.trust === "auto");
  const [probe, setProbe] = useState<Probe>({ state: "checking" });
  const [force, setForce] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [slow, setSlow] = useState(false);
  const [copied, setCopied] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    if (!allowed || pane.trust === "refuse") return;
    let live = true;
    setProbe({ state: "checking" });
    setLoaded(false);
    setSlow(false);
    setForce(false);
    probePage(pane.url).then((p) => live && setProbe(p));
    const t = setTimeout(() => live && setSlow(true), 9000);
    return () => {
      live = false;
      clearTimeout(t);
    };
  }, [pane.url, pane.trust, attempt, allowed]);
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
  const framed = allowed && pane.trust !== "refuse" && (force || probe.state === "ok");
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
            <iframe title={pane.label} src={pane.url} onLoad={() => setLoaded(true)} referrerPolicy="no-referrer" sandbox={PANE_SANDBOX} />
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
  return { values, text, note: src?.note ?? "" };
}

export function AskDetail({
  ask, all, onChanged, brief, paneOpen, onToggleBrief, focusFork, onForkHash,
}: { ask: StoredAsk; all: StoredAsk[]; onChanged: () => void; brief?: Brief; paneOpen?: boolean; onToggleBrief?: () => void; focusFork?: string; onForkHash?: (label: string) => void }) {
  const init = useMemo(() => initialValues(ask), [ask]);
  const [values, setValues] = useState<Values>(init.values);
  const [text, setText] = useState<Record<string, string>>(init.text);
  const [note, setNote] = useState(init.note);
  const [result, setResult] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");

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
  const open = ask.header.status === "open";
  const suggestions = open ? suggestionsFor(ask, values) : {};
  const visibleSuggestions = ask.questions.flatMap((q, i) => {
    const k = questionKey(q, i);
    return visible.includes(q) && suggestions[k] ? [{ label: forkLabel(q, i), code: suggestions[k] }] : [];
  });
  const dep = ask.header.dependsOn?.trim();
  const depMissing = dep && !all.some((a) => a.header.id === dep);
  const depDeclined = dependsOnDeclined(ask, all);
  const headerTickets = [...(ask.header.tickets ?? "").matchAll(/\b([A-Z][A-Z0-9]{1,9}-\d{1,6})\b/g)].map((m) => m[1]);
  const proofs = proofLinks(ask);
  const row = askRow(ask);
  const forkId = (i: number) => `fork-${ask.header.id}-${forkLabel(ask.questions[i], i)}`;

  const scrollToFork = (i: number | undefined) => {
    const el = i === undefined ? document.getElementById(`answerbar-${ask.header.id}`) : document.getElementById(forkId(i));
    el?.scrollIntoView({ block: "start", behavior: "smooth" });
    if (i !== undefined) onForkHash?.(forkLabel(ask.questions[i], i));
  };

  // #Q2, #q2 and #f2 open that fork; an unknown one says so and shows the first.
  useEffect(() => {
    if (!focusFork) return setNotice("");
    const i = resolveFork(ask, focusFork);
    if (i === undefined) {
      setNotice(`No fork “${focusFork}” in this ask; showing ${forkLabel(ask.questions[0] ?? {}, 0)}.`);
      document.getElementById(forkId(0))?.scrollIntoView({ block: "start" });
    } else {
      setNotice("");
      document.getElementById(forkId(i))?.scrollIntoView({ block: "start" });
    }
  }, [focusFork, ask]); // eslint-disable-line react-hooks/exhaustive-deps

  async function act(kind: "draft" | "draft-decline" | "discard" | "send-now") {
    setBusy(true);
    setResult("");
    try {
      if (kind === "discard") {
        const r = await post("/api/discard", { seat: ask.seat, id: ask.header.id });
        setResult(r.status === 200 ? "Draft discarded." : `Error: ${r.json.error}`);
        return onChanged();
      }
      const base = { seat: ask.seat, id: ask.header.id, expectedRevision: Number(ask.header.revision), note: note || undefined };
      const body = kind === "draft-decline" ? { ...base, decline: note.trim() } : { ...base, answers };
      const r = await post("/api/draft", body);
      if (r.status === 409) return setResult(`Not saved: the ask moved (now revision ${r.json.revision}). Read the current state before answering again.`);
      if (r.status !== 200) return setResult(`Error: ${r.json.error}`);
      if (kind === "send-now") {
        const s = await post("/api/send", { refs: [askRef(ask)] });
        const p = s.json.pushes?.[0];
        if (s.json.refused?.length) setResult(`Refused: ${s.json.refused[0].error}`);
        else if (p) setResult(p.delivery.status === "delivered" ? `Queued at ${p.seat}, not read yet. It turns "read" when the seat runs engine ask read.` : `Saved, but ${p.delivery.status} (${p.delivery.reason ?? ""}). The asker's /next picks it up from the file.`);
      } else setResult("Draft saved in the file. Nothing has been sent: use Send batch at the top.");
      onChanged();
    } finally {
      setBusy(false);
    }
  }

  const picked = Object.keys(answers).filter((k) => !k.endsWith(".other")).length;
  const nothing = Object.keys(answers).length === 0;
  return (
    <article className="ask">
      <header className="ask-head">
        <p className="ask-route">
          <span className="seat">{ask.header.from || ask.seat}</span> <span className="muted">→ {ask.header.to}</span>
          {row.age && <span className="muted"> · {row.age} ago</span>}
          {row.high && <span className="chip danger">! High importance</span>}
          {ask.header["reserved-for"] && <span className="chip" title="Only this party may answer; others may forward it">reserved for {ask.header["reserved-for"]}</span>}
          <span className="chip quiet">{ask.header.status === "open" ? `${row.left} of ${row.total} left` : ask.header.status}</span>
        </p>
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
        {visibleSuggestions.length > 0 && (
          <div className="suggest-bar">
            <p>
              <b>Suggested picks</b> are the asker's leans, shown dashed. They are not your answer: nothing is saved or sent until you click. Click a suggested option to confirm it and move to the next fork.
            </p>
            <button className="btn" onClick={() => setValues(acceptAll(ask, values))}>
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
              readOnly={!open}
            />
            {/* Prose written after a fork's options, before the next heading, sits between the cards. */}
            <ForkProse text={q.proseAfter} between />
          </Fragment>
        );
      })}

      <section className="answerbar" id={`answerbar-${ask.header.id}`}>
        {isSettled(ask) && (
          <>
            <h3>{ask.header.status === "declined" ? "Declined" : "Answered"} · revision {ask.header.revision}</h3>
            <AnsweredBy answer={ask.answer} />
            {ask.answer?.note && <p className="answer-note"><Inline text={ask.answer.note} /></p>}
            <Life h={ask.header} />
            <details>
              <summary>Recorded answer block</summary>
              <pre className="code">{JSON.stringify(ask.answer, null, 2)}</pre>
            </details>
          </>
        )}
        {open && (
          <>
            <p className="muted sends">
              {nothing ? "Nothing picked yet. Suggestions are not sent." : `Saving or sending sends ${picked} fork${picked === 1 ? "" : "s"} you picked${Object.keys(answers).length > picked ? " and your notes" : ""}; forks you did not touch stay open.`}
            </p>
            <label className="field-label" htmlFor={`note-${ask.header.id}`}>Note to the asker</label>
            <textarea id={`note-${ask.header.id}`} rows={2} placeholder="Optional. To decline, write the reason here." value={note} onChange={(e) => setNote(e.target.value)} />
            <p className="actions">
              <button className="btn primary" disabled={busy || nothing} onClick={() => act("draft")}>{ask.draft ? "Update draft" : "Save draft"}</button>
              <button className="btn" disabled={busy || nothing} onClick={() => act("send-now")}>Send this one now</button>
              <button className="btn" disabled={busy || !note.trim()} title="Declining needs a reason: write it in the note" onClick={() => act("draft-decline")}>Draft a decline</button>
              {ask.draft && <button className="btn" disabled={busy} onClick={() => act("discard")}>Discard draft</button>}
            </p>
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
        <AskDetails ask={ask} />
      </section>
    </article>
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

      <h3 className="fork-q"><Inline text={q.title} /></h3>
      {index === 0 && ask.preamble.trim() && <Rich text={ask.preamble.trim()} className="rich preamble" />}
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
          {choice && q.options.length > 1 && <TradeLegend trade={trade} />}
          <Input q={q} card={card} lean={leanCode} leanText={lean?.text} trade={trade} radioBase={`${askRef(ask)}#${k}`} value={p.value} suggestion={p.suggestion} onValue={p.onValue} onConfirm={p.onConfirm} readOnly={p.readOnly} />
        </>
      )}
      {lean && !leanCode && (
        <p className="lean-line"><b>Lean:</b> <Inline text={lean.text} />{card.counter && <> <b>Strongest counter:</b> <Inline text={card.counter} /></>}</p>
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
      {trade.dims.map((d) => (
        <span key={d} className={trade.same.includes(d) ? "same" : undefined}>{d === "lean" ? LEGEND.lean : `${DIM_LABEL[d]} ${LEGEND[d]}`}</span>
      ))}
      <span className="muted">faded: the same for every option · – not given</span>
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
  const show = trade.dims.filter((d) => d !== "cost");
  return (
    <span className="strip" aria-label={show.map((d) => `${DIM_LABEL[d]}: ${cells?.[d]?.text ?? "not given"}`).join("; ")}>
      {show.map((d) =>
        d === "lean" ? (
          cells?.lean ? <span key={d} className="g g-lean" title="The asker's lean">★</span> : <span key={d} className="g g-lean blank" aria-hidden="true">☆</span>
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
      <span className="opt-label">
        {o.code && <code className="okey">{o.code}</code>}
        <span className="opt-text"><Inline text={label} /></span>
        {isLean && <span className="rec">Recommended</span>}
        {suggested && <span className="sugg">Suggested · click to confirm</span>}
        <Strip trade={trade} cells={cells} />
      </span>
      {o.description && <span className="opt-desc"><Inline text={o.description} /></span>}
      {o.cost && <span className={`opt-cost${costSame ? " same" : ""}`}><b>Cost</b> <Inline text={o.cost} /></span>}
      {extra.length > 0 && (
        <span className="opt-dims">
          {extra.map(([l, v]) => <span key={l}><b>{l}</b> {v}</span>)}
        </span>
      )}
      {isLean && leanText && <span className="opt-lean"><b>Why the lean</b> <Inline text={leanText} /></span>}
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
export function LensMark({ read, id }: { read: PanelRead; id: string }) {
  const [hover, setHover] = useState(false);
  const [pinned, setPinned] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);
  const show = hover || pinned;
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
      <span className={`lens-pop${pinned ? " pinned" : ""}`} role={pinned ? "dialog" : "tooltip"} aria-label={pinned ? `${read.lens}'s read` : undefined} id={id} hidden={!show}>
        <span className="lp-head"><b>{read.lens}</b> picks <code>{read.pick}</code></span>
        <span className="lp-h">Why</span>
        <span className="lp-body"><Inline text={read.why} /></span>
        <span className="lp-foot muted">From the fork's Panel: line. One line is all the ask file holds for this lens.</span>
        {pinned && <button type="button" className="lp-close" onClick={() => setPinned(false)}>Close</button>}
      </span>
    </span>
  );
}

/** Collect every value in a subtree, so un-picking a branch also un-picks what was chosen under it. */
function subtreeValues(o: AskOption): string[] {
  return [valueOf(o), ...(o.children ?? []).flatMap(subtreeValues)];
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
          <div key={v} className={`optwrap${on ? " on" : ""}${suggested ? " suggested" : ""}${p.lean === o.code ? " is-lean" : ""}`}>
            <label className="opt">
              <input
                type={q.multiSelect ? "checkbox" : "radio"}
                name={p.name}
                disabled={readOnly}
                checked={on || suggested}
                onChange={() => {}}
                onClick={(e) => {
                  e.preventDefault();
                  click();
                }}
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
export function AnsweredBy({ answer }: { answer?: AskAnswer }) {
  if (!answer) return null;
  const relayer = relayerOf(answer);
  return (
    <p className="answered-by">
      by <b>{answer.answeredBy || "unknown"}</b>
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
