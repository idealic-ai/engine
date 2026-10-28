/**
 * The ask-app server: serves the built React client from dist/ and a small JSON API over the asks
 * root. Binds 127.0.0.1 only; no auth, no database — the files are the state.
 *
 *   GET  /api/health   {app, root, pid, port}
 *   GET  /api/asks     every ask under the root, all statuses
 *   GET  /api/events   server-sent events: "change" whenever a file under the root changes
 *   POST /api/answer   {seat, id, expectedRevision, answers | decline: reason, note?}
 *                      → 200 written + pushed · 400 invalid/empty · 409 stale revision (+ current answer)
 *
 * No accounts, but not open to the web (MF-1): every route requires Host to be this loopback origin
 * (defeats DNS rebinding); a POST requires Content-Type application/json (forces a CORS preflight), an
 * Origin that is absent or this origin, and the per-serve token the server writes into the page it
 * serves (`<meta name="ask-token">`). The answerer is stamped by the server, never taken from the body.
 *
 * Usage: node src/server.ts --root <asks dir> --port <port> [--token <t>]
 */
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";
import { answerAsk, defaultAskRoot, listAsks, resolveAskPath } from "./lib/store.ts";
import { AskFormatError, parseAskFile, StaleRevisionError } from "./lib/format.ts";

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
const dist = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist");

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

function send(res: http.ServerResponse, code: number, body: unknown) {
  res.writeHead(code, { "content-type": "application/json" });
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
    if (url.pathname === "/api/health") return send(res, 200, { app: "ask-app", root, pid: process.pid, port });
    if (url.pathname === "/api/asks") return send(res, 200, { root, asks: listAsks(root) });
    if (url.pathname === "/api/events") {
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
      res.write("event: hello\ndata: 0\n\n");
      clients.add(res);
      req.on("close", () => clients.delete(res));
      return;
    }
    if (url.pathname === "/api/answer" && req.method === "POST") {
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
      if (typeof b.seat !== "string" || typeof b.id !== "string") return send(res, 400, { error: "seat and id are required" });
      const input =
        b.decline !== undefined
          ? { declined: true, reason: String(b.decline), answeredBy: "operator" }
          : { answers: b.answers as never, answeredBy: "operator" };
      try {
        const out = await answerAsk(root, b.seat, b.id, { ...input, ...(b.note ? { note: String(b.note) } : {}) }, { expectedRevision: Number(b.expectedRevision) });
        return send(res, 200, out);
      } catch (e) {
        if (e instanceof StaleRevisionError) {
          const cur = parseAskFile(fs.readFileSync(resolveAskPath(root, b.seat, b.id), "utf8"));
          return send(res, 409, { error: e.message, revision: e.current, status: cur.header.status, answer: cur.answer });
        }
        if (e instanceof AskFormatError) return send(res, 400, { error: e.message });
        throw e;
      }
    }
    if (url.pathname.startsWith("/api/")) return send(res, 404, { error: "no such endpoint" });

    const rel = url.pathname === "/" ? "index.html" : decodeURIComponent(url.pathname).replace(/^\/+/, "");
    let file = path.resolve(dist, rel);
    if (!file.startsWith(dist + path.sep) || !fs.existsSync(file)) file = path.join(dist, "index.html");
    if (!fs.existsSync(file)) {
      res.writeHead(503, { "content-type": "text/plain" });
      return res.end("ask-app client is not built: run `npm run build` in engine/tools/ask-app\n");
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
