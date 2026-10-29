/**
 * Ask files on disk: `<root>/<asking seat>/<id>.md`. The directory is the ASKER's seat and never
 * changes; moving a question up the chain rewrites only its `to:` field.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pushToSeat, type DeliverOptions, type DeliveryResult } from "./deliver.ts";
import {
  AskFormatError,
  assertNotSuperseded,
  answerLines,
  bodyDigest,
  clearDraft,
  currentRevision,
  forwardChain,
  hopText,
  type Hop,
  CODE_RULE,
  hasRead,
  invalidDependsOn,
  invalidOptionCodes,
  parseAskFile,
  draftAuthor,
  readsOf,
  relayerOf,
  replacedSummary,
  trailingDraftFence,
  removeHeaderField,
  recipientsOf,
  RECORD_FENCE_RE,
  STAMP_FIELDS,
  setHeaderField,
  StaleRevisionError,
  validateAnswer,
  writeAnswer,
  writeDecline,
  writeDraft,
  type AskAnswer,
  type ParsedAsk,
} from "./format.ts";
import { rewriteSeatRefs, type SeatChange } from "./rename-seat.ts";

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
  if (fs.existsSync(file)) throw new AskFormatError(`ask already exists: ${fields.from}/${fields.id}`);
  // M1: answer and draft blocks are records the store writes. A body that carries one — planted or
  // quoted — would be read back as somebody's answer, so it is refused, not stored.
  if (RECORD_FENCE_RE.test(body)) {
    throw new AskFormatError("the body holds a ```json answer or ```json draft block: those are records the store writes, never part of a question (indent it or use another fence language to quote one)");
  }
  for (const k of STAMP_FIELDS) {
    if (fields[k] !== undefined) throw new AskFormatError(`${k} is written by the store as the ask moves; a new ask does not set it`);
  }
  if (fields.from === "operator") throw new AskFormatError("an ask comes from a seat; the operator is not one (it answers asks, or asks in chat)");
  if (fields.to === fields.from) throw new AskFormatError(`an ask is a question to somebody else: ${fields.from} cannot address an ask to itself`);
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
  assertCodes(parsed);
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

/** Refuse a body whose option codes the grammar cannot read, naming each offending code. */
function assertCodes(ask: ParsedAsk) {
  const bad = invalidOptionCodes(ask);
  if (bad.length) {
    throw new AskFormatError(`option code${bad.length > 1 ? "s" : ""} ${bad.map((b) => `[${b.code}] (in "${b.question}")`).join(", ")} not valid: a code is ${CODE_RULE}`);
  }
  // SHOULD-3: a choice fork with no options cannot be answered at all.
  const empty = ask.questions.filter((q) => (q.kind === "choose-one" || q.kind === "choose" || q.kind === "rank") && q.options.length === 0);
  if (empty.length) throw new AskFormatError(`${empty.map((q) => `"${q.title}"`).join(", ")}: a ${empty[0].kind} fork needs at least one option (- [ ] [CODE] Label)`);
  const deps = invalidDependsOn(ask);
  if (deps.length) throw new AskFormatError(`DependsOn refused: ${deps.join("; ")}`);
}

/**
 * The push wakes the asker and carries the answer's lines (`title → answer · seat/id#KEY`), the same
 * lines a batch carries, read back from the file just written. The file stays the record: the
 * message names it and how to fold it. The socket stamps no sender (measured), so the first line
 * names who answered and which ask.
 */
export function deliveryMessage(seat: string, id: string, file: string, answer: AskAnswer, lines: string[] = [], o: { replaced?: string; resent?: boolean } = {}): string {
  const verb = answer.declined ? "declined" : "answered";
  // IDE-304: a second answer says it CHANGED and what it replaced; a re-push says it is one.
  const first = o.replaced
    ? `[ask-answer-changed] from ${answer.answeredBy || "unknown"} via ask-app: ${seat}/${id} is ${verb} again; this answer replaces the earlier one`
    : `[ask-answer] from ${answer.answeredBy || "unknown"} via ask-app: ${seat}/${id} is ${verb}`;
  return [
    first,
    ...(o.replaced ? [`Replaced: ${o.replaced}`] : []),
    ...(o.resent ? ["Re-sent: an earlier push of this answer may not have arrived; nothing changed since."] : []),
    ...lines.map((l) => `- ${l}`),
    `${seat}/${id} was ${verb} at revision ${answer.revision}. The file is the record; \`engine ask read ${seat}/${id}\` prints it and marks it read:`,
    file,
  ].join("\n");
}

/** Who is writing a `delivery: pending` stamp, so a later send or read can tell it outlived its writer (S3). */
const writerStamp = (now = new Date()) => `${process.pid}@${now.toISOString()}`;

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
  opts: DeliverOptions &
    RelayStanding & {
      push?: typeof pushToSeat;
      expectedRevision: number;
      /** A reserved ask's decline by a seat goes here: the decliner's parent ("" → operator). */
      passUpTo?: string;
      /** A seat's parent ("" when none), to climb past the asker when the pass-up would land on it. */
      parentOf?: (seat: string) => string;
    },
): Promise<{ file: string; revision: number; delivery: DeliveryResult; passedUpTo?: string }> {
  const file = resolveAskPath(root, seat, id);
  if (!Number.isInteger(opts?.expectedRevision)) throw new AskFormatError("expectedRevision is required: pass the revision you read");
  const at = input.answeredAt ?? new Date().toISOString();
  // How the answerer was established (browser, cli, relay:<seat>) is part of the record.
  const via = input.answeredVia ? { answeredVia: input.answeredVia } : {};
  const passed = await withFileLock(file, () => {
    const before = fs.readFileSync(file, "utf8");
    const ask = parseAskFile(before);
    if (!isPassUp(ask, input)) return undefined;
    assertNotSuperseded(ask);
    if (!input.reason?.trim()) throw new AskFormatError("a decline needs a non-empty reason");
    const cur = currentRevision(ask);
    if (opts.expectedRevision !== cur) throw new StaleRevisionError(opts.expectedRevision, cur);
    const to = passUpTarget(opts.passUpTo?.trim() || "operator", ask.header.from ?? "", opts.parentOf);
    // N5: like a supersede, the move drops a saved draft (only the operator can hold one here).
    const after = clearDraft(forwardedText(before, ask, `${seat}/${id}`, { to, by: input.answeredBy ?? "", manages: opts.relayerManages, at, reason: input.reason }));
    atomicWrite(file, after);
    return { to, revision: cur + 1, reserved: reservedOf(ask), reason: forwardChain(parseAskFile(after).header).at(-1)?.reason ?? "" };
  });
  if (passed) {
    // The next holder hears it, with the reason; the operator is not a seat (the app redraws from the file).
    const delivery: DeliveryResult =
      passed.to === "operator"
        ? { status: "delivered" }
        : await safePush(opts.push ?? pushToSeat, passed.to, [
            `[ask-passed-up] from ${input.answeredBy} via ask-app: ${seat}/${id} is reserved for ${passed.reserved}; ${input.answeredBy} declined it and passed it up to you`,
            `Reason: ${passed.reason}`,
            `It is still open, at revision ${passed.revision}. Answer it only if you are who it is reserved for; otherwise decline it to pass it up again. The file is the record:`,
            file,
          ].join("\n"), opts);
    return { file, revision: passed.revision, delivery, passedUpTo: passed.to };
  }
  const { written, record, parsed, replaced } = await withFileLock(file, () => {
    const before = fs.readFileSync(file, "utf8");
    assertMayAnswer(parseAskFile(before), input, opts);
    const replaced = replacedSummary(parseAskFile(before));
    let text: string;
    if (input.declined) {
      text = writeDecline(before, { reason: input.reason ?? "", answeredBy: input.answeredBy, ...via, answeredAt: at, ...(input.note ? { note: input.note } : {}) }, opts.expectedRevision);
    } else {
      validateAnswer(parseAskFile(before), input.answers);
      text = writeAnswer(before, { answers: input.answers, ...(input.note ? { note: input.note } : {}), answeredBy: input.answeredBy, ...via, answeredAt: at }, opts.expectedRevision);
    }
    text = setHeaderField(setHeaderField(text, "delivery", "pending"), "deliveryWriter", writerStamp());
    atomicWrite(file, text);
    const parsed = parseAskFile(text);
    return { written: currentRevision(parsed), record: parsed.answer!, parsed, replaced };
  });
  const delivery = await pushAnswer(parsed, seat, file, record, opts, { replaced });
  await stampDelivery(file, written, delivery);
  return { file, revision: written, delivery };
}

/** S4: the asker and every seat that held and forwarded the ask hear the answer, with its lines. */
async function pushAnswer(parsed: ParsedAsk, seat: string, file: string, record: AskAnswer, opts: DeliverOptions & { push?: typeof pushToSeat }, how: { replaced?: string; resent?: boolean } = {}): Promise<DeliveryResult> {
  const push = opts.push ?? pushToSeat;
  const id = parsed.header.id ?? "";
  const msg = deliveryMessage(seat, id, file, record, answerLines(parsed, seat), how);
  const results: Record<string, DeliveryResult> = {};
  for (const s of pushTargets(parsed, seat)) {
    results[s] = isSelf(s, record) ? SELF : await safePush(push, s, msg, opts);
  }
  return combine(results);
}

/** The seats an answer is pushed to: the asker and every forwarder (the asker's seat when none is named). */
function pushTargets(parsed: ParsedAsk, seat: string): string[] {
  const seats = recipientsOf(parsed);
  return seats.length ? seats : [seat];
}

/**
 * No self-echo (operator, 2026-10-29 02:18): the seat that answered or recorded the answer is never
 * pushed its own answer. Its delivery counts as delivered — it wrote the file — so the ask neither
 * stays pending nor is re-pushed.
 */
const SELF: DeliveryResult = { status: "delivered" };
/** The answerer, or the seat that relayed the operator's answer: neither is pushed what it just wrote. */
const isSelf = (s: string, a: AskAnswer | undefined) => !!a && (s === a.answeredBy || s === relayerOf(a));

async function safePush(push: typeof pushToSeat, seat: string, content: string, opts: DeliverOptions): Promise<DeliveryResult> {
  try {
    return await push(seat, content, opts);
  } catch (e) {
    return { status: "undelivered", reason: String(e) };
  }
}

/**
 * One file's delivery across its recipients. `delivered` only when every recipient's socket took
 * it — and even then it means QUEUED, never read; readAt is the only read signal.
 */
function combine(results: Record<string, DeliveryResult>): DeliveryResult {
  const all = Object.entries(results);
  const bad = all.filter(([, r]) => r.status !== "delivered");
  if (bad.length === 0) return { status: "delivered" };
  const reason = bad.map(([s, r]) => `${s}: ${r.reason ?? "undelivered"}`).join("; ");
  if (all.length === 1) return { status: "undelivered", reason };
  return { status: bad.length === all.length ? "undelivered" : ("partial" as DeliveryResult["status"]), reason };
}

async function stampDelivery(file: string, written: number, delivery: DeliveryResult) {
  await withFileLock(file, () => {
    const now = fs.readFileSync(file, "utf8");
    if (currentRevision(parseAskFile(now)) !== written) return; // a later answer owns the delivery field
    let after = setHeaderField(now, "delivery", delivery.status);
    after = setHeaderField(after, "deliveryNote", (delivery.reason ?? "").replace(/\n/g, " "));
    after = removeHeaderField(after, "deliveryWriter");
    atomicWrite(file, after);
  });
}

/**
 * Who may answer (M3, the operator's ruling): the addressed seat (`to:`), a seat in its forward
 * chain, or the operator. Never the asker of its own ask, never a bystander.
 */
export function answerersOf(ask: ParsedAsk): string[] {
  const out = new Set<string>();
  if (ask.header.to) out.add(ask.header.to);
  for (const h of forwardChain(ask.header)) {
    out.add(h.from);
    out.add(h.to);
  }
  out.add("operator");
  // Never the asker, even when it once held its own ask (an ask to itself is refused at filing).
  if (ask.header.from) out.delete(ask.header.from);
  return [...out];
}

/**
 * Round 3 (MUST-1): FLEET_MANAGES, exported by run.sh from tmux `@pane_manages`, holds pane LABELS
 * (`ideas,writer,deploy` for manager:app; `idealic,app,domain` for manager:director), while asks
 * name full seats (`app:writer`, `manager:app`). A list entry names `seat` when it is the seat
 * itself, or the seat's label (the part after its window, `window:label`).
 */
export function managesSeat(list: string[], seat: string): boolean {
  return list.some((m) => !!m && (m === seat || seat.endsWith(`:${m}`)));
}

/** Who may RELAY the operator's answer onto `ask`: proof of a seat's standing to relay. */
export type RelayStanding = { relayerManages?: string[] };

/**
 * Round 2: a relay is recorded only by a seat in the ask's chain — the addressee, a forwarder — or
 * by a manager of the asker (its FLEET_MANAGES lists the asker). Never by the asker, never by a
 * bystander, and only ever for the operator.
 */
function assertMayRelay(ask: ParsedAsk, a: AskAnswer, standing: RelayStanding = {}) {
  const relayer = relayerOf(a);
  if (!relayer) return;
  const id = ask.header.id ?? "";
  if (a.answeredBy !== "operator") throw new AskFormatError(`a relay records the operator's answer; ${a.answeredBy || "an unnamed answerer"} is not relayed`);
  if (relayer === ask.header.from) throw new AskFormatError(`the asker (${relayer}) never relays an answer to its own ask ${id}; the operator answers it, or a seat in its chain relays`);
  const inChain = answerersOf(ask).filter((s) => s !== "operator").includes(relayer);
  const manager = !!ask.header.from && managesSeat(standing.relayerManages ?? [], ask.header.from);
  if (!inChain && !manager) {
    throw new AskFormatError(`${relayer} may not relay onto ${id}: a relay comes from the addressee, a forwarder, or a manager of the asker (${ask.header.from ?? "?"})`);
  }
}

/**
 * S2 (round 2): where a pass-up lands. The decliner's parent — unless that is the ask's own asker,
 * who cannot answer an operator-reserved ask either: then on up the asker's chain (`parentOf`),
 * skipping the asker each time, ending at `operator` when a seat has no parent, when the parent
 * cannot be read, or when the chain loops.
 */
function passUpTarget(first: string, asker: string, parentOf?: (seat: string) => string): string {
  let to = first;
  const seen = new Set<string>();
  while (to && to !== "operator" && to === asker) {
    if (seen.has(to)) return "operator";
    seen.add(to);
    to = parentOf?.(to)?.trim() || "operator";
  }
  return to || "operator";
}

const reservedOf = (ask: ParsedAsk) => ask.header["reserved-for"]?.trim() ?? "";

/**
 * The operator's ruling (2026-10-30): a decline of a reserved ask by anyone but the one it is
 * reserved for does not close it — it is passed up one rung (forward's rule), with its reason, and
 * stays open. The reserved party's own decline, and any decline of an unreserved ask, settle as before.
 */
function isPassUp(ask: ParsedAsk, a: AskAnswer): boolean {
  const reserved = reservedOf(ask);
  return !!a.declined && !!reserved && a.answeredBy !== reserved;
}

/** R4 and M3: an ask marked `reserved-for: operator` is answered by the operator; any ask only by its answerers. */
function assertMayAnswer(ask: ParsedAsk, a: AskAnswer, standing?: RelayStanding) {
  // First: a superseded ask is refused whoever answers, pointing at the ask that replaced it.
  assertNotSuperseded(ask);
  assertMayRelay(ask, a, standing);
  const by = a.answeredBy;
  const id = ask.header.id ?? "";
  const reserved = ask.header["reserved-for"]?.trim();
  if (reserved && by !== reserved) {
    throw new AskFormatError(`ask ${id} is reserved for ${reserved}; ${by || "an unnamed answerer"} may forward it but not answer it`);
  }
  if (!by) throw new AskFormatError(`an answer to ${id} must name its answerer`);
  if (!answerersOf(ask).includes(by)) {
    throw new AskFormatError(`${by} may not answer ${id}: only the addressed seat (${ask.header.to ?? "?"}), its forward chain, or the operator answers`);
  }
}

const splitRef = (ref: string) => {
  const i = ref.lastIndexOf("/");
  if (i < 1) throw new AskFormatError(`expected <seat>/<id>, got ${ref}`);
  return { seat: ref.slice(0, i), id: ref.slice(i + 1) };
};

// ── drafts and the batch send ────────────────────────────

/** Save (or replace) a draft in the file. Validated like an answer; nothing is pushed. */
export async function saveDraft(root: string, seat: string, id: string, input: AskAnswer, expectedRevision: number, standing: RelayStanding = {}): Promise<string> {
  const file = resolveAskPath(root, seat, id);
  if (!Number.isInteger(expectedRevision)) throw new AskFormatError("expectedRevision is required: pass the revision you read");
  await withFileLock(file, () => {
    const before = fs.readFileSync(file, "utf8");
    const ask = parseAskFile(before);
    assertNotSuperseded(ask);
    // S3 (round 2): a seat's decline of a reserved ask is a pass-up, which moves the ask at once;
    // it is never held as a draft.
    if (isPassUp(ask, input)) {
      throw new AskFormatError(`${seat}/${id} is reserved for ${reservedOf(ask)}: a seat's decline of it is not drafted; use \`engine ask answer --decline\` to pass it up`);
    }
    assertMayAnswer(ask, input, standing);
    // One draft per ask, owned by whoever saved it: another answerer does not overwrite it.
    // Round 3 (MUST-2): the operator outranks every answerer, so it may supersede a seat's draft
    // (the seat's draft is replaced, not answered); a seat never replaces another author's.
    if (ask.draft && draftAuthor(ask.draft) !== draftAuthor(input) && draftAuthor(input) !== "operator") {
      throw new AskFormatError(`${seat}/${id} holds a draft by ${draftAuthor(ask.draft) || "an unnamed answerer"}; only its author replaces or discards it`);
    }
    atomicWrite(file, writeDraft(before, input, expectedRevision));
  });
  return file;
}


/** Drop a draft. Only its author may (M3), or the operator (MUST-2); an ask with no draft is left as it is. */
export async function discardDraft(root: string, seat: string, id: string, by: string): Promise<void> {
  const file = resolveAskPath(root, seat, id);
  if (!by) throw new AskFormatError("discard must name who is discarding");
  await withFileLock(file, () => {
    const text = fs.readFileSync(file, "utf8");
    const d = parseAskFile(text).draft;
    if (d && draftAuthor(d) !== by && by !== "operator") throw new AskFormatError(`${seat}/${id}'s draft was saved by ${draftAuthor(d) || "an unnamed answerer"}; only its author discards it`);
    atomicWrite(file, clearDraft(text));
  });
}

export type BatchResult = {
  /** S3: answers whose `delivery: pending` outlived its writer, pushed again before this batch. */
  repushed: { ref: string; delivery: DeliveryResult }[];
  settled: { ref: string; revision: number; file: string }[];
  refused: { ref: string; error: string }[];
  pushes: { seat: string; refs: string[]; delivery: DeliveryResult }[];
};

/** The batch push: a summary built from the files just written, one per recipient seat. */
export function batchMessage(seat: string, answeredBy: string, items: { ref: string; file: string; lines: string[]; replaced?: string }[]): string {
  const n = items.length;
  return [
    `[ask-batch] from ${answeredBy || "unknown"} via ask-app: ${n} answer${n === 1 ? "" : "s"} for ${seat}`,
    // IDE-304: an item that replaces an earlier answer says so, and what it replaced.
    ...items.flatMap((it) => [...(it.replaced ? [`- [ask-answer-changed] ${it.ref} replaces ${it.replaced}`] : []), ...it.lines.map((l) => `- ${l}`)]),
    "",
    "Each answer is in its file, the only record. `engine ask read <seat>/<id>` prints it in full and marks it read:",
    ...items.map((it) => it.file),
  ].join("\n");
}

/**
 * Settle every draft named in `refs` (with none, every draft SAVED BY `by` — never anybody else's,
 * S1), then push ONE message per recipient seat. The request carries refs only: what is settled and
 * what is pushed is read from the files, so a batch can never send an answer a file does not hold.
 * A draft is sent only by its author. Before the batch, answers left `pending` by a writer that is
 * gone are pushed again (S3).
 */
export async function sendBatch(root: string, refs: string[] | undefined, opts: DeliverOptions & RelayStanding & { push?: typeof pushToSeat; by: string }): Promise<BatchResult> {
  const by = opts?.by;
  if (!by) throw new AskFormatError("send must name its sender: a batch sends only the sender's own drafts");
  const out: BatchResult = { repushed: await repushPending(root, opts), settled: [], refused: [], pushes: [] };
  const list = refs ?? listAsks(root).filter((a) => a.draft && draftAuthor(a.draft) === by).sort((a, b) => a.file.localeCompare(b.file)).map((a) => `${a.seat}/${a.header.id}`);
  const bySeat = new Map<string, { ref: string; file: string; lines: string[]; written: number; replaced?: string }[]>();
  const answerers = new Set<string>();
  const selfOnly: { file: string; written: number; seat: string }[] = [];
  for (const ref of list) {
    try {
      const { seat, id } = splitRef(ref);
      const file = resolveAskPath(root, seat, id);
      const settled = await withFileLock(file, () => {
        const before = fs.readFileSync(file, "utf8");
        const ask = parseAskFile(before);
        const d = ask.draft;
        assertNotSuperseded(ask);
        if (!d) throw new AskFormatError(`${ref} has no draft to send`);
        if (draftAuthor(d) !== by) throw new AskFormatError(`${ref}'s draft was saved by ${draftAuthor(d) || "an unnamed answerer"}; only its author sends it`);
        assertMayAnswer(ask, d, opts);
        // S4: the draft answers the question as it was when it was saved.
        if (d.bodyHash && d.bodyHash !== bodyDigest(before)) throw new AskFormatError(`${ref}: stale draft, the question was edited after the draft was saved: re-read it and draft again`);
        const replaced = replacedSummary(ask);
        const at = new Date().toISOString();
        const base = { answeredBy: d.answeredBy, ...(d.answeredVia ? { answeredVia: d.answeredVia } : {}), answeredAt: at, ...(d.note ? { note: d.note } : {}) };
        let text = d.declined
          ? writeDecline(before, { reason: d.reason ?? "", ...base }, d.basedOn)
          : (validateAnswer(ask, d.answers), writeAnswer(before, { answers: d.answers, ...base }, d.basedOn));
        text = setHeaderField(setHeaderField(text, "delivery", "pending"), "deliveryWriter", writerStamp());
        atomicWrite(file, text);
        return { ...parseAskFile(text), replaced };
      });
      const written = currentRevision(settled);
      out.settled.push({ ref, revision: written, file });
      answerers.add(settled.answer?.answeredBy ?? "");
      const item = { ref, file, lines: answerLines(settled, seat), written, ...(settled.replaced ? { replaced: settled.replaced } : {}) };
      for (const s of pushTargets(settled, seat)) {
        if (isSelf(s, settled.answer)) selfOnly.push({ file, written, seat: s });
        else bySeat.set(s, [...(bySeat.get(s) ?? []), item]);
      }
    } catch (e) {
      if (!(e instanceof AskFormatError)) throw e;
      out.refused.push({ ref, error: e instanceof StaleRevisionError ? `${e.message}: the ask moved (forwarded or answered) after the draft was saved; re-read it and draft again` : e.message });
    }
  }
  const push = opts.push ?? pushToSeat;
  const perFile = new Map<string, { written: number; results: Record<string, DeliveryResult> }>();
  for (const it of selfOnly) {
    const e = perFile.get(it.file) ?? { written: it.written, results: {} };
    e.results[it.seat] = SELF;
    perFile.set(it.file, e);
  }
  const from = [...answerers].filter(Boolean).join(", ");
  for (const [seat, items] of bySeat) {
    const delivery = await safePush(push, seat, batchMessage(seat, from, items), opts);
    out.pushes.push({ seat, refs: items.map((i) => i.ref), delivery });
    for (const it of items) {
      const e = perFile.get(it.file) ?? { written: it.written, results: {} };
      e.results[seat] = delivery;
      perFile.set(it.file, e);
    }
  }
  for (const [file, e] of perFile) await stampDelivery(file, e.written, combine(e.results));
  return out;
}

const NO_WRITER_GRACE_MS = 60_000;

function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return (e as NodeJS.ErrnoException).code === "EPERM";
  }
}

/**
 * Did this `delivery: pending` outlive its writer? A stamped writer counts as gone only when its pid
 * is dead — never on age alone, so a slow but live writer is never pushed over (round 2). A pending
 * with no writer (v1, or hand-made) counts once a minute has passed since the answer, so an
 * in-flight v1 push is not doubled — and only for a caller (`by`) the answer is for: one seat's read
 * never re-pushes the whole root's v1 leftovers.
 */
export function pendingOutlivedWriter(ask: ParsedAsk, o: { now?: number; by?: string } = {}): boolean {
  if (ask.header.delivery !== "pending" || !ask.answer) return false;
  const m = (ask.header.deliveryWriter ?? "").match(/^(\d+)@(.+)$/);
  if (!m) {
    if (!o.by || !recipientsOf(ask).includes(o.by)) return false;
    const at = Date.parse(ask.answer.answeredAt ?? "");
    return !Number.isFinite(at) || (o.now ?? Date.now()) - at > NO_WRITER_GRACE_MS;
  }
  const pid = Number(m[1]);
  return pid !== process.pid && !pidAlive(pid);
}

/**
 * S3: push again every settled ask whose `delivery: pending` outlived its writer — a crash between
 * settling and pushing. The claim is RE-CHECKED and taken under the file lock (the writer stamp
 * becomes ours), so two senders — in two processes — never push one answer twice.
 */
export async function repushPending(root: string, opts: DeliverOptions & { push?: typeof pushToSeat; now?: number; by?: string } = {}): Promise<{ ref: string; delivery: DeliveryResult }[]> {
  const out: { ref: string; delivery: DeliveryResult }[] = [];
  const check = { now: opts.now, by: opts.by };
  for (const a of listAsks(root)) {
    if (!pendingOutlivedWriter(a, check)) continue;
    const claimed = await withFileLock(a.file, () => {
      const text = fs.readFileSync(a.file, "utf8");
      const p = parseAskFile(text);
      // The re-check: another process may have claimed it between our listing and this lock.
      if (!pendingOutlivedWriter(p, check)) return null;
      atomicWrite(a.file, setHeaderField(text, "deliveryWriter", writerStamp()));
      return p;
    });
    if (!claimed?.answer) continue;
    // The answer's own `replaced:` line, if it was a change; marked re-sent either way.
    const delivery = await pushAnswer(claimed, a.seat, a.file, claimed.answer, opts, { replaced: claimed.header.replaced?.trim() || undefined, resent: true });
    await stampDelivery(a.file, currentRevision(claimed), delivery);
    out.push({ ref: `${a.seat}/${claimed.header.id ?? ""}`, delivery });
  }
  return out;
}

// ── read and acted ────────────────────────────────────────

export type ReadResult = { ref: string; file: string; ask: ParsedAsk; lines: string[]; stamped: boolean; why?: string };

/** Add `by`'s own read to the text: its `reads:` entry, and `readAt`/`readBy` when `by` is the asker (M2). */
function stampRead(text: string, ask: ParsedAsk, by: string, at: string): string {
  const reads = readsOf(ask.header).filter((r) => r.seat !== by);
  reads.push({ seat: by, at });
  let after = setHeaderField(text, "reads", reads.map((r) => `${r.seat}@${r.at}`).join(" ; "));
  if (by === ask.header.from) {
    after = setHeaderField(after, "readAt", at);
    after = setHeaderField(after, "readBy", by);
  }
  return after;
}

/** The seats an answer is FOR: the asker and every forwarder, minus whoever answered it. */
const readersOf = (ask: ParsedAsk) => recipientsOf(ask, ask.answer?.answeredBy);

/**
 * Print-side of `engine ask read`: the collapsed lines, and the READER's own read stamped the first
 * time a recipient of the answer (the asker, or a seat that forwarded it) reads a settled ask. Reads
 * are kept per recipient (M2): a forwarder's read is its own `reads:` entry and never stands for the
 * asker's, whose read is `readAt`. Nobody else's read counts.
 */
export async function readAsk(root: string, seat: string, id: string, o: { by?: string; now?: string } = {}): Promise<ReadResult> {
  const file = resolveAskPath(root, seat, id);
  const ref = `${seat}/${id}`;
  return withFileLock(file, () => {
    const text = fs.readFileSync(file, "utf8");
    const ask = parseAskFile(text);
    const lines = answerLines(ask, seat);
    const base = { ref, file, ask, lines };
    if (!ask.answer) return { ...base, stamped: false, why: `not settled (status ${ask.header.status})` };
    if (!o.by || !readersOf(ask).includes(o.by)) return { ...base, stamped: false, why: `${o.by || "an unnamed reader"} is not a recipient of this answer` };
    if (hasRead(ask, o.by)) return { ...base, stamped: false, why: `already read by ${o.by}` };
    const after = stampRead(text, ask, o.by, o.now ?? new Date().toISOString());
    atomicWrite(file, after);
    return { ...base, ask: parseAskFile(after), stamped: true };
  });
}

/**
 * The /next pickup for `seat`: every settled ask `seat` is a recipient of — its own asks, and the
 * asks it forwarded (S2) — that `seat` itself has not read. Each is read as `by`, the CALLER: the
 * caller's read is stamped when it is a recipient, never `seat`'s on its behalf (S2). With no `by`,
 * nothing is stamped. Every unread ask is returned, stamped or not.
 */
export async function pickupUnread(root: string, seat: string, o: { by?: string; now?: string } = {}): Promise<ReadResult[]> {
  const unread = listAsks(root).filter((a) => a.answer && (readersOf(a).includes(seat) || (a.seat === seat && !a.header.from)) && !hasRead(a, seat));
  unread.sort((a, b) => a.file.localeCompare(b.file));
  const out: ReadResult[] = [];
  for (const a of unread) out.push(await readAsk(root, a.seat, a.header.id!, { by: o.by, now: o.now }));
  return out;
}

/**
 * Stamp `acted` with a one-line summary of what the answer was used for. Only a recipient acts on
 * an answer — the asker, a forwarder, or the addressed seat (M2) — and acting implies the actor's
 * own read.
 */
export async function actedAsk(
  root: string,
  seat: string,
  id: string,
  summary: string,
  o: RelayStanding & { by?: string; now?: string; ruledInChat?: string; relayedFrom?: string; note?: string } = {},
): Promise<void> {
  if (!summary || !summary.trim() || /\n/.test(summary)) throw new AskFormatError("acted needs a non-blank, one-line summary");
  if (!o.by) throw new AskFormatError("acted must name who acted");
  const by = o.by;
  const file = resolveAskPath(root, seat, id);
  await withFileLock(file, () => {
    const text = fs.readFileSync(file, "utf8");
    const ask = parseAskFile(text);
    const ruled = o.ruledInChat?.trim();
    if (o.ruledInChat !== undefined && (!ruled || /\n/.test(o.ruledInChat))) throw new AskFormatError('--ruled-in-chat needs "<who, when>" on one line');
    if (!ask.answer && !ruled) {
      throw new AskFormatError(`${seat}/${id} is not settled; there is nothing to act on. If it was ruled outside the file, record the answer (answer --relayed-from operator) or pass --ruled-in-chat "<who, when>"`);
    }
    const reserved = ask.header["reserved-for"]?.trim();
    const closingReserved = !ask.answer && !!ruled && !!reserved;
    if (closingReserved) {
      // Round 2: a reserved ask is the operator's to rule. Closing it as ruled in chat is a RELAY of
      // that ruling — `--relayed-from operator` and a note — by a seat with standing to relay, never
      // by the asker alone.
      if (o.relayedFrom !== reserved) throw new AskFormatError(`${seat}/${id} is reserved for ${reserved}: closing it as ruled in chat needs --relayed-from ${reserved} and a --note`);
      if (!o.note?.trim()) throw new AskFormatError(`closing a reserved ask as ruled in chat needs a --note saying when and where ${reserved} ruled`);
      assertMayRelay(ask, { answeredBy: reserved, answeredVia: `relay:${by}` }, o);
    }
    const allowed = new Set([...recipientsOf(ask), ask.header.to ?? ""].filter(Boolean));
    if (!closingReserved && !allowed.has(by)) throw new AskFormatError(`${by} is not a recipient of ${seat}/${id} (the asker, a forwarder or the addressed seat); it cannot mark it acted`);
    const now = o.now ?? new Date().toISOString();
    let after = text;
    if (!ask.answer && ruled) {
      // Ruled in chat: closed as `ruled`, with no answer invented in the file. The revision moves, so
      // a draft or an answer still in flight against it is refused as stale.
      if (ask.header.status !== "open") throw new AskFormatError(`${seat}/${id} is ${ask.header.status}; only an open ask is closed as ruled in chat`);
      after = clearDraft(after);
      after = setHeaderField(after, "status", "ruled");
      after = setHeaderField(after, "revision", String(currentRevision(ask) + 1));
    }
    if (ruled) after = setHeaderField(after, "ruledInChat", closingReserved ? `${ruled} — relayed by ${by}: ${o.note!.trim().replace(/\n/g, " ")}` : ruled);
    after = setHeaderField(after, "acted", summary.trim());
    after = setHeaderField(after, "actedAt", now);
    after = setHeaderField(after, "actedBy", by);
    if (ask.answer && readersOf(ask).includes(by) && !hasRead(ask, by)) after = stampRead(after, parseAskFile(after), by, now);
    atomicWrite(file, after);
  });
}

// ── forwarding (COORDHOP S4) ──────────────────────────────

const SEAT_RE = /^[A-Za-z0-9][A-Za-z0-9_.:@-]*$/;

/**
 * Move an open ask's `to:` one rung. The current holder (the `to:` seat) may move it; so may the
 * holder's own parent, when the holder is silent (the operator's ruling) — the caller proves that
 * with `manages`, its FLEET_MANAGES. The asker may re-ping the holder but never moves its own ask.
 * Each hop is appended to `forwards:` (a parent's move is recorded as holder→parent, then onward,
 * so the parent hears the answer too), and the revision moves, so a draft saved before the move is
 * stale (S4).
 */
export async function forwardAsk(root: string, seat: string, id: string, o: { to: string; by: string; manages?: string[]; now?: string }): Promise<void> {
  if (!o.by) throw new AskFormatError("forward must name who is forwarding");
  const file = resolveAskPath(root, seat, id);
  await withFileLock(file, () => {
    const text = fs.readFileSync(file, "utf8");
    atomicWrite(file, forwardedText(text, parseAskFile(text), `${seat}/${id}`, { ...o, at: o.now ?? new Date().toISOString() }));
  });
}

/**
 * The move itself, shared by `forward` and by a decline passed up from a reserved ask: the standing
 * check (the holder, or the holder's parent), the hops appended to `forwards:` (with the decline's
 * reason on the last one, when there is one), the new `to:` and the revision moved.
 */
function forwardedText(text: string, ask: ParsedAsk, ref: string, o: { to: string; by: string; manages?: string[]; at: string; reason?: string }): string {
  if (!o.to || !SEAT_RE.test(o.to) || o.to.includes("..")) throw new AskFormatError(`invalid recipient: ${o.to}`);
  if (ask.header.status !== "open") throw new AskFormatError(`${ref} is ${ask.header.status}; only an open ask moves`);
  const holder = ask.header.to ?? "";
  if (o.to === holder) throw new AskFormatError(`${ref} is already with ${holder}`);
  if (o.to === ask.header.from) throw new AskFormatError(`${ref} cannot be forwarded to its own asker (${o.to})`);
  const hops: Hop[] = forwardChain(ask.header);
  if (o.by === holder) hops.push({ from: holder, to: o.to, at: o.at });
  else if (o.by === ask.header.from) {
    throw new AskFormatError(`only the holder (${holder}) or its parent may move this ask; the asker re-pings the holder instead`);
  } else if (managesSeat(o.manages ?? [], holder)) {
    hops.push({ from: holder, to: o.by, at: o.at });
    if (o.to !== o.by) hops.push({ from: o.by, to: o.to, at: o.at });
  } else {
    throw new AskFormatError(`only the holder (${holder}) or its parent may move this ask; ${o.by} is neither`);
  }
  if (o.reason) hops[hops.length - 1].reason = o.reason;
  let after = setHeaderField(text, "to", o.to);
  after = setHeaderField(after, "forwards", hops.map(hopText).join(" ; "));
  return setHeaderField(after, "revision", String(currentRevision(ask) + 1));
}

// ── revising an open ask (the asker only) ─────────────────

/** Header fields a revise may change: the card, never identity or state. */
const FIXED_ON_REVISE = new Set(["id", "from", "to", "status", "revision", "created"]);

export type ReviseResult = { file: string; revision: number; changed: string[]; pushes: { seat: string; delivery: DeliveryResult }[] };

/**
 * Revise an open ask in place: the asker (`from:`) only. The id, `from:`, `to:`, the forward chain
 * and `created:` stay; the given card fields and (when given) the body replace the old ones; the
 * revision moves and `revisions:` records what changed. A draft saved against the old revision is
 * kept in the file but is now stale — the batch's revision and body checks refuse it (S4) — and an
 * answerer still holding the old revision is refused by the answer's compare-and-swap. The holder
 * and every forwarder hear one notice; the asker, who just wrote it, hears nothing.
 */
export async function reviseAsk(
  root: string,
  seat: string,
  id: string,
  fields: Record<string, string | undefined>,
  body: string | undefined,
  o: DeliverOptions & { by: string; push?: typeof pushToSeat; now?: string },
): Promise<ReviseResult> {
  const file = resolveAskPath(root, seat, id);
  if (!o?.by) throw new AskFormatError("revise must name who is revising");
  if (body !== undefined && RECORD_FENCE_RE.test(body)) {
    throw new AskFormatError("the body holds a ```json answer or ```json draft block: those are records the store writes, never part of a question");
  }
  for (const k of Object.keys(fields)) {
    if (fields[k] === undefined) continue;
    if (FIXED_ON_REVISE.has(k) || (STAMP_FIELDS as readonly string[]).includes(k)) throw new AskFormatError(`${k} is not revisable: a revise changes the card and the body only`);
    if (/\n/.test(fields[k]!)) throw new AskFormatError(`header value for ${k} must be one line`);
  }
  const at = o.now ?? new Date().toISOString();
  const res = await withFileLock(file, () => {
    const text = fs.readFileSync(file, "utf8");
    const ask = parseAskFile(text);
    if (o.by !== ask.header.from) throw new AskFormatError(`only the asker (${ask.header.from ?? "?"}) revises ${seat}/${id}; ${o.by} may answer, forward or decline it instead`);
    if (ask.header.status !== "open") throw new AskFormatError(`${seat}/${id} is ${ask.header.status}; only an open ask is revised (ask a new one)`);
    const changed: string[] = [];
    let after = text;
    for (const [k, v] of Object.entries(fields)) {
      if (v === undefined || (ask.header[k] ?? "") === v) continue;
      after = setHeaderField(after, k, v);
      changed.push(k);
    }
    if (body !== undefined) {
      const oldBody = bodyDigest(text);
      const head = after.slice(0, after.indexOf("\n---", 3) + 4);
      const draftFence = trailingDraftFence(text);
      after = `${head}\n\n${body.replace(/\n*$/, "\n")}${draftFence ? `\n${draftFence.replace(/^\n+/, "")}` : ""}`;
      const reparsed = parseAskFile(after);
      if (reparsed.questions.length === 0) throw new AskFormatError('body holds no question: write at least one "## Choose one: …" heading');
      assertCodes(reparsed);
      if (bodyDigest(after) !== oldBody) changed.push("body");
    }
    if (changed.length === 0) throw new AskFormatError(`nothing to revise: ${seat}/${id} already says that`);
    const revision = currentRevision(ask) + 1;
    after = setHeaderField(after, "revision", String(revision));
    const history = (ask.header.revisions ?? "").trim();
    after = setHeaderField(after, "revisions", `${history ? `${history} ; ` : ""}${revision}@${at}:${changed.join(",")}`);
    atomicWrite(file, after);
    return { parsed: parseAskFile(after), revision, changed };
  });
  // One notice to the seats holding or passing the ask on; never to the asker, nor to `operator`,
  // which is not a seat (the app redraws from the file).
  const seats = [...new Set([res.parsed.header.to ?? "", ...forwardChain(res.parsed.header).flatMap((h) => [h.from, h.to])])].filter(
    (s) => s && s !== o.by && s !== "operator",
  );
  const push = o.push ?? pushToSeat;
  const msg = [
    `[ask-revised] from ${o.by} via ask-app: ${seat}/${id} is now revision ${res.revision} (changed: ${res.changed.join(", ")})`,
    `An answer or draft made against an earlier revision is stale and will be refused. \`engine ask list\` shows it; the file is the record:`,
    file,
  ].join("\n");
  const pushes: ReviseResult["pushes"] = [];
  for (const s of seats) pushes.push({ seat: s, delivery: await safePush(push, s, msg, o) });
  return { file, revision: res.revision, changed: res.changed, pushes };
}

// ── superseding (one ask replaces another) ────────────────

export type AskRef = { seat: string; id: string };
export type SupersedeResult = { file: string; revision: number; pushes: { seat: string; delivery: DeliveryResult }[] };

/**
 * Replace the open ask `old` with the ask `by`, so the two can never both be answered (a re-filed
 * copy and its original were, and a ticket flip-flopped — IDE-261). Prefer `revise`; supersede is
 * for when the replacement had to be a new ask.
 *
 * - Who: the old ask's asker (`from:`), a manager of that asker (`manages`, its FLEET_MANAGES —
 *   forward's standing rule), or the operator. Not the holder: it changes what the asker asked. A
 *   reserved ask may be superseded, since it settles no decision.
 * - The old ask: `status: superseded`, `superseded-by: <seat>/<id>`, `superseded-at`,
 *   `superseded-actor`; its revision moves and `revisions:` records it (revise's rule), so an answer
 *   or draft in flight against it is stale, and any saved draft is dropped. The new ask: `supersedes:
 *   <seat>/<id>` only — its question is unchanged, so its revision does not move.
 * - Refused: either ask missing, an ask superseding itself, an old ask that is not open (answered,
 *   declined or ruled asks are history; a superseded one names what replaced it), or a replacement
 *   that is itself superseded.
 * - The holder and forwarders of the old ask hear one `[ask-superseded]` notice naming the new ask.
 */
export async function supersedeAsk(
  root: string,
  old: AskRef,
  by: AskRef,
  o: DeliverOptions & { by: string; manages?: string[]; push?: typeof pushToSeat; now?: string },
): Promise<SupersedeResult> {
  if (!o?.by) throw new AskFormatError("supersede must name who is superseding");
  const oldRef = `${old.seat}/${old.id}`;
  const newRef = `${by.seat}/${by.id}`;
  const oldFile = resolveAskPath(root, old.seat, old.id);
  const newFile = resolveAskPath(root, by.seat, by.id);
  if (oldFile === newFile) throw new AskFormatError(`${oldRef} cannot supersede itself: name the new ask that replaces it`);
  for (const [f, r] of [[oldFile, oldRef], [newFile, newRef]]) if (!fs.existsSync(f)) throw new AskFormatError(`no ask ${r}`);
  const at = o.now ?? new Date().toISOString();
  // Both files are locked, always in the same order, so two supersedes never wait on each other.
  const [first, second] = [oldFile, newFile].sort();
  const res = await withFileLock(first, () =>
    withFileLock(second, () => {
      const oldText = fs.readFileSync(oldFile, "utf8");
      const newText = fs.readFileSync(newFile, "utf8");
      const ask = parseAskFile(oldText);
      const repl = parseAskFile(newText);
      const asker = ask.header.from ?? "";
      if (o.by !== "operator" && o.by !== asker && !(asker && managesSeat(o.manages ?? [], asker))) {
        throw new AskFormatError(`only the asker (${asker || "?"}), its manager or the operator supersedes ${oldRef}; ${o.by} is none of them`);
      }
      const status = ask.header.status ?? "open";
      if (status === "superseded") throw new AskFormatError(`${oldRef} is already superseded by ${ask.header["superseded-by"] || "another ask"}`);
      if (["answered", "declined", "ruled"].includes(status)) {
        throw new AskFormatError(`${oldRef} is ${status}: answered asks are history and are not superseded; file a new one instead`);
      }
      if (status !== "open") throw new AskFormatError(`${oldRef} is ${status}; only an open ask is superseded`);
      if (repl.header.status === "superseded") {
        throw new AskFormatError(`${newRef} is itself superseded (by ${repl.header["superseded-by"] || "another ask"}); supersede ${oldRef} by the live ask`);
      }
      // N2 (round 2): the replacement must still carry the decision — open, or answered by the
      // operator (the IDE-261 clean-up). A declined or ruled one, or one a seat answered, is not.
      const rs = repl.header.status ?? "open";
      if (rs === "declined" || rs === "ruled") throw new AskFormatError(`${newRef} is ${rs}: nothing is left to answer there; supersede ${oldRef} by an open ask`);
      if (rs === "answered" && repl.answer?.answeredBy !== "operator") {
        throw new AskFormatError(`${newRef} was answered by ${repl.answer?.answeredBy || "an unnamed answerer"}, not the operator; only an open ask, or one the operator answered, replaces ${oldRef}`);
      }
      if (rs !== "open" && rs !== "answered") throw new AskFormatError(`${newRef} is ${rs}; only an open ask, or one the operator answered, replaces ${oldRef}`);
      const revision = currentRevision(ask) + 1;
      let after = clearDraft(oldText);
      after = setHeaderField(after, "status", "superseded");
      after = setHeaderField(after, "superseded-by", newRef);
      after = setHeaderField(after, "superseded-at", at);
      after = setHeaderField(after, "superseded-actor", o.by);
      after = setHeaderField(after, "revision", String(revision));
      const history = (ask.header.revisions ?? "").trim();
      after = setHeaderField(after, "revisions", `${history ? `${history} ; ` : ""}${revision}@${at}:superseded`);
      const links = (repl.header.supersedes ?? "").split(/\s*;\s*/).filter(Boolean);
      const newAfter = setHeaderField(newText, "supersedes", [...links.filter((l) => l !== oldRef), oldRef].join(" ; "));
      atomicWrite(newFile, newAfter);
      atomicWrite(oldFile, after);
      return { parsed: parseAskFile(after), revision };
    }),
  );
  // S4 (round 2): the asker hears it too when someone else retired its ask — the replacement's answer
  // goes to the replacement's asker, so otherwise it would wait on a dead ask.
  const seats = [...new Set([res.parsed.header.to ?? "", ...forwardChain(res.parsed.header).flatMap((h) => [h.from, h.to]), res.parsed.header.from ?? ""])].filter(
    (s) => s && s !== o.by && s !== "operator",
  );
  const push = o.push ?? pushToSeat;
  const msg = [
    `[ask-superseded] from ${o.by} via ask-app: ${oldRef} is superseded by ${newRef}`,
    `Do not answer ${oldRef}: an answer or draft on it is refused. Answer ${newRef} instead. The file is the record:`,
    oldFile,
  ].join("\n");
  const pushes: SupersedeResult["pushes"] = [];
  for (const s of seats) pushes.push({ seat: s, delivery: await safePush(push, s, msg, o) });
  return { file: oldFile, revision: res.revision, pushes };
}

// ── renaming a seat (a fleet rename) ──────────────────────

export type RenameSeatChange = SeatChange & { /** `<seat>/<id>.md` under the root, as the file sat BEFORE the move. */ file: string };
export type RenameSeatResult = {
  dryRun: boolean;
  old: string;
  neu: string;
  /** `move`: the folder is renamed whole; `merge`: its asks join an existing folder; `none`: the old seat filed no asks. */
  folder: { from: string; to: string; mode: "move" | "merge" | "none"; ids: string[] };
  changes: RenameSeatChange[];
  /** Files whose text changes. */
  files: string[];
};

/**
 * `engine ask rename-seat <old> <new>`: the fleet renamed a seat, so its asks and every reference to
 * it follow.
 *
 * 1. The folder `<root>/<old>/` becomes `<root>/<new>/`: renamed whole, or, when `<new>/` exists,
 *    merged file by file. Refused — before anything is written — when `<new>/` already holds an
 *    entry of the same name (an ask of the same id), or when a write is in flight in `<old>/`.
 * 2. Every ask file under the root, not only the moved ones, has its references rewritten
 *    (rename-seat.ts says which fields, and that only whole names match).
 * 3. Each file is rewritten under its lock, atomically (temp file, then rename), with its revision
 *    unchanged (a rename is not a revision) and its mtime restored, so the app's newest-first order
 *    and every ask's age stay as they were.
 * With `dryRun`, the same plan is computed and returned, and nothing is written.
 */
export async function renameSeat(root: string, old: string, neu: string, o: { dryRun?: boolean } = {}): Promise<RenameSeatResult> {
  for (const s of [old, neu]) if (!SAFE.test(s) || s.includes("..")) throw new AskFormatError(`invalid seat: ${s}`);
  if (old === neu) throw new AskFormatError(`${old} and ${neu} are the same seat: nothing to rename`);
  if (old === "operator" || neu === "operator") throw new AskFormatError("the operator is not a seat; it is never renamed");
  const fromDir = path.join(root, old);
  const toDir = path.join(root, neu);
  const has = (d: string) => fs.existsSync(d) && fs.statSync(d).isDirectory();
  const entries = has(fromDir) ? fs.readdirSync(fromDir) : [];
  const ids = entries.filter((f) => f.endsWith(".md") && !f.startsWith(".")).map((f) => f.slice(0, -3)).sort();
  const mode: RenameSeatResult["folder"]["mode"] = !has(fromDir) ? "none" : has(toDir) ? "merge" : "move";
  const assertFolder = () => {
    if (!has(fromDir)) return;
    const now = fs.readdirSync(fromDir);
    const busy = now.filter((f) => f.endsWith(".lock") || f.endsWith(".tmp"));
    if (busy.length) throw new AskFormatError(`a write is in flight in ${old}/ (${busy.join(", ")}); try again in a moment`);
    if (!has(toDir)) return;
    const clash = now.filter((f) => fs.existsSync(path.join(toDir, f)));
    if (clash.length) {
      throw new AskFormatError(`refusing to rename ${old} → ${neu}: ${clash.map((f) => `${neu}/${f.replace(/\.md$/, "")}`).join(", ")} already exist${clash.length === 1 ? "s" : ""}; nothing was changed`);
    }
  };
  assertFolder();

  // The plan: every ask file under the root, as it sits now.
  const plan: { file: string; rel: string; changes: SeatChange[] }[] = [];
  const seats = fs.existsSync(root) ? fs.readdirSync(root, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name).sort() : [];
  for (const seat of seats) {
    for (const f of fs.readdirSync(path.join(root, seat)).sort()) {
      if (!f.endsWith(".md") || f.startsWith(".")) continue;
      const file = path.join(root, seat, f);
      const r = rewriteSeatRefs(fs.readFileSync(file, "utf8"), old, neu);
      if (r.changes.length) plan.push({ file, rel: `${seat}/${f}`, changes: r.changes });
    }
  }
  const result: RenameSeatResult = {
    dryRun: !!o.dryRun,
    old,
    neu,
    folder: { from: `${old}/`, to: `${neu}/`, mode, ids },
    changes: plan.flatMap((p) => p.changes.map((c) => ({ file: p.rel, ...c }))),
    files: plan.map((p) => p.rel),
  };
  if (o.dryRun) return result;

  // The rewrite, each file under its lock and re-read there, so a write that landed since the plan is kept.
  result.changes = [];
  for (const p of plan) {
    await withFileLock(p.file, () => {
      const st = fs.statSync(p.file);
      const r = rewriteSeatRefs(fs.readFileSync(p.file, "utf8"), old, neu);
      if (!r.changes.length) return;
      atomicWrite(p.file, r.text);
      // Seconds as a float, not a Date: a Date keeps whole milliseconds, and its round trip drifted up to 2 ms.
      fs.utimesSync(p.file, st.atimeMs / 1000, st.mtimeMs / 1000);
      result.changes.push(...r.changes.map((c) => ({ file: p.rel, ...c })));
    });
  }
  // Then the folder: whole when it can be, else ask by ask (a rename keeps each file's mtime).
  if (mode !== "none") {
    assertFolder();
    if (!has(toDir)) fs.renameSync(fromDir, toDir);
    else {
      for (const f of fs.readdirSync(fromDir)) fs.renameSync(path.join(fromDir, f), path.join(toDir, f));
      fs.rmdirSync(fromDir);
    }
  }
  return result;
}
