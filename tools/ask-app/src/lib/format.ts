/**
 * The /ask file format: a `---` header block of one-line `key: value` fields, free prose, then
 * questions in the engine's decision-tree syntax, and once answered a fenced ```json answer block.
 *
 * The decision-tree grammar mirrors ~/Projects/ideas-bundle/interactions/parse-decision-tree.ts
 * (`## [¶ASK_NAME:] (Choose one|Choose): Title`, options `- [ ] [CODE] Label`, an indented
 * non-list line as the option's description, nesting by indent). It is restated here, not
 * imported, because that file lives in another repository. One addition: a `DependsOn:` metadata
 * line under a heading, `DependsOn: ASK_OTHER` or `DependsOn: ASK_OTHER=CODE`, which hides the
 * question until the other one is answered (with that code, when one is named). And a fenced
 * block indented under an option is that option's, kept verbatim in its description as markdown.
 *
 * Pure string functions only — no fs, no node — so the React client imports this file as is.
 */

export type AskOption = {
  label: string;
  code?: string;
  description?: string;
  /** Per-option card lines: `Cost:`, `Effort:`, `Blast:` indented under the option. */
  cost?: string;
  effort?: string;
  blastRadius?: string;
  children?: AskOption[];
};

/**
 * The kind comes from the heading word: `Choose one` · `Choose` (v1, the ideas grammar) and, from
 * v2, `Rank` · `Text` · `Number` · `Date` · `Yes or no`.
 */
export type QuestionKind = "choose-one" | "choose" | "rank" | "text" | "number" | "date" | "yesno";

/** One council lens's read of a question: which option it picks and why, in one line. */
export type PanelRead = { lens: string; pick: string; why: string };

export type AskQuestion = {
  title: string;
  askName?: string;
  kind: QuestionKind;
  multiSelect: boolean;
  dependsOn?: { ask: string; code?: string };
  options: AskOption[];
  /** Card lines under the heading (`Stake: …`, `Lean: …`), keyed by the lower-camel field name. */
  meta: Record<string, string>;
  /** Repeated `Evidence:` lines under the heading. */
  evidence: string[];
  /**
   * The author's prose under the heading that is neither a card line nor an option — the reasons
   * before the options, and unindented notes after them. Kept and rendered as the fork's context.
   */
  prose?: string;
  /** Unindented prose after the options, before the next heading: shown after the fork's card. */
  proseAfter?: string;
  panel: PanelRead[];
  number?: { min?: number; max?: number; unit?: string };
  /** A fence in this fork is never closed, so it ran to the end of the file (authorWarnings says so). */
  unclosedFence?: boolean;
};

/**
 * Answers keyed by `questionKey`. Choice kinds: a non-empty list of codes (labels for codeless
 * options); rank: every top-level code once, in order; text and date: a string; number: a number.
 * `<key>.other` holds free text beside any kind — a different answer, a condition, a question back.
 */
export type AnswerValue = string[] | string | number;
export type AnswerMap = Record<string, AnswerValue>;

export type AskAnswer = {
  answers?: AnswerMap;
  /** A refusal is a record, never an empty answer (INV_REFUSAL_IS_NOT_EMPTY): it carries its reason. */
  declined?: boolean;
  reason?: string;
  revision?: number;
  note?: string;
  answeredBy?: string;
  /** How the answerer was established (`ask-app loopback UI`, `cli`): the stamp says what was proven. */
  answeredVia?: string;
  answeredAt?: string;
  /**
   * IDE-339: the class of grant a manager's answer gives (A–D), written only by the answering manager
   * through `engine ask answer --grant`. Never on the operator's answer, a reserved ask, or a draft.
   */
  grantClass?: GrantClass;
};

/** IDE-339: the grant classes a manager's answer may carry. */
export const GRANT_CLASSES = ["A", "B", "C", "D"] as const;
export type GrantClass = (typeof GRANT_CLASSES)[number];

/** A saved, unsent answer: kept in the file, never in a message, until a batch send settles it. */
export type AskDraft = AskAnswer & { basedOn: number; savedAt?: string; bodyHash?: string };

export type AskHeader = Record<string, string> & {
  id?: string;
  to?: string;
  from?: string;
  status?: string;
  revision?: string;
  dependsOn?: string;
};

export type ParsedAsk = {
  header: AskHeader;
  preamble: string;
  questions: AskQuestion[];
  answer?: AskAnswer;
  draft?: AskDraft;
  /**
   * IDE-339: every answer this one replaced, oldest first, each record as it was written (revision
   * and all), from the file's ```json history``` fence. Empty when nothing was replaced.
   */
  history: AskAnswer[];
  /**
   * IDE-339 round 2 (NIT-1): why the history fence could not be read whole — not valid JSON, not a
   * list, or entries that are not answer records. The ask still parses (it stays listed), `history`
   * holds only the entries that are records, and a settle is refused while this is set, so a bad
   * fence is never silently overwritten.
   */
  historyError?: string;
};

export const HEADER_FIELDS = [
  "id", "to", "from", "why", "importance", "stakes", "context", "alternatives",
  "lean", "falsifier", "status", "revision", "dependsOn", "created",
  // v2: all optional; a file without them reads exactly as before.
  "tickets", "stake", "unblocks", "related", "counter", "evidence", "rank", "topic",
  "confidence", "reversible", "verify", "ifUnanswered", "neededBy", "askedBy", "blocks",
  "reserved-for", "provenance", "sourceRef",
] as const;

/** Fields written by the store as the ask moves, never set by `engine ask new`. */
export const STAMP_FIELDS = [
  "ruledInChat", "revisions", "delivery", "deliveryNote", "deliveryWriter", "readAt", "readBy", "reads", "acted", "actedAt", "actedBy", "draft", "forwards",
  // `engine ask supersede`: on the replaced ask, its replacement, when, and who replaced it; on the replacement, what it replaced.
  "superseded-by", "superseded-at", "superseded-actor", "supersedes",
  // IDE-304: the answer a later answer replaced, on one line (revision, who, when, what).
  "replaced",
  // IDE-339: the answerer whose settled answer a different answerer replaced.
  "overruled",
] as const;

const KIND_WORDS: Record<string, QuestionKind> = {
  "Choose one": "choose-one", Choose: "choose", Rank: "rank", Text: "text", Number: "number", Date: "date", "Yes or no": "yesno",
};
const HEADING_RE = /^##\s+(?:¶ASK_(\w+):\s+)?(Choose one|Choose|Rank|Text|Number|Date|Yes or no):\s+(.+)$/;
/** Card lines a question may carry under its heading. `Evidence` and `Panel` may repeat. */
const META_KEYS: Record<string, string> = {
  stake: "stake", unblocks: "unblocks", related: "related", lean: "lean", counter: "counter", rank: "rank",
  topic: "topic", confidence: "confidence", reversible: "reversible", verify: "verify", falsifier: "falsifier",
  ifunanswered: "ifUnanswered", neededby: "neededBy", blocks: "blocks", context: "context", range: "range", unit: "unit",
};
const META_RE = /^([A-Za-z][A-Za-z ]*?):\s+(.+)$/;
const OPTION_META: Record<string, "cost" | "effort" | "blastRadius"> = { cost: "cost", effort: "effort", blast: "blastRadius", blastradius: "blastRadius", "blast radius": "blastRadius" };
const PANEL_RE = /^(.+?)\s*(?:→|->)\s*(\S+?)\s*(?:—|–|:|\s-)\s*(.+)$/;
// v1 took 2–4 capitals; v2 also takes one letter (A, B, as /decide boards key options) and digits (L2).
/**
 * An option code: a capital, then up to 11 capitals or digits — 12 at most (`A`, `L2`, `KEEPBROAD`).
 * v1 took 2–4 and v2 1–5, and a longer code (`[RESCOPE]`) silently became label text; anything the
 * rule does not read is now refused at `new`/`revise` by invalidOptionCodes, never folded in.
 */
export const CODE_MAX = 12;
const CODE_SRC = `[A-Z][A-Z0-9]{0,${CODE_MAX - 1}}`;
const CODE_RE = new RegExp(`^\\[(${CODE_SRC})\\]\\s*`);
// A checkbox is `[ ]` or `[x]`. `[X]` is a checkbox only when a `[CODE]` follows it; alone, `- [X] Xray`
// is option code X.
const CHECKBOX_RE = /^\[[ x]\]\s*/;
const CHECKED_X_RE = /^\[X\]\s*(?=\[)/;
// Any token after `=` is taken as the code, so a bad one is REFUSED at filing (invalidDependsOn),
// never silently turned into prose.
const DEPENDS_RE = /^DependsOn:\s*(?:¶|§)?\s*ASK_(\w+)(?:\s*=\s*(\S+))?\s*$/;
// Record fences are whole lines of exactly three backticks: an inline or 4-backtick quote is body
// text, shown as written, and never a record (`new` refuses the indented forms).
/** The store-written record fences (`rename-seat` rewrites seats inside them). */
export const ANSWER_FENCES = /(?:^|\n)```json answer\n([\s\S]*?)\n```(?=\n|$)\n?/g;
export const DRAFT_FENCES = /(?:^|\n)```json draft\n([\s\S]*?)\n```(?=\n|$)\n?/g;
/** IDE-339: the earlier answers, one JSON array in one fence, written by settle() before the answer. */
export const HISTORY_FENCES = /(?:^|\n)```json history\n([\s\S]*?)\n```(?=\n|$)\n?/g;
/** Any record fence (`json answer`, `json draft` or `json history`), wherever it sits: a body never carries one (M1). */
export const RECORD_FENCE_RE = /^\s*```json (?:answer|draft|history)\b/m;
/** The text with every record fence taken out: what the ask asks. */
const stripRecords = (t: string) => t.replace(ANSWER_FENCES, "\n").replace(DRAFT_FENCES, "\n").replace(HISTORY_FENCES, "\n");

export class AskFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AskFormatError";
  }
}

/**
 * The ask was replaced by another (`engine ask supersede`): nothing answers, declines or drafts it
 * any more. `by` is the replacement's `<seat>/<id>`, so a refusal can say where to answer instead.
 */
export class SupersededError extends AskFormatError {
  readonly by: string;
  constructor(id: string, by: string) {
    super(`ask ${id} is superseded${by ? ` by ${by}; answer that one instead` : "; answer its replacement"}`);
    this.name = "SupersededError";
    this.by = by;
  }
}

/** Refuse any answer, decline or draft on a superseded ask, naming its replacement. */
export function assertNotSuperseded(ask: ParsedAsk) {
  if (ask.header.status === "superseded") throw new SupersededError(ask.header.id ?? "", ask.header["superseded-by"] ?? "");
}

/** The ask moved on since the answerer read it (INV_ONE_CHOSEN_DESTINATION: one answer wins). */
export class StaleRevisionError extends AskFormatError {
  readonly current: number;
  constructor(expected: number, current: number) {
    super(`stale revision: expected ${expected}, the ask is at revision ${current}`);
    this.name = "StaleRevisionError";
    this.current = current;
  }
}

// ── header ────────────────────────────────────────────────

function splitHeader(text: string): { headerLines: string[]; rest: string } {
  const lines = text.split("\n");
  if (lines[0]?.trim() !== "---") throw new AskFormatError("missing --- header block on line 1");
  const end = lines.indexOf("---", 1);
  if (end === -1) throw new AskFormatError("header block is not closed with ---");
  return { headerLines: lines.slice(1, end), rest: lines.slice(end + 1).join("\n") };
}

function parseHeader(lines: string[]): AskHeader {
  const header: AskHeader = {};
  for (const line of lines) {
    const m = line.match(/^([A-Za-z][\w-]*):\s?(.*)$/);
    if (m) header[m[1]] = m[2].trim();
  }
  return header;
}

/** Set one header field, rewriting it in place or appending it before the closing `---`. */
export function setHeaderField(text: string, key: string, value: string): string {
  if (/\n/.test(value)) throw new AskFormatError(`header value for ${key} must be one line`);
  const lines = text.split("\n");
  if (lines[0]?.trim() !== "---") throw new AskFormatError("missing --- header block on line 1");
  const end = lines.indexOf("---", 1);
  if (end === -1) throw new AskFormatError("header block is not closed with ---");
  const re = new RegExp(`^${key}:`);
  const at = lines.slice(1, end).findIndex((l) => re.test(l));
  const line = value === "" ? `${key}:` : `${key}: ${value}`;
  if (at === -1) lines.splice(end, 0, line);
  else lines[at + 1] = line;
  return lines.join("\n");
}

/** Remove a header field if present. */
export function removeHeaderField(text: string, key: string): string {
  const lines = text.split("\n");
  const end = lines.indexOf("---", 1);
  if (lines[0]?.trim() !== "---" || end === -1) throw new AskFormatError("missing --- header block on line 1");
  const re = new RegExp(`^${key}:`);
  const at = lines.slice(1, end).findIndex((l) => re.test(l));
  if (at !== -1) lines.splice(at + 1, 1);
  return lines.join("\n");
}

// ── decision tree ─────────────────────────────────────────

type RawOption = { indent: number; code?: string; label: string; description?: string; cost?: string; effort?: string; blastRadius?: string; afterFence?: boolean };

function parseOptionLines(lines: string[], folds: Folds): RawOption[] {
  const raw: RawOption[] = [];
  for (const line of lines) {
    const stripped = line.trimStart();
    if (!stripped) continue;
    const indent = line.length - stripped.length;
    if (stripped.startsWith("- ")) {
      let rest = stripped.slice(2);
      rest = rest.replace(CHECKBOX_RE, "").replace(CHECKED_X_RE, "");
      let code: string | undefined;
      const cm = rest.match(CODE_RE);
      if (cm) {
        code = cm[1];
        rest = rest.slice(cm[0].length);
      }
      const label = rest.trim() || code;
      if (!label) continue;
      raw.push({ indent, code, label });
    } else {
      // An indented line belongs to the nearest option above it with a smaller indent: a line at a
      // child's own indent is its parent's, as in markdown, and is never dropped.
      let at = raw.length - 1;
      while (at >= 0 && raw[at].indent >= indent) at--;
      if (at < 0) continue;
      const last = raw[at];
      const fence = unfoldFence(line, folds);
      if (fence) {
        // A fence keeps its lines: the description becomes markdown with the fence as its own block.
        const code = fence.join("\n");
        last.description = last.description === undefined ? code : `${last.description}\n\n${code}`;
        last.afterFence = true;
        continue;
      }
      const m = stripped.match(META_RE);
      const field = m ? OPTION_META[m[1].toLowerCase()] : undefined;
      if (field) last[field] = m![2].trim();
      // N-2: further indented prose lines continue the description rather than vanishing; after a
      // fence they start a new paragraph, so they are never glued onto its closing line.
      else if (last.afterFence) {
        last.description = `${last.description}\n\n${stripped}`;
        last.afterFence = false;
      } else last.description = last.description === undefined ? stripped : `${last.description} ${stripped}`;
    }
  }
  return raw;
}

function buildTree(raw: RawOption[]): AskOption[] {
  const out: AskOption[] = [];
  let i = 0;
  while (i < raw.length) {
    const item = raw[i];
    const opt: AskOption = { label: item.label };
    if (item.code) opt.code = item.code;
    if (item.description) opt.description = item.description;
    if (item.cost) opt.cost = item.cost;
    if (item.effort) opt.effort = item.effort;
    if (item.blastRadius) opt.blastRadius = item.blastRadius;
    let j = i + 1;
    while (j < raw.length && raw[j].indent > item.indent) j++;
    if (j > i + 1) opt.children = buildTree(raw.slice(i + 1, j));
    out.push(opt);
    i = j;
  }
  return out;
}

function parseQuestions(body: string): { preamble: string; questions: AskQuestion[] } {
  const lines = body.split("\n");
  const questions: AskQuestion[] = [];
  const preambleLines: string[] = [];
  let inFence = false;
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.trim().startsWith("```")) {
      inFence = !inFence;
      if (questions.length === 0) preambleLines.push(line);
      i++;
      continue;
    }
    const m = inFence ? null : line.match(HEADING_RE);
    if (!m) {
      if (questions.length === 0) preambleLines.push(line);
      i++;
      continue;
    }
    const kind = KIND_WORDS[m[2]];
    const q: AskQuestion = { title: m[3].trim(), kind, multiSelect: kind === "choose", options: [], meta: {}, evidence: [], panel: [] };
    if (m[1]) q.askName = m[1];
    i++;
    const body: string[] = [];
    const folds = newFolds();
    while (i < lines.length && !/^#{1,2}\s/.test(lines[i])) {
      const line = lines[i];
      if (line.trim().startsWith("```")) {
        // A fenced block inside a fork never ends the fork. At the top level it is the fork's prose,
        // kept whole. Indented, it may belong to the option above it, so it travels as ONE body line
        // (see Folds) that the option grammar treats as an indented continuation.
        const open = line.trim().match(/^`+/)![0];
        const fence: string[] = [line];
        let closed = false;
        i++;
        while (i < lines.length) {
          fence.push(lines[i]);
          const close = lines[i].trim();
          i++;
          if (close.startsWith(open) && /^`+$/.test(close)) {
            closed = true;
            break;
          }
        }
        // N2: an unclosed fence runs to the end of the file, taking later forks with it.
        if (!closed) q.unclosedFence = true;
        if (/^\s/.test(line)) body.push(fold(folds, fence));
        else body.push(...fence, folds.end);
        continue;
      }
      const dm = line.trim().match(DEPENDS_RE);
      const mm = line.startsWith(" ") || line.startsWith("\t") ? null : line.match(META_RE);
      if (dm) q.dependsOn = dm[2] ? { ask: dm[1], code: dm[2] } : { ask: dm[1] };
      else if (mm && mm[1].toLowerCase() === "evidence") q.evidence.push(mm[2].trim());
      else if (mm && mm[1].toLowerCase() === "panel") {
        const pm = mm[2].trim().match(PANEL_RE);
        if (pm) q.panel.push({ lens: pm[1].trim(), pick: pm[2].trim(), why: pm[3].trim() });
      } else if (mm && META_KEYS[mm[1].toLowerCase()]) q.meta[META_KEYS[mm[1].toLowerCase()]] = mm[2].trim();
      else body.push(line);
      i++;
    }
    const { before, block, after } = splitForkBody(body, folds);
    const proseText = tidy(before, folds);
    if (proseText) q.prose = proseText;
    const afterText = tidy(after, folds);
    if (afterText) q.proseAfter = afterText;
    q.options = buildTree(parseOptionLines(block, folds));
    if (kind === "yesno" && q.options.length === 0) q.options = [{ label: "Yes", code: "YES" }, { label: "No", code: "NO" }];
    if (kind === "number") {
      const r = q.meta.range?.match(/^\s*(-?[\d.]+)?\s*\.\.\s*(-?[\d.]+)?\s*$/);
      q.number = {};
      if (r?.[1] !== undefined) q.number.min = Number(r[1]);
      if (r?.[2] !== undefined) q.number.max = Number(r[2]);
      if (q.meta.unit) q.number.unit = q.meta.unit;
    }
    questions.push(q);
  }
  return { preamble: preambleLines.join("\n"), questions };
}

/**
 * Fences inside one fork. A fence at the fork's top level is kept as its lines followed by `end`, a
 * line that stops an options group. An indented fence is folded into ONE line, `<indent><tag><n>`,
 * and its lines (dedented by the fence's own indent; a line indented less loses only what it has)
 * are kept in `fences[n]`. Being one non-blank indented line, it continues an options group whatever
 * the fence holds. The tag carries a per-parse nonce, so no text an author writes can pose as a fold
 * or an end, and unfolding is a table lookup that cannot throw.
 */
type Folds = { tag: string; end: string; fences: string[][] };
function newFolds(): Folds {
  const nonce = `${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`;
  return { tag: `\u0000fence:${nonce}:`, end: `\u0000fence-end:${nonce}`, fences: [] };
}
function fold(folds: Folds, fence: string[]): string {
  const indent = fence[0].length - fence[0].trimStart().length;
  const dedent = (l: string) => l.slice(Math.min(indent, l.length - l.trimStart().length));
  folds.fences.push(fence.map(dedent));
  return `${fence[0].slice(0, indent)}${folds.tag}${folds.fences.length - 1}`;
}
/** The fence a folded line holds, as dedented lines; undefined for any other line. */
function unfoldFence(line: string, folds: Folds): string[] | undefined {
  const s = line.trimStart();
  if (!s.startsWith(folds.tag)) return undefined;
  const n = s.slice(folds.tag.length);
  return /^\d+$/.test(n) ? folds.fences[Number(n)] : undefined;
}
/** Prose lines as written: a folded fence back at its own indent, the end markers gone. */
function tidy(ls: string[], folds: Folds): string {
  return ls
    .filter((l) => l !== folds.end)
    .flatMap((l) => {
      const f = unfoldFence(l, folds);
      if (!f) return [l];
      const pad = l.slice(0, l.length - l.trimStart().length);
      return f.map((x) => (x ? pad + x : x));
    })
    .join("\n")
    .replace(/^\s*\n/, "")
    .replace(/\s+$/, "");
}

type Group = { start: number; end: number; marked: boolean; coded: boolean; folded?: boolean };

/**
 * Split a fork's lines into its prose, its options and the prose after them. The options are the
 * LAST list of options in the fork — a top-level `- ` line with its indented lines — so a `- [ ]`
 * line in the reasons above (a checklist, an example) is prose, never an answerable option. An
 * earlier list joins the options only when nothing but blank lines separates it from them and it
 * agrees with them on having codes. When any list in the fork is coded, only coded lists are
 * options; else only lists with a checkbox or a code; else any list (a v1 fork of bare `- Label`).
 */
function splitForkBody(body: string[], folds: Folds): { before: string[]; block: string[]; after: string[] } {
  const groups: Group[] = [];
  let g: Group | undefined;
  const item = (l: string) => {
    let rest = l.trimStart().slice(2);
    const marked = CHECKBOX_RE.test(rest) || CHECKED_X_RE.test(rest) || CODE_RE.test(rest);
    rest = rest.replace(CHECKBOX_RE, "").replace(CHECKED_X_RE, "");
    return { marked, coded: CODE_RE.test(rest) };
  };
  body.forEach((l, idx) => {
    const top = /^- /.test(l);
    const cont = !!g && l.trim() !== "" && /^\s/.test(l) && l !== folds.end;
    if (top) {
      const it = item(l);
      // A list that holds a folded fence ends at a bullet that disagrees with it on codes or marks,
      // as the fence once ended it outright: so a plain bullet with a code example in the reasons
      // never joins the coded options under it (S1), and a plain bullet after them stays a note (S2).
      if (g?.folded && (it.coded !== g.coded || it.marked !== g.marked)) {
        groups.push(g);
        g = undefined;
      }
      if (!g) g = { start: idx, end: idx, marked: it.marked, coded: it.coded };
      else {
        g.end = idx;
        g.marked ||= it.marked;
        g.coded &&= it.coded;
      }
    } else if (cont) {
      g!.end = idx;
      if (unfoldFence(l, folds)) g!.folded = true;
    } else if (g && l.trim() === "" && /^\s+\S/.test(body.slice(idx).find((x) => x.trim() !== "") ?? "")) {
      // Blank lines inside an option (around its fence, between its paragraphs) do not end the
      // group when the option's indented body goes on after them.
    } else if (g) {
      groups.push(g);
      g = undefined;
    }
  });
  if (g) groups.push(g);
  // Most specific first: lists whose every item has a code, else lists with a checkbox or a code,
  // else any list. So a codeless checklist pasted after coded options never displaces them.
  const candidates = groups.some((x) => x.coded) ? groups.filter((x) => x.coded) : groups.some((x) => x.marked) ? groups.filter((x) => x.marked) : groups;
  if (candidates.length === 0) return { before: body, block: [], after: [] };
  let first = candidates.length - 1;
  const last = candidates[first];
  while (first > 0) {
    const prev = candidates[first - 1];
    const gap = body.slice(prev.end + 1, candidates[first].start);
    if (gap.every((l) => l.trim() === "") && prev.coded === last.coded) first--;
    else break;
  }
  const from = candidates[first].start;
  return { before: body.slice(0, from), block: body.slice(from, last.end + 1), after: body.slice(last.end + 1) };
}

/** The key a question's answer is stored under: its ask name, or `q<index>` when it has none. */
export function questionKey(q: AskQuestion, index: number): string {
  return q.askName ?? `q${index}`;
}

// ── whole file ────────────────────────────────────────────

export function parseAskFile(text: string): ParsedAsk {
  const { headerLines, rest } = splitHeader(text);
  const header = parseHeader(headerLines);
  let answer: AskAnswer | undefined;
  // An answer block counts only on an answered or declined ask: an asker cannot pre-plant one.
  // The store writes it LAST, so the last one is the record.
  const ams = [...rest.matchAll(ANSWER_FENCES)];
  const settled = header.status === "answered" || header.status === "declined";
  if (ams.length && settled) {
    try {
      answer = JSON.parse(ams[ams.length - 1][1]) as AskAnswer;
    } catch {
      throw new AskFormatError("the json answer block is not valid JSON");
    }
  }
  let draft: AskDraft | undefined;
  const open = header.status === "open" || header.status === undefined;
  const dms = [...rest.matchAll(DRAFT_FENCES)];
  if (dms.length && (open || settled)) draft = honouredDraft(rest, dms[dms.length - 1], header);
  // IDE-304: on a settled ask, only the operator's draft of a change to the operator's own answer counts.
  if (draft && !open && !(isOperatorAnswer(answer) && isOperatorName(draft.answeredBy))) draft = undefined;
  // IDE-339: like the answer, the history counts only on a settled ask, and the last fence is the record.
  const hms = [...rest.matchAll(HISTORY_FENCES)];
  const { history, historyError } = hms.length && settled ? readHistory(hms[hms.length - 1][1]) : { history: [] as AskAnswer[], historyError: undefined };
  const { preamble, questions } = parseQuestions(stripRecords(rest));
  return { header, preamble, questions, ...(answer ? { answer } : {}), ...(draft ? { draft } : {}), history, ...(historyError ? { historyError } : {}) };
}

const isRecord = (x: unknown): x is AskAnswer => !!x && typeof x === "object" && !Array.isArray(x);

/**
 * NIT-1 (round 2): the history fence's JSON, kept to the entries that are answer records (plain
 * objects). Anything else is named in `historyError` rather than thrown, so the ask still lists.
 */
function readHistory(json: string): { history: AskAnswer[]; historyError?: string } {
  let h: unknown;
  try {
    h = JSON.parse(json);
  } catch {
    return { history: [], historyError: "the json history block is not valid JSON" };
  }
  if (!Array.isArray(h)) return { history: [], historyError: "the json history block must be a list of answers" };
  const bad = h.flatMap((x, i) => (isRecord(x) ? [] : [i]));
  const history = h.filter(isRecord);
  return bad.length ? { history, historyError: `the json history block's entr${bad.length > 1 ? "ies" : "y"} ${bad.join(", ")} ${bad.length > 1 ? "are" : "is"} not answer records` } : { history };
}

/**
 * M1: a draft counts only when the store wrote it — it is the LAST block of the file (nothing but
 * whitespace after it) and its `savedAt` equals the `draft:` header the store sets beside it. A
 * draft fence anywhere else (quoted in a question, planted by an asker) is text, never a draft.
 */
function honouredDraft(rest: string, m: RegExpMatchArray, header: AskHeader): AskDraft | undefined {
  if (rest.slice((m.index ?? 0) + m[0].length).trim() !== "") return undefined;
  let d: AskDraft;
  try {
    d = JSON.parse(m[1]) as AskDraft;
  } catch {
    return undefined;
  }
  if (!d || typeof d !== "object" || !header.draft || d.savedAt !== header.draft || !Number.isInteger(d.basedOn)) return undefined;
  return d;
}

/**
 * A digest of what the ask ASKS — its body without the answer and draft records — so a draft can
 * tell that the question was edited after it was saved (S4). FNV-1a, 32 bit: pure, no node.
 */
export function bodyDigest(text: string): string {
  const body = stripRecords(splitHeader(text).rest).trim();
  let h = 0x811c9dc5;
  for (let i = 0; i < body.length; i++) {
    h ^= body.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, "0");
}

/**
 * Embed `answer` as the file's single ```json answer block, set `status: answered` and bump
 * `revision`. Answering again replaces the block. A superseded ask is refused, because its
 * replacement is the one that should carry the answer.
 */
export function currentRevision(ask: ParsedAsk): number {
  return parseInt(ask.header.revision ?? "0", 10) || 0;
}

/** The operator's own recorded answer (as the client's ruledBelow reads it: `operator…`, or a relay of it). */
/**
 * The operator by name: `operator` in any case, or the legacy relayed form on disk,
 * `operator (relayed by <seat>, <when>, via <how>)`. Not a seat whose name merely starts with it
 * (`operator:x`, `operator-bot`).
 */
export const isOperatorName = (s: string | undefined) => /^operator(?: \(relayed by [^)]*\))?$/i.test(s?.trim() ?? "");
export const isOperatorAnswer = (a: AskAnswer | undefined) => !!a && (isOperatorName(a.answeredBy) || !!relayerOf(a));

const REQUEST_LINE_RE = /^request: (\S+) — (.+)$/;

/**
 * IDE-304: what a new answer replaces, on one line, for the `replaced:` stamp and the change push:
 * `revision N by W at T; was <picks | a decline: reason | a request: kind — text (with picks)>`.
 * Undefined when the ask holds no settled answer.
 */
export function replacedSummary(ask: ParsedAsk): string | undefined {
  const a = ask.answer;
  if (!a || (ask.header.status !== "answered" && ask.header.status !== "declined")) return undefined;
  const rev = a.revision ?? currentRevision(ask);
  const picks = ask.questions.flatMap((q, i) => {
    const v = a.answers?.[questionKey(q, i)];
    if (v === undefined) return [];
    return [`${q.askName ?? `Q${i + 1}`} ${Array.isArray(v) ? v.join("+") : String(v)}`];
  }).join(", ");
  const req = (a.note ?? "").split("\n").map((l) => l.trim().match(REQUEST_LINE_RE)).find(Boolean);
  const was = a.declined
    ? `a decline: ${a.reason ?? ""}`
    : req
      ? `a request: ${req[1]} — ${req[2]}${picks ? ` (with ${picks})` : ""}`
      : picks || "no picks";
  return `revision ${rev} by ${a.answeredBy || "unknown"} at ${a.answeredAt ?? "?"}; was ${was}`.replace(/\s+/g, " ").trim();
}

/** One answerer, whatever form its name took: the operator relayed or not is the operator. */
const answererOf = (a: AskAnswer) => (isOperatorName(a.answeredBy) ? "operator" : (a.answeredBy ?? "").trim());

/**
 * IDE-339: who a new answer by `record` overrules — the prior settled answer's answerer, when that
 * is someone else. Undefined for a first answer or a change by the same answerer.
 */
export function overruledBy(ask: ParsedAsk, record: AskAnswer): string | undefined {
  const prior = ask.header.status === "answered" || ask.header.status === "declined" ? ask.answer : undefined;
  // NIT-2 (round 2): a prior answer that names nobody overrules nobody we can name; stamp nothing.
  if (!prior || !prior.answeredBy?.trim() || answererOf(prior) === answererOf(record)) return undefined;
  return prior.answeredBy;
}

/**
 * IDE-339 round 2: whom the CURRENT answer overruled — the last replaced answer's answerer, when it
 * is someone else. Read from the history, not the `overruled:` header, because the header keeps its
 * trail across a later self-change (NIT-3) while the push for that self-change is no overrule.
 */
export function overruledNow(ask: ParsedAsk): string | undefined {
  const prev = ask.history.at(-1);
  if (!ask.answer || !prev || !prev.answeredBy?.trim() || answererOf(prev) === answererOf(ask.answer)) return undefined;
  return prev.answeredBy;
}

function settle(text: string, record: AskAnswer, status: "answered" | "declined", expectedRevision?: number): string {
  const ask = parseAskFile(text);
  assertNotSuperseded(ask);
  // NIT-1 (round 2): a settle rewrites the history fence, so one it cannot read whole is refused.
  if (ask.historyError) throw new AskFormatError(`${ask.historyError}: fix or remove it by hand before this ask is answered again`);
  const cur = currentRevision(ask);
  if (expectedRevision !== undefined && expectedRevision !== cur) throw new StaleRevisionError(expectedRevision, cur);
  const revision = String(cur + 1);
  const answer = { ...record, revision: cur + 1 };
  const replaced = replacedSummary(ask);
  const overruled = overruledBy(ask, record);
  // IDE-339: the answer being replaced joins the history whole, after the ones it replaced.
  const history = replaced && ask.answer ? [...ask.history, ask.answer] : ask.history;
  let out = setHeaderField(text, "status", status);
  out = replaced ? setHeaderField(out, "replaced", replaced) : removeHeaderField(out, "replaced");
  // NIT-3 (round 2): a self-change keeps the stamp, so the header still says an overrule happened;
  // only a different answerer's answer moves it, to the answerer that one overruled.
  if (overruled) out = setHeaderField(out, "overruled", overruled);
  out = setHeaderField(out, "revision", revision);
  // A new answer is unread and not yet acted on, whatever the last one was.
  for (const k of ["readAt", "readBy", "reads", "acted", "actedAt", "actedBy", "draft", "deliveryWriter"]) out = removeHeaderField(out, k);
  out = stripRecords(out);
  out = out.replace(/\n*$/, "\n");
  const kept = history.length ? `\n\`\`\`json history\n${JSON.stringify(history, null, 2)}\n\`\`\`\n` : "";
  return `${out}${kept}\n\`\`\`json answer\n${JSON.stringify(answer, null, 2)}\n\`\`\`\n`;
}

/** Answer the ask. With `expectedRevision`, refuse (StaleRevisionError) if the ask has moved since it was read. */
export function writeAnswer(text: string, answer: AskAnswer, expectedRevision?: number): string {
  return settle(text, { ...answer, declined: undefined }, "answered", expectedRevision);
}

/** Decline the ask: `status: declined`, with a required, non-blank reason. */
export function writeDecline(
  text: string,
  d: { reason: string; answeredBy?: string; answeredVia?: string; answeredAt?: string; note?: string; grantClass?: GrantClass },
  expectedRevision?: number,
): string {
  if (!d.reason || !d.reason.trim()) throw new AskFormatError("a decline needs a non-empty reason");
  return settle(text, { declined: true, ...d, reason: d.reason.trim() }, "declined", expectedRevision);
}

function allValues(opts: AskOption[]): string[] {
  return opts.flatMap((o) => [o.code ?? o.label, o.label, ...allValues(o.children ?? [])]);
}

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
function isRealDate(v: string): boolean {
  const m = v.match(DATE_RE);
  if (!m) return false;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  return d.getUTCFullYear() === +m[1] && d.getUTCMonth() === +m[2] - 1 && d.getUTCDate() === +m[3];
}

/**
 * Refuse an answer that says nothing or says something the ask did not ask (INV_REFUSAL_IS_NOT_EMPTY).
 * Keys: a question key, valued by its kind (see AnswerMap), or `<key>.other` (non-blank free text).
 */
export function validateAnswer(ask: ParsedAsk, answers: unknown): asserts answers is AnswerMap {
  if (answers === null || typeof answers !== "object" || Array.isArray(answers)) {
    throw new AskFormatError("answers must be an object keyed by question");
  }
  const entries = Object.entries(answers as Record<string, unknown>);
  if (entries.length === 0) throw new AskFormatError("an empty answer is not an answer: answer a question, or decline with a reason");
  const byKey = new Map(ask.questions.map((q, i) => [questionKey(q, i), q]));
  for (const [k, v] of entries) {
    if (k.endsWith(".other")) {
      if (!byKey.has(k.slice(0, -6))) throw new AskFormatError(`unknown question: ${k}`);
      if (typeof v !== "string" || !v.trim()) throw new AskFormatError(`${k} must be non-blank text`);
      continue;
    }
    const q = byKey.get(k);
    if (!q) throw new AskFormatError(`unknown question: ${k} (known: ${[...byKey.keys()].join(", ")})`);
    if (q.kind === "text") {
      if (typeof v !== "string" || !v.trim()) throw new AskFormatError(`${k} must be non-blank text`);
      continue;
    }
    if (q.kind === "number") {
      if (typeof v !== "number" || !Number.isFinite(v)) throw new AskFormatError(`${k} must be a number`);
      const { min, max } = q.number ?? {};
      if ((min !== undefined && v < min) || (max !== undefined && v > max)) {
        throw new AskFormatError(`${k} must be between ${min ?? "-∞"} and ${max ?? "∞"}`);
      }
      continue;
    }
    if (q.kind === "date") {
      if (typeof v !== "string" || !isRealDate(v)) throw new AskFormatError(`${k} must be a real date as YYYY-MM-DD`);
      continue;
    }
    if (!Array.isArray(v) || v.length === 0) throw new AskFormatError(`${k} must be a non-empty list of codes`);
    if (q.kind === "rank") {
      const top = q.options.map((o) => o.code ?? o.label);
      const sorted = (xs: unknown[]) => [...xs].map(String).sort().join("\u0000");
      if (v.length !== top.length || sorted(v) !== sorted(top)) {
        throw new AskFormatError(`${k} must rank every option exactly once: ${top.join(", ")}`);
      }
      continue;
    }
    const known = new Set(allValues(q.options));
    for (const c of v) if (typeof c !== "string" || !known.has(c)) throw new AskFormatError(`unknown option for ${k}: ${String(c)}`);
  }
}

/**
 * Save a draft into the file: a ```json draft``` block, the ask stays open and its revision does
 * not move. The draft records the revision it was based on, and a batch send settles it with that
 * revision as the compare-and-swap, so a draft never overwrites an answer that landed meanwhile.
 */
export function writeDraft(text: string, d: AskAnswer & { savedAt?: string }, expectedRevision: number): string {
  const ask = parseAskFile(text);
  assertNotSuperseded(ask);
  // IDE-304: a settled ask takes the operator's draft of a change to the operator's own answer.
  const open = ask.header.status === "open" || ask.header.status === undefined;
  const ownChange = (ask.header.status === "answered" || ask.header.status === "declined") && isOperatorAnswer(ask.answer) && isOperatorName(d.answeredBy);
  if (!open && !ownChange) {
    throw new AskFormatError(`ask ${ask.header.id ?? ""} is ${ask.header.status}; only an open ask, or the operator's own answer, takes a draft`);
  }
  const cur = currentRevision(ask);
  if (expectedRevision !== cur) throw new StaleRevisionError(expectedRevision, cur);
  if (d.declined) {
    if (!d.reason || !d.reason.trim()) throw new AskFormatError("a decline needs a non-empty reason");
  } else validateAnswer(ask, d.answers);
  const savedAt = d.savedAt ?? new Date().toISOString();
  const draft: AskDraft = { ...d, reason: d.declined ? d.reason!.trim() : undefined, basedOn: cur, savedAt, bodyHash: bodyDigest(text) };
  let out = setHeaderField(text, "draft", savedAt);
  out = out.replace(DRAFT_FENCES, "\n").replace(/\n*$/, "\n");
  return `${out}\n\`\`\`json draft\n${JSON.stringify(draft, null, 2)}\n\`\`\`\n`;
}

/** Remove a draft (discard), leaving the ask exactly as open as it was. */
export function clearDraft(text: string): string {
  return removeHeaderField(text, "draft").replace(DRAFT_FENCES, "\n").replace(/\n*$/, "\n");
}

// ── the card (§FMT_DECISION_CARD) ──────────────────

export type Card = {
  rank?: string; topic?: string; stake?: string; unblocks?: string; related?: string; counter?: string;
  confidence?: string; reversible?: string; verify?: string; falsifier?: string; ifUnanswered?: string;
  neededBy?: string; askedBy?: string; blocks?: string; context?: string; reservedFor?: string;
  provenance?: string; sourceRef?: string; asOf?: string;
  evidence: string[];
  lean?: { code?: string; text: string };
};

const CARD_FIELDS = ["rank", "topic", "stake", "unblocks", "related", "counter", "confidence", "reversible", "verify", "falsifier", "ifUnanswered", "neededBy", "blocks", "context"] as const;

function allCodes(opts: AskOption[]): string[] {
  return opts.flatMap((o) => [...(o.code ? [o.code] : []), ...allCodes(o.children ?? [])]);
}

/**
 * The card for question `index`: the question's own lines win; the ask's header fields fill the
 * FIRST card only, so a many-question ask does not repeat one stake under every question. The
 * ask-wide fields (askedBy, reserved-for, provenance, as-of, ref) are on every card.
 */
export function cardFor(ask: ParsedAsk, index: number): Card {
  const q = ask.questions[index];
  const h = ask.header;
  const card: Card = { evidence: [] };
  for (const f of CARD_FIELDS) {
    const v = q?.meta[f] ?? (index === 0 ? h[f] : undefined);
    if (v && v.trim()) card[f] = v.trim();
  }
  // v1's header `stakes` is the same field under its old name.
  if (!card.stake && index === 0 && h.stakes?.trim()) card.stake = h.stakes.trim();
  card.evidence = q?.evidence.length ? q.evidence : index === 0 && h.evidence ? h.evidence.split(/\s;\s|;\s/).map((x) => x.trim()).filter(Boolean) : [];
  const leanText = q?.meta.lean ?? (index === 0 ? h.lean : undefined);
  if (leanText && leanText.trim()) {
    const lm = leanText.trim().match(new RegExp(`^(${CODE_SRC})\\b\\s*(?:—|–|-|:|,)?\\s*(.*)$`));
    const codes = new Set(allCodes(q?.options ?? []));
    card.lean = lm && codes.has(lm[1]) ? { code: lm[1], text: lm[2].trim() } : { text: leanText.trim() };
  }
  for (const [k, f] of [["askedBy", "askedBy"], ["reservedFor", "reserved-for"], ["provenance", "provenance"], ["sourceRef", "sourceRef"]] as const) {
    if (h[f]?.trim()) card[k] = h[f]!.trim();
  }
  card.asOf = (h.created ?? "").slice(0, 10) || undefined;
  return card;
}

// ── tickets (acceptance 6) ────────────────────────────────

const TICKET_RE = /\b([A-Z][A-Z0-9]{1,9}-\d{1,6})\b/g;

/** Ticket keys an ask concerns: the `tickets:` header first, then any key named in the body. */
export function ticketKeys(ask: ParsedAsk): string[] {
  const seen: string[] = [];
  const add = (k: string) => {
    if (!seen.includes(k)) seen.push(k);
  };
  for (const m of (ask.header.tickets ?? "").matchAll(TICKET_RE)) add(m[1]);
  const body = [ask.preamble, ...ask.questions.flatMap((q) => [q.title, q.prose ?? "", q.proseAfter ?? "", ...Object.values(q.meta), ...q.evidence, ...optionText(q.options)])].join("\n");
  for (const m of body.matchAll(TICKET_RE)) add(m[1]);
  return seen;
}
function optionText(opts: AskOption[]): string[] {
  return opts.flatMap((o) => [o.label, o.description ?? "", o.cost ?? "", ...optionText(o.children ?? [])]);
}

// ── the batch message (acceptance 1) ─────────────────────

function labelFor(opts: AskOption[], v: string): string {
  // A value stored before codes over 5 characters were read as codes holds the whole "[CODE] label".
  const legacy = v.match(new RegExp(`^\\[(${CODE_SRC})\\]\\s*(.*)$`));
  if (legacy) return labelFor(opts, legacy[1]) || legacy[2] || v;
  for (const o of opts) {
    if ((o.code ?? o.label) === v || o.label === v) return o.label;
    const inner = labelFor(o.children ?? [], v);
    if (inner) return inner;
  }
  return "";
}

/** One question's settled answer, in words: what the batch message and `engine ask read` print. */
export function describeAnswer(q: AskQuestion, v: AnswerValue | undefined, other?: string): string {
  let s: string;
  if (v === undefined) s = "";
  else if (q.kind === "text") s = JSON.stringify(v);
  else if (q.kind === "number") s = `${v}${q.number?.unit ? ` ${q.number.unit}` : ""}`;
  else if (q.kind === "date") s = String(v);
  else {
    const list = Array.isArray(v) ? v : [String(v)];
    const words = list.map((c) => labelFor(q.options, c) || c);
    s = words.join(q.kind === "rank" ? " > " : ", ");
  }
  if (other) s = s ? `${s} (note: ${other})` : JSON.stringify(other);
  return s;
}

/**
 * ASKNOTE (round 2): an answer's note, marked and on its own line, never folded into a choice:
 * `⚠ note from <answerer>: "<text>"` (JSON-quoted, so a multi-line note stays one line).
 */
export function noteLine(a: AskAnswer | undefined): string | undefined {
  if (!a?.note?.trim()) return undefined;
  return `⚠ note from ${answeredByText(a)}: ${JSON.stringify(a.note.trim())}`;
}

/**
 * `title → answer · seat/id#KEY` for each answered question, read from the FILE's answer block —
 * never from a request — so a batch message cannot carry an answer the file does not hold.
 */
export function answerLines(ask: ParsedAsk, seat: string): string[] {
  const ref = `${seat}/${ask.header.id ?? ""}`;
  const a = ask.answer;
  if (!a) return [];
  // SHOULD-3 (round 2): the grant class the answering manager gave, as its own line after the picks.
  const grant = a.grantClass ? [`grant class ${a.grantClass}, given by ${a.answeredBy || "unknown"} · ${ref}`] : [];
  if (a.declined) return [`${ask.questions[0]?.title ?? ask.header.id} → declined: ${a.reason ?? ""} · ${ref}`, ...grant];
  const answers = a.answers ?? {};
  const out: string[] = [];
  ask.questions.forEach((q, i) => {
    const k = questionKey(q, i);
    const other = answers[`${k}.other`];
    if (answers[k] === undefined && other === undefined) return;
    out.push(`${q.title} → ${describeAnswer(q, answers[k], typeof other === "string" ? other : undefined)} · ${ref}#${k}`);
  });
  return [...out, ...grant];
}

// ── the forward chain (COORDHOP S4) ──────────────────────

export type Hop = { from: string; to: string; at: string; reason?: string };

/** A decline reason as it sits on a hop: one line, and none of the characters the hop is split on. */
/**
 * A decline reason as `forwards:` stores it: one line (whitespace runs collapse to a space), with
 * `%`, `@`, `;` and `]` percent-escaped. The escape keeps the ` ; ` hop split and the closing `]`
 * unambiguous, and keeps a raw `@` out of the hop, so a reader that splits a hop at its last `@`
 * (main before this change) still finds `from→to`. `forwardChain` unescapes it: the reason reads
 * back whole.
 */
export const hopReason = (reason: string) =>
  reason.replace(/\s+/g, " ").trim().replace(/%/g, "%25").replace(/@/g, "%40").replace(/;/g, "%3B").replace(/\]/g, "%5D");
const unescapeReason = (r: string) => r.replace(/%(25|40|3B|5D)/g, (_, c: string) => String.fromCharCode(parseInt(c, 16)));

/** An ISO timestamp, as every hop's `at` is written. */
const HOP_RE = /^(.+?)→(.+?)@(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2}))$/;

/**
 * `forwards: a→b@iso ; b→c@iso [declined: reason]`: every move of `to:`, in order, written by the
 * holder that moved it. A hop made by declining a reserved ask carries the decline's reason.
 * Each hop splits at its TIMESTAMP (a seat name may hold `@`, a timestamp never does); a hop whose
 * `at` is not a timestamp falls back to the last `@` (N5).
 */
export function forwardChain(h: AskHeader): Hop[] {
  return (h.forwards ?? "")
    .split(/\s;\s/)
    .map((x) => {
      const r = x.trim().match(/^(.*?)\s+\[declined: (.*)\]$/);
      const head = r ? r[1] : x.trim();
      const m = head.match(HOP_RE) ?? head.match(/^(.+?)→(.+)@([^@]+)$/);
      return m ? { from: m[1], to: m[2], at: m[3], ...(r ? { reason: unescapeReason(r[2]) } : {}) } : undefined;
    })
    .filter((h): h is Hop => !!h);
}

/** One hop as `forwards:` holds it. */
export const hopText = (h: Hop) => `${h.from}→${h.to}@${h.at}${h.reason ? ` [declined: ${hopReason(h.reason)}]` : ""}`;

/** Who an answer is pushed to: the asker, then every seat that held and forwarded it, minus the answerer. */
export function recipientsOf(ask: ParsedAsk, answeredBy?: string): string[] {
  const out: string[] = [];
  for (const s of [ask.header.from ?? "", ...forwardChain(ask.header).map((h) => h.from)]) {
    if (s && s !== answeredBy && !out.includes(s)) out.push(s);
  }
  return out;
}

// ── visibility ────────────────────────────────────────────

function asList(v: AnswerValue | undefined): string[] {
  if (v === undefined) return [];
  if (typeof v === "number") return [String(v)];
  return Array.isArray(v) ? v : v.trim() ? [v] : [];
}

/** Questions whose `DependsOn` is satisfied by `answers` (a question with none is always shown). */
export function visibleQuestions(questions: AskQuestion[], answers: AnswerMap): AskQuestion[] {
  return questions.filter((q) => {
    if (!q.dependsOn) return true;
    const given = asList(answers[q.dependsOn.ask]);
    if (given.length === 0) return false;
    return q.dependsOn.code ? given.includes(q.dependsOn.code) : true;
  });
}

// ── reads, per recipient (M2) ─────────────────────────────

export type Read = { seat: string; at: string };

/** `reads: seat@iso ; seat@iso`: every recipient's own first read of the current answer. */
export function readsOf(h: AskHeader): Read[] {
  return (h.reads ?? "")
    .split(/\s;\s/)
    .map((x) => x.trim().match(/^(.+)@([^@]+)$/))
    .filter((m): m is RegExpMatchArray => !!m)
    .map((m) => ({ seat: m[1], at: m[2] }));
}

/**
 * Has `seat` read the current answer? The asker's read is `readAt` (stamped only by the asker); a
 * forwarder's is its entry in `reads:`. One seat's read never stands for another's.
 */
export function hasRead(ask: ParsedAsk, seat: string): boolean {
  const h = ask.header;
  if (readsOf(h).some((r) => r.seat === seat)) return true;
  return seat === (h.from ?? "") && !!h.readAt && (!h.readBy || h.readBy === seat);
}

// ── visibility ────────────────────────────────────────────

/**
 * Asks whose header `dependsOn` (another ask's id) is settled — answered, or declined (S6, then
 * flagged by `dependsOnDeclined`). An ask whose dependency is not in the set at all is shown:
 * hiding it would hide it forever, and the renderer flags the gap.
 */
export function visibleAsks<T extends ParsedAsk>(asks: T[]): T[] {
  const byId = new Map(asks.map((a) => [a.header.id, a]));
  return asks.filter((a) => {
    const dep = a.header.dependsOn?.trim();
    if (!dep) return true;
    const other = byId.get(dep);
    return !other || other.header.status === "answered" || other.header.status === "declined";
  });
}

/** S6: the ask waits on another that was DECLINED; it is shown, and marked, rather than hidden forever. */
export function dependsOnDeclined(ask: ParsedAsk, asks: ParsedAsk[]): boolean {
  const dep = ask.header.dependsOn?.trim();
  return !!dep && asks.some((a) => a.header.id === dep && a.header.status === "declined");
}

// ── relays (the operator answered in a seat's terminal) ───

/**
 * The seat that RELAYED an answer it heard from the operator (`answeredVia: relay:<seat>`), or
 * undefined. A relay is an honour record like the rest of R4: the card shows who relayed it, so the
 * operator can spot a false one.
 */
export function relayerOf(a: AskAnswer | undefined): string | undefined {
  const v = a?.answeredVia ?? "";
  return v.startsWith("relay:") && v.length > 6 ? v.slice(6) : undefined;
}

/** The file's honoured draft block as text (the LAST block, a whole 3-backtick fence), or "". */
export function trailingDraftFence(text: string): string {
  const ms = [...text.matchAll(DRAFT_FENCES)];
  const m = ms[ms.length - 1];
  if (!m || text.slice((m.index ?? 0) + m[0].length).trim() !== "") return "";
  return m[0].replace(/^\n+/, "");
}

/** Who owns a draft: the seat that relayed it, else its answerer. Only the owner sends or discards it. */
export const draftAuthor = (d: AskAnswer) => relayerOf(d) ?? d.answeredBy ?? "";

/** "operator, relayed by manager:docs" — who answered, in the words the card and `read` show. */
export function answeredByText(a: AskAnswer | undefined): string {
  if (!a) return "";
  const r = relayerOf(a);
  return `${a.answeredBy || "unknown"}${r ? `, relayed by ${r}` : ""}`;
}

// ── filing checks ─────────────────────────────────────────

/** The code rule in words, for every refusal that cites it. */
export const CODE_RULE = `a capital letter, then up to ${CODE_MAX - 1} capitals or digits (${CODE_MAX} at most), e.g. [WT], [PART] or [KEEPBROAD]`;
const CODE_FULL_RE = new RegExp(`^${CODE_SRC}$`);

/**
 * `DependsOn: ASK_X=CODE` lines that cannot work: a question X the ask does not have, a code that
 * breaks the code rule, or a code X has no option for (which would hide the dependent for good).
 */
export function invalidDependsOn(ask: ParsedAsk): string[] {
  const out: string[] = [];
  for (const q of ask.questions) {
    const d = q.dependsOn;
    if (!d) continue;
    const target = ask.questions.find((t) => t.askName === d.ask);
    if (!target) out.push(`"${q.title}": DependsOn ASK_${d.ask} names no question in this ask`);
    else if (d.code !== undefined && !CODE_FULL_RE.test(d.code)) out.push(`"${q.title}": DependsOn ASK_${d.ask}=${d.code} is not a code (${CODE_RULE})`);
    else if (d.code !== undefined && !allCodes(target.options).includes(d.code)) out.push(`"${q.title}": DependsOn ASK_${d.ask}=${d.code} names no option of ASK_${d.ask} (it has ${allCodes(target.options).join(", ") || "no codes"})`);
  }
  return out;
}

/**
 * Option codes the grammar will not read as codes: `[WORKTREE]` is longer than a code may be
 * (a capital then up to CODE_MAX-1 capitals or digits), so it parses as part of the label and every answer naming it is later
 * refused as "unknown option". `new` and `revise` refuse such a body up front, naming the code.
 */
export function invalidOptionCodes(ask: ParsedAsk): { question: string; code: string }[] {
  const out: { question: string; code: string }[] = [];
  const walk = (q: AskQuestion, opts: AskOption[]) => {
    for (const o of opts) {
      const m = !o.code ? o.label.match(/^\[([^\]\s]+)\]/) : null;
      if (m && !/^[ xX]$/.test(m[1])) out.push({ question: q.title, code: m[1] });
      walk(q, o.children ?? []);
    }
  };
  for (const q of ask.questions) walk(q, q.options);
  return out;
}

/**
 * Non-fatal authoring warnings for `engine ask new` / `revise`: shapes that file fine but read badly
 * (ASK_AUTHOR_GUIDE.md). Each is one line; none blocks filing.
 */
export function authorWarnings(ask: ParsedAsk): string[] {
  const out: string[] = [];
  const choice = (q: AskQuestion) => q.kind === "choose-one" || q.kind === "choose" || q.kind === "rank";
  if (ask.questions.length > 1 && ask.header.lean?.trim()) {
    out.push("the header lean fills the first fork's card only; write a Lean: line under every fork");
  }
  ask.questions.forEach((q, i) => {
    const codeless = q.options.filter((o) => !o.code).length;
    if (q.unclosedFence) out.push(`"${q.title}": a code fence is never closed, so everything after it, later forks included, is read as code`);
    if (choice(q) && codeless) out.push(`"${q.title}": ${codeless} option(s) have no [CODE]; the answer will store the whole label`);
    if (choice(q) && ask.questions.length > 1 && !q.meta.lean && !(i === 0 && ask.header.lean?.trim())) out.push(`"${q.title}": no Lean: line`);
  });
  return out;
}
