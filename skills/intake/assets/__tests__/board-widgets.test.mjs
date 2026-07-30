/* Round-trip test for board-widgets.js — no external deps.
 * Builds a known DOM with a minimal shim (the kit uses only [attr]-presence selectors),
 * runs the kit, and asserts FinchBoard.payloadText() matches PAYLOAD_SCHEMA.md (v2).
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/__tests__/board-widgets.test.mjs
 */
import assert from "node:assert";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const kitSrc = fs.readFileSync(path.join(here, "..", "board-widgets.js"), "utf8");

/* ---- minimal DOM shim (attribute-presence selectors only) ---- */
function attrName(sel) { const m = /^\[([a-z0-9-]+)\]$/i.exec(sel.trim()); return m ? m[1] : null; }
function node(tag, attrs = {}, kids = []) {
  const n = {
    tag, attrs, children: kids, value: attrs._value, checked: !!attrs._checked,
    textContent: attrs._text || "", _listeners: {},
    getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; },
    setAttribute(k, v) { this.attrs[k] = v; },
    hasAttribute(k) { return k in this.attrs; },
    appendChild(c) { this.children.push(c); return c; },
    addEventListener() {}, classList: { add() {}, remove() {}, contains() { return false; } },
    _all() { let out = []; for (const c of this.children) { out.push(c); out = out.concat(c._all()); } return out; },
    querySelectorAll(sel) { const a = attrName(sel); return this._all().filter((e) => a && a in e.attrs); },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
    closest(sel) { const a = attrName(sel); let e = this; while (e) { if (a && a in e.attrs) return e; e = e._parent; } return null; }
  };
  for (const c of kids) c._parent = n;
  return n;
}
function linkParents(n) { for (const c of n.children) { c._parent = n; linkParents(c); } return n; }

function runKit(body) {
  const documentShim = {
    readyState: "complete", body,
    _all: () => body._all(),
    querySelectorAll(sel) { const a = attrName(sel); return [body, ...body._all()].filter((e) => a && a in e.attrs); },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
    createElement(tag) { return node(tag, {}); },
    addEventListener() {}, createRange() { return { selectNodeContents() {} }; }, execCommand() { return false; }
  };
  const sandbox = { document: documentShim, navigator: {}, Date, JSON, setTimeout: () => {}, console, window: {} };
  sandbox.window = sandbox; sandbox.self = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(kitSrc, sandbox);
  const text = sandbox.window.FinchBoard.payloadText();
  return { text, events: text.split("\n").filter(Boolean).map((l) => JSON.parse(l)) };
}

/* A council mark: static markup the render agent emits, read by the kit, never written by it. */
function mark(item, key, lens, icon, weight, why, thin) {
  return node("button", {
    "data-fb-panel": item, "data-fb-panel-key": key, "data-fb-panel-lens": lens,
    "data-fb-panel-icon": icon, "data-fb-panel-weight": String(weight),
    "data-fb-panel-why": why, "data-fb-panel-alt": "", "data-fb-panel-thin": String(thin)
  });
}

const BOARD = { "data-fb-board": "docx-wave2", "data-fb-wave": "Document Extraction wave 2" };

/* ================= Scenario 1 — a board WITH a council panel ================= */
const withPanel = linkParents(node("body", {
  ...BOARD, "data-fb-panel-roster": "4", "data-fb-panel-report": "builds/docx-wave2_COUNCIL_20260731T0914.md"
}, [
  node("input", { "data-fb-voter": "", _value: "yarik" }),
  node("div", { "data-fb-item": "cmt-abc", "data-fb-kind": "steer" }, [
    node("input", { "data-fb-key": "needs-research", _checked: true }),
    node("input", { "data-fb-key": "measure:extraction-count", _checked: true }),
    node("input", { "data-fb-key": "seems-like-a-ticket", _checked: false }),
    node("textarea", { "data-fb-note": "", _value: "also check the 20-page OCR cap" })
  ]),
  node("div", { "data-fb-item": "FIN-9001", "data-fb-kind": "adopt-cancel" }, [
    node("input", { "data-fb-key": "adopt", _checked: true }),
    node("select", { "data-fb-field": "milestone", _value: "Needs research" })
  ]),
  /* No human ever touched this item — the kit's touched-items rule drops it from the human
     side. The panel's read for it MUST still survive; that is why votes are events, not a
     block nested inside items[]. */
  node("div", { "data-fb-item": "cmt-untouched", "data-fb-kind": "steer" }, [
    node("input", { "data-fb-key": "needs-research", _checked: false })
  ]),
  mark("cmt-abc", "needs-research", "Skeptic", "🔍", 5, "The failing case is one query away.", false),
  mark("cmt-abc", "seems-like-a-ticket", "Operator", "⚙️", 3, "Ran on a summary only.", true),
  mark("cmt-untouched", "needs-research", "Skeptic", "🔍", 2, "Weak preference.", false),
  /* Incomplete: no key. Decoration, not a vote — must be skipped, never half-emitted. */
  node("button", { "data-fb-panel": "cmt-abc", "data-fb-panel-lens": "Architect" })
]));

const s1 = runKit(withPanel);
const council = s1.events.filter((e) => e.actor.kind === "council");
const human = s1.events.filter((e) => e.actor.kind === "human");

assert.ok(s1.events.length > 0, "emits events");
assert.ok(s1.events.every((e) => e.v === 2), "every event is v2");
assert.ok(s1.events.every((e) => e.actor && (e.actor.kind === "human" || e.actor.kind === "council")),
  "actor.kind is present on EVERY event — the human-contributor filter depends on it");
assert.strictEqual(new Set(s1.events.map((e) => e.ts)).size, 1,
  "one ts for the whole copy action — the ingest supersede rule keys off it");
assert.ok(s1.events.every((e) => e.board === "docx-wave2"), "board id on every line (lines stand alone)");

assert.strictEqual(council.length, 3, "3 complete council marks; the keyless one is skipped");
const cById = Object.fromEntries(council.map((e) => [e.id, e]));
assert.ok(cById["v:c:skeptic:cmt-abc:needs-research"], "deterministic council id (lens slug + item + key)");
assert.strictEqual(cById["v:c:skeptic:cmt-abc:needs-research"].weight, 5, "weight is a number, not a string");
assert.strictEqual(cById["v:c:skeptic:cmt-abc:needs-research"].actor.icon, "🔍", "persona icon travels with the vote");
assert.strictEqual(cById["v:c:skeptic:cmt-abc:needs-research"].actor.rosterVersion, 4, "rosterVersion carried");
assert.strictEqual(cById["v:c:operator:cmt-abc:seems-like-a-ticket"].thinGrounds, true,
  "thinGrounds is a boolean — a thin-grounds vote must stay visible as one");
assert.ok(council.some((e) => e.item === "cmt-untouched"),
  "THE POINT: a panel vote survives on an item no human touched");

assert.strictEqual(human.filter((e) => e.type === "vote").length, 3,
  "only checked human options vote — 2 on the steer item, 1 adopt; the unchecked one is dropped");
assert.strictEqual(human.filter((e) => e.type === "note").length, 1, "note event");
assert.strictEqual(human.filter((e) => e.type === "field").length, 1, "field event");
assert.ok(!human.some((e) => e.item === "cmt-untouched"), "untouched item emits nothing human-side");
assert.ok(human.every((e) => e.id.startsWith("v:h:yarik") || e.id.startsWith("n:h:yarik") || e.id.startsWith("f:h:yarik")),
  "human ids are namespaced by voter so a re-paste supersedes cleanly");

/* The tally a wave actually runs: humans only. A panel key must never reach it. */
const humanTally = human.filter((e) => e.type === "vote").map((e) => e.key).sort();
assert.deepStrictEqual(humanTally, ["adopt", "measure:extraction-count", "needs-research"],
  "human tally is human-only — no council key ('seems-like-a-ticket' was a panel pick, not a human one)");

/* Dedupe: N teammates paste the same static council events; ids collapse them exactly. */
const twoPastes = [...s1.events, ...s1.events];
const deduped = [...new Map(twoPastes.map((e) => [e.id, e])).values()];
assert.strictEqual(deduped.length, s1.events.length, "duplicate pastes collapse by event id");

/* ============ Scenario 2 — a board with NO council panel (the real compat risk) ============
 * F3: "an old board still works with the updated kit" cannot happen — the kit is inlined into
 * each board at render time, so a board keeps the kit it was built with forever. The risk that
 * actually exists is ingest meeting a payload with NO panel in it: an old board's, or a new
 * board's where the council failed to seat (council writes no report rather than faking one,
 * so an absent panel is a NORMAL outcome). */
const noPanel = linkParents(node("body", BOARD, [
  node("input", { "data-fb-voter": "", _value: "sam" }),
  node("div", { "data-fb-item": "cmt-xyz", "data-fb-kind": "steer" }, [
    node("input", { "data-fb-key": "needs-research", _checked: true })
  ])
]));

const s2 = runKit(noPanel);
assert.strictEqual(s2.events.length, 1, "no panel: only the human's own answers");
assert.ok(s2.events.every((e) => e.actor.kind === "human"), "no council events fabricated when no panel ran");
assert.doesNotThrow(() => s2.text.split("\n").filter(Boolean).forEach((l) => JSON.parse(l)),
  "a panel-less payload parses cleanly — an absent panel is not a parse failure");

/* ======= Scenario 3 — the updated kit against an OLDER board's markup =======
 * This case did not exist while the kit was inlined: a board carried the kit it was built
 * with, so old-markup-meets-new-kit was impossible. With one shared versioned kit it is the
 * central risk of the change — every board pointing at v2 runs whatever v2 currently is.
 * "Older" here means pre-panel markup: containers with no data-fb-kind (the kit defaults it),
 * no panel marks, no roster/report metadata. It must still produce valid human events. */
const oldBoard = linkParents(node("body", BOARD, [
  node("input", { "data-fb-voter": "", _value: "dana" }),
  node("div", { "data-fb-item": "cmt-old" }, [                    // no data-fb-kind at all
    node("input", { "data-fb-key": "needs-research", _checked: true }),
    node("textarea", { "data-fb-note": "", _value: "from a board built before panels existed" })
  ])
]));

const s3 = runKit(oldBoard);
assert.strictEqual(s3.events.length, 2, "older markup still yields its vote and its note");
assert.ok(s3.events.every((e) => e.v === 2), "the updated kit emits v2 from older markup");
assert.ok(s3.events.every((e) => e.actor.kind === "human"), "no council actor invented from a panel-less board");
assert.strictEqual(s3.events.find((e) => e.type === "vote").itemKind, "steer",
  "a container with no data-fb-kind defaults to steer rather than emitting undefined");
assert.strictEqual(s3.events.find((e) => e.type === "note").note, "from a board built before panels existed");
assert.ok(s3.events.every((e) => e.id && e.ts && e.board), "ids, ts and board identity all present");

/* The v1/v2 discrimination the ingest relies on (v1 carries no version field to test). */
const v1 = JSON.stringify({ board: "b", wave: "w", voter: "v", ts: "t", items: [{ id: "i", kind: "steer", selected: ["k"] }] });
function looksV1(text) { try { const o = JSON.parse(text); return !!o && Array.isArray(o.items); } catch { return false; } }
assert.ok(looksV1(v1), "v1 parses as one object with an items array");
assert.ok(!looksV1(s1.text), "v2 does not — multi-line JSONL fails a whole-text parse");
assert.ok(!looksV1(s2.text), "a single-event v2 stream is still not a v1 object");

console.log("board-widgets.test: PASS — 32 assertions (v2 event shape, actor.kind on every event, "
  + "council marks incl. an untouched item, incomplete-mark skip, human-only tally, id dedupe, "
  + "shared ts, no-panel board, older-markup compat, v1/v2 discrimination)");
