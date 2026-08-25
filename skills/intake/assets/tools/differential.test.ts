/**
 * Differential test: balance-aware split vs `split(',')`, on the REAL kit sheets.
 *
 * The core's whole justification is that it is more correct than what it
 * replaces. This measures that, on production input, and fails if the naive
 * splitter is ever *more* correct.
 *
 * Run: `node differential.test.ts [--json]`
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import {
  splitSelectorList,
  naiveSplitSelectorList,
  walk,
  census,
  type StyleRuleRecord,
} from './css-core.ts';

export const KIT_DIR = join(import.meta.dirname, '..');

export const kitSheets = (): readonly string[] =>
  readdirSync(KIT_DIR)
    .filter((f) => f.endsWith('.css'))
    .sort();

export type Divergence = {
  readonly sheet: string;
  readonly selectorList: string;
  readonly truth: readonly string[];
  readonly naive: readonly string[];
  readonly phantoms: readonly string[];
};

export type SheetDiff = {
  readonly sheet: string;
  readonly bytes: number;
  readonly styleRules: number;
  readonly styleRulesExcludingKeyframeFrames: number;
  readonly topLevelStyleRules: number;
  readonly atRules: number;
  readonly atRulesWithBlock: number;
  readonly truthSelectors: number;
  readonly truthSelectorsExcludingKeyframeFrames: number;
  readonly naiveSelectors: number;
  readonly truthSelectorsTopLevel: number;
  readonly divergentRules: number;
  readonly divergences: readonly Divergence[];
};

/** Fragments the naive split invents that the sheet never contained. */
const phantomsOf = (truth: readonly string[], naive: readonly string[]): readonly string[] => {
  const real = new Set(truth);
  return naive.filter((n) => !real.has(n));
};

export const diffSheet = (sheet: string): SheetDiff => {
  const css = readFileSync(join(KIT_DIR, sheet), 'utf8');
  const w = walk(css);
  const c = census(css);
  const divergences: Divergence[] = [];
  let truthSelectors = 0;
  let naiveSelectors = 0;
  let truthSelectorsTopLevel = 0;

  for (const r of w.styleRules as readonly StyleRuleRecord[]) {
    const truth = splitSelectorList(r.selectorList);
    const naive = naiveSplitSelectorList(r.selectorList);
    truthSelectors += truth.length;
    naiveSelectors += naive.length;
    if (r.depth === 0 && r.at.length === 0) truthSelectorsTopLevel += truth.length;
    if (truth.length !== naive.length || truth.some((s, i) => s !== naive[i])) {
      divergences.push({
        sheet,
        selectorList: r.selectorList,
        truth,
        naive,
        phantoms: phantomsOf(truth, naive),
      });
    }
  }

  return {
    sheet,
    bytes: c.bytes,
    styleRules: c.styleRulesAll,
    styleRulesExcludingKeyframeFrames: c.styleRulesExcludingKeyframeFrames,
    topLevelStyleRules: c.topLevelStyleRules,
    atRules: c.atRules,
    atRulesWithBlock: c.atRulesWithBlock,
    truthSelectors,
    truthSelectorsExcludingKeyframeFrames: c.balanceSplitSelectorsExcludingKeyframeFrames,
    naiveSelectors,
    truthSelectorsTopLevel,
    divergentRules: divergences.length,
    divergences,
  };
};

export type DiffReport = {
  readonly sheets: readonly SheetDiff[];
  readonly totals: {
    readonly bytes: number;
    readonly sheets: number;
    readonly styleRules: number;
    readonly styleRulesExcludingKeyframeFrames: number;
    readonly topLevelStyleRules: number;
    readonly atRules: number;
    readonly atRulesWithBlock: number;
    readonly truthSelectors: number;
    readonly truthSelectorsExcludingKeyframeFrames: number;
    readonly naiveSelectors: number;
    readonly truthSelectorsTopLevel: number;
    readonly phantomSelectors: number;
    readonly phantomPct: number;
    readonly divergentRules: number;
  };
  readonly examples: readonly Divergence[];
};

export const buildReport = (): DiffReport => {
  const sheets = kitSheets().map(diffSheet);
  const sum = (pick: (s: SheetDiff) => number): number => sheets.reduce((n, s) => n + pick(s), 0);
  const truthSelectors = sum((s) => s.truthSelectors);
  const naiveSelectors = sum((s) => s.naiveSelectors);
  const phantomSelectors = naiveSelectors - truthSelectors;
  return {
    sheets,
    totals: {
      bytes: sum((s) => s.bytes),
      sheets: sheets.length,
      styleRules: sum((s) => s.styleRules),
      styleRulesExcludingKeyframeFrames: sum((s) => s.styleRulesExcludingKeyframeFrames),
      topLevelStyleRules: sum((s) => s.topLevelStyleRules),
      atRules: sum((s) => s.atRules),
      atRulesWithBlock: sum((s) => s.atRulesWithBlock),
      truthSelectors,
      truthSelectorsExcludingKeyframeFrames: sum((s) => s.truthSelectorsExcludingKeyframeFrames),
      naiveSelectors,
      truthSelectorsTopLevel: sum((s) => s.truthSelectorsTopLevel),
      phantomSelectors,
      phantomPct: (phantomSelectors / truthSelectors) * 100,
      divergentRules: sum((s) => s.divergentRules),
    },
    examples: sheets.flatMap((s) => s.divergences),
  };
};

if (import.meta.filename === process.argv[1]) {
  const report = buildReport();
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(report, null, 2));
    process.exit(0);
  }

  const t = report.totals;
  const pad = (s: string | number, n: number): string => String(s).padStart(n);
  console.log('KIT CENSUS + DIFFERENTIAL  (balance-aware split vs split(\',\'))\n');
  console.log(
    `${'sheet'.padEnd(26)}${pad('bytes', 8)}${pad('rules', 7)}${pad('top', 6)}${pad('@', 5)}${pad('truth', 8)}${pad('naive', 7)}${pad('phantom', 9)}`,
  );
  console.log('-'.repeat(76));
  for (const s of report.sheets) {
    console.log(
      `${s.sheet.padEnd(26)}${pad(s.bytes, 8)}${pad(s.styleRules, 7)}${pad(s.topLevelStyleRules, 6)}${pad(s.atRules, 5)}${pad(s.truthSelectors, 8)}${pad(s.naiveSelectors, 7)}${pad(s.naiveSelectors - s.truthSelectors, 9)}`,
    );
  }
  console.log('-'.repeat(76));
  console.log(
    `${'TOTAL'.padEnd(26)}${pad(t.bytes, 8)}${pad(t.styleRules, 7)}${pad(t.topLevelStyleRules, 6)}${pad(t.atRules, 5)}${pad(t.truthSelectors, 8)}${pad(t.naiveSelectors, 7)}${pad(t.phantomSelectors, 9)}`,
  );
  console.log(
    `\nPHANTOM SELECTORS: ${t.phantomSelectors}  (+${t.phantomPct.toFixed(2)}% over the truth of ${t.truthSelectors})`,
  );
  console.log(`DIVERGENT RULES:   ${t.divergentRules} of ${t.styleRules} style rules mis-split by split(',')`);
  console.log(`TOP-LEVEL SELECTORS (depth 0, no at-rule ancestor): ${t.truthSelectorsTopLevel}`);
  console.log('\nRECONCILIATION against the sibling census (2003 rules / 57 at-rules / 2280 selectors):');
  console.log(`  style rules excluding @keyframes frames : ${t.styleRulesExcludingKeyframeFrames}  (all: ${t.styleRules})`);
  console.log(`  at-rules with a block (@charset excluded): ${t.atRulesWithBlock}  (all: ${t.atRules})`);
  console.log(`  selectors excluding @keyframes frames    : ${t.truthSelectorsExcludingKeyframeFrames}  (all: ${t.truthSelectors})`);

  console.log('\nCONCRETE EXAMPLES — the fragment the naive split invents:\n');
  const shown = report.examples.slice(0, 8);
  for (const d of shown) {
    console.log(`  [${d.sheet}]`);
    console.log(`    source : ${d.selectorList.replace(/\s+/g, ' ')}`);
    console.log(`    truth  : ${d.truth.length} -> ${JSON.stringify(d.truth.map((s) => s.replace(/\s+/g, ' ')))}`);
    console.log(`    naive  : ${d.naive.length} -> ${JSON.stringify(d.naive.map((s) => s.replace(/\s+/g, ' ')))}`);
    console.log(`    PHANTOM: ${JSON.stringify(d.phantoms.map((s) => s.replace(/\s+/g, ' ')))}\n`);
  }

  // ── assertions ───────────────────────────────────────────────────────────
  const failures: string[] = [];
  if (t.sheets !== 8) failures.push(`expected 8 sheets, found ${t.sheets}`);
  if (t.bytes !== 408605) failures.push(`expected 408605 bytes, found ${t.bytes}`);
  if (t.phantomSelectors <= 0) failures.push('naive split produced no phantoms — differential is vacuous');
  if (t.phantomSelectors !== 164) failures.push(`expected 164 phantoms, found ${t.phantomSelectors}`);

  // The sibling census reported 2003 / 57 / 2280. Those figures are reproduced
  // exactly once its two implicit exclusions are named: @keyframes frames are
  // not style rules, and @charset is not a block at-rule.
  if (t.styleRulesExcludingKeyframeFrames !== 2003)
    failures.push(`reconciliation: expected 2003 non-frame style rules, found ${t.styleRulesExcludingKeyframeFrames}`);
  if (t.atRulesWithBlock !== 57)
    failures.push(`reconciliation: expected 57 block at-rules, found ${t.atRulesWithBlock}`);
  if (t.truthSelectorsExcludingKeyframeFrames !== 2280)
    failures.push(`reconciliation: expected 2280 non-frame selectors, found ${t.truthSelectorsExcludingKeyframeFrames}`);

  // The naive splitter must never be MORE correct: every naive result is either
  // identical to the truth or a strict over-split of it. If a phantom fragment
  // is itself a real selector elsewhere in the same list, the truth still holds
  // it — so re-joining the naive pieces must reconstruct the truth exactly.
  for (const d of report.examples) {
    if (d.naive.length < d.truth.length) {
      failures.push(`naive UNDER-split (core may be wrong here): ${d.selectorList}`);
    }
    const rejoined = d.naive.join(',');
    const truthJoined = d.truth.join(',').replace(/,\s*/g, ',').replace(/\s*,/g, ',');
    if (rejoined.replace(/\s+/g, '') !== truthJoined.replace(/\s+/g, '')) {
      failures.push(`naive pieces do not re-join to the truth: ${d.selectorList}`);
    }
  }

  if (failures.length > 0) {
    console.error(`\nFAIL\n${failures.map((f) => `  ✗ ${f}`).join('\n')}`);
    process.exit(1);
  }
  console.log('PASS  differential.test.ts — 8 sheets, 408605 B, naive split never more correct');
}
