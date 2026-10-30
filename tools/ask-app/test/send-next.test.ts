/**
 * Send & next (IDE-304, operator 15:45): beside Send, a secondary button that sends the same way and,
 * once the server accepts, opens the next ask waiting on the operator in the sidebar's current order.
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { NOTHING_WAITING, afterSendNext, nextWaiting } from "../src/client/next.ts";
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
    const html = renderToStaticMarkup(createElement(AskDetail, { ask: ask(), all: [], onChanged: () => {}, onSendNext: () => ({}) }));
    const send = html.indexOf('class="btn primary"');
    const next = html.indexOf(">Send &amp; next</button>");
    expect(send).toBeGreaterThan(-1);
    expect(next).toBeGreaterThan(send);
    expect(html.slice(html.lastIndexOf("<button", next), next)).toMatch(/class="btn"[^>]*title="Sends exactly as Send does/);
  });

  it("no Send & next when the card has nowhere to go (no onSendNext)", async () => {
    const { AskDetail } = await import("../src/client/App.tsx");
    expect(renderToStaticMarkup(createElement(AskDetail, { ask: ask(), all: [], onChanged: () => {} }))).not.toContain("Send &amp; next");
  });

  it("the Change answer form offers it too: the same editable bar renders both", () => {
    // One bar serves the open ask and the Change answer form (`editable` covers `changing`).
    const bar = app.slice(app.indexOf("{editable && ("), app.indexOf("{confirmSend && ("));
    expect(bar).toContain('{changing && <h3>{overrule ? `Overrule ${ask.answer?.answeredBy || "the seat"}` : "Change your answer"}');
    expect(bar).toContain("Send &amp; next");
  });

  it("App hands the card the filtered, searched list and moves only on an accepted send", () => {
    expect(app).toMatch(/onSendNext=\{\(sent\) => \{\s*const r = afterSendNext\(sent, inFilter, askRef\(current\)\);\s*if \(r\.go\) pick\(r\.go\);/);
    expect(app).toContain('{nextNotice && <p className="next-notice muted" role="status">{nextNotice}</p>}');
    // act() reports sent only when the server answered 200 with nothing refused.
    expect(app).toMatch(/const sent = s\.status === 200 && !s\.json\.refused\?\.length;/);
    expect(app).toMatch(/if \(next && sent\)/);
  });
});
