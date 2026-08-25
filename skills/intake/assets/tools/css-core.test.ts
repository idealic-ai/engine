/**
 * Nasty-case unit tests for the CSS core.
 * Run: `node css-core.test.ts` — no framework, no dependency. Exits non-zero on failure.
 */
import {
  splitSelectorList,
  naiveSplitSelectorList,
  stripComments,
  splitDeclaration,
  leadingClassName,
  walk,
  census,
} from './css-core.ts';

let passed = 0;
const failures: string[] = [];

const eq = (label: string, actual: unknown, expected: unknown): void => {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a === b) {
    passed += 1;
    return;
  }
  failures.push(`${label}\n    expected ${b}\n    actual   ${a}`);
};

const split = (s: string): string[] => [...splitSelectorList(s)];

// ── 1. the plain case still works ──────────────────────────────────────────
eq('plain two-selector list', split('.a, .b'), ['.a', '.b']);
eq('no comma', split('.a .b > .c'), ['.a .b > .c']);
eq('trailing whitespace normalised', split('  .a ,\n  .b  '), ['.a', '.b']);

// ── 2. :not() — the defect that cost four conclusions ──────────────────────
eq(':not with comma list', split(':not(.a, .b)'), [':not(.a, .b)']);
eq(':not naive comparison', naiveSplitSelectorList(':not(.a, .b)'), [':not(.a', '.b)']);
eq(
  ':not mixed with a real comma',
  split('.x:not(.a, .b), .y'),
  ['.x:not(.a, .b)', '.y'],
);

// ── 3. :is() / :where() ────────────────────────────────────────────────────
eq(':is + :where descendant', split(':is(a, b) :where(c, d)'), [':is(a, b) :where(c, d)']);
eq(
  ':is + :where with a real separator',
  split(':is(a, b) :where(c, d), .z'),
  [':is(a, b) :where(c, d)', '.z'],
);

// ── 4. attribute selectors ─────────────────────────────────────────────────
eq('comma inside attribute value', split('[data-x="a,b"]'), ['[data-x="a,b"]']);
eq('unquoted attribute, real comma after', split('[data-x=ab], .y'), ['[data-x=ab]', '.y']);
eq('bracket containing bracket-ish text', split('[title="]a,b["]'), ['[title="]a,b["]']);

// ── 5. commas inside strings and url() ─────────────────────────────────────
eq('comma inside a string', split('.a[title="one, two"], .b'), ['.a[title="one, two"]', '.b']);
eq(
  'comma inside url()',
  split('.a:has(> img[src="x,y.png"])'),
  ['.a:has(> img[src="x,y.png"])'],
);
eq(
  'url() in a declaration value survives declaration split',
  splitDeclaration('background: url("a;b,c.png") no-repeat'),
  { property: 'background', value: 'url("a;b,c.png") no-repeat' },
);

// ── 6. nested functional selectors ─────────────────────────────────────────
eq(
  'nested :not inside :is',
  split(':is(.a, :not(.b, .c)) .d, .e'),
  [':is(.a, :not(.b, .c)) .d', '.e'],
);
eq(
  'three levels deep',
  split(':where(:is(:not(.a, .b), .c), .d)'),
  [':where(:is(:not(.a, .b), .c), .d)'],
);

// ── 7. EOF auto-close, matching the CSS tokenizer ──────────────────────────
// Established in this corpus and re-tested against a real engine in
// eof-autoclose.test.ts: the tokenizer AUTO-CLOSES an unclosed function or
// attribute selector at EOF, so `td:nth-of-type(3` is LEGAL. Selector legality
// therefore cannot be used to detect truncation. The splitter matches that
// behaviour rather than inventing its own error.
eq('unclosed function at EOF', split('td:nth-of-type(3'), ['td:nth-of-type(3']);
eq('unclosed function swallows a later comma', split('td:nth-of-type(3, .b'), ['td:nth-of-type(3, .b']);
eq('unclosed attribute at EOF', split('[data-x="a,b'), ['[data-x="a,b']);
eq('unclosed string at EOF', split('.a[t="x,y'), ['.a[t="x,y']);

// ── 8. degenerate input ────────────────────────────────────────────────────
eq('empty', split(''), []);
eq('only commas', split(',,,'), []);
eq('empty fragment dropped', split('.a, , .b'), ['.a', '.b']);
eq('escaped comma in a class name', split('.a\\,b, .c'), ['.a\\,b', '.c']);
eq('stray close paren does not go negative', split('.a), .b'), ['.a)', '.b']);

// ── 9. comments ────────────────────────────────────────────────────────────
eq('comment stripped from selector', split('.a /* x */, .b'), ['.a', '.b']);
eq('comma inside a comment is not a separator', split('.a /*,*/ .b'), ['.a  .b']);
eq('comment stripping keeps strings intact', stripComments('a{c:"/*x*/"}/*y*/'), 'a{c:"/*x*/"}');
eq('unterminated comment runs to EOF', stripComments('.a{} /* tail'), '.a{} ');

// ── 10. the walker ─────────────────────────────────────────────────────────
const sheet = `
/* header */
.a, .b:not(.c, .d) { color: red; margin: 0 }
@media (min-width: 700px) {
  .e { color: blue !important }
  @supports (display: grid) {
    .f { display: grid }
  }
}
@import url("x.css");
@font-face { font-family: Q; src: url("q.woff2") }
@keyframes spin { from { opacity: 0 } to { opacity: 1 } }
`;
const w = walk(sheet);

eq(
  'style-rule selectors are balance-split',
  w.styleRules[0].selectors,
  ['.a', '.b:not(.c, .d)'],
);
eq('top-level style rules', w.styleRules.filter((r) => r.depth === 0 && r.at.length === 0).length, 1);
eq(
  'at-rule context is carried, not reconstructed',
  w.styleRules.find((r) => r.selectors[0] === '.f')?.at.map((a) => `${a.name} ${a.prelude}`),
  ['media (min-width: 700px)', 'supports (display: grid)'],
);
eq(
  'at-rules counted separately (media, supports, import, font-face, keyframes)',
  w.atRules.map((a) => a.name).sort(),
  ['font-face', 'import', 'keyframes', 'media', 'supports'],
);
eq('statement at-rule has no block', w.atRules.find((a) => a.name === 'import')?.hasBlock, false);
eq('keyframe frames are flagged, not counted as design rules', w.styleRules.filter((r) => r.at.some((a) => a.name === 'keyframes')).length, 2);
eq('!important detected and stripped from the value', w.declarations.find((d) => d.selector === '.e'), {
  kind: 'decl',
  at: [{ name: 'media', prelude: '(min-width: 700px)' }],
  selector: '.e',
  selectors: ['.e'],
  property: 'color',
  value: 'blue',
  important: true,
  // depth 2: @media's block is depth 1, the `.e` rule's block is depth 2.
  depth: 2,
  offset: w.declarations.find((d) => d.selector === '.e')?.offset,
});
eq('comments produce no records', w.declarations.some((d) => d.property.includes('header')), false);

// ── 11. custom property with a brace value is a declaration, not a rule ────
const cp = walk('.a { --x: { color: red }; color: blue }');
eq('brace-valued custom property does not open a rule', cp.styleRules.length, 1);
eq('declaration after a brace-valued custom property still parses', cp.declarations.map((d) => d.property), ['color']);

// ── 12. CSS nesting ────────────────────────────────────────────────────────
const nested = walk('.card { color: red; &:hover, &:focus { color: blue } }');
eq('nested rule recorded with its parent', nested.styleRules.length, 2);
eq('nested selectors balance-split', nested.styleRules[1].selectors, ['&:hover', '&:focus']);
eq('nested rule knows its parent selectors', nested.styleRules[1].parentSelectors, ['.card']);

// ── 13. leading class name ─────────────────────────────────────────────────
eq('descendant', leadingClassName('.card .title'), 'card');
eq('compound', leadingClassName('.a.b'), 'a');
eq('tag qualified', leadingClassName('div.x'), 'x');
eq('id has no leading class', leadingClassName('#id .y'), null);
eq('bare tag has no leading class', leadingClassName('div > p'), null);
eq('pseudo-class on a class', leadingClassName('.btn:hover'), 'btn');

// ── 14. census shape ───────────────────────────────────────────────────────
const c = census(sheet);
eq('census top-level style rules', c.topLevelStyleRules, 1);
eq('census at-rules', c.atRules, 5);
eq('census counts every balance-split selector', c.balanceSplitSelectors, 2 + 1 + 1 + 2);
eq('census leading classes', c.leadingClassNames, ['a', 'b', 'e', 'f']);

// ── 15. malformed sheets must not hang or throw ────────────────────────────
for (const bad of ['.a{', '}}}', '@media {', '.a{b:c', '/*', '"', '.a{--x:{']) {
  try {
    walk(bad);
    passed += 1;
  } catch (e) {
    failures.push(`malformed input threw: ${JSON.stringify(bad)} -> ${String(e)}`);
  }
}

// ── report ─────────────────────────────────────────────────────────────────
if (failures.length > 0) {
  console.error(`FAIL  ${failures.length} of ${passed + failures.length} assertions\n`);
  for (const f of failures) console.error(`  ✗ ${f}\n`);
  process.exit(1);
}
console.log(`PASS  ${passed} assertions (css-core.test.ts)`);
