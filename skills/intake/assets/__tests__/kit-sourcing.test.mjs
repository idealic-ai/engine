#!/usr/bin/env node
/**
 * kit-sourcing — does a local page LINK the shared kit, or carry its own copy of it?
 *
 * Local pages link. Always. A page that inlines the kit into a <style>, or links a private
 * copy of it, can never receive a kit fix — it renders the CSS of the day it was written,
 * looks finished, and is wrong forever.
 *
 * There is no "frozen on purpose" exemption, because locally there is no such thing.
 * Immutability is a property of PUBLISHING: a published document is its own snapshot at its
 * own moment, and the moment is recorded. Freezing a working file reproduces that guarantee
 * badly, somewhere nobody can see which revision it captured.
 *
 * So the rule is flat: carrying your own kit is a defect. The only thing that varies is
 * whether it is a NEW defect or part of the backlog, and `--baseline` draws that line.
 *
 * Where it runs follows from that. PUBLISHING is the gate: that is the moment a page stops
 * being a working file and becomes an immutable record, so it is the moment a stale copy
 * must not get through. A working tree is allowed to be a mess. `--file` is the gate;
 * `--scan` is for looking around during development.
 *
 *   node kit-sourcing.test.mjs                       # self-test on fixtures -> exit 0/1
 *   node kit-sourcing.test.mjs --file <page.html>    # THE PUBLISH GATE — one page, exit 1 to block
 *   node kit-sourcing.test.mjs --scan <root>         # development sweep; exit 1 if any page offends
 *        [--baseline <f.json>]                       # only fail on pages not already in the backlog
 *        [--write-baseline <f.json>]                 # record today's backlog
 *        [--list]                                    # print every offender, not just the new ones
 */
import { readdirSync, readFileSync, writeFileSync, realpathSync, existsSync } from 'node:fs';
import { join, relative, resolve, dirname } from 'node:path';

const KIT = realpathSync(resolve(process.env.HOME, '.claude/engine/skills/intake/assets'));

const KIT_SHEETS = [
  'proof-theme.css', 'proof-blocks.css', 'proof-creative.css', 'proof-module.css',
  'proof-ticket.css', 'board-widgets.css', 'board-swipe.css', 'board-warm-overrides.css',
];

// Selectors/custom properties that exist only inside the kit sheets.
const KIT_MARKERS = ['.cpv .verdict', '.proof-block', '--ink-quiet', '.evidence-row', '.verdict.refuted', '.verdict.confirmed'];

// A page may legitimately quote a kit rule to show it beside a proposed replacement.
// Quoting a rule is not carrying a stylesheet, so a volume floor separates the two.
const BAKE_FLOOR_BYTES = 20000;

// Templates and skeletons reference the kit through a token no build resolves. That is a
// page waiting to be filled in, not a page carrying its own copy.
const PLACEHOLDER = /(^|\/)(__[A-Z0-9_]+__|\{\{[^/]*\}\}|<[^/]*>)(\/|$)/;

function hrefToPath(href, fromFile) {
  const clean = href.split('?')[0].split('#')[0];
  if (PLACEHOLDER.test(clean)) return { placeholder: true };
  // Pages authored against a $HOME-rooted local static server. Those URLs name real files;
  // treating them as remote would misreport ~90 correctly-linked pages.
  const loop = clean.match(/^https?:\/\/(?:127\.0\.0\.1|localhost)(?::\d+)?(\/.*)$/i);
  if (loop) return { path: resolve(process.env.HOME, '.' + decodeURIComponent(loop[1])) };
  if (/^https?:\/\//i.test(clean)) return { remote: true };
  if (/^file:/i.test(clean)) return { path: decodeURIComponent(clean.replace(/^file:(\/\/)?/i, '')) };
  return { path: resolve(dirname(fromFile), clean) };
}

function isLiveKit(p) {
  if (!p) return false;
  let d = dirname(p);
  try { d = realpathSync(d); } catch { /* may not exist; fall through to a literal compare */ }
  return d === KIT;
}

export function classify(file, src) {
  const links = [...src.matchAll(/<link\b[^>]*>/gi)]
    .filter((m) => /rel=["']?stylesheet/i.test(m[0]))
    .map((m) => (m[0].match(/href=["']([^"']+)["']/i) || [, ''])[1])
    .filter(Boolean);

  let live = 0, copy = 0, placeholder = 0;
  const copyTargets = [];
  for (const h of links) {
    // A private copy is often version-stamped (proof-blocks.v2.css). Matching the bare kit
    // basename misses those entirely — and they are the copies most likely to be stale.
    const base = h.split('?')[0].split('#')[0].split('/').pop().replace(/\.v\d+\.css$/i, '.css');
    if (!KIT_SHEETS.includes(base)) continue;
    const r = hrefToPath(h, file);
    if (r.placeholder) { placeholder++; continue; }
    if (isLiveKit(r.path)) live++;
    else { copy++; copyTargets.push(r.path || h); }
  }

  const styles = [...src.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/gi)].map((m) => m[1]);
  const styleBytes = styles.reduce((a, s) => a + Buffer.byteLength(s), 0);
  const inline = styles.join('\n');
  const markers = KIT_MARKERS.filter((m) => inline.includes(m));
  const inlined = markers.length >= 2 && styleBytes > BAKE_FLOOR_BYTES;

  let cls;
  if (inlined && live > 0) cls = 'inlined+live';
  else if (inlined) cls = 'inlined';
  else if (live > 0 && copy > 0) cls = 'live+copy';
  else if (live > 0) cls = 'live-link';
  else if (copy > 0) cls = 'copy-link';
  else if (placeholder > 0) cls = 'placeholder-link';
  else if (styleBytes > 0) cls = 'own-css-only';
  else cls = 'no-css';

  const carriesOwnKit = ['inlined', 'inlined+live', 'copy-link', 'live+copy'].includes(cls);
  return { cls, carriesOwnKit, live, copy, placeholder, styleBytes, markers, copyTargets };
}

/* ─────────────────────────── self-test ─────────────────────────── */

const KIT_HREF = `file://${KIT}/proof-blocks.css`;
const BULK = '.proof-block{x:1}\n.cpv .verdict{y:2}\n'.padEnd(BAKE_FLOOR_BYTES + 500, '/*p*/');

const CASES = [
  ['links the live kit',
    `<html><head><link rel=stylesheet href="${KIT_HREF}"></head><body>x</body></html>`,
    { cls: 'live-link', carriesOwnKit: false }],

  ['links the live kit through the ~/.claude/skills symlink',
    `<html><head><link rel=stylesheet href="file://${process.env.HOME}/.claude/skills/intake/assets/proof-blocks.css"></head></html>`,
    { cls: 'live-link', carriesOwnKit: false }],

  ['links the live kit over a loopback static server',
    `<html><head><link rel=stylesheet href="http://127.0.0.1:8731/.claude/engine/skills/intake/assets/proof-blocks.css"></head></html>`,
    { cls: 'live-link', carriesOwnKit: false }],

  ['inlines the kit into a page-local <style> -> DEFECT',
    `<html><head><style>${BULK}</style></head></html>`,
    { cls: 'inlined', carriesOwnKit: true }],

  ['links a private copy -> DEFECT',
    `<html><head><link rel=stylesheet href="kit/proof-blocks.css"></head></html>`,
    { cls: 'copy-link', carriesOwnKit: true }],

  ['links a VERSION-STAMPED private copy -> still a DEFECT (the invisible case)',
    `<html><head><link rel=stylesheet href="kit/proof-blocks.v2.css"></head></html>`,
    { cls: 'copy-link', carriesOwnKit: true }],

  ['a freeze-declaring attribute buys nothing — local pages do not freeze',
    `<html data-kit-frozen="2026-08-01"><head><style>${BULK}</style></head></html>`,
    { cls: 'inlined', carriesOwnKit: true }],

  ['quotes one kit rule beside a proposal, links live -> pass',
    `<html><head><link rel=stylesheet href="${KIT_HREF}"><style>.inc .verdict{color:var(--seal)}\n.cpv .verdict{}</style></head></html>`,
    { cls: 'live-link', carriesOwnKit: false }],

  ['small page-local <style> carrying kit markers, no link -> not carrying the kit',
    `<html><head><style>.proof-block{a:1}\n.cpv .verdict{b:2}</style></head></html>`,
    { cls: 'own-css-only', carriesOwnKit: false }],

  ['skeleton referencing the kit through an unresolved publish token -> pass',
    `<html><head><link rel=stylesheet href="__FB_KIT_BASE__/proof-blocks.v2.css"></head></html>`,
    { cls: 'placeholder-link', carriesOwnKit: false }],

  ['fixture pointing at a __KIT__ placeholder -> pass',
    `<html><head><link rel=stylesheet href="__KIT__/proof-blocks.css"></head></html>`,
    { cls: 'placeholder-link', carriesOwnKit: false }],

  ['links live AND inlines -> still a DEFECT',
    `<html><head><link rel=stylesheet href="${KIT_HREF}"><style>${BULK}</style></head></html>`,
    { cls: 'inlined+live', carriesOwnKit: true }],

  ['no CSS at all -> pass',
    `<html><body>plain</body></html>`,
    { cls: 'no-css', carriesOwnKit: false }],
];

function selfTest() {
  let fail = 0;
  for (const [name, html, want] of CASES) {
    const got = classify('/tmp/fixture/page.html', html);
    const bad = Object.entries(want).filter(([k, v]) => got[k] !== v);
    if (bad.length) {
      fail++;
      console.error(`  FAIL  ${name}`);
      for (const [k, v] of bad) console.error(`          ${k}: want ${JSON.stringify(v)}, got ${JSON.stringify(got[k])}`);
    }
  }
  if (fail) { console.error(`kit-sourcing.test: FAIL — ${fail}/${CASES.length} cases`); return 1; }
  console.log(`kit-sourcing.test: PASS — ${CASES.length} cases (live via file:// · via symlink · via loopback · inlined kit is a defect · private copy is a defect · VERSION-STAMPED private copy is a defect · a freeze attribute buys nothing · quoted rule passes · sub-floor style passes · __FB_KIT_BASE__ passes · __KIT__ passes · link+inline is a defect · no-css passes)`);
  return 0;
}

/* ─────────────────────────── corpus scan ─────────────────────────── */

function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith('.') || e.name === 'node_modules') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.html')) out.push(p);
  }
  return out;
}

const BACKLOG_NOTE = 'UNREVIEWED BACKLOG, NOT APPROVAL. Every page listed here carries its own copy of '
  + 'the kit and cannot receive a kit fix. Recording them suppresses the failure so new offenders stay '
  + 'visible; nobody has examined them and none of them is known to be correct.';

function scan(root, baselinePath, writeBaseline, listAll) {
  const rows = walk(root).map((f) => ({ file: relative(root, f), ...classify(f, readFileSync(f, 'utf8')) }));
  const counts = {};
  for (const r of rows) counts[r.cls] = (counts[r.cls] || 0) + 1;
  console.log(`kit-sourcing — ${rows.length} pages under ${root}`);
  for (const [k, v] of Object.entries(counts).sort((a, b) => b[1] - a[1])) console.log(`${String(v).padStart(6)}  ${k}`);

  const offenders = rows.filter((r) => r.carriesOwnKit).map((r) => r.file).sort();

  if (writeBaseline) {
    writeFileSync(writeBaseline, JSON.stringify({ note: BACKLOG_NOTE, root, generated: new Date().toISOString().slice(0, 10), count: offenders.length, pages: offenders }, null, 1) + '\n');
    console.log(`\nrecorded backlog: ${offenders.length} pages carrying their own kit -> ${writeBaseline}`);
    return 0;
  }

  const known = new Set(baselinePath && existsSync(baselinePath) ? (JSON.parse(readFileSync(baselinePath, 'utf8')).pages || []) : []);
  const fresh = offenders.filter((f) => !known.has(f));
  const debt = offenders.length - fresh.length;
  console.log(`\ncarrying their own kit: ${offenders.length}${known.size ? `   (${debt} unreviewed backlog — recorded, not approved)` : ''}`);

  if (listAll) for (const f of offenders) console.log(`   ${f}`);

  if (!offenders.length) { console.log('VERDICT: PASS — every page links the live kit'); return 0; }
  if (!fresh.length) { console.log(`VERDICT: PASS — nothing new. ${debt} page(s) still owe a fix.`); return 0; }
  console.log(`VERDICT: FAIL — ${fresh.length} page(s) not in the backlog:`);
  if (!listAll) for (const f of fresh.slice(0, 40)) console.log(`   ${f}`);
  return 1;
}

/* ─────────────────────── the publish gate: one page ─────────────────────── */

function gate(file) {
  const r = classify(file, readFileSync(file, 'utf8'));
  console.log(`kit-sourcing gate — ${file}\n  sourcing: ${r.cls}  (live links ${r.live}, private copies ${r.copy}, publish tokens ${r.placeholder}, own style ${r.styleBytes}B)`);
  if (!r.carriesOwnKit) { console.log('VERDICT: PASS — nothing stale can be baked into this record.'); return 0; }
  console.log('VERDICT: FAIL — this page carries its own copy of the kit.');
  console.log('  Publishing makes a page permanent. Whatever CSS it holds now is what it holds forever,');
  console.log('  and it is already behind the shared sheet. Point it at the kit, or at the publish token.');
  for (const t of r.copyTargets) console.log(`  private copy: ${t}`);
  if (r.markers.length) console.log(`  inlined kit vocabulary: ${r.markers.join(' ')}`);
  return 1;
}

// Only act when run directly — `classify` is importable by corpus tooling.
if ((process.argv[1] || '').endsWith('kit-sourcing.test.mjs')) {
  const argv = process.argv.slice(2);
  const arg = (n) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : undefined; };
  if (argv.includes('--file')) process.exit(gate(resolve(arg('--file'))));
  else if (argv.includes('--scan')) process.exit(scan(resolve(arg('--scan')), arg('--baseline'), arg('--write-baseline'), argv.includes('--list')));
  else process.exit(selfTest());
}
