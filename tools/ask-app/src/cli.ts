/**
 * Node half of `engine ask new|list|answer|…|supersede` (scripts/ask.sh handles `path` and `serve`).
 * Run with node >= 23.6, which strips the types itself.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { actedAsk, answerAsk, defaultAskRoot, discardDraft, forwardAsk, listAsks, newAsk, pickupUnread, readAsk, repushPending, reviseAsk, saveDraft, sendBatch, supersedeAsk } from "./lib/store.ts";
import { answeredByText, authorWarnings, HEADER_FIELDS, parseAskFile, type AnswerMap, type AskAnswer } from "./lib/format.ts";

/** The author guide, pointed to whenever `new` or `revise` warns or refuses. */
const GUIDE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "skills", "ask", "assets", "ASK_AUTHOR_GUIDE.md");
const guideLine = () => `ask: how to write an answerable ask: ${GUIDE}`;
function warnAuthoring(file: string) {
  const w = authorWarnings(parseAskFile(fs.readFileSync(file, "utf8")));
  for (const x of w) process.stderr.write(`ask: warning: ${x}\n`);
  if (w.length) process.stderr.write(`${guideLine()}\n`);
}

/** Where an answer is in its life: never shows a queued push as read. */
export function lifeOf(h: Record<string, string | undefined>): string {
  if (h.acted) return "acted";
  if (h.readAt) return "read";
  if (h.delivery === "delivered") return "queued";
  return h.delivery || "";
}

function flags(argv: string[]): { pos: string[]; opt: Record<string, string> } {
  const pos: string[] = [];
  const opt: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) opt[key] = "true";
      else {
        opt[key] = next;
        i++;
      }
    } else pos.push(a);
  }
  return { pos, opt };
}

function die(msg: string): never {
  process.stderr.write(`ask: ${msg}\n`);
  process.exit(1);
}

function defaultId(body: string): string {
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..*/, "").replace("T", "-");
  const title = body.match(/^##\s+(?:¶ASK_\w+:\s+)?Choose(?: one)?:\s+(.+)$/m)?.[1] ?? "ask";
  const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 32);
  return `${stamp}-${slug || "ask"}`;
}

/**
 * This seat's identity and parent, LIVE first — hop.sh's rule (resolve_self, and the parent edge):
 * run.sh caches FLEET_PANE and FLEET_PARENT at launch, so a seat renamed or re-parented since then
 * still carries its old names there ("domain:domain is not a recipient"). With TMUX_PANE set, the
 * pane's `#{window_name}:#{@pane_label}` and `#{@pane_parent}` (`-` = no parent, i.e. the operator)
 * win, with a warning when the cache differs; the cache is used only when tmux cannot be read.
 * Test seam: ASK_LIVE_PANES names a file of `seat pane_id parent` lines read instead of tmux, and
 * ASK_TMUX_SOCKET a `tmux -L` socket.
 */
export function liveIdentity(env: NodeJS.ProcessEnv = process.env, warn: (m: string) => void = (m) => process.stderr.write(`${m}\n`)): { pane: string; parent: string } {
  const cachedPane = env.FLEET_PANE || "";
  const cachedParent = env.FLEET_PARENT || "";
  let line = "";
  if (env.TMUX_PANE) {
    try {
      if (env.ASK_LIVE_PANES) {
        line = fs.readFileSync(env.ASK_LIVE_PANES, "utf8").split("\n").find((l) => l.trim().split(/\s+/)[1] === env.TMUX_PANE) ?? "";
        const [seat, , parent] = line.trim().split(/\s+/);
        line = seat ? `${seat} ${parent ?? "-"}` : "";
      } else {
        const sock = env.ASK_TMUX_SOCKET ? ["-L", env.ASK_TMUX_SOCKET] : [];
        line = execFileSync("tmux", [...sock, "display", "-p", "-t", env.TMUX_PANE, "#{window_name}:#{@pane_label} #{?@pane_parent,#{@pane_parent},-}"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 2000 }).trim();
      }
    } catch {
      line = "";
    }
  }
  const [liveSeat, liveParentRaw] = line.split(/\s+/);
  if (!liveSeat || liveSeat === ":" || liveSeat.startsWith(":") || liveSeat.endsWith(":")) return { pane: cachedPane, parent: cachedParent };
  const liveParent = !liveParentRaw || liveParentRaw === "-" ? "" : liveParentRaw;
  if (cachedPane && cachedPane !== liveSeat) warn(`ask: FLEET_PANE '${cachedPane}' is stale; using the live pane label '${liveSeat}'`);
  if (cachedParent && cachedParent !== liveParent) warn(`ask: FLEET_PARENT '${cachedParent}' is stale; using the live @pane_parent '${liveParent || "none (operator)"}' of '${liveSeat}'`);
  return { pane: liveSeat, parent: liveParent };
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const { pos, opt } = flags(rest);
  const root = opt.root || defaultAskRoot();
  const live = liveIdentity();
  const pane = live.pane;
  /** The panes this seat manages (FLEET_MANAGES): standing to forward a silent child's ask, or to relay onto it. */
  const manages = (process.env.FLEET_MANAGES ?? "").split(/[\s,]+/).filter(Boolean);
  const splitRef = (ref: string | undefined, usage: string) => {
    if (!ref) die(usage);
    const slash = ref.lastIndexOf("/");
    if (slash < 1) die(`expected <seat>/<id>, got ${ref}`);
    return { seat: ref.slice(0, slash), id: ref.slice(slash + 1) };
  };
  /**
   * M3: who is acting. A seat (FLEET_PANE set) acts as itself: a `--by` naming anyone else is refused,
   * and no seat may claim `operator`. A shell with no FLEET_PANE is not a seat, so it names itself
   * with `--by` (the operator at a bare terminal passes `--by operator`). This guards against honest
   * mistakes; it is not a defence against a hostile process on the same account.
   */
  const identity = (verb: string): string => {
    const by = opt.by === "true" ? "" : opt.by || "";
    if (pane) {
      if (pane === "operator") die(`FLEET_PANE=operator is refused: a seat cannot be the operator`);
      if (by === "operator") die(`--by operator from a seat (FLEET_PANE=${pane}) is refused: a seat ${verb}s as itself`);
      if (by && by !== pane) die(`--by ${by} differs from FLEET_PANE=${pane}: a seat ${verb}s as itself`);
      return pane;
    }
    if (!by) die(`FLEET_PANE is unset, so this shell is not a seat: pass --by <who> to ${verb} (the operator passes --by operator)`);
    return by;
  };
  /** The reader, for stamping a read: the same rule, except that a reader with no identity stamps nothing. */
  const reader = (): string => (pane || (opt.by && opt.by !== "true") ? identity("read") : "");
  /**
   * The relay: the operator answered in this seat's terminal, and the seat records it. Stamped
   * `answeredBy: operator, answeredVia: relay:<seat>`, with a note saying when and where the operator
   * said it. An honour record like the rest of R4 — the card shows the relayer so a false relay is
   * visible.
   */
  const relayStamp = (by: string): { answeredBy: string; answeredVia: string } => {
    if (opt["relayed-from"] === undefined) return { answeredBy: by, answeredVia: "cli" };
    if (opt["relayed-from"] !== "operator") die(`--relayed-from takes only operator (got ${opt["relayed-from"]})`);
    if (!pane) die("--relayed-from operator is recorded by a seat (FLEET_PANE); the operator at a bare terminal answers --by operator itself");
    if (!opt.note || opt.note === "true" || !opt.note.trim()) die('--relayed-from needs --note "<when and where the operator said it>"');
    return { answeredBy: "operator", answeredVia: `relay:${by}` };
  };
  const answerInput = (by: string): AskAnswer => {
    const who = relayStamp(by);
    if (opt.decline !== undefined) return { declined: true, reason: opt.decline === "true" ? "" : opt.decline, ...who, ...(opt.note ? { note: opt.note } : {}) };
    let answers: unknown;
    try {
      answers = JSON.parse(opt.json || die("--json or --decline is required"));
    } catch {
      die("--json is not valid JSON");
    }
    return { answers: answers as AnswerMap, ...who, ...(opt.note ? { note: opt.note } : {}) };
  };

  if (cmd === "new") {
    const body = opt["body-file"] ? fs.readFileSync(opt["body-file"], "utf8") : fs.readFileSync(0, "utf8");
    // Round 2: an ask comes from the seat filing it. From a pane, --from may only repeat the live
    // identity; it can never name another seat or the operator.
    if (pane && opt.from && opt.from !== pane) die(`--from ${opt.from} differs from this seat (${pane}): a seat files its own asks`);
    const from = opt.from || pane || die("no --from and no FLEET_PANE: name the asking seat");
    const to = opt.to || live.parent || "operator";
    const fields: Record<string, string> = { from, to, id: opt.id || defaultId(body) };
    for (const k of HEADER_FIELDS) if (opt[k] !== undefined && !["status", "revision", "created"].includes(k)) fields[k] = opt[k];
    let file: string;
    try {
      file = newAsk(root, fields as { from: string; to: string; id: string }, body);
    } catch (e) {
      process.stderr.write(`${guideLine()}\n`);
      die((e as Error).message);
    }
    console.log(file);
    warnAuthoring(file);
    return;
  }

  if (cmd === "revise") {
    const { seat, id } = splitRef(pos[0], "usage: ask revise <seat>/<id> [card flags as for new] [--body-file F | body on stdin | --keep-body]");
    const by = identity("revise");
    const body = opt["keep-body"] === "true" ? undefined : opt["body-file"] ? fs.readFileSync(opt["body-file"], "utf8") : fs.readFileSync(0, "utf8");
    const fields: Record<string, string> = {};
    for (const k of HEADER_FIELDS) if (opt[k] !== undefined && !["id", "from", "to", "status", "revision", "created"].includes(k)) fields[k] = opt[k];
    try {
      const r = await reviseAsk(root, seat, id, fields, body !== undefined && body.trim() ? body : undefined, { by });
      warnAuthoring(r.file);
      console.log(`revised\t${seat}/${id}\trevision ${r.revision}\tchanged: ${r.changed.join(", ")}`);
      for (const p of r.pushes) console.log(`notice ${p.seat} ${p.delivery.status}${p.delivery.reason ? `: ${p.delivery.reason}` : ""}`);
    } catch (e) {
      process.stderr.write(`${guideLine()}\n`);
      die((e as Error).message);
    }
    return;
  }

  if (cmd === "list") {
    const status = opt.status || "open";
    // NEW-4: `settled` is answered + declined; a comma list names several statuses.
    const wanted = new Set(status.split(",").flatMap((x) => (x === "settled" ? ["answered", "declined"] : [x.trim()])));
    const asks = listAsks(root).filter(
      (a) => (wanted.has("all") || wanted.has(a.header.status ?? "")) && (!opt.to || a.header.to === opt.to) && (!opt.seat || a.seat === opt.seat),
    );
    if (opt.json === "true") {
      console.log(JSON.stringify(asks, null, 2));
      return;
    }
    for (const a of asks) {
      const title = a.questions[0]?.title ?? "";
      const life = lifeOf(a.header);
      const delivery = life ? ` (${life})` : a.draft ? " (draft)" : "";
      console.log(`${a.header.status}${delivery}\t${a.seat}/${a.header.id}\trev=${a.header.revision}\tto=${a.header.to}\t${a.header.importance || "-"}\t${title}`);
    }
    return;
  }

  if (cmd === "answer" || cmd === "draft") {
    const { seat, id } = splitRef(pos[0], `usage: ask ${cmd} <seat>/<id> --revision N (--json '{"Q":["CODE"]}' | --decline <reason>) [--by who] [--note text]`);
    // Compare-and-swap: the answerer names the revision it read (shown by `engine ask list`).
    if (opt.revision === undefined || !/^\d+$/.test(opt.revision)) die("--revision is required: pass the revision you read (engine ask list shows it)");
    const input = answerInput(identity(cmd));
    try {
      if (cmd === "draft") {
        console.log(`draft saved\t${await saveDraft(root, seat, id, input, Number(opt.revision), { relayerManages: manages })}`);
        return;
      }
      const res = await answerAsk(root, seat, id, input, { expectedRevision: Number(opt.revision), relayerManages: manages });
      console.log(`${res.delivery.status}${res.delivery.reason ? `: ${res.delivery.reason}` : ""}\trevision ${res.revision}\t${res.file}`);
    } catch (e) {
      die((e as Error).message);
    }
    return;
  }

  if (cmd === "discard") {
    const { seat, id } = splitRef(pos[0], "usage: ask discard <seat>/<id>");
    const by = identity("discard");
    await discardDraft(root, seat, id, by).catch((e) => die((e as Error).message));
    console.log(`draft discarded\t${seat}/${id}`);
    return;
  }

  if (cmd === "send") {
    // The batch reads the files only: refs in, never answers.
    // S1: with no refs, only the sender's own drafts go — never another answerer's held tray.
    const res = await sendBatch(root, pos.length ? pos : undefined, { by: identity("send"), relayerManages: manages });
    for (const r of res.repushed) console.log(`repushed ${r.ref}\t${r.delivery.status}${r.delivery.reason ? `: ${r.delivery.reason}` : ""}`);
    for (const s of res.settled) console.log(`settled ${s.ref}\trevision ${s.revision}`);
    for (const r of res.refused) console.log(`refused ${r.ref}\t${r.error}`);
    for (const p of res.pushes) {
      const label = p.delivery.status === "delivered" ? "queued (not yet read)" : p.delivery.status;
      console.log(`push ${p.seat} ${p.delivery.status === "delivered" ? "delivered" : p.delivery.status} (${p.refs.length} asks)\t${label}${p.delivery.reason ? `: ${p.delivery.reason}` : ""}`);
    }
    if (res.settled.length === 0 && res.refused.length === 0) console.log("no drafts of yours to send");
    if (res.refused.length) process.exitCode = 1;
    return;
  }

  if (cmd === "read") {
    const by = reader();
    // S3: an answer whose push died with its writer is pushed again on the next read.
    for (const r of await repushPending(root, { by: by || undefined })) console.error(`repushed ${r.ref}\t${r.delivery.status}`);
    const print = (r: { ref: string; file: string; lines: string[]; stamped: boolean; why?: string; ask: { answer?: AskAnswer } }) => {
      console.log(`${r.ref}\t${r.file}${r.ask.answer ? `\tby ${answeredByText(r.ask.answer)}` : ""}`);
      for (const l of r.lines) console.log(`  ${l}`);
      if (!r.stamped) console.error(`  (not stamped read: ${r.why})`);
    };
    if (opt.unread === "true") {
      // The seat's /next pickup: every settled ask the seat asked or forwarded that IT has not read.
      // Run for another seat, it stamps the caller's read (when the caller is a recipient), never the seat's.
      const seat = opt.seat || by || die("read --unread needs --seat or FLEET_PANE");
      for (const r of await pickupUnread(root, seat, { by: by || undefined })) print(r);
      return;
    }
    const { seat, id } = splitRef(pos[0], "usage: ask read <seat>/<id> [--full] | ask read --unread [--seat S]");
    try {
      const r = await readAsk(root, seat, id, { by: by || undefined });
      print(r);
      if (opt.full === "true") console.log(JSON.stringify(r.ask.answer ?? null, null, 2));
    } catch (e) {
      die((e as Error).message);
    }
    return;
  }

  if (cmd === "acted") {
    const { seat, id } = splitRef(pos[0], 'usage: ask acted <seat>/<id> "<one-line summary>"');
    try {
      await actedAsk(root, seat, id, pos.slice(1).join(" ") || opt.summary || "", {
        by: identity("act"),
        relayerManages: manages,
        ...(opt["ruled-in-chat"] !== undefined ? { ruledInChat: opt["ruled-in-chat"] === "true" ? "" : opt["ruled-in-chat"] } : {}),
        ...(opt["relayed-from"] !== undefined ? { relayedFrom: opt["relayed-from"] } : {}),
        ...(opt.note && opt.note !== "true" ? { note: opt.note } : {}),
      });
      console.log(`acted\t${seat}/${id}`);
    } catch (e) {
      die((e as Error).message);
    }
    return;
  }

  if (cmd === "forward") {
    const { seat, id } = splitRef(pos[0], "usage: ask forward <seat>/<id> --to <next seat> [--by holder]");
    try {
      await forwardAsk(root, seat, id, { to: opt.to || die("--to is required"), by: identity("forward"), manages });
      console.log(`forwarded\t${seat}/${id} → ${opt.to}`);
    } catch (e) {
      die((e as Error).message);
    }
    return;
  }

  if (cmd === "supersede") {
    // `--by` is overloaded here: `--by <seat>/<id>` names the replacement (the usage the verb was
    // asked for), and `--by <who>` stays the actor, as for every verb. A seat never holds a `/`
    // (resolveAskPath refuses one), so the slash tells them apart; both may be given.
    const usage = "usage: ask supersede <seat>/<old-id> --by <seat>/<new-id> [--by operator]";
    const bys: string[] = [];
    for (let i = 0; i < rest.length; i++) if (rest[i] === "--by" && rest[i + 1] !== undefined && !rest[i + 1].startsWith("--")) bys.push(rest[++i]);
    const refs = bys.filter((b) => b.includes("/"));
    const actors = bys.filter((b) => !b.includes("/"));
    if (refs.length !== 1) die(`${usage}: name exactly one replacement with --by <seat>/<new-id>`);
    if (actors.length > 1) die(`${usage}: more than one actor given (${actors.join(", ")})`);
    if (actors.length) opt.by = actors[0];
    else delete opt.by;
    const old = splitRef(pos[0], usage);
    const neu = splitRef(refs[0], usage);
    try {
      const r = await supersedeAsk(root, old, neu, { by: identity("supersede"), manages });
      console.log(`superseded\t${old.seat}/${old.id} → ${neu.seat}/${neu.id}\trevision ${r.revision}`);
      for (const p of r.pushes) console.log(`notice ${p.seat} ${p.delivery.status}${p.delivery.reason ? `: ${p.delivery.reason}` : ""}`);
    } catch (e) {
      die((e as Error).message);
    }
    return;
  }

  die(`unknown command: ${cmd ?? "(none)"}`);
}

main();
