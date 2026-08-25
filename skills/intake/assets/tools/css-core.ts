/**
 * Shared typed CSS-parsing core.
 *
 * Authoring constraint: this file is run by bare `node css-core.ts` on Node >= 22.6
 * via type stripping. Type stripping ERASES types, it never EMITS code — so any
 * TypeScript construct with a runtime representation throws
 * ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX. No `enum`, no `namespace`, no parameter
 * properties, no decorators. Union types + `as const` objects instead.
 */

export type AtRuleContext = {
  readonly name: string;
  readonly prelude: string;
};

export type StyleRuleRecord = {
  readonly kind: 'style';
  readonly at: readonly AtRuleContext[];
  readonly selectorList: string;
  readonly selectors: readonly string[];
  readonly depth: number;
  readonly offset: number;
  readonly parentSelectors: readonly string[];
};

export type AtRuleRecord = {
  readonly kind: 'at';
  readonly at: readonly AtRuleContext[];
  readonly name: string;
  readonly prelude: string;
  readonly hasBlock: boolean;
  readonly depth: number;
  readonly offset: number;
};

export type DeclarationRecord = {
  readonly kind: 'decl';
  readonly at: readonly AtRuleContext[];
  readonly selector: string;
  readonly selectors: readonly string[];
  readonly property: string;
  readonly value: string;
  readonly important: boolean;
  readonly depth: number;
  readonly offset: number;
};

export type WalkResult = {
  readonly styleRules: readonly StyleRuleRecord[];
  readonly atRules: readonly AtRuleRecord[];
  readonly declarations: readonly DeclarationRecord[];
};

export type Census = {
  readonly bytes: number;
  readonly topLevelStyleRules: number;
  readonly styleRulesAll: number;
  readonly styleRulesExcludingKeyframeFrames: number;
  readonly atRules: number;
  readonly atRulesWithBlock: number;
  readonly atRulesTopLevel: number;
  readonly balanceSplitSelectors: number;
  readonly balanceSplitSelectorsExcludingKeyframeFrames: number;
  readonly balanceSplitSelectorsTopLevel: number;
  readonly distinctLeadingClassNames: number;
  readonly leadingClassNames: readonly string[];
  readonly declarations: number;
};

/**
 * Rule-bearing at-rules whose blocks contain style rules rather than declarations.
 * Everything else with a block (@font-face, @property, a @keyframes frame) holds
 * declarations. Kept as a const object, not an enum — see the file header.
 */
export const RULE_BEARING_AT_RULES = {
  media: true,
  supports: true,
  layer: true,
  container: true,
  scope: true,
  document: true,
  keyframes: true,
  '-webkit-keyframes': true,
  '-moz-keyframes': true,
} as const;

const isTerminator = (c: string): boolean => c === '{' || c === ';' || c === '}';

/**
 * Advance past one atomic run (comment or string) starting at `i`.
 * Returns `i + 1` when `i` does not begin one.
 *
 * Both auto-close at EOF, matching the CSS tokenizer. An unterminated string
 * also ends at a raw newline (the spec's <bad-string-token>).
 */
export const skipAtomic = (css: string, i: number): number => {
  const c = css[i];
  if (c === '/' && css[i + 1] === '*') {
    const end = css.indexOf('*/', i + 2);
    return end === -1 ? css.length : end + 2;
  }
  if (c === '"' || c === "'") {
    let j = i + 1;
    while (j < css.length) {
      const d = css[j];
      if (d === '\\') {
        j += 2;
        continue;
      }
      if (d === c) return j + 1;
      if (d === '\n') return j;
      j += 1;
    }
    return css.length;
  }
  return i + 1;
};

export const stripComments = (css: string): string => {
  const out: string[] = [];
  let i = 0;
  let plain = 0;
  while (i < css.length) {
    const c = css[i];
    if (c === '/' && css[i + 1] === '*') {
      out.push(css.slice(plain, i));
      i = skipAtomic(css, i);
      plain = i;
      continue;
    }
    if (c === '"' || c === "'") {
      i = skipAtomic(css, i);
      continue;
    }
    i += 1;
  }
  out.push(css.slice(plain));
  return out.join('');
};

/**
 * Balance-aware selector-list split.
 *
 * Splits on top-level commas only. A comma inside `(`…`)` (`:not()`, `:is()`,
 * `:where()`, `url()`), inside `[`…`]`, or inside a string is NOT a separator.
 * `split(',')` gets exactly these wrong, manufacturing selector fragments that
 * were never in the sheet.
 *
 * Unclosed functions and attribute selectors auto-close at EOF, matching the
 * tokenizer — `td:nth-of-type(3` is one selector, not a parse error.
 */
export const splitSelectorList = (selectorList: string): readonly string[] => {
  const pieces: string[] = [];
  let start = 0;
  let paren = 0;
  let bracket = 0;
  let i = 0;
  while (i < selectorList.length) {
    const c = selectorList[i];
    if ((c === '/' && selectorList[i + 1] === '*') || c === '"' || c === "'") {
      i = skipAtomic(selectorList, i);
      continue;
    }
    if (c === '\\') {
      i += 2;
      continue;
    }
    if (c === '(') {
      paren += 1;
    } else if (c === ')') {
      if (paren > 0) paren -= 1;
    } else if (c === '[') {
      bracket += 1;
    } else if (c === ']') {
      if (bracket > 0) bracket -= 1;
    } else if (c === ',' && paren === 0 && bracket === 0) {
      pieces.push(selectorList.slice(start, i));
      start = i + 1;
    }
    i += 1;
  }
  pieces.push(selectorList.slice(start));
  const out: string[] = [];
  for (const piece of pieces) {
    const clean = stripComments(piece).trim();
    if (clean.length > 0) out.push(clean);
  }
  return out;
};

/**
 * The naive splitter this core replaces. Exported so the differential test
 * measures the real incumbent rather than a strawman: it trims and drops empties
 * exactly as the loose scripts do, so every difference is balance-awareness alone.
 */
export const naiveSplitSelectorList = (selectorList: string): readonly string[] =>
  selectorList
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

type PreludeRead = {
  readonly text: string;
  readonly end: number;
  readonly term: '{' | ';' | '}' | 'eof';
};

const readPrelude = (css: string, from: number): PreludeRead => {
  let i = from;
  let paren = 0;
  let bracket = 0;
  while (i < css.length) {
    const c = css[i];
    if ((c === '/' && css[i + 1] === '*') || c === '"' || c === "'") {
      i = skipAtomic(css, i);
      continue;
    }
    if (c === '\\') {
      i += 2;
      continue;
    }
    if (c === '(') {
      paren += 1;
    } else if (c === ')') {
      if (paren > 0) paren -= 1;
    } else if (c === '[') {
      bracket += 1;
    } else if (c === ']') {
      if (bracket > 0) bracket -= 1;
    } else if (paren === 0 && bracket === 0 && isTerminator(c)) {
      return { text: css.slice(from, i), end: i, term: c as '{' | ';' | '}' };
    }
    i += 1;
  }
  return { text: css.slice(from), end: css.length, term: 'eof' };
};

export type Declaration = { readonly property: string; readonly value: string };

export const splitDeclaration = (text: string): Declaration | null => {
  let i = 0;
  let paren = 0;
  let bracket = 0;
  while (i < text.length) {
    const c = text[i];
    if ((c === '/' && text[i + 1] === '*') || c === '"' || c === "'") {
      i = skipAtomic(text, i);
      continue;
    }
    if (c === '\\') {
      i += 2;
      continue;
    }
    if (c === '(') {
      paren += 1;
    } else if (c === ')') {
      if (paren > 0) paren -= 1;
    } else if (c === '[') {
      bracket += 1;
    } else if (c === ']') {
      if (bracket > 0) bracket -= 1;
    } else if (c === ':' && paren === 0 && bracket === 0) {
      return { property: text.slice(0, i).trim(), value: text.slice(i + 1).trim() };
    }
    i += 1;
  }
  return null;
};

const splitAtPrelude = (trimmed: string): AtRuleContext => {
  const body = trimmed.slice(1);
  const m = /^([-\w]+)\s*([\s\S]*)$/.exec(body);
  if (m === null) return { name: body.trim().toLowerCase(), prelude: '' };
  return { name: m[1].toLowerCase(), prelude: m[2].trim() };
};

const IMPORTANT = /!\s*important\s*$/i;

type Sink = {
  readonly styleRules: StyleRuleRecord[];
  readonly atRules: AtRuleRecord[];
  readonly declarations: DeclarationRecord[];
};

const emitDeclaration = (
  sink: Sink,
  raw: string,
  at: readonly AtRuleContext[],
  selectors: readonly string[],
  depth: number,
  offset: number,
): void => {
  const parts = splitDeclaration(raw);
  if (parts === null || parts.property.length === 0) return;
  const important = IMPORTANT.test(parts.value);
  sink.declarations.push({
    kind: 'decl',
    at,
    selector: selectors.length > 0 ? selectors[0] : '',
    selectors,
    property: parts.property,
    value: important ? parts.value.replace(IMPORTANT, '').trim() : parts.value,
    important,
    depth,
    offset,
  });
};

const skipBalancedBlock = (css: string, openBrace: number): number => {
  let i = openBrace + 1;
  let depth = 1;
  while (i < css.length) {
    const c = css[i];
    if ((c === '/' && css[i + 1] === '*') || c === '"' || c === "'") {
      i = skipAtomic(css, i);
      continue;
    }
    if (c === '\\') {
      i += 2;
      continue;
    }
    if (c === '{') depth += 1;
    else if (c === '}') {
      depth -= 1;
      if (depth === 0) return i + 1;
    }
    i += 1;
  }
  return css.length;
};

const parseBlock = (
  css: string,
  from: number,
  at: readonly AtRuleContext[],
  selectors: readonly string[],
  depth: number,
  sink: Sink,
): number => {
  let i = from;
  while (i < css.length) {
    const p = readPrelude(css, i);
    const trimmed = stripComments(p.text).trim();

    if (p.term === '}' || p.term === 'eof') {
      if (trimmed.length > 0 && depth > 0) {
        emitDeclaration(sink, trimmed, at, selectors, depth, i);
      }
      return p.term === '}' ? p.end + 1 : css.length;
    }

    if (p.term === ';') {
      if (trimmed.startsWith('@')) {
        const ctx = splitAtPrelude(trimmed);
        sink.atRules.push({
          kind: 'at',
          at,
          name: ctx.name,
          prelude: ctx.prelude,
          hasBlock: false,
          depth,
          offset: i,
        });
      } else if (trimmed.length > 0 && depth > 0) {
        emitDeclaration(sink, trimmed, at, selectors, depth, i);
      }
      i = p.end + 1;
      continue;
    }

    // p.term === '{'
    if (trimmed.startsWith('@')) {
      const ctx = splitAtPrelude(trimmed);
      sink.atRules.push({
        kind: 'at',
        at,
        name: ctx.name,
        prelude: ctx.prelude,
        hasBlock: true,
        depth,
        offset: i,
      });
      const inner: readonly AtRuleContext[] = [...at, ctx];
      const holdsRules = Object.prototype.hasOwnProperty.call(RULE_BEARING_AT_RULES, ctx.name);
      i = parseBlock(css, p.end + 1, inner, holdsRules ? [] : selectors, depth + 1, sink);
      continue;
    }

    // A custom property may carry a brace-delimited value; it is a declaration,
    // never a rule, so consume the block whole rather than descending into it.
    if (trimmed.startsWith('--')) {
      i = skipBalancedBlock(css, p.end);
      continue;
    }

    const own = splitSelectorList(trimmed);
    sink.styleRules.push({
      kind: 'style',
      at,
      selectorList: trimmed,
      selectors: own,
      depth,
      offset: i,
      parentSelectors: selectors,
    });
    i = parseBlock(css, p.end + 1, at, own, depth + 1, sink);
  }
  return i;
};

/** Depth-aware walk. At-rule nesting is carried on every record, not reconstructed. */
export const walk = (css: string): WalkResult => {
  const sink: Sink = { styleRules: [], atRules: [], declarations: [] };
  parseBlock(css, 0, [], [], 0, sink);
  return { styleRules: sink.styleRules, atRules: sink.atRules, declarations: sink.declarations };
};

export const isKeyframeFrame = (rule: StyleRuleRecord): boolean =>
  rule.at.some((a) => a.name.endsWith('keyframes'));

/**
 * The leading class of a selector: the first class name in its leftmost compound.
 * `.card .title` -> `card`; `div.x` -> `x`; `#id .y` -> null (no leading class).
 */
export const leadingClassName = (selector: string): string | null => {
  const s = selector.trim();
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    if (c === ' ' || c === '>' || c === '+' || c === '~' || c === ',') return null;
    if (c === '(' || c === '[') return null;
    if (c === '.') {
      const m = /^\.((?:[-\w]|\\.)+)/.exec(s.slice(i));
      return m === null ? null : m[1];
    }
    i += 1;
  }
  return null;
};

export const census = (css: string): Census => {
  const w = walk(css);
  const leading = new Set<string>();
  let selectorTotal = 0;
  let selectorNoFrames = 0;
  let selectorTopLevel = 0;
  for (const r of w.styleRules) {
    selectorTotal += r.selectors.length;
    if (!isKeyframeFrame(r)) selectorNoFrames += r.selectors.length;
    if (r.depth === 0 && r.at.length === 0) selectorTopLevel += r.selectors.length;
    for (const sel of r.selectors) {
      const cls = leadingClassName(sel);
      if (cls !== null) leading.add(cls);
    }
  }
  const names = [...leading].sort();
  return {
    bytes: Buffer.byteLength(css, 'utf8'),
    topLevelStyleRules: w.styleRules.filter((r) => r.depth === 0 && r.at.length === 0).length,
    styleRulesAll: w.styleRules.length,
    styleRulesExcludingKeyframeFrames: w.styleRules.filter((r) => !isKeyframeFrame(r)).length,
    atRules: w.atRules.length,
    atRulesWithBlock: w.atRules.filter((r) => r.hasBlock).length,
    atRulesTopLevel: w.atRules.filter((r) => r.depth === 0).length,
    balanceSplitSelectors: selectorTotal,
    balanceSplitSelectorsExcludingKeyframeFrames: selectorNoFrames,
    balanceSplitSelectorsTopLevel: selectorTopLevel,
    distinctLeadingClassNames: names.length,
    leadingClassNames: names,
    declarations: w.declarations.length,
  };
};
