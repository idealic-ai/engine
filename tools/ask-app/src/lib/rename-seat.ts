/**
 * The text half of `engine ask rename-seat <old> <new>`: rewrite every reference to one seat in one
 * ask file, and say what changed. Pure — no fs — so it is the same on a dry run and a real one.
 *
 * What counts as a reference (the fields come from format.ts's HEADER_FIELDS and STAMP_FIELDS):
 * - header fields whose whole value is a seat: SEAT_FIELDS;
 * - `askedBy: seat · thread · log` — its first ` · ` segment, when that is the whole seat name;
 * - `reads: seat@iso ; …` — each entry's seat;
 * - `forwards: a→b@iso [declined: …] ; …` — each hop's two seats; the reason is kept byte for byte,
 *   escapes and all (it is prose, like a note);
 * - `delivery`, `deliveryNote`, `revisions`, `replaced` — store-written stamps, where any whole-name
 *   mention is the seat (`deliveryNote: idealic:ui: no live session …`, `replaced: revision 2 by
 *   idealic:ui at …`);
 * - every other header field: each `<seat>/<id>` ref (`supersedes`, `superseded-by`, `related`,
 *   `dependsOn`, and a ref or an ask's file path quoted in `context`, `evidence`, `why`, …). A bare
 *   seat named in such prose (`acted: told idealic:ui`) is history, like a note, and is left alone;
 * - the ```json answer```, ```json draft``` and ```json history``` records (IDE-339: history holds
 *   every replaced answer, each rewritten like the answer): `answeredBy`, `readBy`, `relayedFrom`,
 *   `actedBy`, and the seat in `answeredVia: relay:<seat>`. A seat inside a note or reason is left alone;
 * - ASKFOLLOWUP: each ```json followup``` record's `by` and `addressedBy`. Its `text` is prose, left alone.
 * The body is never touched: its digest guards drafts (S4), and a question's wording is the asker's.
 *
 * Seats compare exactly, case and all: a rename names the spelling it replaces, and a case-only
 * rename (ASKCASE: `domain:Language` → `domain:language`) rewrites only that spelling. A match is a
 * WHOLE seat name: never preceded by a seat-name character, and never followed by one that would
 * continue it.
 */
import { ANSWER_FENCES, DRAFT_FENCES, FOLLOWUP_ENTRIES, HISTORY_FENCES, PANEL_FENCES } from "./format.ts";

export type SeatChange = { field: string; from: string; to: string };

/** Header fields whose whole value is one seat. */
export const SEAT_FIELDS = ["to", "from", "reserved-for", "askedBy", "readBy", "actedBy", "superseded-actor", "overruled", "withdrawn-actor", "withdrawn-draft-of"] as const;
/** Store-written stamps in which any whole-name mention of the seat is the seat. */
const STAMP_TEXT_FIELDS = ["delivery", "deliveryNote", "revisions", "replaced"] as const;
/** JSON keys, in the answer and draft records, whose value is a seat. */
const JSON_SEAT_KEYS = ["answeredBy", "readBy", "relayedFrom", "actedBy"];
/** ASKFOLLOWUP: JSON keys, in a follow-up record, whose value is a seat. */
const FOLLOWUP_SEAT_KEYS = ["by", "addressedBy"];
/** IDE-338: JSON keys, in an attach-panel entry, whose value is a seat. */
const PANEL_SEAT_KEYS = ["by"];

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
/** Not after a seat-name character: `xidealic:kernel` and `app:idealic:kernel` are other names. */
const BEFORE = "(?<![A-Za-z0-9_.:@-])";
/** Not continued: `idealic:kernelx`, `idealic:kernel-2`, `idealic:kernel.v2`, `idealic:kernel:sub`. */
const AFTER = "(?![A-Za-z0-9_-]|[.:@][A-Za-z0-9_])";
const wholeName = (seat: string) => new RegExp(`${BEFORE}${esc(seat)}${AFTER}`, "g");
const refOf = (seat: string) => new RegExp(`${BEFORE}${esc(seat)}/(?=\\S)`, "g");

/** One header value's rewrite, by field. Returns the new value and the changes, field-named. */
function rewriteHeaderValue(key: string, value: string, old: string, neu: string): { value: string; changes: SeatChange[] } {
  const changes: SeatChange[] = [];
  if (key === "askedBy") {
    // S2 (round 2): `seat · thread · log` — only the first segment is a seat, and only a whole match counts.
    const parts = value.split(" · ");
    if (parts[0].trim() !== old) return { value, changes };
    parts[0] = parts[0].replace(old, neu);
    changes.push({ field: key, from: old, to: neu });
    return { value: parts.join(" · "), changes };
  }
  if ((SEAT_FIELDS as readonly string[]).includes(key)) {
    if (value.trim() !== old) return { value, changes };
    changes.push({ field: key, from: old, to: neu });
    return { value: value.replace(old, neu), changes };
  }
  if (key === "reads") {
    const out = value.split(/(\s;\s)/).map((part, i) => {
      if (i % 2) return part;
      const m = part.match(/^(\s*)(.+)(@[^@]+)$/);
      if (!m || m[2] !== old) return part;
      changes.push({ field: "reads", from: `${old}${m[3]}`, to: `${neu}${m[3]}` });
      return `${m[1]}${neu}${m[3]}`;
    });
    return { value: out.join(""), changes };
  }
  if (key === "forwards") {
    const out = value.split(/(\s;\s)/).map((part, i) => {
      if (i % 2) return part;
      // The reason is kept verbatim: only the hop's head, `from→to@at`, is read.
      const cut = part.search(/\s+\[declined: /);
      const head = cut === -1 ? part : part.slice(0, cut);
      const tail = cut === -1 ? "" : part.slice(cut);
      const m = head.match(/^(\s*)(.+?)→(.+?)(@\d{4}-\d{2}-\d{2}T.*)$/) ?? head.match(/^(\s*)(.+?)→(.+)(@[^@]+)$/);
      if (!m) return part;
      const from = m[2] === old ? neu : m[2];
      const to = m[3] === old ? neu : m[3];
      if (from === m[2] && to === m[3]) return part;
      changes.push({ field: "forwards", from: `${m[2]}→${m[3]}${m[4]}`, to: `${from}→${to}${m[4]}` });
      return `${m[1]}${from}→${to}${m[4]}${tail}`;
    });
    return { value: out.join(""), changes };
  }
  if ((STAMP_TEXT_FIELDS as readonly string[]).includes(key)) {
    const out = value.replace(wholeName(old), neu);
    if (out !== value) changes.push({ field: key, from: value, to: out });
    return { value: out, changes };
  }
  const out = value.replace(refOf(old), () => {
    changes.push({ field: key, from: `${old}/…`, to: `${neu}/…` });
    return `${neu}/`;
  });
  // Name each ref whole, so a preview says which ask it points at.
  if (changes.length) {
    const refs = [...value.matchAll(new RegExp(`${BEFORE}${esc(old)}/(\\S+?)(?=[\\s;,)\\]]|$)`, "g"))].map((m) => m[1]);
    changes.forEach((c, i) => {
      const id = refs[i] ?? "…";
      c.from = `${old}/${id}`;
      c.to = `${neu}/${id}`;
    });
  }
  return { value: out, changes };
}

/** Rewrite the seats in one JSON record's text, keeping its layout; `which` is `answer`, `draft` or `history`. */
function rewriteRecord(json: string, which: string, old: string, neu: string, changes: SeatChange[]): string {
  const keys = which === "followup" ? FOLLOWUP_SEAT_KEYS : which === "panels" ? PANEL_SEAT_KEYS : JSON_SEAT_KEYS;
  const keyed = new RegExp(`("(${keys.join("|")})"\\s*:\\s*")${esc(old)}(")`, "g");
  let out = json.replace(keyed, (_m, pre: string, key: string, post: string) => {
    changes.push({ field: `${which}.${key}`, from: old, to: neu });
    return `${pre}${neu}${post}`;
  });
  out = out.replace(new RegExp(`("answeredVia"\\s*:\\s*"relay:)${esc(old)}(")`, "g"), (_m, pre: string, post: string) => {
    changes.push({ field: `${which}.answeredVia`, from: `relay:${old}`, to: `relay:${neu}` });
    return `${pre}${neu}${post}`;
  });
  return out;
}

/**
 * Rewrite one ask file's references from `old` to `neu`. Returns the text unchanged (and no
 * changes) for a file that names neither, or that has no header block.
 */
export function rewriteSeatRefs(text: string, old: string, neu: string): { text: string; changes: SeatChange[] } {
  const lines = text.split("\n");
  const end = lines[0]?.trim() === "---" ? lines.indexOf("---", 1) : -1;
  if (end === -1) return { text, changes: [] };
  const changes: SeatChange[] = [];
  for (let i = 1; i < end; i++) {
    const m = lines[i].match(/^([A-Za-z][\w-]*):(\s?)(.*)$/);
    if (!m) continue;
    const r = rewriteHeaderValue(m[1], m[3], old, neu);
    if (r.changes.length) {
      lines[i] = `${m[1]}:${m[2]}${r.value}`;
      changes.push(...r.changes);
    }
  }
  const head = lines.slice(0, end + 1).join("\n");
  let rest = lines.slice(end + 1).join("\n");
  // `rest` starts at the line after `---`, so a fence on that very line still has its `\n` before it.
  rest = `\n${rest}`;
  for (const [re, which] of [[ANSWER_FENCES, "answer"], [DRAFT_FENCES, "draft"], [HISTORY_FENCES, "history"], [FOLLOWUP_ENTRIES, "followup"], [PANEL_FENCES, "panels"]] as const) {
    rest = rest.replace(re, (whole: string, json: string) => {
      const out = rewriteRecord(json, which, old, neu, changes);
      return out === json ? whole : whole.replace(json, () => out);
    });
  }
  return { text: changes.length ? `${head}${rest}` : text, changes };
}

/** A `<seat>/<id>` ref left in prose: where it sits and what it says. */
export type LeftRef = { field: string; ref: string };

/**
 * N1 (round 2): the `<old>/<id>` refs a rename leaves as written — in the body, in a declined hop's
 * reason, and in a record's `note` or `reason`. They are prose (the body's digest guards drafts, and a
 * reason is kept byte for byte), so they are listed for the operator rather than rewritten;
 * `engine ask read <old>/<id>` will not find the ask they name.
 */
export function leftRefs(text: string, old: string): LeftRef[] {
  const lines = text.split("\n");
  const end = lines[0]?.trim() === "---" ? lines.indexOf("---", 1) : -1;
  if (end === -1) return [];
  const out: LeftRef[] = [];
  const find = (field: string, s: string) => {
    for (const m of s.matchAll(new RegExp(`${BEFORE}${esc(old)}/([A-Za-z0-9][A-Za-z0-9_.:@-]*)`, "g"))) {
      out.push({ field, ref: `${old}/${m[1].replace(/[.:@-]+$/, "")}` });
    }
  };
  for (let i = 1; i < end; i++) {
    const m = lines[i].match(/^forwards:\s?(.*)$/);
    if (!m) continue;
    for (const hop of m[1].split(/\s;\s/)) {
      const cut = hop.search(/\s+\[declined: /);
      if (cut !== -1) find("forwards reason", hop.slice(cut));
    }
  }
  let body = `\n${lines.slice(end + 1).join("\n")}`;
  for (const [re, which] of [[ANSWER_FENCES, "answer"], [DRAFT_FENCES, "draft"], [HISTORY_FENCES, "history"], [FOLLOWUP_ENTRIES, "followup"], [PANEL_FENCES, "panels"]] as const) {
    body = body.replace(re, (_whole: string, json: string) => {
      try {
        // The history fence is a list of records; the others are one.
        const parsed = JSON.parse(json) as Record<string, unknown> | Record<string, unknown>[];
        for (const rec of Array.isArray(parsed) ? parsed : [parsed]) {
          for (const k of ["note", "reason", "text", "deliveryNote"]) if (typeof rec?.[k] === "string") find(`${which}.${k}`, rec[k] as string);
        }
      } catch {
        // an unreadable record names nothing we can point at
      }
      return "\n";
    });
  }
  find("body", body);
  return out;
}
