/* jsdom tests for proof-ticket.js — the <prove-ticket> element + auto-scanner + co-delivery parity.
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/__tests__/proof-ticket.test.mjs
 *   (run from anywhere inside the finch repo — jsdom resolves via cwd / git top-level / FINCH_REPO;
 *    board-widgets.test.mjs's minimal DOM shim can't do customElements/attachShadow/TreeWalker,
 *    so this suite runs the component inside a real jsdom window realm.)
 */
import assert from "node:assert";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { execSync } from "node:child_process";

// jsdom is a project dependency, but this test file lives in the engine dir (outside the repo tree),
// so a bare `import "jsdom"` won't resolve. Try several bases so the gate isn't coupled to being run
// from one exact dir: cwd (any subdir of the repo works — require walks up node_modules), the git
// top-level (any checkout), and a FINCH_REPO override for a fully-external cwd.
function resolveJSDOM() {
  const bases = [process.cwd()];
  try { bases.push(execSync("git rev-parse --show-toplevel", { stdio: ["ignore", "pipe", "ignore"] }).toString().trim()); } catch { /* not a git checkout */ }
  if (process.env.FINCH_REPO) bases.push(process.env.FINCH_REPO);
  for (const base of bases) {
    try { return createRequire(path.join(base, "package.json"))("jsdom"); } catch { /* try next base */ }
  }
  throw new Error("Could not resolve 'jsdom'. Run from within the finch repo, or set FINCH_REPO to its root. Tried: " + bases.join(", "));
}
const { JSDOM } = resolveJSDOM();

const here = path.dirname(fileURLToPath(import.meta.url));
const proofSrc = fs.readFileSync(path.join(here, "..", "proof-ticket.js"), "utf8");
const boardSrc = fs.readFileSync(path.join(here, "..", "board-widgets.js"), "utf8");

const BASE = "https://linear.app/finchclaims/issue/";

let COUNT = 0;
function check(cond, msg) { assert.ok(cond, msg); COUNT++; }
function eq(a, b, msg) { assert.strictEqual(a, b, msg); COUNT++; }

function newDom(bodyHtml) {
  return new JSDOM("<!doctype html><html><body>" + bodyHtml + "</body></html>", {
    runScripts: "outside-only"
  });
}
function blobTag(obj) {
  return '<script id="prove-tickets" type="application/json">' + JSON.stringify(obj) + "</script>";
}
// Both kits gate init behind DOMContentLoaded when the doc is still "loading" (jsdom stays
// "loading" after construction). Fire the real event so we exercise the actual auto-wire path.
function fireReady(dom) {
  if (dom.window.document.readyState === "loading") {
    dom.window.document.dispatchEvent(new dom.window.Event("DOMContentLoaded"));
  }
}
function runProof(dom) { dom.window.eval(proofSrc); fireReady(dom); return dom; }
function runBoard(dom) { dom.window.eval(boardSrc); fireReady(dom); return dom; }
function $(dom, sel) { return dom.window.document.querySelector(sel); }
function $$(dom, sel) { return Array.from(dom.window.document.querySelectorAll(sel)); }
function shadow(el) { return el.shadowRoot; }

/* ── 1. key resolution (attr wins over textContent) + correct href ── */
{
  const dom = runProof(newDom(
    '<prove-ticket key="FIN-100">ignore this text</prove-ticket>' +
    "<prove-ticket>FIN-200</prove-ticket>"
  ));
  const els = $$(dom, "prove-ticket");
  eq(els.length, 2, "two prove-ticket elements present");
  const a1 = shadow(els[0]).querySelector("a");
  eq(a1.getAttribute("href"), BASE + "FIN-100", "attr key wins → href FIN-100");
  eq(a1.textContent, "FIN-100", "anchor label is the resolved key, not the textContent");
  const a2 = shadow(els[1]).querySelector("a");
  eq(a2.getAttribute("href"), BASE + "FIN-200", "textContent key → href FIN-200");
  eq(a2.textContent, "FIN-200", "textContent-derived label");
}

/* ── 2. tooltip: title line + dated status line + a11y wiring ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: { "FIN-100": { title: "Fix the widget", status: "In Progress" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const el = $(dom, "prove-ticket");
  const root = shadow(el);
  const a = root.querySelector("a");
  const tip = root.querySelector(".tip");
  eq(a.getAttribute("aria-describedby"), "pt-tip", "anchor describedby → tooltip");
  eq(tip.id, "pt-tip", "tooltip id matches aria-describedby");
  eq(tip.getAttribute("role"), "tooltip", "tooltip has role=tooltip");
  check(tip.hidden === true, "tooltip starts hidden (no hover-only trap: focus also reveals)");
  eq(root.querySelector(".t").textContent, "Fix the widget", "line 1 = baked title");
  const s = root.querySelector(".s").textContent;
  check(/status as of 2026-07-31/.test(s), "line 2 stamps status as a DATED fact");
  check(/In Progress/.test(s), "line 2 shows the baked status value");
  // focus reveals, Escape dismisses (keyboard path, no hover-only trap)
  a.dispatchEvent(new dom.window.Event("focus"));
  check(tip.hidden === false, "focus reveals tooltip");
  a.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: "Escape" }));
  check(tip.hidden === true, "Escape dismisses tooltip");
}

/* ── 3. link-only degradation: key missing from blob, and blob absent entirely ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: { "FIN-100": { title: "x", status: "Done" } } }) +
    '<prove-ticket key="FIN-999">FIN-999</prove-ticket>'
  ));
  const root = shadow($(dom, "prove-ticket"));
  eq(root.querySelector("a").getAttribute("href"), BASE + "FIN-999", "link still works with no metadata");
  eq(root.querySelector(".t").textContent, "Open FIN-999 in Linear", "unknown key → link-only tooltip");
  check(root.querySelector(".s") === null, "no dated-status line when there's no metadata");
}
{
  const dom = runProof(newDom('<prove-ticket key="FIN-321">FIN-321</prove-ticket>')); // no blob at all
  const root = shadow($(dom, "prove-ticket"));
  eq(root.querySelector("a").getAttribute("href"), BASE + "FIN-321", "link works with no blob present");
  eq(root.querySelector(".t").textContent, "Open FIN-321 in Linear", "absent blob → link-only tooltip");
}

/* ── 4. XSS: a malicious baked title is escaped (textContent, never innerHTML) ── */
{
  const evil = '<img src=x onerror="alert(1)">&<b>pwn</b>';
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: { "FIN-100": { title: evil, status: "Backlog" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const root = shadow($(dom, "prove-ticket"));
  check(root.querySelector("img") === null, "no <img> element materialized from a malicious title");
  check(root.querySelector("b") === null, "no <b> element materialized either");
  eq(root.querySelector(".t").textContent, evil, "malicious title survives verbatim as text (proves textContent path)");
}

/* ── 5. scanner wraps bare FIN-XXX keys inside a <p> ── */
{
  const dom = runProof(newDom("<p>See FIN-123 now and FIN-124 too</p>"));
  const p = $(dom, "p");
  const wrapped = p.querySelectorAll("prove-ticket");
  eq(wrapped.length, 2, "both bare keys in the paragraph got wrapped");
  eq(wrapped[0].getAttribute("key"), "FIN-123", "first wrapped key");
  eq(wrapped[1].getAttribute("key"), "FIN-124", "second wrapped key");
  eq(p.textContent, "See FIN-123 now and FIN-124 too", "surrounding prose preserved intact");
}

/* ── 6. scanner SKIPS <code>, <pre>, <a> (and still wraps a control bare key) ── */
{
  const dom = runProof(newDom(
    "<code>FIN-500</code><pre>FIN-501</pre>" +
    '<a href="#x">FIN-502</a><p>bare FIN-503</p>'
  ));
  check($(dom, "code").querySelector("prove-ticket") === null, "no wrapping inside <code>");
  eq($(dom, "code").textContent, "FIN-500", "<code> text untouched");
  check($(dom, "pre").querySelector("prove-ticket") === null, "no wrapping inside <pre>");
  check($(dom, "a").querySelector("prove-ticket") === null, "no re-linkify inside existing <a>");
  check($(dom, "p").querySelector("prove-ticket") !== null, "control: a bare key outside skip-zones IS wrapped");
}

/* ── 7. scanner is idempotent (second run = same DOM, no double-wrap) ── */
{
  const dom = runProof(newDom("<p>Track FIN-900 here</p>"));
  const before = $$(dom, "prove-ticket").length;
  const htmlBefore = dom.window.document.body.innerHTML;
  dom.window.ProveTicket.scan(); // run the scanner a second time
  eq($$(dom, "prove-ticket").length, before, "second scan adds no new wrappers");
  eq(dom.window.document.body.innerHTML, htmlBefore, "second scan leaves the DOM byte-identical");
}

/* ── 8. co-delivery: proof-ticket.js does not perturb FinchBoard.buildPayload() and adds no data-fb-* ── */
{
  const body =
    '<div data-fb-board="b1" data-fb-wave="wave x">' +
    '  <input data-fb-voter value="ann">' +
    '  <div data-fb-item="i1" data-fb-kind="steer">' +
    "    <p>Adopt FIN-777 per discussion</p>" +
    '    <input type="checkbox" data-fb-key="adopt" checked>' +
    "    <textarea data-fb-note>note text</textarea>" +
    "  </div>" +
    "</div>";

  // A: board-widgets.js ALONE
  const domA = runBoard(newDom(body));
  // B: both kits co-inlined (as the publish step does), then a single DOMContentLoaded
  const domB = newDom(body);
  domB.window.eval(boardSrc);
  domB.window.eval(proofSrc);
  fireReady(domB);

  // Format-agnostic non-interference: compare the board's RAW payloadText() (volatile ts normalized)
  // with vs without proof-ticket.js co-loaded. Deliberately shape-blind — the kit owner may evolve
  // the board's payload schema (v1 object → v2 NDJSON events → …); this oracle only asserts our
  // presentation layer perturbs NOTHING, whatever that schema currently is.
  const norm = (dom) => dom.window.FinchBoard.payloadText().replace(/"ts":\s*"[^"]*"/g, '"ts":"_"');
  eq(norm(domA), norm(domB), "board payloadText() identical (ts-normalized) with vs without proof-ticket.js loaded");

  // proof actually ran in B (wrapped FIN-777) but NOT in A (board alone leaves it bare)
  eq($$(domA, "prove-ticket").length, 0, "board-alone page has no prove-ticket elements");
  const pts = $$(domB, "prove-ticket");
  check(pts.length >= 1, "co-delivered page wrapped the bare FIN-777");
  // prove-ticket introduces ZERO data-fb-* attributes (disjoint namespace)
  let fbLeak = 0;
  pts.forEach((pt) => pt.getAttributeNames().forEach((n) => { if (n.indexOf("data-fb") === 0) fbLeak++; }));
  eq(fbLeak, 0, "prove-ticket elements carry no data-fb-* attributes");
  eq($$(domA, "[data-fb-key]").length, $$(domB, "[data-fb-key]").length, "same count of data-fb-key nodes (no board markup disturbed)");
}

/* ── 9. scanner skips a foreign-namespace (SVG) <a> — its tagName is lowercase "a" ── */
{
  const dom = runProof(newDom(
    '<svg xmlns="http://www.w3.org/2000/svg"><a href="#z"><text>FIN-600</text></a></svg>' +
    "<p>bare FIN-601</p>"
  ));
  const svgAnchor = dom.window.document.querySelector("svg a");
  check(svgAnchor !== null, "the SVG <a> exists");
  eq(svgAnchor.tagName, "a", "SVG anchor tagName is lowercase (the exact case the skip-list must catch)");
  check(svgAnchor.querySelector("prove-ticket") === null, "no link nested inside the existing SVG <a>");
  check($(dom, "p").querySelector("prove-ticket") !== null, "control: a bare key outside the SVG IS wrapped");
}

/* ── 10. hyphen-boundary: a key fused to a hyphen/word char is NOT wrapped; a clean one is ── */
{
  const dom = runProof(newDom(
    "<p>branch report-FIN-5-draft stays plain</p>" +
    "<p>but clean FIN-6 wraps</p>"
  ));
  const ps = $$(dom, "p");
  eq(ps[0].querySelectorAll("prove-ticket").length, 0, "hyphen-fused FIN-5 is left as plain text");
  eq(ps[0].textContent, "branch report-FIN-5-draft stays plain", "the fused text is preserved verbatim");
  const clean = ps[1].querySelectorAll("prove-ticket");
  eq(clean.length, 1, "the clean bare key IS wrapped");
  eq(clean[0].getAttribute("key"), "FIN-6", "…as FIN-6");
}

/* ── 11. freshnessOf() bucketing at the boundaries + unknown ── */
{
  const dom = runProof(newDom(""));
  const F = dom.window.ProveTicket.freshnessOf;
  const baked = "2026-07-31T12:00:00Z";
  const base = Date.parse(baked);
  const iso = (msAgo) => new Date(base - msAgo).toISOString();
  const H = 3600e3, D = 24 * H;
  const bucket = (msAgo) => F({ lastActivityAt: iso(msAgo) }, baked);
  eq(bucket(23 * H), "fresh", "23h ago → fresh (<24h)");
  eq(bucket(25 * H), "recent", "25h ago → recent (≤7d, past the 24h edge)");
  eq(bucket(6 * D), "recent", "6d ago → recent");
  eq(bucket(8 * D), "moderate", "8d ago → moderate (past 7d)");
  eq(bucket(29 * D), "moderate", "29d ago → moderate");
  eq(bucket(31 * D), "stale", "31d ago → stale (past 30d)");
  eq(F({}, baked), "unknown", "no date → unknown");
  eq(F(null, baked), "unknown", "null entry → unknown");
  // updatedAt is the fallback when lastActivityAt is absent
  eq(F({ updatedAt: iso(2 * H) }, baked), "fresh", "falls back to updatedAt when lastActivityAt absent");
  // clock skew: activity 'after' bake clamps to freshest, never negative-buckets
  eq(F({ lastActivityAt: new Date(base + D).toISOString() }, baked), "fresh", "activity after bake → fresh (clamped)");
}

/* ── 12. inline freshness dot: class matches bucket + a11y title present ── */
{
  const baked = "2026-07-31T12:00:00Z";
  const recentIso = new Date(Date.parse(baked) - 3 * 24 * 3600e3).toISOString();
  const dom = runProof(newDom(
    blobTag({ bakedAt: baked, tickets: { "FIN-100": { title: "T", status: "In Progress", statusType: "started", lastActivityAt: recentIso } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const root = shadow($(dom, "prove-ticket"));
  const dot = root.querySelector(".dot");
  check(dot !== null, "a freshness dot renders on the inline ref");
  check(dot.classList.contains("dot-recent"), "3d-old activity → dot-recent class");
  check(/last activity/.test(dot.getAttribute("title") || ""), "dot carries a human title (color is not the only channel)");
  eq(dot.getAttribute("title"), dot.getAttribute("aria-label"), "dot title mirrored to aria-label");
  check(dot.getAttribute("role") === "img", "dot is exposed as an image with a label");
  // teaser gains a 'last activity' line when a date exists
  check(root.querySelector(".la") !== null, "teaser shows a last-activity line");
}
{
  // no-date entry → unknown dot, and NO last-activity teaser line
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: { "FIN-100": { title: "T", status: "Done" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const root = shadow($(dom, "prove-ticket"));
  check(root.querySelector(".dot").classList.contains("dot-unknown"), "dateless entry → dot-unknown");
  check(root.querySelector(".la") === null, "no last-activity line when there is no date");
}

/* ── 13. choosePlacement(): below when room / flip above near bottom / clamp horizontally ── */
{
  const P = runProof(newDom("")).window.ProveTicket.choosePlacement;
  const size = { width: 320, height: 240 };
  const vp = { width: 1000, height: 800 };
  const below = P({ top: 100, bottom: 120, left: 50, right: 100 }, vp, size);
  eq(below.placement, "below", "room below → placed below");
  eq(below.top, 126, "below top = anchor.bottom + gap");
  eq(below.left, 50, "left aligned to anchor when it fits");
  const flip = P({ top: 760, bottom: 780, left: 50, right: 100 }, vp, size);
  eq(flip.placement, "above", "near the bottom edge → flips above");
  eq(flip.top, 514, "above top = anchor.top - gap - height");
  const clampR = P({ top: 100, bottom: 120, left: 900, right: 950 }, vp, size);
  eq(clampR.left, 672, "near right edge → left clamped to viewport.width - margin - width");
  const clampL = P({ top: 100, bottom: 120, left: -50, right: 0 }, vp, size);
  eq(clampL.left, 8, "off the left edge → left clamped to margin");
}

/* ── 14. card open: role=dialog + aria-expanded; Escape closes and RETURNS focus to the ref ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": { title: "Panel votes", status: "In Progress", statusType: "started", description: "A body." } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const pt = $(dom, "prove-ticket");
  const a = shadow(pt).querySelector("a");
  eq(a.getAttribute("aria-haspopup"), "dialog", "ref advertises a dialog popup");
  eq(a.getAttribute("aria-expanded"), "false", "ref starts collapsed");
  a.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  const card = $(dom, "prove-ticket-card");
  check(card !== null && card.hidden === false, "click opens the shared card");
  check(shadow(card).querySelector("[role=dialog]") !== null, "card exposes role=dialog");
  eq(a.getAttribute("aria-expanded"), "true", "ref now aria-expanded=true");
  check(shadow(card).querySelector("[role=dialog]").getAttribute("aria-labelledby") === "pt-card-title", "dialog is labelled by its title");
  // Escape closes + returns focus to the opener (jsdom retargets shadow focus to the host element)
  dom.window.document.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: "Escape" }));
  check(card.hidden === true, "Escape closes the card");
  eq(a.getAttribute("aria-expanded"), "false", "ref collapsed again after close");
  check(dom.window.document.activeElement === pt, "focus returned to the ref (its shadow host) on close");
}

/* ── 15. card outside-click closes ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": { title: "X", status: "Done", statusType: "completed" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket><p id="elsewhere">click me</p>'
  ));
  const a = shadow($(dom, "prove-ticket")).querySelector("a");
  a.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  const card = $(dom, "prove-ticket-card");
  check(card.hidden === false, "card open before outside click");
  $(dom, "#elsewhere").dispatchEvent(new dom.window.MouseEvent("mousedown", { bubbles: true }));
  check(card.hidden === true, "mousedown outside the card closes it");
}

/* ── 16. tabs: switching shows the right panel; Activity renders ≤5 events, comment vs state distinct ── */
{
  const acts = [];
  for (let i = 0; i < 7; i++) acts.push({ author: "u" + i, ts: "2026-07-31T0" + i + ":00:00Z", kind: i % 2 ? "state" : "comment", text: "e" + i });
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": { title: "Tabbed", status: "In Progress", statusType: "started", description: "desc", activity: acts } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const a = shadow($(dom, "prove-ticket")).querySelector("a");
  a.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  const root = shadow($(dom, "prove-ticket-card"));
  const tabs = root.querySelectorAll("[role=tab]");
  eq(tabs.length, 3, "three tabs (Overview/Activity/Relations)");
  const panelOf = (id) => root.querySelector("#pt-panel-" + id);
  eq(panelOf("overview").hidden, false, "overview panel visible on open");
  eq(panelOf("activity").hidden, true, "activity panel hidden on open");
  // click the Activity tab
  const activityTab = root.querySelector("#pt-tab-activity");
  activityTab.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  eq(activityTab.getAttribute("aria-selected"), "true", "activity tab selected after click");
  eq(panelOf("activity").hidden, false, "activity panel shown after switching");
  eq(panelOf("overview").hidden, true, "overview panel hidden after switching");
  const evts = root.querySelectorAll(".pt-evt");
  eq(evts.length, 5, "activity capped at last-5 events (7 baked → 5 shown)");
  check(root.querySelectorAll(".pt-evt--state").length > 0, "state events rendered distinctly");
  check(root.querySelectorAll(".pt-evt--comment").length > 0, "comment events rendered distinctly");
  // arrow-key roving on the tablist
  activityTab.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
  eq(root.querySelector("#pt-tab-relations").getAttribute("aria-selected"), "true", "ArrowRight roves to the next tab");
}

/* ── 17. relations: clicking a relation chip re-anchors the card to that key's content ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: {
      "FIN-100": { title: "Origin", status: "In Progress", statusType: "started", relations: [{ key: "FIN-200", type: "related", title: "The Other" }] },
      "FIN-200": { title: "Destination", status: "Backlog", statusType: "backlog", description: "dest body" }
    } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const pt = $(dom, "prove-ticket");
  const a = shadow(pt).querySelector("a");
  a.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  const card = $(dom, "prove-ticket-card");
  const root = shadow(card);
  root.querySelector("#pt-tab-relations").dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  const chip = root.querySelector(".pt-rel");
  check(chip !== null && chip.getAttribute("data-key") === "FIN-200", "relation chip for FIN-200 present");
  chip.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  eq(root.querySelector("#pt-card-title").textContent, "Destination", "card content re-anchored to FIN-200");
  check(card.hidden === false, "card stays open across relation navigation");
  // navigation must not orphan the focus-return target: Escape still returns to the ORIGINAL ref
  dom.window.document.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: "Escape" }));
  check(dom.window.document.activeElement === pt, "focus returns to the original ref after cross-ticket browse");
}

/* ── 18. back-compat: an iteration-1 {title,status}-only blob still renders (dot=unknown + minimal card) ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: { "FIN-100": { title: "Legacy entry", status: "Done" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const pt = $(dom, "prove-ticket");
  check(shadow(pt).querySelector(".dot").classList.contains("dot-unknown"), "legacy entry → unknown dot (no false freshness)");
  const a = shadow(pt).querySelector("a");
  a.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  const root = shadow($(dom, "prove-ticket-card"));
  eq(root.querySelector("#pt-card-title").textContent, "Legacy entry", "minimal Overview still shows the title");
  check(/No description baked/.test(root.querySelector("#pt-panel-overview").textContent), "no-description graceful text");
  root.querySelector("#pt-tab-activity").dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  check(/No recent activity/.test(root.querySelector("#pt-panel-activity").textContent), "empty activity handled, no error");
}

/* ── 19. XSS: hostile description, comment text, and author are inert (textContent, never innerHTML) ── */
{
  // Note: avoid a literal </script> in any baked string — it would close the fixture's <script id="prove-tickets">
  // block before the JSON ends (a fixture hazard, not a code path). The img/svg payloads exercise the same
  // textContent-vs-innerHTML seam without that nesting problem.
  const evilDesc = '<img src=x onerror="alert(1)"><b>d</b>';
  const evilText = '<img src=y onerror="alert(2)">c';
  const evilAuthor = '<svg onload=alert(3)>hax';
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": {
      title: "T", status: "In Progress", statusType: "started",
      description: evilDesc,
      activity: [{ author: evilAuthor, ts: "2026-07-31T06:00:00Z", kind: "comment", text: evilText }]
    } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const a = shadow($(dom, "prove-ticket")).querySelector("a");
  a.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  const root = shadow($(dom, "prove-ticket-card"));
  const desc = root.querySelector(".desc");
  check(desc.querySelector("img") === null, "no <img> materializes from a hostile description");
  check(desc.querySelector("b") === null, "no <b> from the description either");
  eq(desc.childNodes.length, 1, "description is a single inert text node (no parsed markup)");
  eq(desc.textContent, evilDesc, "hostile description survives verbatim as inert text");
  root.querySelector("#pt-tab-activity").dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  check(root.querySelector("svg") === null, "no <svg> element from a hostile author");
  check(root.querySelector("script") === null, "no <script> element from hostile comment text");
  check(/hax/.test(root.querySelector(".pt-evt-hd").textContent), "hostile author rendered as text");
  eq(root.querySelector(".pt-evt-text").textContent, evilText, "hostile comment text rendered verbatim as text");
}

/* ── 20. zero-external-request by construction: the source holds no network path ── */
{
  check(!/\bfetch\s*\(/.test(proofSrc), "source contains no fetch( call");
  check(!/XMLHttpRequest/.test(proofSrc), "source contains no XMLHttpRequest");
  check(!/\bimport\s*\(/.test(proofSrc), "source contains no dynamic import()");
  check(!/\bWebSocket\b/.test(proofSrc), "source opens no WebSocket");
  check(!/EventSource/.test(proofSrc), "source opens no EventSource");
  check(!/navigator\.sendBeacon/.test(proofSrc), "source sends no beacon");
}

console.log("proof-ticket.test: PASS — " + COUNT + " assertions (iter-1: key/href, tooltip+a11y, dated status, link-only, XSS-escape, scanner wrap/skip/idempotent, co-delivery non-interference, SVG-anchor skip, hyphen-boundary; iter-2: freshness bucketing+dot+a11y, choosePlacement below/flip/clamp, card dialog+aria-expanded+Escape/outside-click+return-focus, tabs+roving+activity last-5 comment/state, relation re-anchor, back-compat, XSS on desc/comment/author, zero-request grep)");
