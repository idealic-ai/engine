/**
 * `engine ask rename-seat <old> <new> [--dry-run]`: a fleet rename (operator, 2026-10-30 03:52:
 * `idealic:*` → `core:*`, `manager:idealic` → `manager:core`) moves the asker's folder and rewrites
 * every reference to the old seat in every ask under the root — the header's seat fields, the forward
 * hops, the `<seat>/<id>` refs, the answer and draft records — without moving a revision.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { answerAsk, listAsks, newAsk, readAsk, renameSeat, saveDraft, sendBatch } from "../src/lib/store.ts";
import { forwardChain, parseAskFile, setHeaderField } from "../src/lib/format.ts";

let root: string;
beforeEach(() => {
  root = path.join(fs.mkdtempSync(path.join("/tmp", "asks-rn-")), "asks");
});
afterEach(() => fs.rmSync(path.dirname(root), { recursive: true, force: true }));

const BODY = "## ¶ASK_GO: Choose one: Ship it?\nContext: c\n- [ ] [YES] Yes\n  Picks YES.\n- [ ] [NO] No\n  Picks NO.\n";
const K = "idealic:kernel";
const file = (seat: string, id: string) => path.join(root, seat, `${id}.md`);
const text = (seat: string, id: string) => fs.readFileSync(file(seat, id), "utf8");
const read = (seat: string, id: string) => parseAskFile(text(seat, id));
const push = async () => ({ status: "delivered" as const });
const edit = (seat: string, id: string, key: string, value: string) => fs.writeFileSync(file(seat, id), setHeaderField(text(seat, id), key, value));
const OP = { by: "operator" };

/** Every file under the root, with its bytes and mtime: what a dry run must leave exactly as it was. */
function snapshot(): Record<string, { text: string; mtimeMs: number }> {
  const out: Record<string, { text: string; mtimeMs: number }> = {};
  for (const seat of fs.readdirSync(root).filter((d) => !d.startsWith("."))) {
    for (const f of fs.readdirSync(path.join(root, seat))) {
      const p = path.join(root, seat, f);
      if (fs.statSync(p).isDirectory()) continue; // a lock
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
    await renameSeat(root, K, "core:kernel", OP);
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
    await renameSeat(root, K, "core:kernel", OP);
    await renameSeat(root, "manager:idealic", "manager:core", OP);
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
    await renameSeat(root, K, "core:kernel", OP);
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
    await renameSeat(root, K, "core:kernel", OP);
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
    await expect(renameSeat(root, K, "core:kernel", OP)).rejects.toThrow(/core:kernel\/k1/);
    await expect(renameSeat(root, K, "core:kernel", { dryRun: true })).rejects.toThrow(/already/);
    expect(snapshot()).toEqual(before);
  });

  it("merges into an existing folder when no id collides", async () => {
    await fleet();
    newAsk(root, { from: "core:kernel", to: "manager:idealic", id: "c9" }, BODY);
    const r = await renameSeat(root, K, "core:kernel", OP);
    expect(r.folder.mode).toBe("merge");
    expect(fs.readdirSync(path.join(root, "core:kernel")).sort()).toEqual(["c9.md", "k1.md"]);
    expect(fs.existsSync(path.join(root, K))).toBe(false);
  });

  it("refuses a bad or identical new name", async () => {
    await fleet();
    await expect(renameSeat(root, K, K, OP)).rejects.toThrow(/same/);
    await expect(renameSeat(root, K, "core/kernel", OP)).rejects.toThrow(/invalid seat/);
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
    const real = run("rename-seat", K, "core:kernel", "--by", "operator");
    expect(real.status, real.stderr).toBe(0);
    expect(fs.existsSync(file("core:kernel", "k1"))).toBe(true);
    const ans = run("answer", "core:kernel/k1", "--revision", "1", "--json", '{"GO":["YES"]}', "--by", "manager:idealic");
    expect(ans.status, ans.stderr).toBe(0);
    expect(read("core:kernel", "k1").answer?.answeredBy).toBe("manager:idealic");
    // The old name is gone: an answer to it is refused.
    expect(run("answer", `${K}/k1`, "--revision", "2", "--json", '{"GO":["NO"]}', "--by", "manager:idealic").status).toBe(1);
  });
});

// ── round 2 ──────────────────────────────────────────────

const stage = (seat: string) => path.join(root, ".rename-seat", `${seat}.staging`);
/** Every place a file named `<id>.md` sits under the root, staging included: a split shows as two. */
function places(id: string): string[] {
  const out: string[] = [];
  const walk = (d: string, rel: string) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.isDirectory()) {
        if (!e.name.endsWith(".lock")) walk(path.join(d, e.name), `${rel}${e.name}/`);
      } else if (e.name === `${id}.md`) out.push(`${rel}${e.name}`);
    }
  };
  walk(root, "");
  return out.sort();
}
const until = async (cond: () => boolean, ms = 5000) => {
  const end = Date.now() + ms;
  while (!cond()) {
    if (Date.now() > end) throw new Error("timed out waiting");
    await new Promise((r) => setTimeout(r, 5));
  }
};
const YES = (by: string) => ({ answers: { GO: ["YES"] }, answeredBy: by });

describe("renameSeat: a live writer (M1)", () => {
  it("moves the old folder out of reach first, waits for a write in flight, then merges; a late writer is told where the seat went", async () => {
    await fleet();
    newAsk(root, { from: "core:kernel", to: "manager:idealic", id: "c9" }, BODY);
    fs.mkdirSync(`${file(K, "k1")}.lock`); // a writer holds k1
    const running = renameSeat(root, K, "core:kernel", OP);
    running.catch(() => {});
    await until(() => fs.existsSync(path.join(stage(K), "k1.md.lock")));
    expect(fs.existsSync(path.join(root, K))).toBe(false);
    expect(places("k1")).toEqual([`.rename-seat/${K}.staging/k1.md`]);
    expect(listAsks(root).filter((a) => a.header.id === "k1")).toEqual([]);
    await expect(answerAsk(root, K, "k1", YES("manager:idealic"), { expectedRevision: 1, push })).rejects.toThrow(
      /seat idealic:kernel was renamed to core:kernel.*may have landed.*engine ask read core:kernel\/k1/s,
    );
    // Still waiting: nothing has reached the new folder yet.
    expect(fs.existsSync(file("core:kernel", "k1"))).toBe(false);
    fs.rmdirSync(path.join(stage(K), "k1.md.lock")); // the holder finishes
    const r = await running;
    expect(r.moved).toBe(1);
    expect(places("k1")).toEqual(["core:kernel/k1.md"]);
    expect(fs.existsSync(stage(K))).toBe(false);
    expect(read("core:kernel", "k1").header.from).toBe("core:kernel");
  });

  it("refuses when a write in flight does not finish, puts the folder back as it was, and a second run finishes", async () => {
    await fleet();
    fs.mkdirSync(`${file(K, "k1")}.lock`);
    const before = snapshot();
    await expect(renameSeat(root, K, "core:kernel", { ...OP, waitMs: 200 })).rejects.toThrow(/in flight.*k1\.md\.lock.*nothing was moved.*run the same command again/s);
    expect(snapshot()).toEqual(before);
    expect(places("k1")).toEqual([`${K}/k1.md`]);
    expect(fs.existsSync(`${file(K, "k1")}.lock`)).toBe(true);
    fs.rmdirSync(`${file(K, "k1")}.lock`);
    const r = await renameSeat(root, K, "core:kernel", OP);
    expect(r.moved).toBe(1);
    expect(places("k1")).toEqual(["core:kernel/k1.md"]);
  });

  it("never overwrites: an ask that lands in the new folder under the same id during the move is kept, and the moved one goes back", async () => {
    await fleet();
    newAsk(root, { from: "core:kernel", to: "manager:idealic", id: "c9" }, BODY);
    const plant = (s: string) => {
      if (s === "staged") newAsk(root, { from: "core:kernel", to: "app:writer", id: "k1" }, BODY);
    };
    await expect(renameSeat(root, K, "core:kernel", { ...OP, onStep: plant })).rejects.toThrow(/core:kernel\/k1 .*nothing was overwritten/s);
    expect(read("core:kernel", "k1").header.to).toBe("app:writer");
    expect(read(K, "k1").header.from).toBe(K);
    expect(places("k1")).toEqual(["core:kernel/k1.md", `${K}/k1.md`]);
    expect(fs.existsSync(stage(K))).toBe(false);
  });

  for (const step of ["ledger", "staged", "linked:k1.md", "moved"]) {
    it(`a run that stops at "${step}" is finished by running again, and no ask is ever listed twice`, async () => {
      await fleet();
      newAsk(root, { from: "core:kernel", to: "manager:idealic", id: "c9" }, BODY);
      const crash = (s: string) => {
        if (s === step) throw new Error("crash");
      };
      await expect(renameSeat(root, K, "core:kernel", { ...OP, onStep: crash })).rejects.toThrow("crash");
      expect(listAsks(root).filter((a) => a.header.id === "k1").length).toBeLessThanOrEqual(1);
      await renameSeat(root, K, "core:kernel", OP);
      expect(places("k1")).toEqual(["core:kernel/k1.md"]);
      expect(fs.statSync(file("core:kernel", "k1")).nlink).toBe(1);
      expect(read("core:kernel", "k1").header.from).toBe("core:kernel");
      expect(read("app:writer", "w1").header.to).toBe("core:kernel");
      expect(fs.existsSync(stage(K))).toBe(false);
      expect(fs.existsSync(path.join(root, K))).toBe(false);
    });
  }
});

describe("renameSeat: a writer caught by the rename (S1)", () => {
  it("an answer that landed before the seat moved reports success, and its delivery is stamped where the ask now is", async () => {
    newAsk(root, { from: K, to: "manager:idealic", id: "k1" }, BODY);
    const pushAndMove = async () => {
      await renameSeat(root, K, "core:kernel", OP);
      return { status: "delivered" as const };
    };
    const r = await answerAsk(root, K, "k1", YES("manager:idealic"), { expectedRevision: 1, push: pushAndMove });
    expect(r.revision).toBe(2);
    expect(r.file).toBe(file("core:kernel", "k1"));
    const k1 = read("core:kernel", "k1");
    expect(k1.answer?.answeredBy).toBe("manager:idealic");
    expect(k1.header.delivery).toBe("delivered");
  });

  // R2-1 (the reviewer's plant P4): the folder moves to staging while answerAsk holds the file lock,
  // so the lock's release finds `<old>/k1.md.lock` gone. Deterministic: the move is started from
  // inside the lock, right after the answer's own atomic rename lands, by calling renameSeat, whose
  // part up to its first await (the ledger, then `<old>/` → staging) runs synchronously.
  it("an answer whose seat folder moves to staging while it holds the lock reports success, and lands at the new path (R2-1)", async () => {
    newAsk(root, { from: K, to: "manager:idealic", id: "k1" }, BODY);
    const realRename = fs.renameSync.bind(fs);
    let running: Promise<unknown> | undefined;
    const spy = vi.spyOn(fs, "renameSync").mockImplementation((from, to) => {
      realRename(from, to);
      if (!running && to === file(K, "k1") && String(from).endsWith(".tmp")) {
        running = renameSeat(root, K, "core:kernel", { ...OP, waitMs: 500 });
        running.catch(() => {});
      }
    });
    // The push waits for the rename to finish, so the delivery stamp has one place to go.
    const pushAfterMove = async () => {
      await running?.catch(() => {});
      return { status: "delivered" as const };
    };
    let r: Awaited<ReturnType<typeof answerAsk>>;
    try {
      r = await answerAsk(root, K, "k1", YES("manager:idealic"), { expectedRevision: 1, push: pushAfterMove });
    } finally {
      spy.mockRestore();
    }
    expect(running).toBeDefined(); // the move did happen inside the lock
    await expect(running).resolves.toMatchObject({ moved: 1 });
    expect(r.revision).toBe(2);
    expect(r.file).toBe(file("core:kernel", "k1"));
    expect(places("k1")).toEqual(["core:kernel/k1.md"]);
    const k1 = read("core:kernel", "k1");
    expect(k1.answer?.answeredBy).toBe("manager:idealic");
    expect(k1.header.delivery).toBe("delivered");
    expect(fs.existsSync(stage(K))).toBe(false);
    expect(fs.existsSync(`${file("core:kernel", "k1")}.lock`)).toBe(false);
  });

  it("a write to a seat that has moved says where it went", async () => {
    newAsk(root, { from: K, to: "manager:idealic", id: "k1" }, BODY);
    await renameSeat(root, K, "core:kernel", OP);
    await expect(answerAsk(root, K, "k1", YES("manager:idealic"), { expectedRevision: 1, push })).rejects.toThrow(
      /seat idealic:kernel was renamed to core:kernel.*may have landed.*engine ask read core:kernel\/k1/s,
    );
  });
});

describe("renameSeat: the fields the first round's tests missed (S2, S3)", () => {
  it("askedBy: the seat part of `seat · thread · log` follows, whole name only (S2)", async () => {
    newAsk(root, { from: "app:writer", to: "manager:idealic", id: "a1", askedBy: `${K} · IDE-1 · sessions/x/LOG.md` }, BODY);
    newAsk(root, { from: "app:writer", to: "manager:idealic", id: "a2", askedBy: `${K}-2 · IDE-1 · log` }, BODY);
    newAsk(root, { from: "app:writer", to: "manager:idealic", id: "a3", askedBy: `app:writer · ${K} · log` }, BODY);
    newAsk(root, { from: "app:writer", to: "manager:idealic", id: "a4", askedBy: K }, BODY);
    await renameSeat(root, K, "core:kernel", OP);
    expect(read("app:writer", "a1").header.askedBy).toBe("core:kernel · IDE-1 · sessions/x/LOG.md");
    expect(read("app:writer", "a2").header.askedBy).toBe(`${K}-2 · IDE-1 · log`);
    expect(read("app:writer", "a3").header.askedBy).toBe(`app:writer · ${K} · log`);
    expect(read("app:writer", "a4").header.askedBy).toBe("core:kernel");
  });

  it("reads: a forwarder's read entry follows, so `read --unread` does not hand it back what it read (R3)", async () => {
    newAsk(root, { from: "app:writer", to: "manager:idealic", id: "r1" }, BODY);
    edit("app:writer", "r1", "reads", `${K}@2026-10-30T01:00:00.000Z ; app:writer@2026-10-30T02:00:00.000Z ; ${K}-2@2026-10-30T03:00:00.000Z`);
    await renameSeat(root, K, "core:kernel", OP);
    expect(read("app:writer", "r1").header.reads).toBe(`core:kernel@2026-10-30T01:00:00.000Z ; app:writer@2026-10-30T02:00:00.000Z ; ${K}-2@2026-10-30T03:00:00.000Z`);
  });

  it("delivery, deliveryNote and revisions stamps follow; look-alikes (idealic:kernel-2, idealic:kernel.v2) do not (R1, R8)", async () => {
    newAsk(root, { from: "app:writer", to: "manager:idealic", id: "d1" }, BODY);
    edit("app:writer", "d1", "delivery", `partial ${K}`);
    edit("app:writer", "d1", "deliveryNote", `${K}-2: no live session; ${K}.v2: gone; ${K}: no live session`);
    edit("app:writer", "d1", "revisions", `2@2026-10-30T01:00:00.000Z:to ${K}`);
    await renameSeat(root, K, "core:kernel", OP);
    const h = read("app:writer", "d1").header;
    expect(h.delivery).toBe("partial core:kernel");
    expect(h.deliveryNote).toBe(`${K}-2: no live session; ${K}.v2: gone; core:kernel: no live session`);
    expect(h.revisions).toBe("2@2026-10-30T01:00:00.000Z:to core:kernel");
  });

  it("relayedFrom and actedBy in an answer record follow (R9)", async () => {
    newAsk(root, { from: "app:writer", to: K, id: "j1" }, BODY);
    await answerAsk(root, "app:writer", "j1", YES(K), { expectedRevision: 1, push });
    const t = text("app:writer", "j1");
    const planted = t.replace(/("answeredBy":\s*"idealic:kernel")/, `$1,\n  "relayedFrom": "${K}",\n  "actedBy": "${K}"`);
    expect(planted).not.toBe(t);
    fs.writeFileSync(file("app:writer", "j1"), planted);
    await renameSeat(root, K, "core:kernel", OP);
    const raw = text("app:writer", "j1");
    expect(raw).toContain('"relayedFrom": "core:kernel"');
    expect(raw).toContain('"actedBy": "core:kernel"');
    expect(raw).not.toContain(`"${K}"`);
  });
});

describe("renameSeat: who may (S4)", () => {
  it("only the operator or the old seat's own manager renames a seat; a dry run writes nothing and is open to anyone", async () => {
    await fleet();
    const before = snapshot();
    await expect(renameSeat(root, K, "core:kernel", { by: "idealic:ui", manages: [] })).rejects.toThrow(/only the operator or idealic:kernel's manager .*idealic:ui is neither/);
    await expect(renameSeat(root, K, "core:kernel")).rejects.toThrow(/only the operator or idealic:kernel's manager/);
    await expect(renameSeat(root, K, "core:kernel", { by: "manager:app", manages: ["writer"] })).rejects.toThrow(/manager:app is neither/);
    expect(snapshot()).toEqual(before);
    await renameSeat(root, K, "core:kernel", { dryRun: true, by: "idealic:ui" });
    await renameSeat(root, K, "core:kernel", { by: "manager:idealic", manages: ["kernel", "ui"] });
    expect(read("core:kernel", "k1").header.from).toBe("core:kernel");
  });
});

describe("engine ask rename-seat (the CLI), round 2", () => {
  const CLI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.ts");
  const run = (args: string[], extra: Record<string, string> = {}) => {
    const env: NodeJS.ProcessEnv = { ...process.env, ASK_SESSIONS_DIR: path.join(path.dirname(root), "sessions") };
    for (const k of ["TMUX_PANE", "TMUX", "FLEET_PANE", "FLEET_PARENT", "FLEET_MANAGES"]) delete env[k];
    Object.assign(env, extra);
    return spawnSync(process.execPath, ["--no-warnings", CLI, ...args, "--root", root], { encoding: "utf8", env });
  };

  it("refuses a seat renaming a seat it does not manage; its manager and the operator may (S4)", () => {
    newAsk(root, { from: K, to: "manager:idealic", id: "k1" }, BODY);
    const bystander = run(["rename-seat", K, "core:kernel"], { FLEET_PANE: "idealic:ui" });
    expect(bystander.status).toBe(1);
    expect(bystander.stderr).toMatch(/only the operator or idealic:kernel's manager/);
    expect(run(["rename-seat", K, "core:kernel"]).status).toBe(1); // no identity at all
    expect(run(["rename-seat", K, "core:kernel", "--by", "operator"], { FLEET_PANE: "idealic:ui" }).status).toBe(1);
    expect(fs.existsSync(file(K, "k1"))).toBe(true);
    const mgr = run(["rename-seat", K, "core:kernel"], { FLEET_PANE: "manager:idealic", FLEET_MANAGES: "kernel,ui" });
    expect(mgr.status, mgr.stderr).toBe(0);
    expect(fs.existsSync(file("core:kernel", "k1"))).toBe(true);
  });

  it("says how many asks it moved and to run it again until a pass changes nothing; lists refs left as written; checks revisions (S5, N1, N3)", () => {
    newAsk(root, { from: K, to: "manager:idealic", id: "k1" }, `See ${K}/k0 for the earlier one.\n\n${BODY}`);
    newAsk(root, { from: K, to: "manager:idealic", id: "k2" }, BODY);
    const real = run(["rename-seat", K, "core:kernel", "--by", "operator"]);
    expect(real.status, real.stderr).toBe(0);
    expect(real.stdout).toMatch(/^recovery\t.*run the same command again/m);
    expect(real.stdout).toContain(`${K}/k1.md\tbody\t${K}/k0\tleft as written`);
    expect(real.stdout).toMatch(/revisions checked: unchanged in 2 files/);
    expect(real.stdout).toMatch(/moved 2 asks; changed 2 fields in 2 files/);
    expect(real.stdout).toMatch(/run it again until a pass reports moved 0 asks and changed 0 fields/);
    // A seat still using the old name files under it again: a dry run says so, and a second pass moves it.
    newAsk(root, { from: K, to: "manager:idealic", id: "stale-1" }, BODY);
    const dry = run(["rename-seat", K, "core:kernel", "--dry-run"]);
    expect(dry.status, dry.stderr).toBe(0);
    expect(dry.stdout).toMatch(new RegExp(`^leftover\\t${K}/ exists again after an earlier rename to core:kernel \\(1 ask: stale-1\\)`, "m"));
    const again = run(["rename-seat", K, "core:kernel", "--by", "operator"]);
    expect(again.stdout).toMatch(/moved 1 ask; changed 1 field in 1 file/);
    const last = run(["rename-seat", K, "core:kernel", "--by", "operator"]);
    expect(last.stdout).toMatch(/moved 0 asks; changed 0 fields in 0 files/);
    expect(last.status).toBe(0);
  });

  it("a dry run reports asks waiting in staging from a run that stopped (S5)", async () => {
    newAsk(root, { from: K, to: "manager:idealic", id: "k1" }, BODY);
    newAsk(root, { from: "core:kernel", to: "manager:idealic", id: "c9" }, BODY);
    await expect(renameSeat(root, K, "core:kernel", { ...OP, onStep: (s) => { if (s === "staged") throw new Error("crash"); } })).rejects.toThrow("crash");
    const dry = run(["rename-seat", K, "core:kernel", "--dry-run"]);
    expect(dry.status, dry.stderr).toBe(0);
    expect(dry.stdout).toMatch(/^leftover\t.*stopped partway.*1 ask: k1/m);
  });
});
