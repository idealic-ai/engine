/**
 * Broadcasts, read-only: the director's notices to seats, as the ask app shows them. Each is
 * `<dir>/<id>.md` (a `key: value` header, then `## Text` and `## Delivery`), with acks as one file
 * per seat in `<dir>/<id>.acks.d/`. The directory is BROADCAST_DIR, else ~/.claude/data/yarik/broadcasts.
 * Nothing here writes.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export type Broadcast = {
  id: string;
  from: string;
  at: string;
  audience: string[];
  text: string;
  acks: string[];
  sticky: boolean;
  expires: string;
  /** Sticky, or an `expires:` still in the future. */
  inForce: boolean;
};

export const defaultBroadcastDir = () => process.env.BROADCAST_DIR || path.join(os.homedir(), ".claude", "data", "yarik", "broadcasts");

/** One broadcast file's fields; `## Text` runs to the next `## ` heading. The delivery log is not read. */
export function parseBroadcast(id: string, text: string, acks: string[], now = Date.now()): Broadcast {
  const field = (k: string) => text.match(new RegExp(`^${k}:[ \\t]*(.*)$`, "m"))?.[1].trim() ?? "";
  const body = text.match(/^## Text[ \t]*\n([\s\S]*?)(?=^## |(?![\s\S]))/m)?.[1].trim() ?? "";
  const sticky = /^(yes|true|on|1)$/i.test(field("sticky"));
  const expires = field("expires");
  const exp = expires && expires !== "-" ? Date.parse(expires) : NaN;
  return {
    id: field("id") || id,
    from: field("from"),
    at: field("at"),
    audience: field("audience").split(/[\s,]+/).filter(Boolean),
    text: body,
    acks,
    sticky,
    expires: expires === "-" ? "" : expires,
    inForce: sticky || (Number.isFinite(exp) && exp > now),
  };
}

/** Every broadcast in `dir`, newest first. A missing directory is an empty list, not an error. */
export function listBroadcasts(dir = defaultBroadcastDir(), now = Date.now()): Broadcast[] {
  let names: string[];
  try {
    names = fs.readdirSync(dir);
  } catch {
    return [];
  }
  const out: Broadcast[] = [];
  for (const n of names) {
    if (!n.endsWith(".md")) continue;
    const id = n.slice(0, -3);
    let text: string;
    try {
      text = fs.readFileSync(path.join(dir, n), "utf8");
    } catch {
      continue;
    }
    let acks: string[] = [];
    try {
      acks = fs.readdirSync(path.join(dir, `${id}.acks.d`)).filter((f) => !f.startsWith(".")).sort();
    } catch {
      /* no acks yet */
    }
    out.push(parseBroadcast(id, text, acks, now));
  }
  return out.sort((a, b) => (Date.parse(b.at) || 0) - (Date.parse(a.at) || 0));
}
