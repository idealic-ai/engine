/**
 * ASKLISTUI: the client half of AUTOWAKE. /api/asks rows carry the holder notice the server pushed
 * (`noticedAt`, `noticedSeat`, `noticeDelivery`, `noticeDeliveryNote`; WakeView in src/lib/wake.ts),
 * all four absent when no notice was pushed. The wake UI says it quietly, never that the seat read it,
 * and a notice starts no cooldown. Every seat here is synthetic.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { parseAskFile } from "../src/lib/format.ts";
import { askRow } from "../src/client/model.ts";
import { wakeFields, wakeUi, type WakeRow } from "../src/client/wake.ts";

const NOW = Date.parse("2026-11-01T12:00:00.000Z");
const MIN = 60_000;
const at = (ms: number) => new Date(NOW + ms).toISOString();
const ASK = `---\nid: t1\nto: test:holder\nfrom: test:asker\nstatus: open\nrevision: 1\ncreated: 2026-10-30T10:00:00.000Z\n---\n\n## ¶ASK_A: Choose one: First?\n- [ ] [X] One\n- [ ] [Y] Two\n`;
const stored = (w: WakeRow) => ({ ...parseAskFile(ASK), seat: "test:folder", file: "/x.md", mtimeMs: 0, ...w });

const TOLD: WakeRow = { wakeTarget: "test:holder", noticedAt: at(-3 * MIN), noticedSeat: "test:holder", noticeDelivery: "delivered" };
const MISSED: WakeRow = { wakeTarget: "test:holder", noticedAt: at(-3 * MIN), noticedSeat: "test:holder", noticeDelivery: "undelivered", noticeDeliveryNote: "no live pane" };
const NONE: WakeRow = { wakeTarget: "test:holder" };

async function card(w: WakeRow) {
  const { AskDetail } = await import("../src/client/App.tsx");
  const a = stored(w);
  return renderToStaticMarkup(createElement(AskDetail, { ask: a, all: [a], onChanged: () => {} }));
}
async function item(w: WakeRow) {
  const { AskListItem } = await import("../src/client/App.tsx");
  const a = stored(w);
  return renderToStaticMarkup(createElement(AskListItem, { r: askRow(a, NOW, [a]), current: false, onPick: () => {}, slim: false, onChanged: () => {} }));
}

describe("the row keeps the notice fields", () => {
  it("wakeFields carries all four, and only those present", () => {
    expect(wakeFields(stored(MISSED))).toMatchObject({ noticedAt: MISSED.noticedAt, noticedSeat: "test:holder", noticeDelivery: "undelivered", noticeDeliveryNote: "no live pane" });
    expect(Object.keys(wakeFields(stored(NONE)))).toEqual(["wakeTarget"]);
  });
});

describe("the notice line", () => {
  it("delivered: '<seat> told N ago'", () => {
    expect(wakeUi(TOLD, NOW).notice?.text).toBe("test:holder told 3m ago");
  });
  it("undelivered: '<seat> not told: <note>'", () => {
    expect(wakeUi(MISSED, NOW).notice?.text).toBe("test:holder not told: no live pane");
    expect(wakeUi({ ...MISSED, noticeDeliveryNote: undefined }, NOW).notice?.text).toBe("test:holder not told: no reason recorded");
  });
  it("no notice: nothing", () => {
    expect(wakeUi(NONE, NOW).notice).toBeUndefined();
  });
  it("never says the seat read it", () => {
    for (const w of [TOLD, MISSED]) {
      const n = wakeUi(w, NOW).notice!;
      // The one place "read" may appear is the disclaimer that denies it.
      expect(n.title).toMatch(/not that the seat read it/);
      expect(`${n.text} ${n.title.replace("not that the seat read it", "")}`).not.toMatch(/\bread\b|\bseen\b/i);
    }
  });
  it("starts no cooldown: the button stays enabled", () => {
    for (const w of [TOLD, MISSED]) {
      const u = wakeUi(w, NOW);
      expect(u.disabled).toBe(false);
      expect(u.counting).toBeUndefined();
    }
  });
});

describe("the markup", () => {
  it("the card shows the line beside an enabled button", async () => {
    const told = await card(TOLD);
    // The card reads the real clock, so the age is whatever it is; the words around it are fixed.
    expect(told).toMatch(/<span class="wake-notice muted" title="[^"]*">test:holder told (just now|\d+[mhd] ago)<\/span>/);
    expect(told).toMatch(/<button type="button" class="chip toggle wake-btn"(?![^>]*disabled)[^>]*>Wake test:holder<\/button>/);
    expect(await card(MISSED)).toContain("test:holder not told: no live pane");
  });
  it("with no notice the card says nothing about one", async () => {
    const html = await card(NONE);
    expect(html).not.toContain(" told ");
    expect(html).not.toContain("wake-notice");
  });
  it("a sidebar row shows only a notice that did not land", async () => {
    expect(await item(MISSED)).toContain("test:holder not told: no live pane");
    // The row reads the real clock, so look for the words, not an age.
    expect(await item(TOLD)).not.toContain("test:holder told");
  });
});
