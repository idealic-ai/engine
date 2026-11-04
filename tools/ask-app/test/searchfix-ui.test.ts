/**
 * ASKLISTUI: the search client adapted to SEARCHFIX (the server's /api/search contract at the top of
 * src/server.ts). The sidebar asks with a lower floor; an empty 200 means nothing reached the floor;
 * a 503 names its cause first and says whether a pass is building the index; the index age header is
 * absent until the first pass; the floor applied comes back in x-search-min-score.
 */
import { beforeEach, describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { fetchSemantic, SEMANTIC_MIN_SCORE, unavailableNote, type SemanticAnswer, type SemanticState } from "../src/client/semantic.ts";
import { SearchResults } from "../src/client/results.tsx";
import { resetTokenState } from "../src/client/token.ts";
import type { Row } from "../src/client/model.ts";
import type { Hay } from "../src/client/search.ts";

const NOW = Date.parse("2026-10-31T12:00:00.000Z");

function fakeFetch(r: { status: number; body: unknown; headers?: Record<string, string> }) {
  const urls: string[] = [];
  const f = async (url: string) => {
    urls.push(url);
    return new Response(JSON.stringify(r.body), { status: r.status, headers: { "content-type": "application/json", ...(r.headers ?? {}) } });
  };
  return { f, urls };
}
const row = (ref: string): Row & { extra?: Hay } =>
  ({ ref, id: ref.split("/")[1], title: `Row ${ref}`, seat: ref.split("/")[0], topic: "", created: 0, age: "", left: 1, total: 1, high: false, waitingOnYou: true, draftSent: false, draft: false, status: "open", askSeat: ref.split("/")[0], settled: false }) as Row & { extra?: Hay };
const panel = (answer: SemanticAnswer, words: (Row & { extra?: Hay })[] = []) =>
  renderToStaticMarkup(createElement(SearchResults, { state: { phase: "done", answer } as SemanticState, words, selected: -1, now: NOW, terms: ["cache"], onOpen: () => undefined, onHover: () => undefined }));

beforeEach(() => resetTokenState("page-token", "build-1"));

describe("the request", () => {
  it("asks with minScore=0.30, below the server's default floor of 0.40", async () => {
    const { f, urls } = fakeFetch({ status: 200, body: [] });
    await fetchSemantic("cache", { fetch: f });
    expect(SEMANTIC_MIN_SCORE).toBe("0.30");
    expect(urls[0]).toContain("minScore=0.30");
    expect(new URL(urls[0], "http://x").searchParams.get("minScore")).toBe("0.30");
  });
});

describe("an empty 200: nothing reached the floor", () => {
  it("is an answer, not a refusal, and the panel says no matches by meaning while the word matches still show", async () => {
    const { f } = fakeFetch({ status: 200, body: [], headers: { "x-search-indexed-at": "2026-10-31T11:55:00.000Z" } });
    const a = await fetchSemantic("cache", { fetch: f });
    expect(a.ok).toBe(true);
    const html = panel(a, [row("meta:x/a1")]);
    expect(html).toContain("no matches by meaning");
    expect(html).not.toContain("unavailable");
    expect(html).toContain("Row meta:x/a1");
  });
  it("with no word matches either, it still says no matches by meaning", async () => {
    const { f } = fakeFetch({ status: 200, body: [] });
    const html = panel(await fetchSemantic("cache", { fetch: f }));
    expect(html).toContain("no matches by meaning");
  });
});

describe("a 503", () => {
  it.each(["index-error", "embedder-unavailable", "index-empty"])("reason %s is a refusal naming it", async (reason) => {
    const { f } = fakeFetch({ status: 503, body: { error: "x", reason, indexing: false } });
    expect(await fetchSemantic("q", { fetch: f })).toEqual({ ok: false, q: "q", reason, indexing: false });
  });
  it("index-missing is no longer a reason the server sends: it reads as unavailable", async () => {
    const { f } = fakeFetch({ status: 503, body: { error: "x", reason: "index-missing" } });
    expect(await fetchSemantic("q", { fetch: f })).toEqual({ ok: false, q: "q", reason: "unavailable" });
  });
  it("embedder-unavailable carries its code, and the note names it", async () => {
    const { f } = fakeFetch({ status: 503, body: { error: "x", reason: "embedder-unavailable", code: "ECONNREFUSED", indexing: false } });
    const a = await fetchSemantic("q", { fetch: f });
    expect(a).toEqual({ ok: false, q: "q", reason: "embedder-unavailable", code: "ECONNREFUSED", indexing: false });
    expect(panel(a)).toContain("semantic search unavailable: embedder-unavailable (ECONNREFUSED)");
  });
  it("index-empty while a pass runs says the index is being built; without one it is unavailable", async () => {
    const building = await fetchSemantic("q", { fetch: fakeFetch({ status: 503, body: { error: "x", reason: "index-empty", indexing: true } }).f });
    expect(building).toEqual({ ok: false, q: "q", reason: "index-empty", indexing: true });
    expect(panel(building)).toContain("search index is being built");
    expect(panel(building)).not.toContain("unavailable");
    const idle = await fetchSemantic("q", { fetch: fakeFetch({ status: 503, body: { error: "x", reason: "index-empty", indexing: false } }).f });
    expect(panel(idle)).toContain("semantic search unavailable: index-empty");
  });
  it("the note's words", () => {
    expect(unavailableNote("index-empty", { indexing: true })).toBe("search index is being built");
    expect(unavailableNote("index-error", { indexing: true })).toBe("semantic search unavailable: index-error");
    expect(unavailableNote("embedder-unavailable", { code: "E1" })).toBe("semantic search unavailable: embedder-unavailable (E1)");
  });
  it("a code that is not a short plain word is left out", async () => {
    const { f } = fakeFetch({ status: 503, body: { error: "x", reason: "embedder-unavailable", code: "<b>x</b> and a lot more words", indexing: false } });
    expect(await fetchSemantic("q", { fetch: f })).toEqual({ ok: false, q: "q", reason: "embedder-unavailable", indexing: false });
  });
});

describe("headers", () => {
  it("no x-search-indexed-at (before the first pass) reads not indexed yet", async () => {
    const { f } = fakeFetch({ status: 200, body: [], headers: { "x-search-refreshing": "1" } });
    const a = await fetchSemantic("q", { fetch: f });
    expect(a).toMatchObject({ ok: true, indexedAt: null, refreshing: true });
    expect(panel(a)).toContain("not indexed yet");
  });
  it("x-search-min-score is shown only as the meaning part's tooltip", async () => {
    const { f } = fakeFetch({ status: 200, body: [], headers: { "x-search-min-score": "0.3" } });
    const a = await fetchSemantic("q", { fetch: f });
    expect(a).toMatchObject({ ok: true, minScore: "0.3" });
    const html = panel(a);
    expect(html).toMatch(/<span class="sr-meaning" title="Meaning matches scored at least 0\.3">no matches by meaning<\/span>/);
    expect(html.replace(/title="[^"]*"/g, "")).not.toContain("0.3");
  });
  it("with meaning hits the part counts them, and keeps the tooltip", async () => {
    const hit = { kind: "ask", id: "a1", seat: "meta:x", title: "T", status: "open", score: 0.5, excerpt: "e", url: null, appPath: null, section: "F1" };
    const a = await fetchSemantic("q", { fetch: fakeFetch({ status: 200, body: [hit, { ...hit, id: "a2" }], headers: { "x-search-min-score": "0.3" } }).f });
    expect(panel(a)).toMatch(/<span class="sr-meaning" title="Meaning matches scored at least 0\.3">2 by meaning<\/span>/);
    expect(panel(a)).not.toContain("no matches by meaning");
  });
  it("without x-search-min-score the meaning part has no tooltip", async () => {
    const a = await fetchSemantic("q", { fetch: fakeFetch({ status: 200, body: [] }).f });
    expect(a).not.toHaveProperty("minScore");
    expect(panel(a)).toMatch(/<span class="sr-meaning">no matches by meaning<\/span>/);
  });
  it("a 400, which carries the same headers, is still a refusal naming its status", async () => {
    const { f } = fakeFetch({ status: 400, body: { error: "minScore must be a number from 0 to 1.1" }, headers: { "x-search-indexed-at": "2026-10-31T11:55:00.000Z", "x-search-refreshing": "0" } });
    expect(await fetchSemantic("q", { fetch: f })).toEqual({ ok: false, q: "q", reason: "http-400" });
  });
});
