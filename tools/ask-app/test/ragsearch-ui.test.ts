/**
 * RAGSEARCH-UI: the sidebar's search bar asks /api/search (IDE-334) after a pause in the typing and shows
 * one results panel: asks first (meaning and word matches merged), then proof pages and broadcasts.
 * The server is a fake fetch here; the pure pieces live in src/client/semantic.ts, and the panel is
 * rendered with react-dom/server like the other client tests. The one run against the real server and
 * the real local embedder is in ragsearch-e2e.test.ts.
 */
import { beforeEach, describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import type { SearchHit } from "../src/search/query.ts";
import type { Row } from "../src/client/model.ts";
import type { Hay } from "../src/client/search.ts";
import { resetTokenState } from "../src/client/token.ts";
import {
  createSemanticSearch,
  semanticQueryFor,
  excerptAfterSection,
  fetchSemantic,
  indexAgeText,
  mergeResults,
  openTarget,
  resultRoute,
  searchKeyAction,
  SEMANTIC_DEBOUNCE_MS,
  stepSelection,
  unavailableNote,
  type SemanticState,
} from "../src/client/semantic.ts";
import { SearchResults } from "../src/client/results.tsx";

const NOW = Date.parse("2026-10-31T12:00:00.000Z");

const hit = (o: Partial<SearchHit> & Pick<SearchHit, "kind" | "id">): SearchHit => ({
  seat: "meta:engine",
  title: `Title of ${o.id}`,
  status: "open",
  score: 0.8,
  excerpt: `excerpt of ${o.id}`,
  url: null,
  appPath: null,
  section: "F1",
  ...o,
});
const row = (ref: string, extra?: Hay): Row & { extra?: Hay } =>
  ({ ref, id: ref.split("/")[1], title: `Row ${ref}`, seat: ref.split("/")[0], topic: "", created: 0, age: "", left: 1, total: 1, high: false, waitingOnYou: true, draftSent: false, draft: false, status: "open", ...(extra ? { extra } : {}) }) as Row & { extra?: Hay };

type Call = { url: string; init?: RequestInit };
function fakeFetch(respond: (url: string) => { status: number; body: unknown; headers?: Record<string, string> } | Error) {
  const calls: Call[] = [];
  const f = async (url: string, init?: RequestInit) => {
    calls.push({ url, init });
    const r = respond(url);
    if (r instanceof Error) throw r;
    return new Response(typeof r.body === "string" ? r.body : JSON.stringify(r.body), { status: r.status, headers: { "content-type": "application/json", ...(r.headers ?? {}) } });
  };
  return { f, calls };
}

beforeEach(() => resetTokenState("page-token", "build-1"));

describe("fetchSemantic: one request to /api/search", () => {
  it("sends the query, a limit and the page token, and reads the hits and both headers", async () => {
    const hits = [hit({ kind: "ask", id: "warm-cache" })];
    const { f, calls } = fakeFetch(() => ({ status: 200, body: hits, headers: { "x-search-indexed-at": "2026-10-31T11:55:00.000Z", "x-search-refreshing": "1" } }));
    const a = await fetchSemantic("warm cache & more", { fetch: f });
    expect(calls).toHaveLength(1);
    const u = new URL(calls[0].url, "http://x");
    expect(u.pathname).toBe("/api/search");
    expect(u.searchParams.get("q")).toBe("warm cache & more");
    expect(u.searchParams.get("limit")).toBe("20");
    expect((calls[0].init?.headers as Record<string, string>)["x-ask-token"]).toBe("page-token");
    expect(a).toEqual({ ok: true, q: "warm cache & more", hits, indexedAt: "2026-10-31T11:55:00.000Z", refreshing: true });
  });

  it("reads an empty x-search-indexed-at as never indexed, and refreshing 0 as not refreshing", async () => {
    const { f } = fakeFetch(() => ({ status: 200, body: [], headers: { "x-search-indexed-at": "", "x-search-refreshing": "0" } }));
    expect(await fetchSemantic("q", { fetch: f })).toEqual({ ok: true, q: "q", hits: [], indexedAt: null, refreshing: false });
  });

  // SEARCHFIX: index-missing is no longer sent (searchfix-ui.test.ts reads it as unavailable).
  it.each(["index-empty", "index-error", "embedder-unavailable"])("a 503 with reason %s is a refusal naming that reason", async (reason) => {
    const { f } = fakeFetch(() => ({ status: 503, body: { error: "cannot answer", reason } }));
    expect(await fetchSemantic("q", { fetch: f })).toEqual({ ok: false, q: "q", reason });
  });

  it("a request that throws, a 503 with no known reason, another status and a 200 that is not a list are all refusals, never an empty answer", async () => {
    expect(await fetchSemantic("q", { fetch: fakeFetch(() => new TypeError("Failed to fetch")).f })).toEqual({ ok: false, q: "q", reason: "request-failed" });
    expect(await fetchSemantic("q", { fetch: fakeFetch(() => ({ status: 503, body: { error: "x", reason: "<b>odd</b>" } })).f })).toEqual({ ok: false, q: "q", reason: "unavailable" });
    expect(await fetchSemantic("q", { fetch: fakeFetch(() => ({ status: 500, body: { error: "boom" } })).f })).toEqual({ ok: false, q: "q", reason: "http-500" });
    expect(await fetchSemantic("q", { fetch: fakeFetch(() => ({ status: 200, body: { hits: [] } })).f })).toEqual({ ok: false, q: "q", reason: "bad-response" });
    expect(await fetchSemantic("q", { fetch: fakeFetch(() => ({ status: 200, body: "not json{" })).f })).toEqual({ ok: false, q: "q", reason: "bad-response" });
  });

  it("a token the server no longer takes, with no fresh token to be had, is a refusal (token-rejected)", async () => {
    const { f } = fakeFetch((url) => (url.startsWith("/api/search") ? { status: 403, body: { error: "missing or wrong ask token" } } : new TypeError("down")));
    expect(await fetchSemantic("q", { fetch: f })).toEqual({ ok: false, q: "q", reason: "token-rejected" });
  });

  it("names the reason in the note the sidebar shows", () => {
    expect(unavailableNote("index-missing")).toBe("semantic search unavailable: index-missing");
  });
});

describe("createSemanticSearch: debounced, latest query wins", () => {
  function harness(run: (q: string) => Promise<any>) {
    const timers: { fn: () => void; ms: number; live: boolean }[] = [];
    const states: SemanticState[] = [];
    const s = createSemanticSearch({
      run,
      timers: {
        set: (fn, ms) => {
          const t = { fn, ms, live: true };
          timers.push(t);
          return t;
        },
        clear: (h) => ((h as { live: boolean }).live = false),
      },
      onState: (st) => states.push(st),
    });
    const fire = () => timers.filter((t) => t.live).forEach((t) => ((t.live = false), t.fn()));
    return { s, timers, states, fire };
  }

  it("waits for the pause, then asks once with the last text typed", async () => {
    const asked: string[] = [];
    const h = harness(async (q) => (asked.push(q), { ok: true, q, hits: [], indexedAt: null, refreshing: false }));
    h.s.query("wa");
    h.s.query("war");
    h.s.query("warm");
    expect(asked).toEqual([]);
    expect(h.timers.filter((t) => t.live).map((t) => t.ms)).toEqual([SEMANTIC_DEBOUNCE_MS]);
    expect(h.states.at(-1)).toEqual({ phase: "waiting", q: "warm" });
    h.fire();
    await Promise.resolve();
    await Promise.resolve();
    expect(asked).toEqual(["warm"]);
    expect(h.states.at(-1)).toMatchObject({ phase: "done", answer: { ok: true, q: "warm" } });
  });

  it("drops an answer that comes back after the text changed", async () => {
    const pending: ((v: any) => void)[] = [];
    const h = harness((q) => new Promise((r) => pending.push(() => r({ ok: true, q, hits: [hit({ kind: "ask", id: q })], indexedAt: null, refreshing: false }))));
    h.s.query("first");
    h.fire();
    h.s.query("second");
    pending[0]!(undefined);
    await new Promise((r) => setTimeout(r, 0));
    expect(h.states.some((s) => s.phase === "done")).toBe(false);
    h.fire();
    pending[1]!(undefined);
    await new Promise((r) => setTimeout(r, 0));
    expect(h.states.at(-1)).toMatchObject({ phase: "done", answer: { q: "second" } });
  });

  it("an empty or one-letter query asks nothing and goes idle; a run that throws is a request-failed refusal", async () => {
    const h = harness(async () => {
      throw new Error("boom");
    });
    h.s.query("  ");
    h.s.query("a");
    expect(h.timers).toHaveLength(0);
    expect(h.states).toEqual([{ phase: "idle" }, { phase: "idle" }]);
    h.s.query("ab");
    h.fire();
    await new Promise((r) => setTimeout(r, 0));
    expect(h.states.at(-1)).toEqual({ phase: "done", answer: { ok: false, q: "ab", reason: "request-failed" } });
  });

  it("dispose cancels the wait", () => {
    const asked: string[] = [];
    const h = harness(async (q) => (asked.push(q), { ok: true, q, hits: [], indexedAt: null, refreshing: false }));
    h.s.query("warm");
    h.s.dispose();
    expect(h.timers.every((t) => !t.live)).toBe(true);
  });
});

describe("mergeResults: asks first, then proofs and broadcasts", () => {
  const hits = [
    hit({ kind: "proof", id: "ledger", title: "Ledger proof", url: "https://proofs.example/ledger.html", appPath: "/proofs/user/ledger.html", score: 0.9 }),
    hit({ kind: "ask", id: "warm-cache", seat: "meta:engine", excerpt: "the warmer cache decides", section: "GO", score: 0.85 }),
    hit({ kind: "broadcast", id: "freeze", seat: "director", appPath: "/broadcasts/freeze", url: "http://127.0.0.1:4977/broadcasts/freeze", score: 0.7 }),
    hit({ kind: "ask", id: "dns-move", seat: "domain:platform", score: 0.6 }),
  ];
  const words = [row("domain:platform/dns-move"), row("meta:utils/tidy-logs", { field: "why", text: "tidy the logs" })];

  it("lists meaning hits on asks in score order, marks an ask both ways matched, then word-only asks, then the rest", () => {
    const m = mergeResults(words, hits);
    expect(m.items.map((i) => [i.kind, i.key, i.match])).toEqual([
      ["ask", "meta:engine/warm-cache", "meaning"],
      ["ask", "domain:platform/dns-move", "both"],
      ["ask", "meta:utils/tidy-logs", "word"],
      ["proof", "proof:ledger", "meaning"],
      ["broadcast", "broadcast:freeze", "meaning"],
    ]);
    expect(m.items[0]).toMatchObject({ excerpt: "the warmer cache decides", section: "GO" });
    expect(m.items[2]).toMatchObject({ extra: { field: "why", text: "tidy the logs" } });
    expect(m.moreWords).toBe(0);
  });

  it("caps the word-only asks and counts the rest (they stay in the list below)", () => {
    const many = Array.from({ length: 14 }, (_, i) => row(`s/a${i}`));
    const m = mergeResults(many, []);
    expect(m.items).toHaveLength(10);
    expect(m.moreWords).toBe(4);
  });

  it("opens an ask in the app, a proof or broadcast at its appPath, else its url, else nowhere", () => {
    const m = mergeResults(words, [...hits, hit({ kind: "proof", id: "local", url: null, appPath: null }), hit({ kind: "proof", id: "far", url: "https://p.example/x.html", appPath: null })]);
    const by = (k: string) => m.items.find((i) => i.key === k)!;
    expect(openTarget(by("meta:engine/warm-cache"))).toEqual({ ask: "meta:engine/warm-cache" });
    expect(openTarget(by("proof:ledger"))).toEqual({ app: "/proofs/user/ledger.html" });
    expect(openTarget(by("broadcast:freeze"))).toEqual({ app: "/broadcasts/freeze" });
    expect(openTarget(by("proof:far"))).toEqual({ url: "https://p.example/x.html" });
    expect(openTarget(by("proof:local"))).toBeNull();
  });
});

describe("stepSelection: arrows through the results", () => {
  it("down from nothing picks the first, stops at the ends, and up from the first leaves the list", () => {
    expect(stepSelection(-1, "ArrowDown", 3)).toBe(0);
    expect(stepSelection(0, "ArrowDown", 3)).toBe(1);
    expect(stepSelection(2, "ArrowDown", 3)).toBe(2);
    expect(stepSelection(1, "ArrowUp", 3)).toBe(0);
    expect(stepSelection(0, "ArrowUp", 3)).toBe(-1);
    expect(stepSelection(-1, "ArrowDown", 0)).toBe(-1);
    expect(stepSelection(5, "ArrowUp", 3)).toBe(1);
  });
});

describe("indexAgeText", () => {
  it("says how old the index is, or that it was never built", () => {
    expect(indexAgeText("2026-10-31T11:55:00.000Z", NOW)).toBe("indexed 5m ago");
    expect(indexAgeText("2026-10-31T09:00:00.000Z", NOW)).toBe("indexed 3h ago");
    expect(indexAgeText(null, NOW)).toBe("not indexed yet");
    expect(indexAgeText("garbage", NOW)).toBe("not indexed yet");
  });
});

describe("SearchResults: the panel", () => {
  const html = (state: SemanticState, words: (Row & { extra?: Hay })[] = [], selected = -1) =>
    renderToStaticMarkup(createElement(SearchResults, { state, words, selected, now: NOW, terms: ["cache"], onOpen: () => undefined, onHover: () => undefined }));
  const ok = (hits: SearchHit[], refreshing = false): SemanticState => ({ phase: "done", answer: { ok: true, q: "cache", hits, indexedAt: "2026-10-31T11:55:00.000Z", refreshing } });

  it("shows nothing at all while idle", () => {
    expect(html({ phase: "idle" })).toBe("");
  });

  it("while waiting says it is searching and never claims an empty result", () => {
    const h = html({ phase: "waiting", q: "cache" });
    expect(h).toContain("searching by meaning");
    expect(h).not.toMatch(/no .*match/i);
  });

  it("on a refusal shows only the note naming the reason, no result list", () => {
    const h = html({ phase: "done", answer: { ok: false, q: "cache", reason: "index-missing" } }, [row("a/b")]);
    expect(h).toContain("semantic search unavailable: index-missing");
    expect(h).not.toContain('role="listbox"');
    expect(h).not.toMatch(/no .*match/i);
  });

  it("marks each hit as a word or meaning match, shows the excerpt and the section, the index age, and refreshing", () => {
    const h = html(ok([hit({ kind: "ask", id: "warm-cache", excerpt: "the warmer cache decides", section: "GO" }), hit({ kind: "proof", id: "ledger", title: "Ledger proof", appPath: "/proofs/l" })], true), [row("x:y/tidy")], 1);
    expect(h).toContain('role="listbox"');
    expect(h).toContain("indexed 5m ago");
    expect(h).toContain("refreshing");
    expect(h).toContain("the warmer cache decides");
    expect(h).toContain("GO");
    expect(h.match(/class="sr-how meaning"/g)).toHaveLength(2);
    expect(h.match(/class="sr-how word"/g)).toHaveLength(1);
    expect(h).toContain(">proof<");
    // The selected option carries aria-selected and the id the input points at.
    expect(h).toMatch(/id="sr-1"[^>]*aria-selected="true"/);
  });

  it("marks the typed words only on a result that matched by word: a meaning hit's letters prove nothing", () => {
    const both = html(ok([hit({ kind: "ask", id: "both", seat: "x:y", excerpt: "the warmer cache decides" })]), [row("x:y/both")]);
    expect(both).toContain("the warmer <mark>cache</mark> decides");
    expect(both).toContain('class="sr-how word meaning"');
    expect(html(ok([hit({ kind: "ask", id: "m", title: "cache title", excerpt: "the warmer cache decides" })]))).not.toContain("<mark>");
  });

  it("does not repeat the section at the start of the excerpt", () => {
    const h = html(ok([hit({ kind: "ask", id: "a", section: "Ship it?", excerpt: "Ship it? Why: the warmer one" }), hit({ kind: "ask", id: "b", section: "GO", excerpt: "GOVERNANCE first" })]));
    expect(h).toContain('<span class="sr-section">Ship it?</span> Why: the warmer one');
    expect(h).toContain("GOVERNANCE first");
    expect(excerptAfterSection("Ship it?", "Ship it?")).toBe("");
  });

  it("does not say refreshing when no pass runs", () => {
    expect(html(ok([hit({ kind: "ask", id: "a" })]))).not.toContain("refreshing");
  });

  it("an answer with no hits and no word matches says so, as a real answer", () => {
    expect(html(ok([]))).toContain("Nothing matches “cache” by meaning or by word.");
  });

  it("a hit with nowhere to open is shown but not clickable", () => {
    const h = html(ok([hit({ kind: "proof", id: "local", title: "Local proof" })]));
    expect(h).toMatch(/aria-disabled="true"/);
  });
});

describe("the search box drives the results from the keyboard", () => {
  it("points the input at the results listbox and the selected option", async () => {
    const { AskSearch } = await import("../src/client/App.tsx");
    const h = renderToStaticMarkup(createElement(AskSearch, { q: "cache", onQuery: () => {}, slim: false, controls: "search-results", activeId: "sr-2" }));
    expect(h).toContain('aria-controls="search-results"');
    expect(h).toContain('aria-activedescendant="sr-2"');
    const none = renderToStaticMarkup(createElement(AskSearch, { q: "cache", onQuery: () => {}, slim: false }));
    expect(none).not.toContain("aria-activedescendant");
  });

  it("the word-filter's empty line says the results above match on meaning when there are some", async () => {
    const { SearchEmpty } = await import("../src/client/App.tsx");
    expect(renderToStaticMarkup(createElement(SearchEmpty, { q: "zebra", onClear: () => {}, meaningHits: 3 }))).toContain("No asks match “zebra” by word; the results above match on meaning.");
    expect(renderToStaticMarkup(createElement(SearchEmpty, { q: "zebra", onClear: () => {} }))).toContain("No asks match “zebra”.");
  });
});

describe("the keys and the links, as App.tsx uses them", () => {
  const items = mergeResults([row("a:b/one"), row("a:b/two")], []).items;

  it("arrows move, Enter opens the selected result, anything else (and Enter on nothing) is left to the box", () => {
    expect(searchKeyAction("ArrowDown", -1, items)).toEqual({ type: "move", to: 0 });
    expect(searchKeyAction("ArrowUp", 1, items)).toEqual({ type: "move", to: 0 });
    expect(searchKeyAction("Enter", 1, items)).toEqual({ type: "open", item: items[1] });
    expect(searchKeyAction("Enter", -1, items)).toBeNull();
    expect(searchKeyAction("ArrowDown", -1, [])).toBeNull();
    expect(searchKeyAction("a", 0, items)).toBeNull();
  });

  it("the input hands its keys over and prevents the default only for a key that was used", async () => {
    const { AskSearch } = await import("../src/client/App.tsx");
    const seen: string[] = [];
    const el = AskSearch({ q: "cache", onQuery: () => {}, slim: false, onKey: (k) => (seen.push(k), k === "ArrowDown") });
    const input = (el.props.children as any[])[0];
    let prevented = 0;
    const press = (key: string) => input.props.onKeyDown({ key, preventDefault: () => prevented++, currentTarget: { blur() {} } });
    press("ArrowDown");
    expect(prevented).toBe(1);
    press("x");
    expect(prevented).toBe(1);
    expect(seen).toEqual(["ArrowDown", "x"]);
  });

  it("an in-app path becomes the route's fields, keeps the ask beside the list, and leaves the search as the section does", () => {
    expect(resultRoute("/proofs/user/ledger.html", "a:b/one")).toEqual({ section: "proofs", ask: "a:b/one", proof: "user/ledger.html", broadcast: undefined, pane: undefined, fork: undefined, q: undefined });
    expect(resultRoute("/broadcasts/freeze", undefined)).toMatchObject({ section: "broadcasts", broadcast: "freeze", q: undefined });
    expect(resultRoute("/a/meta:engine/warm-cache", "a:b/one")).toEqual({ section: "asks", ask: "meta:engine/warm-cache", fork: undefined, pane: undefined });
  });

  it("opens only a web address outside the app: a hit's url is data, never a script", () => {
    const m = mergeResults([], [hit({ kind: "proof", id: "evil", url: "javascript:alert(1)" }), hit({ kind: "proof", id: "ok", url: "http://p.example/x.html" })]);
    expect(openTarget(m.items[0])).toBeNull();
    expect(openTarget(m.items[1])).toEqual({ url: "http://p.example/x.html" });
  });
});

describe("fix round (RAGSEARCH_CRITIQUE)", () => {
  it("S2: a 200 list whose elements are not hits is a bad-response, and the merge never throws on one", async () => {
    for (const body of [[null], [1], ["x"], [{ kind: "ask" }], [{ kind: 1, id: "a" }], [hit({ kind: "ask", id: "ok" }), null]]) {
      expect(await fetchSemantic("q", { fetch: fakeFetch(() => ({ status: 200, body })).f }), JSON.stringify(body)).toEqual({ ok: false, q: "q", reason: "bad-response" });
    }
    expect(() => mergeResults([row("a/b")], [null, 3, { kind: "ask" }] as never)).not.toThrow();
    expect(mergeResults([row("a/b")], [null] as never).items.map((i) => i.key)).toEqual(["a/b"]);
  });

  it("N1: a token refused after a restart says to reload; an updated app is named as such", async () => {
    const refused = fakeFetch((url) => (url.startsWith("/api/search") ? { status: 403, body: { error: "missing or wrong ask token" } } : new TypeError("down")));
    expect(await fetchSemantic("q", { fetch: refused.f })).toEqual({ ok: false, q: "q", reason: "token-rejected" });
    const updated = fakeFetch((url) =>
      url.startsWith("/api/search") ? { status: 403, body: { error: "missing or wrong ask token" } } : url === "/" ? { status: 200, body: '<meta name="ask-token" content="t2">' } : { status: 200, body: { build: "build-2" } },
    );
    expect(await fetchSemantic("q", { fetch: updated.f })).toEqual({ ok: false, q: "q", reason: "app-updated" });
    expect(unavailableNote("token-rejected")).toBe("semantic search unavailable: token-rejected (reload the app)");
    expect(unavailableNote("app-updated")).toBe("semantic search unavailable: app-updated (reload the app)");
    expect(unavailableNote("index-missing")).toBe("semantic search unavailable: index-missing");
  });

  it("N3: a new query aborts the request still in flight, and dispose aborts too", async () => {
    const signals: AbortSignal[] = [];
    const timers: (() => void)[] = [];
    const s = createSemanticSearch({
      run: (_q, signal) => (signals.push(signal), new Promise(() => {})),
      timers: { set: (fn) => (timers.push(fn), fn), clear: () => {} },
      onState: () => {},
    });
    s.query("first");
    timers.shift()!();
    expect(signals[0].aborted).toBe(false);
    s.query("second");
    expect(signals[0].aborted).toBe(true);
    timers.shift()!();
    s.dispose();
    expect(signals[1].aborted).toBe(true);
  });

  it("N3: the signal reaches the request", async () => {
    const { f, calls } = fakeFetch(() => ({ status: 200, body: [] }));
    const c = new AbortController();
    await fetchSemantic("q", { fetch: f, signal: c.signal });
    expect(calls[0].init?.signal).toBe(c.signal);
  });

  it("S1: only the asks view searches, with its ?q=", () => {
    expect(semanticQueryFor("asks", "warm cache")).toBe("warm cache");
    expect(semanticQueryFor("asks", undefined)).toBe("");
    expect(semanticQueryFor("proofs", "warm cache")).toBe("");
    expect(semanticQueryFor("broadcasts", "warm cache")).toBe("");
  });

  const appSrc = () => fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");

  it("S1 + N2: App runs the query effect, in a block body, on the query, the view and the controller", () => {
    expect(appSrc()).toMatch(/useEffect\(\(\) => \{\s*semanticSearch\.query\(semanticQueryFor\(view, route\.q\)\);\s*\}, \[route\.q, view, semanticSearch\]\);/);
  });

  it("N4: the selection resets when the answer or the rows change", () => {
    expect(appSrc()).toMatch(/useEffect\(\(\) => \{\s*setSelected\(-1\);\s*\}, \[semantic, rows\]\);/);
  });

  it("S1: App renders SearchArea with its key handler, and SearchArea hands it to the box as onKey", async () => {
    expect(appSrc()).toMatch(/<SearchArea\b[^>]*\bonSearchKey=\{onSearchKey\}/);
    expect(appSrc()).toMatch(/<AskSearch\b[^>]*\bonKey=\{onSearchKey\}/);
    const { SearchArea, AskSearch } = await import("../src/client/App.tsx");
    const onSearchKey = () => true;
    const el = SearchArea({ query: "cache", onQuery: () => {}, slim: false, semantic: { phase: "idle" }, rows: [], selected: -1, now: NOW, terms: ["cache"], onSearchKey, onOpen: () => {}, onHover: () => {} });
    const found: any[] = [];
    const walk = (n: any) => {
      if (!n || typeof n !== "object") return;
      if (Array.isArray(n)) return n.forEach(walk);
      if (n.type === AskSearch) found.push(n);
      walk(n.props?.children);
    };
    walk(el);
    expect(found).toHaveLength(1);
    expect(found[0].props.onKey).toBe(onSearchKey);
  });

  it("S1: SearchArea renders the box wired to the panel: listbox, aria-controls and aria-activedescendant", async () => {
    const { SearchArea } = await import("../src/client/App.tsx");
    const done: SemanticState = { phase: "done", answer: { ok: true, q: "cache", hits: [hit({ kind: "ask", id: "warm" })], indexedAt: null, refreshing: false } };
    const props = { query: "cache", onQuery: () => {}, slim: false, semantic: done, rows: [], now: NOW, terms: ["cache"], onSearchKey: () => true, onOpen: () => {}, onHover: () => {} };
    const h = renderToStaticMarkup(createElement(SearchArea, { ...props, selected: 0 }));
    expect(h).toContain('role="listbox"');
    expect(h).toContain('aria-controls="search-results"');
    expect(h).toContain('aria-activedescendant="sr-0"');
    expect(h).toContain('id="search-results"');
    const none = renderToStaticMarkup(createElement(SearchArea, { ...props, selected: -1, semantic: { phase: "idle" } }));
    expect(none).not.toContain("aria-controls");
    expect(none).not.toContain('role="listbox"');
  });

  it("S1: searchKeyDown hands a used key over and prevents its default; Esc still clears, then blurs", async () => {
    const { searchKeyDown } = await import("../src/client/App.tsx");
    const ev = (key: string) => {
      const e = { key, prevented: 0, blurred: 0, preventDefault() { e.prevented++; }, currentTarget: { blur() { e.blurred++; } } };
      return e;
    };
    const keys: string[] = [];
    const onKey = (k: string) => (keys.push(k), k === "ArrowDown");
    const cleared: string[] = [];
    const down = ev("ArrowDown");
    searchKeyDown(down, { q: "x", onQuery: (v) => cleared.push(v), onKey });
    expect([down.prevented, keys]).toEqual([1, ["ArrowDown"]]);
    const letter = ev("a");
    searchKeyDown(letter, { q: "x", onQuery: (v) => cleared.push(v), onKey });
    expect(letter.prevented).toBe(0);
    const esc = ev("Escape");
    searchKeyDown(esc, { q: "x", onQuery: (v) => cleared.push(v), onKey });
    expect([esc.prevented, cleared, keys.includes("Escape")]).toEqual([1, [""], false]);
    const esc2 = ev("Escape");
    searchKeyDown(esc2, { q: "", onQuery: (v) => cleared.push(v), onKey });
    expect(esc2.blurred).toBe(1);
  });
});
