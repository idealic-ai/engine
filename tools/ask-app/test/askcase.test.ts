/**
 * ASKCASE: a case-only seat rename (`domain:Language` → `domain:language`) on a case-insensitive
 * volume. There the two names are ONE folder (the same inode), so rename-seat used to see every ask
 * "already exist" in the new folder and refuse. A case-only rename moves through staging and rewrites
 * like any other; a real collision between two different folders still refuses. Seats compare
 * case-insensitively in the recipient checks, so `domain:language` may act on an ask addressed to
 * `domain:Language`.
 *
 * Two roots: a plain temp directory (case-insensitive on a default macOS volume; elsewhere the alias
 * is simulated with a symlink), and a case-insensitive APFS disk image made with hdiutil (skipped,
 * with a message, where hdiutil is unavailable or fails). ASKCASE_SCRATCH sets where the image is made.
 */
import { afterAll, beforeAll, beforeEach, afterEach, describe, expect, it } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { actedAsk, answerAsk, forwardAsk, newAsk, readAsk, renameSeat } from "../src/lib/store.ts";
import { parseAskFile, setHeaderField, writeAnswer } from "../src/lib/format.ts";

const BODY = "## ¶ASK_GO: Choose one: Ship it?\n- [ ] [YES] Yes\n- [ ] [NO] No\n";
const UP = "domain:Language";
const LOW = "domain:language";
const MGR = "manager:domain";
const OP = { by: "operator" };
const push = async () => ({ status: "delivered" as const });
const AT = "2026-10-30T00:00:00.000Z";

/** Every ask file under the root with its bytes: what a dry run must leave as it was. */
function snapshot(root: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const seat of fs.readdirSync(root).filter((d) => !d.startsWith("."))) {
    for (const f of fs.readdirSync(path.join(root, seat))) out[`${seat}/${f}`] = fs.readFileSync(path.join(root, seat, f), "utf8");
  }
  return out;
}

/**
 * l1 is domain:Language's own ask (moves with the folder); w1 is addressed to it and answered by it;
 * w2 was answered by it and then overruled by the operator (a history fence and an overruled stamp);
 * w3 was forwarded to it by its manager.
 */
async function fleet(root: string) {
  newAsk(root, { from: UP, to: MGR, id: "l1", related: `${UP}/l0` }, BODY);
  newAsk(root, { from: "app:writer", to: UP, id: "w1", context: `see ${UP}/l1` }, BODY);
  await answerAsk(root, "app:writer", "w1", { answers: { GO: ["YES"] }, answeredBy: UP }, { expectedRevision: 1, push });
  newAsk(root, { from: "app:writer", to: UP, id: "w2" }, BODY);
  const f2 = path.join(root, "app:writer", "w2.md");
  const t1 = writeAnswer(fs.readFileSync(f2, "utf8"), { answers: { GO: ["YES"] }, answeredBy: UP, answeredVia: "cli", answeredAt: AT }, 1);
  const t2 = writeAnswer(t1, { answers: { GO: ["NO"] }, answeredBy: "operator", answeredVia: `relay:${MGR}`, answeredAt: AT }, 2);
  fs.writeFileSync(f2, setHeaderField(t2, "overruled", UP));
  newAsk(root, { from: "app:writer", to: MGR, id: "w3" }, BODY);
  await forwardAsk(root, "app:writer", "w3", { to: UP, by: MGR });
}

const read = (root: string, seat: string, id: string) => parseAskFile(fs.readFileSync(path.join(root, seat, `${id}.md`), "utf8"));
const seatsOnDisk = (root: string) => fs.readdirSync(root).filter((d) => !d.startsWith("."));

/** The cases, run against a root on a case-insensitive volume (or one that simulates it). */
function cases(rootOf: () => string, prepare: (root: string) => void = () => {}) {
  it("a case-only rename moves the folder through staging and rewrites every seat field", async () => {
    const root = rootOf();
    await fleet(root);
    prepare(root);
    const r = await renameSeat(root, UP, LOW, OP);
    expect(r.folder.mode).toBe("move");
    expect(r.moved).toBe(1);
    // The folder's own name follows, case and all.
    expect(seatsOnDisk(root)).toContain(LOW);
    expect(seatsOnDisk(root)).not.toContain(UP);
    expect(read(root, LOW, "l1").header.from).toBe(LOW);
    expect(read(root, LOW, "l1").header.related).toBe(`${LOW}/l0`);
    const w1 = read(root, "app:writer", "w1");
    expect(w1.header.to).toBe(LOW);
    expect(w1.header.context).toBe(`see ${LOW}/l1`);
    expect(w1.answer?.answeredBy).toBe(LOW);
    const w2 = read(root, "app:writer", "w2");
    expect((w2.history[0] as Record<string, unknown>).answeredBy).toBe(LOW);
    expect(w2.header.overruled).toBe(LOW);
    expect(read(root, "app:writer", "w3").header.forwards).toContain(`${MGR}→${LOW}@`);
    for (const t of Object.values(snapshot(root))) expect(t).not.toContain(UP);
    // The ledger survives: on this volume the old and new ledger are one file.
    expect(fs.readFileSync(path.join(root, ".rename-seat", UP), "utf8").split("\n")[0]).toBe(LOW);
    // A second pass moves and changes nothing.
    const again = await renameSeat(root, UP, LOW, OP);
    expect(again.changes).toEqual([]);
  });

  it("a dry run reports the move and the counts, and changes nothing", async () => {
    const root = rootOf();
    await fleet(root);
    prepare(root);
    const before = snapshot(root);
    const r = await renameSeat(root, UP, LOW, { dryRun: true });
    expect(r.folder).toMatchObject({ mode: "move", ids: ["l1"] });
    expect([...new Set(r.files)].sort()).toEqual(["app:writer/w1.md", "app:writer/w2.md", "app:writer/w3.md", `${UP}/l1.md`]);
    expect(r.changes.map((c) => c.field)).toEqual(expect.arrayContaining(["from", "to", "related", "context", "answer.answeredBy", "history.answeredBy", "overruled", "replaced", "forwards"]));
    expect(snapshot(root)).toEqual(before);
    expect(seatsOnDisk(root)).toContain(UP);
  });

  it("a real collision with a different folder still refuses", async () => {
    const root = rootOf();
    newAsk(root, { from: UP, to: MGR, id: "x1" }, BODY);
    newAsk(root, { from: "domain:Lang", to: MGR, id: "x1" }, BODY);
    prepare(root);
    const before = snapshot(root);
    await expect(renameSeat(root, "domain:Lang", LOW, OP)).rejects.toThrow(`${LOW}/x1 already exists; nothing was changed`);
    expect(snapshot(root)).toEqual(before);
  });

  it("acted works for domain:language on an ask addressed domain:Language, and on its own ask filed as domain:Language", async () => {
    const root = rootOf();
    newAsk(root, { from: "app:writer", to: UP, id: "a1" }, BODY);
    await answerAsk(root, "app:writer", "a1", { answers: { GO: ["YES"] }, answeredBy: UP }, { expectedRevision: 1, push });
    await actedAsk(root, "app:writer", "a1", "shipped it", { by: LOW });
    const a1 = read(root, "app:writer", "a1");
    expect(a1.header.actedBy).toBe(LOW);
    // Stored names stay as written.
    expect(a1.header.to).toBe(UP);

    newAsk(root, { from: UP, to: MGR, id: "a2" }, BODY);
    await answerAsk(root, UP, "a2", { answers: { GO: ["NO"] }, answeredBy: MGR }, { expectedRevision: 1, push });
    const r = await readAsk(root, UP, "a2", { by: LOW });
    expect(r.why).toBeUndefined();
    await actedAsk(root, UP, "a2", "held it", { by: LOW });
    expect(read(root, UP, "a2").header.actedBy).toBe(LOW);
    // A stranger is still refused.
    await expect(actedAsk(root, UP, "a2", "x", { by: "domain:stranger" })).rejects.toThrow("not a recipient");
  });
}

describe("ASKCASE: a plain directory (case-insensitive here, or simulated with a symlink)", () => {
  let base: string;
  beforeEach(() => {
    base = fs.mkdtempSync(path.join(os.tmpdir(), "askcase-"));
  });
  afterEach(() => fs.rmSync(base, { recursive: true, force: true }));
  /** On a case-sensitive volume, make `domain:language` the same folder as `domain:Language`. */
  const alias = (root: string) => {
    const up = path.join(root, UP);
    const low = path.join(root, LOW);
    if (fs.existsSync(up) && !fs.existsSync(low)) fs.symlinkSync(UP, low);
  };
  cases(() => path.join(base, "asks"), alias);
});

/** Make and attach a case-insensitive APFS image; undefined (with the reason) where that cannot be done. */
function attachImage(): { mount: string; dmg: string } | string {
  if (process.platform !== "darwin") return "hdiutil needs macOS";
  if (spawnSync("which", ["hdiutil"]).status !== 0) return "hdiutil is unavailable";
  const scratch = fs.mkdtempSync(path.join(process.env.ASKCASE_SCRATCH ?? os.tmpdir(), "askcase-"));
  const dmg = path.join(scratch, "ci.dmg");
  const mount = path.join(scratch, "mnt");
  fs.mkdirSync(mount);
  // `-fs APFS` is case-insensitive by default, and beforeAll probes that it is. The name "Case-insensitive
  // APFS" was refused (Invalid argument) or hung on this hdiutil, so it is not asked for; every call
  // is bounded, so a stuck hdiutil skips the cases instead of hanging the suite.
  const run = (args: string[]) => spawnSync("hdiutil", args, { encoding: "utf8", timeout: 60_000 });
  const made = run(["create", "-size", "20m", "-fs", "APFS", "-volname", "askcase", dmg]);
  if (made.status !== 0) return `hdiutil create failed: ${(made.stderr || String(made.error ?? made.signal)).trim()}`;
  const att = run(["attach", dmg, "-mountpoint", mount, "-nobrowse"]);
  if (att.status !== 0) return `hdiutil attach failed: ${(att.stderr || String(att.error ?? att.signal)).trim()}`;
  return { mount, dmg };
}

const image = attachImage();
if (typeof image === "string") console.warn(`ASKCASE: skipping the disk-image cases: ${image}`);

describe.skipIf(typeof image === "string")("ASKCASE: a case-insensitive APFS disk image", () => {
  const img = image as { mount: string; dmg: string };
  let n = 0;
  let root: string;
  beforeAll(() => {
    // The volume really is case-insensitive: two spellings, one folder.
    fs.mkdirSync(path.join(img.mount, "Probe"));
    expect(fs.existsSync(path.join(img.mount, "probe"))).toBe(true);
  });
  beforeEach(() => {
    root = path.join(img.mount, `asks${n++}`);
  });
  afterAll(() => {
    spawnSync("hdiutil", ["detach", img.mount, "-force"], { timeout: 60_000 });
    fs.rmSync(path.dirname(img.dmg), { recursive: true, force: true });
  });
  cases(() => root);
});
