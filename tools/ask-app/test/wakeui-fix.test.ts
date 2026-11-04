/**
 * WAKEUI fix round (builds/WAKEUI_CRITIQUE.md): the cooldown tooltip claims no more than the delivery
 * record says (MUST-FIX); forkTickets reads an option's Reversible line (SHOULD-2); the fork-focus
 * effect is keyed by the ask's ref and the fork, not the ask object (SHOULD-3); a 409's wakeAfter is laid
 * over the row, one expiry reloads once, and "no-cost" is not one-way (NITs).
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow } from "../src/client/model.ts";
import { forkFocusKey, isOneWay } from "../src/client/tree.ts";
import { expiryGate, holdCooldown, showsRowBell, wakeOutcome, wakeUi, type WakeRow } from "../src/client/wake.ts";

const NOW = Date.parse("2026-11-01T12:00:00.000Z");
const at = (ms: number) => new Date(NOW + ms).toISOString();
const MIN = 60_000;
const cooling = (wakeDelivery?: string): WakeRow => ({ wakeTarget: "test:holder", wokenAt: at(-MIN), wokenSeat: "test:holder", ...(wakeDelivery ? { wakeDelivery } : {}), wakeAfter: at(4 * MIN), wakeBlocked: "cooldown", wakeBlockedReason: "r" });
const ASK = "---\nid: t1\nto: test:holder\nfrom: test:asker\nstatus: open\nrevision: 1\ncreated: 2026-10-30T10:00:00.000Z\n---\n\n## ¶ASK_A: Choose one: First?\n- [ ] [X] One\n  Reversible: no — see EX-42 for why\n- [ ] [Y] Two\n";
const stored = (extra: object = {}) => ({ ...parseAskFile(ASK), seat: "test:folder", file: "/x.md", mtimeMs: 0, ...extra });

describe("MUST-FIX: the cooldown tooltip is worded by wakeDelivery", () => {
  it("delivered: says woken", () => {
    expect(wakeUi(cooling("delivered"), NOW).title).toBe("test:holder was woken for this ask; it can be woken again in 4:00.");
  });
  it("pending: wake sent, delivery not confirmed, never woken", () => {
    const t = wakeUi(cooling("pending"), NOW).title;
    expect(t).toBe("Wake sent to test:holder; delivery not confirmed. It can be woken again in 4:00.");
    expect(t).not.toMatch(/woken for/);
  });
  it("partial: partly delivered, never woken", () => {
    const t = wakeUi(cooling("partial"), NOW).title;
    expect(t).toBe("Wake partly delivered to test:holder. It can be woken again in 4:00.");
    expect(t).not.toMatch(/was woken/);
  });
  it("no delivery recorded reads as pending, not as woken", () => {
    expect(wakeUi(cooling(), NOW).title).toMatch(/^Wake sent to test:holder; delivery not confirmed\./);
  });
  it("names the seat the wake reached, after a forward", () => {
    expect(wakeUi({ ...cooling("delivered"), wokenSeat: "test:before" }, NOW).title).toMatch(/^test:before was woken/);
  });
  it.each([["delivered", /was woken for this ask/], ["pending", /delivery not confirmed/], ["partial", /partly delivered/]])("on the sidebar row, where the tooltip is the only text, %s reads right", async (d, re) => {
    const { AskListItem } = await import("../src/client/App.tsx");
    const w = { ...cooling(d), wokenAt: new Date(Date.now() - MIN).toISOString(), wakeAfter: new Date(Date.now() + 4 * MIN).toISOString() };
    const a = stored(w);
    const html = renderToStaticMarkup(createElement(AskListItem, { r: askRow(a, NOW, [a]), current: false, onPick: () => {}, slim: false, onChanged: () => {} }));
    const bell = html.slice(html.indexOf('class="row-wake'));
    const title = bell.match(/title="([^"]*)"/)![1];
    expect(title).toMatch(re);
    if (d !== "delivered") expect(title).not.toMatch(/woken for this ask/);
  });
});

describe("SHOULD-1: which rows draw a bell", () => {
  it("none for closed or operator, which no click gets past; one for the rest", () => {
    expect(showsRowBell(undefined)).toBe(false);
    expect(showsRowBell({ wakeTarget: "x", wakeBlocked: "closed" })).toBe(false);
    expect(showsRowBell({ wakeTarget: "operator", wakeBlocked: "operator" })).toBe(false);
    expect(showsRowBell({ wakeTarget: "x", wakeBlocked: "no-pane" })).toBe(true);
    expect(showsRowBell({ wakeTarget: "x", wakeBlocked: "cooldown" })).toBe(true);
    expect(showsRowBell({ wakeTarget: "x" })).toBe(true);
  });
});

describe("SHOULD-2: a ticket key written only in an option's Reversible line is still found", () => {
  it("the fork head counts it", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const a = stored();
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
    expect(html).toContain('<span class="chip quiet" title="EX-42">1 ticket</span>');
  });
});

describe("SHOULD-3: the fork-focus effect runs when the target fork changes, not on every reload", () => {
  it("the same ask reloaded as a new object keeps the same key", () => {
    expect(forkFocusKey(stored(), "Q2")).toBe(forkFocusKey(stored({ wokenAt: at(0) }), "Q2"));
  });
  it("another fork or another ask changes it; no fork is its own key", () => {
    const k = forkFocusKey(stored(), "Q2");
    expect(forkFocusKey(stored(), "Q3")).not.toBe(k);
    expect(forkFocusKey({ ...stored(), seat: "test:other" }, "Q2")).not.toBe(k);
    expect(forkFocusKey(stored(), undefined)).not.toBe(forkFocusKey(stored(), ""));
  });
  it("the effect's only dependency is that key", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
    const body = src.slice(src.indexOf("// #Q2, #q2 and #f2 open that fork"));
    expect(body.slice(0, 700)).toMatch(/\}, \[focusKey\]\);/);
    expect(src).toContain("const focusKey = forkFocusKey(ask, focusFork);");
  });
});

describe("NIT 1: a 409's wakeAfter is laid over the row", () => {
  it("wakeOutcome hands it back", () => {
    expect(wakeOutcome(409, { error: "e", code: "cooldown", wakeAfter: at(2 * MIN) }).wakeAfter).toBe(at(2 * MIN));
    expect(wakeOutcome(409, { error: "e", code: "no-pane" }).wakeAfter).toBeUndefined();
  });
  it("holdCooldown restarts the count on a row whose own clock had let it go", () => {
    const row: WakeRow = { wakeTarget: "test:holder", wakeAfter: at(-1000), wakeBlocked: "cooldown" };
    const u = wakeUi(holdCooldown(row, at(2 * MIN)), NOW);
    expect(u.disabled).toBe(true);
    expect(u.counting).toBe("2:00");
  });
  it("never shortens a later cooldown the row already holds, and keeps another block", () => {
    const row: WakeRow = { wakeTarget: "x", wakeAfter: at(4 * MIN), wakeBlocked: "no-pane", wakeBlockedReason: "gone" };
    expect(holdCooldown(row, at(2 * MIN))).toEqual(row);
    expect(holdCooldown({ wakeTarget: "x", wakeBlocked: "no-pane" }, at(MIN)).wakeBlocked).toBe("no-pane");
  });
  it("WakeButton lays it over", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/WakeButton.tsx"), "utf8");
    expect(src).toMatch(/holdCooldown\(/);
  });
});

describe("NIT 3: one expiry fires one load, however many buttons count it down", () => {
  it("the gate opens once per key", () => {
    const gate = expiryGate();
    expect(gate("a/b@t1")).toBe(true);
    expect(gate("a/b@t1")).toBe(false);
    expect(gate("a/b@t2")).toBe(true);
  });
  it("WakeButton reloads through one shared gate, keyed by ask and wakeAfter", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/WakeButton.tsx"), "utf8");
    expect(src).toMatch(/const EXPIRED = expiryGate\(\);/);
    expect(src).toMatch(/EXPIRED\(`\$\{seat\}\/\$\{id\}@\$\{[^}]+\}`\)\) onChanged\(\)/);
  });
});

describe("NIT 4: one-way is read from the first word, and a hyphenated no- is not it", () => {
  it.each(["no-cost to undo", "no-op to revert", "nothing lost", "not hard"])("%s is not one-way", (s) => {
    expect(isOneWay(s)).toBe(false);
  });
  it.each(["no", "no — the data is gone", "no, it ships", "No.", "one-way", "one way door", "irreversible", "not reversible after send"])("%s is one-way", (s) => {
    expect(isOneWay(s)).toBe(true);
  });
});
