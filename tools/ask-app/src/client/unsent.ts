/**
 * The card's unsent picks and notes, kept per ask in memory and in this browser's storage, so neither a
 * remount (a revision bump) nor a reload after a server restart loses them (operator 01:29). Cleared when
 * the ask is sent. Storage may be missing or throw (a private window); memory still holds them then.
 */
import { questionKey, type AskOption, type ParsedAsk } from "../lib/format.ts";
import { forkLabel, type Unsent, type Values } from "./model.ts";
import { REQUEST_KINDS } from "./loop.ts";

type Store = Pick<Storage, "getItem" | "setItem" | "removeItem">;
const KEY = (ref: string) => `askclient.unsent.${ref}`;
const memory = new Map<string, Unsent>();
const storage = (): Store | undefined => {
  try {
    return typeof localStorage === "undefined" ? undefined : localStorage;
  } catch {
    return undefined;
  }
};

export function loadUnsent(ref: string, s: Store | undefined = storage()): Unsent | undefined {
  if (memory.has(ref)) return memory.get(ref);
  try {
    const raw = s?.getItem(KEY(ref));
    if (!raw) return undefined;
    const u = JSON.parse(raw) as Unsent;
    if (typeof u?.revision !== "string" || typeof u.note !== "string" || !u.values || !u.text) return undefined;
    if (u.need !== undefined && typeof u.need !== "string") return undefined;
    if (u.followup !== undefined && typeof u.followup !== "string") return undefined;
    if (u.needKind !== undefined && typeof u.needKind !== "string") return undefined;
    if ((u.followKind !== undefined && typeof u.followKind !== "string") || (u.followFork !== undefined && typeof u.followFork !== "string") || (u.followAttach !== undefined && typeof u.followAttach !== "boolean")) return undefined;
    memory.set(ref, u);
    return u;
  } catch {
    return undefined;
  }
}

export function saveUnsent(ref: string, u: Unsent, s: Store | undefined = storage()) {
  memory.set(ref, u);
  const empty = !Object.keys(u.values).length && !Object.values(u.text).some((t) => t.trim()) && !u.note.trim() && !u.need?.trim() && !u.followup?.trim();
  try {
    if (empty) s?.removeItem(KEY(ref));
    else s?.setItem(KEY(ref), JSON.stringify(u));
  } catch {
    /* storage full or refused: memory still has it */
  }
}

export function clearUnsent(ref: string, s: Store | undefined = storage()) {
  memory.delete(ref);
  try {
    s?.removeItem(KEY(ref));
  } catch {
    /* nothing to clear */
  }
}

/** Test seam: forget what memory holds, as a reload would. */
export function forgetMemory() {
  memory.clear();
}

/** What a card keeps: its picks, notes, request and follow-up text at this revision; a blank request or follow-up is left out. */
export function cardUnsent(revision: string, s: { values: Values; text: Record<string, string>; note: string; need: string; needKind?: string; followup?: string; followKind?: string; followFork?: string; followAttach?: boolean }): Unsent {
  return {
    revision, values: s.values, text: s.text, note: s.note,
    // NIT-A: the request keeps its kind, so the kept line and a remount say what kind of request it was.
    ...(s.need.trim() ? { need: s.need, ...(s.needKind ? { needKind: s.needKind } : {}) } : {}),
    // ASKFOLLOW SHOULD-2: the follow-up's kind, fork and attach box ride with its text, never alone.
    ...(s.followup?.trim()
      ? { followup: s.followup, ...(s.followKind ? { followKind: s.followKind } : {}), ...(s.followFork !== undefined ? { followFork: s.followFork } : {}), ...(s.followAttach !== undefined ? { followAttach: s.followAttach } : {}) }
      : {}),
  };
}

/** NIT-A: what the kept copy holds, said whole: "Your picks and notes are kept in this browser:". */
export function keptSentence(u: Unsent): string {
  const parts = [
    Object.values(u.values).some((v) => (Array.isArray(v) ? v.length > 0 : v !== undefined && v !== "")) ? "picks" : "",
    u.note.trim() || Object.values(u.text).some((t) => t.trim()) ? "notes" : "",
    u.need?.trim() ? "request" : "",
    u.followup?.trim() ? "follow-up" : "",
  ].filter(Boolean);
  const list = parts.length <= 1 ? parts.join("") : `${parts.slice(0, -1).join(", ")} and ${parts[parts.length - 1]}`;
  const many = parts.length > 1 || parts[0] === "picks" || parts[0] === "notes";
  return `Your ${list || "edits"} ${many || !parts.length ? "are" : "is"} kept in this browser:`;
}

/** WithdrawnBar's state: whether a copy took, and whether Forget is asking to confirm. */
export type BarState = { copy?: "ok" | "failed"; confirming: boolean };
export type BarEvent = "forget" | "yes" | "keep" | { copied: boolean };

/** P13 (ASKWITHDRAWN delta): WithdrawnBar's steps, pure. Only "yes" clears the kept copy. */
export function barStep(s: BarState, ev: BarEvent): { state: BarState; clear: boolean } {
  if (ev === "forget") return { state: { ...s, confirming: true }, clear: false };
  if (ev === "keep") return { state: { ...s, confirming: false }, clear: false };
  if (ev === "yes") return { state: { ...s, confirming: false }, clear: true };
  return { state: { ...s, copy: ev.copied ? "ok" : "failed" }, clear: false };
}

/** An option's label for a stored pick (its code, or its label when it has none); the value itself if no option matches. */
function labelOf(opts: AskOption[], v: string): string | undefined {
  for (const o of opts) {
    if ((o.code ?? o.label) === v || o.label === v) return o.label;
    const inner = labelOf(o.children ?? [], v);
    if (inner) return inner;
  }
  return undefined;
}

/**
 * The operator's unsent picks, notes and request on a withdrawn ask: one line per fork by its name,
 * each pick by its option text (NIT-4: a code alone means nothing once pasted elsewhere), then the
 * note, the request text and (ASKFOLLOW) the unsent follow-up text.
 */
export function keptDraftLines(ask: Pick<ParsedAsk, "questions">, u: Unsent): string[] {
  const out: string[] = [];
  ask.questions.forEach((q, i) => {
    const k = questionKey(q, i);
    const v = u.values[k];
    const picks = Array.isArray(v) ? v.map(String).filter(Boolean) : v !== undefined && v !== "" ? [String(v)] : [];
    const words = picks.map((p) => labelOf(q.options, p) ?? p);
    const t = u.text[k]?.trim() ?? "";
    if (words.length || t) out.push(`${forkLabel(q, i)}: ${[words.join(" · "), t].filter(Boolean).join("; ")}`);
  });
  if (u.note.trim()) out.push(`Note: ${u.note.trim()}`);
  // NIT-3 (ASKFOLLOW critique): the kind by its label, as the request form shows it; an unknown kind as itself.
  const kind = u.needKind ? REQUEST_KINDS.find((k) => k.kind === u.needKind)?.label ?? u.needKind : "";
  if (u.need?.trim()) out.push(`Request${kind ? ` (${kind})` : ""}: ${u.need.trim()}`);
  if (u.followup?.trim()) out.push(`Follow-up: ${u.followup.trim()}`);
  return out;
}

type Clip = { writeText?: (t: string) => Promise<void> } | undefined;
/** S-2: true only when the clipboard took the text; no clipboard API, or a refused write, is false. */
export async function copyText(t: string, clip: Clip = typeof navigator === "undefined" ? undefined : navigator.clipboard): Promise<boolean> {
  if (typeof clip?.writeText !== "function") return false;
  try {
    await clip.writeText(t);
    return true;
  } catch {
    return false;
  }
}

/** S-2: Forget's confirm, saying whether the lines are held anywhere else. */
export function forgetWords(copied: boolean): string {
  return copied ? "Forget them? They are on your clipboard; this browser stops keeping them." : "Forget them? They were not copied, and nothing else holds them.";
}
