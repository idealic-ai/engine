/**
 * NOTIFYQ: an ask notice that asks nobody to act is queued, never pushed.
 *
 * Why: a push to a seat's socket interrupts it (an idle seat is woken, a busy one takes it mid-turn),
 * and the operator ruled that a notice which needs no action must not interrupt at all. A council
 * backfill that attached panels to fourteen forks of one ask sent fourteen "[ask-panel] … No action
 * needed" pushes into one pane. So these notices — panel, revised, superseded, withdrawn — go into the
 * per-seat broadcast queue IDE-352 built for idle seats, and the seat sees them at its next prompt (or,
 * mid-turn, after a tool call) as one digest per ask. Notices that DO ask for action (an answer, a
 * pass-up, a follow-up, a wake, a new ask) stay live pushes through deliver.ts.
 *
 * The queue is broadcast.sh's (scripts/broadcast.sh `fan_out` and `cmd_pending`), not a second one:
 *   - `<dir>/<id>.md` is a broadcast record (header, `## Text`, `## Delivery`);
 *   - `<dir>/queued/<seat, lowercased>/<id>` is an empty file saying the seat has not seen it;
 *   - hooks/user-prompt-broadcast-queue.sh runs `engine broadcast pending --queued`, which claims each
 *     entry by rename, prints it once and appends `delivered <seat> at-wake … via=queue`.
 * `<dir>` is resolved exactly as broadcast.sh resolves BDIR — BROADCAST_DIR, else
 * ~/.claude/data/yarik/broadcasts — and never from ASK_ROOT, so a notice lands where the drain reads.
 *
 * The record: `from: ask-app` (the actors are named in each detail line and in `notice-events:`),
 * `kind: ask-notice` (broadcast.sh prints it without an ack line and `resend` refuses it), and
 * `message: tell` + `tier: note`, TELL's note tier: queued for every seat, never pushed. Its state is
 * read from its `queued`/`delivered` lines; it is never acked. A `done:` line is written at creation,
 * so `engine broadcast status` reads it as complete.
 *
 * The digest: one record per (seat, ask) while it sits unseen. A second notice for the same ask is
 * merged into it. To merge, this process first takes the queue entry itself (renamed to
 * `.<id>.hold.<pid>`, the form the drain already recognises and restores if this process dies), so the
 * drain can neither show nor mark the record while it is rewritten; if the drain got the entry first,
 * the notice starts a new record and the shown one is left untouched. Nothing is lost or shown twice.
 *
 * Refusals (`undelivered`, never a throw): `operator`, which is not a seat; and — the fixture guard — a
 * notice bound for the fleet's live queue (BROADCAST_DIR unset) about an ask file outside the fleet's
 * live ask root. A test or a scratch ASK_ROOT that forgets BROADCAST_DIR therefore writes nothing into
 * real seats' queues.
 *
 * Cleanup: when a seat's new digest is written, that seat's earlier digests that were delivered more
 * than NOTICE_KEEP_MS ago and are no longer queued are deleted.
 */
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

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
  /** One line: what happened, naming who did it. */
  detail: string;
  at?: string;
};

export type NoticeResult = { status: "queued"; id: string; record: string; merged: boolean; reason?: string } | { status: "undelivered"; reason: string };

export type NoticeOptions = { noticeDir?: string; now?: string };

/** broadcast.sh's ID_RE. */
const ID_RE = /^[a-z0-9][a-z0-9._-]{0,63}$/;
/** Detail lines kept in one digest; the first line still counts every event. */
export const DIGEST_DETAIL_MAX = 10;
/** How long a delivered digest is kept after it was shown. */
export const NOTICE_KEEP_MS = 24 * 60 * 60_000;
const LOCK_STALE_MS = 10_000;

const fleetData = () => path.join(os.homedir(), ".claude", "data", "yarik");
/** broadcast.sh's BDIR, exactly: BROADCAST_DIR, else ~/.claude/data/yarik/broadcasts. */
export const noticeQueueDir = () => process.env.BROADCAST_DIR || path.join(fleetData(), "broadcasts");
/** True when the queue dir is the fleet's live one (BROADCAST_DIR unset). */
const isLiveQueue = (dir: string) => !process.env.BROADCAST_DIR && path.resolve(dir) === path.join(fleetData(), "broadcasts");

/** A record's header (before `## Text`) says it is an ask-app digest. Shared by every broadcast reader. */
export function isAskNotice(text: string): boolean {
  return /^kind: ask-notice$/m.test(text.split("\n## Text\n")[0]);
}

const queueDir = (dir: string, seat: string) => path.join(dir, "queued", seat.toLowerCase());
const keyOf = (seat: string, ref: string) => createHash("sha256").update(`${seat.toLowerCase()}\n${ref}`).digest("hex").slice(0, 10);
const oneLine = (s: string) => s.replace(/[\r\n]+/g, " ").trim();
const real = (p: string) => {
  try {
    return fs.realpathSync(p);
  } catch {
    return path.resolve(p);
  }
};
const inside = (file: string, root: string) => {
  const rel = path.relative(real(root), real(path.dirname(file)));
  return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
};

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

/** The digest's first line: the ask, every fork and event it carries, and what (not) to do. */
export function digestLine(ref: string, events: NoticeEvent[]): string {
  const parts: string[] = [];
  const panels = events.filter((e) => e.kind === "panel");
  if (panels.length) {
    const forks = [...new Set(panels.map((e) => e.fork ?? "?"))];
    const bys = [...new Set(panels.map((e) => e.by))];
    parts.push(`${panels.length === 1 ? "a panel" : `${panels.length} panels`} attached on fork${forks.length === 1 ? "" : "s"} ${forks.join(", ")} (by ${bys.join(", ")})`);
  }
  for (const e of events) if (e.kind !== "panel") parts.push(e.detail);
  // A superseded ask has a replacement the holder still owes an answer to: say so, never "no action".
  const close = events.some((e) => e.kind === "superseded")
    ? "Answer the replacement named above; do not reply to or ack this notice."
    : "No action needed: do not reply to or ack this notice.";
  return `[ask-notices] ${ref}: ${parts.join("; ")}. ${close}`;
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
    "from: ask-app",
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
  if (!isAskNotice(text)) return undefined;
  const m = text.split("\n## Text\n")[0].match(/^notice-events: (.*)$/m);
  if (!m) return undefined;
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

/** Delete this seat's digests that are shown, unqueued and older than NOTICE_KEEP_MS. Best effort. */
function prune(dir: string, seat: string, now: number) {
  const qd = queueDir(dir, seat);
  const want = seat.toLowerCase();
  let names: string[];
  try {
    names = fs.readdirSync(dir).filter((n) => n.startsWith("ask-notice-") && n.endsWith(".md"));
  } catch {
    return;
  }
  for (const n of names) {
    const id = n.slice(0, -3);
    try {
      if (fs.readdirSync(qd).some((q) => q === id || q.startsWith(`.${id}.`))) continue;
      const rec = path.join(dir, n);
      const text = fs.readFileSync(rec, "utf8");
      if (!isAskNotice(text) || text.match(/^audience: (.*)$/m)?.[1].trim().toLowerCase() !== want) continue;
      const shown = [...text.matchAll(/^delivered \S+ at-(?:wake|ack) (\S+)/gm)].map((m) => Date.parse(m[1])).filter(Number.isFinite);
      if (shown.length && now - Math.max(...shown) > NOTICE_KEEP_MS) fs.rmSync(rec, { force: true });
    } catch {
      // leave it
    }
  }
}

/**
 * Queue one no-action notice for `seat`, merged into the seat's unseen digest for the same ask.
 * Never throws: a refusal or a queue that cannot be written comes back `undelivered` with the reason,
 * and the ask file stays the record.
 */
export async function queueNotice(seat: string, event: NoticeEvent, o: NoticeOptions = {}): Promise<NoticeResult> {
  if (!seat || seat === "operator") return { status: "undelivered", reason: "operator is not a seat; nothing is queued" };
  const dir = o.noticeDir ?? noticeQueueDir();
  const liveAsks = path.join(fleetData(), "asks");
  if (isLiveQueue(dir) && !inside(event.file, liveAsks)) {
    return { status: "undelivered", reason: `refused: ${event.file} is outside the fleet's ask root ${liveAsks} and BROADCAST_DIR is unset, so a notice about it would reach real seats' queues; set BROADCAST_DIR` };
  }
  const at = o.now ?? new Date().toISOString();
  const ev: NoticeEvent = { ...event, detail: oneLine(event.detail), at: event.at ?? at };
  try {
    const qd = queueDir(dir, seat);
    fs.mkdirSync(qd, { recursive: true });
    return await withDirLock(qd, () => {
      const existing = pendingDigest(dir, seat, ev.ref);
      if (existing) {
        // Take the entry first: while it is held the drain neither shows nor marks the record.
        const hold = path.join(qd, `.${existing}.hold.${process.pid}`);
        let held = false;
        try {
          fs.renameSync(path.join(qd, existing), hold);
          held = true;
        } catch {
          // the drain claimed it first: it is shown as it was, and this notice starts a new digest
        }
        if (held) {
          const rec = path.join(dir, `${existing}.md`);
          try {
            const text = fs.readFileSync(rec, "utf8");
            const events = recordEvents(text);
            if (events) {
              const tail = text.indexOf("\n## Delivery\n");
              const delivery = tail >= 0 ? text.slice(tail + "\n## Delivery\n\n".length) : "";
              const head = text.match(/^at: (.*)$/m)?.[1] ?? at;
              atomic(rec, recordText(existing, seat, head, [...events, ev], delivery));
              return { status: "queued" as const, id: existing, record: rec, merged: true };
            }
          } finally {
            fs.renameSync(hold, path.join(qd, existing));
          }
        }
      }
      let id = `ask-notice-${keyOf(seat, ev.ref)}-${Date.now().toString(36)}`;
      for (let n = 2; fs.existsSync(path.join(dir, `${id}.md`)); n++) id = `${id.replace(/\.\d+$/, "")}.${n}`;
      const rec = path.join(dir, `${id}.md`);
      // The record before the entry: the drain drops an entry whose record it cannot read.
      fs.writeFileSync(rec, recordText(id, seat, at, [ev], `queued ${seat} pid=- idle=? via=ask-notice\ndone: rc=0 delivered=0 undelivered=0 queued=1 at ${at}\n`), { flag: "wx" });
      fs.writeFileSync(path.join(qd, id), "");
      prune(dir, seat, Date.parse(at) || Date.now());
      return { status: "queued" as const, id, record: rec, merged: false };
    });
  } catch (e) {
    return { status: "undelivered", reason: `could not queue the notice: ${String((e as Error)?.message ?? e)}` };
  }
}
