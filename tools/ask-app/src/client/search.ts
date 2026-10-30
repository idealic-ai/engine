/**
 * IDE-304 (ASKSEARCH): the sidebar's text search over the loaded asks, client only.
 *
 * A query is split on whitespace into terms; an ask matches when EVERY term appears, case-
 * insensitively, in at least one of its fields (the title, the why, the id, the seat it is from and
 * to, each question's text, each option's label, the note, and the recorded answer in words).
 *
 * The matcher is a plain function of (ask, terms) so a semantic matcher (meta:engine's) can take its
 * place later through `searchRows`'s `matcher` argument. Nothing here calls the server.
 */
import { displayTitle, inlineTokens } from "./md.ts";
import { answerInWords, askRef, rowInFilter, sortRuled, type Filter, type Row, type StoredAsk } from "./model.ts";
import type { AskOption } from "../lib/format.ts";

export type SearchField = "title" | "why" | "id" | "seat" | "question" | "option" | "answer" | "note";
export type Hay = { field: SearchField; text: string };
/** A match: `extra` is the first field outside the row's title and seat that a term was found in. */
export type SearchMatch = { extra?: Hay };
/** What the row shows besides its title (SHOULD-3): the seat is hidden when grouped by seat or slim. */
export type Shown = { seat: boolean };
export type Matcher = (a: StoredAsk, terms: string[], shown?: Shown) => SearchMatch | null;

/**
 * The title's text as the row renders it (App.tsx's Plain): markdown tokens, so a link shows its
 * label and never its URL, inline code shows without backticks, a ticket shows its key.
 */
export function shownTitleText(title: string): string {
  return inlineTokens(displayTitle(title))
    .map((t) => (t.t === "text" || t.t === "code" || t.t === "strong" || t.t === "em" ? t.v : t.t === "ticket" ? t.key : t.label))
    .join("");
}

/** Whitespace-separated, lowercased, empties dropped. */
export function searchTerms(q: string | undefined): string[] {
  return (q ?? "").toLowerCase().split(/\s+/).filter(Boolean);
}

const optionLabels = (opts: AskOption[]): string[] => opts.flatMap((o) => [o.label.replace(/\s*\(lean\)\s*$/i, ""), ...optionLabels(o.children ?? [])]);

/** Every searchable piece of text in an ask, in the order a hit is reported. */
export function haystackOf(a: StoredAsk): Hay[] {
  const out: Hay[] = [];
  const add = (field: SearchField, text: string | undefined) => {
    const t = text?.trim();
    if (t) out.push({ field, text: t });
  };
  add("title", displayTitle(a.questions[0]?.title ?? a.header.id ?? ""));
  add("why", a.header.why);
  add("id", a.header.id);
  add("seat", a.header.from);
  add("seat", a.seat);
  add("seat", a.header.to);
  a.questions.forEach((q, i) => {
    if (i > 0) add("question", displayTitle(q.title));
  });
  for (const q of a.questions) for (const l of optionLabels(q.options)) add("option", l);
  if (a.answer) {
    for (const line of answerInWords(a, a.answer)) {
      for (const p of line.picks) add("answer", p);
      add("answer", line.note);
    }
    add("answer", a.answer.reason);
  }
  add("note", a.answer?.note);
  add("note", a.draft?.note);
  add("note", a.header.note);
  return out;
}

/** The text matcher: null when some term is nowhere in the ask. */
export const matchAsk: Matcher = (a, terms, shown = { seat: true }) => {
  if (terms.length === 0) return {};
  const hay = haystackOf(a).map((h) => ({ ...h, low: h.text.toLowerCase() }));
  // SHOULD-3: "visible" is what the row renders, so every match it lists shows a <mark> or a snippet.
  const titleHay = hay.find((h) => h.field === "title");
  const shownTitle = titleHay ? shownTitleText(titleHay.text).toLowerCase() : "";
  const shownSeat = shown.seat ? (a.header.from?.trim() || a.seat).toLowerCase() : "";
  let extra: Hay | undefined;
  for (const t of terms) {
    const hit = hay.find((h) => h.low.includes(t));
    if (!hit) return null;
    if (!extra && !shownTitle.includes(t) && !shownSeat.includes(t)) {
      // The first field holding the term that the row does not already show; the raw title (a link's
      // URL) qualifies, since its rendered text does not hold the term.
      const h = hay.find((x) => x.low.includes(t) && !(x.field === "seat" && shownSeat && x.low === shownSeat))!;
      extra = { field: h.field, text: h.text };
    }
  }
  return extra ? { extra } : {};
};

/** The rows whose ask matches `q`, in their order; an empty query keeps them all. */
export function searchRows(rows: Row[], asks: StoredAsk[], q: string | undefined, matcher: Matcher = matchAsk, shown?: Shown): (Row & { extra?: Hay })[] {
  const terms = searchTerms(q);
  if (terms.length === 0) return rows;
  const byRef = new Map(asks.map((a) => [askRef(a), a]));
  const out: (Row & { extra?: Hay })[] = [];
  for (const r of rows) {
    const a = byRef.get(r.ref);
    const m = a ? matcher(a, terms, shown) : null;
    if (m) out.push(m.extra ? { ...r, extra: m.extra } : r);
  }
  return out;
}

/**
 * SHOULD-2: what the sidebar reads, in one place. The list, the filter counts and the groups read the
 * searched rows; the header's "N waiting on you" reads every row, so a search never changes it.
 */
export function sidebarView(allRows: Row[], asks: StoredAsk[], q: string | undefined, filter: Filter, shown?: Shown) {
  const rows = searchRows(allRows, asks, q, matchAsk, shown);
  const inFilter = filter === "ruled" ? sortRuled(rows.filter((r) => rowInFilter(r, filter))) : rows.filter((r) => rowInFilter(r, filter));
  const count = (f: Filter) => rows.filter((r) => rowInFilter(r, f)).length;
  const waiting = allRows.filter((r) => r.waitingOnYou).length;
  return { rows, inFilter, count, waiting };
}

/**
 * NIT-4: `text` lowercased, with `at[i]` the index in `text` that lowercase unit `i` came from (and
 * `at[low.length] = text.length`). A character whose lowercase is longer (İ → i̇) keeps later offsets true.
 */
export function lowerWithMap(text: string): { low: string; at: number[] } {
  let low = "";
  const at: number[] = [];
  for (let i = 0; i < text.length; ) {
    const cp = text.codePointAt(i)!;
    const ch = String.fromCodePoint(cp);
    const l = ch.toLowerCase();
    for (let k = 0; k < l.length; k++) at.push(i);
    low += l;
    i += ch.length;
  }
  at.push(text.length);
  return { low, at };
}

export type Part = { text: string; hit: boolean };
/** `text` cut into plain and matched parts; overlapping or touching hits merge into one. */
export function highlight(text: string, terms: string[]): Part[] {
  const { low, at: from } = lowerWithMap(text);
  const spans: [number, number][] = [];
  for (const t of terms) {
    if (!t) continue;
    for (let i = low.indexOf(t); i !== -1; i = low.indexOf(t, i + 1)) spans.push([from[i], endAt(from, i + t.length)]);
  }
  if (spans.length === 0) return text ? [{ text, hit: false }] : [];
  spans.sort((x, y) => x[0] - y[0]);
  const merged: [number, number][] = [];
  for (const s of spans) {
    const last = merged[merged.length - 1];
    if (last && s[0] <= last[1]) last[1] = Math.max(last[1], s[1]);
    else merged.push([s[0], s[1]]);
  }
  const out: Part[] = [];
  let at = 0;
  for (const [s, e] of merged) {
    if (s > at) out.push({ text: text.slice(at, s), hit: false });
    out.push({ text: text.slice(s, e), hit: true });
    at = e;
  }
  if (at < text.length) out.push({ text: text.slice(at), hit: false });
  return out;
}

/** The original index just past lowercase unit `j - 1`: a match ending inside an expanded character covers all of it. */
function endAt(at: number[], j: number): number {
  while (j < at.length - 1 && at[j] === at[j - 1]) j++;
  return at[j];
}

/** The text around the first hit, `radius` characters each side, with an ellipsis where cut. */
export function snippet(text: string, terms: string[], radius = 30): string {
  const { low, at } = lowerWithMap(text);
  const first = Math.min(...terms.map((t) => low.indexOf(t)).filter((i) => i !== -1).map((i) => at[i]));
  if (!Number.isFinite(first)) return text.length > radius * 2 ? `${text.slice(0, radius * 2)}…` : text;
  const s = Math.max(0, first - radius);
  const e = Math.min(text.length, first + radius + Math.max(...terms.map((t) => t.length)));
  return `${s > 0 ? "…" : ""}${text.slice(s, e)}${e < text.length ? "…" : ""}`;
}

/** Whether `/` should type into the focused element rather than jump to the search box. */
export function isTypingTarget(el: { tagName?: string; isContentEditable?: boolean } | null | undefined): boolean {
  if (!el) return false;
  const tag = (el.tagName ?? "").toUpperCase();
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || !!el.isContentEditable;
}
