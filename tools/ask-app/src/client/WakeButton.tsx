/**
 * WAKEUI: "Wake <seat>" on an open ask's card, and as an icon beside each sidebar row (never inside the
 * row's own button, so a click neither opens nor selects the row). The rules are wake.ts's; this file
 * only holds the click, the clock and the markup. It posts `{}` to the wake route and nothing else.
 */
import { useEffect, useRef, useState } from "react";
import type { WakeResult } from "../lib/wake.ts";
import { authedFetch } from "./token.ts";
import { clickWake, expiryGate, holdCooldown, mergeResult, wakeOutcome, wakeUi, wakeUrl, type WakeRow } from "./wake.ts";

/** One gate for every button on the page: the card and the row of one ask count down the same expiry. */
const EXPIRED = expiryGate();

function useClock(fast: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), fast ? 1000 : 30_000);
    return () => clearInterval(t);
  }, [fast]);
  return now;
}

export function WakeButton({ w, seat, id, onChanged, variant }: { w: WakeRow; seat: string; id: string; onChanged: () => void; variant: "card" | "row" }) {
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<WakeResult | undefined>();
  const [msg, setMsg] = useState("");
  const [held, setHeld] = useState<string | undefined>();
  const merged = result ? mergeResult(w, result) : w;
  const shown = held ? holdCooldown(merged, held) : merged;
  const now = useClock(!!shown.wakeAfter);
  const u = wakeUi(shown, now, { busy });
  const counting = u.counting;
  // At the end of a cooldown nothing touches the file, so no SSE comes: read the list again.
  const wasCounting = useRef(false);
  const countedTo = useRef<string | undefined>();
  useEffect(() => {
    if (wasCounting.current && !counting && EXPIRED(`${seat}/${id}@${countedTo.current}`)) onChanged();
    wasCounting.current = !!counting;
    if (counting) countedTo.current = shown.wakeAfter;
  }, [counting]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!u.show) return null;

  const fire = async () => {
    setBusy(true);
    setMsg("");
    try {
      const r = await authedFetch(wakeUrl(seat, id), { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
      const o = wakeOutcome(r.status, r.json, r.restarted);
      if (o.result) setResult(o.result);
      if (o.wakeAfter) setHeld(o.wakeAfter);
      setMsg(o.text ?? "");
      if (o.refresh) onChanged();
    } catch {
      setMsg("Not woken: the app server did not answer");
    } finally {
      setBusy(false);
    }
  };
  const press = (e: { preventDefault(): void; stopPropagation(): void }) => clickWake(e, () => void fire());

  if (variant === "row") {
    return (
      <span className="row-wake-box">
        <button type="button" className={`row-wake${counting ? " counting" : ""}`} disabled={u.disabled} title={u.title} aria-label={u.label} onClick={press}>
          <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true" focusable="false">
            <path d="M8 1.5a4.5 4.5 0 0 0-4.5 4.5v2.6L2 11h12l-1.5-2.4V6A4.5 4.5 0 0 0 8 1.5zM6.2 12.5a1.8 1.8 0 0 0 3.6 0" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinejoin="round" />
          </svg>
          {counting && <span className="row-wake-count">{counting}</span>}
        </button>
        {u.status?.tone === "warn" && <span className="row-wake-note" title={u.status.title}>{u.status.text}</span>}
        {u.notice?.tone === "warn" && <span className="row-wake-note" title={u.notice.title}>{u.notice.text}</span>}
        {msg && <span className="row-wake-note" role="status">{msg}</span>}
      </span>
    );
  }
  return (
    <div className="ask-wake">
      <span className="wake-wrap" title={u.title}>
        <button type="button" className="chip toggle wake-btn" disabled={u.disabled} title={u.title} onClick={press}>{u.label}</button>
      </span>
      {u.status && <span className={`wake-status ${u.status.tone}`} title={u.status.title}>{u.status.text}</span>}
      {u.notice && <span className={`wake-notice ${u.notice.tone}`} title={u.notice.title}>{u.notice.text}</span>}
      {u.reason && <span className="wake-reason muted">{u.reason}</span>}
      {msg && <span className="chip warn wake-msg" role="status">{msg}</span>}
    </div>
  );
}
