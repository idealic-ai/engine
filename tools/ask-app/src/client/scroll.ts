/**
 * Scrolling that moves ONE container (operator 01:29). Element.scrollIntoView scrolls every scrollable
 * ancestor, overflow:hidden ones included (they stay programmatically scrollable), so it shifted the
 * page, the shell and the sidebar along with the ask. This moves only the container it is given.
 */
export type ScrollBox = Pick<HTMLElement, "scrollTop" | "getBoundingClientRect"> & { scrollTo(o: ScrollToOptions): void };
type Box = Pick<HTMLElement, "getBoundingClientRect">;

/** Attribute that marks a column's own scroller: the ask pane, the side list. */
export const SCROLL_ROOT = "data-scroll-root";

/** Scroll `container` so `el` sits `offset` px below its top edge. Nothing else moves. False when either is missing. */
export function scrollWithin(container: ScrollBox | null | undefined, el: Box | null | undefined, opts: { behavior?: ScrollBehavior; offset?: number } = {}): boolean {
  if (!container || !el) return false;
  const top = el.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop - (opts.offset ?? 8);
  container.scrollTo({ top: Math.max(0, Math.round(top)), behavior: opts.behavior ?? "auto" });
  return true;
}

/** The column scroller that holds `el` (the nearest ancestor marked with SCROLL_ROOT), never the page. */
export function scrollRootOf(el: Element | null | undefined): HTMLElement | null {
  return (el?.closest(`[${SCROLL_ROOT}]`) as HTMLElement | null) ?? null;
}

/** Scroll the element with this id inside its own column. */
export function scrollToId(id: string, behavior: ScrollBehavior = "auto"): boolean {
  if (typeof document === "undefined") return false;
  const el = document.getElementById(id);
  return scrollWithin(scrollRootOf(el), el, { behavior });
}
