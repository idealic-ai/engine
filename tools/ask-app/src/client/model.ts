/**
 * The client's view of an ask, as plain data: one sidebar row per ask (never per fork), the order
 * and grouping of those rows, which option a fork leans to, and which trade-off dimensions are
 * worth a column on a fork. Pure, so the tests read it without a DOM.
 */
import { cardFor, draftAuthor, questionKey, visibleQuestions, type AnswerMap, type AnswerValue, type AskOption, type ParsedAsk } from "../lib/format.ts";

export type StoredAsk = ParsedAsk & { seat: string; file: string; mtimeMs: number };

export type Row = {
  ref: string;
  id: string;
  title: string;
  seat: string;
  topic: string;
  created: number;
  age: string;
  left: number;
  total: number;
  high: boolean;
  reserved?: string;
  waitingOnYou: boolean;
  draft: boolean;
  seatDraft?: string;
  status: string;
};

export const askRef = (a: StoredAsk) => `${a.seat}/${a.header.id}`;
export const isSettled = (a: ParsedAsk) => a.header.status === "answered" || a.header.status === "declined";

/** The answers the operator has given or drafted, which is what "left" counts against. */
function givenAnswers(a: ParsedAsk): AnswerMap {
  if (a.answer?.answers) return a.answer.answers;
  if (a.draft && draftAuthor(a.draft) === "operator") return a.draft.answers ?? {};
  return {};
}

export function ageOf(createdMs: number, now: number): string {
  if (!Number.isFinite(createdMs)) return "";
  const m = Math.max(0, Math.round((now - createdMs) / 60000));
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 48) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
}

export function askRow(a: StoredAsk, now = Date.now()): Row {
  const given = givenAnswers(a);
  const visible = visibleQuestions(a.questions, given);
  const answered = visible.filter((q) => {
    const k = questionKey(q, a.questions.indexOf(q));
    const v = given[k];
    return v !== undefined && !(Array.isArray(v) && v.length === 0) && v !== "";
  }).length;
  const settled = isSettled(a);
  const created = Date.parse(a.header.created ?? "");
  const reserved = a.header["reserved-for"]?.trim() || undefined;
  const author = a.draft ? draftAuthor(a.draft) : "";
  return {
    ref: askRef(a),
    id: a.header.id ?? "",
    title: a.questions[0]?.title ?? a.header.id ?? "",
    seat: a.header.from?.trim() || a.seat,
    topic: (a.header.topic ?? a.questions[0]?.meta.topic ?? "").trim(),
    created,
    age: ageOf(created, now),
    total: visible.length,
    left: settled ? 0 : visible.length - answered,
    high: a.header.importance?.trim().toLowerCase() === "high",
    reserved,
    waitingOnYou: a.header.status === "open" && (a.header.to?.trim() === "operator" || reserved === "operator"),
    draft: !!a.draft && author === "operator",
    seatDraft: a.draft && author !== "operator" ? author : undefined,
    status: a.header.status ?? "open",
  };
}

/** Waiting on you first, then high importance, then the oldest. */
export function sortRows(rows: Row[]): Row[] {
  return [...rows].sort(
    (x, y) =>
      Number(y.waitingOnYou) - Number(x.waitingOnYou) ||
      Number(y.high) - Number(x.high) ||
      (Number.isFinite(x.created) ? x.created : Infinity) - (Number.isFinite(y.created) ? y.created : Infinity),
  );
}

export type GroupBy = "none" | "seat" | "topic";
export const NO_TOPIC = "No topic";

/** Groups in the order their first row appears; asks with no topic gather last. */
export function groupRows(rows: Row[], by: GroupBy): { name: string; rows: Row[] }[] {
  if (by === "none") return [{ name: "", rows }];
  const groups = new Map<string, Row[]>();
  for (const r of rows) {
    const name = by === "seat" ? r.seat : r.topic || NO_TOPIC;
    groups.set(name, [...(groups.get(name) ?? []), r]);
  }
  const out = [...groups].map(([name, rs]) => ({ name, rows: rs }));
  return [...out.filter((g) => g.name !== NO_TOPIC), ...out.filter((g) => g.name === NO_TOPIC)];
}

function codesOf(opts: AskOption[]): string[] {
  return opts.flatMap((o) => [...(o.code ? [o.code] : []), ...codesOf(o.children ?? [])]);
}

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * The option a fork leans to: its own `Lean: CODE` line; else a header `lean:` that names this fork
 * (`F2 DEGR`, `XLOSS: DOC`); else the one option whose label ends in "(lean)".
 */
export function leanCodeFor(a: ParsedAsk, index: number): string | undefined {
  const q = a.questions[index];
  if (!q) return undefined;
  const card = cardFor(a, index);
  if (card.lean?.code) return card.lean.code;
  const own = headerLeanEntries(a).get(index);
  if (own) return own.code;
  const marked = q.options.filter((o) => /\(lean\)\s*$/i.test(o.label) && o.code);
  return marked.length === 1 ? marked[0].code : undefined;
}

// ── trade-off strip (¶FMT_ANSWER_GRADATION glyphs) ─────────

export type Dim = "blast" | "effort" | "cost" | "lean";
export type Cell = { glyph: string; text: string };
/** Gradation order: risk-like first, then effort, then the one text line, then ★ last. */
const DIM_ORDER: Dim[] = ["blast", "effort", "cost", "lean"];
export const DIM_LABEL: Record<Dim, string> = { blast: "Risk (blast radius)", effort: "Effort", cost: "Cost", lean: "The asker's lean" };

const level = (s: string): "s" | "m" | "l" | undefined => {
  const w = s.trim().toLowerCase().split(/[\s—–,;:(-]+/)[0];
  if (["s", "small", "low", "xs", "tiny"].includes(w)) return "s";
  if (["m", "med", "medium", "moderate"].includes(w)) return "m";
  if (["l", "large", "high", "xl", "big"].includes(w)) return "l";
  return undefined;
};
const EFFORT = { s: "Ⓢ", m: "Ⓜ", l: "Ⓛ" };
const RISK = { s: "△", m: "◭", l: "▲" };

function cell(dim: Dim, o: AskOption, lean: string | undefined): Cell | undefined {
  if (dim === "lean") return o.code && o.code === lean ? { glyph: "★", text: "the asker's lean" } : undefined;
  const raw = dim === "effort" ? o.effort : dim === "blast" ? o.blastRadius : o.cost;
  if (!raw?.trim()) return undefined;
  if (dim === "cost") return { glyph: "", text: raw.trim() };
  const lv = level(raw);
  return { glyph: lv ? (dim === "effort" ? EFFORT : RISK)[lv] : "", text: raw.trim() };
}

/**
 * The strip for a fork (S8): always the same shape, risk · effort · cost, plus ★ for the lean. A
 * dimension that is the same on every option stays, marked `same`, so the reader sees it did not
 * separate the options rather than wondering where it went.
 */
export function tradeoff(options: AskOption[], lean: string | undefined): { dims: Dim[]; same: Dim[]; shown: Dim[]; rows: Record<string, Partial<Record<Dim, Cell>>> } {
  const key = (o: AskOption) => o.code ?? o.label;
  const rows: Record<string, Partial<Record<Dim, Cell>>> = {};
  for (const o of options) rows[key(o)] = {};
  const dims: Dim[] = ["blast", "effort", "cost", ...(lean ? (["lean"] as Dim[]) : [])];
  const same: Dim[] = [];
  const shown: Dim[] = [];
  for (const d of dims) {
    const cells = options.map((o) => cell(d, o, lean));
    // Operator 00:30: a dimension no option gives ("–" on every one) is not drawn at all.
    if (cells.some(Boolean)) shown.push(d);
    options.forEach((o, i) => {
      if (cells[i]) rows[key(o)][d] = cells[i];
    });
    if (d === "lean") continue;
    const sig = cells.map((c) => (c ? `${c.glyph}|${c.glyph ? "" : c.text}` : ""));
    if (sig.every((x) => x === sig[0])) same.push(d);
  }
  return { dims, same, shown, rows };
}

/** A lean's reason with its leading separator gone; empty when nothing but punctuation is left ("Why the lean ."). */
export function leanReason(text: string | undefined): string {
  const t = (text ?? "").replace(/^[\s—–:;.,-]+/, "").trim();
  return /[\p{L}\p{N}]/u.test(t) ? t : "";
}

/** True when a value says more than its level word (`high — every CI box`), so the words are worth showing. */
export function saysMore(raw: string | undefined): boolean {
  if (!raw?.trim()) return false;
  return !level(raw) || raw.trim().split(/\s+/).length > 1;
}

// ── round 2: forks by label, deep links, confirm on re-click, per-fork header lean ──

/** A fork's label as people read it: its ask name, or Q1, Q2 … counted from 1. The wire key stays `q0…`. */
export function forkLabel(q: { askName?: string }, index: number): string {
  return q.askName ?? `Q${index + 1}`;
}

/** The fork a fragment names: an ask name in any case, or Q<n> counted from 1. Undefined when none matches. */
export function resolveFork(a: ParsedAsk, token: string): number | undefined {
  const t = token.trim();
  if (!t) return undefined;
  const byName = a.questions.findIndex((q) => q.askName && q.askName.toLowerCase() === t.toLowerCase());
  if (byName !== -1) return byName;
  const m = t.match(/^q(\d+)$/i);
  if (m) {
    const i = Number(m[1]) - 1;
    if (i >= 0 && i < a.questions.length) return i;
  }
  return undefined;
}

/**
 * The page fragment, decoded: `seat/id` picks an ask, `seat/id/F2` an ask and a fork, and a lone
 * `Q2` or `f2` a fork of the ask already open.
 */
export function parseHash(hash: string): { ref?: string; fork?: string } {
  let h = hash.replace(/^#/, "");
  try {
    h = decodeURIComponent(h);
  } catch {
    /* a malformed escape is read as written */
  }
  if (!h) return {};
  const parts = h.split("/");
  if (parts.length === 1) return { fork: parts[0] };
  if (parts.length === 2) return { ref: h };
  return { ref: `${parts[0]}/${parts[1]}`, fork: parts.slice(2).join("/") };
}

/**
 * What a click on an option does to a fork's picks. On a single-choice fork, clicking the option that
 * is already picked CONFIRMS it (and the card moves on); it never clears it. A checkbox still toggles.
 * `siblings` are the values a single pick replaces (the option's level, with their subtrees).
 */
export function clickPicks(picks: string[], value: string, multi: boolean, siblings: string[], subtree: string[] = [value]): { picks: string[]; confirm: boolean } {
  const on = picks.includes(value);
  if (multi) return { picks: on ? picks.filter((p) => !subtree.includes(p)) : [...picks, value], confirm: false };
  if (on) return { picks, confirm: true };
  return { picks: [...picks.filter((p) => !siblings.includes(p)), value], confirm: false };
}

/** The next fork after `index` that is on screen to answer, or undefined at the last one. */
export function nextFork(a: ParsedAsk, index: number, visible: ParsedAsk["questions"]): number | undefined {
  for (let i = index + 1; i < a.questions.length; i++) if (visible.includes(a.questions[i])) return i;
  return undefined;
}

/**
 * A header `lean:` that names several forks (`F1 ALL; F2 DEGR — reason`, `XNOTE: KEEP. XLOSS: DOC — why`)
 * split into one entry per fork: each fork sees only its own code and reason.
 */
export function headerLeanEntries(a: ParsedAsk): Map<number, { code: string; text: string }> {
  const out = new Map<number, { code: string; text: string }>();
  const hl = a.header.lean ?? "";
  if (!hl.trim()) return out;
  const hits: { index: number; start: number; end: number; code: string }[] = [];
  a.questions.forEach((q, i) => {
    if (!q.askName) return;
    const m = new RegExp(`(^\\s*|[;,.]\\s*)(${esc(q.askName)}):?\\s+\\[?([A-Z][A-Z0-9]{0,11})\\]?(?![A-Za-z0-9])`).exec(hl);
    if (!m) return;
    const codes = new Set(codesOf(q.options));
    if (!codes.has(m[3])) return;
    const start = m.index + m[1].length;
    hits.push({ index: i, start, end: m.index + m[0].length, code: m[3] });
  });
  hits.sort((x, y) => x.start - y.start);
  hits.forEach((h, k) => {
    const stop = k + 1 < hits.length ? hits[k + 1].start : hl.length;
    const text = hl.slice(h.end, stop).replace(/^[\s—–:,-]+/, "").replace(/[\s;.,]+$/, "").trim();
    out.set(h.index, { code: h.code, text });
  });
  return out;
}

/**
 * The lean a fork shows: its own `Lean:` line; else its own entry in a header lean that names forks;
 * else (first fork only) a header lean that names none. Never another fork's entry.
 */
export function leanFor(a: ParsedAsk, index: number): { code?: string; text: string } | undefined {
  const q = a.questions[index];
  if (!q) return undefined;
  const card = cardFor(a, index);
  if (q.meta.lean?.trim()) return card.lean;
  const entries = headerLeanEntries(a);
  if (entries.size > 0) {
    const e = entries.get(index);
    return e ? { code: e.code, text: e.text } : undefined;
  }
  return card.lean;
}

// ── round 3 (M1): a lean is a suggestion, never an answer ─────

export type Values = Record<string, AnswerValue | undefined>;
const CHOICE = new Set(["choose-one", "choose", "yesno"]);
export const filled = (v: AnswerValue | undefined) => v !== undefined && v !== "" && !(Array.isArray(v) && v.length === 0) && !(typeof v === "number" && Number.isNaN(v));

/** The lean each untouched choice fork suggests, by answer key. Never part of what is sent. */
export function suggestionsFor(a: ParsedAsk, values: Values): Record<string, string> {
  const open = a.header.status === "open" || a.header.status === undefined;
  const out: Record<string, string> = {};
  if (!open) return out;
  a.questions.forEach((q, i) => {
    const k = questionKey(q, i);
    if (!CHOICE.has(q.kind) || filled(values[k])) return;
    const lean = leanCodeFor(a, i);
    if (lean) out[k] = lean;
  });
  return out;
}

/** The option values from a fork's top level down to `code`, so a nested lean also picks its parent. */
function pathTo(opts: AskOption[], code: string): string[] | undefined {
  for (const o of opts) {
    const v = o.code ?? o.label;
    if (o.code === code) return [v];
    const sub = pathTo(o.children ?? [], code);
    if (sub) return [v, ...sub];
  }
  return undefined;
}

/**
 * The suggestions on forks the operator can SEE now (MF-2), in fork order. A fork hidden by DependsOn
 * is left out: its lean shows as its own dashed suggestion once its parent is picked. This one list is
 * both what the Accept-all button names and what it accepts.
 */
export function visibleSuggestionsFor(a: ParsedAsk, values: Values, visible: ParsedAsk["questions"]): { key: string; label: string; code: string }[] {
  const s = suggestionsFor(a, values);
  return a.questions.flatMap((q, i) => {
    const key = questionKey(q, i);
    return visible.includes(q) && s[key] ? [{ key, label: forkLabel(q, i), code: s[key] }] : [];
  });
}

/** "Accept all suggestions": every suggestion on a VISIBLE fork becomes the operator's pick, and nothing else changes. */
export function acceptAll(a: ParsedAsk, values: Values, visible: ParsedAsk["questions"]): Values {
  const next = { ...values };
  for (const { key, code } of visibleSuggestionsFor(a, values, visible)) {
    const q = a.questions.find((x, i) => questionKey(x, i) === key)!;
    next[key] = pathTo(q.options, code) ?? [code];
  }
  return next;
}

/** The visible forks with no pick, by label. A note (`.other`) is not a pick. */
export function unansweredForks(a: ParsedAsk, answers: AnswerMap, visible: ParsedAsk["questions"] = visibleQuestions(a.questions, answers)): string[] {
  return a.questions.flatMap((q, i) => (visible.includes(q) && !filled(answers[questionKey(q, i)] as AnswerValue | undefined) ? [forkLabel(q, i)] : []));
}

/**
 * MF-1: a send settles the WHOLE ask, so a send that leaves visible forks unpicked (including a send
 * of notes alone) must be confirmed. Undefined when every visible fork is picked.
 */
export function sendConfirmation(unanswered: string[]): string | undefined {
  if (unanswered.length === 0) return undefined;
  const n = unanswered.length;
  return `${n} question${n === 1 ? "" : "s"} unanswered (${unanswered.join(", ")}) — send anyway? Sending settles the whole ask; ${n === 1 ? "it reaches" : "they reach"} the asker unanswered and cannot be answered here afterwards.`;
}

/** The batch tray's confirm: one line per draft that leaves forks unpicked. A decline is not partial. */
export function batchConfirmation(drafts: ParsedAsk[], refOf: (a: ParsedAsk) => string): string | undefined {
  let n = 0;
  const parts = drafts.flatMap((d) => {
    if (!d.draft || d.draft.declined) return [];
    const left = unansweredForks(d, d.draft.answers ?? {});
    n += left.length;
    return left.length ? [`${refOf(d)}: ${left.join(", ")}`] : [];
  });
  if (!parts.length) return undefined;
  return `${n} question${n === 1 ? "" : "s"} unanswered — send anyway? Each ask is settled when sent. ${parts.join(" · ")}`;
}

export type Filter = "open" | "drafts" | "settled" | "all";
/**
 * SF-4: the one predicate behind both a filter's list and its count. Settled is answered or declined;
 * a superseded ask is in All only (it was replaced, not settled by anyone here).
 */
export function rowInFilter(r: Pick<Row, "status" | "draft">, f: Filter): boolean {
  return f === "all" ? true : f === "drafts" ? r.draft : f === "settled" ? r.status === "answered" || r.status === "declined" : r.status === "open";
}

/**
 * SF-5: what survives a remount of the card. Unsent notes (per fork, and to the asker) are kept by ask
 * and fork and restored over what the file holds. Unsent picks come back only at the same revision:
 * when the revision moved, the forks may have changed, so they are cleared and the notice says so.
 */
export type Unsent = { revision: string; values: Values; text: Record<string, string>; note: string };
export function restoreUnsent(
  init: { values: Values; text: Record<string, string>; note: string },
  kept: Unsent | undefined,
  revision: string,
  keys: string[],
): { values: Values; text: Record<string, string>; note: string; notice: string } {
  if (!kept) return { ...init, notice: "" };
  const same = kept.revision === revision;
  const text = { ...init.text };
  const changedNotes: string[] = [];
  const lost: string[] = [];
  for (const [k, v] of Object.entries(kept.text)) {
    if (!v.trim() || v === init.text[k]) continue;
    if (keys.includes(k)) {
      text[k] = v;
      changedNotes.push(k);
    } else lost.push(k);
  }
  const noteKept = !!kept.note.trim() && kept.note !== init.note;
  const note = noteKept ? kept.note : init.note;
  const values = same ? { ...init.values, ...kept.values } : init.values;
  const droppedPicks = same ? 0 : Object.keys(kept.values).filter((k) => filled(kept.values[k]) && JSON.stringify(kept.values[k]) !== JSON.stringify(init.values[k])).length;
  if (same || (!changedNotes.length && !noteKept && !lost.length && !droppedPicks)) return { values, text, note, notice: "" };
  const bits = [
    changedNotes.length || noteKept ? "your unsent notes are kept below" : "",
    lost.length ? `your notes on ${lost.join(", ")} have no fork to go back to and are not shown` : "",
    droppedPicks ? `your ${droppedPicks} unsent pick${droppedPicks === 1 ? " was" : "s were"} cleared, because the forks may have changed` : "",
  ].filter(Boolean);
  return { values, text, note, notice: `The ask changed under you (now revision ${revision}): ${bits.join("; ")}.` };
}

/**
 * The answer map to save or send: only forks the operator picked (or picked before, in a draft), on
 * forks still visible, plus any free-text notes. A suggestion is never in it.
 */
export function buildAnswers(a: ParsedAsk, values: Values, text: Record<string, string>, visible: ParsedAsk["questions"]): AnswerMap {
  const out: AnswerMap = {};
  a.questions.forEach((q, i) => {
    if (!visible.includes(q)) return;
    const k = questionKey(q, i);
    if (filled(values[k])) out[k] = values[k] as AnswerValue;
    if (text[k]?.trim()) out[`${k}.other`] = text[k].trim();
  });
  return out;
}
