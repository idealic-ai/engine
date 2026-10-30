/**
 * ASKSEARCH (IDE-304): the sidebar's search bar. The matching is a pure function in
 * src/client/search.ts (so a semantic matcher can take its place later); the rendered bits are
 * checked with react-dom/server, like client-redesign.test.ts.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow, rowInFilter, sortRows, type StoredAsk } from "../src/client/model.ts";
import { parseRoute, serializeRoute, isNavigation } from "../src/client/route.ts";
import { highlight, isTypingTarget, matchAsk, searchRows, searchTerms, snippet } from "../src/client/search.ts";

const NOW = Date.parse("2026-10-29T13:00:00.000Z");
const head = (id: string, extra = "", from = "idealic:ui") =>
  `---\nid: ${id}\nto: operator\nfrom: ${from}\nstatus: open\nrevision: 1\ncreated: 2026-10-29T10:00:00.000Z\n${extra}---\n\n`;
const stored = (text: string, seat = "idealic:ui"): StoredAsk => ({ ...parseAskFile(text), seat, file: "/x.md", mtimeMs: 0 });

const FORKS = "## ¶ASK_A: Choose one: Which cache backend?\n- [ ] [RED] Redis cluster\n- [ ] [MEM] Memcached pool\n\n## ¶ASK_B: Choose one: Roll out when?\n- [ ] [NOW] This week\n- [ ] [LATER] After the freeze\n";

const cache = stored(head("cache-pick", "why: Pick the store for the session cache\n") + FORKS);
const answeredText =
  head("dns-move", "", "domain:platform").replace("status: open", "status: answered") +
  "## ¶ASK_N: Text: What should the new name be?\n\n" +
  '\n```json answer\n{"answers":{"N":"ledger-west"},"answeredBy":"operator","note":"keep the old alias a month"}\n```\n';
const dns = stored(answeredText, "domain:platform");
const plain = stored(head("tidy-logs", "", "meta:utils") + "## ¶ASK_T: Choose one: Trim the logs?\n- [ ] [Y] Yes\n- [ ] [N] No\n", "meta:utils");
const ALL = [cache, dns, plain];

describe("search terms and matching", () => {
  it("splits on whitespace, lowercases, and drops empties", () => {
    expect(searchTerms("  Redis   CLUSTER ")).toEqual(["redis", "cluster"]);
    expect(searchTerms("   ")).toEqual([]);
  });

  it("every term must match somewhere (AND), across different fields", () => {
    // "redis" is an option label, "ui" is the seat, "cache-pick" the id: all three in one ask.
    expect(matchAsk(cache, searchTerms("redis idealic:ui cache-pick"))).toBeTruthy();
    // One term that is nowhere in the ask fails the whole query.
    expect(matchAsk(cache, searchTerms("redis ledger"))).toBeNull();
    // Case-insensitive.
    expect(matchAsk(cache, searchTerms("SESSION Cache"))).toBeTruthy();
  });

  it("matches the why, the id, the seat (from and to), and each question's text", () => {
    expect(matchAsk(cache, ["session"])).toBeTruthy(); // why
    expect(matchAsk(cache, ["cache-pick"])).toBeTruthy(); // id
    expect(matchAsk(cache, ["operator"])).toBeTruthy(); // to
    expect(matchAsk(dns, ["platform"])).toBeTruthy(); // from
    expect(matchAsk(cache, ["roll", "out"])).toBeTruthy(); // second question's text
  });

  it("finds a match inside an option label and says where it was", () => {
    const m = matchAsk(cache, ["memcached"]);
    expect(m).toBeTruthy();
    expect(m!.extra).toEqual({ field: "option", text: "Memcached pool" });
    // A term the row already shows (the title) needs no extra line.
    expect(matchAsk(cache, ["cache", "backend"])!.extra).toBeUndefined();
  });

  it("finds a match in the recorded answer's text and in the note", () => {
    const a = matchAsk(dns, ["ledger-west"]);
    expect(a?.extra?.field).toBe("answer");
    expect(a?.extra?.text).toContain("ledger-west");
    expect(matchAsk(dns, ["alias"])?.extra).toEqual({ field: "note", text: "keep the old alias a month" });
  });

  it("an empty query matches everything", () => {
    expect(matchAsk(plain, [])).toEqual({});
  });
});

describe("search stacks with the status filter, and the counts follow", () => {
  const rows = sortRows(ALL.map((a) => askRow(a, NOW, ALL)));

  it("filters rows by the asks they came from, keeping their order", () => {
    expect(searchRows(rows, ALL, "").map((r) => r.id)).toEqual(rows.map((r) => r.id));
    expect(searchRows(rows, ALL, "operator").length).toBe(3);
    expect(searchRows(rows, ALL, "ledger").map((r) => r.id)).toEqual(["dns-move"]);
  });

  it("a status filter applies to the searched rows, so each count reflects the search", () => {
    const hit = searchRows(rows, ALL, "operator");
    const count = (f: "open" | "settled" | "all") => hit.filter((r) => rowInFilter(r, f)).length;
    expect([count("open"), count("settled"), count("all")]).toEqual([2, 1, 3]);
    const narrow = searchRows(rows, ALL, "ledger");
    expect(narrow.filter((r) => rowInFilter(r, "open")).length).toBe(0);
    expect(narrow.filter((r) => rowInFilter(r, "settled")).length).toBe(1);
  });

  it("a pluggable matcher (the hook for semantic search) replaces the text matcher", () => {
    const only = searchRows(rows, ALL, "anything", (a) => (a.header.id === "tidy-logs" ? {} : null));
    expect(only.map((r) => r.id)).toEqual(["tidy-logs"]);
  });
});

describe("highlight and snippet", () => {
  it("splits text into hit and plain parts, case-insensitively, merging overlaps", () => {
    expect(highlight("Redis cluster", ["redis"])).toEqual([{ text: "Redis", hit: true }, { text: " cluster", hit: false }]);
    expect(highlight("abcabc", ["bc", "ca"])).toEqual([{ text: "a", hit: false }, { text: "bcabc", hit: true }]);
    expect(highlight("plain", [])).toEqual([{ text: "plain", hit: false }]);
  });

  it("a snippet keeps the text around the first hit", () => {
    const long = "x".repeat(80) + " the needle is here " + "y".repeat(80);
    const s = snippet(long, ["needle"], 10);
    expect(s).toContain("needle");
    expect(s.startsWith("…")).toBe(true);
    expect(s.endsWith("…")).toBe(true);
    expect(snippet("short needle", ["needle"], 10)).toBe("short needle");
  });

  it("/ only steals focus when no text field has it", () => {
    expect(isTypingTarget(null)).toBe(false);
    expect(isTypingTarget({ tagName: "BUTTON" })).toBe(false);
    expect(isTypingTarget({ tagName: "INPUT" })).toBe(true);
    expect(isTypingTarget({ tagName: "TEXTAREA" })).toBe(true);
    expect(isTypingTarget({ tagName: "SELECT" })).toBe(true);
    expect(isTypingTarget({ tagName: "DIV", isContentEditable: true })).toBe(true);
  });
});

describe("?q= in the URL", () => {
  it("round-trips through parseRoute and serializeRoute", () => {
    const r = parseRoute("/a/idealic:ui/cache-pick", "?filter=all&q=redis%20cluster");
    expect(r.q).toBe("redis cluster");
    expect(r.filter).toBe("all");
    const url = serializeRoute(r);
    expect(url).toContain("q=redis");
    const [path, search] = url.split("?");
    expect(parseRoute(path, `?${search}`)).toEqual(r);
  });

  it("an empty query leaves no ?q=, and typing is not a navigation (replaceState)", () => {
    const r = parseRoute("/", "?q=");
    expect(r.q).toBeUndefined();
    expect(serializeRoute({ ...r, q: "" })).toBe("/");
    expect(isNavigation(r, { ...r, q: "abc" })).toBe(false);
  });
});

describe("rendered search bits", () => {
  it("the search box shows the query, a clear button, and the / hint", async () => {
    const { AskSearch } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(AskSearch, { q: "redis", onQuery: () => {}, slim: false }));
    expect(html).toContain('type="search"');
    expect(html).toContain('value="redis"');
    expect(html).toContain('aria-label="Search asks"');
    expect(html).toContain("Clear search");
    const empty = renderToStaticMarkup(createElement(AskSearch, { q: "", onQuery: () => {}, slim: true }));
    expect(empty).not.toContain("Clear search");
    expect(empty).toContain("search slim");
  });

  it("the empty state names the query and offers a clear button", async () => {
    const { SearchEmpty } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(SearchEmpty, { q: "zebra", onClear: () => {} }));
    expect(html).toContain("No asks match “zebra”");
    expect(html).toContain(">Clear search</button>");
  });

  it("a row highlights the matched text in its title and shows where a hidden match was", async () => {
    const { AskRowButton } = await import("../src/client/App.tsx");
    const r = askRow(cache, NOW, ALL);
    const terms = ["cache", "memcached"];
    const html = renderToStaticMarkup(createElement(AskRowButton, { r, current: false, onPick: () => {}, slim: false, terms, extra: matchAsk(cache, terms)!.extra }));
    expect(html).toContain("<mark>cache</mark>");
    expect(html).toContain('class="row-hit"');
    expect(html).toContain("<mark>Memcached</mark> pool");
    // No query, no marks.
    const bare = renderToStaticMarkup(createElement(AskRowButton, { r, current: false, onPick: () => {}, slim: false }));
    expect(bare).not.toContain("<mark>");
  });
});
