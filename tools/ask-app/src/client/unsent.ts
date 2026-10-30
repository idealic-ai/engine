/**
 * The card's unsent picks and notes, kept per ask in memory and in this browser's storage, so neither a
 * remount (a revision bump) nor a reload after a server restart loses them (operator 01:29). Cleared when
 * the ask is sent. Storage may be missing or throw (a private window); memory still holds them then.
 */
import { questionKey, type ParsedAsk } from "../lib/format.ts";
import { forkLabel, type Unsent } from "./model.ts";

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
    memory.set(ref, u);
    return u;
  } catch {
    return undefined;
  }
}

export function saveUnsent(ref: string, u: Unsent, s: Store | undefined = storage()) {
  memory.set(ref, u);
  const empty = !Object.keys(u.values).length && !Object.values(u.text).some((t) => t.trim()) && !u.note.trim();
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

/** The operator's unsent picks and notes on a withdrawn ask, one line per fork by its name, then the note. */
export function keptDraftLines(ask: Pick<ParsedAsk, "questions">, u: Unsent): string[] {
  const out: string[] = [];
  ask.questions.forEach((q, i) => {
    const k = questionKey(q, i);
    const v = u.values[k];
    const picks = Array.isArray(v) ? v.map(String).filter(Boolean) : v !== undefined && v !== "" ? [String(v)] : [];
    const t = u.text[k]?.trim() ?? "";
    if (picks.length || t) out.push(`${forkLabel(q, i)}: ${[picks.join(", "), t].filter(Boolean).join("; ")}`);
  });
  if (u.note.trim()) out.push(`Note: ${u.note.trim()}`);
  return out;
}
