/* Layout guards — the two composition failures the kit now absorbs instead of trusting authors
 * to avoid, checked the way they were found: in a real browser, from computed layout.
 *
 *   1. A composed page lands a catalog class on the SAME element as `.mod` (`class="mod scope
 *      slot-full"`). The catalog root's own `display` re-lays mod-head/body/foot as ITS cells:
 *      the body crushes to a sliver, the head strands alone in a blank column. Three sections of
 *      one published board shipped that way. `.mod.mod` in proof-blocks.css now outspecifies
 *      every bare catalog rule, so the scaffold wins — and this asserts the guard holds for EVERY
 *      class in the kit that sets a display, including ones added after it was written.
 *
 *   2. The head row starved its title: one wrappable child among several nowrap badges absorbed
 *      all the shrink and crushed to two words a line. The head is a wrapping line with a named
 *      title floor now. The property asserted here is the one no media query can hold: two heads
 *      at the SAME width must get opposite answers — the crowded one wraps its rail off, the
 *      sparse one does not — because the break is content-driven, not width-driven.
 *
 *   4. A row-list stated its columns on the ROW instead of on the list, so every row sized column
 *      one to its own content and the column staggered — five times across four blocks before it
 *      was named as a grammar rule rather than four authors' bad luck. The list owns the tracks
 *      and the row takes `subgrid`; and it ships as a PAIR, because tracks alone leave every bare
 *      badge stretched to the widest one. Checks 11-13 own that family: 11 names row-lists still
 *      declaring their own tracks, 12 asserts the companion, 13 states the same failure on the
 *      flow axis (distance stated per pair, so the missing pair is always the one nobody wrote).
 *
 *   3. A page authored an inline `<svg class="fdot" viewBox="0 0 14 14">` with no width and no
 *      height attribute, against a class no stylesheet defines. The UA default for an inline SVG
 *      is width:100%/height:100%, so a 14px freshness dot rendered at 404x404 and stretched its
 *      grid row to 2169px. There is no discriminator that separates "an indicator that forgot its
 *      size" from "a figure that means to be full width" — both are a viewBox and no size — so
 *      the CSS side can only make the FAILURE cheap, never impossible. What is checkable is the
 *      pair of properties that must survive any such default: an SVG that declares a size (by
 *      attribute, or through a kit class that sizes it) is never touched, and an SVG that
 *      declares none does not render at container scale.
 *
 * Sibling checkers: contract-sync.test.mjs (cross-file documentation agreement) and
 * board-widgets.test.mjs (behaviour). This one owns rendered layout.
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/__tests__/layout-guards.test.mjs
 *       ... --scan <page.html>   lint a composed board for the doubled-class defect
 */
import assert from "node:assert";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const intake = path.join(here, "..");
const read = (p) => fs.readFileSync(p, "utf8");

/* proof-theme.css first: it carries the tokens the others resolve against, and a rule whose
   value fails to resolve is a rule that silently does not apply. */
const KIT_CSS = ["proof-theme.css", "proof-blocks.css", "proof-creative.css", "board-widgets.css", "board-warm-overrides.css"];
const blocks = read(path.join(intake, "proof-blocks.css"));

let checks = 0;
const pending = [];
const check = (msg, fn) => { fn(); checks++; };

/* An indicator that omits its size should end up near text-size, never near container-size.
   The bound is deliberately loose: this separates "small" from "runaway", not px from px. */
const SVG_INDICATOR_MAX = 64;

/* ---- The hazard set: every class whose BARE selector sets a display of its own ----
   Derived from the stylesheets rather than listed here, so a catalog class added tomorrow is
   covered tomorrow. @media blocks are stripped: the kit's only responsive declarations are
   track counts, and a width-conditional display would not be checkable at one fixture width. */
function hazardClasses() {
  const map = new Map();
  for (const file of KIT_CSS) {
    const css = read(path.join(intake, file))
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/@media[^{]*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}/g, "");
    for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const decl = /(?:^|;|\s)display\s*:\s*([a-z-]+)/.exec(m[2]);
      if (!decl) continue;
      for (const sel of m[1].split(",").map((s) => s.trim())) {
        const one = /^\.([a-zA-Z][\w-]*)$/.exec(sel);
        if (one && one[1] !== "mod") map.set(one[1], decl[1]);   // last rule wins, as in the cascade
      }
    }
  }
  return map;
}
const HAZARDS = hazardClasses();

/* ---- Which SVGs has the kit already taken responsibility for sizing? ----
   Derived from the stylesheets for the same reason the hazard set is: a family added tomorrow
   (`.figsvg`, `.spark`, `.arrsvg`, whatever comes next) must not become a false positive the day
   it lands. A class some kit rule gives a width or height to is a DECLARED intention and is
   never reported; a class nothing sizes is an omission. Erring toward silence is deliberate —
   this lint should never argue with a stylesheet. */
function svgSizedClasses() {
  const set = new Set();
  for (const file of KIT_CSS) {
    const css = read(path.join(intake, file)).replace(/\/\*[\s\S]*?\*\//g, "");
    for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      if (!/(?:^|;|\s)(?:width|height|max-width|max-height|block-size|inline-size)\s*:/.test(m[2])) continue;
      for (const cls of m[1].matchAll(/\.([a-zA-Z][\w-]*)/g)) set.add(cls[1]);
    }
  }
  return set;
}
const SVG_SIZED = svgSizedClasses();

/* Elements that never open a scope, so the containment stack does not go out of sync on markup
   that omits the closing tag (and on the SVG shape children that sit inside the tag we care about). */
const VOID_TAGS = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
  "source", "track", "wbr", "circle", "ellipse", "line", "path", "polygon", "polyline", "rect", "stop", "use"]);

/* Walk the tag stream keeping a real ancestor stack, so "inside a .mod" is answered by
   containment rather than by proximity in the byte stream. */
function scanSvgHtml(file) {
  const src = read(file);
  const stack = [];
  const offenders = [];
  for (const m of src.matchAll(/<(\/?)([a-zA-Z][a-zA-Z0-9]*)\b([^>]*?)(\/?)>/g)) {
    const [, closing, rawTag, attrs, selfClosed] = m;
    const tag = rawTag.toLowerCase();
    if (closing) {
      for (let i = stack.length - 1; i >= 0; i--) if (stack[i].tag === tag) { stack.length = i; break; }
      continue;
    }
    const cls = (/\bclass="([^"]*)"/i.exec(attrs) || [, ""])[1].split(/\s+/).filter(Boolean);
    const id = (/\bid="([^"]+)"/i.exec(attrs) || [, null])[1];
    if (tag === "svg") {
      const host = [...stack].reverse().find((e) => e.cls.includes("mod"));
      const declaresSize = /\bwidth\s*=/i.test(attrs) || /\bheight\s*=/i.test(attrs);
      const kitSizes = cls.some((c) => SVG_SIZED.has(c));
      if (host && !declaresSize && !kitSizes) {
        const vb = (/\bviewBox="([^"]*)"/i.exec(attrs) || [, "none"])[1];
        offenders.push(`<svg${cls.length ? ` class="${cls.join(" ")}"` : ""} viewBox="${vb}"> in .mod${host.id ? "#" + host.id : ""}`
          + ` — no width/height attribute, and no kit rule sizes ${cls.length ? `.${cls.join("/.")}` : "a bare svg here"};`
          + " the UA default is 100% of its container");
      }
    }
    if (!selfClosed && !VOID_TAGS.has(tag)) stack.push({ tag, cls, id });
  }
  return offenders;
}

/* ---- 1. The guard exists, and is not a list that will rot ----
   An enumerated `.mod.scope, .mod.callout, ...` guard is a maintenance trap: the class added
   next month is unguarded and nothing says so. Doubling `.mod` carries the same specificity
   against every bare catalog rule in every file, named or not. */
check("the scaffold guard is present and class-agnostic", () => {
  assert.ok(HAZARDS.size > 40, `expected the kit's catalog to set display on many classes, found ${HAZARDS.size}`);
  const g = /\.mod\.mod\s*\{([^}]*)\}/.exec(blocks);
  assert.ok(g, ".mod.mod guard is gone from proof-blocks.css — a doubled catalog class re-lays the scaffold as its own grid");
  for (const prop of ["display", "min-width", "padding", "margin"]) {
    assert.ok(new RegExp(`(^|;)\\s*${prop}\\s*:`).test(g[1]),
      `the guard no longer neutralizes ${prop} — a catalog root still reaches the scaffold through it`);
  }
  assert.ok(/revert/.test(g[1]),
    "the guard hardcodes values instead of reverting — a lone .mod would then be styled by the guard, not by .mod");
  const listed = [...HAZARDS.keys()].filter((c) => new RegExp(`\\.mod\\.${c}\\b`).test(blocks));
  assert.deepStrictEqual(listed, [],
    `the guard names catalog classes (${listed.join(", ")}) — a per-class list silently misses the next one added`);
});

/* ---- 2. The head line states its own grammar ---- */
check("the head line wraps and names a title floor", () => {
  const h = /(?:^|\n)\.mod-head\s*\{([^}]*)\}/m.exec(blocks);
  assert.ok(h, ".mod-head rule is missing");
  assert.ok(/flex-flow\s*:\s*row\s+wrap|flex-wrap\s*:\s*wrap/.test(h[1]),
    ".mod-head no longer wraps — the rail then starves the title instead of dropping to its own line");
  assert.ok(/--head-title-min\s*:/.test(h[1]), ".mod-head declares no title floor");
  assert.ok(/\.mod-head\s*>\s*\.mod-title\s*\{[^}]*var\(--head-title-min\)/.test(blocks),
    "the title role does not consume the floor it is given");
});

/* ---- 3. No width query pretends to protect the head ----
   The board this fixed carried `@media (max-width:640px){.dectitle{flex-basis:100%}}` — a
   fallback wired to a width no desktop or tablet reaches, which reads as protection and is
   dead. The wrap is content-driven; a width-conditional head rule here would be the same lie. */
check("no dead breakpoint guards the head", () => {
  for (const m of blocks.matchAll(/@media[^{]*\{((?:[^{}]*\{[^{}]*\})*[^{}]*)\}/g)) {
    assert.ok(!/\.mod-head|\.mod-title/.test(m[1]),
      `a @media block styles the head (${m[0].slice(0, 60)}...) — heads at the same width need different answers, so a width query cannot be right`);
  }
});

/* ---- 4. Composed pages: `.mod` + a display-setting catalog class on one element ----
   The authoring lint. Kit-owned skeletons must be clean; --scan takes any board. */
function scanHtml(file) {
  const src = read(file);
  const offenders = [];
  for (const m of src.matchAll(/<([a-z][a-z0-9]*)\b[^>]*\bclass="([^"]*)"[^>]*>/gi)) {
    const cls = m[2].split(/\s+/).filter(Boolean);
    if (!cls.includes("mod")) continue;
    const doubled = cls.filter((c) => HAZARDS.has(c));
    if (!doubled.length) continue;
    const id = /\bid="([^"]+)"/.exec(m[0]);
    offenders.push(`${m[1]}.mod.${doubled.join(".")}${id ? "#" + id[1] : ""}  [${doubled.map((c) => `.${c} sets display:${HAZARDS.get(c)}`).join("; ")}]`);
  }
  return offenders;
}

check("kit-owned skeletons carry no doubled catalog class", () => {
  const dir = path.join(intake, "skeletons");
  for (const f of fs.readdirSync(dir).filter((f) => f.endsWith(".html"))) {
    const bad = scanHtml(path.join(dir, f));
    assert.deepStrictEqual(bad, [], `skeletons/${f} doubles a catalog class onto .mod:\n  ${bad.join("\n  ")}`);
  }
});

/* ---- 4b. Composed pages: an inline SVG inside `.mod` that declares no size ---- */
check("kit-owned skeletons carry no unsized inline SVG inside a .mod", () => {
  const dir = path.join(intake, "skeletons");
  for (const f of fs.readdirSync(dir).filter((f) => f.endsWith(".html"))) {
    const bad = scanSvgHtml(path.join(dir, f));
    assert.deepStrictEqual(bad, [], `skeletons/${f} leaves an inline SVG unsized inside .mod:\n  ${bad.join("\n  ")}`);
  }
});

/* ---- 5–8. Computed layout, in a real browser ----
   Static text cannot tell you a guard WORKS; the defect was found by looking, so it is checked
   by looking. Same approach as the elevation audit. */
const CHROME = process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PUPPETEER = [
  "/Users/invizko/Projects/finch/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js",
  path.join(intake, "..", "..", "..", "node_modules", "puppeteer-core", "lib", "esm", "puppeteer", "puppeteer-core.js"),
].find((p) => fs.existsSync(p));

if (process.env.LAYOUT_GUARDS_NO_DOM === "1") {
  console.log("layout-guards.test: DOM checks SKIPPED by LAYOUT_GUARDS_NO_DOM=1");
} else {
  assert.ok(PUPPETEER, "puppeteer-core not found — set LAYOUT_GUARDS_NO_DOM=1 to run the static half only");
  assert.ok(fs.existsSync(CHROME), `no Chrome at ${CHROME} — set CHROME_PATH, or LAYOUT_GUARDS_NO_DOM=1 for the static half only`);
  const { default: puppeteer } = await import(PUPPETEER);

  const css = KIT_CSS.map((f) => `<style>${read(path.join(intake, f))}</style>`).join("\n");
  const cases = [...HAZARDS.keys()];
  const fixture = `<!doctype html><html data-theme="light"><head>${css}</head><body><div class="sheet">
    ${cases.map((c, i) => `
      <div class="probe-alone" data-c="${c}"><div class="${c}">x</div></div>
      <section class="mod ${c}" data-c="${c}" id="dbl-${i}">
        <div class="mod-head"><span class="mod-title">Title</span><span class="mod-aff">rail</span></div>
        <div class="mod-body"><p>body</p></div><div class="mod-foot"><span>foot</span></div>
      </section>`).join("")}
    <section class="mod" id="plain"><div class="mod-head"><span class="mod-title">T</span></div><div class="mod-body"><p>b</p></div></section>
    <section class="mod" id="plain2"><div class="mod-body"><p>b</p></div></section>
    <section class="mod flat" id="flat"><div class="mod-head"><span class="mod-title">T</span></div><div class="mod-body"><p>b</p></div></section>
    <section class="mod open" id="open"><div class="mod-head"><span class="mod-title">T</span></div><div class="mod-body"><p>b</p></div></section>
    <section class="mod" id="crowded"><div class="mod-head">
      <span class="n" style="flex:0 0 auto;width:26px">7</span>
      <span class="mod-title">Pending-claim visibility — 351 invisible claims, but the fix may be shipping already</span>
      <span style="white-space:nowrap">open · never triaged</span>
      <span style="white-space:nowrap">🔵 Feature &amp; capability requirements</span>
      <span class="mod-aff"><span class="affgroup"><span class="affseg">Evidence·2</span><span class="affseg">Tickets·3</span><span class="affseg">Origin</span></span></span>
    </div><div class="mod-body"><p>b</p></div></section>
    <section class="mod" id="svg-omitted"><div class="mod-body">
      <svg viewBox="0 0 14 14"><circle cx="7" cy="7" r="5" fill="none" stroke="currentColor" stroke-width="2"/></svg>
    </div></section>
    <section class="mod" id="svg-attrsized"><div class="mod-body">
      <svg viewBox="0 0 120 14" width="88" height="14"><rect x="0" y="0" width="120" height="14"/></svg>
    </div></section>
    <section class="mod" id="svg-figure"><div class="mod-body"><div class="fam-annotated">
      <svg class="figsvg" viewBox="0 0 600 200"><rect x="0" y="0" width="600" height="200"/></svg>
    </div></div></section>
    <section class="mod" id="sparse"><div class="mod-head">
      <span class="n" style="flex:0 0 auto;width:26px">8</span>
      <span class="mod-title">Pool B — wave 2's un-dispositioned candidates</span>
      <span style="white-space:nowrap">unpolled</span>
      <span class="mod-aff"><span class="affgroup"><span class="affseg">Evidence·2</span></span></span>
    </div><div class="mod-body"><p>b</p></div></section>
  </div></body></html>`;

  const browser = await puppeteer.launch({ executablePath: CHROME, headless: "shell" });
  const page = await browser.newPage();
  await page.setViewport({ width: 1400, height: 1000 });
  await page.setContent(fixture, { waitUntil: "load" });
  const probe = await page.evaluate((cases) => {
    const cs = (el) => getComputedStyle(el);
    const out = { alone: {}, doubled: {}, variants: {}, head: {} };
    for (const c of cases) {
      out.alone[c] = cs(document.querySelector(`.probe-alone[data-c="${c}"] > *`)).display;
      const d = document.querySelector(`section.mod[data-c="${c}"]`);
      const s = cs(d);
      const head = d.querySelector(":scope > .mod-head").getBoundingClientRect();
      const body = d.querySelector(":scope > .mod-body").getBoundingClientRect();
      out.doubled[c] = {
        display: s.display, minWidth: s.minWidth, padTop: s.paddingTop, padLeft: s.paddingLeft,
        stacked: head.bottom <= body.top + 1,
        bodyRatio: +(body.width / d.getBoundingClientRect().width).toFixed(3),
      };
    }
    const g = (id) => { const e = document.getElementById(id); const s = cs(e); return { display: s.display, padLeft: s.paddingLeft, padTop: s.paddingTop, marginTop: s.marginTop, bg: s.backgroundColor, borderLeft: s.borderLeftWidth, radius: s.borderTopLeftRadius }; };
    out.variants = { plain: g("plain"), plain2: g("plain2"), flat: g("flat"), open: g("open") };
    for (const id of ["crowded", "sparse"]) {
      const h = document.querySelector(`#${id} > .mod-head`);
      const t = h.querySelector(".mod-title").getBoundingClientRect();
      const rail = h.querySelector(".mod-aff").getBoundingClientRect();
      out.head[id] = { titleW: +t.width.toFixed(1), railWrapped: rail.top > t.bottom - 2, headH: +h.getBoundingClientRect().height.toFixed(1) };
    }
    const svgBox = (sel) => {
      const e = document.querySelector(sel);
      if (!e) return null;
      const b = e.getBoundingClientRect();
      const host = e.closest(".mod-body").getBoundingClientRect();
      return { w: +b.width.toFixed(1), h: +b.height.toFixed(1), hostW: +host.width.toFixed(1) };
    };
    out.svg = {
      omitted: svgBox("#svg-omitted svg"),
      attrSized: svgBox("#svg-attrsized svg"),
      figure: svgBox("#svg-figure svg.figsvg"),
    };
    return out;
  }, cases);
  await browser.close();

  /* ---- 5. Every hazard class still behaves exactly as itself when used ALONE ---- */
  check("no catalog class is changed by the guard when used alone", () => {
    const drift = [...HAZARDS.entries()].filter(([c, want]) => probe.alone[c] !== want)
      .map(([c, want]) => `.${c}: declares display:${want}, renders ${probe.alone[c]}`);
    assert.deepStrictEqual(drift, [], `the guard leaked onto bare catalog classes:\n  ${drift.join("\n  ")}`);
  });

  /* ---- 6. Doubled onto `.mod`, every one of them is structurally harmless ---- */
  check("a doubled catalog class cannot re-lay the scaffold", () => {
    const bad = [];
    for (const [c, r] of Object.entries(probe.doubled)) {
      if (r.display !== "block") bad.push(`section.mod.${c} computes display:${r.display} — the scaffold is being laid out by .${c}`);
      else if (!r.stacked) bad.push(`section.mod.${c} does not stack head above body`);
      else if (r.bodyRatio < 0.9) bad.push(`section.mod.${c} squeezes the body to ${(r.bodyRatio * 100).toFixed(0)}% of the card`);
      else if (r.padTop !== "0px" || r.padLeft !== "0px") bad.push(`section.mod.${c} inherits padding ${r.padTop}/${r.padLeft} from .${c}, insetting the head band`);
      else if (r.minWidth !== "auto" && r.minWidth !== "0px") bad.push(`section.mod.${c} inherits min-width ${r.minWidth} from .${c}`);
    }
    assert.deepStrictEqual(bad, [], `${bad.length} of ${Object.keys(probe.doubled).length} doubled classes still reach the scaffold:\n  ${bad.slice(0, 12).join("\n  ")}`);
  });

  /* ---- 7. A lone `.mod`, and its variants, are untouched by the guard ----
     `revert` in the guard is what buys this; literal values would have re-stated .mod's paint
     and quietly overridden .mod.flat / .mod.open, which sit at the same specificity. */
  check("a lone .mod and its variants are unchanged", () => {
    const v = probe.variants;
    assert.strictEqual(v.plain.display, "block", "a lone .mod no longer renders as a block");
    assert.strictEqual(v.plain.padTop, "0px", "the guard gave a lone .mod padding of its own");
    assert.strictEqual(v.plain2.marginTop, "26px", "`.mod + .mod` rhythm lost — the guard's margin revert is overriding the sibling rule");
    assert.strictEqual(v.flat.bg, "rgba(0, 0, 0, 0)", ".mod.flat is no longer transparent — the guard is overriding the variant");
    assert.ok(parseFloat(v.open.borderLeft) >= 3, ".mod.open lost its accent spine");
    assert.strictEqual(v.open.padLeft, "2px", ".mod.open lost its padding — the guard's padding revert is winning over the variant");
  });

  /* ---- 8. The head wraps on CONTENT, which is the whole point ----
     Both heads are measured at the same viewport width, so a width query could not produce
     these two answers. The crowded head must give its title a readable measure; the sparse one
     must be left exactly alone. */
  check("the crowded head wraps its rail and the sparse head does not", () => {
    assert.ok(probe.head.crowded.railWrapped,
      `a head with three nowrap badges did not drop its rail (title got ${probe.head.crowded.titleW}px) — the title is absorbing the shrink again`);
    assert.ok(probe.head.crowded.titleW >= 300,
      `crowded head title measured ${probe.head.crowded.titleW}px, below the floor`);
    assert.ok(!probe.head.sparse.railWrapped,
      "a head that fits wrapped its rail anyway — the wrap is firing on width, not on content");
  });

  /* ---- 9. An SVG that DECLARED its size keeps it ----
     This is the half that has to hold no matter what default the kit grows, and it is the half a
     careless cap breaks. Geometry attributes on <svg> lose to any CSS rule at all, so a default
     written as `.mod svg{width:…}` would silently resize every attribute-sized meter and arrow in
     the kit; and `max-width` constrains regardless of specificity, so a "harmless" cap would clamp
     `.fam-annotated .figsvg`, which is full-width on purpose. Asserted unconditionally, because it
     must be true both before and after any guard lands. */
  check("an SVG that declares a size — by attribute or by kit class — is left alone", () => {
    const a = probe.svg.attrSized;
    assert.ok(Math.abs(a.w - 88) < 1 && Math.abs(a.h - 14) < 1,
      `an <svg width="88" height="14"> rendered ${a.w}x${a.h} — a CSS rule is overriding geometry attributes, which no size default may do`);
    const f = probe.svg.figure;
    assert.ok(f.w >= f.hostW * 0.9,
      `.fam-annotated .figsvg rendered ${f.w}px inside a ${f.hostW}px body — a size guard is clamping a figure that is full-width by design`);
  });

  /* ---- 10. An SVG that declared NOTHING does not render at container scale ----
     Gated on the guard actually existing, and loud when it does not: the defect is real whether or
     not the CSS can prevent it, so an absent guard is REPORTED rather than quietly passed. */
  const guardPresent = /svg:not\(\[width\]\):not\(\[height\]\)/.test(blocks);
  const omitted = probe.svg.omitted;
  if (guardPresent) {
    check("an SVG that omits its size cannot run away inside a .mod", () => {
      assert.ok(omitted.w <= SVG_INDICATOR_MAX,
        `an inline <svg viewBox="0 0 14 14"> with no width/height rendered ${omitted.w}x${omitted.h} `
        + `(${((omitted.w / omitted.hostW) * 100).toFixed(0)}% of its ${omitted.hostW}px container) — the unsized-SVG default is not reaching it`);
    });
  } else {
    pending.push(`an unsized inline <svg> inside .mod renders ${omitted.w}x${omitted.h}px — `
      + `${((omitted.w / omitted.hostW) * 100).toFixed(0)}% of its ${omitted.hostW}px container. proof-blocks.css declares no `
      + "unsized-SVG default, so a composed page that omits a size still scales to its container.");
  }
}

/* ---- 11. A row-list states its columns ONCE, on the list ----
   The fifth-and-sixth instance of one root cause: `.mod-head`'s crushed title, an op/evidence
   badge list, `claim-verdict`, `sequence --log` — every one of them a row that owned its own
   tracks, so each row sized column 1 to its own content and the column staggered. Two ways out
   of it exist and both are wrong: hardcode the tracks in px (rows line up until one page's label
   is longer) or leave them `auto` (they never line up). The right shape is the list owning the
   tracks and the row taking `subgrid`.

   Derived, not listed: a class is a ROW if the kit's own markup repeats it as >=2 same-class
   direct children of one parent, or if it is named `<base>-row|-item|-line|-entry` beside a
   `.base` rule. It is CLEARED if any `@supports (grid-template-columns:subgrid)` rule hands it
   `subgrid`. `auto`/`*-content` tracks are separated from fixed ones because only the first
   guarantees the stagger — a fixed track merely hides it behind a hardcoded width.

   REPORTED, not asserted. Deliberate: on its first run this finds three live rows in
   `proof-creative.css` (`.tl-item`, `.ledger-row`, `.rc-line`) and `.callout`, and whether each
   should adopt subgrid is a design call, not a lint verdict. A hard gate would therefore need a
   suppression list — the exact "list that will rot" check 1 exists to argue against. Loud is the
   honest strength for a rule that names candidates rather than defects. */
function rowListOffenders(htmlFiles) {
  /* Which classes has some @supports(subgrid) rule already cleared? Brace-matched rather than
     regexed, because these blocks nest and a regex would stop at the first inner `}`. */
  const cleared = new Set();
  const bareCss = [];
  for (const file of KIT_CSS) {
    const css = read(path.join(intake, file)).replace(/\/\*[\s\S]*?\*\//g, "");
    let out = "";
    for (let i = 0; i < css.length; i++) {
      const at = css.startsWith("@supports", i) && /^@supports[^{]*grid-template-columns\s*:\s*subgrid/.test(css.slice(i, css.indexOf("{", i) + 1));
      if (!at) { out += css[i]; continue; }
      let depth = 0, j = css.indexOf("{", i);
      const start = j;
      for (; j < css.length; j++) { if (css[j] === "{") depth++; else if (css[j] === "}") { if (--depth === 0) break; } }
      for (const m of css.slice(start, j).matchAll(/([^{}]+)\{([^{}]*)\}/g))
        if (/grid-template-columns\s*:\s*subgrid/.test(m[2]))
          for (const c of m[1].matchAll(/\.([a-zA-Z][\w-]*)/g)) cleared.add(c[1]);
      i = j;
    }
    bareCss.push(out);
  }
  /* Rules whose SUBJECT is a lone class — `.tl-item` and `.fam-narrative .tl-item` are the same
     row wearing different ancestry, and only the subject matters here. @media stripped for the
     same reason as the hazard set: a width-conditional track count is a responsive step, not a
     row's grammar. */
  const declared = new Map();
  const known = new Set();
  for (const css of bareCss) {
    const flat = css.replace(/@media[^{]*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}/g, "");
    for (const m of flat.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const t = /(?:^|;|\s)grid-template-columns\s*:\s*([^;]+)/.exec(m[2]);
      for (const sel of m[1].split(",").map((s) => s.trim())) {
        const one = /(?:^|\s|>)\.([a-zA-Z][\w-]*)$/.exec(sel);
        if (!one) continue;
        known.add(one[1]);
        if (t && !/subgrid/.test(t[1])) declared.set(one[1], { tracks: t[1].trim(), sel });
      }
    }
  }
  /* A parent with >=2 same-class direct children IS a list, whatever it is called. */
  const repeated = new Map();
  for (const file of htmlFiles) {
    const src = read(file);
    const stack = [];
    for (const m of src.matchAll(/<(\/?)([a-zA-Z][a-zA-Z0-9]*)\b([^>]*?)(\/?)>/g)) {
      const [, closing, rawTag, attrs, selfClosed] = m;
      const tag = rawTag.toLowerCase();
      if (closing) {
        for (let i = stack.length - 1; i >= 0; i--) if (stack[i].tag === tag) {
          for (const [c, n] of stack[i].kids) if (n >= 2) {
            if (!repeated.has(c)) repeated.set(c, new Set());
            repeated.get(c).add(`${path.basename(file)}:${stack[i].tag}${stack[i].cls[0] ? "." + stack[i].cls[0] : ""} (x${n})`);
          }
          stack.length = i; break;
        }
        continue;
      }
      const cls = (/\bclass="([^"]*)"/i.exec(attrs) || [, ""])[1].split(/\s+/).filter(Boolean);
      const parent = stack[stack.length - 1];
      if (parent) for (const c of cls) parent.kids.set(c, (parent.kids.get(c) || 0) + 1);
      if (!selfClosed && !VOID_TAGS.has(tag)) stack.push({ tag, cls, kids: new Map() });
    }
  }
  const out = [];
  for (const [cls, { tracks, sel }] of declared) {
    if (cleared.has(cls)) continue;
    const namedRow = /^(.+)-(row|item|line|entry)$/.exec(cls);
    const byName = namedRow && (known.has(namedRow[1]) || repeated.has(cls));
    const where = repeated.get(cls);
    if (!byName && !where) continue;
    const contentSized = /\bauto\b|min-content|max-content|fit-content/.test(tracks);
    out.push(`${sel}{grid-template-columns:${tracks}} — ${contentSized
      ? "content-sized tracks, so every row negotiates its own and the columns WILL stagger"
      : "fixed tracks, so the columns line up only until one page's content outgrows the number"}`
      + `; row-ness from ${byName ? `the \`-${namedRow[2]}\` name beside a \`.${namedRow[1]}\` rule` : ""}`
      + `${byName && where ? " and " : ""}${where ? [...where].join(", ") : ""}`);
  }
  return out;
}

const KIT_HTML = [
  ...["PROOF_BLOCKS.html", "CREATIVE_LAYOUTS.html"].map((f) => path.join(intake, f)),
  ...fs.readdirSync(path.join(intake, "skeletons")).filter((f) => f.endsWith(".html")).map((f) => path.join(intake, "skeletons", f)),
].filter((p) => fs.existsSync(p));

const rowOffenders = rowListOffenders(KIT_HTML);
if (rowOffenders.length) {
  const willStagger = rowOffenders.filter((o) => o.includes("WILL stagger")).length;
  pending.push(`${rowOffenders.length} row-list(s) state their columns on the ROW rather than on the list `
    + `(${willStagger} with content-sized tracks, which WILL stagger; ${rowOffenders.length - willStagger} hidden behind `
    + "fixed track widths). The list should own the tracks and the row take `subgrid`. Verify before "
    + "acting: an `auto` track whose CONTENT is itself fixed-width — a counter disc, an icon at a set "
    + "size — will not actually stagger, and no static rule can see that:\n    "
    + rowOffenders.join("\n    "));
}

/* ---- 12. A subgrid row-list ships the PAIR, not just the tracks ----
   Half a fix looks exactly like a whole one from the alignment numbers: with tracks alone the
   columns line up perfectly AND every bare grid-item row child stretches to the shared track, so
   a badge's ground stops hugging its label — `.clog .tag` measured [47.45, 34.88, 66.33, 47.45]
   -> [66.33 x4]. The tell is not "is there a bare child" — every `.cpv` cell is one, and they are
   full-bleed panes that are MEANT to stretch. It is a bare child that is BADGE-SHAPED: its own
   rule gives it a fill and a corner radius, which is the grammar of something that must hug its
   text. Being a flex container does NOT make the child immune — `.clog .tag` is `inline-flex`
   and inflated anyway, because a flex box still stretches to its own grid track; what protects
   `.cpv` is that its badge sits one level DEEPER, inside a pane that is supposed to stretch.
   So the question is only ever about the row's own child.

   Hard assertion, unlike 11 and 13. It is clean today, the discriminator is narrow, and the
   cheapest way to make it pass is the correct one-line fix — never a suppression. A row-list
   grammar that is only advisory is what produced six instances of this defect. */
function subgridRowClasses() {
  const rows = new Map();                                  // rowClass -> selector that subgrids it
  const justified = [];                                    // selectors that set justify-self
  const shape = new Map();                                 // class -> {display, fill, radius}
  for (const file of KIT_CSS) {
    const css = read(path.join(intake, file)).replace(/\/\*[\s\S]*?\*\//g, "");
    for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const decl = m[2];
      for (const sel of m[1].split(",").map((s) => s.trim())) {
        if (/grid-template-columns\s*:\s*subgrid/.test(decl)) {
          const subj = /\.([a-zA-Z][\w-]*)$/.exec(sel);
          if (subj) rows.set(subj[1], sel);
        }
        if (/(?:^|;|\s)justify-self\s*:/.test(decl)) justified.push(sel);
        const subj = /\.([a-zA-Z][\w-]*)$/.exec(sel);
        if (!subj) continue;
        const s = shape.get(subj[1]) || {};
        const d = /(?:^|;|\s)display\s*:\s*([a-z-]+)/.exec(decl);
        if (d) s.display = d[1];
        if (/(?:^|;|\s)(?:background|background-color)\s*:/.test(decl)) s.fill = true;
        if (/(?:^|;|\s)border-radius\s*:\s*(?!50%)/.test(decl)) s.radius = true;
        shape.set(subj[1], s);
      }
    }
  }
  return { rows, justified, shape };
}

check("a subgrid row-list also gives its badge-shaped children a justify-self", () => {
  const { rows, justified, shape } = subgridRowClasses();
  /* the row's children come from the kit's own markup, not from a guess about the class name */
  const kids = new Map();
  for (const file of KIT_HTML) {
    const src = read(file);
    const stack = [];
    for (const m of src.matchAll(/<(\/?)([a-zA-Z][a-zA-Z0-9]*)\b([^>]*?)(\/?)>/g)) {
      const [, closing, rawTag, attrs, selfClosed] = m;
      const tag = rawTag.toLowerCase();
      if (closing) { for (let i = stack.length - 1; i >= 0; i--) if (stack[i].tag === tag) { stack.length = i; break; } continue; }
      const cls = (/\bclass="([^"]*)"/i.exec(attrs) || [, ""])[1].split(/\s+/).filter(Boolean);
      const parent = stack[stack.length - 1];
      /* the child's WHOLE class list, because a badge's fill usually lives on its variant
         (`.tag.add`) while its radius lives on the base — either alone looks innocent */
      if (parent && cls.length) for (const pc of parent.cls) if (rows.has(pc)) {
        if (!kids.has(pc)) kids.set(pc, new Set());
        kids.get(pc).add(cls.join(" "));
      }
      if (!selfClosed && !VOID_TAGS.has(tag)) stack.push({ tag, cls });
    }
  }
  const bad = [];
  for (const [row] of rows) {
    const covered = justified.some((s) => new RegExp(`\\.${row}\\s*>|\\.${row}\\s+\\.`).test(s));
    if (covered) continue;
    const naked = [...(kids.get(row) || [])].filter((names) => {
      const parts = names.split(" ").map((c) => shape.get(c) || {});
      return parts.some((s) => s.fill) && parts.some((s) => s.radius);
    });
    if (naked.length) bad.push(`.${row} takes subgrid but no rule gives its children a justify-self, and `
      + `${naked.map((c) => "." + c.split(" ").join(".")).join(", ")} ${naked.length > 1 ? "are" : "is"} a filled, rounded leaf — it will `
      + "stretch to the shared track and stop hugging its label. Add `justify-self:start` for it (and "
      + "`justify-self:stretch` for whichever child holds the fr track).");
  }
  assert.deepStrictEqual(bad, [], `a row-list shipped tracks without the companion:\n  ${bad.join("\n  ")}`);
});

/* ---- 13. Block-to-block flow distance is stated pairwise, so it cannot be complete ----
   The same root cause as check 11, on the other axis: distance between adjacent blocks is
   layout the CONTAINER should own, and the kit states it per PAIR instead. Pairs are O(n²) in
   block types, so the rule that is missing is always the one nobody wrote — a `.callout`
   followed by a `.mod.scope` sits flush while `.callout + .callout` is spaced.
   Reported as a shape, not per instance: only the DOM knows which adjacencies a page actually
   builds, and most zero gaps in this kit are correct (a head against its body, a row against
   the next row). Naming every zero would bury the four that are wrong in eighty that are not. */
{
  const pairRules = [];
  for (const file of KIT_CSS) {
    const css = read(path.join(intake, file)).replace(/\/\*[\s\S]*?\*\//g, "");
    for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      if (!/(?:^|;|\s)margin(?:-top|-block-start)?\s*:/.test(m[2])) continue;
      for (const sel of m[1].split(",").map((s) => s.trim())) {
        const p = /\.([a-zA-Z][\w-]*)\s*\+\s*\.([a-zA-Z][\w-]*)$/.exec(sel);
        if (p) pairRules.push({ a: p[1], b: p[2], same: p[1] === p[2] });
      }
    }
  }
  const cross = pairRules.filter((p) => !p.same);
  if (pairRules.length && !cross.length) {
    pending.push(`block-to-block flow distance is stated as ${pairRules.length} adjacent-sibling rule(s) `
      + `(${[...new Set(pairRules.map((p) => `.${p.a} + .${p.b}`))].join(", ")}) and EVERY ONE of them is same-type. `
      + `With ${HAZARDS.size} display-setting catalog classes that leaves every cross-type adjacency at 0px — a `
      + "`.callout` followed by a `.mod.scope` sits flush while two callouts do not. The fix is not more pairs "
      + "(they are O(n²)); it is the flow container owning the distance for a named set of block roots.");
  }
}

/* ---- 14. Ink/ground contrast: no rule paints small text below the AA floor ----
   A token pair is only legible in the theme you measured. `--defect` on `--defect-bg` carried
   6.16:1 in dark and 4.39:1 in light, so every dark-first check passed it while the light theme
   shipped 16 sub-floor text runs.

   The parser below is deliberately float-aware. `getComputedStyle` returns a `color-mix()`
   background as `color(srgb 0.95 0.93 0.87)` — 0-to-1 FLOATS — and a naive digit regex reads
   that as near-black and manufactures failures that do not exist. A harness that cannot tell
   `color(srgb 0.95 …)` from `rgb(0.95 …)` is worse than no harness, so `assertControl` below
   proves the parser against a hand-computed color-mix ground before any finding is trusted. */
{
  const clamp01 = (n) => (n < 0 ? 0 : n > 1 ? 1 : n);
  const parse = (input, vars) => {
    let s = String(input).trim(), guard = 0;
    while (s.includes("var(") && guard++ < 20) {
      s = s.replace(/var\(\s*(--[\w-]+)\s*(?:,([^()]*))?\)/, (_m, n, fb) => vars[n] ?? (fb ?? "transparent").trim()).trim();
    }
    if (s === "transparent") return [0, 0, 0, 0];
    if (s[0] === "#") {
      const h = s.slice(1);
      const w = h.length <= 4 ? 1 : 2;
      const ex = (i) => parseInt(w === 1 ? h[i] + h[i] : h.substr(i * 2, 2), 16) / 255;
      if (h.length % (w === 1 ? 3 : 6) !== 0 && h.length !== 4 && h.length !== 8) return null;
      return [ex(0), ex(1), ex(2), h.length === 4 || h.length === 8 ? ex(3) : 1];
    }
    const fn = /^([a-z-]+)\((.*)\)$/is.exec(s);
    if (!fn) return null;
    const kind = fn[1].toLowerCase();
    if (kind === "rgb" || kind === "rgba") {
      const t = fn[2].split(/[,/]/).map((x) => x.trim());
      const v = (x, ref) => (x.endsWith("%") ? parseFloat(x) / 100 : parseFloat(x) / ref);
      const head = t.length >= 3 ? t : fn[2].trim().split(/\s+/);
      return [clamp01(v(head[0], 255)), clamp01(v(head[1], 255)), clamp01(v(head[2], 255)), head[3] == null ? 1 : clamp01(v(head[3], 1))];
    }
    if (kind === "color") {
      // >>> the trap <<< channels here are 0-1, never 0-255
      const t = fn[2].trim().split(/\s+|\s*\/\s*/).filter(Boolean);
      if (t[0].toLowerCase() !== "srgb") return null;
      const c = t.slice(1).map((x) => clamp01(x.endsWith("%") ? parseFloat(x) / 100 : parseFloat(x)));
      return [c[0], c[1], c[2], c.length > 3 ? c[3] : 1];
    }
    if (kind === "color-mix") {
      const parts = []; let depth = 0, cur = "";
      for (const ch of fn[2]) {
        if (ch === "(") depth++; else if (ch === ")") depth--;
        if (ch === "," && depth === 0) { parts.push(cur); cur = ""; continue; }
        cur += ch;
      }
      parts.push(cur);
      if (!/^\s*in\s+srgb/i.test(parts[0])) return null;
      const side = (tok) => {
        const m = /\s(\d*\.?\d+)%\s*$/.exec(" " + tok.trim());
        const pct = m ? parseFloat(m[1]) / 100 : null;
        const c = parse(m ? tok.trim().slice(0, tok.trim().length - m[0].length + 1).trim() : tok.trim(), vars);
        return c && { c, pct };
      };
      const A = side(parts[1]), B = side(parts[2]);
      if (!A || !B) return null;
      let p = A.pct, q = B.pct;
      if (p == null && q == null) { p = q = 0.5; } else if (p == null) p = 1 - q; else if (q == null) q = 1 - p;
      const sum = p + q; p /= sum; q /= sum;
      const a = A.c[3] * p + B.c[3] * q;
      if (a === 0) return [0, 0, 0, 0];
      return [0, 1, 2].map((i) => (A.c[i] * A.c[3] * p + B.c[i] * B.c[3] * q) / a).concat(a);
    }
    return null;
  };
  const lin = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  const lum = (c) => 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const over = (src, dst) => {
    const a = src[3] + dst[3] * (1 - src[3]);
    return a === 0 ? [0, 0, 0, 0] : [0, 1, 2].map((i) => (src[i] * src[3] + dst[i] * dst[3] * (1 - src[3])) / a).concat(a);
  };

  /* THE CONTROL. `.mod-head`'s ground is color-mix(in srgb,--card-2 70%,--card); by hand in
     light that is .7*244+.3*250 / .7*236+.3*245 / .7*220+.3*234. If the parser cannot land on
     the same colour — and the same ratio through the `color(srgb …)` float spelling Chrome
     hands back — nothing below it is worth reading. */
  const ctlVars = { "--card-2": "#f4ecdc", "--card": "#faf5ea" };
  const ctlMix = parse("color-mix(in srgb,var(--card-2) 70%,var(--card))", ctlVars);
  const ctlHand = [245.8 / 255, 238.7 / 255, 224.2 / 255, 1];
  const ctlInk = parse("#73644d", {});
  const ctlFloat = parse(`color(srgb ${ctlHand[0].toFixed(5)} ${ctlHand[1].toFixed(5)} ${ctlHand[2].toFixed(5)})`, {});
  assert.ok(ctlMix && ctlMix.slice(0, 3).every((v, i) => Math.abs(v - ctlHand[i]) < 0.002),
    "contrast control: color-mix() did not evaluate to the hand-computed .mod-head ground — parser is unsound");
  assert.ok(Math.abs(ratio(ctlInk, ctlMix) - ratio(ctlInk, ctlHand)) < 0.01
    && Math.abs(ratio(ctlInk, ctlFloat) - ratio(ctlInk, ctlHand)) < 0.01,
    "contrast control: the same ground gave different ratios through color-mix(), hex and color(srgb …) — "
    + "the float spelling is being misread, which is exactly how phantom light-mode failures get reported");

  /* Theme token blocks. `:root` default and [data-theme=light] are the same palette, likewise
     the two dark blocks; measuring one of each pair is enough and keeps the report readable. */
  const themeSrc = read(path.join(intake, "proof-theme.css")).replace(/\/\*[\s\S]*?\*\//g, "");
  const blockAt = (re) => {
    const m = re.exec(themeSrc);
    if (!m) return null;
    let i = m.index + m[0].length, depth = 1, out = "";
    while (depth > 0 && i < themeSrc.length) {
      const ch = themeSrc[i];
      if (ch === "{") depth++; else if (ch === "}" && --depth === 0) break;
      out += ch; i++;
    }
    const vars = {};
    for (const d of out.split(";")) {
      const t = d.trim();
      if (!t.startsWith("--")) continue;
      vars[t.slice(0, t.indexOf(":")).trim()] = t.slice(t.indexOf(":") + 1).trim();
    }
    return vars;
  };
  const THEMES = {
    light: blockAt(/:root\[data-theme="light"\]\s*\{/),
    dark: blockAt(/:root\[data-theme="dark"\]\s*\{/),
  };

  /* A transparent wash states no ground of its own; the kit lands these on a card surface, so
     they resolve over --card-2. That is the measured surface, not a guess: `.pill.ok`'s rendered
     ground back-solves to #f4ecdc exactly. */
  const findings = [];
  for (const [theme, vars] of Object.entries(THEMES)) {
    if (!vars) continue;
    const surface = parse("var(--card-2)", vars);
    for (const file of ["proof-blocks.css", "proof-creative.css"]) {
      const css = read(path.join(intake, file)).replace(/\/\*[\s\S]*?\*\//g, "");
      let line = 1, last = 0;
      for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        const body = m[2];
        const fgm = /(?:^|;)\s*color\s*:\s*([^;]+)/.exec(body);
        const bgm = /(?:^|;)\s*background(?:-color)?\s*:\s*([^;]+)/.exec(body);
        if (!fgm || !bgm) continue;
        if (!/var\(--/.test(fgm[1]) || !/var\(--/.test(bgm[1])) continue;
        const fg = parse(fgm[1].trim(), vars);
        let bg = parse(bgm[1].trim(), vars);
        if (!fg || !bg || fg[3] < 0.99) continue;
        if (bg[3] < 0.999) bg = over(bg, surface);
        const r = ratio(fg, bg);
        if (r >= 4.5) continue;
        while ((last = css.indexOf("\n", last)) !== -1 && last < m.index) { line++; last++; }
        findings.push({ theme, file, sel: m[1].trim().split(/\s*,\s*/)[0], ratio: r, fg: fgm[1].trim(), bg: bgm[1].trim() });
      }
    }
  }

  /* HARD: the --defect family. It is the one that was measured, fixed and re-measured, and the
     token now clears every ground the kit paints it on. A regression here is a real regression. */
  check("no rule paints --defect as text below the 4.5:1 AA floor, in either theme", () => {
    const bad = findings.filter((f) => /--defect/.test(f.fg))
      .map((f) => `[${f.theme}] ${f.file} ${f.sel} — ${f.ratio.toFixed(2)}:1 (${f.fg} on ${f.bg})`);
    assert.deepStrictEqual(bad, [], `${bad.length} rule(s) paint --defect below AA:\n  ${bad.join("\n  ")}`);
  });

  /* REPORTED: everything else. Retinting another semantic token is a design decision with its
     own CVD and greyscale history — the checker names them, a human retints them. */
  const rest = findings.filter((f) => !/--defect/.test(f.fg));
  if (rest.length) {
    const byToken = new Map();
    for (const f of rest) {
      const tok = (/var\((--[\w-]+)/.exec(f.fg) || [])[1] || "?";
      const cur = byToken.get(tok);
      if (!cur || f.ratio < cur.ratio) byToken.set(tok, f);
      byToken.get(tok).count = (cur?.count || 0) + 1;
    }
    pending.push(`${rest.length} rule(s) paint a token as small text below the 4.5:1 AA floor: `
      + [...byToken.entries()].map(([t, f]) => `${t} worst ${f.ratio.toFixed(2)}:1 [${f.theme}] (${f.count} rule(s), e.g. ${f.sel})`).join("; ")
      + ". Large text (>=24px, or >=18.66px bold) legitimately clears at 3:1 and this static pass cannot see "
      + "font-size, so confirm the size before retinting — but every ratio below 3:1 fails at any size.");
  }
}

/* ---- 15. Bar-text alignment: one baseline per line, measured from GLYPHS ----
   THE RULING: text that shares a line with a bar, meter, track, pip row or dot ALIGNS ON THE
   BASELINE — never centred. The kit had already committed (`.mod-foot` and `.meter .ml` are both
   `align-items:baseline`), and these rows mix sizes hard: an 18px numerator against an 11px
   denominator, a 16px count against a 9.5px toggle. Centring two sizes puts two different
   baselines in one row and the eye reads the difference as a typo. Baseline is the only alignment
   that survives a per-slot size change. The GRAPHIC is the single exception and it is
   `align-self:center` at each site, never a container default: a bar has no baseline, so it
   centres on the line the text defines.

   THE MEASUREMENT IS THE POINT. An element box tells you where the div is; the gap between that
   and where the glyphs sit is exactly the defect. So every run here is a `Range` over a text node,
   and the baseline is derived, not assumed: a zero-height `vertical-align:baseline` strut is
   injected beside a probe of the same family and size, its box bottom IS the baseline by
   definition, and the difference from the run's rect bottom gives that font's descent per em. A
   run's baseline is then `rect.bottom - descentRatio * fontSize`. Without that step you are
   comparing box bottoms, which agree only when the sizes agree — i.e. exactly when there is no bug
   to find.

   A LINE IS A ROW, SO THE WALK STOPS AT ANYTHING THAT STACKS. Candidates are flex/inline-flex
   containers only. A grid row places AREAS, not a line: `.rel-fan.brace` centres a single source
   node against a four-row stack, and those two share no baseline because they share no line. The
   collector likewise stops descending at any grid, inline-grid or column-flex subtree. */
if (process.env.LAYOUT_GUARDS_NO_DOM !== "1") {
  const { default: puppeteer } = await import(PUPPETEER);
  const css = KIT_CSS.map((f) => `<style>${read(path.join(intake, f))}</style>`).join("\n");
  const barFixture = `<!doctype html><html data-theme="THEME"><head>${css}</head>
  <body style="margin:0;background:var(--paper);font-family:var(--sans)"><div style="padding:20px;max-width:1040px">

  <section class="mod"><div class="mod-head">
    <span class="mod-ord" style="--rel-n:3;--rel-of:7" data-rel-n="3" data-rel-of="7"><span class="ord-lab">position</span><span class="ord-track"></span></span>
    <span class="mod-pos" style="--rel-n:3;--rel-of:112" data-rel-n="3" data-rel-of="112"><span class="pos-track"></span></span>
    <span class="desc-crumb"><a class="anc" href="#">Intake</a><span class="anc here">This block</span><span class="anc-depth">depth 3</span></span>
    <span class="step-rail">
      <a class="sm" href="#" data-rel-state="past"><span class="seq-mk"></span><span class="sm-k">S1</span></a>
      <a class="sm" href="#" data-rel-state="current"><span class="seq-mk"></span><span class="sm-k">S4</span><span class="sm-t">Triage the incoming</span></a>
      <a class="sm" href="#" data-rel-state="future"><span class="seq-mk"></span><span class="sm-k">S5</span></a>
    </span>
    <span class="ver-chain">
      <a class="vch" href="#" data-rel-state="past"><span class="seq-mk"></span><span class="vlab">v1</span><i>superseded</i></a>
      <a class="vch" href="#" data-rel-state="current"><span class="seq-mk"></span><span class="vlab">v3</span><i>current</i></a>
    </span>
    <span class="rel rel-fan inline" data-rel="fans-to"><span class="relsrc">FIN-3141</span><span class="reltgts"><span class="reltgt">FIN-3210</span></span><span class="relstate">draft</span></span>
    <div class="dep-gate"><span class="dep-verb">blocked by</span><span class="gatekeys"><span class="dep-key is-unsatisfied"><span class="dep-pip is-unsatisfied" data-fill="quarter"></span>FIN-3390</span></span><span class="gatecount">1 of 3 clear</span></div>
    <div class="rel rel-fan ledger" data-rel="splits-into"><details class="relfold"><summary>
      <span class="relcount"><span class="cn">14</span>sub-issues</span><span class="relpeek">FIN-3210 · FIN-3211</span>
      <span class="reltoggle"><span class="tlab-shut">show</span><span class="tlab-open">hide</span></span></summary></details></div>
  </div>
  <div class="mod-body"><div class="meters"><div class="meter">
    <div class="ml"><span class="mn">Coverage</span><span class="mv">62%</span></div>
    <svg viewBox="0 0 300 14" preserveAspectRatio="none"><rect x="0" y="4" width="300" height="6" rx="3"/></svg>
  </div></div></div>
  <div class="mod-foot">
    <span data-foot="provenance"><span class="fk">provenance</span><span class="fv fprovpair"><span class="fsplit"><i class="c" style="width:62%"></i><i class="u" style="width:38%"></i></span><span class="fdot c">18<span class="lab">checked</span></span><span class="fdot u">11<span class="lab">unverified</span></span></span></span>
    <span data-foot="relation"><span class="fk">relation</span><span class="fv frel"><span class="verb">follows</span><span class="dir">&#9656;</span><span class="peer">FIN-3140</span></span><span class="fv fbasis">page-order</span></span>
    <span data-foot="tally"><span class="fk">tally</span><span class="fpips"><i class="on"></i><i class="on"></i><i></i></span><span class="ffrac">4<span class="of">/5</span></span></span>
    <span data-foot="delta" data-foot-dir="improved"><span class="fk">defects</span><span class="fdbars"><i style="width:100%"></i><i class="after" style="width:18%"></i></span><span class="fdelta"><span class="was">11.4</span><span class="arrow">&#8594;</span><span class="now">2.1</span></span><span class="fmag">82% fewer</span></span>
    <span class="foot-when">as of 2026-08-01</span>
  </div></section>

  <div class="scalewrap"><div class="scale">
    <div class="sw"><span class="swatch"></span><div class="sk">Fresh</div><div class="st">under 7d</div></div>
    <div class="sw"><span class="swatch outline"></span><div class="sk">Unknown</div><div class="st">no date</div></div>
  </div></div>

  </div></body></html>`;

  const browser = await puppeteer.launch({ executablePath: CHROME, headless: "shell" });
  const barFindings = [];
  for (const theme of ["light", "dark"]) {
    const page = await browser.newPage();
    await page.setViewport({ width: 1400, height: 1000 });
    await page.setContent(barFixture.replace("THEME", theme), { waitUntil: "load" });
    const out = await page.evaluate(() => {
      const cs = (el) => getComputedStyle(el);
      /* A LINE IS A ROW. Descend only through inline-level boxes and row-flex containers; stop at
         anything that stacks its children — grid, column-flex, and every block-level box (a
         `.scale .sw` is three block rows in a flex parent, and its rows share no line). */
      const stacks = (el) => {
        const d = cs(el);
        if (/grid/.test(d.display)) return true;
        if (/flex/.test(d.display)) return /column/.test(d.flexDirection);   // a row-flex IS a line
        /* A block-ish box stacks only if it actually holds block-level children. Testing the box's
           OWN display would be wrong: every flex item is blockified to `display:block` regardless of
           what it contains, so that test throws away the whole line it was meant to walk. */
        for (const c of el.children) {
          const cd = cs(c).display;
          if (cd === "none") continue;
          if (/^(block|flow-root|list-item|table)/.test(cd)) return true;
        }
        return false;
      };

      /* Runs: one text node each. The rect comes from a `Range` (a glyph box, not an element box)
         and the BASELINE comes from a zero-height `vertical-align:baseline` strut inserted into the
         run's own line — an inline-block of height 0 has its bottom margin edge ON the baseline by
         definition, and contributes no ascent and no descent, so it reads the line without moving it.
         Measuring in situ beats deriving a descent from a probe: a `Range` rect's edges are rounded
         to whole pixels, so a probe reproduces the run's rounding only if it matches its font,
         weight, size and leading exactly — miss any one and you invent ~1px of "spread" per size
         step in rows that are perfectly aligned. This version assumes nothing about the font.
         Each text node is wrapped in an inline span so the strut is never itself a flex item (which
         would add a gap and join the baseline group it is supposed to observe). */
      const wrapped = [];
      const prep = (root, seen) => {
        const walk = (node) => {
          for (const child of [...node.childNodes]) {
            if (child.nodeType === 3) {
              if (!child.data.trim() || seen.has(child)) continue;
              seen.add(child);
              const w = document.createElement("span");
              w.setAttribute("data-basewrap", "");
              const strut = document.createElement("i");
              strut.setAttribute("data-strut", "");
              strut.style.cssText = "display:inline-block;width:0;height:0;vertical-align:baseline";
              child.parentNode.insertBefore(w, child);
              w.appendChild(strut);
              w.appendChild(child);
              wrapped.push(w);
              continue;
            }
            if (child.nodeType !== 1) continue;
            if (child.hasAttribute("data-basewrap")) continue;
            if (cs(child).display === "none") continue;
            if (child !== root && stacks(child)) continue;           // a line is a row: stop at stacks
            walk(child);
          }
        };
        walk(root);
      };
      const measure = (root) => {
        const out = [];
        for (const w of root.querySelectorAll("[data-basewrap]")) {
          const t = w.lastChild;
          if (!t || t.nodeType !== 3) continue;
          const r = document.createRange();
          r.selectNodeContents(t);
          const rects = [...r.getClientRects()].filter((x) => x.width > 0.5 && x.height > 0.5);
          if (rects.length !== 1) continue;                          // wrapped, or invisible
          const host = w.parentElement;
          const st = cs(host);
          out.push({
            text: t.data.trim().slice(0, 24),
            sel: host.tagName.toLowerCase() + (host.className ? "." + String(host.className).trim().split(/\s+/).join(".") : ""),
            top: rects[0].top, bottom: rects[0].bottom, height: rects[0].height,
            size: parseFloat(st.fontSize),
            base: w.firstChild.getBoundingClientRect().bottom,
          });
        }
        return out;
      };
      const unwrap = () => {
        for (const w of wrapped.splice(0)) {
          const t = w.lastChild;
          if (t) w.parentNode.insertBefore(t, w);
          w.remove();
        }
      };
      const runsIn = (root) => { prep(root, new Set()); const r = measure(root); unwrap(); return r; };
      const base = (r) => r.base;
      const spread = (rs) => Math.max(...rs.map(base)) - Math.min(...rs.map(base));

      /* THE CONTROL. Two sizes of one family in a KNOWN baseline-aligned row must resolve to one
         baseline, and the same pair centred must not. If the measurement cannot separate those two,
         nothing below it is admissible. */
      const cal = document.createElement("div");
      cal.style.cssText = "position:absolute;left:-9999px;top:0;white-space:nowrap";
      cal.innerHTML = `<div id="__ok" style="display:flex;align-items:baseline;font-family:var(--mono)">
          <span style="font-size:18px">18</span><span style="font-size:9px">9</span></div>
        <div id="__no" style="display:flex;align-items:center;font-family:var(--mono)">
          <span style="font-size:18px">18</span><span style="font-size:9px">9</span></div>`;
      document.body.appendChild(cal);
      const ctlOk = runsIn(cal.querySelector("#__ok")), ctlNo = runsIn(cal.querySelector("#__no"));
      const control = { aligned: spread(ctlOk), centred: spread(ctlNo), runs: ctlOk.length + ctlNo.length };
      cal.remove();

      /* Candidates: the bar/meter-bearing rows, named. NOT every flex line on the page — `.mod-head`
         centres its badge rail on purpose and is not this guard's business, and a `.scale` cell is a
         block stack wearing a flex parent. The ruling is about text sharing a line WITH A BAR. */
      const BARROWS = ".meter .ml, .mod-foot, .mod-foot > span, .fprovpair, .fdelta, .frel, "
        + ".dep-gate, .dep-gate .gatekeys, .dep-fan, .dep-key, .relfold > summary, .rel-fan.inline, "
        + ".step-rail, .step-rail .sm, .ver-chain, .ver-chain .vch, .desc-crumb, .fdot, .fbopt";
      const findings = [];
      for (const el of document.querySelectorAll(BARROWS)) {
        const d = cs(el);
        if (!/flex/.test(d.display) || /column/.test(d.flexDirection)) continue;
        const rs = runsIn(el);
        if (rs.length < 2) continue;
        const clusters = [];
        for (const r of rs.slice().sort((a, b) => a.top - b.top)) {
          const c = clusters.find((k) => {
            const ov = Math.min(k.bottom, r.bottom) - Math.max(k.top, r.top);
            return ov > 0.5 * Math.min(k.bottom - k.top, r.height);
          });
          if (c) { c.runs.push(r); c.top = Math.min(c.top, r.top); c.bottom = Math.max(c.bottom, r.bottom); }
          else clusters.push({ top: r.top, bottom: r.bottom, runs: [r] });
        }
        for (const c of clusters) {
          if (c.runs.length < 2) continue;
          if (new Set(c.runs.map((r) => Math.round(r.size * 4))).size < 2) continue;  // one size cannot disagree
          /* 0.5px, not 1px. With an in-situ strut a genuinely baseline-aligned row resolves to a
             spread of exactly 0, so the floor exists only to absorb subpixel noise — and a centred
             9px-vs-10.5px pair, the tightest real mismatch in the kit, lands at ~1.4px. */
          const s = spread(c.runs);
          if (s <= 0.5) continue;
          findings.push({
            host: el.tagName.toLowerCase() + (el.className ? "." + String(el.className).trim().split(/\s+/).join(".") : ""),
            spread: +s.toFixed(2),
            runs: c.runs.map((r) => `${r.sel}@${r.size}px "${r.text}" b=${base(r).toFixed(2)}`),
          });
        }
      }
      return { control, findings };
    });
    barFindings.push({ theme, ...out });
    await page.close();
  }
  await browser.close();

  check("the baseline derivation separates a baseline row from a centred one", () => {
    for (const t of barFindings) {
      assert.ok(t.control.aligned <= 0.5,
        `[${t.theme}] a KNOWN baseline-aligned 18px/9px pair derived a ${t.control.aligned.toFixed(2)}px baseline spread — `
        + "the descent calibration is wrong, so every number below it is inadmissible");
      assert.ok(t.control.centred > 1.5,
        `[${t.theme}] a KNOWN centred 18px/9px pair derived only ${t.control.centred.toFixed(2)}px of spread — `
        + "the measurement cannot see the defect it exists to find (element boxes instead of glyph rects?)");
    }
  });

  check("text sharing a line with a bar or meter is baseline-aligned, never centred", () => {
    const bad = barFindings.flatMap((t) => t.findings.map((f) =>
      `[${t.theme}] ${f.host} — ${f.spread}px of baseline spread across ${f.runs.length} runs on one line: ${f.runs.join(" | ")}`));
    assert.deepStrictEqual(bad, [], "the kit's bar/meter rows align text on the BASELINE; these do not:\n  " + bad.join("\n  ")
      + "\n  Fix the ROW (`align-items:baseline`), not the runs — and give the graphic `align-self:center`,"
      + " because a bar has no baseline to sit on.");
  });
}

/* ---- --scan: lint a composed board ---- */
const scanArgs = process.argv.slice(2).filter((a) => a !== "--scan" && !a.startsWith("--"));
if (process.argv.includes("--scan")) {
  let found = 0;
  let unsized = 0;
  for (const f of scanArgs) {
    const p = path.resolve(f);
    const bad = scanHtml(p);
    const bare = scanSvgHtml(p);
    found += bad.length;
    unsized += bare.length;
    console.log(bad.length || bare.length ? `\n${f}:` : `\n${f}: clean`);
    if (bad.length) console.log(`   ${bad.length} element(s) double a display-setting catalog class onto .mod`);
    for (const b of bad) console.log("      " + b);
    if (bare.length) console.log(`   ${bare.length} inline SVG(s) inside .mod declare no size`);
    for (const b of bare) console.log("      " + b);
    const rows = rowListOffenders([p]);
    if (rows.length) console.log(`   ${rows.length} row-list(s) on this page state their columns per-ROW rather than on the list`);
    for (const r of rows) console.log("      " + r);
  }
  if (found) {
    console.log("\nThe guard makes these harmless, but the markup is still wrong: the catalog class belongs on an inner wrapper inside .mod-body.");
  }
  if (unsized) {
    console.log("\nAn inline <svg> with a viewBox and no width/height is sized by the UA at 100% of its container: a 14px"
      + " indicator renders at container scale and stretches its row. Give it width/height attributes, or a class the kit sizes.");
  }
  if (found || unsized) process.exit(1);
}

for (const p of pending) console.log(`layout-guards.test: REPORTED (unguarded) — ${p}`);

console.log(`layout-guards.test: PASS — ${checks} layout checks over ${HAZARDS.size} display-setting catalog classes `
  + `and ${SVG_SIZED.size} kit-sized SVG classes `
  + "(guard present + class-agnostic, head-line wrap + named floor, no dead breakpoint on the head, "
  + "skeletons free of doubled classes and of unsized in-mod SVGs, every catalog class unchanged alone, every doubled class "
  + "structurally harmless, lone .mod + .flat/.open/sibling-rhythm unchanged, head wraps on content not width, "
  + "attribute-sized and declared-full-width SVGs untouched, unsized in-mod SVG contained, "
  + "every subgrid row-list carrying the justify-self companion its badge children need, "
  + "the baseline derivation separating a baseline row from a centred one, "
  + "text sharing a line with a bar or meter aligned on ONE baseline in both themes)"
  + (pending.length ? ` — ${pending.length} defect(s) REPORTED but not prevented, see above` : ""));
