/**
 * ASKSEARCH review fixes (IDE-304, ASKSEARCH_CRITIQUE.md): SHOULD-1 the URL write is debounced,
 * outside the state updater and safe against a throwing replaceState; SHOULD-2 the sidebar reads
 * the searched rows and the header the unsearched ones; SHOULD-3 a matching row always shows why;
 * NIT-1/3/4.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow, sortRows, type StoredAsk } from "../src/client/model.ts";
import { highlight, lowerWithMap, matchAsk, searchRows, shownTitleText, sidebarView, snippet } from "../src/client/search.ts";
import { URL_DEBOUNCE_MS, createUrlSync } from "../src/client/urlsync.ts";

const app = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
const NOW = Date.parse("2026-10-29T13:00:00.000Z");
const head = (id: string, status = "open", from = "idealic:ui") => `---\nid: ${id}\nto: operator\nfrom: ${from}\nstatus: ${status}\nrevision: 1\ncreated: 2026-10-29T10:00:00.000Z\n---\n\n`;
const stored = (text: string, seat = "idealic:ui"): StoredAsk => ({ ...parseAskFile(text), seat, file: "/x.md", mtimeMs: 0 });
const fork = (title: string) => `## ¶ASK_A: Choose one: ${title}\n- [ ] [Y] Yes\n- [ ] [N] No\n`;

function fakeTimers() {
  let seq = 0;
  const live = new Map<number, () => void>();
  return {
    timers: { set: (fn: () => void) => (live.set(++seq, fn), seq), clear: (h: unknown) => void live.delete(h as number) },
    fire: () => [...live.entries()].forEach(([k, fn]) => (live.delete(k), fn())),
    pending: () => live.size,
  };
}

describe("SHOULD-1: the URL write is debounced, outside the updater, and cannot throw", () => {
  it("keystrokes replace once, with the last URL, after the pause", () => {
    const calls: string[] = [];
    const h = { pushState: (_: unknown, __: string, u: string) => calls.push(`push ${u}`), replaceState: (_: unknown, __: string, u: string) => calls.push(`replace ${u}`) };
    const t = fakeTimers();
    const sync = createUrlSync(h, t.timers);
    for (const q of ["r", "re", "red", "redi", "redis"]) sync.later(`/asks?q=${q}`);
    expect(calls).toEqual([]);
    expect(t.pending()).toBe(1);
    t.fire();
    expect(calls).toEqual(["replace /asks?q=redis"]);
    expect(URL_DEBOUNCE_MS).toBe(300);
  });

  it("a push lands the pending query on the entry it leaves first; now() supersedes it", () => {
    const calls: string[] = [];
    const h = { pushState: (_: unknown, __: string, u: string) => calls.push(`push ${u}`), replaceState: (_: unknown, __: string, u: string) => calls.push(`replace ${u}`) };
    const t = fakeTimers();
    const sync = createUrlSync(h, t.timers);
    sync.later("/asks?q=red");
    sync.flush();
    sync.now("/asks/x/a?q=red", true);
    expect(calls).toEqual(["replace /asks?q=red", "push /asks/x/a?q=red"]);
    sync.later("/asks?q=z");
    sync.cancel();
    t.fire();
    expect(calls.length).toBe(2);
  });

  it("a replaceState that throws (WebKit's rate limit) is swallowed", () => {
    const boom = () => {
      throw new DOMException("Attempt to use history.replaceState() more than 100 times per 10 seconds", "SecurityError");
    };
    const t = fakeTimers();
    const sync = createUrlSync({ pushState: boom, replaceState: boom }, t.timers);
    sync.later("/asks?q=x");
    expect(() => t.fire()).not.toThrow();
    expect(() => sync.now("/asks", true)).not.toThrow();
  });

  it("App writes history only through the writer, never inside setRoute's updater", () => {
    expect(app).not.toMatch(/setRoute\(\(cur\)/);
    const direct = app.match(/history\.(pushState|replaceState)\(/g) ?? [];
    // The two in the writer's adapter, and nowhere else.
    expect(direct.length).toBe(2);
    expect(app).toMatch(/createUrlSync\(\{ pushState: \(d, u, url\) => history\.pushState\(d, u, url\), replaceState: \(d, u, url\) => history\.replaceState\(d, u, url\) \}/);
    expect(app).toMatch(/navigate\(\{ q: v \|\| undefined, \.\.\.pin \}, false, true\)/);
    expect(app).toContain("if (typing) return urlSync.later(url);");
  });
});

describe("SHOULD-2: the list and its counts read the searched rows; the header reads every row", () => {
  const a = stored(head("redis-a") + fork("Use redis?"));
  const b = stored(head("redis-b", "answered") + fork("Redis later?") + '\n```json answer\n{"answers":{"A":"Y"},"answeredBy":"operator"}\n```\n');
  const c = stored(head("other-c") + fork("Rename the ledger?"));
  const asks = [a, b, c];
  const allRows = sortRows(asks.map((x) => askRow(x, NOW, asks)));

  it("a search narrows the list and the filter counts", () => {
    const v = sidebarView(allRows, asks, "redis", "open");
    expect(v.inFilter.map((r) => r.id)).toEqual(["redis-a"]);
    expect(v.count("open")).toBe(1);
    expect(v.count("all")).toBe(2);
    expect(v.rows.map((r) => r.id).sort()).toEqual(["redis-a", "redis-b"]);
  });

  it("the header's waiting count does not follow the search", () => {
    const open = allRows.filter((r) => r.waitingOnYou).length;
    expect(open).toBe(2);
    expect(sidebarView(allRows, asks, "redis", "open").waiting).toBe(open);
    expect(sidebarView(allRows, asks, "nothing-matches-this", "open").waiting).toBe(open);
  });

  it("App takes the list, the counts and the waiting count from sidebarView and computes none itself", () => {
    expect(app).toMatch(/const \{ rows, inFilter, count, waiting \} = useMemo\(\(\) => sidebarView\(allRows, shown, route\.q, filter,/);
    expect(app).not.toMatch(/const (inFilter|count|waiting) =/);
    expect(app).toMatch(/\{FILTER_LABEL\[f\]\} <span className="n">\{count\(f\)\}<\/span>/);
    expect(app).toMatch(/groupRows\(inFilter,/);
  });
});

describe("SHOULD-3: a matching row always shows why", () => {
  it("the shown title text is what Plain renders: link labels, not URLs; code without backticks", async () => {
    const title = "Adopt [the store](https://github.com/acme/store) for `cache` (IDE-12)";
    expect(shownTitleText(title)).toBe("Adopt the store for cache (IDE-12)");
    const a = stored(head("t-1") + fork(title));
    const { AskRowButton } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(AskRowButton, { r: askRow(a, NOW, [a]), current: false, onPick: () => {}, slim: false }));
    const rowTitle = html.match(/<span class="row-title">([\s\S]*?)<\/span><\/span>/)?.[1] ?? "";
    expect(rowTitle.replace(/<[^>]+>/g, "")).toBe(shownTitleText(title));
  });

  it("a term only in a title link's URL gets the snippet line", () => {
    const a = stored(head("t-2") + fork("Adopt [the store](https://github.com/acme/store)?"));
    const m = matchAsk(a, ["github"]);
    expect(m?.extra?.field).toBe("title");
    expect(m?.extra?.text).toContain("github.com");
    expect(matchAsk(a, ["store"])?.extra).toBeUndefined();
  });

  it("a seat-only hit gets the snippet when the row hides the seat (grouped by seat, or slim)", () => {
    const a = stored(head("t-3", "open", "domain:platform") + fork("Rename it?"), "domain:platform");
    expect(matchAsk(a, ["platform"])?.extra).toBeUndefined();
    expect(matchAsk(a, ["platform"], { seat: false })?.extra?.field).toBe("seat");
    expect(searchRows([askRow(a, NOW, [a])], [a], "platform", matchAsk, { seat: false })[0].extra?.field).toBe("seat");
  });

  it("App tells the matcher whether the seat is on the row", () => {
    expect(app).toContain('const seatShown = !(sideW < SIDE_SLIM) && groupBy !== "seat";');
    expect(app).toMatch(/sidebarView\(allRows, shown, route\.q, filter, \{ seat: seatShown \}\)/);
  });
});

describe("NITs", () => {
  it("NIT-1: q is dropped on the way to proofs or broadcasts", () => {
    expect(app).toMatch(/const setView = \(v: View\) => navigate\(\{[^}]*\.\.\.\(v === "asks" \? \{\} : \{ q: undefined \}\) \}\);/);
  });

  it("NIT-3: with no ask named, typing names the ask on screen so the pane does not switch", () => {
    expect(app).toMatch(/const pin = !routeNow\.current\.ask && routeNow\.current\.section === "asks" && shownAsk\.current \? \{ ask: shownAsk\.current \} : \{\};/);
    expect(app).toContain("shownAsk.current = currentRef;");
  });

  it("NIT-4: a character whose lowercase is longer does not shift later marks", () => {
    expect("İ".toLowerCase().length).toBe(2);
    const { low, at } = lowerWithMap("İstanbul redis");
    expect(low.length).toBe("İstanbul redis".length + 1);
    expect(at[low.indexOf("redis")]).toBe("İstanbul ".length);
    expect(highlight("İstanbul redis", ["redis"])).toEqual([{ text: "İstanbul ", hit: false }, { text: "redis", hit: true }]);
    expect(highlight("İİ redis İ", ["redis"]).find((p) => p.hit)?.text).toBe("redis");
    // A term matching the start of an expanded character marks the whole character.
    expect(highlight("İx", ["i"])).toEqual([{ text: "İ", hit: true }, { text: "x", hit: false }]);
    expect(snippet(`${"İ".repeat(40)} needle tail`, ["needle"], 3)).toBe("…İİ needle ta…");
  });
});
