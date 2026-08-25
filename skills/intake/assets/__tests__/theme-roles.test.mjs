/* Teeth for the theme token ROLE CONTRACT (theme-roles.json + theme-roles.mjs).
 *
 * The contract file is a set of CLAIMS about four real files. This proves the gate that checks
 * those claims can actually FAIL — the session has now shipped two gates that could not, and
 * neither was detectable by running them. So the shape here is deliberately hostile:
 *
 *   A) a candidate theme MISSING a required role is REJECTED, and the rejection names the role
 *   B) the same candidate, complete, is ACCEPTED (exit 0)
 *   C) a role declared with an EMPTY VALUE does NOT count as satisfied — `--x: ;` is legal CSS
 *      that resolves to nothing, i.e. a declaration that renders as an absence
 *   D) a GRADED theme that loses a recorded token is caught as DRIFT (a different exit code —
 *      a stale contract makes every other number in the run untrustworthy)
 *   E) the anti-taste guard has its own negative control: a contract that grades a role by
 *      something other than the declared mechanical rule is REJECTED. Without this, the
 *      "tiers are recomputed, not declared" claim is an unchecked promise.
 *   F) the extractor reproduces the independent census oracle on the four real frozen files
 *
 * A/B/C/D/E drive the REAL gate against a CRAFTED minimal contract + fixtures (mirroring
 * proof-gates.test.mjs), which isolates the mechanism from today's real-world result — the real
 * run legitimately exits 1 because the kit is missing 6 required roles, so it cannot serve as the
 * acceptance case. F and G read the REAL spec so this test tracks it instead of drifting from it.
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/__tests__/theme-roles.test.mjs
 */
import assert from "node:assert";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const ASSETS = path.join(here, "..");
const GATE = path.join(ASSETS, "theme-roles.mjs");
const { declaredProps, tierOf, canonicalByOf, channelAnswers, channelContract, edgeDraws } = await import(GATE);

let checks = 0;
const check = (msg, fn) => { fn(); checks++; };

const root = fs.mkdtempSync(path.join(os.tmpdir(), "theme-roles-"));
const w = (name, body) => { const p = path.join(root, name); fs.writeFileSync(p, body); return p; };

/* ── the crafted minimal contract ─────────────────────────────────────────────
 * 3 roles, all kit-incumbent so the crafted kit can legitimately be complete.
 * `beta` is spelled differently by theme a, to keep an alias in play. */
const CONTRACT = {
  version: 0,
  measuredAgainst: "crafted fixture",
  mandates: [{ id: "M_TEST", statement: "test mandate", satisfiedByAnyOf: ["gamma"] }],
  roles: [
    { id: "alpha", what: "a", channel: "colour", canonical: "--alpha", canonicalBy: "kit-incumbent",
      kit: "--alpha", spellings: { a: "--alpha", b: "--alpha", c: "--alpha" } },
    { id: "beta", what: "b", channel: "colour", canonical: "--beta", canonicalBy: "kit-incumbent",
      kit: "--beta", spellings: { a: "--b2", b: "--beta", c: "--beta" } },
    { id: "gamma", what: "g", channel: "texture", canonical: "--gamma", canonicalBy: "kit-incumbent",
      kit: "--gamma", spellings: { a: "--gamma", b: null, c: "--gamma" } },
  ],
};
const contractPath = w("contract.json", JSON.stringify(CONTRACT));

const kit = w("kit.css", ":root{--alpha:#111;--beta:#222;--gamma:4px}");
const themeA = w("a.css", ":root{--alpha:#111;--b2:#222;--gamma:4px}");
const themeB = w("b.css", ":root{--alpha:#111;--beta:#222}");
const themeC = w("c.css", ":root{--alpha:#111;--beta:#222;--gamma:4px}");

/* `d` is a CANDIDATE theme: present in the source map but neither graded nor the incumbent, so it
 * gets no drift checks. That isolates the COMPLIANCE exit path from the DRIFT exit path — without
 * it, every crafted failure would trip drift first and the compliance teeth would be untested. */
const sourcesFor = (dPath) => w(`sources-${path.basename(dPath)}.json`, JSON.stringify({
  sources: { kit, a: themeA, b: themeB, c: themeC, ...(dPath ? { d: dPath } : {}) },
  prefix: {}, incumbent: "kit", graded: ["a", "b", "c"],
}));

const run = (sourcesPath, contract = contractPath) =>
  spawnSync(process.execPath, [GATE, "--sources", sourcesPath, "--contract", contract], { encoding: "utf8" });

/* A) A candidate theme with no --beta at all cannot pass. */
check("A: candidate MISSING a required role is REJECTED and the role is named", () => {
  const d = w("d-missing.css", ":root{--alpha:#111;--gamma:4px}");
  const r = run(sourcesFor(d));
  assert.strictEqual(r.status, 1, `expected compliance exit 1, got ${r.status}\n${r.stdout}${r.stderr}`);
  assert.ok(/GAP\s+beta\b/.test(r.stdout), `rejection must name the missing role\n${r.stdout}`);
  assert.ok(r.stdout.includes("d/beta"), `verdict must name file/role\n${r.stdout}`);
  assert.ok(/DRIFT[\s\S]*?OK —/.test(r.stdout), `must NOT be a drift failure — this is the compliance path\n${r.stdout}`);
});

/* B) The same candidate, complete, is accepted. Proves A failed for the reason claimed. */
check("B: a complete candidate is ACCEPTED (exit 0)", () => {
  const d = w("d-complete.css", ":root{--alpha:#111;--beta:#222;--gamma:4px}");
  const r = run(sourcesFor(d));
  assert.strictEqual(r.status, 0, `expected exit 0, got ${r.status}\n${r.stdout}${r.stderr}`);
  assert.ok(r.stdout.includes("VERDICT: PASS"), r.stdout);
  assert.ok(/d\s+INV|d\s+M_TEST/.test(r.stdout) || r.stdout.includes("M_TEST"), "mandates reported");
});

/* C) A declared-but-empty value is not a satisfied role. `--beta: ;` resolves to nothing. */
check("C: a role declared with an EMPTY VALUE does not satisfy it", () => {
  const d = w("d-blank.css", ":root{--alpha:#111;--beta: ;--gamma:4px}");
  const r = run(sourcesFor(d));
  assert.strictEqual(r.status, 1, `blank value must not satisfy the role, got exit ${r.status}\n${r.stdout}`);
  assert.ok(r.stdout.includes("d/beta"), r.stdout);
  // and the unit-level oracle, so this is not resting on the CLI's formatting alone
  assert.ok(!declaredProps("--x: ;").has("--x"), "blank value must not count as declared");
  assert.ok(!declaredProps("--x:;").has("--x"), "blank value (no space) must not count as declared");
  assert.ok(declaredProps("--x:0;").has("--x"), "a real zero IS a value and must count");
  assert.ok(declaredProps("--y:red}").has("--y"), "last declaration in a block, no semicolon, counts");
});

/* D) A GRADED theme losing a recorded token is DRIFT, not merely non-compliance — different exit,
 *    because a contract whose recorded observations are false poisons every other number. */
check("D: a graded theme that loses a recorded token is caught as DRIFT (exit 2)", () => {
  const broken = w("c-broken.css", ":root{--alpha:#111;--gamma:4px}");
  const s = w("sources-drift.json", JSON.stringify({
    sources: { kit, a: themeA, b: themeB, c: broken }, prefix: {}, incumbent: "kit", graded: ["a", "b", "c"],
  }));
  const r = run(s);
  assert.strictEqual(r.status, 2, `expected drift exit 2, got ${r.status}\n${r.stdout}`);
  assert.ok(r.stdout.includes("c/beta: contract records --beta"), r.stdout);
});

/* E) Negative control for the ANTI-TASTE GUARD itself. The contract's authority rests on tiers and
 *    canonical names being recomputed from the evidence — so prove the recomputation rejects a
 *    contract that grades a role by anything else. */
check("E: a contract that mis-grades a role is REJECTED by the self-check (exit 2)", () => {
  const bad = JSON.parse(JSON.stringify(CONTRACT));
  // one theme built it, but the contract claims two agreed on the name
  bad.roles.push({ id: "delta", what: "d", channel: "colour", canonical: "--delta",
    canonicalBy: "theme-consensus", kit: null, spellings: { a: "--delta", b: null, c: null } });
  const badPath = w("contract-bad.json", JSON.stringify(bad));
  const r = run(sourcesFor(w("d-complete2.css", ":root{--alpha:#111;--beta:#222;--gamma:4px}")), badPath);
  assert.strictEqual(r.status, 2, `mis-graded contract must be rejected, got ${r.status}\n${r.stdout}`);
  assert.ok(/delta: canonicalBy is "theme-consensus", evidence says "sole-author"/.test(r.stdout), r.stdout);
  // and the pure function agrees, independent of the CLI
  assert.strictEqual(canonicalByOf(bad.roles[3], ["a", "b", "c"]), "sole-author");
  assert.strictEqual(tierOf(1), "proposed");
  assert.strictEqual(tierOf(2), "emerging");
  assert.strictEqual(tierOf(3), "required");
});

/* F) The extractor vs the independent census oracle, on the four REAL frozen files. Every claim in
 *    the contract rests on this extraction; the four numbers were produced by a separate Python
 *    pass over the same files with the same regex. Pinned on purpose — an external oracle is the
 *    one thing this test is allowed to hardcode. */
check("F: extractor reproduces the independent census oracle 4/4", () => {
  const sources = JSON.parse(fs.readFileSync(path.join(ASSETS, "theme-roles.sources.json"), "utf8"));
  // The three themes are byte-copies and never move. `kit` is the LIVE proof-theme.css, so it
  // legitimately climbs when the kit gains tokens: 74 -> 84 when the 10 --chan-* role slots landed,
  // 84 -> 85 when --focus landed (the focus-ring role's canonical name, agreed 3/3 by the themes).
  // Re-derived by a separate Python pass over the same files, same stated rule, not by editing
  // this number until the test went green.
  const ORACLE = { nerv: 45, akira: 47, wire: 82, kit: 85 };
  const exp = (p) => (p.startsWith("~/") ? path.join(os.homedir(), p.slice(2)) : p);
  for (const [name, want] of Object.entries(ORACLE)) {
    const got = declaredProps(fs.readFileSync(exp(sources.frozen[name]), "utf8")).size;
    assert.strictEqual(got, want, `${name}: extractor says ${got}, oracle says ${want}`);
  }
});

/* G) Spec-tracking: read the REAL contract and assert its shape + that today's honest result is the
 *    one recorded. If someone fills the kit's gaps, this goes red and the contract gets updated —
 *    which is the point. Nothing here is hardcoded except the count that IS the finding. */
check("G: the real contract is self-consistent and the incumbent still fails it", () => {
  const contract = JSON.parse(fs.readFileSync(path.join(ASSETS, "theme-roles.json"), "utf8"));
  const graded = JSON.parse(fs.readFileSync(path.join(ASSETS, "theme-roles.sources.json"), "utf8")).graded;
  assert.ok(contract.roles.length >= 20, "the contract has a meaningful number of roles");
  for (const role of contract.roles) {
    assert.strictEqual(role.canonicalBy, canonicalByOf(role, graded), `${role.id} canonicalBy`);
    assert.ok(role.what && role.channel, `${role.id} has what+channel`);
    // no role may be graded required unless three themes actually built one
    const ev = graded.filter((t) => role.spellings[t]).length;
    if (tierOf(ev) === "required") assert.strictEqual(ev, 3, `${role.id} required with ${ev} evidence`);
  }
  const r = spawnSync(process.execPath, [GATE, "--frozen"], { encoding: "utf8" });
  assert.strictEqual(r.status, 1, `real frozen run should fail on required-role gaps, got ${r.status}\n${r.stdout}`);
  assert.ok(/kit\s+INV_DS_NON_COLOUR_CHANNEL\s+NOT MET/.test(r.stdout), "kit fails the non-colour mandate");
  assert.ok(/kit\s+INV_DS_MISSING_NOT_EMPTY\s+NOT MET/.test(r.stdout), "kit fails the missing-not-empty mandate");
  // focus-ring is CLOSED — the kit declares --focus, the one required role whose name three themes
  // had already agreed on, so no human ruling was needed to close it. The still-open gaps are the
  // five whose NAME is a ruling nobody has made; `absence` stands for them here because
  // INV_DS_MISSING_NOT_EMPTY above depends on it, so the two assertions cannot drift apart.
  assert.ok(!/GAP\s+focus-ring/.test(r.stdout), "focus-ring is no longer a gap — the kit declares --focus");
  assert.ok(/GAP\s+absence/.test(r.stdout), "the name-undecided gaps are still reported");
  const rr = spawnSync(process.execPath, [GATE, "--frozen", "--report-only"], { encoding: "utf8" });
  assert.strictEqual(rr.status, 0, "--report-only downgrades to exit 0");
});

/* H) INV_DS_NON_COLOUR_CHANNEL measured at the role seam. Same hostile shape as A/B: prove the
 *    check REJECTS a hue-only answer and ACCEPTS the same answer once it carries a shape. Without
 *    the accept case this would be an always-fail assertion dressed up as a gate — which is the
 *    exact failure mode the header of this file says the session has already shipped twice. */
check("H: a hue-only channel answer is REJECTED; the same answer with a shape is ACCEPTED", () => {
  const complete = ":root{--alpha:#111;--beta:#222;--gamma:4px;";
  const hueOnly = w("d-hue-only.css", complete + "--chan-z-ink:#999;--chan-z-edge:0 none currentColor}");
  const r = run(sourcesFor(hueOnly));
  assert.strictEqual(r.status, 1, `hue-only answer must fail, got ${r.status}\n${r.stdout}`);
  assert.ok(/HUE-ONLY\s+chan-z/.test(r.stdout), `must name the hue-only role\n${r.stdout}`);
  assert.ok(r.stdout.includes("d/chan-z"), `verdict must name file/role\n${r.stdout}`);
  assert.ok(/DRIFT[\s\S]*?OK —/.test(r.stdout), `must not be a drift failure\n${r.stdout}`);

  const withShape = w("d-with-shape.css", complete + "--chan-z-ink:#999;--chan-z-edge:2px dashed currentColor}");
  const ok = run(sourcesFor(withShape));
  assert.strictEqual(ok.status, 0, `a shape answer must pass, got ${ok.status}\n${ok.stdout}`);
  assert.ok(/1 role\(s\) answered ·  1 survive greyscale/.test(ok.stdout), ok.stdout);

  // a file that never opts into the seam is n/a, not failed
  const none = run(sourcesFor(w("d-no-slots.css", complete + "}")));
  assert.strictEqual(none.status, 0, `no --chan-* slots must be n/a, got ${none.status}\n${none.stdout}`);
  assert.ok(/d\s+n\/a — declares no --chan-\* role slots/.test(none.stdout), none.stdout);

  // and the pure functions, independent of the CLI
  assert.strictEqual(edgeDraws("0 none currentColor"), false, "the kit's decline value draws nothing");
  assert.strictEqual(edgeDraws("0px solid red"), false, "a zero-width border draws nothing");
  assert.strictEqual(edgeDraws("2px dashed currentColor"), true);
  assert.strictEqual(edgeDraws("0.5px solid red"), true, "0.5px is not a zero");
  assert.strictEqual(channelAnswers(":root{--chan-z-edge: ;}").size, 0, "a blank slot is not an answer");
  assert.strictEqual(channelContract(":root{--ink:#111}").length, 0, "no slots => nothing to check");
});

/* I) The REAL kit is measured by this check — the finding, pinned. Exactly ONE role answers with a
 *    shape today: `z`, because --ink-faint measures 2.58:1 light / 3.62:1 dark and so fails AA body
 *    text in both themes, which is where a non-colour channel does real work rather than decoration.
 *    `a` and `g` keep the decline value pending a human ruling. Pinning the SPLIT rather than "all
 *    hue-only" is what keeps this honest in both directions: it fails if the seam regresses to
 *    hue-only AND if someone quietly answers the two roles that are still a ruling. */
check("I: the live kit answers exactly one channel role with a shape (z), the other two with hue alone", () => {
  const rows = channelContract(fs.readFileSync(path.join(ASSETS, "proof-theme.css"), "utf8"));
  assert.deepStrictEqual(rows.map((r) => r.role), ["a", "g", "z"], "three channel roles are answered");
  assert.deepStrictEqual(rows.filter((r) => r.survives).map((r) => r.role), ["z"], "only z survives greyscale");
  for (const r of rows.filter((r) => !r.survives))
    assert.strictEqual(r.edge, "0 none currentColor", `${r.role} still carries the exact decline value`);
});

fs.rmSync(root, { recursive: true, force: true });
console.log(`theme-roles.test: PASS — ${checks} gate checks `
  + `(A missing-role REJECTED · B complete ACCEPTED · C blank value NOT satisfied · `
  + `D drift caught separately · E mis-graded contract rejected · F census oracle 4/4 · G real spec tracked · `
  + `H hue-only channel REJECTED + shape ACCEPTED + no-slots n/a · I live kit answers z with a shape, a+g hue-only)`);
