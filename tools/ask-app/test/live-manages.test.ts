/**
 * MANAGES (meta:engine, 2026-11-04): "is the caller a manager of the asker" is read from the live
 * tmux edge (the asker's @pane_parent, hop.sh's read), not from FLEET_MANAGES, which run.sh froze at
 * launch. Reported: manager:core's FLEET_MANAGES still listed `exchange` after core:exchange was
 * renamed core:database, so `engine ask supersede core:database/<old> --by …` was refused although
 * `hop.sh target --of core:database` printed manager:core.
 *
 * Round 1: a stale env with live authority is allowed; a stale env without live authority is refused
 * (a listed seat that moved away grants nothing); an unreadable tree falls back to FLEET_MANAGES with
 * a warning; neither source refuses.
 * Fix round (builds/MANAGES_CRITIQUE.md): rename-seat after the tmux rename (MUST-1, meta:engine's
 * ruling), the caller vouched by its own pane's row (S2), no standing for a non-seat while the tree
 * reads (S3), a set-but-unreadable or empty seam refuses (S4), case-folded seats (S5), ambiguous seats
 * (S6), one tree read (S7).
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { newAsk } from "../src/lib/store.ts";
import { parseAskFile } from "../src/lib/format.ts";
import { edgeOf, liveManages, parentIn, readLiveTree, type LiveRow, type LiveTree } from "../src/lib/manages.ts";

const CLI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.ts");
const BODY = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";

// The live tree after today's moves: core:exchange renamed core:database (still under manager:core),
// app:writer moved from manager:core to manager:app, and one unlabelled pane (%12).
const TREE = ["manager:core %7 -", "core:database %8 manager:core", "manager:app %9 -", "app:writer %10 manager:app", "idealic:runner %11 -", "work: %12 -"].join("\n") + "\n";

let base: string;
let root: string;
let panes: string;
beforeEach(() => {
  base = fs.mkdtempSync(path.join("/tmp", "asks-manages-"));
  root = path.join(base, "asks");
  panes = path.join(base, "panes.txt");
  fs.writeFileSync(panes, TREE);
});
afterEach(() => fs.rmSync(base, { recursive: true, force: true }));

/** The CLI, with nothing delivered to a real seat (ASK_SESSIONS_DIR is scratch) and no real tmux socket. */
const run = (args: string[], extra: Record<string, string> = {}) => {
  const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(base, "sessions"), ASK_TMUX_SOCKET: "ask-manages-test-none" };
  for (const k of ["TMUX_PANE", "TMUX", "FLEET_PANE", "FLEET_PARENT", "FLEET_MANAGES", "ASK_LIVE_PANES"]) delete env[k];
  Object.assign(env, extra);
  return spawnSync(process.execPath, ["--no-warnings", CLI, ...args, "--root", root], { encoding: "utf8", env });
};
/** manager:core in its own pane (%7), the live tree read from the seam. */
const asCore = (extra: Record<string, string> = {}) => ({ FLEET_PANE: "manager:core", TMUX_PANE: "%7", ASK_LIVE_PANES: panes, ...extra });
const status = (seat: string, id: string) => parseAskFile(fs.readFileSync(path.join(root, seat, `${id}.md`), "utf8")).header.status;
const withdraw = (seat: string, id: string, extra: Record<string, string>) => run(["withdraw", `${seat}/${id}`, "--reason", "moot"], extra);

describe("the live edge decides who manages a seat (the CLI)", () => {
  it("a stale FLEET_MANAGES with live authority is allowed: supersede, the reported refusal", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "old" }, BODY);
    newAsk(root, { from: "app:exchange", to: "manager:core", id: "new" }, BODY);
    const r = run(["supersede", "core:database/old", "--by", "app:exchange/new"], asCore({ FLEET_MANAGES: "exchange" }));
    expect(r.status, r.stderr).toBe(0);
    expect(status("core:database", "old")).toBe("superseded");
    expect(r.stderr).toMatch(/FLEET_MANAGES does not list 'core:database', but its live @pane_parent is 'manager:core'/);
    expect(r.stderr).toMatch(/reading the live tree from ASK_LIVE_PANES=/);
  });

  it("a stale FLEET_MANAGES with live authority is allowed: withdraw", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "w1" }, BODY);
    const r = withdraw("core:database", "w1", asCore({ FLEET_MANAGES: "exchange" }));
    expect(r.status, r.stderr).toBe(0);
    expect(status("core:database", "w1")).toBe("withdrawn");
  });

  it("a stale FLEET_MANAGES without live authority is refused: the seat moved to another manager", () => {
    newAsk(root, { from: "app:writer", to: "manager:app", id: "w2" }, BODY);
    const r = withdraw("app:writer", "w2", asCore({ FLEET_MANAGES: "writer,exchange" }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/only the asker \(app:writer\), its manager or the operator withdraws/);
    expect(r.stderr).toMatch(/FLEET_MANAGES lists 'app:writer', but its live @pane_parent is 'manager:app'; not honoured/);
    expect(status("app:writer", "w2")).toBe("open");
  });

  it("a stale FLEET_MANAGES without live authority is refused: the seat is gone from the live tree", () => {
    newAsk(root, { from: "core:exchange", to: "manager:core", id: "w3" }, BODY);
    const r = withdraw("core:exchange", "w3", asCore({ FLEET_MANAGES: "exchange" }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/'core:exchange' is not in the live tree; not honoured/);
    expect(status("core:exchange", "w3")).toBe("open");
  });

  it("a grant class follows the live edge too, both ways (IDE-339)", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "g1" }, BODY);
    const ok = run(["answer", "core:database/g1", "--revision", "1", "--json", '{"GO":["YES"]}', "--grant", "A"], asCore({ FLEET_MANAGES: "exchange" }));
    expect(ok.status, ok.stderr).toBe(0);
    expect(status("core:database", "g1")).toBe("answered");
    newAsk(root, { from: "app:writer", to: "manager:core", id: "g2" }, BODY);
    const no = run(["answer", "app:writer/g2", "--revision", "1", "--json", '{"GO":["YES"]}', "--grant", "A"], asCore({ FLEET_MANAGES: "writer" }));
    expect(no.status).toBe(1);
    expect(no.stderr).toMatch(/manager:core is not a manager of app:writer/);
    expect(status("app:writer", "g2")).toBe("open");
  });

  it("outside tmux the live tree is unreadable: FLEET_MANAGES decides, with a warning", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "w4" }, BODY);
    const r = withdraw("core:database", "w4", { FLEET_PANE: "manager:core", FLEET_MANAGES: "database" });
    expect(r.status, r.stderr).toBe(0);
    expect(r.stderr).toMatch(/the live tree cannot be read \(this shell is not in tmux.*'core:database' taken as managed on FLEET_MANAGES alone/);
    expect(status("core:database", "w4")).toBe("withdrawn");
  });

  it("tmux failing is unreadable too: FLEET_MANAGES decides, with a warning", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "w4b" }, BODY);
    const r = withdraw("core:database", "w4b", { FLEET_PANE: "manager:core", TMUX_PANE: "%7", FLEET_MANAGES: "database" });
    expect(r.status, r.stderr).toBe(0);
    expect(r.stderr).toMatch(/the live tree cannot be read \(tmux (list-panes failed|returned no panes)\)/);
  });

  it("with neither the live tree nor FLEET_MANAGES, it refuses", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "w5" }, BODY);
    const r = withdraw("core:database", "w5", { FLEET_PANE: "manager:core" });
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/only the asker \(core:database\), its manager or the operator withdraws/);
    expect(status("core:database", "w5")).toBe("open");
  });

  it("S4: a set but unreadable seam refuses, whatever FLEET_MANAGES says", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "s4a" }, BODY);
    const r = withdraw("core:database", "s4a", asCore({ ASK_LIVE_PANES: path.join(base, "missing.txt"), FLEET_MANAGES: "database" }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/ASK_LIVE_PANES=.*missing\.txt is not readable; no manager standing is granted/);
    expect(status("core:database", "s4a")).toBe("open");
  });

  it("S4: an empty seam refuses", () => {
    fs.writeFileSync(panes, "\n");
    newAsk(root, { from: "core:database", to: "manager:core", id: "s4b" }, BODY);
    const r = withdraw("core:database", "s4b", asCore({ FLEET_MANAGES: "database" }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/names no pane; no manager standing is granted/);
  });

  it("S2: a caller whose pane is not in the read tree is not vouched by FLEET_PANE", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "s2" }, BODY);
    const r = withdraw("core:database", "s2", asCore({ TMUX_PANE: "%999", FLEET_MANAGES: "database" }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/this pane \(%999\) is not in the live tree, so the live tree vouches for no caller/);
    expect(status("core:database", "s2")).toBe("open");
  });

  it("S3: a caller that is not a seat gets no standing while the tree reads; --by operator keeps its path", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "s3" }, BODY);
    const r = withdraw("core:database", "s3", { TMUX_PANE: "%12", ASK_LIVE_PANES: panes, FLEET_MANAGES: "database", ...{} });
    // No seat identity: the CLI wants --by; a --by naming a manager is refused, the operator is not.
    const mgr = run(["withdraw", "core:database/s3", "--reason", "moot", "--by", "manager:core"], { TMUX_PANE: "%12", ASK_LIVE_PANES: panes, FLEET_MANAGES: "database" });
    expect(r.status).toBe(1);
    expect(mgr.status).toBe(1);
    expect(mgr.stderr).toMatch(/this pane \(%12\) carries no seat label/);
    expect(status("core:database", "s3")).toBe("open");
    const op = run(["withdraw", "core:database/s3", "--reason", "moot", "--by", "operator"], { TMUX_PANE: "%12", ASK_LIVE_PANES: panes });
    expect(op.status, op.stderr).toBe(0);
    expect(status("core:database", "s3")).toBe("withdrawn");
  });

  it("S5: an asker whose case differs from its live label keeps its manager", () => {
    newAsk(root, { from: "core:Database", to: "manager:core", id: "s5" }, BODY);
    const r = withdraw("core:Database", "s5", asCore());
    expect(r.status, r.stderr).toBe(0);
  });

  it("S6: a seat two panes carry has no manager", () => {
    fs.writeFileSync(panes, TREE + "app:x %20 manager:app\napp:x %21 manager:core\n");
    newAsk(root, { from: "app:x", to: "manager:core", id: "s6" }, BODY);
    const core = withdraw("app:x", "s6", asCore({ FLEET_MANAGES: "x" }));
    expect(core.status).toBe(1);
    expect(core.stderr).toMatch(/'app:x' names 2 panes in the live tree; ambiguous/);
    const app = withdraw("app:x", "s6", { FLEET_PANE: "manager:app", TMUX_PANE: "%9", ASK_LIVE_PANES: panes });
    expect(app.status).toBe(1);
    expect(status("app:x", "s6")).toBe("open");
  });
});

describe("rename-seat after the tmux rename (MUST-1, meta:engine's ruling)", () => {
  it("allowed: old is gone, new is under the caller live, and the caller's launch-time list named old", () => {
    newAsk(root, { from: "core:exchange", to: "manager:core", id: "r1" }, BODY);
    const r = run(["rename-seat", "core:exchange", "core:database"], asCore({ FLEET_MANAGES: "exchange" }));
    expect(r.status, r.stderr).toBe(0);
    expect(r.stderr).toMatch(/'core:exchange' is gone from the live tree; 'core:database' is under 'manager:core' live and FLEET_MANAGES \(launch-time\) named 'core:exchange'/);
    expect(fs.existsSync(path.join(root, "core:database", "r1.md"))).toBe(true);
  });

  it("refused: new is under the caller, but its launch-time list never named old", () => {
    newAsk(root, { from: "core:exchange", to: "manager:core", id: "r2" }, BODY);
    const r = run(["rename-seat", "core:exchange", "core:database"], asCore({ FLEET_MANAGES: "database" }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/FLEET_MANAGES never named 'core:exchange'.*the operator can rename it/);
    expect(r.stderr).toMatch(/the operator can: --by operator/);
    expect(fs.existsSync(path.join(root, "core:exchange", "r2.md"))).toBe(true);
  });

  it("refused: old is in its list, but new is under another manager", () => {
    newAsk(root, { from: "core:exchange", to: "manager:core", id: "r3" }, BODY);
    const r = run(["rename-seat", "core:exchange", "app:writer"], asCore({ FLEET_MANAGES: "exchange" }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/'app:writer' is not under 'manager:core' in the live tree; the operator can rename it/);
    expect(fs.existsSync(path.join(root, "core:exchange", "r3.md"))).toBe(true);
  });

  it("an old seat still in the tree is judged on its own edge, as before", () => {
    newAsk(root, { from: "app:writer", to: "manager:app", id: "r4" }, BODY);
    const r = run(["rename-seat", "app:writer", "core:scribe"], asCore({ FLEET_MANAGES: "writer" }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/FLEET_MANAGES lists 'app:writer', but its live @pane_parent is 'manager:app'/);
  });
});

describe("liveManages (unit)", () => {
  const rows: LiveRow[] = [["manager:core", "%7", "-"], ["core:database", "%8", "manager:core"], ["app:writer", "%10", "manager:app"]];
  const read: LiveTree = { state: "read", rows };
  const check = (o: { tmuxPane?: string; actingAs?: string; env: string[]; tree: LiveTree | (() => LiveTree) }) => {
    const warnings: string[] = [];
    const f = liveManages({ ...o, warn: (m) => warnings.push(m) });
    return { f, warnings };
  };

  it("keeps label matching on the fallback list: `kernel` names `idealic:kernel`, not `idealic:kernelx`", () => {
    const { f } = check({ env: ["kernel"], tree: { state: "unreadable", why: "x" } });
    expect(f("idealic:kernel")).toBe(true);
    expect(f("idealic:kernelx")).toBe(false);
  });

  it("S3: no TMUX_PANE row means no standing with a read tree, whatever FLEET_MANAGES says", () => {
    expect(check({ env: ["database"], tree: read }).f("core:database")).toBe(false);
  });

  it("S2: the caller comes from its pane's row, and a differing acting identity grants nothing", () => {
    expect(check({ tmuxPane: "%7", actingAs: "manager:core", env: [], tree: read }).f("core:database")).toBe(true);
    const { f, warnings } = check({ tmuxPane: "%7", actingAs: "manager:app", env: [], tree: read });
    expect(f("core:database")).toBe(false);
    expect(warnings.join("\n")).toMatch(/acts as 'manager:app'/);
  });

  it("a seat with no live parent has no manager, and a seat never manages itself", () => {
    expect(check({ tmuxPane: "%7", env: ["core"], tree: read }).f("manager:core")).toBe(false);
  });

  it("a refused tree grants nothing, even on a listing FLEET_MANAGES", () => {
    expect(check({ tmuxPane: "%7", env: ["database"], tree: { state: "refused", why: "seam" } }).f("core:database")).toBe(false);
  });

  it("S7: reads the tree lazily, at most once, and not at all when nothing is judged", () => {
    let reads = 0;
    const { f } = check({ tmuxPane: "%7", env: [], tree: () => (reads++, read) });
    expect(reads).toBe(0);
    expect(f("core:database")).toBe(true);
    expect(f("app:writer")).toBe(false);
    expect(f.renamed!("core:exchange", "core:database")).toBe(false);
    expect(reads).toBe(1);
  });

  it("warns once per seat", () => {
    const { f, warnings } = check({ tmuxPane: "%7", env: [], tree: read });
    f("core:database");
    f("core:database");
    expect(warnings).toHaveLength(1);
  });

  it("S5/S6: edgeOf folds case and calls a doubled seat ambiguous; parentIn reads neither as a parent", () => {
    const t: LiveTree = { state: "read", rows: [...rows, ["app:x", "%20", "manager:app"], ["app:X", "%21", "manager:core"]] };
    expect(edgeOf(t, "CORE:database")).toEqual({ readable: true, present: true, parent: "manager:core" });
    expect(edgeOf(t, "app:x")).toEqual({ readable: true, present: "ambiguous", count: 2 });
    expect(parentIn(t, "app:x")).toBe("");
    expect(parentIn(t, "core:database")).toBe("manager:core");
  });

  it("readLiveTree: only inside tmux; the seam says so on stderr; a missing or empty seam is refused", () => {
    const dir = fs.mkdtempSync(path.join("/tmp", "asks-manages-tree-"));
    try {
      const p = path.join(dir, "p.txt");
      fs.writeFileSync(p, "a:b %1 -\nc:d %2 a:b\n");
      const notes: string[] = [];
      expect(readLiveTree({ ASK_LIVE_PANES: p }, (m) => notes.push(m)).state).toBe("unreadable");
      const t = readLiveTree({ TMUX_PANE: "%1", ASK_LIVE_PANES: p }, (m) => notes.push(m));
      expect(edgeOf(t, "c:d")).toEqual({ readable: true, present: true, parent: "a:b" });
      expect(edgeOf(t, "a:b")).toEqual({ readable: true, present: true, parent: "" });
      expect(notes).toEqual([`ask: reading the live tree from ASK_LIVE_PANES=${p}, not tmux`]);
      expect(readLiveTree({ TMUX_PANE: "%1", ASK_LIVE_PANES: path.join(dir, "none") }, () => {}).state).toBe("refused");
      fs.writeFileSync(p, "\n");
      expect(readLiveTree({ TMUX_PANE: "%1", ASK_LIVE_PANES: p }, () => {}).state).toBe("refused");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});
