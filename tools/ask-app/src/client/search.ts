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
import { displayTitle } from "./md.ts";
import { answerInWords, askRef, type Row, type StoredAsk } from "./model.ts";
import type { AskOption } from "../lib/format.ts";

export type SearchField = "title" | "why" | "id" | "seat" | "question" | "option" | "answer" | "note";
export type Hay = { field: SearchField; text: string };
/** A match: `extra` is the first field outside the row's title and seat that a term was found in. */
export type SearchMatch = { extra?: Hay };
export type Matcher = (a: StoredAsk, terms: string[]) => SearchMatch | null;

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
export const matchAsk: Matcher = (a, terms) => {
  if (terms.length === 0) return {};
  const hay = haystackOf(a).map((h) => ({ ...h, low: h.text.toLowerCase() }));
  const shownTitle = hay.find((h) => h.field === "title")?.low ?? "";
  const shownSeat = (a.header.from?.trim() || a.seat).toLowerCase();
  let extra: Hay | undefined;
  for (const t of terms) {
    const hit = hay.find((h) => h.low.includes(t));
    if (!hit) return null;
    if (!extra && !shownTitle.includes(t) && !shownSeat.includes(t)) {
      const h = hay.find((x) => x.low.includes(t) && x.field !== "title" && !(x.field === "seat" && x.low === shownSeat))!;
      extra = { field: h.field, text: h.text };
    }
  }
  return extra ? { extra } : {};
};

/** The rows whose ask matches `q`, in their order; an empty query keeps them all. */
export function searchRows(rows: Row[], asks: StoredAsk[], q: string | undefined, matcher: Matcher = matchAsk): (Row & { extra?: Hay })[] {
  const terms = searchTerms(q);
  if (terms.length === 0) return rows;
  const byRef = new Map(asks.map((a) => [askRef(a), a]));
  const out: (Row & { extra?: Hay })[] = [];
  for (const r of rows) {
    const a = byRef.get(r.ref);
    const m = a ? matcher(a, terms) : null;
    if (m) out.push(m.extra ? { ...r, extra: m.extra } : r);
  }
  return out;
}

export type Part = { text: string; hit: boolean };
/** `text` cut into plain and matched parts; overlapping or touching hits merge into one. */
export function highlight(text: string, terms: string[]): Part[] {
  const low = text.toLowerCase();
  const spans: [number, number][] = [];
  for (const t of terms) {
    if (!t) continue;
    for (let i = low.indexOf(t); i !== -1; i = low.indexOf(t, i + 1)) spans.push([i, i + t.length]);
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

/** The text around the first hit, `radius` characters each side, with an ellipsis where cut. */
export function snippet(text: string, terms: string[], radius = 30): string {
  const low = text.toLowerCase();
  const first = Math.min(...terms.map((t) => low.indexOf(t)).filter((i) => i !== -1));
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
