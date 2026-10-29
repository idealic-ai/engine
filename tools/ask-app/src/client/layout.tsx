/**
 * The desk: the ask list is always on screen as its own column, and a linked page splits the work
 * area with the ask instead of covering it. Landscape: ask | page side by side. Portrait: ask above
 * page. Both dividers drag (pointer) and step (arrow keys); widths and ratios are kept per browser.
 */
import { useCallback, useEffect, useRef, useState, type CSSProperties, type KeyboardEvent, type PointerEvent, type ReactNode } from "react";

export const SIDE_MIN = 96;
export const SIDE_MAX = 480;
/** Below this width a sidebar row shows only its clamped title and its "N of M left". */
export const SIDE_SLIM = 180;
export const RATIO_MIN = 0.2;
export const RATIO_MAX = 0.8;

export const clampSide = (w: number) => Math.round(Math.min(SIDE_MAX, Math.max(SIDE_MIN, Number.isFinite(w) ? w : 300)));
export const clampRatio = (r: number) => Math.min(RATIO_MAX, Math.max(RATIO_MIN, Number.isFinite(r) ? r : 0.5));

/** The sidebar's starting width when the browser has none stored: slim on a phone, roomy on a desk. */
export function sideDefault(viewportWidth: number): number {
  return viewportWidth < 700 ? 116 : viewportWidth < 1100 ? 240 : 300;
}

export type SplitMode = "columns" | "rows";

function readNum(k: string): number | undefined {
  try {
    const v = localStorage.getItem(k);
    return v === null ? undefined : Number(v);
  } catch {
    return undefined;
  }
}
function writeNum(k: string, v: number) {
  try {
    localStorage.setItem(k, String(v));
  } catch {
    /* private window: kept until reload */
  }
}

/** A number kept in localStorage under `key`, clamped on the way in. */
export function useStoredNumber(key: string, initial: () => number, clamp: (n: number) => number) {
  const [v, setV] = useState(() => clamp(readNum(key) ?? initial()));
  const set = useCallback((n: number) => setV(clamp(n)), [clamp]);
  useEffect(() => writeNum(key, v), [key, v]);
  return [v, set] as const;
}

/**
 * A divider. `orientation` is the divider's own line: "vertical" splits left from right. It reports
 * the pointer's position as a fraction of `container` (or, with `absolute`, in pixels from its start).
 */
export function Grip(p: {
  orientation: "vertical" | "horizontal";
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  container: () => HTMLElement | null;
  absolute?: boolean;
  onChange: (v: number) => void;
  onDragging?: (on: boolean) => void;
}) {
  const dragging = useRef(false);
  const at = (e: PointerEvent) => {
    const box = p.container()?.getBoundingClientRect();
    if (!box) return undefined;
    const pos = p.orientation === "vertical" ? e.clientX - box.left : e.clientY - box.top;
    return p.absolute ? pos : pos / (p.orientation === "vertical" ? box.width : box.height);
  };
  const key = (e: KeyboardEvent) => {
    const back = p.orientation === "vertical" ? "ArrowLeft" : "ArrowUp";
    const fwd = p.orientation === "vertical" ? "ArrowRight" : "ArrowDown";
    if (e.key === back) p.onChange(p.value - p.step);
    else if (e.key === fwd) p.onChange(p.value + p.step);
    else if (e.key === "Home") p.onChange(p.min);
    else if (e.key === "End") p.onChange(p.max);
    else return;
    e.preventDefault();
  };
  return (
    <div
      className={`grip-${p.orientation === "vertical" ? "x" : "y"}`}
      role="separator"
      tabIndex={0}
      aria-label={p.label}
      aria-orientation={p.orientation}
      aria-valuemin={Math.round(p.min * (p.absolute ? 1 : 100))}
      aria-valuemax={Math.round(p.max * (p.absolute ? 1 : 100))}
      aria-valuenow={Math.round(p.value * (p.absolute ? 1 : 100))}
      onKeyDown={key}
      onPointerDown={(e) => {
        dragging.current = true;
        (e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId);
        p.onDragging?.(true);
        e.preventDefault();
      }}
      onPointerMove={(e) => {
        if (!dragging.current) return;
        const v = at(e);
        if (v !== undefined) p.onChange(v);
      }}
      onPointerUp={(e) => {
        dragging.current = false;
        (e.currentTarget as HTMLElement).releasePointerCapture?.(e.pointerId);
        p.onDragging?.(false);
      }}
      onPointerCancel={() => {
        dragging.current = false;
        p.onDragging?.(false);
      }}
    >
      <span aria-hidden="true" />
    </div>
  );
}

/**
 * The work area: the ask alone, or the ask and the linked page split by a draggable divider. Nothing
 * is positioned over the ask; each side scrolls on its own.
 */
export function Split(p: { mode: SplitMode; ratio: number; onRatio: (r: number) => void; main: ReactNode; pane: ReactNode | null; onDragging?: (on: boolean) => void }) {
  const box = useRef<HTMLDivElement>(null);
  const r = clampRatio(p.ratio);
  const tracks = `minmax(0, ${r.toFixed(3)}fr) 8px minmax(0, ${(1 - r).toFixed(3)}fr)`;
  const style: CSSProperties | undefined = p.pane ? (p.mode === "columns" ? { gridTemplateColumns: tracks } : { gridTemplateRows: tracks }) : undefined;
  return (
    <div ref={box} className={`work ${p.pane ? `split split-${p.mode}` : "solo"}`} style={style}>
      {p.main}
      {p.pane && (
        <Grip
          orientation={p.mode === "columns" ? "vertical" : "horizontal"}
          label="Resize the ask and the linked page"
          value={r}
          min={RATIO_MIN}
          max={RATIO_MAX}
          step={0.05}
          container={() => box.current}
          onChange={(v) => p.onRatio(clampRatio(v))}
          onDragging={p.onDragging}
        />
      )}
      {p.pane}
    </div>
  );
}
