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
  assertLive,
  assertNotOverOperator,
  answerLines,
  noteLine,
  overruledNow,
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
  GRANT_CLASSES,
  isOperatorName,
  readsOf,
  relayerOf,
  replacedSummary,
  trailingDraftFence,
  removeHeaderField,
  recipientsOf,
  hasSeat,
  seatEq,
  RECORD_FENCE_RE,
  assertFenceLanguages,
  STAMP_FIELDS,
  setHeaderField,
  StaleRevisionError,
  validateAnswer,
  writeAnswer,
  writeDecline,
  writeDraft,
  writeFollowup,
  markFollowups,
  followupEntries,
  allCodes,
  appendPanelEntry,
  panelFence,
  type PanelAttachment,
  type PanelProposal,
  type PanelRead,
  questionKey,
  type AskAnswer,
  type AskFollowup,
  type FollowupInput,
  type ParsedAsk,
} from "./format.ts";
import { leftRefs, rewriteSeatRefs, type LeftRef, type SeatChange } from "./rename-seat.ts";

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
    throw new AskFormatError("the body holds a ```json answer, ```json draft, ```json history, ```json followup or ```json panels block: those are records the store writes, never part of a question (indent it or use another fence language to quote one)");
  }
  // FENCELANG: every fence an author writes carries a language, so the browser can highlight it.
  assertFenceLanguages(body);
  for (const k of STAMP_FIELDS) {
    if (fields[k] !== undefined) throw new AskFormatError(`${k} is written by the store as the ask moves; a new ask does not set it`);
  }
  if (fields.from === "operator") throw new AskFormatError("an ask comes from a seat; the operator is not one (it answers asks, or asks in chat)");
  if (fields.to === fields.from || seatEq(fields.to, fields.from)) throw new AskFormatError(`an ask is a question to somebody else: ${fields.from} cannot address an ask to itself`);
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
export function deliveryMessage(seat: string, id: string, file: string, answer: AskAnswer, lines: string[] = [], o: { replaced?: string; resent?: boolean; overruled?: string } = {}): string {
  const verb = answer.declined ? "declined" : "answered";
  // SHOULD-3 (round 2): the grant class rides the first line, so the worker sees it before acting.
  const grant = answer.grantClass ? ` · grant ${answer.grantClass}` : "";
  const note = noteLine(answer);
  // IDE-304: a second answer says it CHANGED and what it replaced; a re-push says it is one.
  // IDE-339: when a different answerer replaced it, it says it OVERRULED that answerer.
  const head = o.replaced && o.overruled
    ? `[ask-overruled] from ${answer.answeredBy || "unknown"} via ask-app: ${seat}/${id} is ${verb} again; this answer overrules ${o.overruled}'s`
    : o.replaced
    ? `[ask-answer-changed] from ${answer.answeredBy || "unknown"} via ask-app: ${seat}/${id} is ${verb} again; this answer replaces the earlier one`
    : `[ask-answer] from ${answer.answeredBy || "unknown"} via ask-app: ${seat}/${id} is ${verb}`;
  return [
    `${head}${grant}`,
    ...(o.replaced ? [`Replaced: ${o.replaced}`] : []),
    ...(o.resent ? ["Re-sent: an earlier push of this answer may not have arrived; nothing changed since."] : []),
    ...lines.map((l) => `- ${l}`),
    // ASKNOTE (round 2): the note is set apart and marked, never folded into a choice line.
    ...(note ? [`  ${note}`] : []),
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
      // S1 (round 2): the seat's folder is gone — say where it went, when a rename moved it.
      if (isENOENT(e)) throw renamedError(file) ?? e;
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
  let out: T;
  try {
    out = await fn();
  } catch (e) {
    releaseLock(file, lock);
    throw isENOENT(e) ? (renamedError(file) ?? e) : e;
  }
  releaseLock(file, lock);
  return out;
}

const isENOENT = (e: unknown) => (e as NodeJS.ErrnoException | undefined)?.code === "ENOENT";

/**
 * S1 (round 2): release a lock whose seat folder may have been moved by `rename-seat` while it was
 * held. The folder moves whole into staging, and this holder's lock and any temp file of its own
 * move with it. What it wrote before the move moved too, so a release that finds the folder gone is
 * not a failure: the holder clears its own lock and temp file in staging (rename-seat waits on them),
 * and the caller is told only if a later write of the same call fails.
 */
function releaseLock(file: string, lock: string) {
  try {
    fs.rmdirSync(lock);
  } catch (e) {
    const moved = isENOENT(e) ? renamedError(file) : undefined;
    if (!moved) throw e;
    clearOwnInStaging(file, moved.seat);
  }
}

function clearOwnInStaging(file: string, seat: string) {
  const stage = stagingOf(path.dirname(path.dirname(file)), seat);
  const base = path.basename(file);
  for (const [p, rm] of [[path.join(stage, `${base}.lock`), fs.rmdirSync], [path.join(stage, `.${base}.${process.pid}.tmp`), fs.unlinkSync]] as const) {
    try {
      rm(p);
    } catch {
      // not there: rename-seat cleared it (a stale lock), or this call never made it
    }
  }
}

/** S1 (round 2): a write that hit a seat whose folder rename-seat moved. */
export class SeatRenamedError extends AskFormatError {
  readonly seat: string;
  readonly to: string;
  readonly id: string;
  constructor(seat: string, to: string, id: string) {
    super(`seat ${seat} was renamed to ${to} (engine ask rename-seat) while this ran, so ${seat}/${id} is now ${to}/${id}; your answer may have landed: check \`engine ask read ${to}/${id}\` before trying again`);
    this.seat = seat;
    this.to = to;
    this.id = id;
  }
}

/**
 * How a rename is detected (S1): the ask's seat folder `<root>/<seat>/` does not exist, and the
 * ledger file `<root>/.rename-seat/<seat>`, which rename-seat writes before it moves the folder,
 * names the new seat. Anything else is an ordinary ENOENT and is left as it was.
 */
function renamedError(file: string): SeatRenamedError | undefined {
  const seatDir = path.dirname(file);
  if (fs.existsSync(seatDir)) return undefined;
  const seat = path.basename(seatDir);
  const to = renamedTo(path.dirname(seatDir), seat);
  return to ? new SeatRenamedError(seat, to, path.basename(file).replace(/\.md(\.lock)?$/, "")) : undefined;
}

/** `<root>/.rename-seat/`: rename-seat's ledger and staging, one level below a dot folder, so listAsks never reads them. */
const RENAME_DIR = ".rename-seat";
const ledgerOf = (root: string, seat: string) => path.join(root, RENAME_DIR, seat);
const stagingOf = (root: string, seat: string) => path.join(root, RENAME_DIR, `${seat}.staging`);
const readLedger = (root: string, seat: string): string | undefined => {
  try {
    return fs.readFileSync(ledgerOf(root, seat), "utf8").split("\n")[0].trim() || undefined;
  } catch {
    return undefined;
  }
};

/** Where a renamed seat went, following the ledger (a seat renamed twice) until a seat whose folder exists. */
export function renamedTo(root: string, seat: string): string | undefined {
  const seen = new Set([seat]);
  let s = seat;
  for (let i = 0; i < 16; i++) {
    const next = readLedger(root, s);
    if (!next || seen.has(next)) break;
    seen.add(next);
    s = next;
    if (fs.existsSync(path.join(root, s))) break;
  }
  return s === seat ? undefined : s;
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
      /** The answerer's FLEET_MANAGES: a grant class is accepted only when it lists the asker (MUST-1). */
      answererManages?: string[];
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
    assertGrant(ask, input, opts.answererManages);
    if (!isPassUp(ask, input)) return undefined;
    assertLive(ask);
    assertNotOverOperator(ask, input.answeredBy);
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
    assertNotOverOperator(parseAskFile(before), input.answeredBy);
    assertGrant(parseAskFile(before), input, opts.answererManages);
    assertHistoryReadable(parseAskFile(before), file);
    const replaced = replacedSummary(parseAskFile(before));
    const grant = input.grantClass ? { grantClass: input.grantClass } : {};
    let text: string;
    if (input.declined) {
      text = writeDecline(before, { reason: input.reason ?? "", answeredBy: input.answeredBy, ...via, answeredAt: at, ...(input.note ? { note: input.note } : {}), ...grant }, opts.expectedRevision);
    } else {
      validateAnswer(parseAskFile(before), input.answers);
      text = writeAnswer(before, { answers: input.answers, ...(input.note ? { note: input.note } : {}), answeredBy: input.answeredBy, ...via, answeredAt: at, ...grant }, opts.expectedRevision);
    }
    text = setHeaderField(setHeaderField(text, "delivery", "pending"), "deliveryWriter", writerStamp());
    atomicWrite(file, text);
    const parsed = parseAskFile(text);
    return { written: currentRevision(parsed), record: parsed.answer!, parsed, replaced };
  });
  const delivery = await pushAnswer(parsed, seat, file, record, opts, { replaced, overruled: overruledOf(parsed, replaced) });
  try {
    await stampDelivery(file, written, delivery);
  } catch (e) {
    if (!(e instanceof SeatRenamedError)) throw e;
    // S1 (round 2): the answer landed and was pushed, then rename-seat moved the seat's folder. The
    // answer is not a failure: the stamp follows the ask. If the move is still under way, the stamp
    // stays `pending` and a later send or read re-pushes it (S3), which is safe to repeat.
    const moved = resolveAskPath(root, e.to, id);
    try {
      await stampDelivery(moved, written, delivery);
    } catch {
      // left pending, as above
    }
    return { file: moved, revision: written, delivery };
  }
  return { file, revision: written, delivery };
}

/** S4: the asker and every seat that held and forwarded the ask hear the answer, with its lines. */
async function pushAnswer(parsed: ParsedAsk, seat: string, file: string, record: AskAnswer, opts: DeliverOptions & { push?: typeof pushToSeat }, how: { replaced?: string; resent?: boolean; overruled?: string } = {}): Promise<DeliveryResult> {
  const push = opts.push ?? pushToSeat;
  const id = parsed.header.id ?? "";
  const msg = deliveryMessage(seat, id, file, record, answerLines(parsed, seat), how);
  const results: Record<string, DeliveryResult> = {};
  for (const s of pushTargets(parsed, seat, how.overruled)) {
    results[s] = isSelf(s, record) ? SELF : await safePush(push, s, msg, opts);
  }
  return combine(results);
}

/**
 * The seats an answer is pushed to: the asker and every forwarder (the asker's seat when none is
 * named). SHOULD-2 (round 2): an overrule is pushed to the seat it overruled as well — the one
 * whose ruling was reversed — unless that is the operator, who is not a seat.
 */
function pushTargets(parsed: ParsedAsk, seat: string, overruled?: string): string[] {
  const seats = recipientsOf(parsed);
  const out = seats.length ? seats : [seat];
  const prior = overruled?.trim();
  return prior && !isOperatorName(prior) && !out.includes(prior) ? [...out, prior] : out;
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
  // S3 (round 2): folded, so a case variant of the asker is never an answerer either.
  return [...out].filter((s) => !seatEq(s, ask.header.from));
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
  if (seatEq(relayer, ask.header.from)) throw new AskFormatError(`the asker (${relayer}) never relays an answer to its own ask ${id}; the operator answers it, or a seat in its chain relays`);
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

/**
 * IDE-339: whom this settle overruled, read only beside a `replaced:` one. Round 2: read from the
 * history (`overruledNow`), not the `overruled:` header, which keeps its trail across a self-change.
 */
const overruledOf = (ask: ParsedAsk, replaced: string | undefined) => (replaced ? overruledNow(ask) : undefined);

/** NIT-1 (round 2): a settle rewrites the history fence, so one that cannot be read whole is refused, naming the file. */
function assertHistoryReadable(ask: ParsedAsk, file: string) {
  if (ask.historyError) throw new AskFormatError(`${ask.historyError} in ${file}: fix or remove it by hand before this ask is answered again`);
}

/**
 * IDE-339: a grant class is A–D, written by the answering manager (`engine ask answer --grant`): never
 * on the operator's answer (relayed or not), and never on an ask reserved for someone. Round 2
 * (MUST-1): only by a MANAGER of the asker — the answerer's FLEET_MANAGES must list the asker's seat
 * or label — so a peer addressee cannot record an authority it does not hold.
 */
function assertGrant(ask: ParsedAsk, a: AskAnswer, answererManages: string[] = []) {
  if (a.grantClass === undefined) return;
  const id = ask.header.id ?? "";
  if (!(GRANT_CLASSES as readonly unknown[]).includes(a.grantClass)) throw new AskFormatError(`a grant class is A, B, C or D, not ${String(a.grantClass)}`);
  if (isOperatorName(a.answeredBy)) throw new AskFormatError(`the operator's answer to ${id} carries no grant class: a grant class is the answering manager's`);
  if (reservedOf(ask)) throw new AskFormatError(`ask ${id} is reserved for ${reservedOf(ask)}: a reserved ask's answer carries no grant class`);
  const asker = ask.header.from ?? "";
  if (!asker || !managesSeat(answererManages, asker)) {
    throw new AskFormatError(`${a.answeredBy || "an unnamed answerer"} is not a manager of ${asker || "the asker"}: only the asker's manager (its FLEET_MANAGES lists the asker) gives a grant class on ${id}`);
  }
}

/** R4 and M3: an ask marked `reserved-for: operator` is answered by the operator; any ask only by its answerers. */
function assertMayAnswer(ask: ParsedAsk, a: AskAnswer, standing?: RelayStanding) {
  // First: a superseded ask is refused whoever answers, pointing at the ask that replaced it.
  assertLive(ask);
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
    assertLive(ask);
    if (input.grantClass !== undefined) throw new AskFormatError("a grant class is never drafted: it is written with `engine ask answer --grant`");
    // S3 (round 2): a seat's decline of a reserved ask is a pass-up, which moves the ask at once;
    // it is never held as a draft.
    if (isPassUp(ask, input)) {
      throw new AskFormatError(`${seat}/${id} is reserved for ${reservedOf(ask)}: a seat's decline of it is not drafted; use \`engine ask answer --decline\` to pass it up`);
    }
    assertMayAnswer(ask, input, standing);
    assertNotOverOperator(ask, input.answeredBy);
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
export function batchMessage(seat: string, answeredBy: string, items: { ref: string; file: string; lines: string[]; replaced?: string; overruled?: string; note?: string }[]): string {
  const n = items.length;
  return [
    `[ask-batch] from ${answeredBy || "unknown"} via ask-app: ${n} answer${n === 1 ? "" : "s"} for ${seat}`,
    // IDE-304: an item that replaces an earlier answer says so, and what it replaced.
    // IDE-339: one that a different answerer gave is overruled, and says whose it was.
    // ASKFOLLOWUP: reachable from sendBatch now that the operator may draft over a seat's answer
    // (writeDraft), so a batch can change answerer (NIT-4 of round 2 kept it for this).
    ...items.flatMap((it) => [
      ...(it.replaced && it.overruled
        ? [`- [ask-overruled] ${it.ref} overrules ${it.overruled}; replaces ${it.replaced}`]
        : it.replaced
          ? [`- [ask-answer-changed] ${it.ref} replaces ${it.replaced}`]
          : []),
      ...it.lines.map((l) => `- ${l}`),
      // ASKNOTE (round 2): the item's note, marked and set apart under its lines.
      ...(it.note ? [`  ${it.note}`] : []),
    ]),
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
  const bySeat = new Map<string, { ref: string; file: string; lines: string[]; written: number; replaced?: string; overruled?: string; note?: string }[]>();
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
        assertLive(ask);
        // OVEROP: a seat's draft over the operator's answer is not honoured (the parser hides it); say why.
        assertNotOverOperator(ask, d?.answeredBy ?? by);
        if (!d) throw new AskFormatError(`${ref} has no draft to send`);
        if (draftAuthor(d) !== by) throw new AskFormatError(`${ref}'s draft was saved by ${draftAuthor(d) || "an unnamed answerer"}; only its author sends it`);
        assertMayAnswer(ask, d, opts);
        assertHistoryReadable(ask, file);
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
      const overruled = overruledOf(settled, settled.replaced);
      const note = noteLine(settled.answer);
      const item = { ref, file, lines: answerLines(settled, seat), written, ...(settled.replaced ? { replaced: settled.replaced } : {}), ...(overruled ? { overruled } : {}), ...(note ? { note } : {}) };
      for (const s of pushTargets(settled, seat, overruled)) {
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
    if (!o.by || !hasSeat(recipientsOf(ask), o.by)) return false;
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
    const replaced = claimed.header.replaced?.trim() || undefined;
    const delivery = await pushAnswer(claimed, a.seat, a.file, claimed.answer, opts, { replaced, overruled: overruledOf(claimed, replaced), resent: true });
    await stampDelivery(a.file, currentRevision(claimed), delivery);
    out.push({ ref: `${a.seat}/${claimed.header.id ?? ""}`, delivery });
  }
  return out;
}

// ── read and acted ────────────────────────────────────────

export type ReadResult = { ref: string; file: string; ask: ParsedAsk; lines: string[]; stamped: boolean; why?: string };

/** Add `by`'s own read to the text: its `reads:` entry, and `readAt`/`readBy` when `by` is the asker (M2). */
function stampRead(text: string, ask: ParsedAsk, by: string, at: string): string {
  const reads = readsOf(ask.header).filter((r) => !seatEq(r.seat, by));
  reads.push({ seat: by, at });
  let after = setHeaderField(text, "reads", reads.map((r) => `${r.seat}@${r.at}`).join(" ; "));
  if (seatEq(by, ask.header.from)) {
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
    if (!o.by || !hasSeat(readersOf(ask), o.by)) return { ...base, stamped: false, why: `${o.by || "an unnamed reader"} is not a recipient of this answer` };
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
  const unread = listAsks(root).filter((a) => a.answer && (hasSeat(readersOf(a), seat) || (seatEq(a.seat, seat) && !a.header.from)) && !hasRead(a, seat));
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
    const allowed = [...recipientsOf(ask), ask.header.to ?? ""].filter(Boolean);
    if (!closingReserved && !hasSeat(allowed, by)) throw new AskFormatError(`${by} is not a recipient of ${seat}/${id} (the asker, a forwarder or the addressed seat); it cannot mark it acted`);
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
    if (ask.answer && hasSeat(readersOf(ask), by) && !hasRead(ask, by)) after = stampRead(after, parseAskFile(after), by, now);
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
  if (seatEq(o.to, holder)) throw new AskFormatError(`${ref} is already with ${holder}`);
  if (seatEq(o.to, ask.header.from)) throw new AskFormatError(`${ref} cannot be forwarded to its own asker (${o.to})`);
  const hops: Hop[] = forwardChain(ask.header);
  if (seatEq(o.by, holder)) hops.push({ from: holder, to: o.to, at: o.at });
  else if (seatEq(o.by, ask.header.from)) {
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

// ── follow-ups (ASKFOLLOWUP) ──────────────────────────────

/**
 * The push a follow-up wakes the asker with: who, on which ask and fork (and that fork's question),
 * the text, then the kind, the ask's title, the sender's unsent picks, the file and how to reply.
 */
export function followupMessage(seat: string, id: string, file: string, ask: ParsedAsk, f: AskFollowup): string {
  const qi = f.fork === undefined ? -1 : ask.questions.findIndex((q, i) => questionKey(q, i) === f.fork);
  const fork = qi >= 0 ? ` (fork ${f.fork}: "${ask.questions[qi].title}")` : "";
  const picks = Object.entries(f.picks ?? {}).map(([k, v]) => `${k} ${Array.isArray(v) ? v.join("+") : String(v)}`).join(", ");
  return [
    `[ask-followup] from ${f.by} on ${seat}/${id}${fork}: ${f.text.replace(/\n/g, "\n  ")}`,
    f.kind === "first" ? "kind: first — do this first, then revise the ask" : "kind: question",
    `title: ${ask.questions[0]?.title ?? id}`,
    ...(picks ? [`unsent picks: ${picks}`] : []),
    file,
    // NIT-1 (round 2): a bare revise reads the body from stdin; say which body the reply keeps.
    f.kind === "first"
      ? `do it, then reply by \`engine ask revise ${seat}/${id} --answers-followup ${f.n} --body-file <F>\` (or --keep-body if the body still stands); the ask stays open`
      : `reply by \`engine ask revise ${seat}/${id} --keep-body --answers-followup ${f.n}\`; the ask stays open`,
  ].join("\n");
}

/**
 * A follow-up from the answerer (the server stamps the operator, as it stamps an answer): written
 * first under the file lock with compare-and-swap on `expectedRevision`, then pushed to the asker,
 * then its entry stamped with the push's outcome — `delivery: undelivered` and the reason when it
 * failed. The ask stays open; its answer, if any, is never touched (a closed ask is refused).
 */
export async function followupAsk(
  root: string,
  seat: string,
  id: string,
  input: FollowupInput,
  opts: DeliverOptions & { push?: typeof pushToSeat; expectedRevision: number },
): Promise<{ file: string; revision: number; followup: AskFollowup; delivery: DeliveryResult }> {
  const file = resolveAskPath(root, seat, id);
  if (!Number.isInteger(opts?.expectedRevision)) throw new AskFormatError("expectedRevision is required: pass the revision you read");
  const { parsed, followup } = await withFileLock(file, () => {
    const before = fs.readFileSync(file, "utf8");
    const { text, followup } = writeFollowup(before, input, opts.expectedRevision);
    atomicWrite(file, text);
    return { parsed: parseAskFile(text), followup };
  });
  const asker = parsed.header.from || seat;
  // ASKCASE: the asker under any spelling is the sender itself, and is not pushed its own follow-up.
  const delivery = seatEq(asker, followup.by) ? SELF : await safePush(opts.push ?? pushToSeat, asker, followupMessage(seat, id, file, parsed, followup), opts);
  const stamp = { delivery: delivery.status, deliveryNote: delivery.reason ? delivery.reason.replace(/\n/g, " ") : undefined };
  const stampAt = async (f: string) => withFileLock(f, () => atomicWrite(f, markFollowups(fs.readFileSync(f, "utf8"), [followup.n], stamp)));
  let at = file;
  try {
    await stampAt(file);
  } catch (e) {
    if (!(e instanceof SeatRenamedError)) throw e;
    // S1's rule: the follow-up landed and was pushed; the stamp follows the moved ask.
    at = resolveAskPath(root, e.to, id);
    await stampAt(at).catch(() => undefined);
  }
  return { file: at, revision: currentRevision(parsed), followup, delivery };
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
  o: DeliverOptions & { by: string; push?: typeof pushToSeat; now?: string; /** ASKFOLLOWUP: the follow-ups this revision answers. */ answersFollowup?: number[] },
): Promise<ReviseResult> {
  const file = resolveAskPath(root, seat, id);
  if (!o?.by) throw new AskFormatError("revise must name who is revising");
  if (body !== undefined && RECORD_FENCE_RE.test(body)) {
    throw new AskFormatError("the body holds a ```json answer, ```json draft, ```json history, ```json followup or ```json panels block: those are records the store writes, never part of a question");
  }
  if (body !== undefined) assertFenceLanguages(body);
  for (const k of Object.keys(fields)) {
    if (fields[k] === undefined) continue;
    if (FIXED_ON_REVISE.has(k) || (STAMP_FIELDS as readonly string[]).includes(k)) throw new AskFormatError(`${k} is not revisable: a revise changes the card and the body only`);
    if (/\n/.test(fields[k]!)) throw new AskFormatError(`header value for ${k} must be one line`);
  }
  const at = o.now ?? new Date().toISOString();
  const res = await withFileLock(file, () => {
    const text = fs.readFileSync(file, "utf8");
    const ask = parseAskFile(text);
    if (!seatEq(o.by, ask.header.from)) throw new AskFormatError(`only the asker (${ask.header.from ?? "?"}) revises ${seat}/${id}; ${o.by} may answer, forward or decline it instead`);
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
      // ASKFOLLOWUP: the follow-ups are the dialogue about the ask, not its body: they stay.
      after = `${head}\n\n${body.replace(/\n*$/, "\n")}${followupEntries(text)}${panelFence(text)}${draftFence ? `\n${draftFence.replace(/^\n+/, "")}` : ""}`;
      const reparsed = parseAskFile(after);
      if (reparsed.questions.length === 0) throw new AskFormatError('body holds no question: write at least one "## Choose one: …" heading');
      assertCodes(reparsed);
      if (bodyDigest(after) !== oldBody) changed.push("body");
    }
    const answers = [...new Set(o.answersFollowup ?? [])];
    if (answers.length) {
      if (answers.some((n) => !Number.isInteger(n) || n < 1)) throw new AskFormatError("--answers-followup takes follow-up numbers: <n>[,<n>]");
      // NIT-4 (round 2): an addressed follow-up keeps its first stamp; a second revise naming it is refused.
      for (const f of ask.followups) {
        if (answers.includes(f.n) && f.addressedIn !== undefined) throw new AskFormatError(`follow-up ${f.n} is already addressed in revision ${f.addressedIn} by ${f.addressedBy ?? "?"}`);
      }
      changed.push(`followup ${answers.join(",")}`);
    }
    if (changed.length === 0) throw new AskFormatError(`nothing to revise: ${seat}/${id} already says that`);
    const revision = currentRevision(ask) + 1;
    if (answers.length) after = markFollowups(after, answers, { addressedIn: revision, addressedBy: o.by, addressedAt: at });
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

// ── withdrawing (the asker takes its question back) ─────────

export type WithdrawResult = { file: string; revision: number; draftOf?: string; pushes: { seat: string; delivery: DeliveryResult }[] };

/**
 * Take the open ask `ref` back (ASKWITHDRAW). Unlike supersede, no newer ask replaces it: nothing is
 * left to answer, and nobody is asked to confirm the withdrawal (the operator, 2026-10-30: "confirm
 * withdrawal" asks were left in the queue).
 *
 * - Who: supersede's set — the asker (`from:`), a manager of the asker (`manages`, its FLEET_MANAGES),
 *   or the operator. Pending an operator ruling on WHO.
 * - The ask: `status: withdrawn`, `withdrawn-at`, `withdrawn-actor`, `withdrawn-reason` (one line);
 *   its revision moves and `revisions:` records it, so an answer or draft in flight is stale, and
 *   any saved draft is discarded, its author kept as `withdrawn-draft-of`.
 * - Refused: a missing ask, no actor, a blank reason, an ask that is answered, declined or ruled
 *   (that one is history), or one already superseded or withdrawn.
 * - The holder and forwarders hear one `[ask-withdrawn]` notice saying no action is needed; the
 *   asker hears it too when someone else withdrew its ask. The operator is never pushed.
 */
export async function withdrawAsk(
  root: string,
  ref: AskRef,
  o: DeliverOptions & { by: string; reason: string; manages?: string[]; push?: typeof pushToSeat; now?: string },
): Promise<WithdrawResult> {
  if (!o?.by) throw new AskFormatError("withdraw must name who is withdrawing");
  const reason = (o.reason ?? "").replace(/\s+/g, " ").trim();
  const r = `${ref.seat}/${ref.id}`;
  if (!reason) throw new AskFormatError(`withdrawing ${r} needs a reason: --reason "<why it is no longer asked>"`);
  const file = resolveAskPath(root, ref.seat, ref.id);
  if (!fs.existsSync(file)) throw new AskFormatError(`no ask ${r}`);
  const at = o.now ?? new Date().toISOString();
  const res = await withFileLock(file, () => {
    const before = fs.readFileSync(file, "utf8");
    const ask = parseAskFile(before);
    const asker = ask.header.from ?? "";
    // ASKCASE: the asker is matched case folded (an identity check); the operator name and managesSeat stay exact.
    if (o.by !== "operator" && !seatEq(o.by, asker) && !(asker && managesSeat(o.manages ?? [], asker))) {
      throw new AskFormatError(`only the asker (${asker || "?"}), its manager or the operator withdraws ${r}; ${o.by} is none of them`);
    }
    const status = ask.header.status ?? "open";
    if (status === "superseded") throw new AskFormatError(`${r} is already superseded by ${ask.header["superseded-by"] || "another ask"}; there is nothing to withdraw`);
    if (status === "withdrawn") throw new AskFormatError(`${r} is already withdrawn by ${ask.header["withdrawn-actor"] || "someone"} (${ask.header["withdrawn-reason"] || "no reason"})`);
    if (["answered", "declined", "ruled"].includes(status)) {
      throw new AskFormatError(`${r} is ${status}: that one is history and is not withdrawn; file a new ask if the answer no longer holds`);
    }
    if (status !== "open") throw new AskFormatError(`${r} is ${status}; only an open ask is withdrawn`);
    const draftOf = ask.draft ? draftAuthor(ask.draft) || "an unnamed answerer" : undefined;
    const revision = currentRevision(ask) + 1;
    let after = clearDraft(before);
    after = setHeaderField(after, "status", "withdrawn");
    after = setHeaderField(after, "withdrawn-at", at);
    after = setHeaderField(after, "withdrawn-actor", o.by);
    after = setHeaderField(after, "withdrawn-reason", reason);
    if (draftOf) after = setHeaderField(after, "withdrawn-draft-of", draftOf);
    after = setHeaderField(after, "revision", String(revision));
    const history = (ask.header.revisions ?? "").trim();
    after = setHeaderField(after, "revisions", `${history ? `${history} ; ` : ""}${revision}@${at}:withdrawn`);
    atomicWrite(file, after);
    return { parsed: parseAskFile(after), revision, draftOf };
  });
  const h = res.parsed.header;
  // ASKCASE: recipients fold case: one notice per seat whatever its spelling, and never to the withdrawer.
  const seats: string[] = [];
  for (const s of [h.to ?? "", ...forwardChain(h).flatMap((x) => [x.from, x.to]), h.from ?? ""]) {
    if (s && s !== "operator" && !seatEq(s, o.by) && !hasSeat(seats, s)) seats.push(s);
  }
  const push = o.push ?? pushToSeat;
  const msg = [
    `[ask-withdrawn] from ${o.by} via ask-app: ${r} is withdrawn: ${reason}`,
    `No action needed: do not answer it and do not acknowledge this notice; an answer or draft on it is refused.${res.draftOf ? ` A draft saved by ${res.draftOf} on it was discarded.` : ""} The file is the record:`,
    file,
  ].join("\n");
  const pushes: WithdrawResult["pushes"] = [];
  for (const s of seats) pushes.push({ seat: s, delivery: await safePush(push, s, msg, o) });
  return { file, revision: res.revision, ...(res.draftOf ? { draftOf: res.draftOf } : {}), pushes };
}

// ── renaming a seat (a fleet rename) ──────────────────────

export type RenameSeatChange = SeatChange & { /** `<seat>/<id>.md` under the root, as the file sat BEFORE the move. */ file: string };
export type RenameSeatResult = {
  dryRun: boolean;
  old: string;
  neu: string;
  /** `move`: the folder is renamed whole; `merge`: its asks join an existing folder; `none`: the old seat has no asks to move. */
  folder: { from: string; to: string; mode: "move" | "merge" | "none"; ids: string[] };
  changes: RenameSeatChange[];
  /** Files whose text changes. */
  files: string[];
  /** Asks this run moved into `<new>/` (0 on a dry run). */
  moved: number;
  /** N1: `<old>/<id>` refs left as written — in bodies, declined hops' reasons, and records' notes and reasons. */
  left: (LeftRef & { file: string })[];
  /** N3: rewritten files whose revision was read back after the write and found unchanged. */
  revisionsChecked: number;
  /** S5: what earlier runs left — asks waiting in staging, or an old folder a seat still using the old name filed into again. */
  leftover: { staging: string; staged: string[]; oldAgain?: { renamedTo: string; ids: string[] } };
};

export type RenameSeatOptions = {
  dryRun?: boolean;
  /** Who is renaming (S4): the operator, or a manager of `old` (FLEET_MANAGES), as for supersede. A dry run needs neither. */
  by?: string;
  manages?: string[];
  /** How long to wait for a write in flight inside the staged folder before refusing (default: the stale-lock age plus 5 s). */
  waitMs?: number;
  /** Test seam: called at each step (`ledger`, `staged`, `waited`, `linked:<file>`, `moved`); a throw stands for a crash. */
  onStep?: (step: string) => void;
};

const mdFiles = (d: string) => (isDir(d) ? fs.readdirSync(d).filter((f) => f.endsWith(".md") && !f.startsWith(".")).sort() : []);
const isDir = (d: string) => {
  try {
    return fs.statSync(d).isDirectory();
  } catch {
    return false;
  }
};
const isSymlink = (p: string) => {
  try {
    return fs.lstatSync(p).isSymbolicLink();
  } catch {
    return false;
  }
};
const sameFile = (a: string, b: string) => {
  try {
    const [x, y] = [fs.statSync(a), fs.statSync(b)];
    return x.ino === y.ino && x.dev === y.dev;
  } catch {
    return false;
  }
};
const revisionOf = (text: string) => text.match(/^revision:[ \t]*(.*)$/m)?.[1]?.trim() ?? "";

/**
 * Wait until no write is in flight in the staged folder: no `<id>.md.lock` and no temp file. A lock
 * untouched for LOCK_STALE_MS is a dead holder's and is cleared — withFileLock's own rule. A temp
 * file whose writer process is gone never lands, and is cleared. Returns what is still busy when
 * `waitMs` runs out (empty when settled).
 */
async function settleStaging(stage: string, waitMs: number): Promise<string[]> {
  const end = Date.now() + waitMs;
  for (;;) {
    const busy: string[] = [];
    for (const f of fs.readdirSync(stage)) {
      const p = path.join(stage, f);
      try {
        if (f.endsWith(".lock")) {
          if (Date.now() - fs.statSync(p).mtimeMs > LOCK_STALE_MS) fs.rmdirSync(p);
          else busy.push(f);
        } else if (f.endsWith(".tmp")) {
          const pid = Number(f.match(/\.(\d+)\.tmp$/)?.[1]);
          if (pid && !pidAlive(pid)) fs.unlinkSync(p);
          else busy.push(f);
        }
      } catch {
        // cleared by its holder meanwhile
      }
    }
    if (!busy.length || Date.now() >= end) return busy.sort();
    await new Promise((r) => setTimeout(r, 25));
  }
}

/**
 * `engine ask rename-seat <old> <new>`: the fleet renamed a seat, so its asks and every reference to
 * it follow.
 *
 * Who: the operator, or the old seat's own manager (S4, supersede's rule). A dry run writes nothing
 * and needs neither.
 *
 * Order (M1, N4 — the folder moves FIRST, so a writer still using the old name fails loudly with
 * ENOENT instead of writing into a folder being emptied):
 * 1. Refused, before anything is written, when `<new>/` holds an ask of the same id as one to move.
 * 2. The ledger `<root>/.rename-seat/<old>` records `<new>` (how a writer's ENOENT names the rename).
 * 3. `<old>/` is renamed, in one step, to the staging folder `<root>/.rename-seat/<old>.staging/`,
 *    which listAsks never reads. A write in flight there is waited for (a bounded wait; refused
 *    after it, with the folder put back as it was).
 * 4. Staging becomes `<new>/` in one rename when `<new>/` does not exist; otherwise each file is
 *    hard-linked into `<new>/` and then unlinked from staging. A link never overwrites: an ask that
 *    appeared in `<new>/` under the same id meanwhile is kept, the moved one goes back to `<old>/`,
 *    and the run is refused.
 * 5. Every ask file under the root has its references rewritten (rename-seat.ts says which fields;
 *    whole names only), each under its lock, atomically, with its revision unchanged — checked by
 *    reading it back — and its mtime restored, so newest-first order and every ask's age stay as they
 *    were.
 *
 * A run that stops at any point leaves each ask in one place — its old folder, staging, or its new
 * folder (between a link and its unlink, one file under two names, which a re-run tells apart by
 * inode) — and running the same command again finishes it. So does a run after a seat still using
 * the old name files under it again (S5): re-run until a pass moves and changes nothing.
 */
export async function renameSeat(root: string, old: string, neu: string, o: RenameSeatOptions = {}): Promise<RenameSeatResult> {
  for (const s of [old, neu]) if (!SAFE.test(s) || s.includes("..")) throw new AskFormatError(`invalid seat: ${s}`);
  if (old === neu) throw new AskFormatError(`${old} and ${neu} are the same seat: nothing to rename`);
  if (old === "operator" || neu === "operator") throw new AskFormatError("the operator is not a seat; it is never renamed");
  if (!o.dryRun && o.by !== "operator" && !managesSeat(o.manages ?? [], old)) {
    throw new AskFormatError(`only the operator or ${old}'s manager renames ${old}; ${o.by || "an unnamed caller"} is neither`);
  }
  const fromDir = path.join(root, old);
  const toDir = path.join(root, neu);
  const stage = stagingOf(root, old);
  // ASKCASE: a case-only rename (`domain:Language` → `domain:language`) on a case-insensitive volume
  // names ONE folder twice (the same inode). Its asks are not a clash with themselves: the folder
  // moves through staging, and comes back under the new name, case and all.
  const caseOnly = old.toLowerCase() === neu.toLowerCase();
  // S2 (round 2): an old name that is a symlink to the new folder is an alias, not a folder to move:
  // moving the link and merging through it would unlink the real asks. Refused before any write.
  if (isSymlink(fromDir) && isDir(toDir) && sameFile(fromDir, toDir)) {
    throw new AskFormatError(`${fromDir} is a symlink to ${neu}/: there is nothing to move; remove the link (rm '${fromDir}') and run the same command again; nothing was changed`);
  }
  /** Is `name` an entry of `dir` spelled exactly so? A case-insensitive volume finds a folder by either spelling; its listing holds one. */
  const onDisk = (dir: string, name: string) => fs.existsSync(dir) && fs.readdirSync(dir).includes(name);
  // S1 (round 2): the old name still finds the folder through the volume's case folding after the
  // move. It is the old folder only while the listing still spells it the old way; once it reads
  // `neu`, the rename is done, and a re-run moves nothing and reports no old name filed into again.
  const aliasOfNew = (d: string) => caseOnly && isDir(d) && !isSymlink(d) && sameFile(d, toDir);
  const oldPresent = () => isDir(fromDir) && (!aliasOfNew(fromDir) || onDisk(root, old));
  const aliased = oldPresent() && aliasOfNew(fromDir);
  const ledgerWas = readLedger(root, old);
  if (isDir(stage) && ledgerWas && ledgerWas !== neu) {
    // N1: on a case-insensitive volume a case-only pair shares one ledger and one staging folder, so a
    // stopped `X → old` reads here as a ledger naming `old` itself. The command that finishes it names
    // the staging folder's own spelling as its old seat.
    const was = ledgerWas === old ? (fs.readdirSync(path.dirname(stage)).find((e) => e.toLowerCase() === path.basename(stage).toLowerCase())?.replace(/\.staging$/, "") ?? old) : old;
    throw new AskFormatError(`an earlier rename-seat ${was} → ${ledgerWas} stopped partway (its asks wait in ${stage}); finish it first: engine ask rename-seat ${was} ${ledgerWas}`);
  }
  const strip = (f: string) => f.replace(/\.md$/, "");
  const oldMd = oldPresent() ? mdFiles(fromDir) : [];
  const staged = mdFiles(stage);
  const ids = [...new Set([...oldMd, ...staged].map(strip))].sort();
  const mode: RenameSeatResult["folder"]["mode"] = !oldPresent() && !isDir(stage) ? "none" : isDir(toDir) && !aliased ? "merge" : "move";
  const clash = [...new Set([...oldMd.filter((f) => !aliased && fs.existsSync(path.join(toDir, f))), ...staged.filter((f) => fs.existsSync(path.join(toDir, f)) && !sameFile(path.join(stage, f), path.join(toDir, f)))])].sort();
  if (clash.length) {
    throw new AskFormatError(`refusing to rename ${old} → ${neu}: ${clash.map((f) => `${neu}/${strip(f)}`).join(", ")} already exist${clash.length === 1 ? "s" : ""}; nothing was changed`);
  }
  const leftover: RenameSeatResult["leftover"] = { staging: stage, staged: staged.map(strip) };
  if (ledgerWas === neu && oldMd.length) leftover.oldAgain = { renamedTo: neu, ids: oldMd.map(strip) };

  /** Every ask file under the root, named as it sat before the move; staged files are named under the old seat. */
  const askFiles = () => {
    const out: { file: string; rel: string }[] = [];
    const seats = fs.existsSync(root) ? fs.readdirSync(root, { withFileTypes: true }).filter((d) => d.isDirectory() && !d.name.startsWith(".")).map((d) => d.name).sort() : [];
    for (const seat of seats) {
      for (const f of mdFiles(path.join(root, seat))) out.push({ file: path.join(root, seat, f), rel: `${seat === neu && ids.includes(strip(f)) ? old : seat}/${f}` });
    }
    for (const f of mdFiles(stage)) out.push({ file: path.join(stage, f), rel: `${old}/${f}` });
    return out;
  };
  const result: RenameSeatResult = {
    dryRun: !!o.dryRun,
    old,
    neu,
    folder: { from: `${old}/`, to: `${neu}/`, mode, ids },
    changes: [],
    files: [],
    moved: 0,
    left: [],
    revisionsChecked: 0,
    leftover,
  };

  if (o.dryRun) {
    for (const p of askFiles()) {
      const t = fs.readFileSync(p.file, "utf8");
      const r = rewriteSeatRefs(t, old, neu);
      if (r.changes.length) {
        result.files.push(p.rel);
        result.changes.push(...r.changes.map((c) => ({ file: p.rel, ...c })));
      }
      result.left.push(...leftRefs(t, old).map((l) => ({ file: p.rel, ...l })));
    }
    return result;
  }

  const step = (s: string) => o.onStep?.(s);
  if (mode !== "none") {
    fs.mkdirSync(path.join(root, RENAME_DIR), { recursive: true });
    if (ledgerWas !== neu) atomicWrite(ledgerOf(root, old), `${neu}\n${new Date().toISOString()}\n`);
    // N3: after a case-only rename on a case-insensitive volume this one file is also `neu`'s ledger,
    // so it names its own seat; renamedTo ignores a ledger that leads back to a name it has seen.
    // `neu` is a live seat now: a ledger from an earlier rename away from that name no longer applies.
    // On a case-insensitive volume a case-only rename's two ledgers are one file: that one is kept.
    if (readLedger(root, neu) && !sameFile(ledgerOf(root, old), ledgerOf(root, neu))) fs.rmSync(ledgerOf(root, neu), { force: true });
    step("ledger");
    // A few passes at most: one for a staging folder a stopped run left, one for an old folder filed into again.
    // Once moved, the old name of a case-only rename still finds the folder through the alias: that is
    // the new folder, not an old one filed into again.
    const oldLeft = () => oldPresent() && !aliasOfNew(fromDir);
    for (let pass = 0; pass < 3 && ((pass === 0 && aliased) || isDir(stage) || oldLeft()); pass++) {
      if (!isDir(stage)) fs.renameSync(fromDir, stage);
      // An alias that is a symlink (not a case-folding volume) is left dangling by the move: it goes.
      if (aliased && !isDir(toDir) && isSymlink(toDir)) fs.unlinkSync(toDir);
      step("staged");
      const waitMs = o.waitMs ?? LOCK_STALE_MS + 5_000;
      const busy = await settleStaging(stage, waitMs);
      if (busy.length) {
        const back = !isDir(fromDir);
        if (back) fs.renameSync(stage, fromDir);
        if (back && ledgerWas === undefined) fs.rmSync(ledgerOf(root, old), { force: true });
        throw new AskFormatError(
          `a write is in flight in ${old}/ (${busy.join(", ")}) and did not finish in ${(waitMs / 1000).toFixed(1)}s; ${back ? `nothing was moved (${old}/ is back as it was)` : `its asks wait in ${stage}`}; run the same command again in a moment`,
        );
      }
      step("waited");
      result.moved += moveStaged(stage, fromDir, toDir, old, neu, step);
      step("moved");
    }
  }

  // The rewrite, each file under its lock and re-read there, so a write that landed since is kept.
  for (const p of askFiles()) {
    await withFileLock(p.file, () => {
      const st = fs.statSync(p.file);
      const before = fs.readFileSync(p.file, "utf8");
      const r = rewriteSeatRefs(before, old, neu);
      result.left.push(...leftRefs(r.text, old).map((l) => ({ file: p.rel, ...l })));
      if (!r.changes.length) return;
      const rev = revisionOf(before);
      if (revisionOf(r.text) !== rev) throw new AskFormatError(`refusing to rewrite ${p.rel}: its revision would move (${rev} → ${revisionOf(r.text)}); a rename is not a revision`);
      atomicWrite(p.file, r.text);
      // Seconds as a float, not a Date: a Date keeps whole milliseconds, and its round trip drifted up to 2 ms.
      fs.utimesSync(p.file, st.atimeMs / 1000, st.mtimeMs / 1000);
      // N3: read back, so "revisions unchanged" is a check, not a claim.
      const back = revisionOf(fs.readFileSync(p.file, "utf8"));
      if (back !== rev) throw new AskFormatError(`${p.rel}: revision ${rev} read back as ${back} after the rewrite`);
      result.revisionsChecked++;
      result.files.push(p.rel);
      result.changes.push(...r.changes.map((c) => ({ file: p.rel, ...c })));
    });
  }
  return result;
}

/**
 * Step 4: staging into `<new>/`. Returns how many asks moved. Never overwrites: `renameSync` of a
 * folder only onto a missing one, then `linkSync` (EEXIST when the name is taken) and `unlinkSync`.
 */
function moveStaged(stage: string, fromDir: string, toDir: string, old: string, neu: string, step: (s: string) => void): number {
  const asks = mdFiles(stage).length;
  if (!isDir(toDir)) {
    try {
      fs.renameSync(stage, toDir);
      return asks;
    } catch (e) {
      // `<new>/` appeared meanwhile with something in it: merge instead.
      if (!["EEXIST", "ENOTEMPTY"].includes((e as NodeJS.ErrnoException).code ?? "")) throw e;
    }
  }
  let moved = 0;
  const kept: string[] = [];
  for (const f of fs.readdirSync(stage).sort()) {
    const src = path.join(stage, f);
    const dst = path.join(toDir, f);
    try {
      fs.linkSync(src, dst);
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
      // The same file under both names is a stopped run's half-done move; anything else is a clash.
      if (!sameFile(src, dst)) {
        kept.push(f);
        continue;
      }
    }
    step(`linked:${f}`);
    fs.unlinkSync(src);
    if (f.endsWith(".md") && !f.startsWith(".")) moved++;
  }
  if (!kept.length) {
    fs.rmdirSync(stage);
    return moved;
  }
  // Each clashing ask goes back where it was — never over anything — so it stays listed, under its old name.
  fs.mkdirSync(fromDir, { recursive: true });
  const stuck: string[] = [];
  for (const f of kept) {
    try {
      fs.linkSync(path.join(stage, f), path.join(fromDir, f));
      fs.unlinkSync(path.join(stage, f));
    } catch {
      stuck.push(f);
    }
  }
  if (!stuck.length) fs.rmdirSync(stage);
  const ids = kept.map((f) => f.replace(/\.md$/, ""));
  throw new AskFormatError(
    `refusing to finish ${old} → ${neu}: ${ids.map((id) => `${neu}/${id}`).join(", ")} appeared in ${neu}/ while this ran; nothing was overwritten. ` +
      `${kept.length - stuck.length ? `${kept.filter((f) => !stuck.includes(f)).map((f) => `${old}/${f.replace(/\.md$/, "")}`).join(", ")} went back to ${old}/. ` : ""}` +
      `${stuck.length ? `${stuck.join(", ")} wait in ${stage}. ` : ""}${moved} other ask${moved === 1 ? "" : "s"} moved. ` +
      `Compare each pair, keep the one with the higher revision, remove the other, and run the same command again.`,
  );
}

// ── IDE-338: attach a panel's reads to an ask ─────────────

export type AttachPanelResult = { file: string; entry: PanelAttachment; pushes: { seat: string; delivery: DeliveryResult }[]; already?: boolean };

/**
 * `engine ask attach-panel`: any panel runner appends one council's reads on one fork (and any
 * options it proposed) to the ask's ```json panels``` record. Append-only: the question, options,
 * answer, revision and body digest do not move, so an answer or draft in flight stays valid. Refused
 * on a withdrawn or superseded ask; an answered or declined one takes it as a record beside the answer.
 */
export async function attachPanel(
  root: string,
  ref: AskRef,
  o: DeliverOptions & { by: string; fork: string; panel?: PanelRead[]; proposals?: PanelProposal[]; council?: string; push?: typeof pushToSeat; now?: string },
): Promise<AttachPanelResult> {
  const r = `${ref.seat}/${ref.id}`;
  if (!o?.by) throw new AskFormatError("attach-panel must name who is attaching");
  const panel = (o.panel ?? []).map(({ lens, pick, why }) => ({ lens, pick, why }));
  const proposals = (o.proposals ?? []).map(({ lens, label, why }) => ({ lens, label, why }));
  if (!panel.length && !proposals.length) throw new AskFormatError(`attach-panel on ${r} needs at least one --panel or --proposed line`);
  if (!o.council || !/^https?:\/\/\S+$/.test(o.council)) {
    throw new AskFormatError(`--council must be the published report's http(s) URL (publish it to the proof store first); got ${o.council ? `"${o.council}"` : "none"}`);
  }
  for (const x of [...panel, ...proposals]) {
    for (const [k, v] of Object.entries(x)) if (!String(v).trim() || /\n/.test(String(v))) throw new AskFormatError(`attach-panel: a read's ${k} must be one non-empty line`);
  }
  const file = resolveAskPath(root, ref.seat, ref.id);
  if (!fs.existsSync(file)) throw new AskFormatError(`no ask ${r}`);
  const at = o.now ?? new Date().toISOString();
  const res = await withFileLock(file, () => {
    const before = fs.readFileSync(file, "utf8");
    const ask = parseAskFile(before);
    assertLive(ask);
    const keys = ask.questions.map((q, i) => questionKey(q, i));
    const qi = keys.indexOf(o.fork);
    if (qi === -1) throw new AskFormatError(`${r} has no fork ${o.fork}; its forks are ${keys.join(", ")}`);
    // M2: a positional key (q0, q1) moves when a revise adds or reorders forks, so it can only name the one fork.
    if (keys.length > 1 && !ask.questions[qi].askName) {
      throw new AskFormatError(`${r} fork ${o.fork} has no ¶ASK_ name, and the ask has ${keys.length} forks; a position can move on revise, so ask ${ask.header.from ?? "the asker"} to name the forks (\`## ¶ASK_<NAME>: …\`) first`);
    }
    // S2: the same council on the same fork is attached once; a re-run after a crash changes nothing.
    const prior = ask.panelAttachments.find((e) => e.fork === o.fork && e.council === o.council);
    if (prior) return { entry: prior, asker: "", already: true };
    const codes = allCodes(ask.questions[qi].options);
    for (const p of panel) {
      if (!codes.includes(p.pick)) throw new AskFormatError(`${p.lens}'s pick ${p.pick} names no option of ${o.fork} (it has ${codes.join(", ") || "no codes"}); an option the panel proposes goes in --proposed`);
    }
    const entry: PanelAttachment = { fork: o.fork, title: ask.questions[qi].title, panel, proposals, council: o.council!, by: o.by, at };
    atomicWrite(file, appendPanelEntry(before, entry));
    return { entry, asker: ask.header.from ?? "", already: false };
  });
  const push = o.push ?? pushToSeat;
  const pushes: AttachPanelResult["pushes"] = [];
  if (res.asker && res.asker !== o.by && res.asker !== "operator") {
    const n = (k: number, w: string) => `${k} ${w}${k === 1 ? "" : "s"}`;
    const msg = [
      `[ask-panel] from ${o.by} via ask-app: ${r} fork ${o.fork} has a panel attached: ${n(panel.length, "read")}${proposals.length ? `, ${n(proposals.length, "proposed option")}` : ""}. Report: ${o.council}`,
      "No action needed: the reads show beside the fork's options; the question and any answer are unchanged. The file is the record:",
      file,
    ].join("\n");
    pushes.push({ seat: res.asker, delivery: await safePush(push, res.asker, msg, o) });
  }
  return { file, entry: res.entry, pushes, ...(res.already ? { already: true } : {}) };
}
