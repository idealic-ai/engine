/* reference-guards — an authoring checker for how a /prove page WRITES its references.
 *
 * Run as a test (fixtures, self-checking):
 *   node ~/.claude/engine/skills/intake/assets/__tests__/reference-guards.test.mjs
 * Run as an auditor against a real page (prints a report, exits 1 on any defect):
 *   node …/reference-guards.test.mjs --file  builds/board.html
 *   node …/reference-guards.test.mjs --url   https://…/proofs/yarik/board.html [--json]
 *
 * WHY THIS EXISTS. proof-ticket.js turns a bare `FIN-1234` into a chip: freshness dot, hover
 * teaser, anchored card. Its scanner SKIPS <a>, <code> and <pre> — deliberately, so it never nests
 * a link inside a link or rewrites a code listing. The consequence is that a key an author wrote as
 * its OWN anchor —
 *     <a href="https://linear.app/finchclaims/issue/FIN-2226">FIN-2226</a>
 * — can NEVER become a chip, no matter what is baked or fetched. It stays a plain blue link, and
 * nothing anywhere says why. On one real published board that was 78 anchors out of 440 refs. The
 * bake even fetches metadata for those keys and ships it; nothing can ever render it.
 *
 * So this is not a style rule. It is a defect class whose symptom is INVISIBLE — the page looks
 * fine, it is simply missing a third of its affordances — which is exactly the kind of thing that
 * has to be checked mechanically or not at all.
 *
 * SIBLING CHECKERS. `builds/elev/audit.mjs` (puppeteer, computed-style violations → JSON) and
 * `layout-guards.test.mjs` were written the same night. The shape deliberately matches both halves
 * so they consolidate rather than diverge: the check/eq counter + `PASS — N assertions` line from
 * proof-ticket.test.mjs, and audit.mjs's "one findings object, printed as JSON" report mode. What
 * a merged checker would need is a shared `rule(id, severity, fn) → findings[]` registry; each
 * rule below is already written in that shape (id, severity, a pure `scan(html)`), so the merge is
 * a move, not a rewrite.
 *
 * TRACKER CONFIG IS SOURCED, NOT HARDCODED. The issue-URL pattern and key prefix come from the
 * project's CLAUDE.md `## Tracker` section — the same place /ticket, /pr and /snapshot read them —
 * so a project on a different tracker gets a working checker without editing this file.
 */
import assert from "node:assert";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

/* ── tracker config, read from the project's `## Tracker` section ───────────── */

function findClaudeMd() {
  const bases = [];
  if (process.env.FINCH_REPO) bases.push(process.env.FINCH_REPO);
  try { bases.push(execSync("git rev-parse --show-toplevel", { stdio: ["ignore", "pipe", "ignore"] }).toString().trim()); } catch { /* not a checkout */ }
  bases.push(process.cwd());
  for (const b of bases) {
    let d = b;
    for (let i = 0; i < 8 && d && d !== "/"; i++) {
      const p = path.join(d, "CLAUDE.md");
      if (fs.existsSync(p)) return p;
      d = path.dirname(d);
    }
  }
  return null;
}

function escapeRe(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

// Returns { prefix, urlTemplate, issueUrlRe, keyRe, source }. Falls back to the kit default only
// when no CLAUDE.md is reachable — and says so, so a silently-wrong tracker is impossible.
function trackerConfig() {
  const file = findClaudeMd();
  const DEFAULT = { prefix: "FIN", urlTemplate: "https://linear.app/finchclaims/issue/<KEY>", source: "built-in default (no CLAUDE.md found)" };
  let cfg = DEFAULT;
  if (file) {
    const md = fs.readFileSync(file, "utf8");
    const prefix = /^\s*-\s*\*\*Issue-key prefix\*\*:\s*`([A-Za-z][A-Za-z0-9]*)`/m.exec(md);
    const url = /^\s*-\s*\*\*Issue URL\*\*:\s*`([^`]+)`/m.exec(md);
    if (prefix && url) cfg = { prefix: prefix[1], urlTemplate: url[1], source: file };
    else cfg = { ...DEFAULT, source: `${file} (no \`## Tracker\` Issue-URL / prefix entry — using the built-in default)` };
  }
  const keySrc = `${escapeRe(cfg.prefix)}-\\d+`;
  // The template's <KEY> placeholder becomes the capture group; everything else is literal. A
  // trailing slug / query / fragment is tolerated because tracker links routinely carry one.
  const urlSrc = cfg.urlTemplate.split("<KEY>").map(escapeRe).join(`(${keySrc})`);
  return {
    ...cfg,
    keyRe: new RegExp(`\\b${keySrc}\\b`, "g"),
    issueUrlRe: new RegExp(urlSrc, "i"),
  };
}

/* ── the rules ──────────────────────────────────────────────────────────────── */
/* Each is { id, severity, title, fix, scan(html, cfg) → finding[] }. A finding is
   { key?, sample, note? }. `defect` fails the audit; `warning` reports without failing. */

const ANCHOR_RE = /<a\b[^>]*>[\s\S]*?<\/a\s*>/gi;
const HREF_RE = /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i;
const stripTags = (s) => s.replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();

// Strip what is never rendered, so a scan of an already-baked page does not harvest its own blob.
// Mirrors bake-tickets.sh --scan, which is the other half of this contract.
function renderable(html) {
  let s = html;
  for (const tag of ["script", "style", "textarea"]) {
    s = s.replace(new RegExp(`<${tag}\\b[^>]*>[\\s\\S]*?</${tag}\\s*>`, "gi"), " ");
  }
  return s.replace(/<!--[\s\S]*?-->/g, " ");
}

// Both anchor rules read the same walk. Split by what the anchor's VISIBLE TEXT is, because that
// is what decides whether anything was actually lost:
//   · text IS the key  → a chip was destroyed. The component would have rendered a dot, a teaser
//     and a card here; the hand-written anchor replaced all of it with a plain blue link. DEFECT.
//   · text is prose ("↗ Origin") → nothing was lost, there was no key to chip. But the reference
//     is still invisible to the scanner and to --scan's bake list. WARNING, not defect: demanding
//     a rewrite here would be demanding worse prose for no gain.
function trackerAnchors(html, cfg) {
  const out = [];
  for (const a of renderable(html).match(ANCHOR_RE) || []) {
    const h = HREF_RE.exec(a);
    const href = h ? (h[1] ?? h[2] ?? h[3] ?? "") : "";
    const m = cfg.issueUrlRe.exec(href);
    if (!m) continue;
    const text = stripTags(a);
    out.push({
      key: m[1],
      text,
      bare: new RegExp(`^${escapeRe(m[1])}$`).test(text),
      sample: a.length > 160 ? a.slice(0, 157) + "…" : a,
    });
  }
  return out;
}

const RULES = [
  {
    id: "RG-ANCHOR",
    severity: "defect",
    title: "a ticket key written as its own <a> can never render as a chip",
    fix: "write the key as BARE TEXT — `<KEY>`, never `<a href=\"…/issue/<KEY>\"><KEY></a>`. The component builds the link, the freshness dot and the card for you; your own anchor only takes them away.",
    scan(html, cfg) {
      return trackerAnchors(html, cfg).filter((a) => a.bare)
        .map((a) => ({ key: a.key, sample: a.sample, note: "bare-key anchor" }));
    },
  },
  {
    id: "RG-ANCHOR-PROSE",
    severity: "warning",
    title: "a prose link to a ticket is invisible to the scanner and to the bake list",
    fix: "nothing is lost visually — keep the prose link if it reads better. If you want the ticket's status shown, mention the bare key somewhere in the surrounding sentence too.",
    scan(html, cfg) {
      return trackerAnchors(html, cfg).filter((a) => !a.bare)
        .map((a) => ({ key: a.key, sample: a.sample, note: `text: ${JSON.stringify(a.text.slice(0, 40))}` }));
    },
  },
  {
    id: "RG-CODE-ONLY",
    severity: "warning",
    title: "a ticket key that appears ONLY inside <code>/<pre> can never render as a chip",
    fix: "if it is a reference, move it into prose; if it is genuinely code/log output, ignore this — the skip is correct.",
    scan(html, cfg) {
      const page = renderable(html);
      const banked = [];
      const stripped = page.replace(/<(code|pre)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, (m) => {
        banked.push(...(m.match(cfg.keyRe) || []));
        return " ";
      });
      const reachable = new Set(stripped.match(cfg.keyRe) || []);
      return [...new Set(banked)].filter((k) => !reachable.has(k)).map((k) => ({ key: k, sample: `<code>…${k}…</code>` }));
    },
  },
  {
    id: "RG-DANGLING-ITEM",
    severity: "warning",
    title: "an internal item reference resolves to nothing",
    fix: "the ordinal in prose no longer matches any item's ordinal — renumber the prose, or give the item a matching ordinal. proof-ticket.js leaves an unresolvable token as plain text, so this is silent today.",
    scan(html) {
      const page = renderable(html);
      const items = [...page.matchAll(/<[a-z][^>]*\bdata-(?:fb-item|decision-item|prove-item)\s*=\s*"([^"]*)"[^>]*>/gi)];
      if (!items.length) return [];   // not an item-bearing page; bracket tokens mean something else
      const ids = new Set(items.map((m) => m[1]));
      // Ordinals as the component reads them: the first .decno/.itemno/[data-ordinal] inside an item.
      const ordinals = new Set();
      for (const m of page.matchAll(/<[^>]*class="[^"]*\b(?:decno|itemno)\b[^"]*"[^>]*>([^<]{1,8})</gi)) {
        const t = m[1].trim();
        if (t) ordinals.add(t);
      }
      if (!ordinals.size) return [];  // no ordinals shown ⇒ the component falls back to position
      const text = page.replace(/<[^>]+>/g, " ");
      const out = [];
      for (const m of new Set((text.match(/\[\d{1,3}\]/g) || []))) {
        const tok = m.slice(1, -1);
        if (!ordinals.has(tok) && !ids.has(tok)) out.push({ key: m, sample: m, note: `no item carries ordinal ${tok}` });
      }
      return out;
    },
  },
];

function audit(html, cfg) {
  const findings = {};
  let defects = 0, warnings = 0;
  for (const r of RULES) {
    const f = r.scan(html, cfg);
    findings[r.id] = { severity: r.severity, title: r.title, fix: r.fix, count: f.length, findings: f };
    if (r.severity === "defect") defects += f.length; else warnings += f.length;
  }
  const totalKeys = (renderable(html).match(cfg.keyRe) || []).length;
  return { tracker: { prefix: cfg.prefix, urlTemplate: cfg.urlTemplate, source: cfg.source }, totalKeys, defects, warnings, rules: findings };
}

/* ── CLI (auditor) mode ─────────────────────────────────────────────────────── */

const argv = process.argv.slice(2);
const argOf = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : null; };
const target = argOf("--file");
const url = argOf("--url");

if (target || url) {
  const cfg = trackerConfig();
  const html = target ? fs.readFileSync(target, "utf8") : await (await fetch(url)).text();
  const report = audit(html, cfg);
  if (argv.includes("--json")) {
    console.log(JSON.stringify(report, null, 1));
  } else {
    console.log(`reference-guards — ${target || url}`);
    console.log(`  tracker: ${cfg.prefix} · ${cfg.urlTemplate}`);
    console.log(`  source:  ${cfg.source}`);
    console.log(`  ${report.totalKeys} renderable ${cfg.prefix} key occurrence(s) on the page\n`);
    for (const r of RULES) {
      const g = report.rules[r.id];
      const badge = g.count === 0 ? "ok  " : (g.severity === "defect" ? "FAIL" : "warn");
      console.log(`  ${badge} ${r.id}  ${g.count}  ${r.title}`);
      if (!g.count) continue;
      const byKey = {};
      for (const f of g.findings) byKey[f.key] = (byKey[f.key] || 0) + 1;
      const keys = Object.entries(byKey).sort((a, b) => b[1] - a[1]);
      console.log(`       distinct: ${keys.length} — ${keys.map(([k, n]) => (n > 1 ? `${k}×${n}` : k)).join(" ")}`);
      console.log(`       fix: ${r.fix}`);
      console.log(`       e.g. ${g.findings[0].sample}`);
    }
    console.log(`\n  ${report.defects} defect(s), ${report.warnings} warning(s)`);
  }
  process.exit(report.defects ? 1 : 0);
}

/* ── test mode (fixtures) ───────────────────────────────────────────────────── */

let COUNT = 0;
function check(cond, msg) { assert.ok(cond, msg); COUNT++; }
function eq(a, b, msg) { assert.strictEqual(a, b, msg); COUNT++; }

const CFG = trackerConfig();

/* ── 1. the tracker config is SOURCED from CLAUDE.md, not hardcoded ── */
{
  check(/CLAUDE\.md/.test(CFG.source), "the tracker config was read from a CLAUDE.md, not the built-in default");
  eq(CFG.prefix, "FIN", "…yielding this project's issue-key prefix");
  check(CFG.urlTemplate.includes("<KEY>"), "…and an Issue-URL template with a <KEY> placeholder");
  check(CFG.issueUrlRe.test("https://linear.app/finchclaims/issue/FIN-2226"), "the derived URL matcher matches a real issue link");
  check(!CFG.issueUrlRe.test("https://linear.app/finchclaims/project/FIN-2226"), "…and not a project link that merely contains a key");
  // Nothing OPERATIVE may name a tracker. The rules must work off `cfg`, and the one hardcoded
  // host in the file is the labelled DEFAULT that only applies when no CLAUDE.md is reachable.
  const src = fs.readFileSync(fileURLToPath(import.meta.url), "utf8");
  const rulesBlock = src.slice(src.indexOf("const RULES = ["), src.indexOf("function audit("));
  check(!/linear\.app|\bFIN-/.test(rulesBlock), "no rule hardcodes a tracker host or key prefix — every rule reads `cfg`");
  const defaults = src.slice(src.indexOf("const DEFAULT ="), src.indexOf("let cfg = DEFAULT"));
  eq((defaults.match(/linear\.app/g) || []).length, 1, "the host is hardcoded exactly once: in the labelled no-CLAUDE.md fallback");
}

/* ── 2. RG-ANCHOR: the defect this checker exists for ── */
{
  const page = `<p>Plain FIN-100 is fine. But
    <a href="https://linear.app/finchclaims/issue/FIN-2226">FIN-2226</a> is not, and neither is
    <a class="x" href='https://linear.app/finchclaims/issue/FIN-2227/some-slug'>see the ticket</a>.</p>`;
  const r = audit(page, CFG);
  eq(r.rules["RG-ANCHOR"].count, 1, "the BARE-KEY anchor is the defect — a chip was destroyed there");
  eq(r.defects, 1, "…and it is the only defect");
  eq(r.rules["RG-ANCHOR"].findings[0].key, "FIN-2226", "the offending KEY is reported, not just the line");
  // The prose anchor is a different animal: nothing was lost, because there was no key to chip.
  eq(r.rules["RG-ANCHOR-PROSE"].count, 1, "the prose anchor is reported separately");
  eq(r.rules["RG-ANCHOR-PROSE"].severity, "warning", "…as a WARNING — demanding a rewrite there buys worse prose and no chip");
  eq(r.rules["RG-ANCHOR-PROSE"].findings[0].key, "FIN-2227", "a slugged tracker URL is matched too");
}

/* ── 3. RG-ANCHOR does not fire on links that are not tracker issue links ── */
{
  const page = `<a href="https://example.com/FIN-1">FIN-1</a>
    <a href="#local">FIN-2</a>
    <a href="https://linear.app/finchclaims/project/abc">project</a>`;
  eq(audit(page, CFG).rules["RG-ANCHOR"].count, 0, "a non-tracker href carrying a key is not a defect (it is someone else's link)");
}

/* ── 4. the checker ignores what the page never renders (its own baked blob) ── */
{
  const page = `<script id="prove-tickets" type="application/json">{"tickets":{"FIN-3000":{"url":"https://linear.app/finchclaims/issue/FIN-3000"}}}</script>
    <p>FIN-100</p>`;
  const r = audit(page, CFG);
  eq(r.rules["RG-ANCHOR"].count, 0, "a tracker URL inside the baked blob is not an authoring defect");
  eq(r.totalKeys, 1, "…and blob keys are not counted as page references");
}

/* ── 5. RG-CODE-ONLY: a key reachable ONLY through <code>/<pre> ── */
{
  const page = `<p>See FIN-1 in prose.</p><code>grep FIN-1 FIN-777</code><pre>FIN-888</pre>`;
  const g = audit(page, CFG).rules["RG-CODE-ONLY"];
  eq(g.count, 2, "the two code-only keys are reported");
  eq(g.severity, "warning", "…as warnings — a key in a log listing is often correctly skipped");
  check(g.findings.map((f) => f.key).join(" ") === "FIN-777 FIN-888", "…naming exactly the unreachable keys");
  check(!g.findings.some((f) => f.key === "FIN-1"), "a key that ALSO appears in prose is reachable and not reported");
}

/* ── 6. RG-DANGLING-ITEM: an internal ref pointing at an ordinal no item carries ── */
{
  const board = `<section data-fb-item="a1"><span class="decno">1</span></section>
    <section data-fb-item="b2"><span class="decno">2</span></section>
    <p>see [1] and [2] and [7]</p>`;
  const g = audit(board, CFG).rules["RG-DANGLING-ITEM"];
  eq(g.count, 1, "only the unresolvable ordinal is reported");
  eq(g.findings[0].key, "[7]", "…naming it");
  // A page with no items at all: brackets mean something else entirely, so say nothing.
  eq(audit("<p>a regex [0-9] and a citation [3]</p>", CFG).rules["RG-DANGLING-ITEM"].count, 0,
    "a page with no addressable items is not an item-reference page — no findings");
}

/* ── 7. a clean page is clean (no false positives on the shape we want authors to write) ── */
{
  const good = `<section data-fb-item="a1"><span class="decno">1</span><span class="dectitle">One</span></section>
    <p>Decision [1] is blocked on FIN-100 and FIN-101.</p>`;
  const r = audit(good, CFG);
  eq(r.defects, 0, "the CORRECT authoring shape produces no defects");
  eq(r.warnings, 0, "…and no warnings");
  eq(r.totalKeys, 2, "…with both bare keys counted as real references");
}

console.log("reference-guards.test: PASS — " + COUNT + " assertions (tracker config sourced from CLAUDE.md `## Tracker`; RG-ANCHOR bare-key + prose + slugged URLs, no false fire on foreign hrefs or the page's own baked blob; RG-CODE-ONLY reachability; RG-DANGLING-ITEM ordinal resolution + no-items abstention; clean-page zero-finding). Audit a real page with --file <path> | --url <url> [--json].");
