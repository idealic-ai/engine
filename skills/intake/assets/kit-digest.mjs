#!/usr/bin/env node
/* kit-digest.mjs — turn the kit's rendered HTML galleries into a compact markdown digest.
 *
 * WHAT THIS IS, AND THE ONE THING IT IS NOT.
 * This is an EXTRACTOR, not an editor. Authored prose comes through as written: no summarising, no
 * deduping, no rephrasing a clause because it repeats one three entries up. What it drops is
 * PRESENTATION — markup, CSS, SVG, specimen chrome, syntax-highlight spans — and what it adds is
 * navigation (headings, an index, a reach-for table) built only from content already on the page.
 * Restructuring and repetition are a deliberately separate, later pass. If a change to this file
 * decides what is worth KEEPING, it is out of lane.
 *
 * WHY IT EXISTS. Measured across five reference documents: 978KB raw → 291KB prose = 29%. Seventy-one
 * per cent of what an agent reads is presentation. Worse, proof-creative.css is entirely
 * family-scoped (591 selectors), so a gallery's markup cannot be lifted as its own masthead instructs
 * — the agent pays full freight for specimens that render unstyled when pasted.
 *
 * FIVE SOURCES, FIVE GRAMMARS. There is no shared page shape to parse; each source gets its own
 * reader. See PARSERS below. The `--check` mode is what makes a generated digest trustworthy:
 * staleness becomes a gate failure rather than silent rot.
 *
 * POSTURE (borrowed from prove/assets/bake-tickets.sh): VALIDATE loudly, WARN rather than refuse on a
 * thin entry — a partial digest beats no digest. FATAL only on what a reader would swallow in
 * silence. Here the silent-swallow case is A CONTRACT EMITTED WITH A CLAUSE MISSING: an agent obeys a
 * truncated rule without ever knowing it was truncated. So a lost clause is fatal; thin text warns.
 *
 * Usage:
 *   kit-digest.mjs --out <digest.md> [--recipes-out <r.md>] [--markup-out <m.md>] [--sources <manifest.json>]
 *                  [--preconditions <p>] [--recipes <p>] [--openers <p>]
 *                  [--blocks <p>] [--layouts <p>]
 *   kit-digest.mjs --check  [same source flags]     # regenerate to memory, diff against --out; exit 1 on drift
 *   kit-digest.mjs --stats  [same source flags]     # per-section byte/token budget to stderr
 *
 * Source paths are ARGUMENTS, never hardcoded: the contract-bearing pages currently live in a session
 * folder and have not been promoted into the kit. `--sources` reads a JSON manifest of the same keys
 * ({preconditions,recipes,openers,blocks,layouts}) with `~` expanded, so promotion is a one-line edit
 * there rather than a code change. Explicit flags override the manifest.
 */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SELF = "kit-digest.mjs";

/* ─────────────────────────────  fatal / warn  ───────────────────────────── */

const warnings = [];
const warn = (msg) => { warnings.push(msg); process.stderr.write(`${SELF}: warning — ${msg}\n`); };
const die = (msg) => { process.stderr.write(`${SELF}: FATAL — ${msg}\n`); process.exit(1); };

/* ─────────────────────────────  tiny HTML reader  ─────────────────────────
   No dependency is available in this asset dir and none is wanted: the kit's other checks are
   plain node --test .mjs files. This is a tag scanner, not a DOM — enough to slice balanced
   elements and read class attributes, which is all five grammars need. */

const VOID = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);
const TAG_RE = /<([a-zA-Z][-\w]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/g;

function attrOf(attrs, name) {
  const m = new RegExp(`\\b${name}\\s*=\\s*("([^"]*)"|'([^']*)')`, "i").exec(attrs);
  if (!m) return null;
  return m[2] !== undefined ? m[2] : m[3];
}

function classListOf(attrs) {
  const c = attrOf(attrs, "class");
  return c ? c.trim().split(/\s+/) : [];
}

/* Slice the element whose '<' sits at `start`. Returns inner HTML + the index just past '</tag>'. */
function sliceEl(html, start) {
  TAG_RE.lastIndex = start;
  const m = TAG_RE.exec(html);
  if (!m || m.index !== start) return null;
  const tag = m[1].toLowerCase();
  const openEnd = start + m[0].length;
  if (VOID.has(tag) || m[3] === "/") return { tag, attrs: m[2], inner: "", start, end: openEnd };
  const scan = new RegExp(`</?${tag}\\b`, "gi");
  scan.lastIndex = openEnd;
  let depth = 1, mm;
  while ((mm = scan.exec(html))) {
    if (html[mm.index + 1] === "/") {
      if (--depth === 0) {
        const close = html.indexOf(">", mm.index);
        return { tag, attrs: m[2], inner: html.slice(openEnd, mm.index), start, end: close + 1 };
      }
    } else {
      depth++;
    }
  }
  return null;   // unbalanced — caller decides whether that is fatal
}

/* Every element carrying ALL of `want` as class tokens, in document order, non-overlapping. */
function queryAll(html, want) {
  const need = Array.isArray(want) ? want : [want];
  const out = [];
  const re = new RegExp(TAG_RE.source, "g");
  let m, skipUntil = -1;
  while ((m = re.exec(html))) {
    if (m.index < skipUntil) continue;
    const cls = classListOf(m[2]);
    if (!need.every((n) => cls.includes(n))) continue;
    const el = sliceEl(html, m.index);
    if (!el) continue;
    out.push(el);
    skipUntil = el.end;
    re.lastIndex = m.index + 1;      // allow a sibling that starts before `end` to be skipped by skipUntil
  }
  return out;
}

/* First descendant matching — used where a contract's parts are known singletons. */
function queryOne(html, want) {
  const all = queryAll(html, want);
  return all.length ? all[0] : null;
}

/* ─────────────────────────────  entities + text  ───────────────────────── */

const ENTITIES = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
  mdash: "—", ndash: "–", hellip: "…", rsquo: "’", lsquo: "‘",
  ldquo: "“", rdquo: "”", laquo: "«", raquo: "»",
  larr: "←", rarr: "→", uarr: "↑", darr: "↓", harr: "↔",
  para: "¶", sect: "§", middot: "·", bull: "•", deg: "°",
  times: "×", divide: "÷", plusmn: "±", minus: "−",
  ge: "≥", le: "≤", ne: "≠", asymp: "≈", equiv: "≡",
  copy: "©", reg: "®", trade: "™", dagger: "†", Dagger: "‡",
  ensp: " ", emsp: " ", thinsp: " ", shy: "", zwnj: "", zwj: "",
  frac12: "½", frac14: "¼", frac34: "¾", prime: "′", Prime: "″",
  lowast: "∗", oline: "‾", sup2: "²", sup3: "³", micro: "µ",
  alpha: "α", beta: "β", gamma: "γ", delta: "δ", Delta: "Δ",
  pi: "π", sigma: "σ", omega: "ω", infin: "∞", radic: "√",
  cap: "∩", cup: "∪", sub: "⊂", sup: "⊃", isin: "∈", notin: "∉",
  and: "∧", or: "∨", not: "¬", forall: "∀", exist: "∃",
  loz: "◊", spades: "♠", clubs: "♣", hearts: "♥", diams: "♦",
  euro: "€", pound: "£", yen: "¥", cent: "¢", curren: "¤",
};

const UNKNOWN_ENTITIES = new Set();

function unescapeEntities(s) {
  return s.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/g, (whole, body) => {
    if (body[0] === "#") {
      const cp = body[1] === "x" || body[1] === "X"
        ? parseInt(body.slice(2), 16)
        : parseInt(body.slice(1), 10);
      return Number.isFinite(cp) ? String.fromCodePoint(cp) : whole;
    }
    if (Object.prototype.hasOwnProperty.call(ENTITIES, body)) return ENTITIES[body];
    UNKNOWN_ENTITIES.add(body);
    return whole;
  });
}

const stripTags = (s) => s.replace(/<[^>]*>/g, "");

/* HTML → inline markdown. Presentation tags become their markdown equivalent; everything else goes.
   This is a format map, not an edit: no word of authored text is changed, added or removed. */
function toText(html, { keepBreaks = false } = {}) {
  if (html == null) return "";
  let s = String(html);
  s = s.replace(/<!--[\s\S]*?-->/g, "");
  s = s.replace(/<br\s*\/?>/gi, keepBreaks ? "\n" : " ");
  if (keepBreaks) s = s.replace(/<\/(p|div|li|h[1-6])\s*>/gi, "\n");
  /* code first: it swallows its own inner markup, so a <b> inside a <code> cannot leak asterisks
     into a span the reader will paste. */
  /* content stays ESCAPED here on purpose. `<code>&lt;em&gt;</code>` is real content on these pages;
     decoding it now would hand a literal <em> to the global stripTags below, which would delete the
     one token the author was pointing at and leave an empty pair of backticks. Entities are decoded
     once, at the end, after every tag has already gone. */
  s = s.replace(/<code[^>]*>([\s\S]*?)<\/code>/gi, (_m, x) => {
    const t = stripTags(x).replace(/`/g, "").trim();
    return t ? "`" + t + "`" : "";
  });
  for (let pass = 0; pass < 3; pass++) {
    const before = s;
    s = s.replace(/<(b|strong)\b[^>]*>([\s\S]*?)<\/\1\s*>/gi, (_m, _t, x) => (/\S/.test(stripTags(x)) ? "**" + x.trim() + "**" : ""));
    s = s.replace(/<(i|em)\b[^>]*>([\s\S]*?)<\/\1\s*>/gi, (_m, _t, x) => (/\S/.test(stripTags(x)) ? "*" + x.trim() + "*" : ""));
    if (s === before) break;
  }
  s = stripTags(s);
  s = unescapeEntities(s);
  s = s.replace(/ /g, " ");
  if (keepBreaks) {
    s = s.split("\n").map((l) => l.replace(/[ \t]+/g, " ").trim()).filter((l, i, a) => l || (i && a[i - 1])).join("\n");
  } else {
    s = s.replace(/\s+/g, " ");
  }
  /* an emphasis run that ended up adjacent collapses into ****, which renders as nothing */
  s = s.replace(/\*\*\s*\*\*/g, " ").replace(/\*{4,}/g, "**");
  return s.trim();
}

const cell = (s) => s.replace(/\|/g, "\\|").replace(/\n/g, " ");

/* ─────────────────────────────  <pre> lifting  ─────────────────────────────
   The emit side. The galleries' <pre> blocks are the one thing the reference pages most
   conspicuously lack, and [RECIPE] guarantees its rendered example and its <pre> are the same
   bytes. Highlight spans are real tags around escaped text, so tags come off FIRST and entities
   are decoded second — reversing that order would corrupt any `&lt;` the author actually wrote. */
function liftPre(inner) {
  const text = unescapeEntities(stripTags(inner.replace(/^\n/, "")));
  return text.replace(/\s+$/, "");
}

/* ─────────────────────────────  PARSERS  ─────────────────────────────
   One per source. They share nothing but the tag scanner, because the pages share nothing but HTML. */

function stripInert(html) {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<svg[\s\S]*?<\/svg>/gi, "");
}

/* ── 1. preconditions.html — 45 four-clause contracts ──
   .ct entries: .ct-id{.ct-n name, .ct-cls selector, .ct-use status} + .cl.{req,unl|blk,exc,deg}
   each holding <span class="k">label</span><span class="v">value</span>.
   §02 carries a TEACHING copy of the entry geometry inside .spec — a specimen, not a catalogue
   row. It is excluded, which is why the markup counts 46 .ct-n and the page's own prose says 45. */
function parsePreconditions(raw) {
  const html = stripInert(raw);
  const specRanges = queryAll(html, "spec").map((e) => [e.start, e.end]);
  const inSpec = (i) => specRanges.some(([a, b]) => i >= a && i < b);

  /* a section heading is a `.no` number-span butted straight against its dek with no whitespace,
     so the two have to be read apart or they concatenate into "…25 creative patternsSix families." */
  const sections = [];
  for (const el of queryAll(html, "sec")) {
    const no = queryOne(el.inner, "no");
    const title = no ? toText(no.inner) : toText(el.inner);
    const dek = no ? toText(el.inner.slice(0, no.start) + el.inner.slice(no.end)) : "";
    sections.push({ at: el.start, title, dek });
  }
  const sectionAt = (i) => {
    let cur = null;
    for (const s of sections) { if (s.at < i) cur = s; else break; }
    return cur;
  };

  const signature = {
    "ct-n": queryAll(html, "ct-n").length,
    "ct-cls": queryAll(html, "ct-cls").length,
    "cl req": queryAll(html, ["cl", "req"]).length,
    "cl exc": queryAll(html, ["cl", "exc"]).length,
    "cl deg": queryAll(html, ["cl", "deg"]).length,
    "cl unl": queryAll(html, ["cl", "unl"]).length,
    "cl blk": queryAll(html, ["cl", "blk"]).length,
  };

  const clauseText = (el) => {
    if (!el) return null;
    const v = queryOne(el.inner, "v");
    return v ? toText(v.inner) : toText(el.inner);
  };

  /* Rows are the .ct grid items; the .ct-id column and the clause column are its two children, so
     the row — not the id — is the unit that must be sliced. A .ct carrying no .ct-id is layout. */
  const entries = [];
  for (const row of queryAll(html, "ct")) {
    if (inSpec(row.start)) continue;
    const id = queryOne(row.inner, "ct-id");
    if (!id) continue;

    const nameEl = queryOne(id.inner, "ct-n");
    const clsEl = queryOne(id.inner, "ct-cls");
    const useEl = queryOne(id.inner, "ct-use");

    const name = nameEl ? toText(nameEl.inner) : null;
    const selector = clsEl
      ? queryAll(clsEl.inner, "atom").map((a) => toText(a.inner)).join(" ") || toText(clsEl.inner)
      : null;

    let status = null;
    if (useEl) {
      const parts = [];
      const st = queryOne(useEl.inner, "ustat");
      if (st) parts.push(toText(st.inner));
      for (const chip of queryAll(useEl.inner, "uchip")) parts.push(toText(chip.inner));
      status = parts.filter(Boolean).join(" · ") || null;
    }

    const req = queryOne(row.inner, ["cl", "req"]);
    const unl = queryOne(row.inner, ["cl", "unl"]);
    const blk = queryOne(row.inner, ["cl", "blk"]);
    const exc = queryOne(row.inner, ["cl", "exc"]);
    const deg = queryOne(row.inner, ["cl", "deg"]);

    /* the checkability marker rides INSIDE the requires value; it is its own fact, not part of the
       rule text, so it is lifted out rather than left glued on as "● AF-HERO". */
    let checkable = null;
    let requires = null;
    if (req) {
      const v = queryOne(req.inner, "v");
      const scope = v ? v.inner : req.inner;
      const chk = queryOne(scope, "chk");
      if (chk) {
        const grade = classListOf(chk.attrs).find((c) => ["yes", "part", "no"].includes(c)) || "?";
        const label = toText(chk.inner).replace(/^[●○◐•\s]+/, "").trim();
        checkable = { grade, label };
      }
      requires = toText(chk ? scope.slice(0, chk.start) + scope.slice(chk.end) : scope);
    }

    entries.push({
      name,
      selector,
      status,
      section: (sectionAt(row.start) || {}).title || null,
      sectionDek: (sectionAt(row.start) || {}).dek || null,
      unreachable: Boolean(blk),
      requires,
      unlocks: clauseText(unl),
      blockedBy: clauseText(blk),
      excludes: clauseText(exc),
      degradesTo: clauseText(deg),
      checkable,
    });
  }

  return { entries, signature };
}

/* ── 2. recipes.html — 6 compositions, two panels each ──
   .rc-when (use-when) · .rc-front > 2× .rc-panel (precondition checklist / failure branch) ·
   .rc-sig (affordance signature) · .rc-moves (ordered moves) · .lift .lift-body > pre (the emit). */
function parseRecipes(raw) {
  const html = stripInert(raw);
  const signature = {
    "rc-panel": queryAll(html, "rc-panel").length,
    "rc-n": queryAll(html, "rc-n").length,
    "rc-lead": queryAll(html, "rc-lead").length,
    "rc-when": queryAll(html, "rc-when").length,
    "rc-sig": queryAll(html, "rc-sig").length,
    "rc-siglab": queryAll(html, "rc-siglab").length,
  };

  const whens = queryAll(html, "rc-when");
  const recipes = [];

  for (let i = 0; i < whens.length; i++) {
    const from = whens[i].start;
    const to = i + 1 < whens.length ? whens[i + 1].start : html.length;
    const seg = html.slice(from, to);
    const abs = (el) => ({ ...el, start: el.start + from, end: el.end + from });

    /* the recipe's own title is the nearest heading ABOVE its use-when line */
    let title = null, oneline = null;
    const head = html.slice(0, from);
    const hm = [...head.matchAll(/<h([12])\b[^>]*>([\s\S]*?)<\/h\1\s*>/gi)].pop();
    if (hm) title = toText(hm[2]);
    const ol = [...head.matchAll(/class=["']rc-oneline["']/g)].pop();
    if (ol) { const e = sliceEl(html, head.lastIndexOf("<", ol.index)); if (e) oneline = toText(e.inner); }

    const panels = queryAll(seg, "rc-panel").map(abs);
    const readPanel = (p) => {
      if (!p) return null;
      const h = /<h3\b[^>]*>([\s\S]*?)<\/h3\s*>/i.exec(p.inner);
      const heading = h ? toText(h[1].replace(/<span class=["']rc-n["'][\s\S]*/i, "")) : null;
      const nEl = queryOne(p.inner, "rc-n");
      const lead = queryOne(p.inner, "rc-lead");
      return {
        heading,
        gloss: nEl ? toText(nEl.inner) : null,
        lead: lead ? toText(lead.inner) : null,
      };
    };

    const checksEl = queryOne(seg, "rc-checks");
    const checks = checksEl ? queryAll(checksEl.inner, []).length : 0;   // placeholder, replaced below
    void checks;

    const items = [];
    if (checksEl) {
      for (const li of listItems(checksEl.inner)) {
        const why = queryOne(li, "rc-why");
        const unlock = queryOne(li, "rc-unlock");
        const body = toText(stripRanges(li, [why, unlock]));
        items.push({
          optional: /class=["'][^"']*\bopt\b/.test(li) ? true : undefined,
          text: body,
          why: why ? toText(why.inner) : null,
          unlocks: unlock ? toText(unlock.inner) : null,
        });
      }
    }
    /* .opt lives on the <li> itself, so it has to be read off the element, not the inner html */
    const optFlags = checksEl ? listItemOpenTags(checksEl.inner).map((t) => classListOf(t).includes("opt")) : [];
    items.forEach((it, k) => { it.optional = Boolean(optFlags[k]); });

    const branchEl = queryOne(seg, "rc-branch");
    const branches = [];
    if (branchEl) {
      for (const li of listItems(branchEl.inner)) {
        const sev = queryOne(li, "rc-if");
        const cond = queryOne(li, "rc-cond");
        const then = queryOne(li, "rc-then");
        branches.push({
          severity: sev ? toText(sev.inner) : null,
          when: cond ? toText(cond.inner) : null,
          then: then ? toText(then.inner) : null,
        });
      }
    }

    const movesEl = queryOne(seg, "rc-moves");
    const moves = [];
    if (movesEl) {
      for (const li of listItems(movesEl.inner)) {
        const mv = queryOne(li, "rc-move");
        const bc = queryOne(li, "rc-because");
        moves.push({ move: mv ? toText(mv.inner) : toText(li), why: bc ? toText(bc.inner) : null });
      }
    }

    const sigEl = queryOne(seg, "rc-sig");
    let signatureLine = null;
    if (sigEl) {
      const lab = queryOne(sigEl.inner, "rc-siglab");
      signatureLine = toText(lab ? sigEl.inner.slice(0, lab.start) + sigEl.inner.slice(lab.end) : sigEl.inner);
    }

    const liftHead = queryOne(seg, "lh-m");
    const liftBody = queryOne(seg, "lift-body");
    let markup = null;
    if (liftBody) {
      const pre = /<pre\b[^>]*>([\s\S]*?)<\/pre\s*>/i.exec(liftBody.inner);
      if (pre) markup = liftPre(pre[1]);
    }

    recipes.push({
      title, oneline,
      useWhen: toText(whens[i].inner),
      panels: panels.map(readPanel),
      preconditions: items,
      branches,
      moves,
      signature: signatureLine,
      liftMeta: liftHead ? toText(liftHead.inner) : null,
      markup,
    });
  }

  return { recipes, signature };
}

/* <li> slicing that survives nested markup and both quote styles */
function listItems(html) {
  const out = [];
  const re = /<li\b((?:"[^"]*"|'[^']*'|[^>"'])*?)>/gi;
  let m;
  while ((m = re.exec(html))) {
    const el = sliceEl(html, m.index);
    if (!el) continue;
    out.push(el.inner);
    re.lastIndex = el.end;
  }
  return out;
}
function listItemOpenTags(html) {
  const out = [];
  const re = /<li\b((?:"[^"]*"|'[^']*'|[^>"'])*?)>/gi;
  let m;
  while ((m = re.exec(html))) {
    const el = sliceEl(html, m.index);
    out.push(m[1]);
    if (el) re.lastIndex = el.end;
  }
  return out;
}
function stripRanges(html, els) {
  const keep = els.filter(Boolean).sort((a, b) => b.start - a.start);
  let s = html;
  for (const e of keep) s = s.slice(0, e.start) + s.slice(e.end);
  return s;
}

/* ── 3. openers.html — a DIFFERENT grammar, hence a second parser ──
   Its op-* classes are specimen parts, not contract clauses. The contracts live in §4 as .brief
   blocks holding ALTERNATING .bk (label) / .bv (value) siblings — no wrapper per clause — and the
   second clause is "Composes", not "unlocks". Copyable source sits in a sibling <pre class="src">
   carrying syntax-highlight spans. */
function parseOpeners(raw) {
  const html = stripInert(raw);
  const signature = {
    brief: queryAll(html, "brief").length,
    "bk req": queryAll(html, ["bk", "req"]).length,
    "bk cmp": queryAll(html, ["bk", "cmp"]).length,
    "bk exc": queryAll(html, ["bk", "exc"]).length,
    "bk deg": queryAll(html, ["bk", "deg"]).length,
  };

  const forms = [];
  for (const brief of queryAll(html, "brief")) {
    const label = [...html.slice(0, brief.start).matchAll(/class=["']speclab["']/g)].pop();
    let name = null;
    if (label) {
      const el = sliceEl(html, html.lastIndexOf("<", label.index));
      if (el) name = toText(el.inner);
    }

    /* alternating siblings: read the .bk label, then the .bv that follows it */
    const clauses = [];
    const bks = queryAll(brief.inner, "bk");
    for (const bk of bks) {
      const kind = classListOf(bk.attrs).find((c) => c !== "bk") || null;
      const after = brief.inner.slice(bk.end);
      const bv = queryOne(after, "bv");
      clauses.push({ kind, label: toText(bk.inner), value: bv ? toText(bv.inner) : null });
    }

    /* the copyable source is the next <pre class="src"> after the brief */
    let markup = null;
    const tail = html.slice(brief.end);
    const pm = /<pre\b[^>]*class=["'][^"']*\bsrc\b[^"']*["'][^>]*>([\s\S]*?)<\/pre\s*>/i.exec(tail);
    if (pm && pm.index < 2000) markup = liftPre(pm[1]);

    forms.push({ name, clauses, markup });
  }

  /* §-level headings are the page's own spine; carried so the digest can say honestly what part of
     openers.html this parser does NOT read. */
  const sections = [...html.matchAll(/<h2\b[^>]*>([\s\S]*?)<\/h2\s*>/gi)].map((m) => toText(m[1]));

  return { forms, sections, signature };
}

/* ── 4 + 5. PROOF_BLOCKS.html / CREATIVE_LAYOUTS.html ──
   Checked rather than assumed: NEITHER carries the four-clause contract (cl req = 0, bk req = 0).
   What they carry that nothing else does is the job→reach picker (.prow: .pneed → .preach) and,
   in CREATIVE_LAYOUTS, a Pattern/When/Remix caption per pattern. Those are extracted; the
   specimens are not, because preconditions.html already contracts the same catalogues at four
   clauses each. */
function parsePicker(raw, sourceLabel) {
  const html = stripInert(raw);
  const rows = [];
  for (const row of queryAll(html, "prow")) {
    /* `.prow.phead` is a column-header row in CREATIVE_LAYOUTS; PROOF_BLOCKS has no such class and
       smuggles its column label into the first data row as a `.lead` span instead. Both are
       chrome, and both have to be dropped by a different mechanism. */
    if (classListOf(row.attrs).includes("phead")) continue;
    const need = queryOne(row.inner, "pneed");
    const reach = queryOne(row.inner, "preach");
    if (!need || !reach) continue;
    let needText = need.inner;
    const lead = queryOne(needText, "lead");
    if (lead) needText = needText.slice(0, lead.start) + needText.slice(lead.end);
    rows.push({ need: toText(needText), reach: toText(reach.inner), from: sourceLabel });
  }
  return rows;
}

function parseBlocks(raw) {
  const html = stripInert(raw);
  const blocks = [];
  for (const art of queryAll(html, "mod")) {
    const id = attrOf(art.attrs, "id");
    if (!id || !id.startsWith("b-")) continue;
    /* #b-skeleton is §01's teaching copy of the .mod shell, not a catalogue block — the same kind
       of specimen as preconditions' .spec demo, excluded on the same principle. Dropping it leaves
       20, which is exactly the set preconditions.html §05 contracts. */
    if (id === "b-skeleton") continue;
    const eyebrow = queryOne(art.inner, "mod-eyebrow");
    const slug = queryOne(art.inner, "mod-slug");
    const use = queryOne(art.inner, "mod-use");
    blocks.push({
      id,
      name: eyebrow ? toText(eyebrow.inner) : id.slice(2),
      modifier: slug ? toText(slug.inner) : null,
      useWhen: use ? toText(use.inner) : null,
    });
  }
  return { blocks, picker: parsePicker(raw, "PROOF_BLOCKS") };
}

/* CREATIVE_LAYOUTS carries FOUR caption states across its 25 patterns and this parser reads all
   four rather than assuming one:
     ·  4 — <div class="caption"> with structured .k/.v spans (Pattern · When · Remix)
     ·  4 — <div class="caption"> with a .cn label row, a <p><span class="use">Use when</span>…,
            and a <p class="remix"> — the same three fields, third markup
     ·  4 — <p class="caption"> with a .lead span and the three fields flattened into one prose run
     · 13 — no caption at all. Named as an honest absence, never silently omitted.
   Only the .k/.v form yields labelled fields. The other two are emitted as the author's own lines,
   verbatim: splitting a written sentence into invented fields would be rewriting, which is out of
   lane. Note .pat is REUSED inside the .cn row as a caption label, which is why the article scan
   is keyed on id^="p-" rather than on the class alone. */
function parseLayouts(raw) {
  const html = stripInert(raw);
  const patterns = [];
  for (const art of queryAll(html, "pat")) {
    const id = attrOf(art.attrs, "id");
    if (!id || !id.startsWith("p-")) continue;
    const no = queryOne(art.inner, "pno");
    const h = /<h3\b[^>]*>([\s\S]*?)<\/h3\s*>/i.exec(art.inner);
    const cap = queryOne(art.inner, "caption");
    const fields = {};
    let lines = [];
    if (cap) {
      const ks = queryAll(cap.inner, "k");
      if (ks.length) {
        for (const k of ks) {
          const v = queryOne(cap.inner.slice(k.end), "v");
          if (v) fields[toText(k.inner)] = toText(v.inner);
        }
      } else {
        /* These captions are label/value ROWS: `<span>Pattern</span><span class="pat">Name</span>`
           and `<span class="use">Use when</span>…` sit flush against each other in the source and
           are separated only by CSS, so a straight text join yields "PatternDiagonal split". A
           space at each span/div boundary restores the separation the stylesheet was providing —
           inside a caption only, where no construct glues two halves of one word. */
        const spaced = cap.inner.replace(/<\/(span|div)\s*>/gi, "$& ");
        lines = toText(spaced, { keepBreaks: true }).split("\n").map((l) => l.trim()).filter(Boolean);
      }
    }
    const shape = Object.keys(fields).length ? "fields" : lines.length ? "blob" : "none";
    patterns.push({ id, no: no ? toText(no.inner) : null, name: h ? toText(h[1]) : null, shape, fields, lines });
  }
  return { patterns, picker: parsePicker(raw, "CREATIVE_LAYOUTS") };
}

/* ─────────────────────────────  VALIDATION  ─────────────────────────────
   The parse signature is self-verifying: preconditions.html carries ct-n ×46 / cl unl ×40, and the
   40-against-46 gap is EXACTLY the six unreachable patterns carrying blocked-by instead of
   unlocks. Any other numbers mean the parse is wrong, so they are asserted rather than trusted. */

const EXPECTED = {
  preconditions: { "ct-n": 46, "ct-cls": 46, "cl req": 46, "cl exc": 46, "cl deg": 46, "cl unl": 40, "cl blk": 6 },
  recipes: { "rc-panel": 12, "rc-n": 12, "rc-lead": 12, "rc-when": 6, "rc-sig": 6, "rc-siglab": 6 },
  openers: { brief: 5, "bk req": 5, "bk cmp": 5, "bk exc": 5, "bk deg": 5 },
  blocks: { catalogue: 20, picker: 19 },
  layouts: { patterns: 25, picker: 25, "caption fields": 4, "caption blob": 8, "caption none": 13 },
};

function assertSignature(which, got) {
  const want = EXPECTED[which];
  const bad = [];
  for (const [k, v] of Object.entries(want)) if (got[k] !== v) bad.push(`${k}: expected ${v}, parsed ${got[k]}`);
  if (bad.length) {
    die(`${which}: parse signature mismatch — the source shape changed or the parser is wrong.\n`
      + bad.map((b) => `    ${b}`).join("\n")
      + `\n  Refusing to emit a digest from a parse that cannot verify itself.`);
  }
}

/* A contract emitted with a clause missing is the one failure a reader swallows in silence: an
   agent obeys a truncated rule without knowing it was truncated. Fatal, never warn. */
function assertContractsWhole(entries) {
  const broken = [];
  for (const e of entries) {
    const missing = [];
    if (!e.name) missing.push("name");
    if (!e.selector) missing.push("selector");
    if (!e.requires) missing.push("requires");
    if (!e.excludes) missing.push("excludes");
    if (!e.degradesTo) missing.push("degrades-to");
    if (!e.unlocks && !e.blockedBy) missing.push("unlocks|blocked-by");
    if (missing.length) broken.push(`${e.name || "<unnamed>"} — lost: ${missing.join(", ")}`);
  }
  if (broken.length) {
    die(`${broken.length} contract(s) would be emitted with a clause missing. An agent obeys a `
      + `truncated rule without knowing it was truncated, so this refuses rather than degrades:\n`
      + broken.map((b) => `    ${b}`).join("\n"));
  }
  const THIN = 24;
  for (const e of entries) {
    for (const [k, v] of Object.entries({ requires: e.requires, excludes: e.excludes, "degrades-to": e.degradesTo })) {
      if (v && v.length < THIN) warn(`${e.name}: ${k} clause is thin (${v.length} chars) — kept, but check the source`);
    }
  }
}

/* ─────────────────────────────  RENDER  ───────────────────────────── */

const H = (n, s) => `${"#".repeat(n)} ${s}`;

/* the page's own word for the grade, plus the rule id it names — never both when they are the same
   string, which is what "human-only: human-only" would read as. */
const checkLabel = (c) => {
  const grade = c.grade === "yes" ? "machine-checkable" : c.grade === "part" ? "structural only" : "human-only";
  return c.label && c.label !== grade ? `${grade}: ${c.label}` : grade;
};

function renderDigest(model) {
  const { pre, rec, op, blocks, layouts, sources, markupName } = model;
  const L = [];
  const push = (...x) => L.push(...x);

  push(`<!-- GENERATED by ${SELF} — do not edit by hand.`);
  push(`     Regenerate:  node ${SELF} --out <this file>  (source paths in kit-digest.sources.json)`);
  push(`     Drift gate:  node __tests__/kit-digest.test.mjs  — asserts regenerate → byte-identical. -->`);
  push("");
  push(H(1, "Proof-kit contract digest"));
  push("");
  push("Every contract in the kit's reference galleries, extracted from the rendered pages with the");
  push("presentation dropped. Prose is **as authored** — nothing here is summarised or rewritten.");
  push("");
  push("Load in tiers — the split follows the sources' own division of labour, one file per question:");
  push("");
  push(`- **this file** — *which block, and am I allowed to use it.* The contract set.`);
  push(`- **\`${model.recipesName}\`** — *how do I compose a whole page.* The 6 sanctioned recipes.`);
  push(`- **\`${markupName}\`** — *what do I paste.* The verbatim markup, load only when emitting.`);
  push("");

  /* provenance */
  push(H(2, "Extracted from"));
  push("");
  push("| source | sha256 | yielded |");
  push("| --- | --- | --- |");
  for (const s of sources) push(`| \`${cell(s.label)}\` | \`${s.sha.slice(0, 12)}\` | ${cell(s.yield)} |`);
  push("");

  /* reach-for index, built only from the galleries' own picker rows */
  const picker = [...(blocks ? blocks.picker : []), ...(layouts ? layouts.picker : [])];
  if (picker.length) {
    push(H(2, `What to reach for — ${picker.length} rows, verbatim from the galleries' own pickers`));
    push("");
    push("| if you need to… | reach for | from |");
    push("| --- | --- | --- |");
    for (const r of picker) push(`| ${cell(r.need)} | ${cell(r.reach)} | ${r.from} |`);
    push("");
  }

  /* the honest-absence index, hoisted to the top because it is the set an agent most needs first */
  if (pre) {
    const blocked = pre.entries.filter((e) => e.unreachable);
    const partial = pre.entries.filter((e) => e.checkable && e.checkable.grade === "part");
    push(H(2, `Unreachable today — ${blocked.length}`));
    push("");
    push("These carry a **blocked-by** clause instead of **unlocks**. Nothing in the corpus can satisfy");
    push("them, so do not reach for them; each row states its blocker as a measurement.");
    push("");
    for (const e of blocked) push(`- **${e.name}** — \`${e.selector}\` — blocked-by: ${e.blockedBy}`);
    push("");
    if (partial.length) {
      push(`Partially checkable (${partial.length}) — the shape passes, a judgment remains: `
        + partial.map((e) => `**${e.name}**`).join(" · "));
      push("");
    }
  }

  /* the contracts, in the source page's own section order */
  if (pre) {
    const bySection = new Map();
    for (const e of pre.entries) {
      const k = e.section || "contracts";
      if (!bySection.has(k)) bySection.set(k, []);
      bySection.get(k).push(e);
    }
    for (const [section, entries] of bySection) {
      push(H(2, section));
      if (entries[0].sectionDek) { push(""); push(`*${entries[0].sectionDek}*`); }
      push("");
      for (const e of entries) {
        const bits = [`\`${e.selector}\``];
        if (e.status) bits.push(e.status);
        if (e.unreachable) bits.push("**UNREACHABLE TODAY**");
        push(H(3, e.name));
        push(bits.join(" · "));
        push("");
        push(`- **requires** — ${e.requires}${e.checkable ? `  \`[${checkLabel(e.checkable)}]\`` : ""}`);
        if (e.blockedBy) push(`- **blocked-by** — ${e.blockedBy}`);
        else push(`- **unlocks** — ${e.unlocks}`);
        push(`- **excludes** — ${e.excludes}`);
        push(`- **degrades to** — ${e.degradesTo}`);
        push("");
      }
    }
  }

  /* openers — second grammar, labelled as such so nobody reads it as the same contract */
  if (op) {
    push(H(2, `Opener hero forms — ${op.forms.length}`));
    push("");
    push("A different contract dialect from the sheet above: the second clause is **Composes**, not");
    push("**unlocks**, and there is no status/checkability channel. Source page: `openers.html` §4.");
    push("");
    for (const f of op.forms) {
      push(H(3, f.name));
      for (const c of f.clauses) push(`- **${c.label.toLowerCase()}** — ${c.value}`);
      if (f.markup) push(`- *copyable markup:* \`${markupName}\` → "${f.name}"`);
      push("");
    }
    push(`> \`openers.html\` carries ${op.sections.length} sections; this digest reads §4 only. Not extracted:`);
    push(`> ${op.sections.filter((s) => !/hero forms/i.test(s)).map((s) => s.split(" — ")[0].trim()).join(" · ")}.`);
    push("");
  }

  /* gallery residue — the fields the contract sheet does not carry */
  if (layouts) {
    const withCap = layouts.patterns.filter((p) => p.shape !== "none");
    const without = layouts.patterns.filter((p) => p.shape === "none");
    push(H(2, `Creative-layout captions — ${withCap.length} of ${layouts.patterns.length}`));
    push("");
    push("`CREATIVE_LAYOUTS.html` carries no four-clause contract; `preconditions.html` above contracts");
    push("the same catalogue. What is here and nowhere else is the **Remix** field — how to adapt.");
    push("");
    for (const p of withCap) {
      const head = `- **${p.no ? p.no + " " : ""}${p.name}** — `;
      if (p.shape === "fields") push(head + Object.keys(p.fields).map((k) => `*${k}:* ${p.fields[k]}`).join(" "));
      else push(head + p.lines.join("  ").trim());
    }
    push("");
    if (without.length) {
      push(`**No caption in the gallery (${without.length})** — these patterns ship with no when/remix`);
      push("guidance at all; their only contract is the sheet above.");
      push("");
      push(without.map((p) => `\`${p.id.replace(/^p-/, "")}\``).join(" · "));
      push("");
    }
  }
  if (blocks) {
    push(H(2, `Static blocks — ${blocks.blocks.length}, use-when only`));
    push("");
    push("`PROOF_BLOCKS.html` carries no four-clause contract either. Its unique field is the");
    push("modifier vocabulary on each block.");
    push("");
    for (const b of blocks.blocks) {
      push(`- **${b.name}**${b.modifier ? ` \`${b.modifier}\`` : ""} — ${b.useWhen || "(no use-when on the page)"}`);
    }
    push("");
  }

  return L.join("\n").replace(/\n{3,}/g, "\n\n").replace(/\s+$/, "") + "\n";
}

function renderRecipes(model) {
  const { rec, markupName, digestName } = model;
  const L = [];
  const push = (...x) => L.push(...x);
  push(`<!-- GENERATED by ${SELF} — do not edit by hand. Companion to ${digestName}. -->`);
  push("");
  push(H(1, `Proof-kit recipes — ${rec.recipes.length} sanctioned compositions`));
  push("");
  push(`Whole-page compositions: what must be true of your material, what to do when it is not, and the`);
  push(`moves in order. Per-block contracts are in \`${digestName}\`; the markup is in \`${markupName}\`.`);
  push("");
    for (const r of rec.recipes) {
      push(H(3, r.title || "(untitled recipe)"));
      if (r.oneline) push(`*${r.oneline}*`);
      push("");
      push(`**Use when** — ${r.useWhen}`);
      push("");
      if (r.preconditions.length) {
        const p = r.panels[0];
        push(`**${p && p.heading ? p.heading : "Precondition brief"}**${p && p.gloss ? ` — ${p.gloss}` : ""}`);
        push("");
        for (const it of r.preconditions) {
          const mark = it.optional ? "○" : "☐";
          let line = `- ${mark} ${it.text}`;
          if (it.why) line += `  \n  *why:* ${it.why}`;
          if (it.unlocks) line += `  \n  *${it.unlocks}*`;
          push(line);
        }
        push("");
      }
      if (r.branches.length) {
        const p = r.panels[1];
        push(`**${p && p.heading ? p.heading : "Failure branch"}**${p && p.gloss ? ` — ${p.gloss}` : ""}`);
        push("");
        push("| severity | when | then |");
        push("| --- | --- | --- |");
        for (const b of r.branches) push(`| ${cell(b.severity || "")} | ${cell(b.when || "")} | ${cell(b.then || "")} |`);
        push("");
      }
      if (r.signature) { push(`**Affordance signature** — ${r.signature}`); push(""); }
      if (r.moves.length) {
        push("**Moves, in this order**");
        push("");
        r.moves.forEach((m, i) => {
          push(`${i + 1}. ${m.move}`);
          if (m.why) push(`   ${m.why}`);
        });
        push("");
      }
      if (r.markup) push(`*Copyable composition* (${r.liftMeta || "whole block"}): \`${markupName}\` → "${r.title}"`);
      push("");
    }
  return L.join("\n").replace(/\n{3,}/g, "\n\n").replace(/\s+$/, "") + "\n";
}

function renderMarkup(model) {
  const { rec, op, markupName, digestName } = model;
  const L = [];
  const push = (...x) => L.push(...x);
  push(`<!-- GENERATED by ${SELF} — do not edit by hand. Companion to ${digestName}. -->`);
  push("");
  push(H(1, "Proof-kit copyable markup"));
  push("");
  push("The emit side, carried through **verbatim** from each gallery's own `<pre>` — the same bytes the");
  push(`rendered example on the page is built from. Contracts and preconditions are in \`${digestName}\`.`);
  push("");
  push(`> One caveat the sources state and this file repeats: \`proof-creative.css\` is entirely`);
  push(`> family-scoped, so a specimen lifted without its \`.fam-*\` ancestor renders unstyled.`);
  push("");

  if (rec) {
    push(H(2, "Recipe compositions"));
    push("");
    for (const r of rec.recipes) {
      if (!r.markup) { warn(`markup: recipe "${r.title}" carries no lift <pre> — nothing to emit`); continue; }
      push(H(3, r.title || "(untitled recipe)"));
      if (r.liftMeta) push(`${r.liftMeta}`);
      push("");
      push("```html");
      push(r.markup);
      push("```");
      push("");
    }
  }
  if (op) {
    push(H(2, "Opener hero forms"));
    push("");
    for (const f of op.forms) {
      if (!f.markup) { warn(`markup: opener "${f.name}" carries no <pre class="src">`); continue; }
      push(H(3, f.name));
      push("");
      push("```html");
      push(f.markup);
      push("```");
      push("");
    }
  }
  return L.join("\n").replace(/\n{3,}/g, "\n\n").replace(/\s+$/, "") + "\n";
}

/* ─────────────────────────────  CLI  ───────────────────────────── */

const SOURCE_KEYS = ["preconditions", "recipes", "openers", "blocks", "layouts"];

function parseArgv(argv) {
  const o = { srcs: {} };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const take = () => { const v = argv[++i]; if (v === undefined) die(`${a} needs a value`); return v; };
    if (a === "--out") o.out = take();
    else if (a === "--markup-out") o.markupOut = take();
    else if (a === "--recipes-out") o.recipesOut = take();
    else if (a === "--sources") o.sources = take();
    else if (a === "--check") o.check = true;
    else if (a === "--stats") o.stats = true;
    else if (a === "-h" || a === "--help") o.help = true;
    else if (a.startsWith("--") && SOURCE_KEYS.includes(a.slice(2))) o.srcs[a.slice(2)] = take();
    else die(`unknown argument: ${a}`);
  }
  return o;
}

const expand = (p) => (p.startsWith("~/") ? path.join(os.homedir(), p.slice(2)) : p);

function main() {
  const opt = parseArgv(process.argv.slice(2));
  if (opt.help) {
    process.stdout.write(fs.readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").slice(0, 44).join("\n") + "\n");
    return;
  }

  /* sources: manifest first (so promotion is a data edit), explicit flags win */
  const manifestPath = expand(opt.sources || path.join(HERE, "kit-digest.sources.json"));
  let manifest = {};
  if (fs.existsSync(manifestPath)) {
    try { manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8")); }
    catch (e) { die(`sources manifest does not parse: ${manifestPath} (${e.message})`); }
  }
  const srcs = {};
  for (const k of SOURCE_KEYS) {
    const raw = opt.srcs[k] || (manifest.sources && manifest.sources[k]);
    if (raw) srcs[k] = expand(raw);
  }
  if (!srcs.preconditions) {
    die("no --preconditions source (and none in the manifest). The contract sheet is the spine of the "
      + "digest; refusing to emit a contract digest with no contracts.");
  }

  const read = (k) => {
    if (!srcs[k]) return null;
    if (!fs.existsSync(srcs[k])) {
      die(`${k} source not found: ${srcs[k]}\n  If the page moved (promotion into the kit), update `
        + `${manifestPath} — a missing source is drift, not an excuse to emit a thinner digest.`);
    }
    return fs.readFileSync(srcs[k], "utf8");
  };

  const rawPre = read("preconditions");
  const rawRec = read("recipes");
  const rawOp = read("openers");
  const rawBlk = read("blocks");
  const rawLay = read("layouts");

  const pre = parsePreconditions(rawPre);
  assertSignature("preconditions", pre.signature);
  assertContractsWhole(pre.entries);

  let rec = null;
  if (rawRec) { rec = parseRecipes(rawRec); assertSignature("recipes", rec.signature); }
  let op = null;
  if (rawOp) { op = parseOpeners(rawOp); assertSignature("openers", op.signature); }
  const blocks = rawBlk ? parseBlocks(rawBlk) : null;
  if (blocks) assertSignature("blocks", { catalogue: blocks.blocks.length, picker: blocks.picker.length });
  const layouts = rawLay ? parseLayouts(rawLay) : null;
  if (layouts) {
    const n = (k) => layouts.patterns.filter((p) => p.shape === k).length;
    assertSignature("layouts", {
      patterns: layouts.patterns.length, picker: layouts.picker.length,
      "caption fields": n("fields"), "caption blob": n("blob"), "caption none": n("none"),
    });
  }

  if (UNKNOWN_ENTITIES.size) {
    die(`unresolved HTML entities would ship into the digest as literal source: `
      + `${[...UNKNOWN_ENTITIES].map((e) => "&" + e + ";").join(" ")}\n  `
      + `A stray entity in a rule an agent reads is exactly the silent corruption this refuses to emit. `
      + `Add them to ENTITIES in ${SELF}.`);
  }

  const outPath = opt.out ? expand(opt.out) : path.join(HERE, "KIT_DIGEST.md");
  const stem = path.join(path.dirname(outPath), path.basename(outPath).replace(/\.md$/, ""));
  const markupPath = opt.markupOut ? expand(opt.markupOut) : stem + "_MARKUP.md";
  const recipesPath = opt.recipesOut ? expand(opt.recipesOut) : stem + "_RECIPES.md";

  const sha = (s) => crypto.createHash("sha256").update(s).digest("hex");
  const sources = [];
  const note = { preconditions: pre.entries.length + " contracts", recipes: rec ? rec.recipes.length + " recipes" : "", openers: op ? op.forms.length + " hero forms (§4 only)" : "", blocks: blocks ? blocks.blocks.length + " blocks + " + blocks.picker.length + " picker rows" : "", layouts: layouts ? layouts.patterns.length + " captions + " + layouts.picker.length + " picker rows" : "" };
  for (const k of SOURCE_KEYS) {
    if (!srcs[k]) continue;
    sources.push({ label: path.basename(srcs[k]), sha: sha(fs.readFileSync(srcs[k], "utf8")), yield: note[k] });
  }

  const model = {
    pre, rec, op, blocks, layouts, sources,
    markupName: path.basename(markupPath),
    recipesName: path.basename(recipesPath),
    digestName: path.basename(outPath),
  };
  const digest = renderDigest(model);
  const recipes = rec ? renderRecipes(model) : null;
  const markup = renderMarkup(model);
  const outputs = [[outPath, digest], [markupPath, markup]];
  if (recipes) outputs.splice(1, 0, [recipesPath, recipes]);

  if (opt.stats) {
    const est = (s) => Math.round(s.length / 4);
    const rawTotal = SOURCE_KEYS.filter((k) => srcs[k]).reduce((n, k) => n + fs.statSync(srcs[k]).size, 0);
    const total = outputs.reduce((n, [, b]) => n + b.length, 0);
    let out = `\n${SELF} — size report\n`
      + `  sources             ${String(rawTotal).padStart(9)} B  (~${est({ length: rawTotal }).toLocaleString()} tok)\n`;
    for (const [p, b] of outputs) {
      out += `  ${path.basename(p).padEnd(20)}${String(b.length).padStart(8)} B  (~${est(b).toLocaleString()} tok)\n`;
    }
    out += `  combined            ${String(total).padStart(9)} B  (~${est({ length: total }).toLocaleString()} tok)\n`
      + `  reduction           ${(rawTotal / total).toFixed(1)}x\n`;
    /* the digest's own section budget — what an agent pays for each thing it loads */
    out += "\n  " + model.digestName + " by section:\n";
    for (const sec of digest.split(/^## /m).slice(1)) {
      out += `    ${String(sec.length).padStart(7)} B  ~${String(Math.round(sec.length / 4)).padStart(6)} tok  ${sec.split("\n")[0].slice(0, 62)}\n`;
    }
    process.stderr.write(out + "\n");
  }

  if (opt.check) {
    let bad = 0;
    for (const [p, want] of outputs) {
      if (!fs.existsSync(p)) { process.stderr.write(`${SELF}: MISSING ${p}\n`); bad++; continue; }
      const got = fs.readFileSync(p, "utf8");
      if (got !== want) {
        const i = [...want].findIndex((c, k) => c !== got[k]);
        process.stderr.write(`${SELF}: DRIFT ${p} — differs at byte ${i}\n`
          + `    committed: ${JSON.stringify(got.slice(Math.max(0, i - 40), i + 60))}\n`
          + `    regenerated: ${JSON.stringify(want.slice(Math.max(0, i - 40), i + 60))}\n`);
        bad++;
      }
    }
    if (bad) { process.stderr.write(`${SELF}: ${bad} output(s) stale — regenerate with --out\n`); process.exit(1); }
    process.stdout.write(`${SELF}: check PASS — both outputs match a fresh extraction\n`);
    return;
  }

  for (const [p, body] of outputs) fs.writeFileSync(p, body);
  process.stdout.write(
    `${SELF}: wrote ${outputs.map(([p, b]) => `${path.basename(p)} (${b.length.toLocaleString()} B)`).join(" + ")}`
    + `${warnings.length ? ` — ${warnings.length} warning(s)` : ""}\n`);
}

main();
