/**
 * Linked-ticket details for the card's hover tooltip, fetched by the LOCAL
 * SERVER with the Linear API key. The key never leaves this module's caller: it is read from the
 * environment or from an env file, held in a closure, sent only as Linear's Authorization header,
 * and no field of the response is copied through except the whitelist in `TicketInfo`.
 */
import fs from "node:fs";

export type TicketInfo = {
  key: string;
  title: string;
  status: string;
  statusType: string;
  /** When the ticket entered its current state, as near as the API says: started/completed/canceled/created. */
  statusSince: string;
  assignee: string;
  summary: string;
  url: string;
};

export class TicketNotFound extends Error {}

export const TICKET_KEY_RE = /^[A-Z][A-Z0-9]{1,9}-\d{1,6}$/;

/** The key from LINEAR_API_KEY, else from `LINEAR_API_KEY=` in the env file at `envFile`. */
export function loadLinearKey(env: NodeJS.ProcessEnv = process.env): string | undefined {
  if (env.LINEAR_API_KEY?.trim()) return env.LINEAR_API_KEY.trim();
  const file = env.ASK_LINEAR_ENV;
  if (!file) return undefined;
  try {
    for (const line of fs.readFileSync(file, "utf8").split("\n")) {
      const m = line.match(/^\s*(?:export\s+)?LINEAR_API_KEY\s*=\s*(.*)\s*$/);
      if (m) return m[1].replace(/^["']|["']$/g, "").trim() || undefined;
    }
  } catch {
    // no env file: tickets render as plain links
  }
  return undefined;
}

const QUERY = `query AskTicket($id: String!) { issue(id: $id) {
  identifier title url description
  state { name type } assignee { name }
  createdAt updatedAt startedAt completedAt canceledAt
} }`;

/** The first meaningful line of the description, markdown stripped, at most ~200 chars. */
export function summarize(description: string | null | undefined): string {
  const line = (description ?? "")
    .split("\n")
    .map((l) => l.replace(/<[^>]+>/g, "").replace(/[*_`#>]/g, "").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1").trim())
    .find((l) => l.length > 0) ?? "";
  return line.length > 200 ? `${line.slice(0, 197)}…` : line;
}

type Fetch = typeof fetch;

export function makeTicketFetcher(o: { apiKey?: string; endpoint?: string; fetch?: Fetch; ttlMs?: number }) {
  const apiKey = o.apiKey;
  const endpoint = o.endpoint ?? "https://api.linear.app/graphql";
  const doFetch = o.fetch ?? fetch;
  const ttl = o.ttlMs ?? 5 * 60_000;
  const cache = new Map<string, { at: number; info: TicketInfo }>();
  return {
    enabled: !!apiKey,
    async get(key: string): Promise<TicketInfo> {
      if (!TICKET_KEY_RE.test(key)) throw new Error(`not a ticket key: ${key}`);
      if (!apiKey) throw new Error("no Linear key configured on the server");
      const hit = cache.get(key);
      if (hit && Date.now() - hit.at < ttl) return hit.info;
      const r = await doFetch(endpoint, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: apiKey },
        body: JSON.stringify({ query: QUERY, variables: { id: key } }),
        signal: AbortSignal.timeout(5000),
      });
      if (!r.ok) throw new Error(`Linear answered HTTP ${r.status}`);
      const j = (await r.json()) as { data?: { issue?: Record<string, any> | null } };
      const i = j.data?.issue;
      if (!i) throw new TicketNotFound(`no ticket ${key}`);
      const type = String(i.state?.type ?? "");
      const since = (type === "completed" && i.completedAt) || (type === "canceled" && i.canceledAt) || (type === "started" && i.startedAt) || i.createdAt || i.updatedAt || "";
      const info: TicketInfo = {
        key: String(i.identifier ?? key),
        title: String(i.title ?? ""),
        status: String(i.state?.name ?? ""),
        statusType: type,
        statusSince: String(since),
        assignee: String(i.assignee?.name ?? "unassigned"),
        // Redact BEFORE summarize: stripping markdown removes `_`, which would let a mangled key through.
        summary: summarize(String(i.description ?? "").split(apiKey).join("[redacted]")),
        url: String(i.url ?? ""),
      };
      // Belt and braces: whatever Linear echoes, the key itself never goes out in a field.
      for (const k of Object.keys(info) as (keyof TicketInfo)[]) info[k] = info[k].split(apiKey).join("[redacted]");
      cache.set(key, { at: Date.now(), info });
      return info;
    },
  };
}
