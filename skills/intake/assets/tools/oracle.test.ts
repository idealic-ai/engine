/**
 * Engine-oracle test: validate the core against a REAL CSS engine (Chrome), not
 * against my own opinion of the grammar.
 *
 * Two things are proved here:
 *
 *  1. EOF AUTO-CLOSE. The corpus holds that the CSS tokenizer auto-closes an
 *     unclosed function or attribute selector at EOF, so `td:nth-of-type(3` is
 *     LEGAL while `.a{` and `:pending(x)` THROW — meaning selector legality can
 *     NOT be used to detect truncation. That is re-measured here rather than
 *     assumed, and the splitter is asserted to match it.
 *
 *  2. EVERY PIECE IS A REAL SELECTOR. Each selector the core splits out of the
 *     kit is fed to `document.querySelector`. A correct split yields only valid
 *     standalone selectors; a wrong split yields fragments the engine rejects.
 *     The naive `split(',')` is run through the same gate for comparison.
 *
 * Run: `node oracle.test.ts [--json]`   (needs Google Chrome + puppeteer-core)
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import puppeteer from '/Users/invizko/Projects/finch/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js';
import { splitSelectorList, naiveSplitSelectorList, walk } from './css-core.ts';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const KIT_DIR = join(import.meta.dirname, '..');

export type EofCase = { readonly input: string; readonly legal: boolean; readonly error: string };
export type OracleReport = {
  readonly eof: readonly EofCase[];
  readonly truthTotal: number;
  readonly truthInvalid: readonly string[];
  readonly naiveTotal: number;
  readonly naiveInvalid: readonly string[];
  readonly chromeTopLevelRules: number;
  readonly coreTopLevelRules: number;
  /** Naive pieces absent from the truth. Split by whether the engine accepts them. */
  readonly phantomTotal: number;
  readonly phantomValid: readonly string[];
  readonly phantomInvalid: readonly string[];
};

const EOF_CASES = [
  'td:nth-of-type(3',
  '[data-x="a,b',
  '.a[t="x,y',
  ':is(.a, .b',
  ':not(.a',
  '.a{',
  ':pending(x)',
  '.a,',
  '::unknown-element',
  '.a >',
] as const;

const run = async (): Promise<OracleReport> => {
  const sheets = readdirSync(KIT_DIR).filter((f) => f.endsWith('.css')).sort();
  const truth: string[] = [];
  const naive: string[] = [];
  let coreTopLevelRules = 0;
  const styleTags: string[] = [];

  for (const f of sheets) {
    const css = readFileSync(join(KIT_DIR, f), 'utf8');
    styleTags.push(css);
    const w = walk(css);
    coreTopLevelRules += w.styleRules.filter((r) => r.depth === 0 && r.at.length === 0).length;
    for (const r of w.styleRules) {
      truth.push(...splitSelectorList(r.selectorList));
      naive.push(...naiveSplitSelectorList(r.selectorList));
    }
  }

  const browser = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    await page.setContent('<!doctype html><title>oracle</title><body>');

    const eof = await page.evaluate((cases: readonly string[]) =>
      cases.map((input) => {
        try {
          document.querySelector(input);
          return { input, legal: true, error: '' };
        } catch (e) {
          return { input, legal: false, error: (e as Error).name };
        }
      }),
    EOF_CASES as unknown as string[]);

    const check = async (list: readonly string[]): Promise<string[]> =>
      page.evaluate((sels: readonly string[]) => {
        const bad: string[] = [];
        for (const s of sels) {
          try {
            document.querySelector(s);
          } catch {
            bad.push(s);
          }
        }
        return bad;
      }, list as unknown as string[]);

    const truthInvalid = await check(truth);
    const naiveInvalid = await check(naive);

    // Chrome's own top-level rule count, as the engine parses the real sheets.
    const chromeTopLevelRules = await page.evaluate((cssList: readonly string[]) => {
      let n = 0;
      for (const css of cssList) {
        const el = document.createElement('style');
        el.textContent = css;
        document.head.appendChild(el);
        const sheet = el.sheet;
        if (sheet === null) continue;
        for (const rule of Array.from(sheet.cssRules)) {
          if (rule instanceof CSSStyleRule) n += 1;
        }
      }
      return n;
    }, styleTags as unknown as string[]);

    const truthSet = new Set(truth);
    const phantoms = naive.filter((n) => !truthSet.has(n));
    const invalidSet = new Set(naiveInvalid);
    const phantomDistinct = [...new Set(phantoms)];

    return {
      phantomTotal: phantoms.length,
      phantomValid: phantomDistinct.filter((p) => !invalidSet.has(p)),
      phantomInvalid: phantomDistinct.filter((p) => invalidSet.has(p)),
      eof,
      truthTotal: truth.length,
      truthInvalid: [...new Set(truthInvalid)],
      naiveTotal: naive.length,
      naiveInvalid: [...new Set(naiveInvalid)],
      chromeTopLevelRules,
      coreTopLevelRules,
    };
  } finally {
    await browser.close();
  }
};

const report = await run();

if (process.argv.includes('--json')) {
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

console.log('ENGINE ORACLE — Google Chrome as ground truth\n');
console.log('1. EOF AUTO-CLOSE (document.querySelector on a truncated selector)\n');
for (const c of report.eof) {
  console.log(`   ${c.legal ? 'LEGAL ' : 'THROWS'}  ${JSON.stringify(c.input).padEnd(24)} ${c.error}`);
}

console.log('\n2. EVERY SPLIT PIECE MUST BE A VALID STANDALONE SELECTOR\n');
console.log(`   balance-aware : ${report.truthTotal} pieces, ${report.truthInvalid.length} rejected by Chrome`);
console.log(`   split(',')    : ${report.naiveTotal} pieces, ${report.naiveInvalid.length} rejected by Chrome`);
if (report.naiveInvalid.length > 0) {
  console.log('\n   fragments the naive split invents that are not selectors at all (first 10 distinct):');
  for (const s of report.naiveInvalid.slice(0, 10)) console.log(`     ✗ ${s.replace(/\s+/g, ' ')}`);
}

console.log('\n2b. THE DANGEROUS HALF — phantoms the engine ACCEPTS\n');
console.log(`   phantom pieces total (naive minus truth) : ${report.phantomTotal}`);
console.log(`   distinct phantoms the engine REJECTS     : ${report.phantomInvalid.length}  (loud — a syntax error)`);
console.log(`   distinct phantoms the engine ACCEPTS     : ${report.phantomValid.length}  (SILENT — a valid selector the sheet never wrote)`);
console.log(`   e.g. ${JSON.stringify(report.phantomValid.slice(0, 14))}`);

console.log('\n3. TOP-LEVEL STYLE-RULE COUNT vs the engine\n');
console.log(`   Chrome CSSOM : ${report.chromeTopLevelRules}`);
console.log(`   css-core     : ${report.coreTopLevelRules}`);

// ── assertions ─────────────────────────────────────────────────────────────
const failures: string[] = [];
const legalOf = (s: string): boolean => report.eof.find((c) => c.input === s)?.legal === true;

// The corpus claim, re-measured.
for (const legal of ['td:nth-of-type(3', '[data-x="a,b', '.a[t="x,y', ':is(.a, .b', ':not(.a']) {
  if (!legalOf(legal)) failures.push(`expected AUTO-CLOSE (legal) but engine rejected: ${legal}`);
}
for (const bad of ['.a{', ':pending(x)']) {
  if (legalOf(bad)) failures.push(`expected THROW but engine accepted: ${bad}`);
}

// The splitter must MATCH that behaviour: it must not error, and it must return
// the truncated selector whole rather than inventing a repair or a split.
for (const legal of ['td:nth-of-type(3', '[data-x="a,b', '.a[t="x,y']) {
  const got = splitSelectorList(legal);
  if (got.length !== 1 || got[0] !== legal) {
    failures.push(`splitter did not auto-close like the engine: ${legal} -> ${JSON.stringify(got)}`);
  }
}

if (report.truthInvalid.length > 0) {
  failures.push(
    `core produced ${report.truthInvalid.length} pieces Chrome rejects: ${JSON.stringify(report.truthInvalid.slice(0, 5))}`,
  );
}
if (report.naiveInvalid.length === 0) {
  failures.push('naive split produced no engine-invalid fragments — the differential would be vacuous');
}
if (report.chromeTopLevelRules !== report.coreTopLevelRules) {
  failures.push(
    `top-level rule count disagrees with the engine: Chrome ${report.chromeTopLevelRules} vs core ${report.coreTopLevelRules}`,
  );
}

if (failures.length > 0) {
  console.error(`\nFAIL\n${failures.map((f) => `  ✗ ${f}`).join('\n')}`);
  process.exit(1);
}
console.log('\nPASS  oracle.test.ts — core agrees with the Chrome CSS engine on every axis measured');
