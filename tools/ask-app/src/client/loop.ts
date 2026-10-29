/**
 * Round 5: the ask loop as the client sees it before meta:engine's LOOMASK change lands. A request
 * for something first, a draft answer sent as "provisional", and rounds linked by `round:` and
 * `previous:`. Every function degrades: a field today's server drops is read back from the note.
 */
import { describeAnswer, questionKey, type AnswerMap, type AskAnswer, type ParsedAsk } from "../lib/format.ts";

/** The note line a draft answer carries, so the asker sees it even where `provisional` is not stored. */
export const DRAFT_NOTE = "Draft answer — not final; expect a second round.";

export type RequestKind = { kind: string; label: string; group: string };
/** The closed set the CLI will parse. `proof:best` is the default proof choice. */
export const REQUEST_KINDS: RequestKind[] = [
  { kind: "details", label: "More details", group: "Ask the asker" },
  { kind: "reword", label: "Reword the question", group: "Ask the asker" },
  { kind: "proof:best", label: "Best match: the asker picks the page type", group: "A proof page" },
  { kind: "proof:prove", label: "Prove one claim", group: "A proof page" },
  { kind: "proof:explore", label: "Explore: map the whole", group: "A proof page" },
  { kind: "proof:visionary", label: "Visionary: options and a direction", group: "A proof page" },
  { kind: "proof:plan", label: "Plan", group: "A proof page" },
  { kind: "proof:explanation", label: "Explanation for a newcomer", group: "A proof page" },
  { kind: "council:critique", label: "Critique", group: "A council" },
  { kind: "council:design-off", label: "Design-off", group: "A council" },
  { kind: "council:ideas", label: "Ideas", group: "A council" },
  { kind: "council:refute", label: "Refute the lean", group: "A council" },
  { kind: "vote", label: "A vote", group: "Other" },
  { kind: "scrutinize", label: "Scrutinize the work", group: "Other" },
];
const KINDS = new Set(REQUEST_KINDS.map((k) => k.kind));

/** `request: <kind>[:<arg>] — <operator text>`, byte-exact: one space each side of an em dash. */
export function requestLine(kind: string, text: string): string {
  if (!KINDS.has(kind)) throw new Error(`unknown request kind: ${kind}`);
  const t = text.replace(/\s+/g, " ").trim();
  if (!t) throw new Error("a request needs the operator's words");
  return `request: ${kind} — ${t}`;
}

const REQUEST_RE = /^request: ([a-z]+(?::[a-z-]+)?) — (.+)$/;

/** The request a note carries, if its first matching line is one. */
export function parseRequestLine(note: string | undefined): { kind: string; arg?: string; text: string } | undefined {
  for (const line of (note ?? "").split("\n")) {
    const m = line.match(REQUEST_RE);
    if (m) {
      const [kind, arg] = m[1].split(":");
      return { kind, ...(arg ? { arg } : {}), text: m[2] };
    }
  }
  return undefined;
}

/** The request line first, then whatever else the operator wrote. */
export function composeNote(first: string, rest: string): string {
  const r = rest.trim();
  return r ? `${first}\n${r}` : first;
}

/**
 * A provisional answer: the status the server will set, the `provisional` flag, or, until both
 * exist, the draft note or a request line in the recorded note.
 */
export function isProvisional(a: ParsedAsk): boolean {
  if (a.header.status === "answered-provisional") return true;
  const ans = a.answer as (AskAnswer & { provisional?: boolean }) | undefined;
  if (!ans || a.header.status !== "answered") return false;
  if (ans.provisional === true) return true;
  return (ans.note ?? "").split("\n").some((l) => l.trim() === DRAFT_NOTE || REQUEST_RE.test(l));
}

/**
 * The body for a provisional answer. With no picks, the request still needs an answer to carry
 * it (an empty answer is refused), so the first fork's free-text slot holds the request line.
 */
export function provisionalAnswers(a: ParsedAsk, picks: AnswerMap, line: string): AnswerMap {
  if (Object.keys(picks).length) return picks;
  const q = a.questions[0];
  return q ? { [`${questionKey(q, 0)}.other`]: line } : {};
}

export type Poster = (url: string, body: unknown) => Promise<{ status: number; json: any }>;
export type SendOutcome = { ok: boolean; message: string; flagStored?: boolean };

/**
 * Save as a draft with `provisional: true`, send it, and read it back. A server that refuses the
 * field gets the same body without it; one that drops it silently is caught on read-back. Either way
 * the note line stays, so the asker sees the answer is not final.
 */
export async function sendProvisional(
  post: Poster,
  readBack: () => Promise<ParsedAsk | undefined>,
  args: { seat: string; id: string; expectedRevision: number; answers: AnswerMap; note: string },
): Promise<SendOutcome> {
  const base = { seat: args.seat, id: args.id, expectedRevision: args.expectedRevision, answers: args.answers, note: args.note };
  let r = await post("/api/draft", { ...base, provisional: true });
  let refusedFlag = false;
  if (r.status === 400 && /provisional/i.test(String(r.json?.error ?? ""))) {
    refusedFlag = true;
    r = await post("/api/draft", base);
  }
  if (r.status === 409) return { ok: false, message: `Not sent: the ask moved (now revision ${r.json.revision}). Read it again first.` };
  if (r.status !== 200) return { ok: false, message: `Error: ${r.json?.error ?? r.status}` };
  const s = await post("/api/send", { refs: [`${args.seat}/${args.id}`] });
  if (s.json?.refused?.length) return { ok: false, message: `Refused: ${s.json.refused[0].error}` };
  const after = await readBack();
  const stored = !refusedFlag && !!(after?.answer as { provisional?: boolean } | undefined)?.provisional;
  const where = stored ? "marked provisional" : "sent as an ordinary answer with the draft note, because this server does not store the provisional mark yet";
  return { ok: true, flagStored: stored, message: `Waiting on the asker: draft sent (${where}).` };
}

// ── threaded rounds ──────────────────────────────────────

export type RoundView = { ref: string; round: number; title: string; status: string; lines: string[]; note?: string; provisional: boolean };

/** Earlier rounds, oldest first, by walking `previous: <seat>/<id>` through the asks the app holds. */
export function earlierRounds<T extends ParsedAsk & { seat: string }>(a: T, all: T[]): RoundView[] {
  const out: RoundView[] = [];
  const seen = new Set<string>([`${a.seat}/${a.header.id}`]);
  let prev = a.header.previous?.trim();
  while (prev && !seen.has(prev)) {
    seen.add(prev);
    const p = all.find((x) => `${x.seat}/${x.header.id}` === prev);
    if (!p) {
      out.unshift({ ref: prev, round: 0, title: "", status: "not in this root", lines: [], provisional: false });
      break;
    }
    const lines = p.answer?.answers
      ? p.questions.flatMap((q, i) => {
          const k = questionKey(q, i);
          const v = p.answer!.answers![k];
          const other = p.answer!.answers![`${k}.other`];
          return v === undefined && other === undefined ? [] : [`${q.askName ?? `Q${i + 1}`}: ${describeAnswer(q, v, other as string | undefined)}`];
        })
      : [];
    out.unshift({ ref: prev, round: Number(p.header.round) || 0, title: p.questions[0]?.title ?? prev, status: p.header.status ?? "", lines, note: p.answer?.note, provisional: isProvisional(p) });
    prev = p.header.previous?.trim();
  }
  out.forEach((r, i) => {
    if (!r.round) r.round = i + 1;
  });
  return out;
}

/**
 * Picks to suggest in this round: the operator's answer in the previous round, kept only where the
 * fork and the code still exist. They are suggestions (dashed), never answers.
 */
export function priorPicks<T extends ParsedAsk & { seat: string }>(a: T, all: T[]): Record<string, string> {
  const prev = a.header.previous?.trim();
  const p = prev ? all.find((x) => `${x.seat}/${x.header.id}` === prev) : undefined;
  const ans = p?.answer?.answers;
  if (!ans) return {};
  const out: Record<string, string> = {};
  a.questions.forEach((q, i) => {
    const v = ans[questionKey(q, i)];
    const first = Array.isArray(v) ? v[0] : undefined;
    const codes = new Set(q.options.map((o) => o.code ?? o.label));
    if (first && codes.has(first) && q.kind !== "rank" && Array.isArray(v) && v.length === 1) out[questionKey(q, i)] = first;
  });
  return out;
}

export type Turn = { who: string; text: string };

/**
 * The conversation so far. A parsed `dialogue` array wins; until the parser provides one, a
 * `## Dialogue` block in the preamble is read as `who: text` lines. A block after the forks does
 * not reach the client (the parser drops it), so nothing is shown for it.
 */
export function dialogueOf(a: ParsedAsk): { turns: Turn[]; preamble: string } {
  const parsed = (a as ParsedAsk & { dialogue?: Turn[] }).dialogue;
  if (Array.isArray(parsed) && parsed.length) return { turns: parsed.filter((t) => t && typeof t.text === "string"), preamble: a.preamble };
  const lines = a.preamble.split("\n");
  const start = lines.findIndex((l) => /^##\s+Dialogue\s*$/i.test(l));
  if (start === -1) return { turns: [], preamble: a.preamble };
  let end = start + 1;
  while (end < lines.length && !/^#{1,2}\s/.test(lines[end])) end++;
  const turns: Turn[] = [];
  for (const l of lines.slice(start + 1, end)) {
    // `- **who**: text`, `- who: text` or `who: text`; a seat name keeps its colon (`idealic:ui: …`).
    const m = l.match(/^\s*(?:[-*]\s+)?(?:\*\*(.{1,60}?)\*\*|([\w.-]+(?::[\w.-]+)?)):\s+(.+)$/);
    if (m) turns.push({ who: (m[1] ?? m[2]).trim(), text: m[3].trim() });
    else if (l.trim() && turns.length) turns[turns.length - 1].text += ` ${l.trim()}`;
  }
  return { turns, preamble: [...lines.slice(0, start), ...lines.slice(end)].join("\n") };
}

export type SendKind = "send" | "draft" | "request";
/**
 * Whether a send must first ask "N questions unanswered — send anyway?". Only a final send does: it
 * settles the whole ask. Send as draft and Send request are provisional and partial on purpose, since
 * the asker answers with a second round.
 */
export function needsUnansweredConfirm(kind: SendKind, unanswered: string[]): boolean {
  return kind === "send" && unanswered.length > 0;
}
