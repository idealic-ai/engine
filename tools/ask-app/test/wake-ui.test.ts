/**
 * WAKEUI 1: the client half of WAKEBTN (src/lib/wake.ts). Pure rules from src/client/wake.ts, and the
 * markup that App.tsx and WakeButton.tsx draw. Server-side render only, as the suite's other UI tests.
 */
import { describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow } from "../src/client/model.ts";
import { clickWake, countdown, mergeResult, wakeFields, wakeOutcome, wakeUi, wakeUrl, WAKE_WORDS, type WakeRow } from "../src/client/wake.ts";

const NOW = Date.parse("2026-11-01T12:00:00.000Z");
const at = (ms: number) => new Date(NOW + ms).toISOString();
const MIN = 60_000;
const ask = (status = "open") => `---\nid: t1\nto: test:holder\nfrom: test:asker\nstatus: ${status}\nrevision: 1\ncreated: 2026-10-30T10:00:00.000Z\n---\n\n## ¶ASK_A: Choose one: First?\n- [ ] [X] One\n- [ ] [Y] Two\n\n## ¶ASK_B: Choose one: Second?\n- [ ] [P] One\n- [ ] [Q] Two\n`;
const stored = (w: WakeRow, status = "open") => ({ ...parseAskFile(ask(status)), seat: "test:folder", file: "/x.md", mtimeMs: 0, ...w });
const ui = (w: WakeRow, o: Parameters<typeof wakeUi>[2] = {}) => wakeUi(w, NOW, o);
const IDLE: WakeRow = { wakeTarget: "test:holder" };
const COOLING: WakeRow = { wakeTarget: "test:holder", wokenAt: at(-2 * MIN), wokenBy: "operator", wokenSeat: "test:holder", wakeDelivery: "delivered", wakeAfter: at(3 * MIN), wakeBlocked: "cooldown", wakeBlockedReason: "woken a moment ago" };

async function detail(w: WakeRow, status = "open") {
  const { AskDetail } = await import("../src/client/App.tsx");
  const a = stored(w, status);
  return renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
}
async function item(w: WakeRow) {
  const { AskListItem } = await import("../src/client/App.tsx");
  const a = stored(w);
  return renderToStaticMarkup(createElement(AskListItem, { r: askRow(a, NOW, [a]), current: false, onPick: () => {}, slim: false, onChanged: () => {} }));
}
const count = (s: string, needle: string) => s.split(needle).length - 1;

describe("the request", () => {
  it("names the ask's own folder and id, each encoded", () => {
    expect(wakeUrl("meta:utils", "a b/c")).toBe("/api/asks/meta%3Autils/a%20b%2Fc/wake");
  });
  it("a row carries the folder seat, not the asker's from: line, which can differ", () => {
    const a = stored(IDLE);
    expect(askRow(a, NOW, [a]).askSeat).toBe("test:folder");
    expect(askRow(a, NOW, [a]).seat).toBe("test:asker");
  });
  it("wakeFields keeps only the fields /api/asks sent, and a server without them sends none", () => {
    expect(wakeFields(stored(COOLING))).toEqual(COOLING);
    expect(wakeFields(stored({}))).toEqual({});
  });
});

describe("the button, up front", () => {
  it("an old server's row has no target and draws no button", () => {
    expect(ui({}).show).toBe(false);
  });
  it("is named for the seat the ask waits on and is pressable when nothing blocks it", () => {
    expect(ui(IDLE)).toMatchObject({ show: true, label: "Wake test:holder", disabled: false });
    expect(ui(IDLE).status).toBeUndefined();
  });
  it.each(["operator", "closed", "no-pane"] as const)("%s disables it, with the server's reason as the tooltip", (code) => {
    const u = ui({ wakeTarget: "x:y", wakeBlocked: code, wakeBlockedReason: `because ${code}` });
    expect(u.disabled).toBe(true);
    expect(u.title).toBe(`because ${code}`);
  });
  it("no target at all still draws a named, disabled button", () => {
    expect(ui({ wakeTarget: "", wakeBlocked: "no-pane", wakeBlockedReason: "names no seat" })).toMatchObject({ show: true, label: "Wake", disabled: true });
  });
  it("is disabled while a click is on its way", () => {
    expect(ui(IDLE, { busy: true })).toMatchObject({ disabled: true, label: "Waking test:holder…" });
  });
});

describe("the cooldown", () => {
  it("counts down from wakeAfter, and the button stays disabled", () => {
    const u = ui(COOLING);
    expect(u.disabled).toBe(true);
    expect(u.counting).toBe("3:00");
    expect(u.label).toBe("Wake test:holder in 3:00");
  });
  it("formats a countdown with no negative or NaN reading", () => {
    expect(countdown(61_000)).toBe("1:01");
    expect(countdown(1)).toBe("0:01");
    expect(countdown(-5)).toBe("0:00");
  });
  it("a cooldown the server reported but that has since ended no longer disables: no file change fires SSE at its end", () => {
    const u = wakeUi(COOLING, NOW + 3 * MIN, {});
    expect(u.disabled).toBe(false);
    expect(u.counting).toBeUndefined();
  });
  it("a block other than cooldown still holds after wakeAfter", () => {
    expect(wakeUi({ ...COOLING, wakeBlocked: "no-pane", wakeBlockedReason: "gone" }, NOW + 4 * MIN, {}).disabled).toBe(true);
  });
  it("the button refetches at the end of the cooldown, since the next refusal may be no-pane", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/WakeButton.tsx"), "utf8");
    expect(src).toMatch(/wasCounting\.current && !counting[\s\S]{0,60}onChanged\(\)/);
  });
});

describe("what the line says about the latest wake", () => {
  it("delivered: woken N ago, naming the seat", () => {
    expect(ui(COOLING).status).toMatchObject({ tone: "ok", text: "test:holder woken 2m ago" });
  });
  it("just now rather than 0m", () => {
    expect(ui({ ...COOLING, wokenAt: at(-5_000) }).status?.text).toBe("test:holder woken just now");
  });
  it("after a forward it names the seat that was woken, while the button names the new holder", () => {
    const u = ui({ wakeTarget: "test:next", wokenAt: at(-MIN), wokenSeat: "test:holder", wakeDelivery: "delivered" });
    expect(u.status?.text).toBe("test:holder woken 1m ago");
    expect(u.label).toBe("Wake test:next");
    expect(u.disabled).toBe(false);
  });
  it("undelivered says so with the note, never says woken, and leaves the button pressable", () => {
    const u = ui({ wakeTarget: "test:holder", wokenAt: at(-MIN), wokenSeat: "test:holder", wakeDelivery: "undelivered", wakeDeliveryNote: "no live session named test:holder" });
    expect(u.status).toMatchObject({ tone: "warn", text: "test:holder not delivered 1m ago: no live session named test:holder" });
    expect(u.status!.text).not.toMatch(/woken/);
    expect(u.disabled).toBe(false);
  });
  it("undelivered with no note still says not delivered", () => {
    const u = ui({ wakeTarget: "t:h", wokenAt: at(-MIN), wokenSeat: "t:h", wakeDelivery: "undelivered" });
    expect(u.status?.text).toBe("t:h not delivered 1m ago: no reason recorded");
  });
  it("partial says partly delivered, with the note", () => {
    const u = ui({ ...COOLING, wakeDelivery: "partial", wakeDeliveryNote: "one of two" });
    expect(u.status).toMatchObject({ tone: "warn", text: "test:holder partly delivered 2m ago: one of two" });
  });
  it("pending never says woken: the outcome was not recorded", () => {
    const u = ui({ ...COOLING, wakeDelivery: "pending" });
    expect(u.status?.text).toBe("waking test:holder: started 2m ago, delivery not confirmed");
  });
  it("no line claims the seat read, saw or acknowledged anything; the tooltip says delivery is not a read", () => {
    for (const d of ["delivered", "partial", "pending", "undelivered"]) {
      const u = ui({ ...COOLING, wakeDelivery: d, wakeDeliveryNote: "n" });
      expect(u.status!.text).not.toMatch(/\b(read|seen|saw|acknowledged|received)\b/i);
      expect(u.status!.title).toBe(WAKE_WORDS.notARead);
    }
    expect(WAKE_WORDS.notARead).toMatch(/not that the seat read/);
  });
});

describe("a click's own answer, until the next listing catches up", () => {
  const delivered = { ref: "a/b", target: "test:holder", wokenAt: at(0), wokenBy: "operator", delivery: { status: "delivered" as const }, wakeAfter: at(5 * MIN) };
  const failed = { ref: "a/b", target: "test:holder", wokenAt: at(0), wokenBy: "operator", delivery: { status: "undelivered" as const, reason: "socket gone" } };
  it("a 200 starts the countdown at once, before any listing", () => {
    const u = ui(mergeResult(IDLE, delivered));
    expect(u.disabled).toBe(true);
    expect(u.counting).toBe("5:00");
    expect(u.status?.text).toBe("test:holder woken just now");
  });
  it("an undelivered 200 starts no cooldown, even over the pending row the claim wrote", () => {
    const pending: WakeRow = { wakeTarget: "test:holder", wokenAt: at(0), wokenSeat: "test:holder", wakeDelivery: "pending", wakeAfter: at(5 * MIN), wakeBlocked: "cooldown", wakeBlockedReason: "r" };
    const merged = mergeResult(pending, failed);
    // The merged row claims no cooldown at all, so nothing else reading it is told one runs.
    expect(merged.wakeBlocked).toBeUndefined();
    expect(merged.wakeBlockedReason).toBeUndefined();
    expect(merged.wakeAfter).toBeUndefined();
    const u = ui(merged);
    expect(u.disabled).toBe(false);
    expect(u.counting).toBeUndefined();
    expect(u.status?.text).toBe("test:holder not delivered just now: socket gone");
  });
  it("a listing with the outcome stamped wins: a forward since then has moved the target", () => {
    const row: WakeRow = { wakeTarget: "test:next", wokenAt: at(0), wokenSeat: "test:holder", wakeDelivery: "delivered" };
    expect(mergeResult(row, delivered)).toEqual(row);
  });
  it("a later wake's row wins over an earlier click", () => {
    const row: WakeRow = { ...COOLING, wokenAt: at(MIN) };
    expect(mergeResult(row, delivered)).toEqual(row);
  });
  it("a block the row holds besides cooldown is not cleared by an undelivered answer", () => {
    const row: WakeRow = { wakeTarget: "test:holder", wakeBlocked: "no-pane", wakeBlockedReason: "gone" };
    expect(ui(mergeResult(row, failed)).disabled).toBe(true);
  });
});

describe("what an answer from the route becomes", () => {
  const ok = { ref: "a/b", target: "x", wokenAt: at(0), wokenBy: "operator", delivery: { status: "delivered" } };
  it("200 is a result, with a refresh", () => {
    expect(wakeOutcome(200, ok)).toEqual({ result: ok, refresh: true });
  });
  it.each(["operator", "closed", "no-pane", "cooldown"])("409 %s shows the code's reason and the server's words, and refreshes", (code) => {
    const o = wakeOutcome(409, { error: "server words", code });
    expect(o.refresh).toBe(true);
    expect(o.text).toContain(WAKE_WORDS.refused[code]);
    expect(o.text).toContain("server words");
    expect(o.text).toMatch(/^Not woken:/);
  });
  it("a 409 with an unknown code still says not woken, with the server's words", () => {
    expect(wakeOutcome(409, { error: "new rule", code: "later" })).toEqual({ text: "Not woken: new rule", refresh: true });
  });
  it.each([404, 400, 403, 415])("%i says not woken with the server's words", (status) => {
    expect(wakeOutcome(status, { error: "why" }).text).toBe("Not woken: why");
    expect(wakeOutcome(status, {}).text).toBe(`Not woken: HTTP ${status}`);
  });
  it("a restarted server asks for a reload and promises nothing about picks the button did not save", () => {
    for (const r of ["updated", "failed"] as const) {
      const o = wakeOutcome(403, { error: "missing or wrong ask token" }, r);
      expect(o.text).toMatch(/reload/i);
      expect(o.text).not.toMatch(/picks/i);
      expect(o.refresh).toBe(false);
    }
  });
});

describe("the click takes nothing else with it", () => {
  it("clickWake stops the event, and fires once", () => {
    const e = { preventDefault: vi.fn(), stopPropagation: vi.fn() };
    const fire = vi.fn();
    clickWake(e, fire);
    expect(e.preventDefault).toHaveBeenCalledOnce();
    expect(e.stopPropagation).toHaveBeenCalledOnce();
    expect(fire).toHaveBeenCalledOnce();
  });
  it("the card is keyed by ref and revision only, so a wake, which moves no revision, does not remount it and lose picks", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
    expect(src).toContain("key={askRef(current) + current.header.revision}");
  });
  it("the wake path posts an empty body and touches no answer route", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/WakeButton.tsx"), "utf8");
    expect(src).toContain('body: "{}"');
    expect(src).not.toMatch(/api\/(answer|draft|send|discard)/);
    expect(src).not.toMatch(/setValues|setText|setNote/);
  });
});

describe("the sidebar row", () => {
  it("the wake button is a sibling of the row's button, never inside it", async () => {
    const html = await item(IDLE);
    const rowEnd = html.indexOf("</button>");
    expect(html.indexOf('class="row other"')).toBeLessThan(rowEnd);
    expect(html.slice(0, rowEnd)).not.toContain("row-wake");
    expect(html.slice(rowEnd)).toContain('class="row-wake');
    expect(count(html, "<button")).toBe(2);
  });
  it("it is an icon with a type=button, a tooltip and an accessible name", async () => {
    const html = await item(IDLE);
    const b = html.slice(html.indexOf('class="row-wake'));
    expect(b).toContain('type="button"');
    expect(b).toContain('aria-label="Wake test:holder"');
    expect(b).toMatch(/title="[^"]*test:holder/);
    expect(b).toContain("<svg");
  });
  it("the title's own markup is unchanged by it: the row button holds the title as before", async () => {
    const { AskRowButton } = await import("../src/client/App.tsx");
    const a = stored(IDLE);
    const r = askRow(a, NOW, [a]);
    const alone = renderToStaticMarkup(createElement(AskRowButton, { r, current: false, onPick: () => {}, slim: false }));
    expect(await item(IDLE)).toContain(alone);
  });
  it("disabled up front, with the reason as its tooltip, when a click could later get through (no-pane)", async () => {
    const html = await item({ wakeTarget: "test:holder", wakeBlocked: "no-pane", wakeBlockedReason: "nobody holds the seat" });
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*title="nobody holds the seat"|<button[^>]*title="nobody holds the seat"[^>]*disabled=""/);
  });
  it.each(["operator", "closed"] as const)("SHOULD-1: a %s row draws no bell at all, since no click can get past it", async (code) => {
    const html = await item({ wakeTarget: "operator", wakeBlocked: code, wakeBlockedReason: "never" });
    expect(html).not.toContain("row-wake");
    expect(html).not.toContain("has-wake");
  });
  it("an undelivered wake says so on the row itself, not only in a tooltip", async () => {
    // The component reads the real clock, so the wake is placed a minute before it.
    const html = await item({ wakeTarget: "test:holder", wokenAt: new Date(Date.now() - MIN).toISOString(), wokenSeat: "test:holder", wakeDelivery: "undelivered", wakeDeliveryNote: "socket gone" });
    expect(html).toContain("not delivered 1m ago: socket gone");
  });
  it("the cooldown is on the row as a count", async () => {
    expect(await item({ ...COOLING, wakeAfter: new Date(Date.now() + 3 * MIN).toISOString() })).toMatch(/row-wake-count[^>]*>[23]:\d\d</);
  });
  it("an old server's row draws just the row", async () => {
    expect(await item({})).not.toContain("row-wake");
  });
});

describe("the ask card", () => {
  it("an open ask has one button, naming its one target, in the card's head", async () => {
    const html = await detail(IDLE);
    expect(count(html, "wake-btn")).toBe(1);
    expect(html).toContain(">Wake test:holder<");
    expect(html.indexOf("wake-btn")).toBeLessThan(html.indexOf("</header>"));
  });
  it("a closed ask has none, though the row keeps its disabled mark", async () => {
    expect(await detail({ wakeTarget: "test:holder", wakeBlocked: "closed", wakeBlockedReason: "answered" }, "answered")).not.toContain("wake-btn");
  });
  it("the woken line is drawn, and the blocked reason is on the page, not only in a tooltip", async () => {
    expect(await detail({ ...COOLING, wakeAfter: new Date(Date.now() + 3 * MIN).toISOString(), wokenAt: new Date(Date.now() - 2 * MIN).toISOString() })).toContain("test:holder woken 2m ago");
    expect(await detail({ wakeTarget: "test:holder", wakeBlocked: "no-pane", wakeBlockedReason: "nobody home" })).toMatch(/wake-reason[^>]*>nobody home</);
  });
  it("a cooldown's reason is not repeated as a line: the count says it", async () => {
    expect(await detail({ ...COOLING, wakeAfter: new Date(Date.now() + 3 * MIN).toISOString() })).not.toContain("wake-reason");
  });
  it("disabled ones keep a tooltip on a wrapper, since some browsers drop a disabled button's title", async () => {
    expect(await detail({ wakeTarget: "test:holder", wakeBlocked: "no-pane", wakeBlockedReason: "nobody home" })).toMatch(/<span class="wake-wrap" title="nobody home">/);
  });
  it("the row's fields reach the row from the listing", () => {
    const a = stored(COOLING);
    expect(askRow(a, NOW, [a]).wake).toEqual(COOLING);
    const b = stored({});
    expect(askRow(b, NOW, [b]).wake).toBeUndefined();
  });
});
