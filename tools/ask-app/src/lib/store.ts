/**
 * Ask files on disk: `<root>/<asking seat>/<id>.md`. The directory is the ASKER's seat and never
 * changes; moving a question up the chain rewrites only its `to:` field.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pushToSeat, type DeliverOptions, type DeliveryResult } from "./deliver.ts";
import { AskFormatError, currentRevision, parseAskFile, setHeaderField, validateAnswer, writeAnswer, writeDecline, type AskAnswer, type ParsedAsk } from "./format.ts";

export type StoredAsk = ParsedAsk & { seat: string; file: string; mtimeMs: number };

export const defaultAskRoot = () =>
  process.env.ASK_ROOT || path.join(os.homedir(), ".claude", "data", "yarik", "asks");

const SAFE = /^[A-Za-z0-9][A-Za-z0-9_.:@-]*$/;

export function resolveAskPath(root: string, seat: string, id: string): string {
  if (!SAFE.test(seat) || seat.includes("..")) throw new AskFormatError(`invalid seat: ${seat}`);
  if (!SAFE.test(id) || id.includes("..")) throw new AskFormatError(`invalid id: ${id}`);
  return path.join(root, seat, `${id}.md`);
}

/** Write `text` beside `file` and rename over it, so a watcher never reads half a file. */
function atomicWrite(file: string, text: string) {
  const tmp = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.tmp`);
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, file);
}

export type NewAskFields = { from: string; to: string; id: string } & Record<string, string | undefined>;

export function newAsk(root: string, fields: NewAskFields, body: string): string {
  const file = resolveAskPath(root, fields.from, fields.id);
  if (fs.existsSync(file)) throw new AskFormatError(`ask already exists: ${file}`);
  const header: Record<string, string> = {
    id: fields.id,
    to: fields.to,
    from: fields.from,
    why: "", importance: "", stakes: "", context: "", alternatives: "", lean: "", falsifier: "",
    status: "open",
    revision: "1",
    dependsOn: "",
    created: new Date().toISOString(),
  };
  for (const [k, v] of Object.entries(fields)) if (v !== undefined && !["status", "revision"].includes(k)) header[k] = v;
  for (const [k, v] of Object.entries(header)) {
    if (/\n/.test(v)) throw new AskFormatError(`header value for ${k} must be one line`);
  }
  const text = `---\n${Object.entries(header).map(([k, v]) => (v ? `${k}: ${v}` : `${k}:`)).join("\n")}\n---\n\n${body.replace(/\n*$/, "\n")}`;
  const parsed = parseAskFile(text);
  if (parsed.questions.length === 0) {
    throw new AskFormatError('body holds no question: write at least one "## Choose one: …" or "## Choose: …" heading');
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  atomicWrite(file, text);
  return file;
}

export function listAsks(root: string): StoredAsk[] {
  let seats: string[];
  try {
    seats = fs.readdirSync(root, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name);
  } catch {
    return [];
  }
  const out: StoredAsk[] = [];
  for (const seat of seats) {
    for (const f of fs.readdirSync(path.join(root, seat))) {
      if (!f.endsWith(".md") || f.startsWith(".")) continue;
      const file = path.join(root, seat, f);
      try {
        const text = fs.readFileSync(file, "utf8");
        out.push({ ...parseAskFile(text), seat, file, mtimeMs: fs.statSync(file).mtimeMs });
      } catch {
        // an unreadable file is skipped, not fatal: one bad ask must not blank the list
      }
    }
  }
  return out.sort((a, b) => b.mtimeMs - a.mtimeMs);
}

/**
 * The push is a POINTER, never a second copy of the answer (INV_ONE_CHOSEN_DESTINATION): the file is
 * the one destination, and the message only wakes the asker to read it. The socket stamps no sender
 * (measured), so the first line names who answered and which ask.
 */
export function deliveryMessage(seat: string, id: string, file: string, answer: AskAnswer): string {
  const verb = answer.declined ? "declined" : "answered";
  return [
    `[ask-answer] from ${answer.answeredBy || "unknown"} via ask-app: ${seat}/${id} is ${verb}`,
    `${seat}/${id} was ${verb} at revision ${answer.revision}. Read the answer from the file; it is the only record:`,
    file,
  ].join("\n");
}

const LOCK_STALE_MS = 10_000;

/** A per-file mkdir lock: atomic on every local filesystem, and cleared if a holder died holding it. */
async function withFileLock<T>(file: string, fn: () => T | Promise<T>): Promise<T> {
  const lock = `${file}.lock`;
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
      if (i > 500) throw new AskFormatError(`could not lock ${file}`);
      await new Promise((r) => setTimeout(r, 10));
    }
  }
  try {
    return await fn();
  } finally {
    fs.rmdirSync(lock);
  }
}

export type AnswerInput = AskAnswer;

/**
 * Settle the ask, then push a pointer to the asking seat.
 *
 * - Compare-and-swap: `expectedRevision` is the revision the answerer read. If the file moved, the
 *   call throws StaleRevisionError and writes and pushes nothing, so one answer wins and only the
 *   winner is pushed.
 * - The file is written FIRST (`delivery: pending`); a failed push never loses the answer.
 * - The delivery outcome is stamped only if the revision is still the one this call wrote.
 * - An empty or unknown answer is refused; a decline needs a reason (INV_REFUSAL_IS_NOT_EMPTY).
 */
export async function answerAsk(
  root: string,
  seat: string,
  id: string,
  input: AnswerInput,
  opts: DeliverOptions & { push?: typeof pushToSeat; expectedRevision: number },
): Promise<{ file: string; revision: number; delivery: DeliveryResult }> {
  const file = resolveAskPath(root, seat, id);
  if (!Number.isInteger(opts?.expectedRevision)) throw new AskFormatError("expectedRevision is required: pass the revision you read");
  const at = input.answeredAt ?? new Date().toISOString();
  const { written, record } = await withFileLock(file, () => {
    const before = fs.readFileSync(file, "utf8");
    let text: string;
    if (input.declined) {
      text = writeDecline(before, { reason: input.reason ?? "", answeredBy: input.answeredBy, answeredAt: at, ...(input.note ? { note: input.note } : {}) }, opts.expectedRevision);
    } else {
      validateAnswer(parseAskFile(before), input.answers);
      text = writeAnswer(before, { answers: input.answers, ...(input.note ? { note: input.note } : {}), answeredBy: input.answeredBy, answeredAt: at }, opts.expectedRevision);
    }
    text = setHeaderField(text, "delivery", "pending");
    atomicWrite(file, text);
    const parsed = parseAskFile(text);
    return { written: currentRevision(parsed), record: { ...parsed.answer!, from: parsed.header.from } };
  });
  const asker = record.from || seat;
  const push = opts.push ?? pushToSeat;
  let delivery: DeliveryResult;
  try {
    delivery = await push(asker, deliveryMessage(seat, id, file, record), opts);
  } catch (e) {
    delivery = { status: "undelivered", reason: String(e) };
  }
  await withFileLock(file, () => {
    const now = fs.readFileSync(file, "utf8");
    if (currentRevision(parseAskFile(now)) !== written) return; // a later answer owns the delivery field
    let after = setHeaderField(now, "delivery", delivery.status);
    after = setHeaderField(after, "deliveryNote", (delivery.reason ?? "").replace(/\n/g, " "));
    atomicWrite(file, after);
  });
  return { file, revision: written, delivery };
}
