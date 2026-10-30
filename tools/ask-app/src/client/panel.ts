/**
 * COUNCILUI (IDE-338, the client half): pure helpers for a fork's panel reads and its council
 * reports. The shapes and the matchers are lib/format.ts's (PanelRead, PanelProposal on
 * AskQuestion, forkText, mentionsPanelReport); none is restated here.
 */
import { ASK_TEXT_FIELDS, forkText, mentionsPanelReport, type AskOption, type AskQuestion, type ParsedAsk, type PanelRead } from "../lib/format.ts";

/**
 * A `Council:` value as the client shows it: only an http(s) URL (bare, or a `[label](url)` link)
 * is a link; a path or anything else is plain text, never followed. S4: each link is labelled so
 * that several on one fork are told apart — the link's own text, else the report's file name, else
 * its host and the tail of its path.
 */
export function councilRef(v: string): { href?: string; label: string } {
  const s = v.trim();
  if (/^https?:\/\/\S+$/i.test(s)) return { href: s, label: urlLabel(s) };
  const m = s.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/i);
  if (m) return { href: m[2], label: m[1] };
  return { label: s };
}

function urlLabel(href: string): string {
  let u: URL;
  try {
    u = new URL(href);
  } catch {
    return href;
  }
  const segs = u.pathname.split("/").filter(Boolean);
  const last = segs[segs.length - 1];
  if (!last) return u.host;
  if (/\.[A-Za-z0-9]{1,5}$/.test(last)) return decodeURIComponent(last);
  return segs.length > 1 ? `${u.host}/…/${decodeURIComponent(last)}` : `${u.host}/${decodeURIComponent(last)}`;
}

/** Every report a fork's reads came from: its own Council: first, then each attached one once. */
export function forkCouncils(q: AskQuestion): string[] {
  const out: string[] = [];
  const add = (c?: string) => c && !out.includes(c) && out.push(c);
  add(q.council);
  for (const r of q.panel) add(r.council);
  for (const p of q.proposals ?? []) add(p.council);
  return out;
}

const picks = (r: PanelRead, o: AskOption) => r.pick === o.code || r.pick === o.label;
const tree = (opts: AskOption[]): AskOption[] => opts.flatMap((o) => [o, ...tree(o.children ?? [])]);

/** N1: a read whose pick names no option anywhere in the fork's tree (an option revised away). */
export function isStale(q: AskQuestion, r: PanelRead): boolean {
  return !tree(q.options).some((o) => picks(r, o));
}

/**
 * The reads that picked this option (by code, or by label for a codeless one) and, S2, the reads
 * that picked an option nested under it — its child rows stay hidden until it is picked. `of` counts
 * only live reads (N1): a stale read is listed in the strip, never in a row's denominator.
 */
export function optionTally(q: AskQuestion, o: AskOption): { picked: number; under: number; of: number; reads: PanelRead[]; underReads: PanelRead[] } {
  const reads = q.panel.filter((r) => picks(r, o));
  const below = tree(o.children ?? []);
  const underReads = q.panel.filter((r) => !picks(r, o) && below.some((c) => picks(r, c)));
  const of = q.panel.filter((r) => !isStale(q, r)).length;
  return { picked: reads.length, under: underReads.length, of, reads, underReads };
}

/** "2 of 3 lenses picked this", in words a reader takes in without hovering. */
export function tallyText(picked: number, of: number, under = 0): string {
  const lenses = `lens${of === 1 ? "" : "es"}`;
  if (picked) return `${picked} of ${of} ${lenses} picked this${under ? ` · ${under} picked an option under this` : ""}`;
  if (under) return `${under} of ${of} ${lenses} picked an option under this`;
  return `No lens of ${of} picked this`;
}

/** Who attached a read and when, for an attach-panel read; undefined for the asker's own Panel: line. */
export function attachedText(r: { attachedBy?: string; attachedAt?: string }): string | undefined {
  if (!r.attachedBy) return undefined;
  return `attached by ${r.attachedBy}${r.attachedAt ? ` at ${r.attachedAt.replace("T", " ").replace(/:\d\d(?:\.\d+)?Z$/, "Z")}` : ""}`;
}

/** N2: a proposal's label without a leading `[CODE]`, so it never reads as one of the fork's options. */
export function proposalLabel(label: string): string {
  return label.replace(/^\s*\[[^\]\s]+\]\s*/, "");
}

/** A report reference in prose: a markdown link, a bare URL or a file path. */
const REPORT_TOKEN = /\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)|https?:\/\/[^\s)<>\]"'`]+|(?:~|\.{0,2}\/)?[\w.@-]+(?:\/[\w.@-]+)*\.(?:md|html?)\b/gi;

/** S-B: a file name with `council` or `panel` as a whole segment (VOICE_COUNCIL.md, x_COUNCIL_2026.md, fund-council-1.html), never a substring (COUNCILUI_CRITIQUE.md). */
const REPORT_FILE = /(?:^|[_.-])(?:council|panel)(?:[_.-]|$)/i;

function isReportFile(pathOrUrl: string): boolean {
  let p = pathOrUrl;
  if (/^https?:\/\//i.test(p)) {
    try {
      p = new URL(p).pathname;
    } catch {
      return false;
    }
  }
  const base = p.split("/").filter(Boolean).pop() ?? "";
  return REPORT_FILE.test(base);
}

/**
 * The first council report a text names, as written. A file path or an http(s) URL counts when its
 * file name is a report file (S-B); a markdown link counts by its URL (N-b) and, unless `filesOnly`,
 * by a label that says council or panel.
 */
function firstReport(texts: string[], filesOnly: boolean): string | undefined {
  for (const text of texts) {
    for (const m of text.matchAll(REPORT_TOKEN)) {
      const tok = m[1] !== undefined ? m[0] : m[0].replace(/[.,;:]+$/, "");
      const ok = m[1] !== undefined ? isReportFile(m[2]) || (!filesOnly && /\b(?:council|panel)\b/i.test(m[1])) : isReportFile(tok);
      if (ok) return tok;
    }
  }
  return undefined;
}

/**
 * S1: a fork that carries no reads, no Council: and no proposals, but where a council evidently ran.
 * - scope "fork": the fork's own text says a council or panel ran (format.ts's mentionsPanelReport).
 *   `report` is the first report it, the text above the first fork or the header's prose names.
 * - scope "ask" (S-A), on the first fork only and while no fork carries reads: the text above the
 *   forks or a header prose field names a council report FILE, or an http(s) URL to one. Prose
 *   about panels never fires this, because it so often describes a council still to run.
 * `report` is shown as written; councilRef decides whether it links.
 */
export function namedReport(ask: Pick<ParsedAsk, "questions" | "preamble" | "header">, at: number | AskQuestion): { named: boolean; scope?: "fork" | "ask"; report?: string } {
  const q = typeof at === "number" ? ask.questions[at] : at;
  if (!q || q.panel.length || q.council !== undefined || (q.proposals ?? []).length) return { named: false };
  const own = forkText(q);
  const header = ask.header as Record<string, string | undefined>;
  const above = [ask.preamble, ...ASK_TEXT_FIELDS.map((k) => header[k] ?? "")];
  if (own.some(mentionsPanelReport)) {
    const report = firstReport([...own, ...above], false);
    return { named: true, scope: "fork", ...(report ? { report } : {}) };
  }
  if (ask.questions[0] !== q || ask.questions.some((x) => x.panel.length)) return { named: false };
  const report = firstReport(above, true);
  return report ? { named: true, scope: "ask", report } : { named: false };
}
