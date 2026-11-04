/**
 * NOTIFYQ: an ask notice that asks nobody to act is queued, never pushed.
 *
 * Why: a push to a seat's socket interrupts it (an idle seat is woken, a busy one takes it mid-turn),
 * and the operator ruled that a notice which needs no action must not interrupt at all. A council
 * backfill that attached panels to fourteen forks of one ask sent fourteen "[ask-panel] … No action
 * needed" pushes into one pane. So these notices — `[ask-panel]`, `[ask-revised]`, `[ask-superseded]`,
 * `[ask-withdrawn]` — go into the per-seat broadcast queue IDE-352 built for idle seats, and the seat
 * sees them at its next prompt (or, mid-turn, after a tool call) as one digest per ask.
 * Notices that DO ask for action (an answer, a pass-up, a follow-up, a wake, a new ask) stay live
 * pushes through deliver.ts; nothing here touches them.
 *
 * The queue is broadcast.sh's (scripts/broadcast.sh, `fan_out` and `cmd_pending`), not a second one:
 *   - `$BROADCAST_DIR/<id>.md` is a broadcast record (header, `## Text`, `## Delivery`);
 *   - `$BROADCAST_DIR/queued/<seat, lowercased>/<id>` is an empty file saying the seat has not seen it;
 *   - hooks/user-prompt-broadcast-queue.sh runs `engine broadcast pending --queued`, which claims each
 *     entry by rename, prints it once and appends `delivered <seat> at-wake … via=queue`.
 * The record says `kind: ask-notice`, so broadcast.sh prints it without asking for an ack, and
 * `message: tell` + `tier: note` (TELL's note tier: queued for every seat, never pushed), so a reader
 * of tells shows it as what it is.
 *
 * The digest: one record per (seat, ask) while it sits unseen in the queue. A second notice for the
 * same ask before the seat drains it is merged into that record — its first line lists every fork and
 * event — so a backfill over seven forks is one queued item, not seven. Once drained, the next notice
 * starts a new record. Merging rewrites the record by rename; if the drain claimed the entry while we
 * were merging, the event is queued again in a fresh record, so an event can be shown twice but is
 * never lost.
 *
 * `operator` is never queued (it is not a seat; the app redraws from the file). The operator's own
 * pane is a seat like any other, so its notices queue and show at its next prompt.
 */
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { defaultBroadcastDir } from "./broadcasts.ts";

export type NoticeKind = "panel" | "revised" | "superseded" | "withdrawn";

export type NoticeEvent = {
  /** `<seat>/<id>` of the ask the notice is about. */
  ref: string;
  /** The ask file, the record. */
  file: string;
  kind: NoticeKind;
  /** Who did the thing the notice reports. */
  by: string;
  /** The fork, for a panel. */
  fork?: string;
  /** One line: what happened, in the words the old push used. */
  detail: string;
  at?: string;
};

export type NoticeResult = { status: "queued"; id: string; record: string; merged: boolean; reason?: string } | { status: "undelivered"; reason: string };

export type NoticeOptions = { noticeDir?: string; now?: string };

/** broadcast.sh's ID_RE. */
const ID_RE = /^[a-z0-9][a-z0-9._-]{0,63}$/;
/** Detail lines kept in one digest; the first line still counts every event. */
export const DIGEST_DETAIL_MAX = 10;
const LOCK_STALE_MS = 10_000;

const queueDir = (dir: string, seat: string) => path.join(dir, "queued", seat.toLowerCase());
const keyOf = (seat: string, ref: string) => createHash("sha256").update(`${seat.toLowerCase()}\n${ref}`).digest("hex").slice(0, 10);
const oneLine = (s: string) => s.replace(/[\r\n]+/g, " ").trim();

function atomic(file: string, text: string) {
  const tmp = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.tmp`);
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, file);
}

async function withDirLock<T>(dir: string, fn: () => T): Promise<T> {
  const lock = path.join(dir, ".ask-notice.lock");
  for (let i = 0; ; i++) {
    try {
      fs.mkdirSync(lock);
      break;
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
      try {
        if (Date.now() - fs.statSync(lock).mtimeMs > LOCK_STALE_MS) fs.rmdirSync(lock);
      } catch {
        // gone already
      }
      if (i > 500) throw new Error(`could not lock ${dir}`);
      await new Promise((r) => setTimeout(r, 10));
    }
  }
  try {
    return fn();
  } finally {
    try {
      fs.rmdirSync(lock);
    } catch {
      // released already
    }
  }
}

/** The digest's first line: the ask, every fork and event it carries, and that nothing is asked. */
export function digestLine(ref: string, events: NoticeEvent[]): string {
  const parts: string[] = [];
  const panels = events.filter((e) => e.kind === "panel");
  if (panels.length) {
    const forks = [...new Set(panels.map((e) => e.fork ?? "?"))];
    const bys = [...new Set(panels.map((e) => e.by))];
    parts.push(`${panels.length === 1 ? "a panel" : `${panels.length} panels`} attached on fork${forks.length === 1 ? "" : "s"} ${forks.join(", ")} (by ${bys.join(", ")})`);
  }
  for (const e of events) if (e.kind !== "panel") parts.push(e.detail);
  return `[ask-notices] ${ref}: ${parts.join("; ")}. No action needed: do not answer, acknowledge or ack this.`;
}

/** The record's `## Text`: the digest line, up to DIGEST_DETAIL_MAX detail lines, and the file. */
export function digestText(ref: string, file: string, events: NoticeEvent[]): string {
  const shown = events.slice(0, DIGEST_DETAIL_MAX).map((e) => `- ${e.detail}`);
  const more = events.length > DIGEST_DETAIL_MAX ? [`- +${events.length - DIGEST_DETAIL_MAX} more`] : [];
  return [digestLine(ref, events), ...shown, ...more, `The file is the record: ${file}`].join("\n");
}

function recordText(id: string, seat: string, at: string, events: NoticeEvent[], delivery: string): string {
  const e0 = events[0];
  return [
    `# Broadcast ${id}`,
    "",
    `id: ${id}`,
    `from: ${e0.by}`,
    "sent-by: ask-app",
    `at: ${at}`,
    "scope: seat",
    "sticky: no",
    "expires: -",
    `audience: ${seat}`,
    "kind: ask-notice",
    "message: tell",
    "tier: note",
    `subject: ask notices on ${e0.ref}`,
    `ask: ${e0.ref}`,
    `notice-events: ${JSON.stringify(events)}`,
    "",
    "## Text",
    "",
    digestText(e0.ref, e0.file, events),
    "",
    "## Delivery",
    "",
    delivery,
  ].join("\n");
}

/** The events a record holds (its `notice-events:` header), or undefined when it is not ours or unreadable. */
export function recordEvents(text: string): NoticeEvent[] | undefined {
  const head = text.split("\n## Text\n")[0];
  const m = head.match(/^notice-events: (.*)$/m);
  if (!m || !/^kind: ask-notice$/m.test(head)) return undefined;
  try {
    const v = JSON.parse(m[1]);
    return Array.isArray(v) ? v : undefined;
  } catch {
    return undefined;
  }
}

/** The unseen queue entry already carrying this seat's digest for `ref`, if any. */
function pendingDigest(dir: string, seat: string, ref: string): string | undefined {
  const prefix = `ask-notice-${keyOf(seat, ref)}-`;
  let names: string[];
  try {
    names = fs.readdirSync(queueDir(dir, seat));
  } catch {
    return undefined;
  }
  return names.filter((n) => n.startsWith(prefix) && ID_RE.test(n) && fs.existsSync(path.join(dir, `${n}.md`))).sort().at(-1);
}

/**
 * Queue one no-action notice for `seat`, merged into the seat's unseen digest for the same ask.
 * Never throws: a queue that cannot be written comes back `undelivered` with the reason, as a failed
 * push did, and the ask file stays the record.
 */
export async function queueNotice(seat: string, event: NoticeEvent, o: NoticeOptions = {}): Promise<NoticeResult> {
  if (!seat || seat === "operator") return { status: "undelivered", reason: "operator is not a seat; nothing is queued" };
  const dir = o.noticeDir ?? defaultBroadcastDir();
  const at = o.now ?? new Date().toISOString();
  const ev: NoticeEvent = { ...event, detail: oneLine(event.detail), at: event.at ?? at };
  try {
    const qd = queueDir(dir, seat);
    fs.mkdirSync(qd, { recursive: true });
    return await withDirLock(qd, () => {
      const existing = pendingDigest(dir, seat, ev.ref);
      if (existing) {
        const rec = path.join(dir, `${existing}.md`);
        const text = fs.readFileSync(rec, "utf8");
        const events = recordEvents(text);
        if (events) {
          const delivery = text.slice(text.lastIndexOf("\n## Delivery\n") + "\n## Delivery\n\n".length);
          const head = text.match(/^at: (.*)$/m)?.[1] ?? at;
          atomic(rec, recordText(existing, seat, head, [...events, ev], delivery));
          // The drain may have claimed the entry while we wrote: then this event was not shown.
          if (fs.existsSync(path.join(qd, existing))) return { status: "queued" as const, id: existing, record: rec, merged: true };
        }
      }
      let id = `ask-notice-${keyOf(seat, ev.ref)}-${Date.now().toString(36)}`;
      for (let n = 2; fs.existsSync(path.join(dir, `${id}.md`)); n++) id = `${id.replace(/\.\d+$/, "")}.${n}`;
      const rec = path.join(dir, `${id}.md`);
      // The record before the entry: the drain drops an entry whose record it cannot read.
      fs.writeFileSync(rec, recordText(id, seat, at, [ev], `queued ${seat} pid=- idle=? via=ask-notice\n`), { flag: "wx" });
      fs.writeFileSync(path.join(qd, id), "");
      return { status: "queued" as const, id, record: rec, merged: false };
    });
  } catch (e) {
    return { status: "undelivered", reason: `could not queue the notice: ${String((e as Error)?.message ?? e)}` };
  }
}
