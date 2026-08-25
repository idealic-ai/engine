/* shoot.mjs — render css-core_PROOF.preview.html and take ELEMENT shots only.
 *
 * Discipline (session rule): DPR 1, element shots only, never fullPage above ~7,900 CSS px.
 * The document height is printed so the shot NOT taken is on the record.
 *
 * usage: node shoot.mjs <pagePath> <outDir>
 */
import puppeteer from '/Users/invizko/Projects/finch/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PAGE = process.argv[2];
const OUT = process.argv[3];
const SETTLE = 450;

const TARGETS = [
  ['figure', '#figure'],
  ['sidebyside-worst', '#dx-0'],
  ['distribution', '#dist'],
  ['silent-vs-loud', '#silent'],
  ['oracle-eof', '#oracle'],
  ['census', '#census'],
  ['reconciliation', '#recon'],
  ['ledger', '#ledger'],
  ['old-parsers-right', '#right'],
];

mkdirSync(OUT, { recursive: true });

const browser = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--no-sandbox', '--force-device-scale-factor=1'] });
const written = [];
const heights = {};

for (const [w, h] of [[1400, 1000], [390, 844]]) {
  for (const theme of ['light', 'dark']) {
    const page = await browser.newPage();
    await page.setViewport({ width: w, height: h, deviceScaleFactor: 1 });
    await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: theme }]);
    await page.goto(`file://${PAGE}`, { waitUntil: 'networkidle0' });
    await page.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
    await new Promise((r) => setTimeout(r, SETTLE));

    const docH = await page.evaluate(() => document.documentElement.scrollHeight);
    heights[`${w}-${theme}`] = docH;

    // Sheet-loading proof: if the kit never resolved, the page is unstyled and
    // the shots are worthless. Measure a property only the kit sets.
    const styled = await page.evaluate(() => {
      const el = document.querySelector('.mod');
      if (el === null) return 'no .mod';
      const cs = getComputedStyle(el);
      return `${cs.fontFamily.slice(0, 28)} | bg=${cs.backgroundColor} | pad=${cs.paddingTop}`;
    });

    for (const [label, sel] of TARGETS) {
      const el = await page.$(sel);
      if (el === null) { console.log(`  MISSING ${sel}`); continue; }
      const box = await el.boundingBox();
      if (box === null || box.height < 4) { console.log(`  ZERO-BOX ${sel}`); continue; }
      const file = join(OUT, `${label}-${w}-${theme}.png`);
      await el.screenshot({ path: file });
      written.push({ file, sel, w, theme, h: Math.round(box.height) });
    }
    console.log(`${w}px ${theme}: docHeight=${docH}px  styled? ${styled}`);
    await page.close();
  }
}

await browser.close();
console.log(`\nWROTE ${written.length} element shots`);
for (const s of written) console.log(`  ${s.file}  (${s.sel}, elH=${s.h}px)`);
console.log(`\nDOC HEIGHTS: ${JSON.stringify(heights)}`);
const over = Object.entries(heights).filter(([, v]) => v > 7900);
console.log(over.length > 0
  ? `fullPage DELIBERATELY NOT TAKEN at: ${over.map(([k, v]) => `${k}=${v}px`).join(', ')} (>7900px scrambles)`
  : 'all doc heights under 7900px; fullPage still not taken — element shots are the discipline');
