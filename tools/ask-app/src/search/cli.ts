/**
 * IDE-334 (RAGPROOFS): `engine ask search`, the command-line side of the ask app's search index.
 *
 *   engine ask search index [--full] [--json]     one incremental pass over asks, broadcasts and proofs
 *   engine ask search query "<q>" [--kind ask|proof|broadcast[,…]] [--limit N] [--json]
 *   engine ask search status [--json]             when the index last ran, its size, the last pass's report
 *
 * The index is `<asks root>/.ask-app.search.db` (ASK_SEARCH_DB overrides), the same file `engine ask serve`
 * reads and refreshes, so a pass here is what the app searches next. Exit: 0 done; 1 failed (the message
 * says why: no index yet, the embedder down, another indexer running); 2 usage.
 */
import { createLocalEmbeddingClient, INDEXER_EMBED_RETRY, resolveEmbedConfig } from "../../../embed-local/src/index.ts";
import { defaultAskRoot } from "../lib/store.ts";
import { openSearchDb, searchDbPath } from "./db.ts";
import { indexSources, tryIndexLock } from "./indexer.ts";
import { indexState, search, SearchUnavailable } from "./query.ts";
import { defaultSources, KINDS, type Kind } from "./sources.ts";

const argv = process.argv.slice(2);
const sub = argv.shift();
const flag = (name: string) => {
  const i = argv.indexOf(`--${name}`);
  if (i < 0) return undefined;
  const v = argv[i + 1];
  argv.splice(i, 2);
  return v;
};
const bool = (name: string) => {
  const i = argv.indexOf(`--${name}`);
  if (i < 0) return false;
  argv.splice(i, 1);
  return true;
};
const die = (msg: string, code = 1): never => {
  process.stderr.write(`ask search: ${msg}\n`);
  process.exit(code);
};

const root = process.env.ASK_ROOT || defaultAskRoot();
const file = searchDbPath(root);
const json = bool("json");

if (sub === "index") {
  const full = bool("full");
  const release = tryIndexLock(file) ?? die("another indexer is running on this index (see its .lock file); nothing done");
  const db = openSearchDb(file);
  const t0 = Date.now();
  try {
    const r = await indexSources(db, defaultSources(root), createLocalEmbeddingClient({ retry: INDEXER_EMBED_RETRY }), {
      full,
      onSource: (name, n) => {
        if (!json) process.stderr.write(`ask search: ${name}: ${n} listed (${((Date.now() - t0) / 1000).toFixed(1)} s)\n`);
      },
    });
    if (json) process.stdout.write(`${JSON.stringify(r)}\n`);
    else {
      for (const [name, s] of Object.entries(r.sources)) if (!s.ok) process.stdout.write(`${name}: NOT LISTED (${s.error}); nothing pruned from it\n`);
      process.stdout.write(
        `added ${r.added}, changed ${r.changed}, touched ${r.touched}, unchanged ${r.unchanged}, deleted ${r.deleted}, duplicates ${r.duplicates}, unreadable ${r.unreadable}\n` +
          `embeddings: created ${r.embeddingsCreated}, reused ${r.embeddingsReused}, pruned ${r.embeddingsPruned}; ${(r.ms / 1000).toFixed(1)} s\n`,
      );
    }
    if (r.error) die(`the pass stopped: ${r.error} (what was written stays; the next pass retries the rest)`);
  } finally {
    db.close();
    release();
  }
} else if (sub === "query") {
  const kinds = (flag("kind") ?? "").split(",").filter(Boolean);
  const bad = kinds.filter((k) => !KINDS.includes(k as Kind));
  if (bad.length) die(`unknown kind ${bad.join(", ")}: one of ${KINDS.join(", ")}`, 2);
  const limit = Number(flag("limit") ?? 10);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) die("--limit is a whole number from 1 to 100", 2);
  const q = argv.join(" ").trim();
  if (!q) die('usage: engine ask search query "<q>" [--kind ask|proof|broadcast] [--limit N] [--json]', 2);
  let db;
  try {
    db = openSearchDb(file, { create: false });
  } catch (e) {
    die(`${(e as Error).message}: run \`engine ask search index\``);
  }
  try {
    const embedder = createLocalEmbeddingClient({ config: { ...resolveEmbedConfig(), timeoutMs: 30_000 } });
    const hits = await search(db!, embedder, { q, limit, kinds: kinds as Kind[] });
    if (json) process.stdout.write(`${JSON.stringify(hits)}\n`);
    else
      for (const h of hits) {
        process.stdout.write(`${h.score.toFixed(3)}  ${h.kind.padEnd(9)} ${h.seat ? `${h.seat}  ` : ""}${h.id}  [${h.status}]\n       ${h.title}\n       § ${h.section}\n       ${h.excerpt}\n       ${h.url ?? "(not published: no URL)"}\n`);
      }
  } catch (e) {
    if (e instanceof SearchUnavailable) die(`${e.message} (${e.reason})`);
    throw e;
  } finally {
    db!.close();
  }
} else if (sub === "status") {
  let db;
  try {
    db = openSearchDb(file, { create: false });
  } catch (e) {
    die((e as Error).message);
  }
  const s = indexState(db!);
  db!.close();
  if (json) process.stdout.write(`${JSON.stringify({ file, ...s })}\n`);
  else process.stdout.write(`index: ${file}\nlast full pass: ${s.indexedAt ?? "never"}\nitems: ${s.items}, chunks: ${s.chunks}\nlast report: ${JSON.stringify(s.lastReport)}\n`);
} else {
  die('usage: engine ask search index [--full] | query "<q>" [--kind ask|proof|broadcast] [--limit N] | status   (each takes --json)', 2);
}
