/**
 * `engine ask rename-seat <old> <new> [--dry-run]`: a fleet rename (operator, 2026-10-30 03:52:
 * `idealic:*` → `core:*`, `manager:idealic` → `manager:core`) moves the asker's folder and rewrites
 * every reference to the old seat in every ask under the root — the header's seat fields, the forward
 * hops, the `<seat>/<id>` refs, the answer and draft records — without moving a revision.
 */
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { answerAsk, newAsk, readAsk, renameSeat, saveDraft, sendBatch } from "../src/lib/store.ts";
import { forwardChain, parseAskFile, setHeaderField } from "../src/lib/format.ts";

let root: string;
beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-rn-")), "asks");
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const K = "idealic:kernel";
const file = (seat: string, id: string) => path.join(root, seat, `${id}.md`);
const text = (seat: string, id: string) => fs.readFileSync(file(seat, id), "utf8");
const read = (seat: string, id: string) => parseAskFile(text(seat, id));
const push = async () => ({ status: "delivered" as const });
const edit = (seat: string, id: string, key: string, value: string) => fs.writeFileSync(file(seat, id), setHeaderField(text(seat, id), key, value));

/** Every file under the root, with its bytes and mtime: what a dry run must leave exactly as it was. */
function snapshot(): Record<string, { text: string; mtimeMs: number }> {
  const out: Record<string, { text: string; mtimeMs: number }> = {};
  for (const seat of fs.readdirSync(root)) {
    for (const f of fs.readdirSync(path.join(root, seat))) {
      const p = path.join(root, seat, f);
      out[`${seat}/${f}`] = { text: fs.readFileSync(p, "utf8"), mtimeMs: fs.statSync(p).mtimeMs };
    }
  }
  return out;
}

/**
 * A small fleet: k1 is idealic:kernel's own ask (moves with the folder); w1 is app:writer's ask
 * answered by idealic:kernel; w2 is app:writer's ask the operator answered with idealic:kernel
 * relaying; w3 is reserved, declined by idealic:kernel and passed up (a hop with an escaped reason);
 * w4 is open with idealic:kernel's draft; i1 is app:Idealic's ask naming look-alikes only.
 */
async function fleet() {
  newAsk(root, { from: K, to: "manager:idealic", id: "k1", related: `${K}/k0 ; app:Idealic/z1`, dependsOn: `${K}/k0` }, BODY);
  newAsk(root, { from: "app:writer", to: K, id: "w1", context: `see ${K}/k1 and /x/asks/${K}/k1.md; told ${K} at 01:00` }, BODY);
  await answerAsk(root, "app:writer", "w1", { answers: { GO: ["YES"] }, answeredBy: K, note: `${K} checked this` }, { expectedRevision: 1, push });
  await readAsk(root, "app:writer", "w1", { by: "app:writer" });
  newAsk(root, { from: "app:writer", to: K, id: "w2" }, BODY);
  await answerAsk(root, "app:writer", "w2", { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: `relay:${K}`, note: "operator, 01:00" }, { expectedRevision: 1, push });
  newAsk(root, { from: "app:writer", to: K, id: "w3", "reserved-for": "operator" }, BODY);
  await answerAsk(root, "app:writer", "w3", { declined: true, reason: `not mine; ask ${K}@home` , answeredBy: K }, { expectedRevision: 1, passUpTo: "manager:idealic", push });
  newAsk(root, { from: "app:writer", to: K, id: "w4" }, BODY);
  await saveDraft(root, "app:writer", "w4", { answers: { GO: ["YES"] }, answeredBy: K }, 1);
  newAsk(root, { from: "app:Idealic", to: "xidealic:kernel", id: "i1", related: `app:Idealic/z2 ; ${K}x/z3 ; x${K}/z4`, askedBy: "idealic:kernelx" }, BODY);
}

describe("renameSeat: a dry run", () => {
  it("changes nothing, and names every file and field it would change, old → new", async () => {
    await fleet();
    const before = snapshot();
    const r = await renameSeat(root, K, "core:kernel", { dryRun: true });
    expect(snapshot()).toEqual(before);
    expect(fs.existsSync(path.join(root, "core:kernel"))).toBe(false);
    expect(r.dryRun).toBe(true);
    expect(r.folder).toMatchObject({ mode: "move", ids: ["k1"] });
    const said = r.changes.map((c) => `${c.file} ${c.field} ${c.from} → ${c.to}`);
    expect(said).toContain(`${K}/k1.md from ${K} → core:kernel`);
    expect(said).toContain(`app:writer/w1.md to ${K} → core:kernel`);
    expect(said).toContain(`app:writer/w1.md answer.answeredBy ${K} → core:kernel`);
    expect(said).toContain(`app:writer/w2.md answer.answeredVia relay:${K} → relay:core:kernel`);
    expect(said).toContain(`app:writer/w4.md draft.answeredBy ${K} → core:kernel`);
    expect(said.some((s) => s.startsWith("app:writer/w3.md forwards "))).toBe(true);
    // Nothing in the look-alikes' file.
    expect(r.changes.filter((c) => c.file.startsWith("app:Idealic/"))).toEqual([]);
  });
});

describe("renameSeat: a real run", () => {
  it("moves the folder and rewrites to/from/forwards/refs/answer JSON in other seats' files", async () => {
    await fleet();
    await renameSeat(root, K, "core:kernel");
    expect(fs.existsSync(path.join(root, K))).toBe(false);
    const k1 = read("core:kernel", "k1");
    expect(k1.header.from).toBe("core:kernel");
    expect(k1.header.related).toBe("core:kernel/k0 ; app:Idealic/z1");
    expect(k1.header.dependsOn).toBe("core:kernel/k0");
    const w1 = read("app:writer", "w1");
    expect(w1.header.to).toBe("core:kernel");
    expect(w1.answer?.answeredBy).toBe("core:kernel");
    // Refs and the path to the moved file follow; a bare mention in prose, and a note, are left alone.
    expect(w1.header.context).toBe(`see core:kernel/k1 and /x/asks/core:kernel/k1.md; told ${K} at 01:00`);
    expect(w1.answer?.note).toBe(`${K} checked this`);
    expect(read("app:writer", "w2").answer?.answeredVia).toBe("relay:core:kernel");
    const w3 = read("app:writer", "w3");
    expect(forwardChain(w3.header)).toEqual([expect.objectContaining({ from: "core:kernel", to: "manager:idealic", reason: `not mine; ask ${K}@home` })]);
    // The escaping on disk is kept byte for byte.
    expect(w3.header.forwards).toContain(`[declined: not mine%3B ask ${K}%40home]`);
    expect(read("app:writer", "w4").draft?.answeredBy).toBe("core:kernel");
  });

  it("matches whole seat names only: app:Idealic, xidealic:kernel and idealic:kernelx are left alone", async () => {
    await fleet();
    const i1 = text("app:Idealic", "i1");
    await renameSeat(root, K, "core:kernel");
    await renameSeat(root, "manager:idealic", "manager:core");
    expect(text("app:Idealic", "i1")).toBe(i1);
    expect(fs.existsSync(path.join(root, "app:Idealic", "i1.md"))).toBe(true);
    // manager:idealic's rename reached k1's to: and w3's hop, nothing called Idealic.
    expect(read("core:kernel", "k1").header.to).toBe("manager:core");
    expect(read("core:kernel", "k1").header.related).toBe("core:kernel/k0 ; app:Idealic/z1");
    expect(forwardChain(read("app:writer", "w3").header)[0].to).toBe("manager:core");
  });

  it("keeps every revision and every mtime", async () => {
    await fleet();
    const before = snapshot();
    await renameSeat(root, K, "core:kernel");
    const after = snapshot();
    for (const [k, v] of Object.entries(before)) {
      const key = k.startsWith(`${K}/`) ? `core:kernel/${k.slice(K.length + 1)}` : k;
      expect(after[key], key).toBeDefined();
      expect(parseAskFile(after[key].text).header.revision, key).toBe(parseAskFile(v.text).header.revision);
      // The app sorts newest first by mtime: kept to well under a millisecond, so no two asks swap.
      expect(Math.abs(after[key].mtimeMs - v.mtimeMs), key).toBeLessThan(0.01);
    }
  });

  it("a moved draft still sends under the new name, and the honoured draft stays honoured", async () => {
    await fleet();
    await renameSeat(root, K, "core:kernel");
    const out = await sendBatch(root, undefined, { by: "core:kernel", push });
    expect(out.refused).toEqual([]);
    expect(out.settled.map((s) => s.ref)).toEqual(["app:writer/w4"]);
    expect(read("app:writer", "w4").answer?.answeredBy).toBe("core:kernel");
  });
});

describe("renameSeat: the folder", () => {
  it("refuses when the new folder holds an ask with the same id, and changes nothing", async () => {
    await fleet();
    newAsk(root, { from: "core:kernel", to: "manager:idealic", id: "k1" }, BODY);
    const before = snapshot();
    await expect(renameSeat(root, K, "core:kernel")).rejects.toThrow(/core:kernel\/k1/);
    await expect(renameSeat(root, K, "core:kernel", { dryRun: true })).rejects.toThrow(/already/);
    expect(snapshot()).toEqual(before);
  });

  it("merges into an existing folder when no id collides", async () => {
    await fleet();
    newAsk(root, { from: "core:kernel", to: "manager:idealic", id: "c9" }, BODY);
    const r = await renameSeat(root, K, "core:kernel");
    expect(r.folder.mode).toBe("merge");
    expect(fs.readdirSync(path.join(root, "core:kernel")).sort()).toEqual(["c9.md", "k1.md"]);
    expect(fs.existsSync(path.join(root, K))).toBe(false);
  });

  it("refuses a bad or identical new name", async () => {
    await fleet();
    await expect(renameSeat(root, K, K)).rejects.toThrow(/same/);
    await expect(renameSeat(root, K, "core/kernel")).rejects.toThrow(/invalid seat/);
  });
});

describe("engine ask rename-seat (the CLI)", () => {
  const CLI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.ts");
  const run = (...args: string[]) => {
    const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(path.dirname(root), "sessions") };
    for (const k of ["TMUX_PANE", "FLEET_PANE", "FLEET_PARENT", "FLEET_MANAGES"]) delete env[k];
    return spawnSync(process.execPath, ["--no-warnings", CLI, ...args, "--root", root], { encoding: "utf8", env });
  };

  it("previews with --dry-run, renames, and an answer to the moved ask by its new name works", async () => {
    newAsk(root, { from: K, to: "manager:idealic", id: "k1" }, BODY);
    const dry = run("rename-seat", K, "core:kernel", "--dry-run");
    expect(dry.status, dry.stderr).toBe(0);
    expect(dry.stdout).toContain("dry run");
    expect(dry.stdout).toContain(`${K}/k1.md\tfrom\t${K} → core:kernel`);
    expect(fs.existsSync(file(K, "k1"))).toBe(true);
    const real = run("rename-seat", K, "core:kernel");
    expect(real.status, real.stderr).toBe(0);
    expect(fs.existsSync(file("core:kernel", "k1"))).toBe(true);
    const ans = run("answer", "core:kernel/k1", "--revision", "1", "--json", '{"GO":["YES"]}', "--by", "manager:idealic");
    expect(ans.status, ans.stderr).toBe(0);
    expect(read("core:kernel", "k1").answer?.answeredBy).toBe("manager:idealic");
    // The old name is gone: an answer to it is refused.
    expect(run("answer", `${K}/k1`, "--revision", "2", "--json", '{"GO":["NO"]}', "--by", "manager:idealic").status).toBe(1);
  });
});
