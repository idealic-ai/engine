/**
 * ASKDESIGN prototype: list the proof pages published to the local MinIO proofs store, read-only.
 * The endpoint, bucket and prefix come from the /prove skill's own resolver
 * (skills/prove/assets/_prove-s3-env.sh), sourced in a child bash; listing is `aws s3api
 * list-objects-v2` (signed, since the bucket refuses anonymous listing). Titles are read from the
 * first 6 KB of the newest pages over the public URL. Nothing is written anywhere.
 */
import { execFile } from "node:child_process";
import os from "node:os";
import path from "node:path";

export type Proof = { key: string; url: string; title: string; owner: string; slug: string; modified: string; size: number };
export type ProofList = { ok: boolean; endpoint?: string; bucket?: string; prefix?: string; proofs: Proof[]; error?: string; at: string; total: number };

const ENV = process.env.ASK_PROVE_ENV_SH || path.join(os.homedir(), ".claude", "engine", "skills", "prove", "assets", "_prove-s3-env.sh");
const SCRIPT = `. "$1" >/dev/null 2>&1 || exit 3
printf '%s\\n%s\\n%s\\n%s\\n' "$PROVE_S3_ENDPOINT_URL" "$PROVE_S3_PUBLIC_URL" "$PROVE_S3_BUCKET" "\${PROVE_S3_PREFIX:-proofs}"
aws "\${ENDPOINT_ARG[@]}" "\${PROFILE_ARG[@]}" s3api list-objects-v2 --bucket "$PROVE_S3_BUCKET" --prefix "\${PROVE_S3_PREFIX:-proofs}/" --output json --cli-read-timeout 8 --cli-connect-timeout 3`;

let cache: { at: number; value: ProofList } | undefined;
const titles = new Map<string, string>();

/**
 * NIT-B1: a failure is reported by a fixed message and its exit code, never by the child's text. That
 * text ends with the argv (the env script's absolute path) and would reach the page in a 200 body.
 */
function run(): Promise<string> {
  return new Promise((resolve, reject) =>
    execFile("bash", ["-c", SCRIPT, "proofs", ENV], { maxBuffer: 64 * 1024 * 1024, timeout: 20_000 }, (e, out) => {
      if (!e) return resolve(out);
      const x = e as Error & { code?: number | string; killed?: boolean };
      const why = x.killed ? "timed out" : x.code === 3 ? "its settings could not be read" : `exit ${x.code ?? "?"}`;
      reject(new Error(`proof store not reachable (${why})`));
    }),
  );
}

const SKIP = /\/(state|events|assets?)\//;
function humanTitle(slug: string): string {
  return slug.replace(/\.html$/, "").replace(/-[0-9a-f]{8}$/, "").replace(/-\d{8}-\d{4}$/, "").replace(/[-_]+/g, " ").trim();
}

async function readTitle(url: string): Promise<string | undefined> {
  if (titles.has(url)) return titles.get(url);
  try {
    const r = await fetch(url, { headers: { range: "bytes=0-6143" }, signal: AbortSignal.timeout(3000) });
    const m = (await r.text()).match(/<title[^>]*>([^<]{1,200})<\/title>/i);
    const t = m?.[1].replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#39;|&apos;/g, "'").replace(/&quot;/g, '"').trim();
    if (t) titles.set(url, t);
    return t;
  } catch {
    return undefined;
  }
}

let refreshing: Promise<ProofList> | undefined;
/** One listing at a time: every caller that wants a new one joins the one already running (SF-6). */
function refresh(): Promise<ProofList> {
  if (!refreshing) refreshing = fetchProofs().finally(() => (refreshing = undefined));
  return refreshing;
}
/** Stale-while-revalidate: a cached list answers at once and refreshes behind the response. `fresh` waits for a new one. */
export async function listProofs(fresh = false): Promise<ProofList> {
  if (!fresh && cache) {
    if (Date.now() - cache.at >= 60_000) void refresh();
    return cache.value;
  }
  return refresh();
}

async function fetchProofs(): Promise<ProofList> {
  const at = new Date().toISOString();
  let value: ProofList;
  try {
    const out = await run();
    const [endpoint, publicBase, bucket, prefix, ...json] = out.split("\n");
    const objs = (JSON.parse(json.join("\n") || "{}").Contents ?? []) as { Key: string; LastModified: string; Size: number }[];
    const pages = objs
      .filter((o) => o.Key.endsWith(".html") && !SKIP.test(o.Key))
      .sort((a, b) => b.LastModified.localeCompare(a.LastModified));
    const proofs: Proof[] = pages.map((o) => {
      const parts = o.Key.slice(prefix.length + 1).split("/");
      const owner = parts.length > 1 ? parts[0] : "";
      const file = parts[parts.length - 1];
      const slug = file === "index.html" && parts.length > 1 ? parts[parts.length - 2] : file;
      const url = `${publicBase.replace(/\/$/, "")}/${bucket}/${o.Key.split("/").map(encodeURIComponent).join("/")}`;
      return { key: o.Key, url, owner, slug, title: humanTitle(slug), modified: o.LastModified, size: o.Size };
    });
    // Real titles for the newest pages, a few at a time; older pages keep the slug-derived title.
    const head = proofs.slice(0, 120);
    for (let i = 0; i < head.length; i += 12) {
      await Promise.all(head.slice(i, i + 12).map(async (p) => { p.title = (await readTitle(p.url)) ?? p.title; }));
    }
    for (const p of proofs.slice(120)) p.title = titles.get(p.url) ?? p.title;
    value = { ok: true, endpoint, bucket, prefix, proofs, at, total: proofs.length };
  } catch (e) {
    value = { ok: false, proofs: [], error: (e as Error).message, at, total: 0 };
  }
  cache = { at: Date.now(), value };
  return value;
}
