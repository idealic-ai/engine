import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { listAsks } from "../src/lib/store.ts";
import { settlementOf, withSettlement } from "../src/lib/settle.ts";

/**
 * ASKLIST: what decides whether an ask still needs somebody. The operator's list showed answered asks
 * with ⏳ (a provisional answer whose asker never filed a follow-up naming it). These pin the rule the
 * server now states on each /api/asks row: `settled`, and when not settled, what is `owed` and by whom.
 */

let root: string;
beforeEach(() => {
  root = fs.mkdtempSync(path.join("/tmp", "asklist-"));
});
afterEach(() => fs.rmSync(root, { recursive: true, force: true }));

type Head = Record<string, string>;
function write(seat: string, id: string, head: Head, answer?: Record<string, unknown>) {
  const h = { id, to: "operator", from: seat, status: "open", revision: "1", created: "2026-10-30T10:00:00.000Z", ...head };
  const lines = ["---", ...Object.entries(h).map(([k, v]) => `${k}: ${v}`), "---", "", "## Choose one: ¶ASK_GO — ship it?", "- [ ] [YES] Yes", "  Cost: none.", "- [ ] [NO] No", "  Cost: none.", ""];
  if (answer) lines.push("```json answer", JSON.stringify({ answers: { q0: "YES" }, answeredBy: "operator", answeredVia: "browser", answeredAt: "2026-10-30T11:00:00.000Z", revision: Number(h.revision), ...answer }, null, 2), "```", "");
  fs.mkdirSync(path.join(root, seat), { recursive: true });
  fs.writeFileSync(path.join(root, seat, `${id}.md`), lines.join("\n"));
}
const one = (ref: string) => {
  const all = listAsks(root);
  const a = all.find((x) => `${x.seat}/${x.header.id}` === ref);
  if (!a) throw new Error(`no ${ref}`);
  return settlementOf(a, all);
};

describe("settlementOf", () => {
  it("an open ask is not settled and owes nothing beyond its answer", () => {
    write("domain:stats", "o1", {});
    expect(one("domain:stats/o1")).toEqual({ settled: false });
  });

  it("an answered ask whose push was delivered is settled, read or not (delivered is queued, and readAt stays the asker's)", () => {
    write("domain:stats", "d1", { status: "answered", delivery: "delivered" }, {});
    write("domain:stats", "d2", { status: "answered", delivery: "delivered", readAt: "2026-10-30T12:00:00.000Z", readBy: "domain:stats" }, {});
    expect(one("domain:stats/d1")).toEqual({ settled: true });
    expect(one("domain:stats/d2")).toEqual({ settled: true });
  });

  it("a declined ask, a withdrawn one and a superseded one are settled", () => {
    write("domain:stats", "x1", { status: "declined", delivery: "delivered" }, { declined: true });
    write("domain:stats", "x2", { status: "withdrawn" });
    write("domain:stats", "x3", { status: "superseded" });
    for (const r of ["x1", "x2", "x3"]) expect(one(`domain:stats/${r}`).settled).toBe(true);
  });

  it("an answer whose push did not land owes a delivery, to the asker", () => {
    write("core:realm", "u1", { status: "answered", delivery: "undelivered", deliveryNote: "no pane" }, {});
    write("core:realm", "u2", { status: "answered", delivery: "partial", deliveryNote: "one of two" }, {});
    expect(one("core:realm/u1")).toEqual({ settled: false, owed: { kind: "delivery", by: "core:realm", why: "undelivered: no pane" } });
    expect(one("core:realm/u2")).toEqual({ settled: false, owed: { kind: "delivery", by: "core:realm", why: "partial: one of two" } });
  });

  it("a provisional answer (a request: note) owes the asker's follow-up, read or not", () => {
    write("core:kernel", "p1", { status: "answered", delivery: "delivered", readAt: "2026-10-30T12:00:00.000Z", readBy: "core:kernel" }, { note: "request: proof:best — explain" });
    expect(one("core:kernel/p1")).toEqual({ settled: false, owed: { kind: "follow-up", by: "core:kernel", why: "a provisional answer: the asker owes a follow-up ask" } });
  });

  it("a forwarder's acted does not close the follow-up: it relayed, the asker still owes the re-ask", () => {
    write("manager:domain", "p2", { status: "answered", delivery: "delivered", acted: "relayed for a re-ask", actedBy: "manager:director" }, { note: "request: details — reask me" });
    expect(one("manager:domain/p2").owed?.kind).toBe("follow-up");
  });

  it("the asker's own acted closes a provisional answer: it said it followed up", () => {
    write("domain:stats", "p3", { status: "answered", delivery: "delivered", acted: "re-put the choice as a new operator ask", actedBy: "domain:Stats" }, { note: "request: proof:explore — explain" });
    expect(one("domain:stats/p3")).toEqual({ settled: true });
  });

  it("a follow-up ask from the same asker naming it in previous: closes it (the client's existing rule)", () => {
    write("domain:stats", "p4", { status: "answered", delivery: "delivered" }, { note: "request: details — say more" });
    write("domain:stats", "p5", { previous: "domain:stats/p4", created: "2026-10-30T13:00:00.000Z" });
    expect(one("domain:stats/p4")).toEqual({ settled: true });
  });

  it("an undelivered provisional answer reports the delivery first: nothing reached the asker yet", () => {
    write("core:kernel", "p6", { status: "answered", delivery: "undelivered", deliveryNote: "no pane" }, { note: "request: details — say more" });
    expect(one("core:kernel/p6").owed?.kind).toBe("delivery");
  });
});

describe("withSettlement", () => {
  it("adds settled (and owed when there is one) to each row, keeping every field it had", () => {
    write("domain:stats", "d1", { status: "answered", delivery: "delivered" }, {});
    write("core:kernel", "p1", { status: "answered", delivery: "delivered" }, { note: "request: details — say more" });
    const rows = withSettlement(listAsks(root));
    const d1 = rows.find((r) => r.header.id === "d1")!;
    const p1 = rows.find((r) => r.header.id === "p1")!;
    expect(d1.settled).toBe(true);
    expect("owed" in d1).toBe(false);
    expect(d1.header.status).toBe("answered");
    expect(p1.settled).toBe(false);
    expect(p1.owed).toEqual({ kind: "follow-up", by: "core:kernel", why: "a provisional answer: the asker owes a follow-up ask" });
  });
});

describe("GET /api/asks carries the settlement", () => {
  it("a delivered answer reads settled; a provisional one reads owed follow-up; an open one reads unsettled", async () => {
    const { spawn } = await import("node:child_process");
    const http = await import("node:http");
    const { BUILD_ID_FILE, computeBuildId } = await import("../src/build-id.ts");
    write("domain:stats", "d1", { status: "answered", delivery: "delivered" }, {});
    write("core:kernel", "p1", { status: "answered", delivery: "delivered", readAt: "2026-10-30T12:00:00.000Z", readBy: "core:kernel" }, { note: "request: details — say more" });
    write("domain:stats", "o1", {});
    const base = fs.mkdtempSync(path.join("/tmp", "asklist-srv-"));
    const dist = path.join(base, "dist");
    fs.mkdirSync(dist);
    fs.writeFileSync(path.join(dist, "index.html"), "<!doctype html><title>t</title>\n");
    fs.writeFileSync(path.join(dist, BUILD_ID_FILE), `${computeBuildId()}\n`);
    fs.mkdirSync(path.join(base, "sessions"));
    const port = 30000 + Math.floor(Math.random() * 20000);
    const proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", root, "--port", String(port), "--token", "t"], {
      env: { ...process.env, ASK_SESSIONS_DIR: path.join(base, "sessions"), ASK_APP_DIST: dist },
      stdio: "ignore",
    });
    const get = (p: string) =>
      new Promise<{ status: number; body: string }>((resolve, reject) => {
        const r = http.request({ host: "127.0.0.1", port, path: p, method: "GET", headers: { host: `127.0.0.1:${port}` } }, (res) => {
          let b = "";
          res.on("data", (d) => (b += d));
          res.on("end", () => resolve({ status: res.statusCode!, body: b }));
        });
        r.on("error", reject);
        r.end();
      });
    try {
      let up = false;
      for (let i = 0; i < 100 && !up; i++) {
        try {
          up = (await get("/api/health")).status === 200;
        } catch {
          await new Promise((r) => setTimeout(r, 50));
        }
      }
      expect(up).toBe(true);
      const { asks } = JSON.parse((await get("/api/asks")).body) as { asks: { header: { id: string }; settled: boolean; owed?: { kind: string; by: string }; history: unknown }[] };
      const by = (id: string) => asks.find((a) => a.header.id === id)!;
      expect(by("d1").settled).toBe(true);
      expect(by("d1").owed).toBeUndefined();
      expect(by("p1")).toMatchObject({ settled: false, owed: { kind: "follow-up", by: "core:kernel" } });
      expect(by("o1").settled).toBe(false);
      expect(Array.isArray(by("d1").history)).toBe(true);
    } finally {
      proc.kill();
      fs.rmSync(base, { recursive: true, force: true });
    }
  });
});

describe("delivery: owed.by names the seats the push missed (critique SHOULD-1)", () => {
  it("live case core:realm/ide326-applist: partial, only the forwarder manager:core missed, and core:realm has read it → settled", () => {
    write("core:realm", "ide326-applist", { status: "answered", delivery: "partial", deliveryNote: "manager:core: no live session named manager:core", forwards: "manager:core→operator@2026-10-30T06:00:00.000Z", readAt: "2026-10-30T07:24:00.000Z", readBy: "core:realm" }, {});
    expect(one("core:realm/ide326-applist")).toEqual({ settled: true });
  });

  it("the same partial row before the asker reads it owes the delivery to the forwarder it missed, not the asker", () => {
    write("core:realm", "fwd", { status: "answered", delivery: "partial", deliveryNote: "manager:core: no live session named manager:core" }, {});
    expect(one("core:realm/fwd")).toEqual({ settled: false, owed: { kind: "delivery", by: "manager:core", why: "partial: manager:core: no live session named manager:core" } });
  });

  it("live case app:Idealic/writer-deployed: the asker itself missed and has not read it → owed by the asker", () => {
    write("app:Idealic", "writer-deployed", { status: "answered", delivery: "partial", deliveryNote: "app:Idealic: no live session named app:Idealic" }, {});
    expect(one("app:Idealic/writer-deployed").owed).toEqual({ kind: "delivery", by: "app:Idealic", why: "partial: app:Idealic: no live session named app:Idealic" });
  });

  it("several missed seats are all named, once each, in the note's order", () => {
    write("core:realm", "two", { status: "answered", delivery: "undelivered", deliveryNote: "core:realm: socket refused; manager:core: no live session named manager:core" }, {});
    expect(one("core:realm/two").owed?.by).toBe("core:realm, manager:core");
  });

  it("a pending push with no note owes the asker; an undelivered row the asker has read is settled", () => {
    write("core:realm", "pend", { status: "answered", delivery: "pending" }, {});
    write("core:realm", "readit", { status: "answered", delivery: "undelivered", deliveryNote: "core:realm: no pane", readAt: "2026-10-30T07:24:00.000Z", readBy: "core:realm" }, {});
    expect(one("core:realm/pend").owed?.by).toBe("core:realm");
    expect(one("core:realm/readit")).toEqual({ settled: true });
  });
});
