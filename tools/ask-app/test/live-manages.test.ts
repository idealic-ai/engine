/**
 * MANAGES (meta:engine, 2026-11-04): "is the caller a manager of the asker" is read from the live
 * tmux edge (the asker's @pane_parent, hop.sh's read), not from FLEET_MANAGES, which run.sh froze at
 * launch. Reported: manager:core's FLEET_MANAGES still listed `exchange` after core:exchange was
 * renamed core:database, so `engine ask supersede core:database/<old> --by …` was refused although
 * `hop.sh target --of core:database` printed manager:core.
 *
 * The four cases: a stale env with live authority is allowed; a stale env without live authority is
 * refused (the security direction: a listed seat that moved away grants nothing); an unreadable tree
 * falls back to FLEET_MANAGES with a warning; neither source refuses.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { newAsk } from "../src/lib/store.ts";
import { parseAskFile } from "../src/lib/format.ts";
import { edgeOf, liveManages, readLiveTree, type LiveRow } from "../src/lib/manages.ts";

const CLI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.ts");
const BODY = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";

// The live tree after today's moves: core:exchange renamed core:database (still under manager:core),
// and app:writer moved from manager:core to manager:app.
const TREE = ["manager:core %7 -", "core:database %8 manager:core", "manager:app %9 -", "app:writer %10 manager:app", "idealic:runner %11 -"].join("\n") + "\n";

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

/** The CLI as manager:core, with nothing delivered to a real seat (ASK_SESSIONS_DIR is scratch). */
const run = (args: string[], extra: Record<string, string> = {}) => {
  const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(base, "sessions"), ASK_TMUX_SOCKET: "ask-manages-test-none" };
  for (const k of ["TMUX_PANE", "TMUX", "FLEET_PANE", "FLEET_PARENT", "FLEET_MANAGES", "ASK_LIVE_PANES"]) delete env[k];
  Object.assign(env, extra);
  return spawnSync(process.execPath, ["--no-warnings", CLI, ...args, "--root", root], { encoding: "utf8", env });
};
const asCore = (extra: Record<string, string> = {}) => ({ FLEET_PANE: "manager:core", TMUX_PANE: "%7", ASK_LIVE_PANES: panes, ...extra });
const status = (seat: string, id: string) => parseAskFile(fs.readFileSync(path.join(root, seat, `${id}.md`), "utf8")).header.status;

describe("the live edge decides who manages a seat (the CLI)", () => {
  it("a stale FLEET_MANAGES with live authority is allowed: supersede, the reported refusal", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "old" }, BODY);
    newAsk(root, { from: "app:exchange", to: "manager:core", id: "new" }, BODY);
    const r = run(["supersede", "core:database/old", "--by", "app:exchange/new"], asCore({ FLEET_MANAGES: "exchange" }));
    expect(r.status, r.stderr).toBe(0);
    expect(status("core:database", "old")).toBe("superseded");
    expect(r.stderr).toMatch(/FLEET_MANAGES does not list 'core:database', but its live @pane_parent is 'manager:core'/);
  });

  it("a stale FLEET_MANAGES with live authority is allowed: withdraw", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "w1" }, BODY);
    const r = run(["withdraw", "core:database/w1", "--reason", "moot"], asCore({ FLEET_MANAGES: "exchange" }));
    expect(r.status, r.stderr).toBe(0);
    expect(status("core:database", "w1")).toBe("withdrawn");
  });

  it("a stale FLEET_MANAGES without live authority is refused: the seat moved to another manager", () => {
    newAsk(root, { from: "app:writer", to: "manager:app", id: "w2" }, BODY);
    const r = run(["withdraw", "app:writer/w2", "--reason", "moot"], asCore({ FLEET_MANAGES: "writer,exchange" }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/only the asker \(app:writer\), its manager or the operator withdraws/);
    expect(r.stderr).toMatch(/FLEET_MANAGES lists 'app:writer', but its live @pane_parent is 'manager:app'; not honoured/);
    expect(status("app:writer", "w2")).toBe("open");
  });

  it("a stale FLEET_MANAGES without live authority is refused: the seat is gone from the live tree", () => {
    newAsk(root, { from: "core:exchange", to: "manager:core", id: "w3" }, BODY);
    const r = run(["withdraw", "core:exchange/w3", "--reason", "moot"], asCore({ FLEET_MANAGES: "exchange" }));
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

  it("an unreadable live tree falls back to FLEET_MANAGES, with a warning", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "w4" }, BODY);
    const r = run(["withdraw", "core:database/w4", "--reason", "moot"], asCore({ ASK_LIVE_PANES: path.join(base, "missing.txt"), FLEET_MANAGES: "database" }));
    expect(r.status, r.stderr).toBe(0);
    expect(r.stderr).toMatch(/the live tree cannot be read; 'core:database' taken as managed on FLEET_MANAGES alone/);
    expect(status("core:database", "w4")).toBe("withdrawn");
  });

  it("with neither the live tree nor FLEET_MANAGES, it refuses", () => {
    newAsk(root, { from: "core:database", to: "manager:core", id: "w5" }, BODY);
    const r = run(["withdraw", "core:database/w5", "--reason", "moot"], asCore({ ASK_LIVE_PANES: path.join(base, "missing.txt") }));
    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/only the asker \(core:database\), its manager or the operator withdraws/);
    expect(status("core:database", "w5")).toBe("open");
  });
});

describe("liveManages (unit)", () => {
  const tree: LiveRow[] = [["manager:core", "%7", "-"], ["core:database", "%8", "manager:core"], ["app:writer", "%10", "manager:app"]];
  const check = (self: string, env: string[], t: LiveRow[] | undefined) => {
    const warnings: string[] = [];
    const f = liveManages({ self, env, tree: t, warn: (m) => warnings.push(m) });
    return { f, warnings };
  };

  it("keeps label matching on the fallback list: `kernel` names `idealic:kernel`, not `idealic:kernelx`", () => {
    const { f } = check("manager:idealic", ["kernel"], undefined);
    expect(f("idealic:kernel")).toBe(true);
    expect(f("idealic:kernelx")).toBe(false);
  });

  it("a caller that is not a seat is judged on FLEET_MANAGES only, even with a readable tree", () => {
    const { f, warnings } = check("", [], tree);
    expect(f("core:database")).toBe(false);
    expect(warnings).toEqual([]);
  });

  it("a seat with no live parent has no manager, and a seat never manages itself", () => {
    expect(check("manager:core", ["core"], tree).f("manager:core")).toBe(false);
  });

  it("reads the tree lazily, at most once, and not at all when nothing is judged", () => {
    let reads = 0;
    const f = liveManages({ self: "manager:core", env: [], tree: () => (reads++, tree), warn: () => {} });
    expect(reads).toBe(0);
    expect(f("core:database")).toBe(true);
    expect(f("app:writer")).toBe(false);
    expect(reads).toBe(1);
  });

  it("warns once per seat", () => {
    const { f, warnings } = check("manager:core", [], tree);
    f("core:database");
    f("core:database");
    expect(warnings).toHaveLength(1);
  });

  it("readLiveTree reads only inside tmux, and an empty seam is unreadable", () => {
    const dir = fs.mkdtempSync(path.join("/tmp", "asks-manages-tree-"));
    try {
      const p = path.join(dir, "p.txt");
      fs.writeFileSync(p, "a:b %1 -\nc:d %2 a:b\n");
      expect(readLiveTree({ ASK_LIVE_PANES: p })).toBeUndefined();
      expect(edgeOf(readLiveTree({ TMUX_PANE: "%1", ASK_LIVE_PANES: p }), "c:d")).toEqual({ readable: true, present: true, parent: "a:b" });
      expect(edgeOf(readLiveTree({ TMUX_PANE: "%1", ASK_LIVE_PANES: p }), "a:b")).toEqual({ readable: true, present: true, parent: "" });
      fs.writeFileSync(p, "\n");
      expect(readLiveTree({ TMUX_PANE: "%1", ASK_LIVE_PANES: p })).toBeUndefined();
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});
