/**
 * ASKLINK: the app URL of an ask, `http://127.0.0.1:<port>/a/<seat>/<id>` — what an agent hands the
 * operator in place of a bare id or a file path.
 *
 * The host and port are the ones `engine ask serve` uses (scripts/ask.sh cmd_serve): it always binds
 * 127.0.0.1, and its port is `--port`, else the port recorded in `<root>/.ask-app.pid` (`pid port`),
 * else 4977. The CLI cannot see a `--port` given to an earlier serve except through that record, so
 * this reads the record and falls back to the same default.
 *
 * The path is the client router's (src/client/route.ts serializeRoute): each segment URI-encoded,
 * with `:` and `@` kept readable, so `/a/domain:stats/<id>` opens that seat's ask by its full id.
 */
import fs from "node:fs";
import path from "node:path";

const DEFAULT_PORT = 4977;

/** One path segment, encoded as the client router writes it. */
const seg = (s: string) => encodeURIComponent(s).replace(/%3A/gi, ":").replace(/%40/g, "@");

/** The app's origin for this asks root: the recorded serve port, else serve's default. */
export function askAppBase(root: string): string {
  let port = DEFAULT_PORT;
  try {
    const p = Number(fs.readFileSync(path.join(root, ".ask-app.pid"), "utf8").trim().split(/\s+/)[1]);
    if (Number.isInteger(p) && p > 0 && p < 65536) port = p;
  } catch {
    // no record: the server has not been started for this root yet
  }
  return `http://127.0.0.1:${port}`;
}

/** The clickable URL that opens one ask in the app. */
export function askUrl(root: string, seat: string, id: string): string {
  return `${askAppBase(root)}/a/${seg(seat)}/${seg(id)}`;
}
