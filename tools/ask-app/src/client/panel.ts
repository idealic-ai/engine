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

/**
 * S1: a fork whose own text says a council or panel ran (format.ts's mentionsPanelReport) but that
 * carries no reads, no Council: and no proposals — or, on the first fork only, an ask whose preamble
 * or header prose says so while no fork carries reads. `report` is the first reference that names a
 * council or panel, looked for in the fork's text, then the text above the first fork, then the
 * header's prose fields; it is shown as written (councilRef decides whether it links).
 */
export function namedReport(ask: Pick<ParsedAsk, "questions" | "preamble" | "header">, at: number | AskQuestion): { named: boolean; report?: string } {
  const q = typeof at === "number" ? ask.questions[at] : at;
  if (!q || q.panel.length || q.council !== undefined || (q.proposals ?? []).length) return { named: false };
  const own = forkText(q);
  const header = ask.header as Record<string, string | undefined>;
  const above = [ask.preamble, ...ASK_TEXT_FIELDS.map((k) => header[k] ?? "")];
  // A council named only above the forks is said once, on the first fork, and only while no fork carries reads.
  const askLevel = ask.questions[0] === q && !ask.questions.some((x) => x.panel.length) && above.some(mentionsPanelReport);
  if (!own.some(mentionsPanelReport) && !askLevel) return { named: false };
  for (const text of [...own, ...above]) {
    for (const m of text.matchAll(REPORT_TOKEN)) {
      const tok = m[0].replace(/[.,;:]+$/, "");
      if (/council|panel/i.test(m[1] ?? tok)) return { named: true, report: tok };
    }
  }
  return { named: true };
}
