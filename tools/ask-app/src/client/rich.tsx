/**
 * Prose as the card shows it: links, inline code and ticket keys in a line; paragraphs, lists,
 * fenced code and collapsed callouts across lines. A proof link opens in the related pane (through
 * PaneContext) instead of a new tab; a ticket key gets the ticket popover.
 */
import { createContext, useContext, useEffect, useLayoutEffect, useRef, useState, type MouseEvent } from "react";
import { blocks, inlineTokens, type CalloutKind } from "./md.ts";
import { isProofUrl } from "./related.ts";
import { pushEsc } from "./esc.ts";

export { blocks, inlineTokens } from "./md.ts";

/** useLayoutEffect in the browser, useEffect on the server (the tests render there). */
const useIsoLayout = typeof window === "undefined" ? useEffect : useLayoutEffect;

export type PaneOpener = (url: string, label: string) => void;
export const PaneContext = createContext<PaneOpener | undefined>(undefined);

const token = () => (typeof document === "undefined" ? "" : document.querySelector('meta[name="ask-token"]')?.getAttribute("content") ?? "");

/** N3: a link is followed only when it is http(s); anything else (javascript:, data:) is dropped. */
export function safeHref(url: string | undefined): string | undefined {
  return url && /^https?:\/\//i.test(url) ? url : undefined;
}

export function Inline({ text }: { text: string }) {
  return (
    <>
      {inlineTokens(text).map((t, i) =>
        t.t === "text" ? <span key={i}>{t.v}</span>
        : t.t === "code" ? <code key={i} className="ic">{t.v}</code>
        : t.t === "ticket" ? <TicketLink key={i} k={t.key} />
        : t.t === "strong" ? <strong key={i}><Inline text={t.v} /></strong>
        : t.t === "em" ? <em key={i}><Inline text={t.v} /></em>
        : <SmartLink key={i} href={t.href} label={t.label} />,
      )}
    </>
  );
}

export function SmartLink({ href, label }: { href: string; label: string }) {
  const open = useContext(PaneContext);
  const safe = safeHref(href);
  if (!safe) return <span>{label}</span>;
  const proof = isProofUrl(safe);
  const onClick = (e: MouseEvent) => {
    if (!proof || !open || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    open(safe, label);
  };
  return (
    <a href={safe} target="_blank" rel="noreferrer" className={proof ? "proof-link" : undefined} onClick={onClick} title={proof ? "Opens beside the ask" : undefined}>
      {proof && <span aria-hidden="true" className="pl-ico">◧ </span>}
      {label}
    </a>
  );
}

const CALLOUT_LABEL: Record<CalloutKind, [string, string]> = {
  background: ["Background", "◔"],
  term: ["What it means", "≡"],
  code: ["Code", "‹›"],
  evidence: ["Evidence", "⌕"],
  more: ["More", "+"],
};

/** Multi-paragraph prose. Callouts render closed; the question and the options never sit inside one. */
export function Rich({ text, className }: { text?: string; className?: string }) {
  if (!text?.trim()) return null;
  return (
    <div className={className ?? "rich"}>
      {blocks(text).map((b, i) => {
        if (b.t === "p") return <p key={i}><Inline text={b.text} /></p>;
        if (b.t === "pre") return <pre key={i} className="code"><code>{b.code}</code></pre>;
        if (b.t === "quote") return <blockquote key={i}><Rich text={b.text} /></blockquote>;
        if (b.t === "hr") return <hr key={i} />;
        if (b.t === "h") {
          // Prose headings sit under the fork's own title, so they render a step quieter than it.
          const H = (b.level <= 2 ? "h4" : b.level === 3 ? "h5" : "h6") as "h4" | "h5" | "h6";
          return <H key={i} className="md-h"><Inline text={b.text} /></H>;
        }
        if (b.t === "list") {
          const items = b.items.map((it, j) => (
            <li key={j}>
              <Inline text={it} />
              {b.nested?.[j] ? <Rich text={b.nested[j]} className="rich nested-md" /> : null}
            </li>
          ));
          return b.ordered ? <ol key={i} start={b.start}>{items}</ol> : <ul key={i}>{items}</ul>;
        }
        const [label, icon] = CALLOUT_LABEL[b.kind];
        const lines = b.body.split("\n").length;
        return (
          <details key={i} className={`callout k-${b.kind}`}>
            <summary>
              <span className="co-ico" aria-hidden="true">{icon}</span>
              <span className="co-kind">{label}</span>
              {b.title ? <span className="co-title"><Inline text={b.title} /></span> : <span className="co-title muted">{lines} line{lines === 1 ? "" : "s"}</span>}
            </summary>
            <div className="co-body">{b.kind === "code" && !b.body.includes("```") ? <pre className="code"><code>{b.body}</code></pre> : <Rich text={b.body} />}</div>
          </details>
        );
      })}
    </div>
  );
}

// ── tickets: the Linear key stays on the server ─────────────

export type TicketInfo = { key: string; title: string; status: string; statusType: string; statusSince: string; assignee: string; summary: string; url: string };
const ticketCache = new Map<string, Promise<TicketInfo | { error: string }>>();
function loadTicket(k: string) {
  if (!ticketCache.has(k)) {
    ticketCache.set(
      k,
      fetch(`/api/ticket/${encodeURIComponent(k)}`, { headers: { "x-ask-token": token() } })
        .then(async (r) => (r.ok ? r.json() : { error: (await r.json().catch(() => ({}))).error ?? `HTTP ${r.status}` }))
        .catch(() => ({ error: "the app server did not answer" }))
        .then((v: TicketInfo | { error: string }) => {
          // S6: a failed lookup is shown once, then forgotten, so the next hover asks again.
          if ("error" in v) ticketCache.delete(k);
          return v;
        }),
    );
  }
  return ticketCache.get(k)!;
}

const statusTone = (t?: TicketInfo) => (!t ? "" : t.statusType === "completed" ? "ok" : t.statusType === "canceled" ? "bad" : t.statusType === "started" ? "warn" : "");

/**
 * A ticket key with its popover: hover or focus shows it, a tap pins it (the first tap on a touch
 * screen pins instead of leaving the page), Esc closes it. Loaded on first show, cached per key.
 */
export function TicketLink({ k }: { k: string }) {
  const [info, setInfo] = useState<TicketInfo | { error: string } | undefined>();
  const [hover, setHover] = useState(false);
  const [pinned, setPinned] = useState(false);
  const [shift, setShift] = useState(0);
  const pointer = useRef("mouse");
  const tip = useRef<HTMLSpanElement>(null);
  const show = hover || pinned;
  useEffect(() => {
    if (!show || info) return;
    let live = true;
    loadTicket(k).then((i) => live && setInfo(i));
    return () => {
      live = false;
    };
  }, [k, show, info]);
  // S3/N6: Esc closes it whether it opened by hover, focus or a tap, and closes only it.
  useEffect(() => {
    if (!show) return;
    return pushEsc(() => {
      setPinned(false);
      setHover(false);
    });
  }, [show]);
  useEffect(() => {
    if (!pinned) return;
    const away = (e: Event) => !(e.target as Element)?.closest?.(`[data-ticket="${k}"]`) && setPinned(false);
    document.addEventListener("pointerdown", away);
    return () => document.removeEventListener("pointerdown", away);
  }, [pinned, k]);
  // Keep the popover inside the viewport: shift it left when it would run past the right edge.
  useIsoLayout(() => {
    if (!show || !tip.current) return setShift(0);
    const r = tip.current.getBoundingClientRect();
    const over = r.right + shift - (window.innerWidth - 8);
    if (over > 0) setShift(-over);
  }, [show, info]); // eslint-disable-line react-hooks/exhaustive-deps
  const t = info && "key" in info ? info : undefined;
  const id = `tt-${k}`;
  return (
    <span className="ticket" data-ticket={k} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}>
      <a
        href={safeHref(t?.url) ?? `#ticket-${k}`}
        target="_blank"
        rel="noreferrer"
        aria-describedby={show ? id : undefined}
        onPointerDown={(e) => (pointer.current = e.pointerType)}
        onFocus={() => setHover(true)}
        onBlur={() => setHover(false)}
        onClick={(e) => {
          if (pointer.current === "touch" && !pinned) {
            e.preventDefault();
            setPinned(true);
          } else if (!t) e.preventDefault();
        }}
      >
        {k}
      </a>
      {t && <span className={`tdot ${statusTone(t)}`} title={t.status} aria-hidden="true" />}
      {show && (
        <span className="tooltip" role="tooltip" id={id} ref={tip} style={shift ? { transform: `translateX(${shift}px)` } : undefined}>
          {!info ? (
            <span className="muted">Loading {k}…</span>
          ) : t ? (
            <>
              <b>{t.key} · {t.title}</b>
              <span className="tt-meta"><span className={`pill ${statusTone(t)}`}>{t.status}</span> since {t.statusSince.slice(0, 10)} · {t.assignee || "unassigned"}</span>
              {t.summary && <span className="tt-sum">{t.summary}</span>}
            </>
          ) : (
            <span>{k}: {(info as { error: string }).error}</span>
          )}
        </span>
      )}
    </span>
  );
}
