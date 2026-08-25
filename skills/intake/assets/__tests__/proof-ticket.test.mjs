/* jsdom tests for proof-ticket.js — the <prove-ticket> element + auto-scanner + co-delivery parity.
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/__tests__/proof-ticket.test.mjs
 *   (run from anywhere inside the finch repo — jsdom resolves via cwd / git top-level / FINCH_REPO;
 *    board-widgets.test.mjs's minimal DOM shim can't do customElements/TreeWalker, so this suite
 *    runs the component inside a real jsdom window realm.)
 *
 * LIGHT-DOM: the component renders into light DOM (no Shadow DOM) so it can consume the page's WARM
 * PRINT design tokens. These tests therefore query the document directly (no shadowRoot), assert the
 * kill of all hardcoded palette (tokens/classes, never hex), the non-color freshness channel, and
 * per-instance id-uniqueness.
 */
import assert from "node:assert";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { execSync } from "node:child_process";

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
const cssSrc = fs.readFileSync(path.join(here, "..", "proof-ticket.css"), "utf8");

const BASE = "https://linear.app/finchclaims/issue/";
const SVGNS = "http://www.w3.org/2000/svg";

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
function fireReady(dom) {
  if (dom.window.document.readyState === "loading") {
    dom.window.document.dispatchEvent(new dom.window.Event("DOMContentLoaded"));
  }
}
function runProof(dom) { dom.window.eval(proofSrc); fireReady(dom); return dom; }
function runBoard(dom) { dom.window.eval(boardSrc); fireReady(dom); return dom; }
function $(dom, sel) { return dom.window.document.querySelector(sel); }
function $$(dom, sel) { return Array.from(dom.window.document.querySelectorAll(sel)); }
// light DOM: the ref's rendered markup lives inside the <prove-ticket> element itself.
function link(el) { return el.querySelector("a.pt-link"); }
function openCard(dom, pt) {
  link(pt).dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  return $(dom, "prove-ticket-card");
}
function svgAttr(node, name) { return node.getAttribute(name); }

/* ── 1. key resolution (attr wins over textContent) + correct href ── */
{
  const dom = runProof(newDom(
    '<prove-ticket key="FIN-100">ignore this text</prove-ticket>' +
    "<prove-ticket>FIN-200</prove-ticket>"
  ));
  const els = $$(dom, "prove-ticket");
  eq(els.length, 2, "two prove-ticket elements present");
  const a1 = link(els[0]);
  eq(a1.getAttribute("href"), BASE + "FIN-100", "attr key wins → href FIN-100");
  eq(a1.textContent, "FIN-100", "anchor label is the resolved key, not the textContent");
  const a2 = link(els[1]);
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
  const a = link(el);
  const tip = el.querySelector(".pt-tip");
  check(/^pt-tip-\d+$/.test(tip.id), "tooltip id is per-instance uniquified (pt-tip-<uid>)");
  eq(a.getAttribute("aria-describedby"), tip.id, "anchor describedby → its own tooltip id");
  eq(tip.getAttribute("role"), "tooltip", "tooltip has role=tooltip");
  check(tip.hidden === true, "tooltip starts hidden (no hover-only trap: focus also reveals)");
  eq(el.querySelector(".pt-tip-title").textContent, "Fix the widget", "line 1 = baked title");
  const s = el.querySelector(".pt-tip-status").textContent;
  check(/status as of 2026-07-31/.test(s), "line 2 stamps status as a DATED fact");
  check(/In Progress/.test(s), "line 2 shows the baked status value");
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
  const el = $(dom, "prove-ticket");
  eq(link(el).getAttribute("href"), BASE + "FIN-999", "link still works with no metadata");
  eq(el.querySelector(".pt-tip-title").textContent, "Open FIN-999 in Linear", "unknown key → link-only tooltip");
  check(el.querySelector(".pt-tip-status") === null, "no dated-status line when there's no metadata");
  check(el.querySelector(".pt-dot").classList.contains("pt-dot-unknown"), "unknown key → unknown dot (graceful degradation)");
}
{
  const dom = runProof(newDom('<prove-ticket key="FIN-321">FIN-321</prove-ticket>')); // no blob at all
  const el = $(dom, "prove-ticket");
  eq(link(el).getAttribute("href"), BASE + "FIN-321", "link works with no blob present");
  eq(el.querySelector(".pt-tip-title").textContent, "Open FIN-321 in Linear", "absent blob → link-only tooltip");
  check(el.querySelector(".pt-dot").classList.contains("pt-dot-unknown"), "absent blob → unknown dot");
}

/* ── 4. XSS: a malicious baked title is escaped (textContent, never innerHTML) ── */
{
  const evil = '<img src=x onerror="alert(1)">&<b>pwn</b>';
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: { "FIN-100": { title: evil, status: "Backlog" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const el = $(dom, "prove-ticket");
  check(el.querySelector("img") === null, "no <img> element materialized from a malicious title");
  check(el.querySelector("b") === null, "no <b> element materialized either");
  eq(el.querySelector(".pt-tip-title").textContent, evil, "malicious title survives verbatim as text (proves textContent path)");
}

/* ── 5. scanner wraps bare FIN-XXX keys inside a <p> ── */
{
  const dom = runProof(newDom("<p>See FIN-123 now and FIN-124 too</p>"));
  const p = $(dom, "p");
  const wrapped = p.querySelectorAll("prove-ticket");
  eq(wrapped.length, 2, "both bare keys in the paragraph got wrapped");
  eq(wrapped[0].getAttribute("key"), "FIN-123", "first wrapped key");
  eq(wrapped[1].getAttribute("key"), "FIN-124", "second wrapped key");
  // light DOM: the surrounding prose text nodes are preserved intact between the wrappers
  const proseNodes = Array.from(p.childNodes).filter((n) => n.nodeType === 3).map((n) => n.nodeValue).join("|");
  eq(proseNodes, "See | now and | too", "surrounding prose text nodes preserved intact around the wrappers");
  eq(link(wrapped[0]).textContent, "FIN-123", "first anchor labels its key");
  eq(link(wrapped[1]).textContent, "FIN-124", "second anchor labels its key");
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

  const domA = runBoard(newDom(body));
  const domB = newDom(body);
  domB.window.eval(boardSrc);
  domB.window.eval(proofSrc);
  fireReady(domB);

  const norm = (dom) => dom.window.FinchBoard.payloadText().replace(/"ts":\s*"[^"]*"/g, '"ts":"_"');
  eq(norm(domA), norm(domB), "board payloadText() identical (ts-normalized) with vs without proof-ticket.js loaded");

  eq($$(domA, "prove-ticket").length, 0, "board-alone page has no prove-ticket elements");
  const pts = $$(domB, "prove-ticket");
  check(pts.length >= 1, "co-delivered page wrapped the bare FIN-777");
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
  eq(F({ updatedAt: iso(2 * H) }, baked), "fresh", "falls back to updatedAt when lastActivityAt absent");
  eq(F({ lastActivityAt: new Date(base + D).toISOString() }, baked), "fresh", "activity after bake → fresh (clamped)");
}

/* ── 12. inline freshness dot: class matches bucket + a11y title + non-color fill channel ── */
{
  const baked = "2026-07-31T12:00:00Z";
  const recentIso = new Date(Date.parse(baked) - 3 * 24 * 3600e3).toISOString();
  const dom = runProof(newDom(
    blobTag({ bakedAt: baked, tickets: { "FIN-100": { title: "T", status: "In Progress", statusType: "started", lastActivityAt: recentIso } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const el = $(dom, "prove-ticket");
  const dot = el.querySelector(".pt-dot");
  check(dot !== null, "a freshness dot renders on the inline ref");
  check(dot.classList.contains("pt-dot-recent"), "3d-old activity → pt-dot-recent class");
  eq(dot.getAttribute("data-fill"), "three-quarter", "recent bucket → three-quarter non-color fill (survives greyscale)");
  check(/last activity/.test(dot.getAttribute("title") || ""), "dot carries a human title (color is not the only channel)");
  eq(dot.getAttribute("title"), dot.getAttribute("aria-label"), "dot title mirrored to aria-label");
  check(dot.getAttribute("role") === "img", "dot is exposed as an image with a label");
  check(!/#[0-9a-fA-F]{3,6}/.test(dot.getAttribute("style") || ""), "dot carries no inline hex color (token via CSS class)");
  check(el.querySelector(".pt-tip-age") !== null, "teaser shows a last-activity line");
}
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: { "FIN-100": { title: "T", status: "Done" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const el = $(dom, "prove-ticket");
  const dot = el.querySelector(".pt-dot");
  check(dot.classList.contains("pt-dot-unknown"), "dateless entry → pt-dot-unknown");
  eq(dot.getAttribute("data-fill"), "ring", "dateless entry → ring fill (non-color unknown shape)");
  check(el.querySelector(".pt-tip-age") === null, "no last-activity line when there is no date");
}

/* ── 12b. non-color channel is DISTINCT across every bucket (survives with no color at all) ── */
{
  const baked = "2026-07-31T12:00:00Z";
  const base = Date.parse(baked);
  const H = 3600e3, D = 24 * H;
  const mk = (msAgo, extra) => ({ lastActivityAt: new Date(base - msAgo).toISOString(), ...extra });
  const cases = [
    ["FIN-1", mk(1 * H), "full"],
    ["FIN-2", mk(3 * D), "three-quarter"],
    ["FIN-3", mk(10 * D), "half"],
    ["FIN-4", mk(60 * D), "quarter"],
    ["FIN-5", {}, "ring"]
  ];
  const tickets = {};
  cases.forEach(([k, entry]) => { tickets[k] = { title: "T", ...entry }; });
  const dom = runProof(newDom(
    blobTag({ bakedAt: baked, tickets }) +
    cases.map(([k]) => `<prove-ticket key="${k}">${k}</prove-ticket>`).join("")
  ));
  const fills = $$(dom, "prove-ticket .pt-dot").map((d) => d.getAttribute("data-fill"));
  eq(fills.join(","), "full,three-quarter,half,quarter,ring", "each bucket carries a DISTINCT fill-fraction word (a real non-color channel)");
  eq(new Set(fills).size, 5, "all five fill fractions are distinct");
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
  const a = link(pt);
  eq(a.getAttribute("aria-haspopup"), "dialog", "ref advertises a dialog popup");
  eq(a.getAttribute("aria-expanded"), "false", "ref starts collapsed");
  const card = openCard(dom, pt);
  check(card !== null && card.hidden === false, "click opens the shared card");
  const dialog = card.querySelector("[role=dialog]");
  check(dialog !== null, "card exposes role=dialog");
  eq(a.getAttribute("aria-expanded"), "true", "ref now aria-expanded=true");
  const titleId = dialog.getAttribute("aria-labelledby");
  check(/^pt-card-title-\d+$/.test(titleId), "dialog is labelled by its uniquified title id");
  eq(card.querySelector(".pt-title").id, titleId, "the title element carries that id");
  dom.window.document.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: "Escape" }));
  check(card.hidden === true, "Escape closes the card");
  eq(a.getAttribute("aria-expanded"), "false", "ref collapsed again after close");
  eq(dom.window.document.activeElement, a, "focus returned to the ref's anchor on close (light DOM)");
}

/* ── 15. card outside-click closes ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": { title: "X", status: "Done", statusType: "completed" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket><p id="elsewhere">click me</p>'
  ));
  const card = openCard(dom, $(dom, "prove-ticket"));
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
  const card = openCard(dom, $(dom, "prove-ticket"));
  const tabs = card.querySelectorAll("[role=tab]");
  eq(tabs.length, 3, "three tabs (Overview/Activity/Relations)");
  const panelOf = (id) => card.querySelector('[data-panel="' + id + '"]');
  eq(panelOf("overview").hidden, false, "overview panel visible on open");
  eq(panelOf("activity").hidden, true, "activity panel hidden on open");
  const activityTab = card.querySelector('[data-tab="activity"]');
  activityTab.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  eq(activityTab.getAttribute("aria-selected"), "true", "activity tab selected after click");
  eq(panelOf("activity").hidden, false, "activity panel shown after switching");
  eq(panelOf("overview").hidden, true, "overview panel hidden after switching");
  const evts = card.querySelectorAll(".pt-evt");
  eq(evts.length, 5, "activity capped at last-5 events (7 baked → 5 shown)");
  check(card.querySelectorAll(".pt-evt--state").length > 0, "state events rendered distinctly");
  check(card.querySelectorAll(".pt-evt--comment").length > 0, "comment events rendered distinctly");
  activityTab.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
  eq(card.querySelector('[data-tab="relations"]').getAttribute("aria-selected"), "true", "ArrowRight roves to the next tab");
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
  const a = link(pt);
  const card = openCard(dom, pt);
  card.querySelector('[data-tab="relations"]').dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  const chip = card.querySelector(".pt-rel");
  check(chip !== null && chip.getAttribute("data-key") === "FIN-200", "relation chip for FIN-200 present");
  chip.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  eq(card.querySelector(".pt-title").textContent, "Destination", "card content re-anchored to FIN-200");
  check(card.hidden === false, "card stays open across relation navigation");
  dom.window.document.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: "Escape" }));
  eq(dom.window.document.activeElement, a, "focus returns to the original ref's anchor after cross-ticket browse");
}

/* ── 18. back-compat: an iteration-1 {title,status}-only blob still renders (dot=unknown + minimal card) ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: { "FIN-100": { title: "Legacy entry", status: "Done" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const pt = $(dom, "prove-ticket");
  check(pt.querySelector(".pt-dot").classList.contains("pt-dot-unknown"), "legacy entry → unknown dot (no false freshness)");
  const card = openCard(dom, pt);
  eq(card.querySelector(".pt-title").textContent, "Legacy entry", "minimal Overview still shows the title");
  check(/No description baked/.test(card.querySelector('[data-panel="overview"]').textContent), "no-description graceful text");
  card.querySelector('[data-tab="activity"]').dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  check(/No recent activity/.test(card.querySelector('[data-panel="activity"]').textContent), "empty activity handled, no error");
}

/* ── 19. XSS: hostile description, comment text, and author are inert (textContent, never innerHTML) ── */
{
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
  const card = openCard(dom, $(dom, "prove-ticket"));
  const desc = card.querySelector(".pt-desc");
  check(desc.querySelector("img") === null, "no <img> materializes from a hostile description");
  check(desc.querySelector("b") === null, "no <b> from the description either");
  eq(desc.childNodes.length, 1, "description is a single inert text node (no parsed markup)");
  eq(desc.textContent, evilDesc, "hostile description survives verbatim as inert text");
  card.querySelector('[data-tab="activity"]').dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  check(card.querySelector("svg") === null, "no <svg> element from a hostile author");
  check(card.querySelector("script") === null, "no <script> element from hostile comment text");
  check(/hax/.test(card.querySelector(".pt-evt-hd").textContent), "hostile author rendered as text");
  eq(card.querySelector(".pt-evt-text").textContent, evilText, "hostile comment text rendered verbatim as text");
}

/* ── 20. [v4] the ONE request is its own sibling tickets.json — never the tracker, never a channel ──
 *
 * v3 asserted "no fetch( anywhere", which encoded the inline-only MECHANISM rather than the
 * property it was standing in for. v4 fetches, so the assertion is restated as that property:
 * the component talks to exactly one thing — the ticket-data JSON published beside the page —
 * carries no credentials, and opens no persistent or outbound channel. The gate that always
 * mattered (a browser must never call the TRACKER: no CORS route, and it would leak the reader's
 * identity to it) is now asserted directly instead of by proxy.
 */
{
  check(/\bfetch\s*\(\s*url\b/.test(proofSrc), "the only fetch( call takes the resolved tickets-JSON url");
  check(/credentials\s*:\s*["']omit["']/.test(proofSrc), "the fetch is credentials:'omit' (so the bucket may answer Access-Control-Allow-Origin: *)");
  check(/withCredentials\s*=\s*false/.test(proofSrc), "the XHR fallback likewise sends no credentials");
  check(!/\bimport\s*\(/.test(proofSrc), "source contains no dynamic import()");
  check(!/\bWebSocket\b/.test(proofSrc), "source opens no WebSocket");
  check(!/EventSource/.test(proofSrc), "source opens no EventSource");
  check(!/navigator\.sendBeacon/.test(proofSrc), "source sends no beacon");
  // The tracker host appears only as a link href / allow-list prefix, never as a request target.
  check(/linear\.app/.test(proofSrc), "the tracker host appears (as the permalink base)");
  check(!/(fetch|\.open|\.send)\s*\([^)]*linear\.app/.test(proofSrc), "…and never inside a request call");
  check(!/(fetch|\.open)\s*\([^)]*TRACKER_ISSUE_BASE/.test(proofSrc), "no request is ever aimed at TRACKER_ISSUE_BASE");
}

/* ── 20b. [v4] the fetch is GATED: inline blob wins, no refs / no derivable url ⇒ no request ── */
{
  // (a) an inline blob wins outright — nothing is requested.
  const withBlob = newDom(blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-1": { title: "T" } } }) + "<p>FIN-1</p>");
  let calls = 0;
  withBlob.window.fetch = () => { calls++; return Promise.reject(new Error("should not run")); };
  runProof(withBlob);
  eq(calls, 0, "a page carrying an inline blob issues NO request (offline-honest path preserved)");
  eq(withBlob.window.ProveTicket.dataState().state, "inline", "…and reports state=inline");

  // (b) a page with no ticket references never asks for ticket data.
  const noRefs = newDom("<p>nothing to see here</p>");
  let calls2 = 0;
  noRefs.window.fetch = () => { calls2++; return Promise.reject(new Error("nope")); };
  runProof(noRefs);
  eq(calls2, 0, "a page with zero ticket refs issues NO request");
  eq(noRefs.window.ProveTicket.dataState().state, "absent", "…and reports state=absent");

  // (c) refs but no derivable url (jsdom's about:blank has no http(s) sibling) ⇒ still no request.
  const noUrl = newDom("<p>FIN-4242</p>");
  let calls3 = 0;
  noUrl.window.fetch = () => { calls3++; return Promise.reject(new Error("nope")); };
  runProof(noUrl);
  eq(calls3, 0, "refs on a non-http page issue NO request (a guessed sibling is a guaranteed failure)");
  eq(noUrl.window.ProveTicket.dataState().state, "absent", "…and reports state=absent, not error");
}

/* ── 21. [#1] baked meta.url of a non-http scheme never becomes a live href (javascript: sink) ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": {
      title: "T", status: "In Progress", statusType: "started",
      url: "javascript:alert(document.domain)"
    } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const card = openCard(dom, $(dom, "prove-ticket"));
  const href = card.querySelector(".pt-keylink").getAttribute("href");
  check(!/^javascript:/i.test(href), "javascript: url is rejected as an href");
  eq(href, BASE + "FIN-100", "unsafe baked url falls back to the constructed tracker permalink");
  const dom2 = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": {
      title: "T", status: "Done", url: "https://linear.app/finchclaims/issue/FIN-100/some-slug"
    } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const card2 = openCard(dom2, $(dom2, "prove-ticket"));
  eq(card2.querySelector(".pt-keylink").getAttribute("href"),
    "https://linear.app/finchclaims/issue/FIN-100/some-slug", "a valid https permalink is preserved");
  const dom3 = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": { title: "T", url: "data:text/html,<x>1</x>" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const card3 = openCard(dom3, $(dom3, "prove-ticket"));
  eq(card3.querySelector(".pt-keylink").getAttribute("href"), BASE + "FIN-100", "data: url falls back to the safe permalink");
}

/* ── 22. [#2/#3] focusables()/trap exclude controls in the hidden panel; trap wraps (no escape) ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: {
      "FIN-100": { title: "Origin", status: "In Progress", statusType: "started",
        relations: [{ key: "FIN-200", type: "related", title: "Other" }] }
    } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const card = openCard(dom, $(dom, "prove-ticket"));
  const relPanel = card.querySelector('[data-panel="relations"]');
  const chip = card.querySelector(".pt-rel");
  check(relPanel.hidden === true, "relations panel is hidden while Overview is active");
  const f = card.focusables();
  check(f.indexOf(chip) === -1, "focusables() excludes the relation chip inside the hidden panel");
  check(!relPanel.contains(f[f.length - 1]), "focusables() 'last' is a genuinely reachable control, not a hidden-panel chip");
  const overviewTab = card.querySelector('[data-tab="overview"]');
  overviewTab.focus();
  const tabEv = new dom.window.KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true });
  dom.window.document.dispatchEvent(tabEv);
  check(tabEv.defaultPrevented, "Tab at the last visible control wraps inside the card (trap holds, no escape via hidden chips)");
  card.querySelector('[data-tab="relations"]').dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  const f2 = card.focusables();
  check(f2.indexOf(chip) !== -1, "after switching to the Relations tab, the chip is included in focusables()");
}

/* ── 23. [#4] the shipped source carries no literal </script> (only the loss-free escaped form) ── */
{
  check(proofSrc.indexOf("</" + "script>") === -1, "source contains no literal close-script token (inline-embed safe)");
  check(proofSrc.indexOf("<\\/script>") !== -1, "the header example uses the escaped <\\/script> form");
}

/* ── 24. [#5] activity sorts newest-first before capping → oldest-first bake shows the NEWEST 5 ── */
{
  const acts = [];
  for (let i = 0; i < 6; i++) acts.push({ author: "u" + i, ts: "2026-07-31T0" + i + ":00:00Z", kind: "comment", text: "e" + i });
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": { title: "T", status: "In Progress", statusType: "started", activity: acts } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const card = openCard(dom, $(dom, "prove-ticket"));
  card.querySelector('[data-tab="activity"]').dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  const texts = Array.from(card.querySelectorAll(".pt-evt-text")).map((n) => n.textContent);
  eq(texts.length, 5, "activity still capped at 5");
  eq(texts[0], "e5", "newest event (e5) renders first despite oldest-first bake");
  check(texts.indexOf("e0") === -1, "the oldest event (e0) is dropped, not shown as 'recent'");
  check(texts.indexOf("e1") !== -1, "the 5 newest (e1..e5) are the ones shown");
}

/* ── 25. [#6] missing/unparseable bakedAt → freshness degrades to unknown (never wall-clock) ── */
{
  const F = runProof(newDom("")).window.ProveTicket.freshnessOf;
  const A = runProof(newDom("")).window.ProveTicket.ageString;
  const entry = { lastActivityAt: "2026-05-01T00:00:00Z" };
  eq(F(entry, ""), "unknown", "missing bakedAt → freshness unknown (no wall-clock bucketing)");
  eq(F(entry, "not-a-date"), "unknown", "unparseable bakedAt → freshness unknown");
  eq(A(entry, ""), "", "missing bakedAt → no confident age string");
  eq(A(entry, "garbage"), "", "unparseable bakedAt → no age string");
  eq(F(entry, "2026-05-01T05:00:00Z"), "fresh", "a valid bakedAt still buckets (5h gap → fresh)");
}

/* ── 26. [#6] rendered card with a garbage bakedAt shows the unknown dot, not a false 'stale' ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "garbage", tickets: { "FIN-100": { title: "T", status: "In Progress", statusType: "started", lastActivityAt: "2026-01-01T00:00:00Z" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const pt = $(dom, "prove-ticket");
  check(pt.querySelector(".pt-dot").classList.contains("pt-dot-unknown"), "garbage bakedAt → inline dot is unknown, not a wall-clock 'stale'");
}

/* ── 27. [SVG] a bare FIN in <svg><text> → an SVG-namespace <a>+<tspan>, key kept ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-3519": { title: "SVG ticket", status: "In Progress", statusType: "started", lastActivityAt: "2026-07-30T18:00:00Z" } } }) +
    '<svg xmlns="http://www.w3.org/2000/svg" width="300" height="80"><text x="10" y="40">Depends on FIN-3519 here</text></svg>' +
    "<p>bare FIN-3520</p>"
  ));
  const svg = dom.window.document.querySelector("svg");
  const svgA = svg.querySelector("a[data-pt-key]");
  check(svgA !== null, "SVG <text> FIN key → an SVG <a> affordance is created (key not lost)");
  eq(svgA.namespaceURI, SVGNS, "the affordance <a> is SVG-namespace (createElementNS, not an HTML element)");
  eq(svgA.getAttribute("data-pt-key"), "FIN-3519", "affordance carries the resolved key");
  const tspan = svgA.querySelector("tspan");
  check(tspan !== null && tspan.namespaceURI === SVGNS, "the SVG <a> wraps an SVG-namespace <tspan>");
  check(/FIN-3519/.test(tspan.textContent), "the key text survives inside the <tspan> (not silently eaten)");
  eq(svgA.getAttribute("href"), BASE + "FIN-3519", "href resolves via safeHref → constructed permalink (no baked url)");
  check(svg.querySelector("prove-ticket") === null, "no HTML <prove-ticket> injected into SVG (the latent corruption bug is fixed)");
  check(dom.window.document.querySelector("p prove-ticket") !== null, "control: a bare key in HTML prose still wraps as <prove-ticket>");
}

/* ── 28. [SVG] freshness dot: <circle> gets the bucket CLASS + token fill (no hex attr); placement guards zero geometry ── */
{
  const baked = "2026-07-31T12:00:00Z";
  const recentIso = new Date(Date.parse(baked) - 3 * 24 * 3600e3).toISOString();
  const dom = runProof(newDom(
    blobTag({ bakedAt: baked, tickets: { "FIN-3519": { title: "T", status: "In Progress", statusType: "started", lastActivityAt: recentIso } } }) +
    '<svg xmlns="http://www.w3.org/2000/svg"><text x="10" y="40">See FIN-3519</text></svg>'
  ));
  const svg = dom.window.document.querySelector("svg");
  const dot = svg.querySelector("circle[data-pt-dot]");
  check(dot !== null, "an SVG <circle> freshness dot is emitted as a sibling in the <svg>");
  eq(dot.namespaceURI, SVGNS, "the dot is an SVG-namespace <circle>");
  eq(svgAttr(dot, "data-pt-bucket"), "recent", "3d-old activity → the recent bucket on the dot");
  check(/\bpt-dot-recent\b/.test(svgAttr(dot, "class")), "the dot carries the pt-dot-recent CLASS (color via CSS token, not a hex attr)");
  eq(svgAttr(dot, "data-fill"), "three-quarter", "non-color size channel word present on the SVG dot");
  check(svgAttr(dot, "fill") === null, "no hardcoded hex fill attribute — CSS `fill: var(--recent)` wins");
  await new Promise((r) => setTimeout(r, 20));
  check(svgAttr(dot, "cx") === null, "deferred dot placement no-ops under zero jsdom geometry — no bogus coordinates, no crash");
}
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: { "FIN-3519": { title: "T", status: "Done" } } }) +
    '<svg xmlns="http://www.w3.org/2000/svg"><text>FIN-3519</text></svg>'
  ));
  const dot = dom.window.document.querySelector("svg circle[data-pt-dot]");
  eq(svgAttr(dot, "data-pt-bucket"), "unknown", "dateless SVG entry → unknown dot bucket");
  eq(svgAttr(dot, "data-fill"), "ring", "unknown SVG dot → ring fill word");
  check(/\bpt-dot-unknown\b/.test(svgAttr(dot, "class")), "unknown dot carries the pt-dot-unknown class (fill:none via CSS)");
  check(svgAttr(dot, "fill") === null, "unknown dot carries no hardcoded fill attribute");
}

/* ── 29. [SVG] click the SVG <a> → the SAME shared card opens, anchored to that key's data ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-3519": { title: "SVG panel", status: "In Progress", statusType: "started", description: "body" } } }) +
    '<svg xmlns="http://www.w3.org/2000/svg"><text x="10" y="40">Blocks FIN-3519</text></svg>'
  ));
  const svgA = dom.window.document.querySelector("svg a[data-pt-key]");
  check(svgA !== null, "the SVG affordance is present before the click");
  eq(svgA.getAttribute("aria-haspopup"), "dialog", "the SVG <a> advertises a dialog popup");
  eq(svgA.getAttribute("role"), "link", "the SVG <a> carries an explicit role=link");
  svgA.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  const card = $(dom, "prove-ticket-card");
  check(card !== null && card.hidden === false, "clicking the SVG <a> opens the SAME shared <prove-ticket-card>");
  check(card.querySelector("[role=dialog]") !== null, "the shared card exposes role=dialog");
  eq(card.querySelector(".pt-title").textContent, "SVG panel", "the card is anchored to the clicked SVG key's baked data");
}

/* ── 30. [SVG] foreignObject unregressed: an HTML label inside <foreignObject> keeps the HTML affordance ── */
{
  const dom = runProof(newDom(
    '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject width="200" height="50">' +
    '<div xmlns="http://www.w3.org/1999/xhtml">Label FIN-3521 here</div></foreignObject></svg>' +
    "<p>bare FIN-3522</p>"
  ));
  const fo = dom.window.document.querySelector("foreignObject");
  const pt = fo.querySelector("prove-ticket");
  check(pt !== null, "a FIN key inside a foreignObject HTML <div> still gets the HTML <prove-ticket> affordance");
  eq(pt.getAttribute("key"), "FIN-3521", "…wrapping the right key");
  check(fo.querySelector("a[data-pt-key]") === null, "no SVG-namespace affordance is created inside the HTML foreignObject");
}

/* ── 31. [SVG] idempotent: a second scan does not double-wrap the SVG key or duplicate the dot ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-3519": { title: "T", status: "Done", statusType: "completed", lastActivityAt: "2026-07-30T12:00:00Z" } } }) +
    '<svg xmlns="http://www.w3.org/2000/svg"><text x="10" y="40">Track FIN-3519 now</text></svg>'
  ));
  const svg = dom.window.document.querySelector("svg");
  const beforeA = svg.querySelectorAll("a[data-pt-key]").length;
  const beforeDots = svg.querySelectorAll("circle[data-pt-dot]").length;
  eq(beforeA, 1, "one SVG affordance after the first scan");
  eq(beforeDots, 1, "one SVG dot after the first scan");
  dom.window.ProveTicket.scan();
  eq(svg.querySelectorAll("a[data-pt-key]").length, beforeA, "second scan adds no new SVG affordance (idempotent)");
  eq(svg.querySelectorAll("circle[data-pt-dot]").length, beforeDots, "second scan adds no new SVG dot");
}

/* ── 32. [SVG] a key already inside an SVG <a> is not re-wrapped into our affordance ── */
{
  const dom = runProof(newDom(
    '<svg xmlns="http://www.w3.org/2000/svg"><a href="https://linear.app/finchclaims/issue/FIN-600"><text>FIN-600</text></a></svg>'
  ));
  const svgAnchor = dom.window.document.querySelector("svg a");
  check(svgAnchor.getAttribute("data-pt-key") === null, "the pre-existing SVG <a> is not converted into our affordance");
  eq(svgAnchor.querySelectorAll("a").length, 0, "no nested <a> is created inside the existing SVG <a>");
  eq(svgAnchor.querySelector("text").textContent, "FIN-600", "the key text inside the existing SVG <a> is left untouched");
}

/* ── 33. URL guard: a FIN inside a plain-text URL is NOT wrapped (HTML + SVG); prose keys still wrap ── */
{
  const dom = runProof(newDom(
    "<p>ref https://linear.app/finchclaims/issue/FIN-3519 done</p>" +
    "<p>see (FIN-3520) and issue FIN-3521</p>"
  ));
  const ps = $$(dom, "p");
  eq(ps[0].querySelectorAll("prove-ticket").length, 0, "a FIN inside a plain-text URL is left as plain text (HTML path)");
  check(/https:\/\/linear\.app\/finchclaims\/issue\/FIN-3519/.test(ps[0].textContent), "the URL text is preserved verbatim");
  const wrapped = ps[1].querySelectorAll("prove-ticket");
  eq(wrapped.length, 2, "parenthesized and prose keys still wrap (guard does not over-reject)");
  eq(wrapped[0].getAttribute("key"), "FIN-3520", "(FIN-3520) wraps");
  eq(wrapped[1].getAttribute("key"), "FIN-3521", "issue FIN-3521 wraps");
  const dom2 = runProof(newDom(
    '<svg xmlns="http://www.w3.org/2000/svg"><text x="10" y="40">url https://linear.app/finchclaims/issue/FIN-3519 end</text></svg>'
  ));
  check(dom2.window.document.querySelector("svg a[data-pt-key]") === null, "a FIN inside a plain-text URL is left plain in SVG <text> too (guard shared)");
}

/* ── 34. [light-DOM] neither custom element uses Shadow DOM (renders into light DOM to share tokens) ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: { "FIN-100": { title: "T", status: "Done", statusType: "completed" } } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>'
  ));
  const pt = $(dom, "prove-ticket");
  check(pt.shadowRoot === null, "<prove-ticket> has NO shadowRoot (light DOM)");
  check(pt.querySelector(".pt-wrap") !== null, "its markup is rendered directly into light DOM");
  const card = openCard(dom, pt);
  check(card.shadowRoot === null, "<prove-ticket-card> has NO shadowRoot (light DOM)");
  check(card.querySelector(".pt-card") !== null, "the card markup is rendered directly into light DOM");
  check(!/attachShadow/.test(proofSrc), "the source no longer calls attachShadow anywhere");
}

/* ── 35. [tokens] no hardcoded palette anywhere: source has no freshness/status hex or Canvas; CSS uses var() ── */
{
  // The component source (JS) must not carry any freshness/status/system color literal. The only
  // allowed URL is TRACKER_ISSUE_BASE (contains no hex). Grep for hex triples/pairs and CSS system colors.
  const jsHexMatches = (proofSrc.match(/#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b/g) || [])
    .filter((h) => h !== "#fff"); // (#fff appears only in the CSS string as pill text-on-color, allowed)
  eq(jsHexMatches.length, 0, "proof-ticket.js carries no palette hex (freshness/status colors are tokens): " + jsHexMatches.join(","));
  check(!/\bCanvas\b|\bCanvasText\b/.test(proofSrc), "no CSS system-color keyword (Canvas/CanvasText) — replaced by --card/--ink tokens");
  // The stylesheet now lives ONLY in proof-ticket.css (the JS ships no CSS). It must reference the
  // tokens, not the raw palette.
  ["--fresh", "--recent", "--moderate", "--stale", "--unknown", "--card", "--ink", "--rule", "--accent"]
    .forEach((tok) => check(cssSrc.indexOf("var(" + tok + ")") !== -1, "proof-ticket.css consumes " + tok));
  ["--status-started", "--status-completed", "--status-canceled", "--status-backlog", "--status-unstarted", "--status-triage"]
    .forEach((tok) => check(cssSrc.indexOf("var(" + tok + ")") !== -1, "proof-ticket.css maps the pill to " + tok));
  check(!/#16a34a|#65a30d|#d97706|#9ca3af|#2563eb|#6b7280|#8b5cf6/.test(cssSrc), "proof-ticket.css carries NONE of the old hardcoded freshness/status hexes");
}

/* ── 36. [tokens] the status pill uses a per-type CLASS mapped to a token — never an inline hex ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31T12:00:00Z", tickets: {
      "FIN-100": { title: "T", status: "In Progress", statusType: "started" },
      "FIN-200": { title: "U", status: "Weird", statusType: "nonsense" },
      "FIN-300": { title: "V", status: "NoType" }
    } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>' +
    '<prove-ticket key="FIN-200">FIN-200</prove-ticket>' +
    '<prove-ticket key="FIN-300">FIN-300</prove-ticket>'
  ));
  const els = $$(dom, "prove-ticket");
  const c1 = openCard(dom, els[0]);
  const pill1 = c1.querySelector(".pt-pill");
  check(pill1.classList.contains("pt-pill-started"), "known statusType → pt-pill-started class (token background)");
  check(!/background/.test(pill1.getAttribute("style") || ""), "pill sets NO inline background (no pill.style.background hex)");
  els[0].querySelector("a.pt-link").focus();
  // reuse the shared card for the unknown-statusType ticket
  const c2 = openCard(dom, els[1]);
  const pill2 = c2.querySelector(".pt-pill");
  check(pill2.classList.contains("pt-pill") && !/pt-pill-/.test(pill2.className.replace("pt-pill", "")), "unknown statusType → base .pt-pill only (falls back to --ink-soft token)");
  const c3 = openCard(dom, els[2]);
  check(c3.querySelector(".pt-pill") !== null, "a status with no statusType still renders a pill (default token bg)");
}

/* ── 37. [ids] two <prove-ticket> on one page get DISTINCT ids + correctly-wired aria (no collision) ── */
{
  const dom = runProof(newDom(
    blobTag({ bakedAt: "2026-07-31", tickets: {
      "FIN-100": { title: "One", status: "Done" },
      "FIN-200": { title: "Two", status: "Done" }
    } }) +
    '<prove-ticket key="FIN-100">FIN-100</prove-ticket>' +
    '<prove-ticket key="FIN-200">FIN-200</prove-ticket>'
  ));
  const els = $$(dom, "prove-ticket");
  const tip1 = els[0].querySelector(".pt-tip");
  const tip2 = els[1].querySelector(".pt-tip");
  check(tip1.id !== tip2.id, "the two tooltips have DISTINCT ids (no light-DOM id collision)");
  eq(link(els[0]).getAttribute("aria-describedby"), tip1.id, "ref #1 describedby points at ITS OWN tooltip");
  eq(link(els[1]).getAttribute("aria-describedby"), tip2.id, "ref #2 describedby points at ITS OWN tooltip");
  // no duplicate ids anywhere in the document
  const ids = $$(dom, "[id]").map((n) => n.id);
  eq(ids.length, new Set(ids).size, "no duplicate element ids in the whole document");
}

/* ── 38. [degradation] the JS enhancer never fetches; a no-blob page degrades to link + unknown dot ── */
{
  const dom = runProof(newDom("<p>plain FIN-4242 with no metadata blob</p>"));
  const pt = $(dom, "prove-ticket");
  check(pt !== null, "the enhancer still wraps the bare key with no blob");
  eq(link(pt).getAttribute("href"), BASE + "FIN-4242", "…as a working plain link");
  check(pt.querySelector(".pt-dot").classList.contains("pt-dot-unknown"), "…with an unknown (ring) freshness dot");
  eq(pt.querySelector(".pt-dot").getAttribute("data-fill"), "ring", "…carrying the ring non-color shape");
}

/* ── 39. [contract] the component is BEHAVIOR-ONLY: it ships no CSS and injects no <style> — styling
       comes from proof-ticket.css, a real linkable asset the page provides ── */
{
  // Source carries no embedded stylesheet and no self-injection machinery.
  check(!/PT_CSS/.test(proofSrc), "proof-ticket.js no longer embeds a PT_CSS constant");
  check(!/ensureStyles/.test(proofSrc), "proof-ticket.js no longer defines/calls ensureStyles()");
  check(!/pt-styles/.test(proofSrc), "proof-ticket.js no longer references the id=pt-styles injection guard");
  check(!/createElement\(\s*["']style["']\s*\)/.test(proofSrc), "proof-ticket.js never creates a <style> element");
  // Running the component injects NOTHING into the head, even after a scan.
  const dom = runProof(newDom("<p>FIN-4242</p>"));
  dom.window.ProveTicket.scan();
  eq($$(dom, "style").length, 0, "no <style> is auto-injected anywhere (behavior-only)");
  eq($(dom, "#pt-styles"), null, "no id=pt-styles stylesheet is created");
  // proof-ticket.css remains the authoritative source (present + token-consuming, checked in test 35).
  const norm = (s) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\s+/g, "");
  check(norm(cssSrc).length > 0, "proof-ticket.css is non-empty (the sole source of the component's styling)");
  // When the page PROVIDES proof-ticket.css, the component still renders + functions.
  const styled = newDom("<style>" + cssSrc + "</style>" + "<prove-ticket key=\"FIN-100\">FIN-100</prove-ticket>");
  runProof(styled);
  const pt = $(styled, "prove-ticket");
  check(pt.querySelector("a.pt-link") !== null, "with proof-ticket.css linked, the ref renders");
  const card = openCard(styled, pt);
  check(card.querySelector(".pt-card") !== null, "…and the card still opens (behavior intact)");
}

/* ── 40. [version] PROOF_TICKET_VERSION is declared (publish-kit.sh greps it) and bumped past 1 ── */
{
  const m = proofSrc.match(/PROOF_TICKET_VERSION\s*=\s*(\d+)/);
  check(m !== null, "PROOF_TICKET_VERSION is declared in the source (publish-kit.sh reads it)");
  check(Number(m[1]) >= 4, "PROOF_TICKET_VERSION bumped to >= 4 for the fetched-tickets.json rework");
  eq(runProof(newDom("")).window.ProveTicket.PROOF_TICKET_VERSION, Number(m[1]), "the exported version matches the source constant");
}

/* ══ iter-5 (v4): FETCHED sibling tickets.json, loud failure, internal item refs ══════════════ */

// A jsdom window whose location is a real http(s) URL, so the sibling-URL convention is exercised
// rather than short-circuited. `fetchImpl` stands in for the network.
function httpDom(bodyHtml, url, fetchImpl) {
  const dom = new JSDOM("<!doctype html><html><body>" + bodyHtml + "</body></html>", {
    runScripts: "outside-only", url: url || "https://bucket.example.com/proofs/yarik/wave3-a1b2c3d4.html"
  });
  dom.window.fetch = fetchImpl || (() => Promise.reject(new TypeError("Failed to fetch")));
  return dom;
}
// The component paints on data arrival, which is a microtask behind the fetch promise. Drain.
const settle = () => new Promise((r) => setTimeout(r, 0));
function jsonRes(obj) {
  return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(JSON.stringify(obj)) });
}

/* ── 41. [v4] sibling-URL resolution: <link rel> wins, then <meta>, then the .html→.tickets.json convention ── */
{
  const conv = httpDom("<p>FIN-1</p>");
  runProof(conv);
  eq(conv.window.ProveTicket.ticketsUrl(),
    "https://bucket.example.com/proofs/yarik/wave3-a1b2c3d4.tickets.json",
    "convention: the page's own key with .html swapped for .tickets.json");

  const declared = httpDom('<link rel="prove-tickets" href="https://bucket.example.com/proofs/kit/wave3.tickets.json"><p>FIN-1</p>');
  runProof(declared);
  eq(declared.window.ProveTicket.ticketsUrl(),
    "https://bucket.example.com/proofs/kit/wave3.tickets.json",
    "an explicit <link rel=prove-tickets> overrides the convention (this is what survives re-hosting)");

  const viaMeta = httpDom('<meta name="prove-tickets" content="https://bucket.example.com/shared.json"><p>FIN-1</p>');
  runProof(viaMeta);
  eq(viaMeta.window.ProveTicket.ticketsUrl(), "https://bucket.example.com/shared.json", "<meta name=prove-tickets> also works");

  // A file:// / about: page derives NOTHING — a guessed sibling there is a guaranteed failure.
  eq(runProof(newDom("<p>FIN-1</p>")).window.ProveTicket.ticketsUrl(), "", "no sibling is guessed off a non-http(s) address");
}

/* ── 42. [v4] the happy fetch path: refs upgrade in place, and the card shows the JSON's OWN bakedAt ── */
{
  let asked = null;
  const dom = httpDom("<p>see FIN-3519 for the fix</p>", undefined, (u, opts) => {
    asked = { url: u, opts };
    return jsonRes({
      bakedAt: "2026-07-30T09:00:00Z",
      tickets: { "FIN-3519": {
        title: "Fetched title", status: "In Progress", statusType: "started",
        assignee: "Yarik", lastActivityAt: "2026-07-30T06:00:00Z",
        description: "from the sibling json"
      } }
    });
  });
  runProof(dom);
  // Before the data lands the ref is already a working link with an unknown dot — first paint is
  // never blocked, and the degraded state is the INITIAL state rather than a failure mode.
  const early = $(dom, "prove-ticket");
  check(early !== null, "the ref is wrapped immediately, before any data arrives");
  eq(early.getAttribute("data-pt-source"), "loading", "…and is marked as loading, not as missing");

  await settle();

  eq(asked.url, "https://bucket.example.com/proofs/yarik/wave3-a1b2c3d4.tickets.json", "the sibling JSON is what was requested");
  eq(asked.opts.credentials, "omit", "…with credentials omitted");
  const pt = $(dom, "prove-ticket");
  eq(pt.getAttribute("data-pt-source"), "fetched", "the ref now reports data-pt-source=fetched");
  eq(pt.querySelector(".pt-tip-title").textContent, "Fetched title", "the teaser shows the FETCHED title");
  check(pt.querySelector(".pt-dot").classList.contains("pt-dot-fresh"), "…and the dot buckets against the JSON's bakedAt (fresh)");
  eq(dom.window.ProveTicket.dataState().state, "fetched", "dataState() reports fetched");
  eq(dom.window.ProveTicket.dataState().bakedAt, "2026-07-30T09:00:00Z", "…carrying the JSON's own bakedAt");
  eq(dom.window.document.documentElement.getAttribute("data-prove-tickets"), "fetched", "<html> is stamped with the state");
  eq(dom.window.document.documentElement.getAttribute("data-prove-tickets-baked-at"), "2026-07-30T09:00:00Z", "…and with the DATA's timestamp");

  const card = openCard(dom, pt);
  const fresh = card.querySelector(".pt-fresh").textContent;
  check(/ticket data as of 2026-07-30T09:00:00Z/.test(fresh),
    "the card dates the DATA ('ticket data as of <JSON bakedAt>'), not the page");
  check(!/as of 2026-07-31/.test(fresh), "…and never a timestamp the JSON did not supply");
}

/* ── 43. [v4] a re-baked shared JSON moves the stated date: the page states the DATA's freshness ──
 *
 * The consequence of sharing one JSON across pages: its bakedAt can change after a page shipped.
 * The honest behaviour is that the page reports whatever the DATA says, so two loads of the same
 * unchanged page state two different (and each time correct) dates.
 */
{
  const mk = (baked) => httpDom("<p>FIN-77</p>", undefined, () => jsonRes({
    bakedAt: baked, tickets: { "FIN-77": { title: "T", status: "Todo", lastActivityAt: baked } }
  }));
  const a = mk("2026-06-01T00:00:00Z"); runProof(a); await settle();
  const b = mk("2026-07-31T00:00:00Z"); runProof(b); await settle();
  const dateOf = (dom) => openCard(dom, $(dom, "prove-ticket")).querySelector(".pt-fresh").textContent;
  check(/ticket data as of 2026-06-01/.test(dateOf(a)), "load A states the JSON's June date");
  check(/ticket data as of 2026-07-31/.test(dateOf(b)), "load B of the SAME page states the re-baked July date");
}

/* ── 44. [v4] LOUD failure: a 404 / CORS block degrades to working links AND says why, everywhere ── */
{
  for (const [name, impl] of [
    ["404", () => Promise.resolve({ ok: false, status: 404, text: () => Promise.resolve("") })],
    ["CORS block", () => Promise.reject(new TypeError("Failed to fetch"))],
    ["unparseable JSON", () => Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve("<html>nope") })]
  ]) {
    const dom = httpDom('<p data-prove-tickets-status></p><p>blocked on FIN-9001</p>', undefined, impl);
    runProof(dom);
    await settle();
    const pt = $(dom, "prove-ticket");
    // 1. still a WORKING link with an unknown dot — nothing is lost.
    eq(link(pt).getAttribute("href"), BASE + "FIN-9001", name + ": the ref is still a working tracker link");
    check(pt.querySelector(".pt-dot").classList.contains("pt-dot-unknown"), name + ": …with an unknown dot");
    eq(pt.querySelector(".pt-dot").getAttribute("data-fill"), "ring", name + ": …carrying the ring non-color shape");
    // 2. and it is LOUD: the dot no longer claims the innocuous 'activity date unknown'.
    eq(pt.querySelector(".pt-dot").getAttribute("aria-label"), "ticket data unavailable — link only",
      name + ": the dot says the DATA is unavailable, not that the ticket has no date");
    eq(pt.getAttribute("data-pt-source"), "unavailable", name + ": the ref is marked data-pt-source=unavailable");
    eq(dom.window.document.documentElement.getAttribute("data-prove-tickets"), "error", name + ": <html> carries data-prove-tickets=error");
    // 3. the PAGE gets to say why.
    const host = $(dom, "[data-prove-tickets-status]");
    check(/Ticket data unavailable/.test(host.textContent), name + ": the page's status host states the failure");
    check(/tickets\.json/.test(host.textContent), name + ": …names the URL it could not load");
    check(/MISSING, not empty/.test(host.textContent), name + ": …and distinguishes missing from empty");
    // 4. so does the card the reader actually opens.
    const card = openCard(dom, pt);
    const alert = card.querySelector(".pt-alert");
    check(alert !== null, name + ": the card carries a failure banner");
    eq(alert.getAttribute("role"), "alert", name + ": …announced as an alert");
    check(card.querySelector(".pt-retry") !== null, name + ": …with a Retry control");
    check(/could not be loaded/.test(card.querySelector(".pt-empty").textContent),
      name + ": the empty panels say 'could not be loaded', never 'none baked'");
  }
  // Contrast: a CLEAN load carries no banner at all — the chrome appears only when it must.
  const ok = httpDom("<p>FIN-1</p>", undefined, () => jsonRes({ bakedAt: "2026-07-30T09:00:00Z", tickets: { "FIN-1": { title: "T" } } }));
  runProof(ok); await settle();
  eq(openCard(ok, $(ok, "prove-ticket")).querySelector(".pt-alert"), null, "a clean load shows no banner");
}

/* ── 45. [v4] the CORS reason is named, because that is the failure an attached copy actually hits ── */
{
  const dom = httpDom("<p>FIN-1</p>", undefined, () => Promise.reject(new TypeError("Failed to fetch")));
  runProof(dom); await settle();
  const msg = dom.window.ProveTicket.dataState().detail;
  check(/CORS/.test(msg), "the failure sentence names CORS — the one cause a reader can act on");
  check(/blocked|unreachable/.test(msg), "…without claiming to know which of the two it was");
}

/* ── 45b. [v4] an EMPTY prove-tickets meta is a source DECLARED AS NONE, not a fall-through ──
 * publish-s3.sh injects this on a page that carries ticket refs but has no baked JSON to upload.
 * Without it the convention tier derives a sibling nobody uploaded, and the reader gets a 403
 * banner for a file the publisher knew did not exist. The meta must therefore short-circuit the
 * convention: zero requests, state=absent, no banner — and the refs still work. */
{
  const dom = httpDom('<meta name="prove-tickets" content=""><p data-prove-tickets-status></p><p>FIN-1</p>');
  let calls = 0;
  dom.window.fetch = () => { calls++; return Promise.reject(new Error("should not run")); };
  runProof(dom); await settle();
  eq(calls, 0, "an empty prove-tickets meta issues NO request — the convention tier is short-circuited");
  eq(dom.window.ProveTicket.dataState().state, "absent", "…and the page reports absent, never error");
  eq($(dom, "[data-prove-tickets-status]").getAttribute("data-state"), "absent",
    "…so the status host renders the absent (hidden) state, not the failure banner");
  eq(link($(dom, "prove-ticket")).getAttribute("href"), BASE + "FIN-1", "…and the ref is still a working link");
}

/* ── 46. [v4] internal item refs: resolve against the page, no fetch, unresolvable left as prose ── */
{
  const board =
    '<p>see decision [2], and also [f34c8270] — but [0-9] is a regex and [99] does not exist.</p>' +
    '<section id="f34c8270" data-fb-item="f34c8270" data-fb-channel="observed-problems">' +
      '<span class="decno">1</span><span class="dectitle">Backfilled-provenance defect</span>' +
      '<span class="statechip open">open · ranked 1st</span></section>' +
    '<section id="aad7b15a" data-fb-item="aad7b15a">' +
      '<span class="decno">2</span><span class="dectitle">Second decision</span>' +
      '<span class="statechip">deferred</span></section>';
  let calls = 0;
  const dom = newDom(board);
  dom.window.fetch = () => { calls++; return Promise.reject(new Error("no")); };
  runProof(dom);

  const refs = $$(dom, "prove-ref");
  eq(refs.length, 2, "exactly the two RESOLVABLE bracket tokens became refs");
  eq(calls, 0, "internal refs need no network at all — the answer is already in the DOM");

  // [2] resolves by ORDINAL (what prose means), [f34c8270] by id.
  eq(refs[0].getAttribute("data-pt-item"), "aad7b15a", "[2] resolves to the item whose .decno is 2, not the 2nd in DOM order");
  eq(refs[1].getAttribute("data-pt-item"), "f34c8270", "[f34c8270] resolves by id / data-fb-item");
  eq(refs[0].querySelector("a.pt-link").getAttribute("href"), "#aad7b15a", "…and the link is a real in-page anchor");
  eq(refs[0].querySelector("a.pt-link").textContent, "[2]", "…whose label is the token exactly as authored");

  // The unresolvable ones are untouched prose — no affordance may point nowhere.
  const prose = $(dom, "p").textContent;
  check(/\[0-9\] is a regex/.test(prose), "[0-9] stays plain text (it is a regex, not a decision)");
  check(/\[99\] does not exist/.test(prose), "[99] stays plain text (no such item)");

  // The teaser reads title + state off the ITEM's own DOM.
  const tip = refs[0].querySelector(".pt-tip");
  eq(tip.querySelector(".pt-tip-title").textContent, "Second decision", "the teaser title comes from the item's .dectitle");
  eq(tip.querySelector(".pt-tip-status").textContent, "deferred", "…and the state from its .statechip");

  // The mark opens the SAME shared card in item mode, with dialog a11y and a jump action.
  const mark = refs[1].querySelector("button.pt-mark");
  check(mark !== null, "each internal ref carries a § mark button (the card affordance)");
  mark.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  const card = $(dom, "prove-ticket-card");
  eq(card.querySelectorAll(".pt-card").length, 1, "the SHARED card is reused — no second popover implementation");
  eq(card.querySelector(".pt-card").getAttribute("role"), "dialog", "…still a dialog");
  eq(card.querySelector(".pt-title").textContent, "Backfilled-provenance defect", "…titled from the item's own DOM");
  eq(card.querySelector(".pt-pill").textContent, "open · ranked 1st", "…with the item's state");
  check(/observed-problems/.test(card.querySelector(".pt-metarow").textContent), "…and its channel");
  eq(card.querySelector('[role=tablist]'), null, "item mode has no tabs (there is nothing tabbed to show)");
  const go = card.querySelector(".pt-go");
  check(go !== null, "…and a 'Go to decision' action");
  eq(dom.window.document.activeElement, go, "…which is focused first, so Enter jumps immediately");

  // Clicking it scrolls to the item and moves focus there.
  let scrolled = null;
  const target = dom.window.document.getElementById("f34c8270");
  target.scrollIntoView = () => { scrolled = "f34c8270"; };
  go.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  eq(scrolled, "f34c8270", "clicking it scrollIntoViews the item");
  eq(dom.window.document.activeElement, target, "…and moves focus there, not just the viewport");

  // The ref's own link jumps too (native anchor semantics: Enter on <a> fires click).
  let scrolled2 = null;
  const t2 = dom.window.document.getElementById("aad7b15a");
  t2.scrollIntoView = () => { scrolled2 = "aad7b15a"; };
  refs[0].querySelector("a.pt-link").dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  eq(scrolled2, "aad7b15a", "clicking the ref link itself jumps to the item");
}

/* ── 47. [v4] the two reference kinds go through ONE scanner, one skip-list, one card ── */
{
  const html =
    '<section id="a1" data-fb-item="a1"><span class="decno">1</span><span class="dectitle">One</span></section>' +
    '<p>FIN-500 relates to [1].</p>' +
    '<code>FIN-501 and [1] in code</code><a href="#x">FIN-502 and [1] in a link</a>';
  const dom = runProof(newDom(html));
  eq($$(dom, "prove-ticket").length, 1, "one ticket ref wrapped (the <code>/<a> ones skipped)");
  eq($$(dom, "prove-ref").length, 1, "one internal ref wrapped (same skip-list applies to both kinds)");
  check(/FIN-501 and \[1\] in code/.test($(dom, "code").textContent), "<code> content untouched for BOTH kinds");
  check(/FIN-502 and \[1\] in a link/.test($(dom, "a[href='#x']").textContent), "<a> content untouched for BOTH kinds");
  // Idempotent across both kinds.
  dom.window.ProveTicket.scan();
  eq($$(dom, "prove-ticket").length, 1, "a second scan double-wraps neither kind");
  eq($$(dom, "prove-ref").length, 1, "…including internal refs");
  // Both kinds share the single <prove-ticket-card> host.
  openCard(dom, $(dom, "prove-ticket"));
  $(dom, "prove-ref").querySelector("button.pt-mark")
    .dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }));
  eq($$(dom, "prove-ticket-card").length, 1, "both kinds open the SAME single card host");
}

/* ── 48. [v4] CSS carries the v4 surfaces (alert/retry/mark/ref/go/flash) and still uses only tokens ── */
{
  for (const cls of [".pt-alert", ".pt-retry", ".pt-mark", ".pt-wrap-ref", ".pt-go", "data-pt-flash", ".pt-tip-warn"]) {
    check(cssSrc.includes(cls), "proof-ticket.css styles " + cls + " (the v4 surfaces are not unstyled)");
  }
  // Scoped to the v4 additions. The file carries exactly one pre-existing literal — `color:#fff`
  // on the status pill, whose background is always a saturated status token — and widening this to
  // the whole file would either fail on that pre-existing line or license new ones.
  const v4 = cssSrc.slice(cssSrc.indexOf("v4: internal item references"));
  check(v4.length > 0, "the v4 CSS block is present");
  eq((v4.match(/#[0-9a-fA-F]{3,8}\b/g) || []).length, 0, "the v4 CSS block hardcodes no hex — every color resolves from a token");
  eq((cssSrc.match(/#[0-9a-fA-F]{3,8}\b/g) || []).length, 1, "the file's only literal color remains the pre-existing pill #fff");
}

console.log("proof-ticket.test: PASS — " + COUNT + " assertions (iter-1: key/href, tooltip+a11y, dated status, link-only, XSS-escape, scanner wrap/skip/idempotent, co-delivery non-interference, SVG-anchor skip, hyphen-boundary; iter-2: freshness bucketing+dot+a11y, choosePlacement below/flip/clamp, card dialog+aria-expanded+Escape/outside-click+return-focus, tabs+roving+activity last-5 comment/state, relation re-anchor, back-compat, XSS on desc/comment/author, zero-request grep; iter-2-hardening: href scheme allow-list, focus-trap ancestor-visibility, no-literal-close-script source, activity newest-first sort, bakedAt→unknown freshness; iter-3 SVG/mermaid: SVG-namespace <a>+<tspan> affordance+safeHref, <circle> dot bucket-class+token-fill+zero-geometry guard, click→shared card, foreignObject unregressed, SVG idempotent, existing-SVG-<a> skip, plain-text-URL guard HTML+SVG; iter-4 WARM PRINT light-DOM: no-shadowRoot, token-consumption+no-hex+no-Canvas, non-color fill-fraction channel (distinct per bucket, HTML+SVG), pill per-type class→token, id-uniqueness across 2 refs, graceful no-blob degradation, behavior-only de-injection contract (no PT_CSS/ensureStyles/<style>; styled+functional when page provides proof-ticket.css), PROOF_TICKET_VERSION; iter-5 v4 FETCHED tickets.json: one-request-to-its-own-sibling invariant (replaces the old no-fetch grep) + credentials:omit + never-the-tracker, fetch GATED (inline wins / no refs / no derivable url ⇒ zero requests, counted), sibling-URL resolution link>meta>convention + no guess off non-http + an EMPTY meta declares NONE (short-circuits the convention: publish-s3's no-bake injection), happy path upgrade-in-place + card dates the JSON's OWN bakedAt, re-baked shared JSON restates the date, LOUD failure x3 causes (404/CORS/bad-JSON → working link + unknown ring + 'data unavailable' dot label + data-pt-source=unavailable + html[data-prove-tickets=error] + page status host + card alert/retry + 'could not be loaded' empties) vs no banner on a clean load, CORS named in the reason; internal item refs: ordinal-first then id resolution, unresolvable left as prose ([0-9]/[99]), teaser from the item's own DOM, shared card in item mode (no tabs, Go-to-decision focused first) + scrollIntoView + focus move, ONE scanner/one skip-list/one card host for both kinds + idempotent, v4 CSS surfaces token-only)");
