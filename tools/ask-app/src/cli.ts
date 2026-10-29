/**
 * Node half of `engine ask new|list|answer` (scripts/ask.sh handles `path` and `serve`).
 * Run with node >= 23.6, which strips the types itself.
 */
import fs from "node:fs";
import { answerAsk, defaultAskRoot, listAsks, newAsk } from "./lib/store.ts";
import { HEADER_FIELDS, type AnswerMap, type AskAnswer } from "./lib/format.ts";

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

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const { pos, opt } = flags(rest);
  const root = opt.root || defaultAskRoot();

  if (cmd === "new") {
    const body = opt["body-file"] ? fs.readFileSync(opt["body-file"], "utf8") : fs.readFileSync(0, "utf8");
    const from = opt.from || process.env.FLEET_PANE || die("no --from and no FLEET_PANE: name the asking seat");
    const to = opt.to || process.env.FLEET_PARENT || "operator";
    const fields: Record<string, string> = { from, to, id: opt.id || defaultId(body) };
    for (const k of HEADER_FIELDS) if (opt[k] !== undefined && !["status", "revision", "created"].includes(k)) fields[k] = opt[k];
    try {
      console.log(newAsk(root, fields as { from: string; to: string; id: string }, body));
    } catch (e) {
      die((e as Error).message);
    }
    return;
  }

  if (cmd === "list") {
    const status = opt.status || "open";
    const asks = listAsks(root).filter(
      (a) => (status === "all" || a.header.status === status) && (!opt.to || a.header.to === opt.to) && (!opt.seat || a.seat === opt.seat),
    );
    if (opt.json === "true") {
      console.log(JSON.stringify(asks, null, 2));
      return;
    }
    for (const a of asks) {
      const title = a.questions[0]?.title ?? "";
      const delivery = a.header.delivery ? ` (${a.header.delivery})` : "";
      console.log(`${a.header.status}${delivery}\t${a.seat}/${a.header.id}\trev=${a.header.revision}\tto=${a.header.to}\t${a.header.importance || "-"}\t${title}`);
    }
    return;
  }

  if (cmd === "answer") {
    const ref = pos[0] || die("usage: ask answer <seat>/<id> --revision N (--json '{\"Q\":[\"CODE\"]}' | --decline <reason>) [--by who] [--note text]");
    const slash = ref.lastIndexOf("/");
    if (slash < 1) die(`expected <seat>/<id>, got ${ref}`);
    // Compare-and-swap: the answerer names the revision it read (shown by `engine ask list`).
    if (opt.revision === undefined || !/^\d+$/.test(opt.revision)) die("--revision is required: pass the revision you read (engine ask list shows it)");
    const by = opt.by || process.env.FLEET_PANE || "operator";
    let input: AskAnswer;
    if (opt.decline !== undefined) {
      input = { declined: true, reason: opt.decline === "true" ? "" : opt.decline, answeredBy: by };
    } else {
      let answers: unknown;
      try {
        answers = JSON.parse(opt.json || die("--json or --decline is required"));
      } catch {
        die("--json is not valid JSON");
      }
      input = { answers: answers as AnswerMap, answeredBy: by };
    }
    try {
      const res = await answerAsk(root, ref.slice(0, slash), ref.slice(slash + 1), { ...input, ...(opt.note ? { note: opt.note } : {}) }, { expectedRevision: Number(opt.revision) });
      console.log(`${res.delivery.status}${res.delivery.reason ? `: ${res.delivery.reason}` : ""}\trevision ${res.revision}\t${res.file}`);
    } catch (e) {
      die((e as Error).message);
    }
    return;
  }

  die(`unknown command: ${cmd ?? "(none)"}`);
}

main();
