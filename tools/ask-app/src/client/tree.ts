/**
 * ASKTREEUI: pure helpers for the context an option carries — its per-option fields as rows, the
 * forks that picking it opens (derived from DependsOn, no field of its own), a fork's one-way mark,
 * the compare table and the outline. Every shape is lib/format.ts's (AskOption, AskQuestion,
 * AnswerMap); none is restated here.
 */
import { questionKey, visibleQuestions, type AnswerMap, type AskOption, type AskQuestion } from "../lib/format.ts";
import { forkLabel } from "./model.ts";
import { optionTally, tallyText } from "./panel.ts";

/** The per-option fields the card and the compare table draw, in their order: Elegance beside Cost. */
export type FieldKey = Extract<keyof AskOption, "cost" | "elegance" | "effort" | "unblocks" | "then">;
export const OPTION_ROWS: [FieldKey, string][] = [
  ["cost", "Cost"], ["elegance", "Elegance"], ["effort", "Effort"], ["unblocks", "Unblocks"], ["then", "Then"],
];
export const NO_ELEGANCE = "no elegance given";

const tree = (opts: AskOption[]): AskOption[] => opts.flatMap((o) => [o, ...tree(o.children ?? [])]);

/** An option's answer value: its code, or its label when it has none. */
export const valueOf = (o: AskOption) => o.code ?? o.label;
/** An option's label as the card shows it, without a "(lean)" the author wrote into it. */
export const shownLabel = (o: AskOption) => o.label.replace(/\s*\(lean\)\s*$/i, "");

/** True when any option of the fork, at any depth, states its Elegance: then the others say they do not. */
export function forkGivesElegance(q: AskQuestion): boolean {
  return tree(q.options).some((o) => !!o.elegance?.trim());
}

export type ForkRef = { index: number; label: string; title: string };
const refOf = (questions: AskQuestion[], i: number): ForkRef => ({ index: i, label: forkLabel(questions[i], i), title: questions[i].title });

/** The forks that a pick of this option opens: every fork whose `DependsOn: ASK_<this fork>=<this code>`. */
export function opensUnder(questions: AskQuestion[], q: AskQuestion, o: AskOption): ForkRef[] {
  if (!q.askName || !o.code) return [];
  return questions.flatMap((d, i) => (d.dependsOn?.ask === q.askName && d.dependsOn?.code === o.code ? [refOf(questions, i)] : []));
}

/** The forks that follow any answer to this fork (`DependsOn: ASK_<this fork>`, no code). */
export function anyAnswerOpens(questions: AskQuestion[], q: AskQuestion): ForkRef[] {
  if (!q.askName) return [];
  return questions.flatMap((d, i) => (d.dependsOn?.ask === q.askName && !d.dependsOn?.code ? [refOf(questions, i)] : []));
}

/**
 * A fork is one-way when its own `Reversible:` line says so in its first word: no, one-way or
 * irreversible. Nothing else is read — not an option's prose — so a badge is never guessed.
 */
export function isOneWay(reversible: string | undefined): boolean {
  return /^\s*(?:no\b|one[- ]way\b|irreversible\b|not reversible\b)/i.test(reversible ?? "");
}

export type CompareRow = { label: string; cells: (string | undefined)[]; same: boolean; missing?: string };

/**
 * A fork's options side by side: one column per top-level option, one row per field (Cost,
 * Elegance, Effort, Unblocks, Then, then Panel from panel.ts's tally). A row no option fills is not
 * drawn; it is named in `omitted`. `same` marks a row every option fills with the same text.
 */
export function compareRows(q: AskQuestion): { columns: { code?: string; label: string }[]; rows: CompareRow[]; omitted: string[] } {
  const opts = q.options;
  const rows: CompareRow[] = [];
  const omitted: string[] = [];
  const push = (label: string, cells: (string | undefined)[], missing?: string) => {
    if (!cells.some((c) => c?.trim())) return void omitted.push(label);
    const filled = cells.every((c) => c?.trim());
    rows.push({ label, cells, same: filled && cells.length > 1 && cells.every((c) => c!.trim() === cells[0]!.trim()), ...(missing ? { missing } : {}) });
  };
  for (const [k, label] of OPTION_ROWS) push(label, opts.map((o) => o[k]?.trim() || undefined), k === "elegance" ? NO_ELEGANCE : undefined);
  push("Panel", opts.map((o) => {
    const t = optionTally(q, o);
    return t.of > 0 ? tallyText(t.picked, t.of, t.under) : undefined;
  }));
  return { columns: opts.map((o) => ({ ...(o.code ? { code: o.code } : {}), label: o.label })), rows, omitted };
}

export type OutlinePick = { value: string; label: string; elegance?: string };
export type OutlineEntry = ForkRef & {
  answered: boolean;
  /** Its parent fork is not answered yet. */
  waiting: boolean;
  /** S2: its parent was answered, with another code — `ASK_P = CODE`; nothing is pending. */
  notOpened?: string;
  picked: string[];
  /** N4/S5: each pick's label and, where the option states one, its Elegance. */
  picks: OutlinePick[];
  after?: string;
  opens: string[];
};

/**
 * One entry per fork: answered when the answers so far hold a value for it; hidden by format.ts's
 * visibleQuestions, it is waiting while its parent is unanswered and not opened once the parent was
 * answered without its code. `after` is the dependency as the fork card's foot words it, `opens` the
 * labels of the forks that depend on it.
 */
export function outlineOf(questions: AskQuestion[], answers: AnswerMap): OutlineEntry[] {
  const visible = visibleQuestions(questions, answers);
  return questions.map((q, i) => {
    const v = answers[questionKey(q, i)];
    const picked = Array.isArray(v) ? v : [];
    const answered = Array.isArray(v) ? v.length > 0 : v !== undefined && String(v).trim() !== "";
    const hidden = !visible.includes(q);
    const parent = q.dependsOn ? answers[q.dependsOn.ask] : undefined;
    const given = Array.isArray(parent) ? parent : parent === undefined || String(parent).trim() === "" ? [] : [String(parent)];
    const notOpened = hidden && given.length > 0 ? `ASK_${q.dependsOn!.ask} = ${given.join(", ")}` : undefined;
    const waiting = hidden && !notOpened;
    const opts = tree(q.options);
    const picks = picked.map((value): OutlinePick => {
      const o = opts.find((x) => valueOf(x) === value);
      const el = o?.elegance?.trim();
      return { value, label: o ? shownLabel(o) : value, ...(el ? { elegance: el } : {}) };
    });
    const after = q.dependsOn ? `ASK_${q.dependsOn.ask}${q.dependsOn.code ? `=${q.dependsOn.code}` : ""}` : undefined;
    const opens = q.askName ? questions.flatMap((d, j) => (d.dependsOn?.ask === q.askName ? [forkLabel(d, j)] : [])) : [];
    return { ...refOf(questions, i), answered, waiting, ...(notOpened ? { notOpened } : {}), picked, picks, after, opens };
  });
}

/** N2: a mark on the fork an outline click reached, taken off after `ms` (restarted on a repeat click). */
export function markReached(el: { classList: { add(c: string): void; remove(c: string): void } } | null, ms = 1600): void {
  if (!el) return;
  el.classList.remove("reached");
  el.classList.add("reached");
  setTimeout(() => el.classList.remove("reached"), ms);
}

/** S6: the compare view's column count for the stylesheet's breakpoints, capped at 5. */
export const compareCols = (n: number) => String(Math.min(Math.max(n, 1), 5));

/** S6: what a stacked compare cell is labelled with: the option's code and its label, cut short. */
export function cellLabel(c: { code?: string; label: string }, max = 48): string {
  const label = c.label.replace(/\s*\(lean\)\s*$/i, "");
  const short = label.length > max ? `${label.slice(0, max).replace(/\s+\S*$/, "")} …` : label;
  return c.code ? `${c.code} · ${short}` : short;
}
