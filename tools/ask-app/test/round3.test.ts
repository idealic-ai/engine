/**
 * Ask v2 fix round 3 (builds/askv2_REREVIEW_R2.md): MUST-1 label-shaped FLEET_MANAGES,
 * MUST-2 the operator over a seat's draft, SHOULD-3 empty choice forks, SHOULD-7 the S9 guards
 * K1 (build id pinned at server start) and K2 (the imported stylesheets hashed). K3 and SHOULD-5 are in bash.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import net from "node:net";
import path from "node:path";
import { answerAsk, discardDraft, forwardAsk, managesSeat, newAsk, reviseAsk, saveDraft, sendBatch } from "../src/lib/store.ts";
import { parseAskFile } from "../src/lib/format.ts";
import { APP_DIR, BUILD_ID_FILE, buildInputs, computeBuildId } from "../src/build-id.ts";

let base: string;
let root: string;
beforeEach(() => {
  base = fs.mkdtempSync(path.join("/tmp", "asksr3-"));
  root = path.join(base, "asks");
});
afterEach(() => fs.rmSync(base, { recursive: true, force: true }));

const GO = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";
const file = (seat: string, id: string) => path.join(root, seat, `${id}.md`);
const read = (seat: string, id: string) => parseAskFile(fs.readFileSync(file(seat, id), "utf8"));
const push = async () => ({ status: "delivered" as const });
// The live shape, measured on tmux @pane_manages (re-review R2 §2).
const MANAGER_APP = "ideas,writer,deploy,playground".split(",");
const MANAGER_DIRECTOR = "idealic,app,domain,docs,meta".split(",");

describe("MUST-1: FLEET_MANAGES holds pane labels", () => {
  it("managesSeat matches a full seat name or its label, never a stranger", () => {
    expect(managesSeat(MANAGER_APP, "app:writer")).toBe(true);
    expect(managesSeat(MANAGER_DIRECTOR, "manager:app")).toBe(true);
    expect(managesSeat(["app:writer"], "app:writer")).toBe(true);
    expect(managesSeat(MANAGER_APP, "app:writers")).toBe(false);
    expect(managesSeat(MANAGER_APP, "manager:app")).toBe(false);
    expect(managesSeat([""], "app:")).toBe(false); // an empty entry names nobody
  });

  it("manager:app relays onto its child's reserved ask with the LIVE label list", async () => {
    newAsk(root, { from: "app:writer", to: "operator", id: "m1", "reserved-for": "operator" }, GO);
    await answerAsk(root, "app:writer", "m1", { answers: { GO: ["YES"] }, answeredBy: "operator", answeredVia: "relay:manager:app", note: "in my chat" }, { expectedRevision: 1, push, relayerManages: MANAGER_APP });
    expect(read("app:writer", "m1").answer?.answeredVia).toBe("relay:manager:app");
    newAsk(root, { from: "app:other", to: "operator", id: "m2", "reserved-for": "operator" }, GO);
    await expect(answerAsk(root, "app:other", "m2", { answers: { GO: ["YES"] }, answeredBy: "operator", answeredVia: "relay:manager:app", note: "x" }, { expectedRevision: 1, push, relayerManages: MANAGER_APP })).rejects.toThrow("may not relay");
  });

  it("the director forwards a silent manager:app's ask with its LIVE label list", async () => {
    newAsk(root, { from: "app:writer", to: "manager:app", id: "m3" }, GO);
    await forwardAsk(root, "app:writer", "m3", { to: "operator", by: "manager:director", manages: MANAGER_DIRECTOR });
    expect(read("app:writer", "m3").header.to).toBe("operator");
    newAsk(root, { from: "app:writer", to: "manager:ideas2", id: "m4" }, GO);
    await expect(forwardAsk(root, "app:writer", "m4", { to: "operator", by: "manager:director", manages: MANAGER_DIRECTOR })).rejects.toThrow("neither");
  });
});

describe("MUST-2: a seat's draft never locks the operator out", () => {
  it("the operator replaces a seat's draft (relay draft included) and may discard one; a seat still cannot replace another's", async () => {
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "d1", "reserved-for": "operator" }, GO);
    await saveDraft(root, "idealic:kernel", "d1", { answers: { GO: ["YES"] }, answeredBy: "operator", answeredVia: "relay:manager:idealic", note: "n" }, 1);
    await saveDraft(root, "idealic:kernel", "d1", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: "browser" }, 1);
    expect(read("idealic:kernel", "d1").draft).toMatchObject({ answers: { GO: ["NO"] }, answeredVia: "browser" });
    await expect(saveDraft(root, "idealic:kernel", "d1", { answers: { GO: ["YES"] }, answeredBy: "operator", answeredVia: "relay:manager:idealic", note: "n" }, 1)).rejects.toThrow("only its author");
    const out = await sendBatch(root, ["idealic:kernel/d1"], { by: "operator", push });
    expect(out.settled.map((s) => s.ref)).toEqual(["idealic:kernel/d1"]);

    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "d2" }, GO);
    await saveDraft(root, "idealic:kernel", "d2", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic" }, 1);
    await discardDraft(root, "idealic:kernel", "d2", "operator");
    expect(read("idealic:kernel", "d2").draft).toBeUndefined();
    await saveDraft(root, "idealic:kernel", "d2", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic" }, 1);
    await expect(discardDraft(root, "idealic:kernel", "d2", "idealic:stranger")).rejects.toThrow("only its author");
  });

  it("the card pre-fills the operator's own draft or the answer, never a seat's draft as the operator's choice", async () => {
    const { initialValues } = await import("../src/client/App.tsx");
    newAsk(root, { from: "idealic:kernel", to: "manager:idealic", id: "d3" }, GO);
    await saveDraft(root, "idealic:kernel", "d3", { answers: { GO: ["YES"] }, answeredBy: "manager:idealic", note: "seat's" }, 1);
    expect(initialValues(read("idealic:kernel", "d3"))).toEqual({ values: {}, text: {}, note: "" });
    await saveDraft(root, "idealic:kernel", "d3", { answers: { GO: ["NO"] }, answeredBy: "operator", note: "mine" }, 1);
    expect(initialValues(read("idealic:kernel", "d3"))).toEqual({ values: { GO: ["NO"] }, text: {}, note: "mine" });
  });
});

describe("SHOULD-3: a choice fork with no options is refused", () => {
  it("at new and at revise, naming the fork", async () => {
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "z1" }, "## ¶ASK_Q: Choose one: Which?\nJust prose, no options.\n")).toThrow('"Which?": a choose-one fork needs at least one option');
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "z2" }, "## ¶ASK_R: Rank: Order?\nContext: c\n")).toThrow("needs at least one option");
    expect(() => newAsk(root, { from: "a:b", to: "operator", id: "z3" }, "## ¶ASK_T: Text: Why?\nContext: c\n\n## ¶ASK_Y: Yes or no: Ok?\nContext: c\n")).not.toThrow();
    newAsk(root, { from: "a:b", to: "operator", id: "z4" }, GO);
    await expect(reviseAsk(root, "a:b", "z4", {}, "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n", { by: "a:b", push })).rejects.toThrow("needs at least one option");
  });
});

/** A port the OS reports unused right now: never a fixed or random guess, which can land on the live
 * ask server (4977) or on another lane's test server. */
function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.once("error", reject);
    s.listen(0, "127.0.0.1", () => {
      const { port } = s.address() as net.AddressInfo;
      s.close(() => resolve(port));
    });
  });
}

/** A copy of what the build id hashes, laid out as in the engine (app + the kit sheets main.tsx imports). */
function copySources(dest: string): string {
  const engine = path.resolve(APP_DIR, "..", "..");
  for (const f of buildInputs()) {
    const to = path.join(dest, path.relative(engine, f));
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(f, to);
  }
  return path.join(dest, path.relative(engine, APP_DIR));
}

describe("SHOULD-7: the S9 guards", () => {
  it("K2: the stylesheets main.tsx imports are build inputs inside the app, and editing one changes the id", () => {
    const inputs = buildInputs();
    expect(inputs.filter((f) => !f.startsWith(APP_DIR + path.sep))).toEqual([]);
    expect(inputs.map((f) => path.basename(f))).toEqual(expect.arrayContaining(["theme.css", "styles.css"]));
    const app = copySources(path.join(base, "eng"));
    const before = computeBuildId(app);
    expect(before).toBe(computeBuildId());
    const sheet = path.join(app, "src", "client", "theme.css");
    fs.appendFileSync(sheet, "\n/* a comment is a different build */\n");
    expect(computeBuildId(app)).not.toBe(before);
  });

  it("K1: the server pins the build id at START — sources edited after it starts do not change what it serves", async () => {
    const app = copySources(path.join(base, "eng"));
    const dist = path.join(base, "dist");
    fs.mkdirSync(dist);
    fs.writeFileSync(path.join(dist, "index.html"), "<!doctype html><html><head></head><body>pinned</body></html>\n");
    const id = computeBuildId(app);
    fs.writeFileSync(path.join(dist, BUILD_ID_FILE), `${id}\n`);
    const port = await freePort();
    const proc = spawn(process.execPath, ["--no-warnings", "src/server.ts", "--root", root, "--port", String(port), "--token", "t"], {
      env: { ...process.env, ASK_APP_DIST: dist, ASK_BUILD_SRC: app, ASK_SESSIONS_DIR: path.join(base, "s"), ASK_LINEAR_ENV: "/dev/null" },
      stdio: "ignore",
    });
    const get = (p: string) =>
      new Promise<{ status: number; body: string }>((resolve, reject) => {
        const r = http.request({ host: "127.0.0.1", port, path: p, headers: { host: `127.0.0.1:${port}` } }, (res) => {
          let b = "";
          res.on("data", (d) => (b += d));
          res.on("end", () => resolve({ status: res.statusCode!, body: b }));
        });
        r.on("error", reject);
        r.end();
      });
    try {
      let up = false;
      for (let i = 0; i < 200 && !up; i++) {
        up = await get("/api/health").then((r) => r.status === 200, () => false);
        if (!up) await new Promise((r) => setTimeout(r, 50));
      }
      expect(up).toBe(true);
      expect(JSON.parse((await get("/api/health")).body).build).toBe(id);
      expect((await get("/")).status).toBe(200);
      fs.appendFileSync(path.join(app, "src", "client", "styles.css"), "\n/* edited after start */\n");
      expect(computeBuildId(app)).not.toBe(id);
      const r = await get("/");
      expect(r.status).toBe(200);
      expect(r.body).toContain("pinned");
    } finally {
      proc.kill();
    }
  });
});
