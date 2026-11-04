/**
 * COMMSUI: the Comms tab, the client half of TELL's GET /api/comms (src/lib/comms.ts, CommsRow).
 * A tab beside Asks, Proofs and Broadcasts; one row per tell, broadcast or ask with from → to, tier,
 * subject, time, the withdrawal struck through with who and why, the managers' align notice and the
 * ask linked; filters by seat and tier kept in the URL; a reload on the SSE `change`; and empty and
 * error states that never read a failure as "no messages". Server-side render only (react-dom/server).
 *
 * The e2e block at the end runs the real server (from 89693ee) over fixture records in temp dirs and
 * renders what it answered; nothing reads the live store.
 */
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { BUILD_ID_FILE, computeBuildId } from "../src/build-id.ts";
import type { CommsRow, Tier } from "../src/lib/comms.ts";
import { isNavigation, normalizeRoute, parseRoute, serializeRoute, viewPatch, type Route } from "../src/client/route.ts";
import { createRouteNav, createUrlSync } from "../src/client/urlsync.ts";
import { CommsFeed, CommsFilters, CommsRows, askLink, commHref, commsMissing, commsQuery, commsResult, createCommsLoader, fetchComms, listenComms, pinnedReducer, scrollStep, seatCounts, seatStateLabel, stateLabel, uniqueKeys, type CommsState, type ScrollMemo } from "../src/client/comms.tsx";

const NOW = Date.parse("2026-11-04T12:00:00Z");
const row = (o: Partial<CommsRow>): CommsRow => ({
  id: "x",
  kind: "tell",
  from: "app:ask",
  sentBy: "app:ask",
  to: ["domain:stats"],
  tier: "lazy",
  subject: "s",
  at: "2026-11-04T10:00:00Z",
  state: "queued",
  seats: [],
  withdrawn: null,
  notice: null,
  noticeOf: null,
  forSeats: [],
  ref: "/tmp/x.md",
  ...o,
});
const ALIGN = row({ id: "a1", tier: "align", subject: "stats schema moved", at: "2026-11-04T10:05:00Z", notice: "a1.align", seats: [{ seat: "domain:stats", state: "queued" }] });
const NOTICE = row({ id: "a1.align", tier: "note", from: "app:ask", to: ["manager:app", "manager:domain"], subject: "these two are talking: stats schema moved", noticeOf: "a1" });
const GONE = row({ id: "d1", subject: "ignore me", to: ["app:ui"], state: "withdrawn", withdrawn: { by: "manager:app", at: "2026-11-04T09:01:00Z", reason: "sent to the wrong seat" } });
// The landed contract (d90ef82..61b3371): an ask has tier null and a ref encoded per segment.
const ASK = row({ id: "app:ask/20261104-q1", kind: "ask", tier: null, to: ["manager:app"], subject: "parser order", state: "open", ref: "/a/app%3Aask/20261104-q1" });
const ok = (rows: CommsRow[], query = ""): CommsState => ({ query, rows, error: "", at: "2026-11-04T11:59:00Z" });
const feed = (state: CommsState | undefined, extra: Record<string, unknown> = {}) =>
  renderToStaticMarkup(createElement(CommsFeed, { state, query: state?.query ?? "", now: NOW, onComm: () => {}, onOpenAsk: () => {}, onSeat: () => {}, ...extra }));
const side = (state: CommsState | undefined, filtered = false, query = state?.query ?? "") => renderToStaticMarkup(createElement(CommsRows, { state, query, filtered, onPick: () => {}, slim: false, now: NOW }));
const alerts = (html: string) => html.split('role="alert"').length - 1;
const filters = (seat?: string, tier?: Tier[], kind?: CommsRow["kind"][]) => renderToStaticMarkup(createElement(CommsFilters, { seat, tier, kind, onKind: () => {}, seats: ["app:ask", "domain:stats"], onSeat: () => {}, onTier: () => {}, onReload: () => {}, busy: false, at: "2026-11-04T11:59:00Z" }));

describe("route: the Comms section and its filters live in the URL", () => {
  it("parses /comms and /comms/<id> with ?seat= and ?tier=", () => {
    expect(parseRoute("/comms")).toMatchObject({ section: "comms" });
    expect(parseRoute("/comms/a1.align", "?seat=app:ask&tier=align,note")).toMatchObject({ section: "comms", comm: "a1.align", seat: "app:ask", tier: ["align", "note"] });
    // An ask row's id carries a slash.
    expect(parseRoute("/comms/app:ask/20261104-q1")).toMatchObject({ comm: "app:ask/20261104-q1" });
  });
  it("drops a tier it does not know and an empty seat", () => {
    expect(parseRoute("/comms", "?tier=bogus,lazy&seat=").tier).toEqual(["lazy"]);
    expect(parseRoute("/comms", "?seat=").seat).toBeUndefined();
    expect(parseRoute("/comms", "?tier=bogus").tier).toBeUndefined();
  });
  it("serializes back to the same URL, readable", () => {
    const u = "/comms/a1.align?seat=app:ask&tier=align,note";
    const r = parseRoute("/comms/a1.align", "?seat=app:ask&tier=align,note");
    expect(serializeRoute(r)).toBe(u);
    expect(serializeRoute(parseRoute("/comms"))).toBe("/comms");
    expect(serializeRoute(parseRoute("/comms/app:ask/20261104-q1"))).toBe("/comms/app:ask/20261104-q1");
  });
  it("keeps seat and tier out of the other sections' URLs", () => {
    expect(serializeRoute({ ...parseRoute("/"), seat: "app:ask", tier: ["lazy"] })).toBe("/");
    expect(parseRoute("/", "?seat=app:ask&tier=lazy")).not.toHaveProperty("seat");
  });
  it("a row picked is Back-worthy; a filter change is not", () => {
    const a = parseRoute("/comms");
    expect(isNavigation(a, { ...a, comm: "a1" })).toBe(true);
    expect(isNavigation(a, { ...a, seat: "app:ask" })).toBe(false);
    expect(isNavigation(a, { ...a, tier: ["note"] })).toBe(false);
  });
});

describe("the query the tab sends", () => {
  it("names the seat and the tiers, and nothing when unfiltered", () => {
    expect(commsQuery({})).toBe("/api/comms");
    expect(commsQuery({ seat: "app:ask", tier: ["align", "note"] })).toBe("/api/comms?seat=app%3Aask&tier=align%2Cnote");
    expect(commsQuery({ tier: [] })).toBe("/api/comms");
  });
});

describe("commsResult: an answer, or a failure that says so", () => {
  it("takes the rows from a 200", () => {
    const s = commsResult("q", { status: 200, json: { rows: [ALIGN] } }, "t");
    expect(s).toEqual({ query: "q", rows: [ALIGN], error: "", at: "t" });
  });
  it("a refusal, a restart and a body with no rows are errors, never an empty list", () => {
    expect(commsResult("q", { status: 403, json: { error: "missing or wrong ask token" } }, "t")).toMatchObject({ error: "missing or wrong ask token" });
    expect(commsResult("q", { status: 403, json: {}, restarted: "failed" }, "t").error).toMatch(/restarted/);
    expect(commsResult("q", { status: 500, json: {} }, "t").error).toBe("HTTP 500");
    expect(commsResult("q", { status: 200, json: { broadcasts: [] } }, "t").error).toMatch(/no rows/);
    expect(commsResult("q", { status: 404, json: { error: "not found" } }, "t").rows).toBeUndefined();
  });
  it("keeps the rows it had for the same query when a reload fails, and drops them for another", () => {
    const prev = ok([ALIGN], "q");
    const same = commsResult("q", { status: 500, json: {} }, "t2", prev);
    expect(same).toMatchObject({ rows: [ALIGN], error: "HTTP 500", at: prev.at });
    expect(commsResult("other", { status: 500, json: {} }, "t2", prev).rows).toBeUndefined();
  });
});

describe("CommsFeed: one row per message", () => {
  it("shows from → to, tier, subject and time", () => {
    const html = feed(ok([ALIGN]));
    expect(html).toContain('id="cm-a1"');
    expect(html).toMatch(/app:ask<\/button> → <button[^>]*>domain:stats<\/button>/);
    expect(html).toContain('<span class="chip tier tier-align">align</span>');
    expect(html).toContain("stats schema moved");
    expect(html).toContain('title="2026-11-04T10:05:00Z">1h ago</span>');
  });
  it("strikes a withdrawn message through and says who withdrew it and why", () => {
    const html = feed(ok([GONE]));
    expect(html).toContain('class="fork comm withdrawn');
    expect(html).toContain("<s>ignore me</s>");
    expect(html).toMatch(/Withdrawn by <b>manager:app<\/b> <span title="2026-11-04T09:01:00Z">[^<]+<\/span>: sent to the wrong seat/);
    expect(feed(ok([ALIGN]))).not.toContain("<s>");
  });
  it("links an align tell to its managers' notice, and the notice back to its tell", () => {
    const html = feed(ok([ALIGN, NOTICE]));
    expect(html).toContain('href="/comms/a1.align"');
    expect(html).toMatch(/managers&#x27; notice/);
    expect(html).toContain('href="/comms/a1"');
    // No notice, no link.
    expect(feed(ok([GONE]))).not.toContain("notice");
  });
  it("links an ask into the ask", () => {
    const html = feed(ok([ASK]));
    expect(html).toContain('href="/a/app:ask/20261104-q1"');
    expect(html).toContain("Open the ask");
    expect(feed(ok([ALIGN]))).not.toContain("Open the ask");
  });
  it("says who an escalate was meant for and who sent a broadcast on another's behalf", () => {
    const html = feed(ok([row({ id: "e1", tier: "escalate", to: ["manager:app"], forSeats: ["domain:stats"] }), row({ id: "b1", kind: "broadcast", from: "manager:director", sentBy: "app:ask" })]));
    expect(html).toContain("meant for domain:stats");
    expect(html).toContain("sent by app:ask");
  });
  it("a row with no time says so rather than showing nothing", () => {
    expect(feed(ok([row({ id: "t0", at: "" })]))).toContain("no time");
  });
  it("marks the picked row and warns when it is not in this view", () => {
    expect(feed(ok([ALIGN]), { current: "a1" })).toContain('class="fork comm current');
    expect(feed(ok([ALIGN]), { current: "zz", filtered: true })).toMatch(/Looking up “zz”, which these filters hide/);
  });
});

describe("empty and error states never pass a failure off as no messages", () => {
  it("loading", () => {
    expect(feed(undefined)).toContain("Loading messages");
  });
  it("an error with nothing to show is an alert, not 'no messages'", () => {
    const html = feed({ query: "q", rows: undefined, error: "HTTP 500", at: "t" });
    expect(html).toContain('role="alert"');
    expect(html).toContain("The comms feed could not be read");
    expect(html).toContain("HTTP 500");
    expect(html).not.toMatch(/No messages/);
  });
  it("an error over rows it read earlier says the rows are stale", () => {
    const html = feed({ ...ok([ALIGN]), error: "the app server did not answer" });
    expect(html).toContain('role="alert"');
    expect(html).toMatch(/last read/i);
    expect(html).toContain("stats schema moved");
  });
  it("empty with no filter, and empty under a filter, say which", () => {
    expect(feed(ok([]))).toContain("The feed answered with no messages.");
    const f = feed(ok([]), { filtered: true });
    expect(f).toContain("No messages match these filters.");
    expect(f).not.toContain("The feed answered with no messages.");
  });
  it("the sidebar list follows the same rules", () => {
    expect(side(undefined)).toContain("Loading");
    const err = side({ query: "q", rows: undefined, error: "HTTP 500", at: "t" });
    expect(err).toContain("could not be read");
    expect(err).not.toMatch(/No messages/);
    expect(side(ok([]))).toContain("No messages.");
    expect(side(ok([]), true)).toContain("No messages match");
    const one = side(ok([GONE]));
    expect(one).toContain("<s>ignore me</s>");
    expect(one).toContain("app:ask → app:ui");
  });
});

describe("CommsFilters", () => {
  it("offers every tier as a toggle, pressed when it is in the filter", () => {
    const html = filters(undefined, ["align"]);
    for (const t of ["note", "lazy", "align", "escalate", "wake"]) expect(html).toContain(`>${t}</button>`);
    expect(html).toContain('aria-pressed="true">align</button>');
    expect(html).toContain('aria-pressed="false">note</button>');
  });
  it("a seat box that knows the seats seen, holding the current seat", () => {
    const html = filters("app:ask");
    expect(html).toContain('value="app:ask"');
    expect(html).toContain('<option value="domain:stats">');
    expect(html).toContain("Clear");
  });
  it("a Refresh, and when the feed was last read", () => {
    const html = filters();
    expect(html).toContain("Refresh");
    expect(html).toContain('title="2026-11-04T11:59:00Z"');
  });
});

describe("App wiring (source): the tab, its feed, and the SSE reload", () => {
  const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
  it("lists Comms beside Asks, Proofs and Broadcasts", () => {
    expect(src).toMatch(/\["asks", "proofs", "broadcasts", "comms"\]/);
  });
  it("reloads the comms feed on every SSE change and comms event", () => {
    expect(src).toMatch(/listenComms\(es, \(\) => setChangeTick\(\(n\) => n \+ 1\)\)/);
    expect(src).toMatch(/useComms\(view === "comms", [^)]*changeTick\)/);
  });
});

// ---- e2e: the real /api/comms (TELL as landed: d90ef82, ff2207e, 61b3371), rendered by the tab ----

const TOKEN = "t0k3n-commsui";
let base: string, port: number, proc: ChildProcess, bdir: string, askRoot: string;

const REC = (o: { id: string; from: string; at: string; audience: string; extra: string; text: string; delivery: string; tail?: string }) =>
  `# Broadcast ${o.id}\n\nid: ${o.id}\nfrom: ${o.from}\nsent-by: ${o.from}\nat: ${o.at}\nscope: to:${o.audience.replace(/ /g, ",")}\nsticky: no\nexpires: -\naudience: ${o.audience}\n${o.extra}\n## Text\n\n${o.text}\n\n## Delivery\n\n${o.delivery}\n${o.tail ?? ""}`;

function req(p: string): Promise<{ status: number; json: any }> {
  return new Promise((resolve, reject) => {
    const r = http.request({ host: "127.0.0.1", port, path: p, method: "GET", headers: { host: `127.0.0.1:${port}`, "x-ask-token": TOKEN } }, (res) => {
      let b = "";
      res.on("data", (d) => (b += d));
      res.on("end", () => resolve({ status: res.statusCode!, json: JSON.parse(b || "{}") }));
    });
    r.on("error", reject);
    r.end();
  });
}

describe("e2e: the tab over the real /api/comms", () => {
  beforeAll(async () => {
    base = fs.mkdtempSync(path.join("/tmp", "askcommsui-"));
    bdir = path.join(base, "broadcasts");
    askRoot = path.join(base, "asks");
    fs.mkdirSync(bdir);
    fs.mkdirSync(path.join(askRoot, "app:ask"), { recursive: true });
    const w = (id: string, body: string) => fs.writeFileSync(path.join(bdir, `${id}.md`), body);
    w("a1", REC({ id: "a1", from: "app:ask", at: "2026-11-04T10:05:00Z", audience: "domain:stats", extra: "message: tell\ntier: align\nsubject: stats schema moved\nnotice: a1.align\n", text: "stats schema moved", delivery: "queued domain:stats pid=2007" }));
    w("a1.align", REC({ id: "a1.align", from: "app:ask", at: "2026-11-04T10:05:01Z", audience: "manager:app manager:domain", extra: "message: tell\ntier: note\nsubject: these two are talking: stats schema moved\nnotice-of: a1\n", text: "talking", delivery: "queued manager:app pid=2002\nqueued manager:domain pid=2003" }));
    w("d1", REC({ id: "d1", from: "app:ask", at: "2026-11-04T09:00:00Z", audience: "app:ui", extra: "message: tell\ntier: lazy\nsubject: ignore me\n", text: "ignore me", delivery: "queued app:ui pid=2005", tail: "\n## Withdrawn\n\nwithdrawn: by manager:app at 2026-11-04T09:01:00Z — sent to the wrong seat\n" }));
    fs.writeFileSync(
      path.join(askRoot, "app:ask", "20261104-q1.md"),
      "---\nid: 20261104-q1\nto: manager:app\nfrom: app:ask\ntopic: parser order\nstatus: open\nrevision: 1\ncreated: 2026-11-04T10:10:00.000Z\n---\n\n## Which parser goes first?\n\n- [ ] [A] Ours\n- [ ] [B] Theirs\n",
    );
    const dist = path.join(base, "dist");
    fs.mkdirSync(dist);
    fs.writeFileSync(path.join(dist, "index.html"), "<!doctype html><html><head><title>ask-app</title></head><body></body></html>\n");
    fs.writeFileSync(path.join(dist, BUILD_ID_FILE), `${computeBuildId()}\n`);
    port = 30000 + Math.floor(Math.random() * 20000);
    const env: NodeJS.ProcessEnv = { ...process.env, BROADCAST_DIR: bdir, ASK_SESSIONS_DIR: path.join(base, "s"), ASK_LINEAR_ENV: "/dev/null", ASK_APP_DIST: dist, ASK_SEARCH_AUTO: "0" };
    delete env.LINEAR_API_KEY;
    proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", askRoot, "--port", String(port), "--token", TOKEN], { env, stdio: "ignore" });
    for (let i = 0; i < 200; i++) {
      try {
        if ((await req("/api/health")).status === 200) return;
      } catch {
        // not up yet
      }
      await new Promise((r) => setTimeout(r, 50));
    }
    throw new Error("server did not start");
  }, 30000);
  afterAll(() => {
    proc?.kill();
    if (base) fs.rmSync(base, { recursive: true, force: true });
  });

  it("renders every row the server answered, with the withdrawal, the notice link and the ask link", async () => {
    const q = commsQuery({});
    const s = commsResult(q, await req(q), "t");
    expect(s.error).toBe("");
    expect(s.rows!.map((r) => r.id)).toEqual(["app:ask/20261104-q1", "a1.align", "a1", "d1"]);
    const html = feed(s);
    expect(html).toContain('href="/a/app:ask/20261104-q1"');
    expect(html).toContain('href="/comms/a1.align"');
    expect(html).toContain("<s>ignore me</s>");
    expect(html).toContain("sent to the wrong seat");
  });

  it("the seat and tier filters the tab sends are the ones the server applies", async () => {
    const q = commsQuery({ seat: "manager:domain" });
    expect(commsResult(q, await req(q), "t").rows!.map((r) => r.id)).toEqual(["a1.align"]);
    const t = commsQuery({ tier: ["align", "note"] });
    expect(commsResult(t, await req(t), "t").rows!.map((r) => r.id)).toEqual(["a1.align", "a1"]);
    const both = commsQuery({ seat: "app:ui", tier: ["lazy"] });
    expect(commsResult(both, await req(both), "t").rows!.map((r) => r.id)).toEqual(["d1"]);
  });

  describe("e2e on the landed server: kind, id and the comms event", () => {
    it("kind=ask is the ask alone, with tier null and no tier chip", async () => {
      const q = commsQuery({ kind: ["ask"] });
      const s = commsResult(q, await req(q), "t");
      expect(s.rows!.map((r) => [r.id, r.tier])).toEqual([["app:ask/20261104-q1", null]]);
      expect(feed(s)).not.toMatch(/tier-/);
      // A tier filter leaves the ask out.
      const t = commsQuery({ tier: ["lazy"] });
      expect(commsResult(t, await req(t), "t").rows!.map((r) => r.kind)).not.toContain("ask");
    });
    it("id= returns exactly the hidden notice, whatever the filter would say", async () => {
      const q = commsQuery({ ids: ["a1.align"], seat: "app:ui" });
      expect(commsResult(q, await req(q), "t").rows!.map((r) => r.id)).toEqual(["a1.align"]);
    });
    it("the ask's encoded ref still makes the in-app link", async () => {
      const q = commsQuery({ kind: ["ask"] });
      const r = commsResult(q, await req(q), "t").rows![0];
      expect(r.ref).toBe("/a/app%3Aask/20261104-q1");
      expect(feed(ok([r]))).toContain('href="/a/app:ask/20261104-q1"');
    });
    it("a new tell fires event: comms on /api/events, and the reload shows it", async () => {
      const got = await new Promise<string>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error("no comms event within 6s")), 6000);
        const r = http.get({ host: "127.0.0.1", port, path: "/api/events", headers: { host: `127.0.0.1:${port}` } }, (res) => {
          let buf = "";
          let wrote = false;
          res.on("data", (d) => {
            buf += d;
            if (!wrote && buf.includes("event: hello")) {
              wrote = true;
              fs.writeFileSync(path.join(bdir, "n2.md"), REC({ id: "n2", from: "app:ask", at: "2026-11-04T11:00:00Z", audience: "app:ui", extra: "message: tell\ntier: lazy\nsubject: fresh one\n", text: "fresh one", delivery: "queued app:ui pid=2005" }));
            }
            if (buf.includes("event: comms")) {
              clearTimeout(timer);
              r.destroy();
              resolve("comms");
            }
          });
        });
        r.on("error", (e) => (e.message.includes("socket hang up") ? undefined : reject(e)));
      });
      expect(got).toBe("comms");
      const q = commsQuery({});
      expect(feed(commsResult(q, await req(q), "t"))).toContain("fresh one");
    }, 15000);
  });
});


// ---- COMMSUI fix round (COMMSUI_CRITIQUE.md) ----

describe("MF-1: a state read for another query is never shown as this query's answer", () => {
  const X = commsQuery({ seat: "app:x" });
  const Y = commsQuery({ seat: "app:y" });
  it("the feed shows loading, not X's rows and not 'No messages match'", () => {
    const withRows = feed({ query: X, rows: [ALIGN], error: "", at: "t" }, { query: Y, filtered: true });
    expect(withRows).toContain("Loading messages");
    expect(withRows).not.toContain("stats schema moved");
    expect(withRows).not.toContain('class="n"');
    const empty = feed({ query: X, rows: [], error: "", at: "t" }, { query: Y, filtered: true });
    expect(empty).toContain("Loading messages");
    expect(empty).not.toMatch(/No messages/);
  });
  it("the sidebar does the same", () => {
    const withRows = side({ query: X, rows: [ALIGN], error: "", at: "t" }, true, Y);
    expect(withRows).toContain("Loading messages");
    expect(withRows).not.toContain("stats schema moved");
    const empty = side({ query: X, rows: [], error: "", at: "t" }, true, Y);
    expect(empty).toContain("Loading messages");
    expect(empty).not.toMatch(/No messages/);
  });
  it("a hung request ends as an error after the timeout, never as an empty list", async () => {
    const hang = (_u: string, init?: RequestInit) => new Promise<Response>((_r, reject) => init?.signal?.addEventListener("abort", () => reject(new Error("aborted"))));
    const r = await fetchComms(X, { fetch: hang, timeoutMs: 30 });
    expect(r.status).toBe(0);
    expect(r.json.error).toMatch(/did not answer within/);
    const s = commsResult(X, r, "t");
    expect(s.rows).toBeUndefined();
    expect(s.error).toMatch(/did not answer/);
  });
});

describe("N-3: the newest load wins", () => {
  const deferred = () => {
    let resolve!: (v: { status: number; json: any }) => void;
    const p = new Promise<{ status: number; json: any }>((r) => (resolve = r));
    return { p, resolve };
  };
  it("an older reload of the same query that answers last is dropped", async () => {
    const calls = [deferred(), deferred()];
    let i = 0;
    const applied: string[] = [];
    const loader = createCommsLoader({ fetch: () => calls[i++].p, apply: (_q, r) => applied.push(r.json.rows[0].id) });
    const first = loader.load("q");
    const second = loader.load("q");
    calls[1].resolve({ status: 200, json: { rows: [row({ id: "new" })] } });
    await second;
    calls[0].resolve({ status: 200, json: { rows: [row({ id: "old" })] } });
    await first;
    expect(applied).toEqual(["new"]);
  });
  it("an answer to a query since changed is dropped", async () => {
    const calls = [deferred(), deferred()];
    let i = 0;
    const applied: string[] = [];
    const loader = createCommsLoader({ fetch: () => calls[i++].p, apply: (q) => applied.push(q) });
    const a = loader.load("a");
    const b = loader.load("b");
    calls[0].resolve({ status: 200, json: { rows: [] } });
    await a;
    calls[1].resolve({ status: 200, json: { rows: [] } });
    await b;
    expect(applied).toEqual(["b"]);
  });
});

describe("S-1: leaving Comms by any path drops comm, seat and tier from the route in memory", () => {
  const nav = () => {
    const urls: string[] = [];
    const sync = createUrlSync({ pushState: (_d, _u, url) => urls.push(url), replaceState: (_d, _u, url) => urls.push(url) }, { set: () => 0, clear: () => {} });
    const n = createRouteNav<Route>(sync, parseRoute("/comms/a1", "?seat=app:ask&tier=align"), { serialize: serializeRoute, isNavigation, normalize: normalizeRoute, onChange: () => {} });
    return { n, urls };
  };
  it("'Open the ask' (a navigate to the asks section) forgets the filters, and the tab comes back unfiltered", () => {
    const { n, urls } = nav();
    n.navigate({ section: "asks", ask: "app:ask/q1", fork: undefined, pane: undefined });
    expect(n.get()).not.toHaveProperty("seat");
    expect(n.get()).not.toHaveProperty("tier");
    expect(n.get()).not.toHaveProperty("comm");
    n.navigate(viewPatch("comms", "app:ask/q1"));
    expect(urls.at(-1)).toBe("/comms?ask=app:ask/q1");
    expect(n.get().seat).toBeUndefined();
  });
  it("a filter change within Comms keeps them", () => {
    const { n, urls } = nav();
    n.navigate({ tier: ["note"] }, false);
    expect(n.get()).toMatchObject({ section: "comms", comm: "a1", seat: "app:ask", tier: ["note"] });
    expect(urls.at(-1)).toBe("/comms/a1?seat=app:ask&tier=note");
  });
  it("normalizeRoute keeps a Comms route whole and strips the others", () => {
    const r = parseRoute("/comms/a1", "?seat=s&tier=lazy");
    expect(normalizeRoute(r)).toBe(r);
    expect(normalizeRoute({ ...r, section: "asks" })).toEqual({ section: "asks", filter: "open", group: "none" });
  });
  it("App's route navigator normalizes", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
    expect(src).toMatch(/createRouteNav\(urlSync, route, \{[^}]*normalize: normalizeRoute/);
  });
});

describe("S-3: link hrefs come from serializeRoute, and an ask ref that is not an in-app path gets no link", () => {
  it("a notice href is a serialized Comms route, encoded", () => {
    expect(commHref("a1.align")).toBe("/comms/a1.align");
    expect(commHref("odd id#1?x")).toBe("/comms/odd%20id%231%3Fx");
  });
  it("an ask link parses the server's ref and serializes it again", () => {
    expect(askLink(ASK)).toEqual({ ask: "app:ask/20261104-q1", href: "/a/app:ask/20261104-q1" });
    // Encoded per segment, as the landed server writes it, and still parsed through the validator.
    expect(askLink({ ...ASK, ref: "/a/app%3Aask/2026%20q%231" })).toEqual({ ask: "app:ask/2026 q#1", href: "/a/app:ask/2026%20q%231" });
    expect(askLink({ ...ASK, ref: "/a/app:ask/20261104-q1" })).toEqual({ ask: "app:ask/20261104-q1", href: "/a/app:ask/20261104-q1" });
    expect(askLink(ALIGN)).toBeNull();
  });
  it("refuses a ref that is not /a/<seat>/<id>", () => {
    for (const ref of ["javascript:alert(1)", "//evil.example/a/x/y", "https://evil.example/a/x/y", "/a/only-seat", "/proofs/x", "/a/x/y?z=1", "/a/x/y#F1", "", "/a/x y/z"]) {
      expect(askLink({ ...ASK, ref }), ref).toBeNull();
    }
    const html = feed(ok([{ ...ASK, ref: "javascript:alert(1)" }]));
    expect(html).not.toContain("javascript:");
    expect(html).not.toContain("Open the ask");
    expect(html).toContain("no readable link");
  });
});

describe("N-4: one alert, in the feed", () => {
  it("an error over earlier rows alerts once across sidebar and feed", () => {
    const s = { ...ok([ALIGN]), error: "the app server did not answer" };
    expect(alerts(side(s))).toBe(0);
    expect(alerts(feed(s))).toBe(1);
    expect(side(s)).toContain("could not be read");
  });
  it("an error with nothing read alerts once too", () => {
    const s: CommsState = { query: "", rows: undefined, error: "HTTP 500", at: "t" };
    expect(alerts(side(s)) + alerts(feed(s))).toBe(1);
  });
});

describe("N-5: React keys are unique even when the server repeats an id or a seat", () => {
  it("uniqueKeys suffixes repeats", () => {
    const k = uniqueKeys(["a", "a", "b", "a"]);
    expect(new Set(k).size).toBe(4);
    expect(k[0]).toBe("a");
    expect(k[2]).toBe("b");
  });
  it("the feed and list render repeated rows and seats without losing any", () => {
    const dup = row({ id: "dup", to: ["s:1", "s:1"] });
    const html = feed(ok([dup, dup]));
    expect(html.split('id="cm-dup"').length - 1).toBe(2);
    expect(html.split(">s:1</button>").length - 1).toBe(4);
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/comms.tsx"), "utf8");
    expect(src).not.toMatch(/key=\{r\.id\}|key=\{s\}/);
  });
});

describe("S-1 on the search stack: a search result opened from Comms also forgets the Comms filters", () => {
  it("navigate(resultRoute(…)) from a filtered Comms route drops comm, seat and tier", async () => {
    const { resultRoute } = await import("../src/client/semantic.ts");
    for (const app of ["/proofs/x.html", "/broadcasts/b1", "/a/app:ask/q1"]) {
      const sync = createUrlSync({ pushState: () => {}, replaceState: () => {} }, { set: () => 0, clear: () => {} });
      const n = createRouteNav<Route>(sync, parseRoute("/comms/a1", "?seat=app:ask&tier=align"), { serialize: serializeRoute, isNavigation, normalize: normalizeRoute, onChange: () => {} });
      n.navigate(resultRoute(app, "app:ask/q0"), true);
      expect(n.get(), app).not.toHaveProperty("seat");
      expect(n.get(), app).not.toHaveProperty("tier");
      expect(n.get(), app).not.toHaveProperty("comm");
    }
  });
});


// ---- COMMSUI on the landed contract ----

describe("live: the feed reloads on the server's comms event as well as change", () => {
  it("listenComms bumps on change and on comms, and on nothing else", () => {
    const es = new EventTarget();
    let n = 0;
    listenComms(es, () => n++);
    es.dispatchEvent(new Event("change"));
    es.dispatchEvent(new Event("comms"));
    es.dispatchEvent(new Event("hello"));
    expect(n).toBe(2);
  });
});

describe("id lookup: a notice or its tell that the filter hides is fetched by id", () => {
  it("the query by id carries only the ids", () => {
    expect(commsQuery({ ids: ["a1.align"] })).toBe("/api/comms?id=a1.align");
    expect(commsQuery({ ids: ["a1", "app:ask/q1"], seat: "x", tier: ["note"], kind: ["tell"] })).toBe("/api/comms?id=a1%2Capp%3Aask%2Fq1");
  });
  it("commsMissing names the picked row only once this query's rows are read and it is not among them", () => {
    expect(commsMissing(ok([ALIGN]), "", "a1.align")).toBe(true);
    expect(commsMissing(ok([ALIGN]), "", "a1")).toBe(false);
    expect(commsMissing(ok([ALIGN]), "", undefined)).toBe(false);
    expect(commsMissing(undefined, "", "a1")).toBe(false);
    expect(commsMissing(ok([ALIGN], "old"), "new", "zz")).toBe(false);
  });
  it("the feed shows the looked-up row, said to be outside the filters, instead of 'clear the filters'", () => {
    const html = feed(ok([ALIGN]), { current: "a1.align", filtered: true, pinned: ok([NOTICE], commsQuery({ ids: ["a1.align"] })) });
    expect(html).toContain('id="cm-a1.align"');
    expect(html).toContain("Outside these filters");
    expect(html).not.toMatch(/Clear the filters/);
  });
  it("while the lookup runs it says so; when it finds nothing it says the message does not exist; a failed lookup is not 'none'", () => {
    expect(feed(ok([ALIGN]), { current: "zz", filtered: true })).toContain("Looking up “zz”");
    expect(feed(ok([ALIGN]), { current: "zz", filtered: true, pinned: ok([], "/api/comms?id=zz") })).toContain("No message “zz” exists.");
    const failed = feed(ok([ALIGN]), { current: "zz", filtered: true, pinned: { query: "/api/comms?id=zz", rows: undefined, error: "bad id 'zz'", at: "t" } });
    expect(failed).toContain("could not be looked up");
    expect(failed).not.toContain("exists");
    expect(alerts(failed)).toBe(0);
  });
});

describe("tier on asks is null", () => {
  it("an ask row has no tier chip in the feed or the list", () => {
    const html = feed(ok([ASK]));
    expect(html).not.toMatch(/tier-/);
    expect(html).not.toContain(">null<");
    const list = side(ok([ASK]));
    expect(list).not.toMatch(/tier-/);
    expect(list).not.toContain("null");
  });
  it("the tier filter's hint says asks ride no tier and a tier filter leaves them out", () => {
    // Visible once a tier is picked, not only in the hover title (T2 plant).
    expect(filters(undefined, ["align"])).toContain('<p class="muted comms-hint">Asks ride no tier, so a tier filter leaves them out.</p>');
    expect(filters()).not.toContain("comms-hint");
    expect(filters()).toContain('title="Asks ride no tier, so a tier filter leaves them out."');
  });
});

describe("state labels", () => {
  it("every tell state and seat state has words", () => {
    expect(stateLabel(row({ state: "read" }))).toBe("read by every recipient");
    expect(stateLabel(row({ state: "not-attempted" }))).toBe("not attempted");
    expect(stateLabel(row({ state: "queued" }))).toBe("queued, not shown yet");
    expect(stateLabel(row({ state: "delivered" }))).toBe("delivered");
    expect(stateLabel(row({ state: "undelivered" }))).toBe("not delivered");
    expect(stateLabel(row({ state: "withdrawn" }))).toBe("withdrawn");
    expect(stateLabel(ASK)).toBe("open");
    for (const [k, v] of [["read", "read"], ["queued", "queued"], ["delivered", "delivered"], ["undelivered", "not delivered"], ["not-attempted", "not attempted"]] as const) expect(seatStateLabel(k)).toBe(v);
  });
  it("the card shows the label and each seat's label", () => {
    const html = feed(ok([row({ id: "r1", state: "read", seats: [{ seat: "app:ui", state: "read" }, { seat: "app:x", state: "read" }] })]));
    expect(html).toContain(">read by every recipient</span>");
    expect(html).toContain('title="app:ui: read\napp:x: read"');
    expect(html).not.toContain("mixed");
  });
});

describe("kind filter in the URL", () => {
  it("parses, serializes and leaves with the section", () => {
    const r = parseRoute("/comms", "?kind=tell,ask,bogus");
    expect(r.kind).toEqual(["tell", "ask"]);
    expect(serializeRoute(r)).toBe("/comms?kind=tell,ask");
    expect(serializeRoute({ ...parseRoute("/"), kind: ["ask"] })).toBe("/");
    expect(normalizeRoute({ ...r, section: "asks" })).not.toHaveProperty("kind");
    expect(isNavigation(r, { ...r, kind: ["tell"] })).toBe(false);
  });
  it("the query carries it, and the filter offers tell, broadcast and ask as toggles", () => {
    expect(commsQuery({ kind: ["tell", "ask"] })).toBe("/api/comms?kind=tell%2Cask");
    const html = filters(undefined, undefined, ["ask"]);
    expect(html).toContain('aria-pressed="true">ask</button>');
    expect(html).toContain('aria-pressed="false">tell</button>');
    expect(html).toContain('aria-pressed="false">broadcast</button>');
  });
  it("App sends the kind from the route", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
    expect(src).toMatch(/useComms\(view === "comms", \{ seat: route\.seat, tier: route\.tier, kind: route\.kind \}, changeTick\)/);
  });
});


// ---- COMMSUI delta round (COMMSUI_DELTA_CRITIQUE.md) ----

const PQ = commsQuery({ ids: ["a1.align"] });
describe("S-1: a failed refresh of the pinned lookup shows its error", () => {
  it("over an earlier empty answer: the error, never 'No message exists'", () => {
    const html = feed(ok([ALIGN]), { current: "a1.align", filtered: true, pinned: { query: PQ, rows: [], error: "HTTP 500", at: "2026-11-04T11:00:00Z" } });
    expect(html).toContain("could not be looked up: HTTP 500");
    expect(html).not.toContain("exists");
  });
  it("over an earlier found card: the error, the card, and 'as last read'", () => {
    const html = feed(ok([ALIGN]), { current: "a1.align", filtered: true, pinned: { query: PQ, rows: [NOTICE], error: "the app server did not answer", at: "2026-11-04T11:00:00Z" } });
    expect(html).toContain("the app server did not answer");
    expect(html).toMatch(/as last read [^<]+/);
    expect(html).toContain('id="cm-a1.align"');
  });
});

describe("S-2: unfiltered, a message the page does not carry is older than this page, not hidden by filters", () => {
  it("unfiltered wording", () => {
    const looking = feed(ok([ALIGN]), { current: "zz", filtered: false });
    expect(looking).toContain("older than this page");
    expect(looking).not.toContain("filters hide");
    const found = feed(ok([ALIGN]), { current: "a1.align", filtered: false, pinned: ok([NOTICE], PQ) });
    expect(found).toContain("Older than this page");
    expect(found).not.toContain("Outside these filters");
  });
  it("filtered wording stays", () => {
    expect(feed(ok([ALIGN]), { current: "zz", filtered: true })).toContain("which these filters hide");
    expect(feed(ok([ALIGN]), { current: "a1.align", filtered: true, pinned: ok([NOTICE], PQ) })).toContain("Outside these filters");
  });
});

describe("S-3: scroll once per pick, when the picked card first appears", () => {
  it("scrollStep", () => {
    let m: ScrollMemo = { done: false };
    const step = (current: string | undefined, present: boolean) => {
      const r = scrollStep(m, current, present);
      m = r.memo;
      return r.scroll;
    };
    expect(step("a1", false)).toBe(false); // picked, lookup still running
    expect(step("a1", true)).toBe(true); // the pinned card arrived
    expect(step("a1", true)).toBe(false); // a later reload of the same pick
    expect(step("a1", true)).toBe(false);
    expect(step("a2", true)).toBe(true); // another pick
    expect(step("a1", true)).toBe(true); // back to the first
    expect(step(undefined, false)).toBe(false);
  });
  it("the feed scrolls through scrollStep, with the pinned rows among its inputs", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/comms.tsx"), "utf8");
    expect(src).toMatch(/scrollStep\(scrolled\.current, current, present\)/);
    expect(src).toMatch(/\}, \[current, state\?\.rows, pinnedRows\]\);/);
  });
});

describe("S-4: the overall state does not over-claim", () => {
  it("mixed recipients read as mixed, with visible per-seat counts", () => {
    const r = row({ id: "m1", state: "queued", seats: [{ seat: "a:1", state: "read" }, { seat: "a:2", state: "read" }, { seat: "a:3", state: "queued" }] });
    expect(seatCounts(r)).toBe("2 read · 1 queued");
    const html = feed(ok([r]));
    expect(html).toContain(">mixed</span>");
    expect(html).toContain("2 read · 1 queued");
    expect(html).not.toContain("queued, not shown yet");
  });
  it("delivered over an undelivered seat is mixed too", () => {
    const r = row({ id: "m2", state: "delivered", seats: [{ seat: "a:1", state: "delivered" }, { seat: "a:2", state: "undelivered" }] });
    expect(feed(ok([r]))).toContain("1 delivered · 1 not delivered");
  });
  it("one shared state keeps the plain label, and a withdrawn row stays withdrawn", () => {
    expect(seatCounts(row({ state: "queued", seats: [{ seat: "a:1", state: "queued" }, { seat: "a:2", state: "queued" }] }))).toBe("");
    expect(feed(ok([row({ id: "q1", state: "queued", seats: [{ seat: "a:1", state: "queued" }, { seat: "a:2", state: "queued" }] })]))).toContain(">queued, not shown yet</span>");
    const w = feed(ok([row({ id: "w1", state: "withdrawn", withdrawn: { by: "x", at: "2026-11-04T10:00:00Z", reason: "r" }, seats: [{ seat: "a:1", state: "read" }, { seat: "a:2", state: "queued" }] })]));
    expect(w).toContain(">withdrawn</span>");
    expect(w).not.toContain(">mixed</span>");
  });
});

describe("N-1: one change reloads once", () => {
  it("the change handler loads the asks and does not bump the comms tick; listenComms does", () => {
    const src = fs.readFileSync(path.join(import.meta.dirname, "../src/client/App.tsx"), "utf8");
    expect(src).toContain('es.addEventListener("change", () => load());');
    const bumps = src.match(/setChangeTick\(\(n\) => n \+ 1\)/g) ?? [];
    // One in the reconnect hello, one in listenComms; none in a change handler.
    expect(bumps).toHaveLength(2);
    expect(src).not.toMatch(/addEventListener\("change"[^;]*setChangeTick/);
  });
});

describe("N-2: Pinned shows only the requested id", () => {
  it("drops any other row the lookup returned", () => {
    const html = feed(ok([GONE]), { current: "a1.align", filtered: true, pinned: ok([NOTICE, ALIGN], PQ) });
    expect(html.split('id="cm-a1.align"').length - 1).toBe(1);
    expect(html).not.toContain('id="cm-a1"');
  });
});

describe("N-3: a pinned answer from a superseded lookup is not shown again", () => {
  it("pinnedReducer starts fresh whenever the lookup query changes, even back to the same id", () => {
    let s = pinnedReducer(undefined, { type: "query", query: PQ });
    expect(s).toBeUndefined();
    s = pinnedReducer(s, { type: "answer", query: PQ, r: { status: 200, json: { rows: [] } }, at: "t1" });
    expect(s).toMatchObject({ query: PQ, rows: [] });
    s = pinnedReducer(s, { type: "query", query: PQ }); // a tick: same lookup, kept
    expect(s).toMatchObject({ rows: [] });
    s = pinnedReducer(s, { type: "query", query: "" }); // a filter change: no lookup
    expect(s).toBeUndefined();
    s = pinnedReducer(s, { type: "query", query: PQ }); // missing again: loading, not the old answer
    expect(s).toBeUndefined();
    // An answer for another query than the current one is dropped.
    expect(pinnedReducer({ query: PQ, rows: [], error: "", at: "t" }, { type: "answer", query: "/api/comms?id=zz", r: { status: 200, json: { rows: [] } }, at: "t2" })).toMatchObject({ query: PQ, at: "t" });
  });
});

describe("N-4: the kind group has its own class", () => {
  it("comms-kinds", () => {
    const html = filters();
    expect(html).toContain('class="seg comms-kinds" role="group" aria-label="Kind"');
    expect(html).toContain('class="seg comms-tiers" role="group" aria-label="Tier"');
  });
});
