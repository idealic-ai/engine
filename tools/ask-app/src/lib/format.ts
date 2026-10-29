/**
 * The /ask file format: a `---` header block of one-line `key: value` fields, free prose, then
 * questions in the engine's decision-tree syntax, and once answered a fenced ```json answer block.
 *
 * The decision-tree grammar mirrors ~/Projects/ideas-bundle/interactions/parse-decision-tree.ts
 * (`## [¶ASK_NAME:] (Choose one|Choose): Title`, options `- [ ] [CODE] Label`, an indented
 * non-list line as the option's description, nesting by indent). It is restated here, not
 * imported, because that file lives in another repository. One addition: a `DependsOn:` metadata
 * line under a heading, `DependsOn: ASK_OTHER` or `DependsOn: ASK_OTHER=CODE`, which hides the
 * question until the other one is answered (with that code, when one is named).
 *
 * Pure string functions only — no fs, no node — so the React client imports this file as is.
 */

export type AskOption = {
  label: string;
  code?: string;
  description?: string;
  children?: AskOption[];
};

export type AskQuestion = {
  title: string;
  askName?: string;
  multiSelect: boolean;
  dependsOn?: { ask: string; code?: string };
  options: AskOption[];
};

/** Answers keyed by `questionKey`: selected codes (or labels for codeless options), or free text. */
export type AnswerMap = Record<string, string[] | string>;

export type AskAnswer = {
  answers?: AnswerMap;
  /** A refusal is a record, never an empty answer (INV_REFUSAL_IS_NOT_EMPTY): it carries its reason. */
  declined?: boolean;
  reason?: string;
  revision?: number;
  note?: string;
  answeredBy?: string;
  answeredAt?: string;
};

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
};

export const HEADER_FIELDS = [
  "id", "to", "from", "why", "importance", "stakes", "context", "alternatives",
  "lean", "falsifier", "status", "revision", "dependsOn", "created",
] as const;

const HEADING_RE = /^##\s+(?:¶ASK_(\w+):\s+)?(Choose one|Choose):\s+(.+)$/;
const CODE_RE = /^\[([A-Z]{2,4})\]\s*/;
const CHECKBOX_RE = /^\[[ xX]\]\s*/;
const DEPENDS_RE = /^DependsOn:\s*(?:¶|§)?\s*ASK_(\w+)(?:\s*=\s*([A-Z]{2,4}))?\s*$/;
const ANSWER_FENCE_RE = /\n?```json answer\n([\s\S]*?)\n```\n?/;

export class AskFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AskFormatError";
  }
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

// ── decision tree ─────────────────────────────────────────

type RawOption = { indent: number; code?: string; label: string; description?: string };

function parseOptionLines(lines: string[]): RawOption[] {
  const raw: RawOption[] = [];
  for (const line of lines) {
    const stripped = line.trimStart();
    if (!stripped) continue;
    const indent = line.length - stripped.length;
    if (stripped.startsWith("- ")) {
      let rest = stripped.slice(2);
      rest = rest.replace(CHECKBOX_RE, "");
      let code: string | undefined;
      const cm = rest.match(CODE_RE);
      if (cm) {
        code = cm[1];
        rest = rest.slice(cm[0].length);
      }
      const label = rest.trim() || code;
      if (!label) continue;
      raw.push({ indent, code, label });
    } else if (raw.length > 0 && indent > raw[raw.length - 1].indent && raw[raw.length - 1].description === undefined) {
      raw[raw.length - 1].description = stripped;
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
    const q: AskQuestion = { title: m[3].trim(), multiSelect: m[2] === "Choose", options: [] };
    if (m[1]) q.askName = m[1];
    i++;
    const block: string[] = [];
    while (i < lines.length && !/^#{1,2}\s/.test(lines[i]) && !lines[i].trim().startsWith("```")) {
      const dm = lines[i].trim().match(DEPENDS_RE);
      if (dm) q.dependsOn = dm[2] ? { ask: dm[1], code: dm[2] } : { ask: dm[1] };
      else block.push(lines[i]);
      i++;
    }
    q.options = buildTree(parseOptionLines(block));
    questions.push(q);
  }
  return { preamble: preambleLines.join("\n"), questions };
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
  const am = rest.match(ANSWER_FENCE_RE);
  let body = rest;
  // An answer block counts only on an answered or declined ask: an asker cannot pre-plant one.
  const settled = header.status === "answered" || header.status === "declined";
  if (am && settled) {
    try {
      answer = JSON.parse(am[1]) as AskAnswer;
    } catch {
      throw new AskFormatError("the json answer block is not valid JSON");
    }
  }
  if (am) body = rest.replace(ANSWER_FENCE_RE, "\n");
  const { preamble, questions } = parseQuestions(body);
  return { header, preamble, questions, ...(answer ? { answer } : {}) };
}

/**
 * Embed `answer` as the file's single ```json answer block, set `status: answered` and bump
 * `revision`. Answering again replaces the block. A superseded ask is refused, because its
 * replacement is the one that should carry the answer.
 */
export function currentRevision(ask: ParsedAsk): number {
  return parseInt(ask.header.revision ?? "0", 10) || 0;
}

function settle(text: string, record: AskAnswer, status: "answered" | "declined", expectedRevision?: number): string {
  const ask = parseAskFile(text);
  if (ask.header.status === "superseded") {
    throw new AskFormatError(`ask ${ask.header.id ?? ""} is superseded; answer its replacement`);
  }
  const cur = currentRevision(ask);
  if (expectedRevision !== undefined && expectedRevision !== cur) throw new StaleRevisionError(expectedRevision, cur);
  const revision = String(cur + 1);
  const answer = { ...record, revision: cur + 1 };
  let out = setHeaderField(text, "status", status);
  out = setHeaderField(out, "revision", revision);
  out = out.replace(ANSWER_FENCE_RE, "\n");
  out = out.replace(/\n*$/, "\n");
  return `${out}\n\`\`\`json answer\n${JSON.stringify(answer, null, 2)}\n\`\`\`\n`;
}

/** Answer the ask. With `expectedRevision`, refuse (StaleRevisionError) if the ask has moved since it was read. */
export function writeAnswer(text: string, answer: AskAnswer, expectedRevision?: number): string {
  return settle(text, { ...answer, declined: undefined }, "answered", expectedRevision);
}

/** Decline the ask: `status: declined`, with a required, non-blank reason. */
export function writeDecline(
  text: string,
  d: { reason: string; answeredBy?: string; answeredAt?: string; note?: string },
  expectedRevision?: number,
): string {
  if (!d.reason || !d.reason.trim()) throw new AskFormatError("a decline needs a non-empty reason");
  return settle(text, { declined: true, ...d, reason: d.reason.trim() }, "declined", expectedRevision);
}

function allValues(opts: AskOption[]): string[] {
  return opts.flatMap((o) => [o.code ?? o.label, o.label, ...allValues(o.children ?? [])]);
}

/**
 * Refuse an answer that says nothing or says something the ask did not ask (INV_REFUSAL_IS_NOT_EMPTY).
 * Keys: a question key (array of its codes/labels, non-empty) or `<key>.other` (non-blank free text).
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
    if (!Array.isArray(v) || v.length === 0) throw new AskFormatError(`${k} must be a non-empty list of codes`);
    const known = new Set(allValues(q.options));
    for (const c of v) if (typeof c !== "string" || !known.has(c)) throw new AskFormatError(`unknown option for ${k}: ${String(c)}`);
  }
}

// ── visibility ────────────────────────────────────────────

function asList(v: string[] | string | undefined): string[] {
  if (v === undefined) return [];
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

/**
 * Asks whose header `dependsOn` (another ask's id) is answered. An ask whose dependency is not in
 * the set at all is shown: hiding it would hide it forever, and the renderer flags the gap.
 */
export function visibleAsks<T extends ParsedAsk>(asks: T[]): T[] {
  const byId = new Map(asks.map((a) => [a.header.id, a]));
  return asks.filter((a) => {
    const dep = a.header.dependsOn?.trim();
    if (!dep) return true;
    const other = byId.get(dep);
    return !other || other.header.status === "answered";
  });
}
