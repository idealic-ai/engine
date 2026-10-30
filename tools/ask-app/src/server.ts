/**
 * The ask-app server: serves the built React client from dist/ and a small JSON API over the asks
 * root. Binds 127.0.0.1 only; no auth, no database — the files are the state.
 *
 *   GET  /api/health   {app, root, pid, port}
 *   GET  /api/asks     every ask under the root, all statuses; each with `history`, its replaced answers and
 *                      (ASKFOLLOWUP) its follow-ups as `{type: "followup", …}`, oldest first
 *                      and, on a withdrawn ask whose draft was set aside, `withdrawnDraft` (that draft, parsed)
 *   GET  /api/proofs   (token required) published proof pages in the local proof store, newest first
 *                      (?fresh skips the cache, and joins a listing already running rather than starting one)
 *   GET  /api/broadcasts  (token required) broadcasts newest first, with acks; read-only, BROADCAST_DIR overrides the dir
 *   GET  /api/search   (token required) ?q=<text>&limit=<1-100, default 20>&kind=<ask|proof|broadcast[,…]> → 200
 *                      [{kind, seat, id, title, status, score, excerpt, url, appPath, section}], best first, one per
 *                      item (IDE-334). Semantic: the query is embedded by the local model and compared with the index
 *                      of asks (all statuses, cut by fork), broadcasts and proof pages (src/search/). Headers
 *                      x-search-indexed-at (the last full pass) and x-search-refreshing (1 when a pass runs).
 *                      → 400 bad q, limit or kind · 503 {error, reason, code?} when it cannot answer: reason
 *                      index-missing | index-empty | index-error | embedder-unavailable. Never an empty 200 for a failure.
 *                      A search finding the index older than ASK_SEARCH_STALE_MS starts a pass behind its answer.
 *   GET  /api/search/status  (token required) {indexedAt, items, chunks, running, lastReport}
 *   GET  /api/events   server-sent events: "change" whenever a file under the root changes
 *   POST /api/answer   {seat, id, expectedRevision, answers | decline: reason, note?}  (a `grantClass` is refused: 400)
 *                      → 200 written + pushed · 400 invalid/empty · 409 stale revision (+ current answer)
 *                        · 409 superseded ({ error, status: "superseded", supersededBy: "<seat>/<id>" })
 *                        · 409 withdrawn ({ error, status: "withdrawn", withdrawnBy, withdrawnAt, withdrawnReason })
 *                        · 409 answered-by-operator ({ error, status: "answered-by-operator", answeredAt, answeredBy }):
 *                          a seat over the operator's answer (OVEROP; the browser answers as the operator, so
 *                          only a non-operator caller reaches it)
 *   POST /api/draft    same body as /api/answer → the answer is saved IN THE FILE as a draft; nothing pushed
 *   POST /api/discard  {seat, id} → the operator's draft is removed (404 when there is no such ask)
 *   POST /api/followup {seat, id, expectedRevision, kind: "question"|"first", fork?, text, picks?} → a follow-up
 *                      to the asker, stamped `by` the server's answerer (never the body's); the ask stays open
 *                      → 200 {revision, followup: {n, at, by, kind, fork, text, picks}, delivery} · 400 empty text,
 *                        unknown kind or fork · 409 stale revision (+ current revision) or a closed ask (+ status;
 *                        a superseded or withdrawn ask carries the same fields as /api/answer's 409)
 *   POST /api/send     {refs?: ["seat/id", …]} → every named draft (the operator's own drafts when refs
 *                      is absent) is settled from its file and ONE message per recipient seat is pushed. The body's
 *                      refs are the only input: answers in the body are never read (the file is the record).
 *                      Each `refused[]` entry is {ref, error}; a withdrawn or superseded ask's also carries the
 *                      409's fields (status + withdrawnBy/At/Reason, or supersededBy), so no reader parses `error`.
 *   GET  /api/ticket/:key  (token required) → {key,title,status,statusType,statusSince,assignee,summary,url},
 *                      fetched from Linear by this server. The Linear key is read from LINEAR_API_KEY or
 *                      the env file named by ASK_LINEAR_ENV, never argv, and never written to a response.
 *
 * No accounts, but not open to the web (MF-1): every route requires Host to be this loopback origin
 * (defeats DNS rebinding); a POST requires Content-Type application/json (forces a CORS preflight), an
 * Origin that is absent or this origin, and the per-serve token the server writes into the page it
 * serves (`<meta name="ask-token">`). The answerer is stamped by the server, never taken from the body.
 * That token is in the page, so any process of the same user that can fetch the page can write: the
 * stamp `answeredBy: operator, answeredVia: browser` records how the identity was claimed, and guards
 * against honest mistakes, not against a hostile local process (M3).
 *
 * A 4xx or 5xx body never carries an absolute path (N2). ASK_APP_DIST names the built client to serve
 * (default: dist/ beside this app), so a test or a scratch build never touches the live one.
 *
 * Usage: node src/server.ts --root <asks dir> --port <port> [--token <t>]
 */
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";
import { answerAsk, defaultAskRoot, discardDraft, followupAsk, listAsks, resolveAskPath, saveDraft, sendBatch } from "./lib/store.ts";
import { loadLinearKey, makeTicketFetcher, TICKET_KEY_RE, TicketNotFound } from "./lib/linear.ts";
import { AnsweredByOperatorError, AskFormatError, dialogueHistory, FollowupClosedError, parseAskFile, StaleRevisionError, SupersededError, WithdrawnError } from "./lib/format.ts";
import { computeBuildId, recordedBuildId } from "./build-id.ts";
import { listProofs } from "./lib/proofs.ts";
import { listBroadcasts } from "./lib/broadcasts.ts";
import { createLocalEmbeddingClient, INDEXER_EMBED_RETRY, resolveEmbedConfig } from "../../embed-local/src/index.ts";
import { openSearchDb, searchDbPath, type SearchDb } from "./search/db.ts";
import { createRefresher, type Refresher } from "./search/refresher.ts";
import { askSource, defaultSources, KINDS, type Kind } from "./search/sources.ts";
import { indexState, search, SearchUnavailable } from "./search/query.ts";

const args = process.argv.slice(2);
const arg = (name: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};
const root = path.resolve(arg("root") || defaultAskRoot());
const port = Number(arg("port") || 4977);
const token = arg("token") || stableToken(path.join(root, ".ask-app.token"));

/**
 * The page token outlives a restart: it is kept in <root>/.ask-app.token (mode 600) and reused, so a
 * tab opened before a deploy can still send, and unsent picks are not lost to a forced reload.
 */
function stableToken(file: string): string {
  try {
    const t = fs.readFileSync(file, "utf8").trim();
    if (/^[0-9a-f]{48}$/.test(t)) return t;
  } catch {}
  const t = randomBytes(24).toString("hex");
  fs.writeFileSync(file, t + "\n", { mode: 0o600 });
  return t;
}
const ORIGINS = [`http://127.0.0.1:${port}`, `http://localhost:${port}`];
const HOSTS = [`127.0.0.1:${port}`, `localhost:${port}`];
const tickets = makeTicketFetcher({ apiKey: loadLinearKey(), endpoint: process.env.ASK_LINEAR_ENDPOINT });
delete process.env.LINEAR_API_KEY; // nothing this process spawns inherits it
/** R4: the one identity this server can establish — whoever holds the page's token on loopback. */
const ANSWERER = { answeredBy: "operator", answeredVia: "browser" };
const dist = path.resolve(process.env.ASK_APP_DIST || path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist"));

/**
 * S9 (round 2): the one client this server will serve is the one its own sources build. A dist with
 * no `.build-id` (a v1 build) or another id is refused with a 503 that says so, never served silently.
 */
// Pinned at START (K1): a client rebuilt from sources edited after this server started is not this
// server's client. ASK_BUILD_SRC (a test seam) names an app directory to hash instead of this one.
const BUILD_ID = computeBuildId(process.env.ASK_BUILD_SRC || undefined);

fs.mkdirSync(root, { recursive: true });

/**
 * IDE-334: the search index, opened (or created) at start. A file this code cannot read leaves `searchDb`
 * null and /api/search answers 503 index-error; the rest of the app is unaffected.
 */
const searchFile = searchDbPath(root);
let searchDb: SearchDb | null = null;
let searchDbError = "";
let refresher: Refresher | null = null;
// A query fails fast; an indexing pass retries a busy runner (embed-local README).
const queryEmbedder = createLocalEmbeddingClient({ config: { ...resolveEmbedConfig(), timeoutMs: Number(process.env.ASK_SEARCH_QUERY_TIMEOUT_MS || 10_000) } });
try {
  searchDb = openSearchDb(searchFile);
  refresher = createRefresher({
    db: searchDb,
    dbFile: searchFile,
    sources: () => defaultSources(root),
    askSources: () => [askSource(root)],
    embedder: createLocalEmbeddingClient({ retry: INDEXER_EMBED_RETRY }),
    log: (line) => process.stdout.write(`${line}\n`),
  });
  if (process.env.ASK_SEARCH_AUTO !== "0") void refresher.start();
} catch (e) {
  searchDbError = (e as Error).message;
  process.stderr.write(`ask-app: search index unavailable: ${searchDbError}\n`);
}

const clients = new Set<http.ServerResponse>();
let pending: NodeJS.Timeout | undefined;
fs.watch(root, { recursive: true }, (_ev, name) => {
  if (name && (String(name).endsWith(".tmp") || String(name).startsWith(".ask-app"))) return;
  if (name && String(name).endsWith(".md") && process.env.ASK_SEARCH_AUTO !== "0") refresher?.asksChanged();
  clearTimeout(pending);
  pending = setTimeout(() => {
    for (const c of clients) c.write(`event: change\ndata: ${Date.now()}\n\n`);
  }, 100);
});

const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".css": "text/css",
  ".svg": "image/svg+xml",
  ".json": "application/json",
};

/** N2: an error message names an ask by seat/id, never by where it sits on this disk. */
function scrub(msg: string): string {
  return msg.split(root).join("<root>").split(dist).join("<dist>").replace(/(^|[\s:'"(=])\/[^\s'"),]+/g, "$1<path>");
}

function send(res: http.ServerResponse, code: number, body: unknown) {
  res.writeHead(code, { "content-type": "application/json" });
  if (code >= 400 && body && typeof body === "object" && typeof (body as { error?: unknown }).error === "string") {
    body = { ...(body as object), error: scrub((body as { error: string }).error) };
  }
  res.end(JSON.stringify(body));
}

function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => {
      data += c;
      if (data.length > 1_000_000) reject(new Error("body too large"));
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", "http://127.0.0.1");
  if (!HOSTS.includes(String(req.headers.host ?? ""))) return send(res, 403, { error: "bad host" });
  try {
    if (url.pathname === "/api/health") return send(res, 200, { app: "ask-app", root, pid: process.pid, port, tickets: tickets.enabled, build: BUILD_ID });
    if (url.pathname === "/api/asks") return send(res, 200, { root, asks: listAsks(root).map((a) => ({ ...a, history: dialogueHistory(a) })) });
    // The published proof pages in the local MinIO store, read-only (ported from the ASKDESIGN prototype).
    // SF-6: a listing spawns bash + aws, so it is gated like /api/broadcasts: GET only, the page's token,
    // and no foreign Origin. Any other method falls through to the 404 below.
    if (url.pathname === "/api/proofs" && req.method === "GET") {
      const origin = req.headers.origin;
      if (origin !== undefined && !ORIGINS.includes(origin)) return send(res, 403, { error: "cross-origin read refused" });
      if (req.headers["x-ask-token"] !== token) return send(res, 403, { error: "missing or wrong ask token" });
      return send(res, 200, await listProofs(url.searchParams.has("fresh")));
    }
    // Broadcasts, read-only: the director's notices and which seats acked them. Token-checked like /api/ticket/.
    if (url.pathname === "/api/broadcasts" && req.method === "GET") {
      if (req.headers["x-ask-token"] !== token) return send(res, 403, { error: "missing or wrong ask token" });
      return send(res, 200, { broadcasts: listBroadcasts() });
    }
    // IDE-334: semantic search over asks, broadcasts and proofs. Gated like /api/proofs: GET, the page's
    // token, no foreign Origin (a query costs an embedding, and the index holds every ask's text).
    if ((url.pathname === "/api/search" || url.pathname === "/api/search/status") && req.method === "GET") {
      const origin = req.headers.origin;
      if (origin !== undefined && !ORIGINS.includes(origin)) return send(res, 403, { error: "cross-origin read refused" });
      if (req.headers["x-ask-token"] !== token) return send(res, 403, { error: "missing or wrong ask token" });
      if (!searchDb || !refresher) return send(res, 503, { error: `the search index cannot be opened: ${searchDbError}`, reason: "index-error" });
      if (url.pathname === "/api/search/status") return send(res, 200, { ...indexState(searchDb), running: refresher.state().running, lastAttemptAt: refresher.state().lastAttemptAt });
      const q = (url.searchParams.get("q") ?? "").trim();
      if (!q) return send(res, 400, { error: "q is required" });
      if (q.length > 500) return send(res, 400, { error: "q is longer than 500 characters" });
      const rawLimit = url.searchParams.get("limit");
      const limit = rawLimit === null || rawLimit === "" ? 20 : Number(rawLimit);
      if (!Number.isInteger(limit) || limit < 1 || limit > 100) return send(res, 400, { error: "limit must be a whole number from 1 to 100" });
      const kinds = (url.searchParams.get("kind") ?? "").split(",").map((k) => k.trim()).filter(Boolean);
      const bad = kinds.filter((k) => !KINDS.includes(k as Kind));
      if (bad.length) return send(res, 400, { error: `unknown kind ${bad.join(", ")}: one of ${KINDS.join(", ")}` });
      refresher.ensureFresh();
      const st = refresher.state();
      try {
        const hits = await search(searchDb, queryEmbedder, { q, limit, kinds: kinds as Kind[] });
        res.setHeader("x-search-indexed-at", st.indexedAt ?? "");
        res.setHeader("x-search-refreshing", refresher.state().running ? "1" : "0");
        return send(res, 200, hits);
      } catch (e) {
        if (e instanceof SearchUnavailable) {
          return send(res, 503, { error: e.message, reason: e.reason, ...(e.code ? { code: e.code } : {}), indexing: refresher.state().running !== null });
        }
        throw e;
      }
    }
    if (url.pathname === "/api/events") {
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
      res.write("event: hello\ndata: 0\n\n");
      clients.add(res);
      req.on("close", () => clients.delete(res));
      return;
    }
    if (url.pathname.startsWith("/api/ticket/") && req.method === "GET") {
      if (req.headers["x-ask-token"] !== token) return send(res, 403, { error: "missing or wrong ask token" });
      let key = "";
      try {
        key = decodeURIComponent(url.pathname.slice("/api/ticket/".length));
      } catch {
        return send(res, 400, { error: "not a ticket key" });
      }
      if (!TICKET_KEY_RE.test(key)) return send(res, 400, { error: "not a ticket key" });
      if (!tickets.enabled) return send(res, 503, { error: "no Linear key configured on the server" });
      try {
        return send(res, 200, await tickets.get(key));
      } catch (e) {
        if (e instanceof TicketNotFound) return send(res, 404, { error: `no ticket ${key}` });
        return send(res, 502, { error: "Linear lookup failed" });
      }
    }
    if (req.method === "POST" && ["/api/answer", "/api/draft", "/api/discard", "/api/send", "/api/followup"].includes(url.pathname)) {
      if (!String(req.headers["content-type"] ?? "").startsWith("application/json")) return send(res, 415, { error: "content-type must be application/json" });
      const origin = req.headers.origin;
      if (origin !== undefined && !ORIGINS.includes(origin)) return send(res, 403, { error: "cross-origin write refused" });
      if (req.headers["x-ask-token"] !== token) return send(res, 403, { error: "missing or wrong ask token" });
      let b: Record<string, unknown>;
      try {
        b = JSON.parse(await readBody(req));
      } catch {
        return send(res, 400, { error: "body is not JSON" });
      }
      if (b === null || typeof b !== "object") return send(res, 400, { error: "body must be an object" });
      if (url.pathname === "/api/send") {
        // Refs only. Whatever else the body says is ignored: the batch is read from the files.
        if (b.refs !== undefined && (!Array.isArray(b.refs) || b.refs.some((r) => typeof r !== "string"))) return send(res, 400, { error: "refs must be a list of seat/id strings" });
        return send(res, 200, await sendBatch(root, b.refs as string[] | undefined, { by: ANSWERER.answeredBy }));
      }
      if (typeof b.seat !== "string" || typeof b.id !== "string") return send(res, 400, { error: "seat and id are required" });
      if (url.pathname === "/api/discard") {
        try {
          await discardDraft(root, b.seat, b.id, ANSWERER.answeredBy);
          return send(res, 200, { ok: true });
        } catch (e) {
          if (e instanceof AskFormatError) return send(res, 400, { error: e.message });
          if ((e as NodeJS.ErrnoException).code === "ENOENT") return send(res, 404, { error: "no such ask" });
          throw e;
        }
      }
      if (url.pathname === "/api/followup") {
        // ASKFOLLOWUP: `by` and `via` are the server's (R4); whatever the body says about them is ignored.
        try {
          const out = await followupAsk(
            root,
            b.seat,
            b.id,
            { by: ANSWERER.answeredBy, via: ANSWERER.answeredVia, kind: b.kind as never, ...(b.fork !== undefined ? { fork: b.fork as string } : {}), text: b.text as string, ...(b.picks !== undefined ? { picks: b.picks as never } : {}) },
            { expectedRevision: Number(b.expectedRevision) },
          );
          return send(res, 200, { revision: out.revision, followup: out.followup, delivery: out.delivery });
        } catch (e) {
          // SHOULD-3 (round 2): the same 409 payloads as /api/answer for a replaced or withdrawn ask.
          if (e instanceof SupersededError) return send(res, 409, { error: e.message, status: "superseded", supersededBy: e.by });
          if (e instanceof WithdrawnError) return send(res, 409, { error: e.message, status: "withdrawn", withdrawnBy: e.actor, withdrawnAt: e.at, withdrawnReason: e.reason });
          if (e instanceof FollowupClosedError) return send(res, 409, { error: e.message, status: e.status });
          if (e instanceof StaleRevisionError) return send(res, 409, { error: e.message, revision: e.current });
          if (e instanceof AskFormatError) return send(res, 400, { error: e.message });
          if ((e as NodeJS.ErrnoException).code === "ENOENT") return send(res, 404, { error: "no such ask" });
          throw e;
        }
      }
      // IDE-339: a grant class is the answering manager's, written from the CLI; the browser is the
      // operator, whose answer never carries one. Refused, not dropped, so a client that sends one learns.
      if (b.grantClass !== undefined) return send(res, 400, { error: "a grant class is never written from the browser: the answering manager writes it with `engine ask answer --grant`" });
      // NEW-3: a decline's reason is a string; null, false or an object is not a reason.
      if (b.decline !== undefined && typeof b.decline !== "string") return send(res, 400, { error: "decline must be a non-empty string reason" });
      const input =
        b.decline !== undefined
          ? { declined: true, reason: b.decline as string, ...ANSWERER }
          : { answers: b.answers as never, ...ANSWERER };
      const withNote = { ...input, ...(typeof b.note === "string" && b.note.trim() ? { note: b.note } : {}) };
      try {
        if (url.pathname === "/api/draft") {
          const file = await saveDraft(root, b.seat, b.id, withNote, Number(b.expectedRevision));
          return send(res, 200, { file, draft: true });
        }
        const out = await answerAsk(root, b.seat, b.id, withNote, { expectedRevision: Number(b.expectedRevision) });
        return send(res, 200, out);
      } catch (e) {
        // The ask was replaced: 409, naming the replacement, so the client can link to it.
        if (e instanceof SupersededError) return send(res, 409, { error: e.message, status: "superseded", supersededBy: e.by });
        // ASKWITHDRAW: the asker took it back; 409 with who, when and why, and no replacement to name.
        if (e instanceof WithdrawnError) return send(res, 409, { error: e.message, status: "withdrawn", withdrawnBy: e.actor, withdrawnAt: e.at, withdrawnReason: e.reason });
        // OVEROP: a seat over the operator's answer; 409 naming whose answer stands and since when.
        if (e instanceof AnsweredByOperatorError) return send(res, 409, { error: e.message, status: "answered-by-operator", answeredAt: e.answeredAt, answeredBy: e.answeredBy });
        if (e instanceof StaleRevisionError) {
          const cur = parseAskFile(fs.readFileSync(resolveAskPath(root, b.seat, b.id), "utf8"));
          return send(res, 409, { error: e.message, revision: e.current, status: cur.header.status, answer: cur.answer });
        }
        if (e instanceof AskFormatError) return send(res, 400, { error: e.message });
        if ((e as NodeJS.ErrnoException).code === "ENOENT") return send(res, 404, { error: "no such ask" });
        throw e;
      }
    }
    if (url.pathname.startsWith("/api/")) return send(res, 404, { error: "no such endpoint" });

    let rel = "index.html";
    try {
      if (url.pathname !== "/") rel = decodeURIComponent(url.pathname).replace(/^\/+/, "");
    } catch {
      // a malformed escape is not a file; the page is served instead
    }
    let file = path.resolve(dist, rel);
    if (!file.startsWith(dist + path.sep) || !fs.existsSync(file)) file = path.join(dist, "index.html");
    if (!fs.existsSync(file)) {
      res.writeHead(503, { "content-type": "text/plain" });
      return res.end("ask-app client is not built: `engine ask serve` builds it (into ASK_APP_DIST)\n");
    }
    const built = recordedBuildId(dist);
    if (built !== BUILD_ID) {
      res.writeHead(503, { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" });
      return res.end(
        `ask-app client build mismatch: the built client is ${built ? `build ${built}` : "an unstamped (v1 or hand-made) build"}, and this server serves only build ${BUILD_ID}, the one its sources make.\n` +
          "Restart through `engine ask serve` (it rebuilds the client when the ids differ), or build it with `vite build --outDir <ASK_APP_DIST>`.\n",
      );
    }
    if (file.endsWith("index.html")) {
      const html = fs.readFileSync(file, "utf8").replace("<head>", `<head>\n    <meta name="ask-token" content="${token}">`);
      res.writeHead(200, { "content-type": TYPES[".html"], "cache-control": "no-store" });
      return res.end(html);
    }
    res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream" });
    fs.createReadStream(file).pipe(res);
  } catch (e) {
    send(res, 500, { error: (e as Error).message });
  }
});

server.on("error", (e) => {
  process.stderr.write(`ask-app: ${(e as Error).message}\n`);
  process.exit(1);
});
server.listen(port, "127.0.0.1", () => {
  process.stdout.write(`ask-app listening on http://127.0.0.1:${port}/ root=${root}\n`);
});
