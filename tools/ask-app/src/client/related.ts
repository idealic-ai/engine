/**
 * What the related pane shows for an ask: its brief (a `brief:` header field, or failing that the
 * first proof page the ask links), and the list of proof pages it links anywhere.
 */
import type { ParsedAsk } from "../lib/format.ts";
import { linksIn } from "./md.ts";

export type Brief = { url: string; source: "brief" | "first proof link" };
export type ProofLink = { url: string; label: string };

/** A proof page: a link to the local proof server, a published `/proofs/` path, or an .html page. */
export function isProofUrl(href: string): boolean {
  let u: URL;
  try {
    u = new URL(href);
  } catch {
    return false;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return false;
  return u.port === "9440" || /\/proofs?\//.test(u.pathname) || /\.html?$/.test(u.pathname);
}

/** True when the page lives on this machine's loopback, so it cannot open anywhere else. */
export function isLocalOnly(href: string): boolean {
  try {
    return ["127.0.0.1", "localhost", "[::1]"].includes(new URL(href).hostname);
  } catch {
    return false;
  }
}

/** The ask's text in reading order: header context and evidence, the preamble, then each fork. */
function sources(ask: ParsedAsk): string[] {
  const h = ask.header;
  return [
    h.context ?? "",
    h.evidence ?? "",
    ask.preamble,
    ...ask.questions.flatMap((q) => [q.meta.context ?? "", ...q.evidence, q.prose ?? "", q.proseAfter ?? ""]),
  ];
}

export function proofLinks(ask: ParsedAsk): ProofLink[] {
  const seen = new Map<string, string>();
  for (const s of sources(ask)) {
    for (const l of linksIn(s)) {
      if (!isProofUrl(l.href) || seen.has(l.href)) continue;
      seen.set(l.href, l.label === l.href ? lastSegment(l.href) : l.label);
    }
  }
  return [...seen].map(([url, label]) => ({ url, label }));
}

export function briefFor(ask: ParsedAsk): Brief | undefined {
  const b = ask.header.brief?.trim();
  if (b && /^https?:\/\//i.test(b)) return { url: b, source: "brief" };
  const first = proofLinks(ask)[0];
  return first ? { url: first.url, source: "first proof link" } : undefined;
}

export function lastSegment(href: string): string {
  try {
    const p = new URL(href).pathname.split("/").filter(Boolean);
    return p[p.length - 1] ?? href;
  } catch {
    return href;
  }
}

export type Trust = "auto" | "ask" | "refuse";

/**
 * Whether the pane may open a page on its own (M2):
 * - "refuse": the app's own origin. A framed same-origin page could read the page's ask token.
 * - "auto": loopback, or an origin named as a proof host. It opens and is checked without a click.
 * - "ask": any other host. Nothing is fetched until the operator clicks "Open in pane".
 */
export function paneTrust(href: string, appOrigin: string, proofOrigins: string[] = []): Trust {
  let u: URL;
  try {
    u = new URL(href);
  } catch {
    return "refuse";
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return "refuse";
  if (u.origin === appOrigin) return "refuse";
  if (["127.0.0.1", "localhost", "[::1]"].includes(u.hostname)) return "auto";
  if (proofOrigins.some((o) => o && u.origin === o.replace(/\/+$/, ""))) return "auto";
  return "ask";
}

/** Proof hosts besides loopback, from the build: VITE_PROOF_ORIGINS, comma separated (the PROVE_S3_PUBLIC_BASE origin). */
export function proofOriginsFromEnv(raw: string | undefined): string[] {
  return (raw ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .flatMap((s) => {
      try {
        return [new URL(s).origin];
      } catch {
        return [];
      }
    });
}
