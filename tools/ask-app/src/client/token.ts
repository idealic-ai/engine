/**
 * The page's ask token, and what to do when the server no longer takes it (operator 01:29). The server
 * mints a new token on every start, so a tab opened before a restart holds a dead one and every write
 * came back 403 "missing or wrong ask token". Now a rejected request re-reads the token from a fresh
 * copy of the page and is retried ONCE. If the server now runs a different build, nothing is retried:
 * the operator is told to reload, and the card's picks are kept (see unsent.ts).
 */
export const TOKEN_REJECTED = "missing or wrong ask token";

type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
const realFetch: Fetch = (u, i) => fetch(u, i);

let override: string | undefined;
let loadedBuild: string | undefined;

/** The token to send: the refreshed one once a refresh happened, else the one in this page's meta tag. */
export function askToken(): string {
  if (override !== undefined) return override;
  return typeof document === "undefined" ? "" : document.querySelector('meta[name="ask-token"]')?.getAttribute("content") ?? "";
}

/** Test seam, and the reset for a test: forget the refreshed token and the recorded build. */
export function resetTokenState(token?: string, build?: string) {
  override = token;
  loadedBuild = build;
}

/** The build this tab was loaded with; read once at start from /api/health (it needs no token). */
export async function recordBuild(f: Fetch = realFetch): Promise<string | undefined> {
  if (loadedBuild) return loadedBuild;
  try {
    loadedBuild = (await (await f("/api/health", { cache: "no-store" })).json()).build;
  } catch {
    /* unknown: the first refresh records it */
  }
  return loadedBuild;
}

export type Refresh = { ok: true; token: string } | { ok: false; updated: boolean; reason: string };

/** Fetch the page fresh, read its token, and check the server still runs the build this tab was loaded with. */
export async function refreshToken(f: Fetch = realFetch): Promise<Refresh> {
  try {
    const html = await (await f("/", { cache: "no-store" })).text();
    const token = html.match(/<meta name="ask-token" content="([^"]+)"/)?.[1];
    const build = (await (await f("/api/health", { cache: "no-store" })).json()).build as string | undefined;
    if (loadedBuild && build && build !== loadedBuild) return { ok: false, updated: true, reason: "the app was updated" };
    if (!loadedBuild && build) loadedBuild = build;
    if (!token) return { ok: false, updated: false, reason: "the page carried no token" };
    override = token;
    return { ok: true, token };
  } catch {
    return { ok: false, updated: false, reason: "the app server did not answer" };
  }
}

export type Authed = { status: number; json: any; restarted?: "updated" | "failed" };
export const RELOAD_UPDATED = "The app was updated — reload to continue. Your picks and notes are kept.";
export const RELOAD_RESTARTED = "The app restarted. Reload to continue; your picks are kept.";

const isRejection = (status: number, json: any) => status === 403 && json?.error === TOKEN_REJECTED;

/**
 * A request with the token. On a token rejection: refresh the token, and retry once with it. Before the
 * retry `beforeRetry` runs (the card saves its unsent picks there). `restarted` says why it gave up.
 */
export async function authedFetch(url: string, init: RequestInit = {}, deps: { fetch?: Fetch; beforeRetry?: () => void } = {}): Promise<Authed> {
  const f = deps.fetch ?? realFetch;
  const once = async (): Promise<{ status: number; json: any }> => {
    const r = await f(url, { ...init, headers: { ...(init.headers as Record<string, string> | undefined), "x-ask-token": askToken() } });
    return { status: r.status, json: await r.json().catch(() => ({})) };
  };
  const first = await once();
  if (!isRejection(first.status, first.json)) return first;
  deps.beforeRetry?.();
  const fresh = await refreshToken(f);
  if (!fresh.ok) return { ...first, restarted: fresh.updated ? "updated" : "failed" };
  const second = await once();
  if (isRejection(second.status, second.json)) return { ...second, restarted: "failed" };
  return second;
}
