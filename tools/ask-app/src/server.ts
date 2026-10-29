/**
 * The ask-app server: serves the built React client from dist/ and a small JSON API over the asks
 * root. Binds 127.0.0.1 only; no auth, no database — the files are the state.
 *
 *   GET  /api/health   {app, root, pid, port}
 *   GET  /api/asks     every ask under the root, all statuses
 *   GET  /api/events   server-sent events: "change" whenever a file under the root changes
 *   POST /api/answer   {seat, id, expectedRevision, answers | decline: reason, note?}
 *                      → 200 written + pushed · 400 invalid/empty · 409 stale revision (+ current answer)
 *   POST /api/draft    same body as /api/answer → the answer is saved IN THE FILE as a draft; nothing pushed
 *   POST /api/discard  {seat, id} → the operator's draft is removed (404 when there is no such ask)
 *   POST /api/send     {refs?: ["seat/id", …]} → every named draft (the operator's own drafts when refs
 *                      is absent) is settled from its file and ONE message per recipient seat is pushed. The body's
 *                      refs are the only input: answers in the body are never read (the file is the record).
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
import { answerAsk, defaultAskRoot, discardDraft, listAsks, resolveAskPath, saveDraft, sendBatch } from "./lib/store.ts";
import { loadLinearKey, makeTicketFetcher, TICKET_KEY_RE, TicketNotFound } from "./lib/linear.ts";
import { AskFormatError, parseAskFile, StaleRevisionError } from "./lib/format.ts";
import { computeBuildId, recordedBuildId } from "./build-id.ts";

const args = process.argv.slice(2);
const arg = (name: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};
const root = path.resolve(arg("root") || defaultAskRoot());
const port = Number(arg("port") || 4977);
const token = arg("token") || randomBytes(24).toString("hex");
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

const clients = new Set<http.ServerResponse>();
let pending: NodeJS.Timeout | undefined;
fs.watch(root, { recursive: true }, (_ev, name) => {
  if (name && (String(name).endsWith(".tmp") || String(name).startsWith(".ask-app"))) return;
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
    if (url.pathname === "/api/asks") return send(res, 200, { root, asks: listAsks(root) });
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
    if (req.method === "POST" && ["/api/answer", "/api/draft", "/api/discard", "/api/send"].includes(url.pathname)) {
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
