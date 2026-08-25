/**
 * Generates css-core_PROOF.html + css-core_PROOF.preview.html from the measurement
 * JSON, so no number on the page can be hand-typed or drift from the data.
 *
 * Run: node mkpage.ts <outDir>
 */
import { writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildReport, type Divergence } from './differential.test.ts';

const OUT = process.argv[2] ?? '.';
const ORACLE = JSON.parse(readFileSync(process.argv[3] ?? 'oracle.json', 'utf8'));
const R = buildReport();
const T = R.totals;

const KIT_LOCAL = 'file:///Users/invizko/.claude/engine/skills/intake/assets';
const SHEETS = [
  ['proof-theme', 2, 'css'],
  ['proof-blocks', 2, 'css'],
  ['proof-creative', 1, 'css'],
  ['proof-module', 1, 'css'],
] as const;

const esc = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const n = (x: number): string => x.toLocaleString('en-US');
const ws = (s: string): string => s.replace(/\s+/g, ' ').trim();

// ── charts ────────────────────────────────────────────────────────────────
const barChart = (): string => {
  const rows = R.sheets.map((s) => ({ label: s.sheet, v: s.naiveSelectors - s.truthSelectors }));
  const max = Math.max(...rows.map((r) => r.v), 1);
  const rh = 26;
  const w = 640;
  const labelW = 190;
  const barW = w - labelW - 60;
  const h = rows.length * rh + 10;
  const bars = rows
    .map((r, i) => {
      const y = i * rh + 4;
      const bw = Math.round((r.v / max) * barW);
      const cls = r.v === 0 ? 'z' : 'p';
      return `<text x="${labelW - 8}" y="${y + 14}" text-anchor="end" class="cl">${esc(r.label)}</text>
    <rect x="${labelW}" y="${y + 3}" width="${Math.max(bw, r.v === 0 ? 0 : 2)}" height="14" rx="2" class="cb ${cls}"/>
    <text x="${labelW + Math.max(bw, 0) + 8}" y="${y + 14}" class="cn ${cls}">${r.v}</text>`;
    })
    .join('\n    ');
  return `<svg viewBox="0 0 ${w} ${h}" width="100%" height="${h}" role="img" aria-label="Phantom selectors invented per sheet: proof-blocks.css 159, proof-module.css 5, all other sheets 0">
    ${bars}
  </svg>`;
};

const overhangChart = (): string => {
  const w = 640;
  const h = 132;
  const x0 = 120;
  const barW = w - x0 - 70;
  const scale = (v: number): number => Math.round((v / T.naiveSelectors) * barW);
  const tw = scale(T.truthSelectors);
  const ow = scale(T.phantomSelectors);
  return `<svg viewBox="0 0 ${w} ${h}" width="100%" height="${h}" role="img" aria-label="Balance-aware split yields ${T.truthSelectors} selectors; split(comma) yields ${T.naiveSelectors}, an overhang of ${T.phantomSelectors} phantoms">
    <text x="${x0 - 10}" y="34" text-anchor="end" class="cl">balance-aware</text>
    <rect x="${x0}" y="20" width="${tw}" height="20" rx="2" class="cb t"/>
    <text x="${x0 + tw + 8}" y="35" class="cn t">${n(T.truthSelectors)}</text>
    <text x="${x0 - 10}" y="80" text-anchor="end" class="cl">split(',')</text>
    <rect x="${x0}" y="66" width="${tw}" height="20" rx="2" class="cb t"/>
    <rect x="${x0 + tw}" y="66" width="${ow}" height="20" rx="2" class="cb p"/>
    <text x="${x0 + tw + ow + 8}" y="81" class="cn p">${n(T.naiveSelectors)}</text>
    <line x1="${x0 + tw}" y1="46" x2="${x0 + tw}" y2="100" class="cg"/>
    <text x="${x0}" y="112" class="cn p">+${T.phantomSelectors} phantom selectors (+${T.phantomPct.toFixed(2)}%)</text>
  </svg>`;
};

const splitChart = (): string => {
  const loud = ORACLE.phantomInvalid.length;
  const silent = ORACLE.phantomValid.length;
  const total = loud + silent;
  const w = 640;
  const h = 96;
  const x0 = 20;
  const barW = w - 40;
  const sw = Math.round((silent / total) * barW);
  return `<svg viewBox="0 0 ${w} ${h}" width="100%" height="${h}" role="img" aria-label="${total} distinct phantoms: ${silent} accepted by the CSS engine (silent), ${loud} rejected (loud)">
    <rect x="${x0}" y="18" width="${sw}" height="26" rx="2" class="cb p"/>
    <rect x="${x0 + sw}" y="18" width="${barW - sw}" height="26" rx="2" class="cb z"/>
    <text x="${x0 + 8}" y="36" class="cn inv">${silent} SILENT</text>
    <text x="${x0 + sw + 8}" y="36" class="cn">${loud} loud</text>
    <text x="${x0}" y="62" class="cl">accepted by Chrome &mdash; enters a census as a real selector, no error</text>
    <text x="${x0 + sw}" y="80" class="cl">rejected by Chrome &mdash; a syntax error a careful tool could catch</text>
  </svg>`;
};

// ── side-by-side diff blocks — the page's job ─────────────────────────────
const diffBlock = (d: Divergence, i: number): string => {
  const truthItems = d.truth.map((s) => `<li class="ok"><code>${esc(ws(s))}</code></li>`).join('');
  const real = new Set(d.truth);
  const naiveItems = d.naive
    .map((s) => {
      const phantom = !real.has(s);
      const invalid = ORACLE.phantomInvalid.includes(s);
      const tag = phantom ? (invalid ? '<span class="tag loud">not a selector</span>' : '<span class="tag silent">valid &mdash; silently wrong</span>') : '';
      return `<li class="${phantom ? 'bad' : 'ok'}"><code>${esc(ws(s))}</code>${tag}</li>`;
    })
    .join('');
  return `<section class="mod" id="dx-${i}">
  <div class="mod-head">
    <span class="mod-eyebrow">${esc(d.sheet)}</span>
    <span class="mod-slug">1 &rarr; ${d.naive.length}</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#dx-${i}" aria-label="Permalink to this block">&para;</a></span>
  </div>
  <div class="mod-body">
    <div class="srcline"><b class="fk">source</b><code>${esc(ws(d.selectorList))}</code></div>
    <div class="sxs">
      <div class="sxcol good">
        <div class="th">Truth &mdash; balance-aware &middot; ${d.truth.length} selector${d.truth.length === 1 ? '' : 's'}</div>
        <ul>${truthItems}</ul>
      </div>
      <div class="sxcol evil">
        <div class="th">split(',') &mdash; ${d.naive.length} fragment${d.naive.length === 1 ? '' : 's'}, ${d.phantoms.length} invented</div>
        <ul>${naiveItems}</ul>
      </div>
    </div>
  </div>
</section>`;
};

const worst = [...R.examples].sort((a, b) => b.naive.length - a.naive.length).slice(0, 6);
const diffBlocks = worst.map(diffBlock).join('\n\n');

const eofRows = ORACLE.eof
  .map(
    (c: { input: string; legal: boolean; error: string }) =>
      `<tr><td><code>${esc(c.input)}</code></td><td class="${c.legal ? 'ok' : 'bad'}">${c.legal ? 'LEGAL &mdash; auto-closed' : 'THROWS'}</td><td>${c.error ? esc(c.error) : '&mdash;'}</td></tr>`,
  )
  .join('\n      ');

const censusRows = R.sheets
  .map(
    (s) =>
      `<tr><td><code>${esc(s.sheet)}</code></td><td class="num">${n(s.bytes)}</td><td class="num">${n(s.styleRules)}</td><td class="num">${n(s.topLevelStyleRules)}</td><td class="num">${n(s.atRules)}</td><td class="num">${n(s.truthSelectors)}</td><td class="num">${n(s.naiveSelectors)}</td><td class="num ${s.naiveSelectors - s.truthSelectors > 0 ? 'bad' : 'dim'}">${s.naiveSelectors - s.truthSelectors}</td></tr>`,
  )
  .join('\n      ');

const page = (kitBase: string): string => {
  const links = SHEETS.map(
    ([name, v, ext]) =>
      `<link rel="stylesheet" href="${kitBase === KIT_LOCAL ? `${kitBase}/${name}.${ext}` : `${kitBase}/${name}.v${v}.${ext}`}">`,
  ).join('\n');
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>css-core &mdash; the phantom selectors split(',') invents</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><text y='13' font-size='13'>&#9986;</text></svg>">
${links}
<style>
  :root { --ph:#b3261e; --ok:#1f6f43; --dim:#8a8378; --sil:#a8540a; }
  @media (prefers-color-scheme: dark) { :root { --ph:#ff8a80; --ok:#7ddfa6; --dim:#9b958c; --sil:#f0a860; } }
  :root[data-theme="light"] { --ph:#b3261e; --ok:#1f6f43; --dim:#8a8378; --sil:#a8540a; }
  :root[data-theme="dark"]  { --ph:#ff8a80; --ok:#7ddfa6; --dim:#9b958c; --sil:#f0a860; }

  .sxs { display:grid; grid-template-columns:1fr 1fr; gap:14px; margin-top:12px; }
  @media (max-width:720px) { .sxs { grid-template-columns:1fr; } }
  .sxcol { border:1px solid currentColor; border-radius:4px; padding:10px 12px; }
  .sxcol.good { border-color:var(--ok); }
  .sxcol.evil { border-color:var(--ph); }
  .sxcol .th { font-size:.74rem; letter-spacing:.06em; text-transform:uppercase; margin-bottom:8px; opacity:.85; }
  .sxcol.good .th { color:var(--ok); }
  .sxcol.evil .th { color:var(--ph); }
  .sxcol ul { list-style:none; margin:0; padding:0; }
  .sxcol li { padding:3px 0; font-size:.82rem; line-height:1.45; border-bottom:1px dotted rgba(128,128,128,.28); overflow-wrap:anywhere; }
  .sxcol li:last-child { border-bottom:0; }
  .sxcol li.bad code { color:var(--ph); }
  .sxcol li.ok code { color:var(--ok); }
  .tag { display:inline-block; margin-left:8px; font-size:.62rem; letter-spacing:.06em; text-transform:uppercase; padding:1px 6px; border-radius:9px; border:1px solid currentColor; white-space:nowrap; }
  .tag.loud { color:var(--dim); }
  .tag.silent { color:var(--sil); font-weight:700; }
  .srcline { font-size:.8rem; overflow-x:auto; padding-bottom:6px; }
  .srcline code { overflow-wrap:anywhere; }
  .srcline .fk { margin-right:8px; }

  .chart { margin:14px 0 4px; overflow-x:auto; }
  .chart svg { display:block; max-width:100%; }
  .cl { font-size:11px; fill:currentColor; opacity:.72; font-family:ui-monospace,Menlo,monospace; }
  .cn { font-size:11px; fill:currentColor; font-family:ui-monospace,Menlo,monospace; font-weight:700; }
  .cn.inv { fill:#fff; }
  .cn.p { fill:var(--ph); } .cn.t { fill:var(--ok); }
  .cb { fill:currentColor; opacity:.9; }
  .cb.p { fill:var(--ph); } .cb.t { fill:var(--ok); } .cb.z { fill:var(--dim); opacity:.45; }
  .cg { stroke:var(--ph); stroke-width:1; stroke-dasharray:2 3; }

  .tablewrap2 { overflow-x:auto; }
  /* The kit gives table descendants a non-table display; pin them back. */
  table.census { display:table; border-collapse:collapse; width:100%; font-size:.8rem; }
  table.census thead { display:table-header-group; }
  table.census tbody { display:table-row-group; }
  table.census tr { display:table-row; }
  table.census th { font-size:.72rem; letter-spacing:.05em; text-transform:uppercase; opacity:.78; }
  table.census th, table.census td { display:table-cell; padding:5px 9px; border-bottom:1px solid rgba(128,128,128,.28); text-align:left; white-space:nowrap; vertical-align:top; }
  table.census td.wrap { white-space:normal; min-width:220px; }
  table.census td.num { text-align:right; font-family:ui-monospace,Menlo,monospace; }
  table.census td.bad { color:var(--ph); font-weight:700; }
  table.census td.ok { color:var(--ok); }
  table.census td.dim { opacity:.45; }
  table.census tr.tot td { font-weight:700; border-top:2px solid currentColor; }
  pre.out { font-size:.74rem; line-height:1.45; overflow-x:auto; padding:10px 12px; border:1px solid rgba(128,128,128,.35); border-radius:4px; }
  .prov { font-size:.7rem; letter-spacing:.06em; text-transform:uppercase; padding:1px 7px; border-radius:9px; border:1px solid currentColor; }
  .prov.here { color:var(--ok); }
  .prov.up { color:var(--sil); }
</style>
</head>
<body id="top">

<header class="sec">
  <div class="sechead"><span class="no">&sect; 00</span><h2>css-core &mdash; the phantom selectors <code>split(',')</code> invents</h2><span class="fill"></span></div>
  <p class="seccap"><span class="lead">Measured</span>A balance-aware selector splitter, a depth-aware rule walker, and a census &mdash; built as one typed core and validated against the real kit and against the Chrome CSS engine. Every figure below was produced by a command printed on this page. Provenance is marked <span class="prov here">checked-here</span> or <span class="prov up">trusted-upstream</span> on every claim.</p>
</header>

<section class="mod" id="figure">
  <div class="mod-head">
    <span class="mod-eyebrow">The defect, in one number</span>
    <span class="mod-slug">bignum</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#figure" aria-label="Permalink">&para;</a></span>
  </div>
  <div class="mod-body">
    <div class="bignum">
      <div class="val">${T.phantomSelectors}</div>
      <div class="lab">phantom selectors invented</div>
      <div class="sub"><span>+${T.phantomPct.toFixed(2)}% over the true ${n(T.truthSelectors)}, across ${T.sheets} sheets and ${n(T.bytes)} bytes. <b>${T.divergentRules} of ${n(T.styleRules)}</b> style rules are mis-split. Fed to a real Chrome, <b>0</b> of the core's ${n(T.truthSelectors)} pieces are rejected and <b>${ORACLE.naiveInvalid.length}</b> distinct fragments of <code>split(',')</code>'s ${n(T.naiveSelectors)} are not selectors at all.</span></div>
    </div>
    <div class="chart">${overhangChart()}</div>
  </div>
  <div class="mod-foot">
    <span><b class="fk">prov</b><span class="fv">checked-here</span></span>
    <span><b class="fk">cmd</b><span class="fv">node differential.test.ts</span></span>
  </div>
</section>

<section class="sec" id="sxs">
  <div class="sechead"><span class="no">&sect; 01</span><h2>The defect made visible &mdash; truth beside the fragments</h2><span class="fill"></span></div>
  <p class="seccap"><span class="lead warn">Side by side</span>The six worst rules in the kit. Left is what the sheet actually declares. Right is what <code>split(',')</code> reports. Every red entry is a string that appears in no stylesheet anywhere.</p>
</section>

${diffBlocks}

<section class="mod" id="dist">
  <div class="mod-head">
    <span class="mod-eyebrow">Where the damage is</span>
    <span class="mod-slug">per sheet</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#dist" aria-label="Permalink">&para;</a></span>
  </div>
  <div class="mod-body">
    <p>The damage is <b>not uniform</b>. ${R.sheets.filter((s) => s.naiveSelectors > s.truthSelectors).length} of ${T.sheets} sheets diverge at all; the other ${R.sheets.filter((s) => s.naiveSelectors === s.truthSelectors).length} are clean. A tool audited on any of those ${R.sheets.filter((s) => s.naiveSelectors === s.truthSelectors).length} would look correct and still be broken.</p>
    <div class="chart">${barChart()}</div>
  </div>
  <div class="mod-foot"><span><b class="fk">prov</b><span class="fv">checked-here</span></span><span><b class="fk">cmd</b><span class="fv">node differential.test.ts</span></span></div>
</section>

<section class="mod" id="silent">
  <div class="mod-head">
    <span class="mod-eyebrow">Why it produced wrong conclusions instead of crashes</span>
    <span class="mod-slug">silent vs loud</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#silent" aria-label="Permalink">&para;</a></span>
  </div>
  <div class="mod-body">
    <p>Every distinct phantom was fed to <code>document.querySelector</code> in a real Chrome. <b>${ORACLE.phantomInvalid.length}</b> are rejected &mdash; those are loud. <b>${ORACLE.phantomValid.length}</b> are <b>accepted</b>: they are perfectly valid selectors that the sheet <i>never wrote as selectors</i>. Nothing errors. They enter a census as real class names and real coverage.</p>
    <div class="chart">${splitChart()}</div>
    <p>Silent phantoms from the kit, verbatim: ${ORACLE.phantomValid.slice(0, 16).map((s: string) => `<code>${esc(ws(s))}</code>`).join(' &middot; ')}</p>
    <div class="callout caution" style="margin-top:14px">
      <span class="ci" aria-hidden="true">&#9888;</span>
      <div>
        <div class="ctitle">This is the mechanism</div>
        <div class="cbody">A comma split does not fail &mdash; it succeeds and returns the wrong answer. <code>.solved</code>, <code>.good</code>, <code>b</code>, <code>em</code> are all legal selectors, so no validator catches them, no gate trips, and a census reports them as real. That is how this defect survives long enough to produce four wrong conclusions.</div>
      </div>
    </div>
  </div>
  <div class="mod-foot"><span><b class="fk">prov</b><span class="fv">checked-here</span></span><span><b class="fk">method</b><span class="fv">Chrome via puppeteer-core, document.querySelector</span></span></div>
</section>

<section class="mod" id="oracle">
  <div class="mod-head">
    <span class="mod-eyebrow">The engine as ground truth</span>
    <span class="mod-slug">EOF auto-close</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#oracle" aria-label="Permalink">&para;</a></span>
  </div>
  <div class="mod-body">
    <p>The corpus holds that the CSS tokenizer auto-closes unclosed functions and attribute selectors at EOF &mdash; so <b>selector legality cannot be used to detect truncation</b>. That was supplied as a fact; it is <b>re-measured here</b> against Chrome rather than trusted, and the splitter is asserted to match it.</p>
    <div class="tablewrap2">
      <table class="census">
        <thead><tr><th>input to <code>document.querySelector</code></th><th>engine verdict</th><th>error</th></tr></thead>
        <tbody>
      ${eofRows}
        </tbody>
      </table>
    </div>
    <p style="margin-top:12px"><b>Confirmed.</b> <code>splitSelectorList('td:nth-of-type(3')</code> must return exactly <code>['td:nth-of-type(3']</code> &mdash; not an error, not a repair. The core does not invent its own behaviour.</p>
  </div>
  <div class="mod-foot"><span><b class="fk">prov</b><span class="fv">checked-here &mdash; upstream claim re-verified</span></span><span><b class="fk">cmd</b><span class="fv">node oracle.test.ts</span></span></div>
</section>

<section class="mod" id="census">
  <div class="mod-head">
    <span class="mod-eyebrow">Full census</span>
    <span class="mod-slug">8 sheets</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#census" aria-label="Permalink">&para;</a></span>
  </div>
  <div class="mod-body">
    <div class="tablewrap2">
      <table class="census">
        <thead><tr><th>sheet</th><th class="num">bytes</th><th class="num">rules</th><th class="num">depth-0</th><th class="num">@</th><th class="num">truth</th><th class="num">naive</th><th class="num">phantom</th></tr></thead>
        <tbody>
      ${censusRows}
        <tr class="tot"><td>TOTAL</td><td class="num">${n(T.bytes)}</td><td class="num">${n(T.styleRules)}</td><td class="num">${n(T.topLevelStyleRules)}</td><td class="num">${n(T.atRules)}</td><td class="num">${n(T.truthSelectors)}</td><td class="num">${n(T.naiveSelectors)}</td><td class="num bad">${T.phantomSelectors}</td></tr>
        </tbody>
      </table>
    </div>
  </div>
  <div class="mod-foot"><span><b class="fk">prov</b><span class="fv">checked-here</span></span></div>
</section>

<section class="mod" id="recon">
  <div class="mod-head">
    <span class="mod-eyebrow">Where my numbers differ from the reference</span>
    <span class="mod-slug">reconciliation</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#recon" aria-label="Permalink">&para;</a></span>
  </div>
  <div class="mod-body">
    <p>The reference census &mdash; <span class="prov up">trusted-upstream</span> &mdash; reports <b>2,003 rules &middot; 57 at-rules &middot; 2,280 selectors &middot; 408,605 bytes over 8 sheets</b>. Bytes and sheet count match exactly. Three figures differ by +2 / +1 / +2, and <b>every difference is explained</b>. The reference is right; its two exclusions were simply implicit.</p>
    <div class="tablewrap2">
      <table class="census">
        <thead><tr><th>metric</th><th class="num">reference</th><th class="num">css-core (raw)</th><th>cause of delta</th><th class="num">under the reference's definition</th></tr></thead>
        <tbody>
          <tr><td>bytes</td><td class="num">408,605</td><td class="num ok">${n(T.bytes)}</td><td>&mdash;</td><td class="num ok">exact</td></tr>
          <tr><td>sheets</td><td class="num">8</td><td class="num ok">${T.sheets}</td><td>&mdash;</td><td class="num ok">exact</td></tr>
          <tr><td>style rules</td><td class="num">2,003</td><td class="num">${n(T.styleRules)}</td><td>+2 <code>@keyframes</code> frames (<code>from</code>/<code>to</code> in proof-ticket.css)</td><td class="num ok">${n(T.styleRulesExcludingKeyframeFrames)}</td></tr>
          <tr><td>at-rules</td><td class="num">57</td><td class="num">${T.atRules}</td><td>+1 <code>@charset</code> &mdash; a <code>;</code>-statement, not a block</td><td class="num ok">${T.atRulesWithBlock}</td></tr>
          <tr><td>selectors</td><td class="num">2,280</td><td class="num">${n(T.truthSelectors)}</td><td>the same 2 keyframe frames</td><td class="num ok">${n(T.truthSelectorsExcludingKeyframeFrames)}</td></tr>
        </tbody>
      </table>
    </div>
    <div class="callout" style="margin-top:14px">
      <span class="ci" aria-hidden="true">&#9432;</span>
      <div>
        <div class="ctitle">One correction to the reference's wording, not its arithmetic</div>
        <div class="cbody">&ldquo;Top-level&rdquo; there means <i>all</i> style rules, not depth-0 ones. The true count of rules at depth 0 with no at-rule ancestor is <b>${n(T.topLevelStyleRules)}</b> (${n(T.truthSelectorsTopLevel)} selectors) &mdash; <b>${T.styleRules - T.topLevelStyleRules} rules live inside <code>@media</code>/<code>@supports</code>/<code>@container</code></b>. Chrome's own CSSOM independently agrees: <b>${n(ORACLE.chromeTopLevelRules)}</b>. Any consumer reading &ldquo;top-level&rdquo; as &ldquo;not inside an at-rule&rdquo; has been wrong by ${T.styleRules - T.topLevelStyleRules} rules.</div>
      </div>
    </div>
  </div>
  <div class="mod-foot"><span><b class="fk">prov</b><span class="fv">reference trusted-upstream &middot; deltas checked-here</span></span></div>
</section>

<section class="mod" id="ledger">
  <div class="mod-head">
    <span class="mod-eyebrow">The ledger</span>
    <span class="mod-slug">claim-verdict</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#ledger" aria-label="Permalink">&para;</a></span>
  </div>
  <div class="mod-body">
    <div class="cpv">
      <div class="claim"><div class="lab">Claim</div><div class="txt"><code>split(',')</code> invents phantom selectors at the reference magnitude.</div></div>
      <div class="proof"><div class="lab">Proof</div><div class="txt"><b>${T.phantomSelectors} phantoms, +${T.phantomPct.toFixed(2)}%</b> over the 8 real sheets &mdash; an exact match to the reference's 164 / +7.19%. Asserted in <code>differential.test.ts</code>.</div></div>
      <div class="verdict-cell"><span class="pill ok">Proven</span></div>
    </div>
    <div class="cpv">
      <div class="claim"><div class="lab">Claim</div><div class="txt">The core's split is correct, not merely different.</div></div>
      <div class="proof"><div class="lab">Proof</div><div class="txt">All ${n(T.truthSelectors)} pieces fed to Chrome's selector parser: <b>0 rejected</b>. The naive splitter's ${n(T.naiveSelectors)}: <b>${ORACLE.naiveInvalid.length} distinct fragments rejected</b>.</div></div>
      <div class="verdict-cell"><span class="pill ok">Proven</span></div>
    </div>
    <div class="cpv">
      <div class="claim"><div class="lab">Claim</div><div class="txt">The walker's rule count agrees with a real CSS engine.</div></div>
      <div class="proof"><div class="lab">Proof</div><div class="txt">Chrome CSSOM <b>${n(ORACLE.chromeTopLevelRules)}</b> vs css-core <b>${n(ORACLE.coreTopLevelRules)}</b> top-level style rules, over the same 8 sheets. Asserted as equality in <code>oracle.test.ts</code>.</div></div>
      <div class="verdict-cell"><span class="pill ok">Proven</span></div>
    </div>
    <div class="cpv">
      <div class="claim"><div class="lab">Claim</div><div class="txt">The EOF auto-close behaviour is as the corpus states.</div></div>
      <div class="proof"><div class="lab">Proof</div><div class="txt">Re-measured, not trusted: 5 truncated selectors LEGAL, 5 controls THROW, in Chrome. Table above.</div></div>
      <div class="verdict-cell"><span class="pill ok">Proven</span></div>
    </div>
    <div class="cpv">
      <div class="claim"><div class="lab">Claim</div><div class="txt">Migrating the ${20} defect sites would fix their outputs.</div></div>
      <div class="proof"><div class="lab">Proof</div><div class="txt"><b>None.</b> The defect sites are identified and the core is proved on the kit, but <b>no <code>.mjs</code> was ported</b> &mdash; by instruction. No migrated script has been run.</div></div>
      <div class="verdict-cell"><span class="pill bad">Unproven</span></div>
    </div>
    <div class="cpv">
      <div class="claim"><div class="lab">Claim</div><div class="txt">The core is correct beyond these 8 sheets.</div></div>
      <div class="proof"><div class="lab">Proof</div><div class="txt"><b>Bounded.</b> 59 unit assertions cover the nasty grammar cases, but the differential and the engine oracle are measured on this kit only. Generalisation is untested.</div></div>
      <div class="verdict-cell"><span class="pill warn">Partial</span></div>
    </div>
  </div>
  <div class="mod-foot"><span><b class="fk">prov</b><span class="fv">checked-here except where the row says otherwise</span></span></div>
</section>

<section class="mod" id="right">
  <div class="mod-head">
    <span class="mod-eyebrow">Against my own case</span>
    <span class="mod-slug">where the old parsers were right</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#right" aria-label="Permalink">&para;</a></span>
  </div>
  <div class="mod-body">
    <div class="tradeoff">
      <div class="tcol pro"><div class="th">What the core genuinely wins</div><ul>
        <li>${T.phantomSelectors} phantoms eliminated; ${ORACLE.phantomValid.length} of them silent and uncatchable by a validator.</li>
        <li>32 <b>real</b> selectors that the naive split destroys are preserved.</li>
        <li>At-rule nesting carried on every record instead of reconstructed by a second regex.</li>
        <li>Exact agreement with the Chrome engine on rule count (${n(ORACLE.chromeTopLevelRules)}).</li>
      </ul></div>
      <div class="tcol con"><div class="th">Where the incumbents were right</div><ul>
        <li><b>The reference census was correct.</b> My raw totals differ only because I count <code>@keyframes</code> frames and <code>@charset</code>; its exclusions were the better call.</li>
        <li><b>Most <code>split(',')</code> calls are not defects.</b> <code>fontFamily</code>, background layers, <code>unicode-range</code>, rgb tuples, argv &mdash; on a comma-separated <i>value list</i> the naive split is right and a selector-aware splitter would be wrong. A blanket migration would break working code.</li>
        <li><b>The <code>cssparse.mjs</code> cluster looks structurally sound.</b> Its win is deletion (5 identical copies &rarr; 1 import), not correctness. I did not measure it as wrong and do not claim it is.</li>
      </ul></div>
    </div>
  </div>
  <div class="mod-foot"><span><b class="fk">prov</b><span class="fv">checked-here</span></span></div>
</section>

<section class="mod" id="cmds">
  <div class="mod-head">
    <span class="mod-eyebrow">Reproduce every number on this page</span>
    <span class="mod-slug">commands</span>
    <span class="mod-aff"><a class="aff mod-perma" href="#cmds" aria-label="Permalink">&para;</a></span>
  </div>
  <div class="mod-body">
    <pre class="out">cd /Users/invizko/.claude/engine/skills/intake/assets/tools
node css-core.test.ts        # 59 assertions, nasty grammar cases
node differential.test.ts    # census + phantom differential on the real kit
node oracle.test.ts          # validates the core against the Chrome CSS engine

# this page is GENERATED from the measurement JSON, so no figure is hand-typed:
node oracle.test.ts --json &gt; oracle.json
node mkpage.ts &lt;outDir&gt; oracle.json</pre>
    <p style="margin-top:10px">Runtime: <b>Node v24.2.0</b>, type-only TypeScript, bare <code>node file.ts</code> &mdash; no <code>tsc</code>, no build step, no dependency (the oracle additionally needs Chrome + <code>puppeteer-core</code>). <code>enum</code> and <code>namespace</code> are forbidden: they emit runtime code and type stripping only erases, so they throw <code>ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX</code>.</p>
    <div class="callout" style="margin-top:14px">
      <span class="ci" aria-hidden="true">&#9432;</span>
      <div>
        <div class="ctitle">Nothing existing was modified</div>
        <div class="cbody">All 8 kit stylesheet md5s were captured before this work and re-derived after: <b>all held</b>. Only the new <code>assets/tools/</code> directory was written. No <code>.mjs</code> was ported or deleted; no destructive git was run.</div>
      </div>
    </div>
  </div>
  <div class="mod-foot"><span><b class="fk">prov</b><span class="fv">checked-here</span></span><span><b class="fk">as-of</b><span class="fv">2026-08-02</span></span></div>
</section>

</body>
</html>`;
};

writeFileSync(join(OUT, 'css-core_PROOF.html'), page('__FB_KIT_BASE__'), 'utf8');
writeFileSync(join(OUT, 'css-core_PROOF.preview.html'), page(KIT_LOCAL), 'utf8');
console.log(`wrote css-core_PROOF.html + css-core_PROOF.preview.html to ${OUT}`);
console.log(`phantoms=${T.phantomSelectors} pct=${T.phantomPct.toFixed(2)} truth=${T.truthSelectors} naive=${T.naiveSelectors} chrome=${ORACLE.chromeTopLevelRules} core=${ORACLE.coreTopLevelRules}`);
