/**
 * Operator 01:29 (live): a server restart left the open tab with a dead token ("missing or wrong ask
 * token" on Send), and scrolling to the next fork moved the page and the sidebar. Plus the same
 * screenshot's markdown, and meta:engine's note on answerInWords.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import fs from "node:fs";
import path from "node:path";
import { parseAskFile } from "../src/lib/format.ts";
import { answerInWords, restoreUnsent } from "../src/client/model.ts";
import { displayTitle } from "../src/client/md.ts";
import { Rich } from "../src/client/rich.tsx";
import { RELOAD_RESTARTED, RELOAD_UPDATED, TOKEN_REJECTED, authedFetch, askToken, resetTokenState } from "../src/client/token.ts";
import { clearUnsent, forgetMemory, loadUnsent, saveUnsent } from "../src/client/unsent.ts";
import { scrollRootOf, scrollWithin, SCROLL_ROOT } from "../src/client/scroll.ts";

const page = (t: string) => `<!doctype html><html><head>\n    <meta name="ask-token" content="${t}"><title>ask-app</title></head><body></body></html>`;
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/** A fake server that restarted: it takes only `live`, serves `build`, and records every request. */
function server(live: string, build: string) {
  const calls: { url: string; token?: string; body?: string }[] = [];
  const f = vi.fn(async (url: string, init: RequestInit = {}) => {
    const token = (init.headers as Record<string, string> | undefined)?.["x-ask-token"];
    calls.push({ url, token, body: init.body as string | undefined });
    if (url === "/") return new Response(page(live), { status: 200 });
    if (url === "/api/health") return json(200, { app: "ask-app", build });
    if (token !== live) return json(403, { error: TOKEN_REJECTED });
    return json(200, { settled: ["s/a1"], pushes: [], refused: [] });
  });
  return { f, calls };
}

afterEach(() => resetTokenState());

describe("a token refused after a server restart", () => {
  it("is refreshed from a fresh page and the same request is retried once, and succeeds", async () => {
    resetTokenState("dead", "b1");
    const { f, calls } = server("fresh", "b1");
    const saved = vi.fn();
    const r = await authedFetch("/api/send", { method: "POST", body: '{"refs":["s/a1"]}' }, { fetch: f, beforeRetry: saved });
    expect(r.status).toBe(200);
    expect(r.restarted).toBeUndefined();
    const sends = calls.filter((c) => c.url === "/api/send");
    expect(sends.map((c) => c.token)).toEqual(["dead", "fresh"]);
    expect(sends[1].body).toBe(sends[0].body);
    expect(saved).toHaveBeenCalledTimes(1);
    expect(askToken()).toBe("fresh");
  });

  it("does not retry when the server now runs another build, and says to reload", async () => {
    resetTokenState("dead", "b1");
    const { f, calls } = server("fresh", "b2");
    const r = await authedFetch("/api/send", { method: "POST", body: "{}" }, { fetch: f });
    expect(r.restarted).toBe("updated");
    expect(calls.filter((c) => c.url === "/api/send")).toHaveLength(1);
    expect(RELOAD_UPDATED).toMatch(/updated — reload to continue/);
  });

  it("retries only once: a second refusal gives up with the restart message", async () => {
    resetTokenState("dead", "b1");
    const f = vi.fn(async (url: string) => (url === "/" ? new Response(page("also-dead")) : url === "/api/health" ? json(200, { build: "b1" }) : json(403, { error: TOKEN_REJECTED })));
    const r = await authedFetch("/api/draft", { method: "POST", body: "{}" }, { fetch: f });
    expect(r.restarted).toBe("failed");
    expect(f.mock.calls.filter(([u]) => u === "/api/draft")).toHaveLength(2);
    expect(RELOAD_RESTARTED).toBe("The app restarted. Reload to continue; your picks are kept.");
  });

  it("leaves every other answer alone: a 409 or a 400 is not retried", async () => {
    resetTokenState("ok", "b1");
    const f = vi.fn(async () => json(409, { error: "stale", revision: 3 }));
    const r = await authedFetch("/api/draft", { method: "POST" }, { fetch: f });
    expect(r).toEqual({ status: 409, json: { error: "stale", revision: 3 } });
    expect(f).toHaveBeenCalledTimes(1);
  });

  it("the card's picks and notes survive a reload: kept in storage per ask, cleared on send", () => {
    const mem = new Map<string, string>();
    const s = { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => void mem.set(k, v), removeItem: (k: string) => void mem.delete(k) };
    const u = { revision: "4", values: { F1: ["A"] }, text: { F2: "a note" }, note: "to the asker" };
    saveUnsent("s/a1", u, s);
    forgetMemory(); // the reload
    expect(loadUnsent("s/a1", s)).toEqual(u);
    const back = restoreUnsent({ values: {}, text: {}, note: "" }, loadUnsent("s/a1", s), "4", ["F1", "F2"]);
    expect(back.values).toEqual({ F1: ["A"] });
    expect(back.text).toEqual({ F2: "a note" });
    clearUnsent("s/a1", s);
    forgetMemory();
    expect(loadUnsent("s/a1", s)).toBeUndefined();
  });

  it("every client request with a token goes through authedFetch: no raw token header is left", () => {
    const dir = path.join(import.meta.dirname, "../src/client");
    for (const f of fs.readdirSync(dir).filter((n) => /\.tsx?$/.test(n) && n !== "token.ts")) {
      expect(fs.readFileSync(path.join(dir, f), "utf8"), f).not.toMatch(/"x-ask-token"/);
    }
  });
});

describe("scrolling moves the ask pane only", () => {
  const box = (top: number, scrollTop = 0) => ({ scrollTop, getBoundingClientRect: () => ({ top }) as DOMRect, scrollTo: vi.fn() });

  it("scrollWithin scrolls the given container to the element, and nothing else", () => {
    const pane = box(100, 250);
    const page = box(0);
    const fork = { getBoundingClientRect: () => ({ top: 420 }) as DOMRect };
    expect(scrollWithin(pane, fork, { behavior: "smooth" })).toBe(true);
    // 420 - 100 + 250 - 8 (breathing room) = 562
    expect(pane.scrollTo).toHaveBeenCalledWith({ top: 562, behavior: "smooth" });
    expect(page.scrollTo).not.toHaveBeenCalled();
    expect(scrollWithin(undefined, fork)).toBe(false);
    expect(scrollWithin(pane, null)).toBe(false);
    expect(pane.scrollTo).toHaveBeenCalledTimes(1);
  });

  it("never scrolls above the top", () => {
    const pane = box(100, 0);
    scrollWithin(pane, { getBoundingClientRect: () => ({ top: 102 }) as DOMRect });
    expect(pane.scrollTo).toHaveBeenCalledWith({ top: 0, behavior: "auto" });
  });

  it("finds the element's own column, marked as a scroll root", () => {
    const root = {};
    const el = { closest: (sel: string) => (sel === `[${SCROLL_ROOT}]` ? root : null) } as unknown as Element;
    expect(scrollRootOf(el)).toBe(root);
    expect(scrollRootOf(null)).toBeNull();
  });

  it("no scrollIntoView is left in the client, and the ask pane and the list are scroll roots", async () => {
    const dir = path.join(import.meta.dirname, "../src/client");
    for (const f of fs.readdirSync(dir).filter((n) => /\.tsx?$/.test(n) && n !== "scroll.ts")) {
      expect(fs.readFileSync(path.join(dir, f), "utf8"), f).not.toMatch(/scrollIntoView/);
    }
    const app = fs.readFileSync(path.join(dir, "App.tsx"), "utf8");
    expect(app).toMatch(/<main className="detail" ref=\{detail\} \{\.\.\.\{ \[SCROLL_ROOT\]: "" \}\}>/);
    expect(app).toMatch(/<nav className=\{`side[^`]*`\} \{\.\.\.\{ \[SCROLL_ROOT\]: "" \}\}/);
  });

  it("the shell clips rather than hides where it can, so a script cannot scroll it", () => {
    const css = fs.readFileSync(path.join(import.meta.dirname, "../src/client/styles.css"), "utf8");
    expect(css).toMatch(/html, body, #root \{[^}]*overflow: hidden; overflow: clip;/);
    expect(css).toMatch(/\n\.app \{[^}]*overflow: hidden; overflow: clip;/);
  });
});

describe("the same screenshot's markdown", () => {
  it("strips ¶ASK_X with or without its colon", () => {
    expect(displayTitle("¶ASK_SNAR Run /snapshot --yes on the branch")).toBe("Run /snapshot --yes on the branch");
    expect(displayTitle("¶ASK_SNAR: Run it")).toBe("Run it");
    expect(displayTitle("ASK_RATE limits")).toBe("ASK_RATE limits"); // no ¶ and no colon: not an anchor
  });
  it("renders a '# heading' line at the top of prose as a heading", () => {
    const html = renderToStaticMarkup(createElement(Rich, { text: "# IDE150-ARCH is ready for review\n\nThe body." }));
    expect(html).toContain('<h4 class="md-h"><span>IDE150-ARCH is ready for review</span></h4>');
    expect(html).not.toContain("# IDE150");
  });
});

describe("answerInWords (meta:engine)", () => {
  it("names the option for a single pick stored as a string, the same as for a list", () => {
    const head = "---\nid: a1\nto: operator\nfrom: x\nstatus: answered\nrevision: 2\n---\n\n";
    const a = parseAskFile(head + "## ¶ASK_EL: Choose one: Where?\n- [ ] [ELEM] On the element\n- [ ] [DOC] On the document\n\n## ¶ASK_T: Text: Why?\n");
    const words = answerInWords(a, { answers: { EL: "ELEM", T: "because" } });
    expect(words[0].picks).toEqual(["ELEM · On the element"]);
    expect(answerInWords(a, { answers: { EL: ["ELEM"] } })[0].picks).toEqual(["ELEM · On the element"]);
    expect(words[1].picks).toEqual(["because"]);
  });
});
