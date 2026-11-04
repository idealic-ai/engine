/**
 * TELL: the communication log between seats, as the ask app's Comms tab shows it. One row per
 * tell, broadcast or ask, newest first. Read-only.
 *
 * Tells and broadcasts are the same files (`<BROADCAST_DIR>/<id>.md`, written by scripts/broadcast.sh):
 * a tell carries `message: tell`, `tier:` and `subject:` header lines, and an align tell links its
 * managers' notice by `notice: <id>.align`, which points back by `notice-of:`. A broadcast with no
 * tier reads as `wake` when it was a wake broadcast and `lazy` otherwise, which is what its delivery
 * did. Asks come from the ask store; they ride no tier yet, and `engine ask new` pushes nothing to
 * the holder, so they read as `lazy`.
 */
import fs from "node:fs";
import path from "node:path";
import { defaultBroadcastDir } from "./broadcasts.ts";
import type { StoredAsk } from "./store.ts";

export type Tier = "note" | "lazy" | "align" | "escalate" | "wake";
export type SeatState = "queued" | "delivered" | "undelivered" | "not-attempted" | "read";
export type CommsRow = {
  id: string;
  kind: "tell" | "broadcast" | "ask";
  from: string;
  /** The seat that ran the command, when it differs from `from` (a broadcast sent on another's behalf). */
  sentBy: string;
  to: string[];
  tier: Tier;
  subject: string;
  at: string;
  /**
   * Tells and broadcasts: withdrawn · read (every recipient acked) · queued (a recipient has not
   * been shown it yet) · delivered · undelivered · not-attempted. Asks: the ask's own status.
   */
  state: string;
  /** Per recipient, tells and broadcasts only; an ask's is empty. */
  seats: { seat: string; state: SeatState }[];
  withdrawn: { by: string; at: string; reason: string } | null;
  /** An align tell's managers' notice id; null when it has none. */
  notice: string | null;
  /** On a notice (an align notice or a withdrawal notice): the tell it is about. */
  noticeOf: string | null;
  /** An escalate tell: the seats it was meant for. */
  forSeats: string[];
  /** Where the full record is: the ask's app path, or the record file. */
  ref: string;
};

export type CommsFilter = { seat?: string; tier?: string; kind?: string; since?: string; limit?: number };

const TIERS: Tier[] = ["note", "lazy", "align", "escalate", "wake"];

/** The header block, before the first `## Text` line. */
function headerOf(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of text.split("\n")) {
    if (line === "## Text") break;
    const m = line.match(/^([a-z][a-z-]*): ?(.*)$/);
    if (m && !(m[1] in out)) out[m[1]] = m[2].trim();
  }
  return out;
}

/** Lines after the last `## Delivery` heading (the writer's delivery log and any later sections). */
function afterDelivery(text: string): string[] {
  const lines = text.split("\n");
  const i = lines.lastIndexOf("## Delivery");
  return i < 0 ? [] : lines.slice(i + 1);
}

export function parseRecord(id: string, text: string, acks: string[], file: string): CommsRow {
  const h = headerOf(text);
  const tail = afterDelivery(text);
  const audience = (h.audience ?? "").split(/\s+/).filter(Boolean);
  const last = new Map<string, SeatState>();
  for (const l of tail) {
    const m = l.match(/^(delivered|queued|undelivered) (\S+)/);
    if (m && audience.includes(m[2])) last.set(m[2], m[1] as SeatState);
  }
  const ackSet = new Set(acks.map((a) => a.toLowerCase()));
  const seats = audience.map((seat) => ({ seat, state: (ackSet.has(seat.toLowerCase()) ? "read" : last.get(seat) ?? "not-attempted") as SeatState }));
  const w = tail.map((l) => l.match(/^withdrawn: by (\S+) at (\S+) — (.*)$/)).find(Boolean);
  const withdrawn = w ? { by: w[1], at: w[2], reason: w[3] } : null;
  const isTell = h.message === "tell";
  const tier: Tier = TIERS.includes(h.tier as Tier) ? (h.tier as Tier) : h.kind === "wake" ? "wake" : "lazy";
  const states = seats.map((s) => s.state);
  const state = withdrawn
    ? "withdrawn"
    : !states.length
      ? "not-attempted"
      : states.every((s) => s === "read")
        ? "read"
        : states.includes("queued")
          ? "queued"
          : states.some((s) => s === "delivered" || s === "read")
            ? "delivered"
            : states.includes("undelivered")
              ? "undelivered"
              : "not-attempted";
  const opt = (v?: string) => (v && v !== "-" ? v : null);
  return {
    id: h.id || id,
    kind: isTell ? "tell" : "broadcast",
    from: h.from ?? "",
    sentBy: h["sent-by"] ?? h.from ?? "",
    to: audience,
    tier,
    subject: h.subject || (text.split("\n## Text\n")[1] ?? "").trim().split("\n")[0].slice(0, 100),
    at: h.at ?? "",
    state,
    seats,
    withdrawn,
    notice: opt(h.notice),
    noticeOf: opt(h["notice-of"]),
    forSeats: (opt(h.for) ?? "").split(/\s+/).filter(Boolean),
    ref: file,
  };
}

export function askRow(a: StoredAsk): CommsRow {
  const h = a.header;
  const withdrawn = h.status === "withdrawn" ? { by: h["withdrawn-actor"] || "", at: h["withdrawn-at"] || "", reason: h["withdrawn-reason"] || "" } : null;
  return {
    id: `${a.seat}/${h.id ?? path.basename(a.file, ".md")}`,
    kind: "ask",
    from: h.from ?? a.seat,
    sentBy: h.from ?? a.seat,
    to: (h.to ?? "").split(/[\s,]+/).filter(Boolean),
    tier: "lazy",
    subject: h.topic || h.why || a.questions[0]?.title || "",
    at: h.created ?? "",
    state: h.status ?? "open",
    seats: [],
    withdrawn,
    notice: null,
    noticeOf: null,
    forSeats: [],
    ref: `/a/${a.seat}/${h.id ?? path.basename(a.file, ".md")}`,
  };
}

/** Every tell and broadcast record in `dir`. A missing directory is an empty list. */
export function listRecords(dir = defaultBroadcastDir()): CommsRow[] {
  let names: string[];
  try {
    names = fs.readdirSync(dir);
  } catch {
    return [];
  }
  const out: CommsRow[] = [];
  for (const n of names) {
    if (!n.endsWith(".md")) continue;
    const id = n.slice(0, -3);
    const file = path.join(dir, n);
    let text: string;
    try {
      text = fs.readFileSync(file, "utf8");
    } catch {
      continue;
    }
    let acks: string[] = [];
    try {
      acks = fs.readdirSync(path.join(dir, `${id}.acks.d`)).filter((f) => !f.startsWith("."));
    } catch {
      /* none yet */
    }
    out.push(parseRecord(id, text, acks, file));
  }
  return out;
}

/** The feed: tells, broadcasts and asks, filtered, newest first, at most `limit` (default 200, max 1000). */
export function listComms(asks: StoredAsk[], f: CommsFilter = {}, dir = defaultBroadcastDir()): CommsRow[] {
  const sinceMs = f.since ? Date.parse(f.since) : NaN;
  const kinds = f.kind ? f.kind.split(",") : null;
  const tiers = f.tier ? f.tier.split(",") : null;
  const rows = [...listRecords(dir), ...asks.map(askRow)].filter(
    (r) =>
      (!f.seat || r.from === f.seat || r.sentBy === f.seat || r.to.includes(f.seat) || r.forSeats.includes(f.seat)) &&
      (!tiers || tiers.includes(r.tier)) &&
      (!kinds || kinds.includes(r.kind)) &&
      (!Number.isFinite(sinceMs) || (Date.parse(r.at) || 0) >= sinceMs),
  );
  rows.sort((a, b) => (Date.parse(b.at) || 0) - (Date.parse(a.at) || 0));
  const limit = Math.min(Math.max(f.limit ?? 200, 1), 1000);
  return rows.slice(0, limit);
}
