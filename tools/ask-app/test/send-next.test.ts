/**
 * Send & next (IDE-304, operator 15:45): beside Send, a secondary button that sends the same way and,
 * once the server accepts, opens the next ask waiting on the operator in the sidebar's current order.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { NOTHING_WAITING, afterSendNext, nextWaiting, noticeFor, postSendStep, sendOutcome } from "../src/client/next.ts";
import { parseAskFile } from "../src/lib/format.ts";

const row = (ref: string, waitingOnYou = true) => ({ ref, waitingOnYou });
const app = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");

describe("nextWaiting: the next ask in the list's order", () => {
  it("follows the order it is given (the filtered, searched list), not any other", () => {
    const list = [row("x/c"), row("x/a"), row("x/b")];
    expect(nextWaiting(list, "x/c")).toBe("x/a");
    expect(nextWaiting(list, "x/a")).toBe("x/b");
  });

  it("skips the ask just sent and asks not waiting on the operator", () => {
    expect(nextWaiting([row("a"), row("b", false), row("c")], "a")).toBe("c");
    // The sent row still says waiting until the list reloads; it is never its own next.
    expect(nextWaiting([row("a")], "a")).toBeUndefined();
  });

  it("nothing comes after the last ask when nothing above it waits either", () => {
    expect(nextWaiting([row("a", false), row("b", false), row("c")], "c")).toBeUndefined();
  });

  it("an ask above the sent one that still waits is found by wrapping round", () => {
    expect(nextWaiting([row("a"), row("b", false), row("c")], "c")).toBe("a");
  });

  it("when the sent ask is not in the list (filtered out), the first waiting row is next", () => {
    expect(nextWaiting([row("a", false), row("b")], "gone")).toBe("b");
  });
});

describe("afterSendNext: only an accepted send moves on", () => {
  const list = [row("a"), row("b")];
  it("a failed or refused send does not navigate and says nothing", () => {
    expect(afterSendNext(false, list, "a")).toEqual({});
  });
  it("an accepted send goes to the next waiting ask", () => {
    expect(afterSendNext(true, list, "a")).toEqual({ go: "b" });
  });
  it("an accepted send with nothing else waiting stays and says so quietly", () => {
    expect(afterSendNext(true, [row("a")], "a")).toEqual({ notice: NOTHING_WAITING });
    expect(NOTHING_WAITING).toBe("Nothing else is waiting on you.");
  });
});

describe("the button and its wiring", () => {
  const head = "---\nid: a1\nto: operator\nfrom: x\nstatus: open\nrevision: 1\n---\n\n";
  const ask = () => ({ ...parseAskFile(head + "## ¶ASK_R: Choose one: Return shape?\n- [ ] [TUP] Tuple\n- [ ] [OBJ] Object\n"), seat: "x", file: "/x.md", mtimeMs: 0 });

  it("an open ask's bar has Send (primary) then Send & next (secondary)", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: ask(), all: [], onChanged: () => {}, onSent: () => {} }));
    const send = html.indexOf('class="btn primary"');
    const next = html.indexOf(">Send &amp; next</button>");
    expect(send).toBeGreaterThan(-1);
    expect(next).toBeGreaterThan(send);
    expect(html.slice(html.lastIndexOf("<button", next), next)).toMatch(/class="btn"[^>]*title="Sends exactly as Send does/);
  });

  it("no Send & next when the card has nowhere to go (no onSent)", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    expect(renderToStaticMarkup(createElement(AskDetail, { ask: ask(), all: [], onChanged: () => {} }))).not.toContain("Send &amp; next");
  });

  it("the Change answer form offers it too: the same editable bar renders both", () => {
    // One bar serves the open ask and the Change answer form (`editable` covers `changing`).
    const bar = app.slice(app.indexOf("{editable && ("), app.indexOf("{confirmSend && ("));
    expect(bar).toContain('{changing && <h3>{overrule ? `Overrule ${ask.answer?.answeredBy || "the seat"}` : "Change your answer"}');
    expect(bar).toContain("Send &amp; next");
  });

  it("App hands the card the filtered, searched list, read when the send resolves", () => {
    expect(app).toMatch(/onSent=\{\(text, next\) => \{[\s\S]*?postSendStep\(\{ sentRef: askRef\(current\), text, next, routeAsk: routeNow\.current\.ask, shownRef: shownAsk\.current, rows: inFilter \}\);\s*if \(step\.go\) return pick\(step\.go\);\s*if \(step\.notice\) setSentNotice\(step\.notice\);\s*if \(step\.pin\) navigate\(\{ ask: step\.pin \}, false\);/);
    // act() calls onSent only after sendOutcome says sent.
    expect(app).toMatch(/const out = sendOutcome\(s\.status, s\.json\);\s*if \(!out\.sent\) \{\s*keep\(\);\s*setResult\(out\.text\);\s*return onChanged\(\);\s*\}\s*clearUnsent\(keyFor\(changing\)\);\s*onChanged\(\);\s*if \(onSent\) onSent\(out\.text, next\);/);
  });
});

describe("fix round 1 (ASKHL_CRITIQUE.md)", () => {
  const head = (rev: number) => `---\nid: a1\nto: operator\nfrom: x\nstatus: open\nrevision: ${rev}\n---\n\n`;
  const ask = (rev: number) => ({ ...parseAskFile(head(rev) + "## ¶ASK_R: Choose one: Return shape?\n- [ ] [TUP] Tuple\n- [ ] [OBJ] Object\n"), seat: "x", file: "/x.md", mtimeMs: 0 });

  it("MUST-FIX-1: the notice is keyed by ref, so it outlives the revision bump a send makes", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    const held = { ref: "x/a1", text: `Queued at x, not read yet. ${NOTHING_WAITING}` };
    for (const rev of [1, 2]) {
      const a = ask(rev);
      // App renders the card keyed askRef + revision; the notice comes from App's state by ref alone.
      const html = renderToStaticMarkup(createElement(AskDetail, { key: `x/a1${rev}`, ask: a, all: [a], onChanged: () => {}, onSent: () => {}, sentNotice: noticeFor(held, "x/a1") }));
      expect(html, `revision ${rev}`).toContain(`<p class="result sent-notice" role="status">${held.text}</p>`);
    }
    expect(noticeFor(held, "x/other")).toBeUndefined();
    // The state is App's, not the card's: the card has no notice state of its own to lose.
    const card = app.slice(app.indexOf("export function AskDetail("));
    expect(card.slice(0, card.indexOf("\n}\n"))).not.toMatch(/nextNotice|useState[^\n]*sentNotice/);
    expect(app).toMatch(/const \[sentNotice, setSentNotice\] = useState<SentNotice \| undefined>\(\);/);
    expect(app).toContain("sentNotice={noticeFor(sentNotice, currentRef)}");
  });

  it("MUST-FIX-1: nothing left keeps both lines for the sent ask and names it when the URL did not", () => {
    const r = postSendStep({ sentRef: "a", text: "Queued at x, not read yet.", next: true, routeAsk: undefined, shownRef: "a", rows: [{ ref: "a", waitingOnYou: true }] });
    expect(r).toEqual({ notice: { ref: "a", text: `Queued at x, not read yet. ${NOTHING_WAITING}` }, pin: "a" });
    expect(postSendStep({ sentRef: "a", text: "Queued.", next: false, routeAsk: "a", shownRef: "a", rows: [] })).toEqual({ notice: { ref: "a", text: "Queued." } });
  });

  it("SHOULD-1: a non-200 send is a failure with the server's words; only a clean 200 is sent", () => {
    expect(sendOutcome(500, { error: "disk full" })).toEqual({ sent: false, text: "Error: disk full" });
    expect(sendOutcome(403, undefined)).toEqual({ sent: false, text: "Error: HTTP 403" });
    expect(sendOutcome(200, { refused: [{ error: "stale" }] })).toEqual({ sent: false, text: "Refused: stale" });
    expect(sendOutcome(200, { pushes: [{ seat: "x", delivery: { status: "delivered" } }] }).sent).toBe(true);
    expect(sendOutcome(200, {})).toEqual({ sent: true, text: "" });
  });

  it("SHOULD-2: a send that resolves after the operator opened another ask does not move them", () => {
    const rows = [{ ref: "a", waitingOnYou: true }, { ref: "b", waitingOnYou: true }];
    expect(postSendStep({ sentRef: "a", text: "", next: true, routeAsk: "c", shownRef: "c", rows })).toEqual({});
    // No ask named, but the list now shows another one on screen: still stays.
    expect(postSendStep({ sentRef: "a", text: "", next: true, routeAsk: undefined, shownRef: "b", rows })).toEqual({});
    // Still on the sent ask: moves on.
    expect(postSendStep({ sentRef: "a", text: "", next: true, routeAsk: "a", shownRef: "a", rows })).toEqual({ go: "b" });
    expect(postSendStep({ sentRef: "a", text: "", next: true, routeAsk: undefined, shownRef: "a", rows })).toEqual({ go: "b" });
  });
});
