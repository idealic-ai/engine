/* Drift gate + extraction-fidelity checks for kit-digest.mjs.
 *
 * A generated digest is only trustworthy if going stale is a GATE FAILURE rather than silent rot.
 * The committed KIT_DIGEST*.md are what an agent actually loads; if a source gallery changes and
 * nobody re-runs the generator, the agent reads a rule the kit no longer holds and never learns it
 * was reading history. So the spine of this file is one check: regenerate → byte-identical.
 *
 * Around that spine sit checks that do NOT simply trust the generator. The parse signature is
 * recomputed here from the raw HTML, independently of the script, because a parser and its own
 * self-check agreeing proves nothing. And the two failure modes the digest exists to prevent —
 * a contract shipping with a clause missing, and an unreachable pattern shipping as if reachable —
 * are asserted against the emitted markdown, not against the parser's intermediate objects.
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/__tests__/kit-digest.test.mjs
 */
import assert from "node:assert";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const intake = path.join(here, "..");
const script = path.join(intake, "kit-digest.mjs");
const read = (p) => fs.readFileSync(p, "utf8");

const OUTPUTS = ["KIT_DIGEST.md", "KIT_DIGEST_RECIPES.md", "KIT_DIGEST_MARKUP.md"];
const digest = read(path.join(intake, "KIT_DIGEST.md"));
const recipesDoc = read(path.join(intake, "KIT_DIGEST_RECIPES.md"));
const markupDoc = read(path.join(intake, "KIT_DIGEST_MARKUP.md"));

const manifest = JSON.parse(read(path.join(intake, "kit-digest.sources.json")));
const expand = (p) => (p.startsWith("~/") ? path.join(os.homedir(), p.slice(2)) : p);
const sourcePaths = Object.fromEntries(
  Object.entries(manifest.sources).map(([k, v]) => [k, expand(v)]));

let checks = 0;
const check = (msg, fn) => { fn(); checks++; };

/* Sources living outside the kit is the normal state today — the contract-bearing pages have not
   been promoted yet. A missing one is drift in its own right (the manifest stopped describing
   reality), so it fails loudly with the remediation rather than skipping. */
const missing = Object.entries(sourcePaths).filter(([, p]) => !fs.existsSync(p)).map(([k]) => k);
assert.deepStrictEqual(missing, [],
  `kit-digest sources are unreachable: ${missing.join(", ")}. The committed digest cannot be `
  + `re-derived, so it cannot be trusted. If a page moved (promotion into the kit), update `
  + `kit-digest.sources.json and re-run: node ${script}`);

const src = Object.fromEntries(Object.entries(sourcePaths).map(([k, p]) => [k, read(p)]));
const bodyOf = (h) => h
  .replace(/<style[\s\S]*?<\/style>/gi, "")
  .replace(/<script[\s\S]*?<\/script>/gi, "")
  .replace(/<svg[\s\S]*?<\/svg>/gi, "");
const countExact = (h, attr) => (bodyOf(h).match(new RegExp(`class=["']${attr}["']`, "g")) || []).length;

/* ---- 1. THE DRIFT GATE — the whole reason a generated digest is trustworthy ---- */

check("regenerate → byte-identical to every committed output", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "kit-digest-"));
  try {
    execFileSync(process.execPath, [script, "--out", path.join(tmp, "KIT_DIGEST.md")],
      { stdio: ["ignore", "pipe", "pipe"] });
    for (const name of OUTPUTS) {
      const fresh = read(path.join(tmp, name));
      const committed = read(path.join(intake, name));
      if (fresh === committed) continue;
      const i = [...fresh].findIndex((c, k) => c !== committed[k]);
      assert.fail(
        `${name} is STALE — a fresh extraction differs at byte ${i}.\n`
        + `  committed:   ${JSON.stringify(committed.slice(Math.max(0, i - 60), i + 80))}\n`
        + `  regenerated: ${JSON.stringify(fresh.slice(Math.max(0, i - 60), i + 80))}\n`
        + `  Regenerate:  node ${script}`);
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

check("--check agrees with the committed outputs", () => {
  const out = execFileSync(process.execPath, [script, "--check"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  assert.match(out, /check PASS/, "the script's own drift mode disagrees with the committed files");
});

/* ---- 2. THE PARSE SIGNATURE, recomputed here rather than taken on trust ----
   preconditions.html carries ct-n ×46 and cl unl ×40, and the 40-against-46 gap is EXACTLY the six
   unreachable patterns carrying blocked-by instead of unlocks. That relation is what makes the
   parse self-verifying: any other numbers mean the parse is wrong, not that the page grew. */

check("preconditions signature: 46 entries, 40 unlocks + 6 blocked-by = 46", () => {
  const h = src.preconditions;
  const n = (c) => countExact(h, c);
  assert.strictEqual(n("ct-n"), 46, "ct-n count moved");
  assert.strictEqual(n("ct-cls"), 46, "ct-cls count moved");
  assert.strictEqual(n("cl req"), 46, "cl req count moved");
  assert.strictEqual(n("cl exc"), 46, "cl exc count moved");
  assert.strictEqual(n("cl deg"), 46, "cl deg count moved");
  assert.strictEqual(n("cl unl"), 40, "cl unl count moved");
  assert.strictEqual(n("cl blk"), 6, "cl blk count moved");
  assert.strictEqual(n("cl unl") + n("cl blk"), n("ct-n"),
    "the unlocks/blocked-by split no longer accounts for every entry — the parse would silently "
    + "drop or duplicate a contract");
});

check("recipes signature: 6 recipes × 2 panels", () => {
  const h = src.recipes;
  assert.strictEqual(countExact(h, "rc-when"), 6);
  assert.strictEqual(countExact(h, "rc-sig"), 6);
  assert.strictEqual(countExact(h, "rc-siglab"), 6);
  assert.strictEqual(countExact(h, "rc-panel"), 12, "two panels per recipe");
  assert.strictEqual(countExact(h, "rc-n"), 12);
  assert.strictEqual(countExact(h, "rc-lead"), 12);
});

check("openers signature: 5 hero forms, four clauses each", () => {
  const h = src.openers;
  assert.strictEqual(countExact(h, "brief"), 5);
  for (const k of ["bk req", "bk cmp", "bk exc", "bk deg"]) assert.strictEqual(countExact(h, k), 5, `${k} moved`);
});

check("the digest reports exactly the counts the sources carry", () => {
  assert.match(digest, /\| `preconditions\.html` \| `[0-9a-f]{12}` \| 45 contracts \|/);
  assert.match(digest, /\| `recipes\.html` \| `[0-9a-f]{12}` \| 6 recipes \|/);
  assert.match(digest, /\| `openers\.html` \| `[0-9a-f]{12}` \| 5 hero forms \(§4 only\) \|/);
  assert.match(digest, /\| `PROOF_BLOCKS\.html` \| `[0-9a-f]{12}` \| 20 blocks \+ 19 picker rows \|/);
  assert.match(digest, /\| `CREATIVE_LAYOUTS\.html` \| `[0-9a-f]{12}` \| 25 captions \+ 25 picker rows \|/);
});

check("45 emitted contracts = 46 markup entries minus the one §02 teaching specimen", () => {
  const heads = digest.match(/^### .+$/gm) || [];
  const contracts = digest
    .split(/^## /m)
    .filter((s) => /^\d\d · the contracts/.test(s))
    .reduce((n, s) => n + (s.match(/^### /gm) || []).length, 0);
  assert.strictEqual(contracts, 45,
    `expected 45 contracts (46 .ct-n minus the .spec demo in §02); the digest has ${contracts}`);
  assert.ok(heads.length > contracts, "the digest lost its non-contract sections");
});

/* ---- 3. THE TWO THINGS THAT MUST SURVIVE EXTRACTION ---- */

check("every contract carries all four clauses — a truncated rule is obeyed silently", () => {
  const bad = [];
  for (const sec of digest.split(/^## /m).filter((s) => /^\d\d · the contracts/.test(s))) {
    for (const entry of sec.split(/^### /m).slice(1)) {
      const name = entry.split("\n")[0].trim();
      const has = (k) => new RegExp(`^- \\*\\*${k}\\*\\* — \\S`, "m").test(entry);
      const miss = [];
      if (!has("requires")) miss.push("requires");
      if (!has("excludes")) miss.push("excludes");
      if (!has("degrades to")) miss.push("degrades to");
      if (!has("unlocks") && !has("blocked-by")) miss.push("unlocks|blocked-by");
      if (miss.length) bad.push(`${name}: ${miss.join(", ")}`);
    }
  }
  assert.deepStrictEqual(bad, [],
    `contract(s) emitted with a clause missing — an agent obeys a truncated rule without knowing `
    + `it was truncated:\n    ${bad.join("\n    ")}`);
});

check("all six unreachable patterns survive, each with its blocker", () => {
  const BLOCKED = ["Confidence band", "Callout-pins overlay", "Leader-line margin annotations",
    "Highlighted crop + zoom", "Spec-rail annotated exhibit", "figure"];
  const idx = digest.split(/^## /m).find((s) => /^Unreachable today — 6/.test(s));
  assert.ok(idx, "the unreachable index is gone — an agent will reach for a pattern nothing can fill");
  for (const name of BLOCKED) {
    assert.ok(idx.includes(`**${name}**`), `${name} dropped from the unreachable index`);
  }
  const blockedRows = (idx.match(/^- \*\*.+\*\* — `.+` — blocked-by: \S/gm) || []).length;
  assert.strictEqual(blockedRows, 6, "an unreachable row lost its blocked-by clause");
  /* and each one keeps its blocked-by inside its own contract entry too */
  for (const name of BLOCKED) {
    const entry = digest.split(/^### /m).find((s) => s.startsWith(name + "\n"));
    assert.ok(entry, `${name} has no contract entry`);
    assert.match(entry, /^- \*\*blocked-by\*\* — \S/m, `${name} lost its blocked-by clause`);
    assert.ok(!/^- \*\*unlocks\*\*/m.test(entry), `${name} emitted an unlocks clause it does not have`);
    assert.ok(entry.includes("**UNREACHABLE TODAY**"), `${name} is not flagged as unreachable`);
  }
});

check("the deliberately partial `sequence` contract is kept, not dropped as malformed", () => {
  const entry = digest.split(/^### /m).find((s) => s.startsWith("sequence\n"));
  assert.ok(entry, "the sequence contract was dropped");
  assert.match(entry, /^- \*\*degrades to\*\* — A `<ul>`\./m,
    "sequence ships a one-token degrades-to on purpose; it must survive, thin, not be discarded");
});

/* ---- 4. THE EMIT SIDE — [RECIPE]'s same-bytes guarantee, checked rather than believed ---- */

check("each recipe's lifted markup is byte-identical to its rendered specimen", () => {
  const h = bodyOf(src.recipes);
  const sliceEl = (s, i) => {
    const m = /^<([a-zA-Z][-\w]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/.exec(s.slice(i));
    const tag = m[1], openEnd = i + m[0].length;
    const scan = new RegExp(`</?${tag}\\b`, "gi");
    scan.lastIndex = openEnd;
    let depth = 1, mm;
    while ((mm = scan.exec(s))) {
      if (s[mm.index + 1] === "/") { if (--depth === 0) return s.slice(openEnd, mm.index); }
      else depth++;
    }
    return null;
  };
  const unesc = (t) => t.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'").replace(/&amp;/g, "&");
  /* .specimen is overloaded — 10 on the page, only 6 belong to recipes — so the reliable anchor is
     .lift-body, and each recipe's specimen is the LAST .block before it. */
  const lifts = [...h.matchAll(/<div class="lift-body">/g)].map((m) => m.index);
  assert.strictEqual(lifts.length, 6, "recipe count moved");
  for (const [n, at] of lifts.entries()) {
    const blockAt = h.lastIndexOf('<div class="block">', at);
    const rendered = sliceEl(h, blockAt).trim();
    const pre = /<pre[^>]*>([\s\S]*?)<\/pre\s*>/i.exec(sliceEl(h, at))[1];
    const lifted = unesc(pre.replace(/<[^>]*>/g, "")).trim();
    assert.strictEqual(lifted, rendered,
      `recipe ${n + 1}: the copyable <pre> and the rendered specimen are NOT the same bytes — the `
      + `guarantee the markup file repeats no longer holds`);
  }
});

check("every recipe and opener reaches the markup file with a fenced block", () => {
  const fences = (markupDoc.match(/^```html$/gm) || []).length;
  assert.strictEqual(fences, 11, "6 recipes + 5 openers should each carry exactly one html fence");
  assert.strictEqual((markupDoc.match(/^```$/gm) || []).length, 11, "unclosed fence in the markup file");
  for (const n of [1, 2, 3, 4, 5, 6]) {
    assert.ok(markupDoc.includes(`RECIPE ${n} ·`), `recipe ${n}'s composition is missing`);
  }
  for (const n of [1, 2, 3, 4, 5]) {
    assert.ok(markupDoc.includes(`OP-H${n} `) || markupDoc.includes(`OP-H${n}·`),
      `opener OP-H${n} is missing from the markup file`);
  }
});

check("lifted markup is real HTML source, not double-escaped or tag-stripped", () => {
  assert.ok(markupDoc.includes('<section class="mod open" id="dd-thesis">'),
    "the composition lost its literal tags — entities were decoded in the wrong order");
  assert.ok(!markupDoc.includes("&lt;section"), "the composition is still escaped");
  assert.ok(markupDoc.includes("&para;"),
    "an entity the author wrote INTO the source was decoded — the paste would no longer match");
});

/* ---- 5. NO SILENT CORRUPTION IN THE PROSE ---- */

check("no empty inline-code span survives", () => {
  /* `<code>&lt;em&gt;</code>` is real content on these pages. Decoding entities before the global
     tag strip turns it into a literal <em> that the strip then deletes, leaving `` — a rule with
     its subject silently removed. */
  for (const [name, body] of [["digest", digest], ["recipes", recipesDoc]]) {
    const at = body.indexOf("``");
    assert.strictEqual(at, -1,
      `${name} carries an empty inline-code span at byte ${at} — a code reference was destroyed: `
      + JSON.stringify(body.slice(Math.max(0, at - 90), at + 40)));
  }
  assert.ok(digest.includes("`<em>`"),
    "the <em> reference in the thesis-hero unlocks clause is the canary for this bug and is gone");
});

check("no HTML entity leaks into the prose as literal source", () => {
  const KNOWN_LITERAL = /&(?:para|amp|lt|gt|quot|nbsp|#\d+);/;   // legal only inside the markup file
  for (const [name, body] of [["digest", digest], ["recipes", recipesDoc]]) {
    const hits = [...new Set((body.match(/&[a-zA-Z][a-zA-Z0-9]{1,9};/g) || []))]
      .filter((e) => !KNOWN_LITERAL.test(e));
    assert.deepStrictEqual(hits, [], `${name} leaks undecoded entities: ${hits.join(" ")}`);
  }
});

check("no raw markup survives into the digest prose", () => {
  const strays = digest.match(/<(?:div|span|section|p|ul|li|article|b|i|em|strong)\b[^>]*>/g) || [];
  const outsideCode = strays.filter((t) => !digest.includes("`" + t + "`"));
  assert.deepStrictEqual(outsideCode, [],
    `presentation markup leaked into the digest: ${outsideCode.slice(0, 5).join(" ")}`);
});

/* ---- 6. THE NAVIGATION IS BUILT FROM CONTENT, AND POINTS SOMEWHERE REAL ---- */

check("the reach-for index carries every picker row from both galleries and invents none", () => {
  const table = digest.split(/^## /m).find((s) => s.startsWith("What to reach for"));
  assert.ok(table, "the reach-for index is gone");
  const rows = (table.match(/^\| .+ \| .+ \| (?:PROOF_BLOCKS|CREATIVE_LAYOUTS) \|$/gm) || []);
  assert.strictEqual(rows.length, 44,
    "19 PROOF_BLOCKS + 25 CREATIVE_LAYOUTS picker rows; a count change means .prow.phead header "
    + "rows leaked in or data rows dropped out");
  /* Every reach-for line must be present in its own source page. Compared on letters and digits
     alone: the sources spell apostrophes and dashes as entities (&rsquo;, &ndash;) that the digest
     resolves, so a literal substring test would flag correct extractions as inventions. */
  const alnum = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "");
  const need = table.match(/^\| ([^|]+) \|/gm).slice(1).map((s) => s.slice(2, -2).trim());
  const plain = (h) => bodyOf(h).replace(/<[^>]*>/g, " ").replace(/&[a-zA-Z#0-9]+;/g, "");
  const haystack = alnum(plain(src.blocks) + " " + plain(src.layouts));
  const invented = need.filter((n) => {
    const key = alnum(n);
    return key.length > 12 && !haystack.includes(key.slice(0, 28));
  });
  assert.deepStrictEqual(invented, [], `reach-for rows not present in either source: ${invented.join(" | ")}`);
});

check("the three tiers cross-reference each other by their real filenames", () => {
  assert.ok(digest.includes("`KIT_DIGEST_RECIPES.md`") && digest.includes("`KIT_DIGEST_MARKUP.md`"),
    "the digest does not tell an agent where the other two tiers are");
  assert.ok(recipesDoc.includes("`KIT_DIGEST.md`") && recipesDoc.includes("`KIT_DIGEST_MARKUP.md`"));
  assert.ok(markupDoc.includes("`KIT_DIGEST.md`"));
  for (const name of OUTPUTS) assert.ok(fs.existsSync(path.join(intake, name)), `${name} missing`);
});

check("every markup pointer in the digest names a heading that exists in the markup file", () => {
  const pointers = [...digest.matchAll(/`KIT_DIGEST_MARKUP\.md` → "([^"]+)"/g)].map((m) => m[1]);
  assert.ok(pointers.length >= 5, "the opener entries stopped pointing at their markup");
  const dangling = pointers.filter((p) => !markupDoc.includes(`### ${p}`));
  assert.deepStrictEqual(dangling, [], `markup pointers with no target heading: ${dangling.join(", ")}`);
  const recipePointers = [...recipesDoc.matchAll(/`KIT_DIGEST_MARKUP\.md` → "([^"]+)"/g)].map((m) => m[1]);
  assert.strictEqual(recipePointers.length, 6, "every recipe should point at its composition");
  const danglingR = recipePointers.filter((p) => !markupDoc.includes(`### ${p}`));
  assert.deepStrictEqual(danglingR, [], `recipe markup pointers with no target: ${danglingR.join(", ")}`);
});

check("the honest absences the galleries carry are named, not quietly omitted", () => {
  /* 13 of CREATIVE_LAYOUTS' 25 patterns ship with no caption at all. Reporting 12 captions without
     saying 13 are missing would read as a complete extraction of an incomplete page. */
  assert.match(digest, /^## Creative-layout captions — 12 of 25$/m);
  assert.match(digest, /\*\*No caption in the gallery \(13\)\*\*/);
  assert.match(digest, /^## Opener hero forms — 5$/m);
  assert.match(digest, /this digest reads §4 only\. Not extracted:/,
    "openers.html is only partly read; the digest must say which part");
});

/* ---- 7. THE COST — the number this whole exercise exists to move ---- */

check("the always-loaded tier stays far below the corpus it replaces", () => {
  const rawBytes = Object.values(sourcePaths).reduce((n, p) => n + fs.statSync(p).size, 0);
  const tok = (s) => Math.round(s.length / 4);
  assert.ok(rawBytes > 900_000, "sources shrank unexpectedly — re-measure before trusting the ratio");
  assert.ok(tok(digest) < 20_000,
    `KIT_DIGEST.md is ~${tok(digest)} tok; past 20k the always-loaded tier stops being cheap`);
  assert.ok(tok(digest) + tok(recipesDoc) + tok(markupDoc) < 45_000,
    "the three tiers together have grown past the point where reading the galleries is competitive");
  const ratio = rawBytes / (digest.length + recipesDoc.length + markupDoc.length);
  assert.ok(ratio > 5, `extraction ratio fell to ${ratio.toFixed(1)}x — presentation is leaking through`);
});

check("the generator refuses rather than degrades when a source is unusable", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "kit-digest-neg-"));
  try {
    /* a preconditions page with one clause surgically removed must be REFUSED, not emitted thin */
    const maimed = path.join(tmp, "maimed.html");
    fs.writeFileSync(maimed, src.preconditions.replace(/<div class="cl exc">[\s\S]*?<\/div>\s*<div class="cl deg">/, '<div class="cl deg">'));
    let failed = false, out = "";
    try {
      execFileSync(process.execPath, [script, "--preconditions", maimed, "--out", path.join(tmp, "x.md")],
        { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    } catch (e) { failed = true; out = String(e.stderr || ""); }
    assert.ok(failed, "the generator emitted a digest from a page whose clause counts do not add up");
    assert.match(out, /FATAL/, "the refusal was not loud");
    assert.ok(!fs.existsSync(path.join(tmp, "x.md")), "a partial digest was written before refusing");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

console.log(`kit-digest.test: PASS — ${checks} checks `
  + "(drift gate byte-identity across 3 outputs, --check agreement, preconditions/recipes/openers parse "
  + "signatures recomputed from source, reported counts, 45-not-46 contracts, four clauses on every "
  + "contract, 6 unreachable rows keep blocked-by and drop unlocks, partial `sequence` kept, "
  + "[RECIPE] same-bytes specimen↔<pre> on all 6, 11 fenced compositions, entity order, no empty "
  + "code spans, no entity leak, no markup leak, 44 picker rows all verbatim, tier cross-links, "
  + "markup pointers resolve, honest absences named, cost ceiling, refusal on a maimed source)");
