/**
 * COUNCILUI (IDE-338, the client half): pure helpers for a fork's panel reads and its council
 * reports. The shapes are lib/format.ts's (PanelRead, PanelProposal on AskQuestion); none is
 * restated here.
 */
import type { AskOption, AskQuestion, PanelRead } from "../lib/format.ts";

/**
 * A `Council:` value as the client shows it: only an http(s) URL (bare, or a `[label](url)` link)
 * is a link; a path or anything else is plain text, never followed.
 */
export function councilRef(v: string): { href?: string; label: string } {
  const s = v.trim();
  if (/^https?:\/\/\S+$/i.test(s)) return { href: s, label: "Council report" };
  const m = s.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/i);
  if (m) return { href: m[2], label: m[1] };
  return { label: s };
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

/** The reads that picked this option (by code, or by label for a codeless one), out of all of them. */
export function optionTally(q: AskQuestion, o: AskOption): { picked: number; of: number; reads: PanelRead[] } {
  const reads = q.panel.filter((r) => r.pick === o.code || r.pick === o.label);
  return { picked: reads.length, of: q.panel.length, reads };
}

/** "2 of 3 lenses picked this", in words a reader takes in without hovering. */
export function tallyText(picked: number, of: number): string {
  const lenses = `lens${of === 1 ? "" : "es"}`;
  return picked ? `${picked} of ${of} ${lenses} picked this` : `No lens of ${of} picked this`;
}

/** Who attached a read and when, for an attach-panel read; undefined for the asker's own Panel: line. */
export function attachedText(r: { attachedBy?: string; attachedAt?: string }): string | undefined {
  if (!r.attachedBy) return undefined;
  return `attached by ${r.attachedBy}${r.attachedAt ? ` at ${r.attachedAt.replace("T", " ").replace(/:\d\d(?:\.\d+)?Z$/, "Z")}` : ""}`;
}
