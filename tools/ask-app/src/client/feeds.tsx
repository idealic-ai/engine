/**
 * The Proofs and Broadcasts tabs. Proofs: published proof pages, newest first; one click opens a page
 * in the split pane beside the ask. Broadcasts: the director's notices, newest first, with their text,
 * how many of their audience acked, and whether they are still in force. Both are read-only.
 */
import { useCallback, useEffect, useState } from "react";
import type { Proof, ProofList } from "../lib/proofs.ts";
import type { Broadcast } from "../lib/broadcasts.ts";
import { ageOf } from "./model.ts";
import { Rich } from "./rich.tsx";

const token = () => (typeof document === "undefined" ? "" : document.querySelector('meta[name="ask-token"]')?.getAttribute("content") ?? "");

/** Acks counted against the audience: a seat outside the audience that acked does not raise the count. */
export function ackSummary(b: Pick<Broadcast, "acks" | "audience">): { acked: number; of: number; missing: string[] } {
  const acked = new Set(b.acks);
  const of = b.audience.length;
  const missing = b.audience.filter((s) => !acked.has(s));
  return { acked: of - missing.length, of, missing };
}

/** The line a broadcast is known by in a list: its text's first sentence, or its id. */
export function broadcastHeadline(b: Pick<Broadcast, "text" | "id">): string {
  const first = b.text.split(/\n/).find((l) => l.trim()) ?? "";
  const s = first.match(/^(.{1,140}?[.!?:])(\s|$)/)?.[1] ?? first.slice(0, 140);
  return s.trim() || b.id;
}

export function useProofs(enabled: boolean) {
  const [list, setList] = useState<ProofList | undefined>();
  const [busy, setBusy] = useState(false);
  const load = useCallback(async (fresh = false) => {
    setBusy(true);
    try {
      const r = await fetch(`/api/proofs${fresh ? "?fresh" : ""}`, { headers: { "x-ask-token": token() } });
      const j = await r.json();
      setList(r.ok ? j : { ok: false, proofs: [], error: j.error ?? `HTTP ${r.status}`, at: new Date().toISOString(), total: 0 });
    } catch {
      setList({ ok: false, proofs: [], error: "the app server did not answer", at: new Date().toISOString(), total: 0 });
    } finally {
      setBusy(false);
    }
  }, []);
  useEffect(() => {
    if (enabled && !list) load();
  }, [enabled, list, load]);
  return { list, busy, reload: () => load(true) };
}

export function useBroadcasts(enabled: boolean) {
  const [list, setList] = useState<Broadcast[] | undefined>();
  const [error, setError] = useState("");
  const load = useCallback(async () => {
    try {
      const r = await fetch("/api/broadcasts", { headers: { "x-ask-token": token() } });
      const j = await r.json();
      if (!r.ok) throw new Error(j.error ?? `HTTP ${r.status}`);
      setList(j.broadcasts);
      setError("");
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);
  useEffect(() => {
    if (enabled) load();
  }, [enabled, load]);
  return { list, error, reload: load };
}

export function ProofRows({ list, busy, onOpen, onReload, current, slim, now = Date.now() }: { list?: ProofList; busy: boolean; onOpen: (p: Proof) => void; onReload: () => void; current?: string; slim: boolean; now?: number }) {
  if (!list) return <p className="muted pad">Loading proof pages…</p>;
  return (
    <>
      <div className="feed-tools">
        <span className="muted">{list.ok ? `${list.total} page${list.total === 1 ? "" : "s"}` : "Proof store not reachable"}</span>
        <button className="linkish" onClick={onReload} disabled={busy}>{busy ? "Refreshing…" : "Refresh"}</button>
      </div>
      {!list.ok && <p className="pad feed-error" role="alert">{list.error || "no reason given"}</p>}
      {list.ok && list.total === 0 && <p className="muted pad">No proof pages in the store{list.bucket ? ` (${list.bucket}/${list.prefix ?? ""})` : ""}.</p>}
      <ul className="rows">
        {list.proofs.map((p) => (
          <li key={p.key}>
            <button className="row" aria-current={p.url === current} onClick={() => onOpen(p)} title={slim ? p.title : p.url}>
              <span className="row-top"><span className="row-title">{p.title}</span></span>
              <span className="row-meta">
                {!slim && p.owner && <span className="seat">{p.owner}</span>}
                <span className="age" title={p.modified}>{ageOf(Date.parse(p.modified), now)}</span>
              </span>
            </button>
          </li>
        ))}
      </ul>
    </>
  );
}

export function BroadcastRows({ list, error, current, onPick, slim }: { list?: Broadcast[]; error: string; current?: string; onPick: (id: string) => void; slim: boolean }) {
  if (error) return <p className="muted pad">Broadcasts could not be read: {error}</p>;
  if (!list) return <p className="muted pad">Loading broadcasts…</p>;
  if (!list.length) return <p className="muted pad">No broadcasts.</p>;
  return (
    <ul className="rows">
      {list.map((b) => {
        const a = ackSummary(b);
        return (
          <li key={b.id}>
            <button className="row" aria-current={b.id === current} onClick={() => onPick(b.id)}>
              <span className="row-top"><span className="row-title">{broadcastHeadline(b)}</span></span>
              <span className="row-meta">
                {!slim && <span className="seat">{b.from}</span>}
                {b.inForce && <span className="mk you">in force</span>}
                <span className="left">{a.acked} of {a.of} acked</span>
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

/** The broadcasts in full: newest first, the text inline, the acks over the audience, and in force. */
export function BroadcastFeed({ list, error, current, now = Date.now() }: { list?: Broadcast[]; error: string; current?: string; now?: number }) {
  useEffect(() => {
    if (current) document.getElementById(`bc-${current}`)?.scrollIntoView({ block: "start" });
  }, [current]);
  if (error) return <p className="muted">Broadcasts could not be read: {error}</p>;
  if (!list) return <p className="muted">Loading broadcasts…</p>;
  const inForce = list.filter((b) => b.inForce).length;
  const missing = !!current && !list.some((b) => b.id === current);
  return (
    <section className="feed" aria-label="Broadcasts">
      <h2 className="feed-title">Broadcasts <span className="n">{list.length}, {inForce} in force</span></h2>
      {missing && <p className="chip warn notice" role="status">No broadcast “{current}”. The list still works.</p>}
      {list.map((b) => {
        const a = ackSummary(b);
        return (
          <article key={b.id} id={`bc-${b.id}`} className={`fork bcast${b.id === current ? " current" : ""}${b.inForce ? " in-force" : ""}`}>
            <div className="fork-head">
              <span className="eyebrow"><b className="flabel">{b.id}</b> · {b.from} · <span title={b.at}>{ageOf(Date.parse(b.at), now)} ago</span></span>
              <span className="fork-aff">
                {b.inForce ? <span className="chip danger">{b.sticky ? "in force · sticky" : `in force until ${b.expires}`}</span> : <span className="chip quiet">{b.expires ? `expired ${b.expires}` : "not in force"}</span>}
                <span className="chip quiet" title={a.missing.length ? `Not acked: ${a.missing.join(", ")}` : "Every seat in the audience acked"}>{a.acked} of {a.of} acked</span>
              </span>
            </div>
            <Rich text={b.text} />
            {a.missing.length > 0 && a.missing.length <= 6 && <p className="muted bc-missing">Not acked yet: {a.missing.join(", ")}</p>}
          </article>
        );
      })}
    </section>
  );
}

/**
 * IDE-304 item 6: why the Proofs tab is empty, said plainly in the main area, where there is room:
 * the server's own error text when the store did not answer, or that it answered with no pages.
 * Undefined while loading and when there are pages to pick from.
 */
export function ProofStatus({ list }: { list?: ProofList }) {
  if (!list) return null;
  if (!list.ok) {
    return (
      <div className="feed-status" role="alert">
        <b>The proof list could not be read</b>
        <p>The app server said: <code>{list.error || "no reason given"}</code></p>
        <p className="muted">Nothing is wrong with the asks. Refresh in the list on the left tries again.</p>
      </div>
    );
  }
  if (list.total === 0) {
    return (
      <div className="feed-status" role="status">
        <b>The proof store answered with no pages</b>
        <p className="muted">{list.bucket ? `Nothing under ${list.bucket}/${list.prefix ?? ""}${list.endpoint ? ` at ${list.endpoint}` : ""}.` : "It listed nothing."}</p>
      </div>
    );
  }
  return null;
}
