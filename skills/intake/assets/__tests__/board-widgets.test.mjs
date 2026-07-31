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
/* Every assignment to .innerHTML anywhere in the shimmed tree lands here. The kit is allowed to
 * use it for its OWN constant markup (the copy bar, the state bar); it must never use it for a
 * string that came off the wire. Recording every write is how the XSS scenario proves that,
 * rather than asserting on a rendered string that happens to look safe. */
const HTML_WRITES = [];
function node(tag, attrs = {}, kids = []) {
  const n = {
    tag, attrs, children: kids, value: attrs._value, checked: !!attrs._checked,
    textContent: attrs._text || "", _listeners: {},
    getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; },
    setAttribute(k, v) { this.attrs[k] = v; },
    hasAttribute(k) { return k in this.attrs; },
    appendChild(c) { this.children.push(c); c._parent = this; return c; },
    replaceChildren(...kids2) { this.children = kids2; for (const c of kids2) c._parent = this; },
    focus() { this._focused = true; },
    addEventListener() {}, classList: { add() {}, remove() {}, contains() { return false; } },
    _all() { let out = []; for (const c of this.children) { out.push(c); out = out.concat(c._all()); } return out; },
    querySelectorAll(sel) { const a = attrName(sel); return this._all().filter((e) => a && a in e.attrs); },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
    closest(sel) { const a = attrName(sel); let e = this; while (e) { if (a && a in e.attrs) return e; e = e._parent; } return null; }
  };
  Object.defineProperty(n, "innerHTML", {
    get() { return this._html || ""; },
    set(v) { this._html = v; HTML_WRITES.push({ tag: this.tag, html: String(v) }); }
  });
  for (const c of kids) c._parent = n;
  return n;
}

/* A structural fingerprint — tag, every attribute, text, recursively. Used to prove a poll cycle
 * left the council's static marks untouched, which no "looks the same" eyeball check can. */
function fingerprint(n) {
  return JSON.stringify({
    tag: n.tag, attrs: n.attrs, text: n.textContent, html: n._html || "",
    kids: (n.children || []).map(fingerprint)
  });
}
function linkParents(n) { for (const c of n.children) { c._parent = n; linkParents(c); } return n; }

/* A recording network. Default GET answer is 404 — "nothing folded yet", the honest starting
 * state for a board whose fold is agent-run — so a scenario that does not opt into a doc cannot
 * accidentally depend on one. Every call is recorded, which is what lets the no-config scenario
 * assert ZERO requests rather than assert that some request looked harmless. */
function makeNet(plan = {}) {
  const calls = [];
  const fetchShim = (url, init) => {
    const method = (init && init.method) || "GET";
    calls.push({ url, method, init: init || {}, headers: (init && init.headers) || {} });
    const h = method === "POST" ? plan.post : plan.get;
    const res = typeof h === "function" ? h(calls.length, url, init) : h;
    return Promise.resolve(res || { ok: false, status: 404, headers: { get: () => null } });
  };
  return {
    calls, fetchShim,
    gets: () => calls.filter((c) => c.method === "GET"),
    posts: () => calls.filter((c) => c.method === "POST")
  };
}
function ok200(doc, etag = '"e1"') {
  return { ok: true, status: 200, headers: { get: (k) => (k === "ETag" ? etag : null) }, json: () => Promise.resolve(doc) };
}
/* Minimal multipart stand-ins. The only thing the test needs off them is WHAT the kit put in the
 * body and IN WHAT ORDER — S3's presigned POST requires `file` last, so order is load-bearing. */
class FormDataShim { constructor() { this.entries = []; } append(k, v) { this.entries.push([k, v]); } }
class BlobShim { constructor(parts, o) { this.parts = parts; this.type = o && o.type; } }
function bodyEvent(post) {
  const fd = post.init.body;
  const file = fd.entries[fd.entries.length - 1];
  return { fd, fileKey: file[0], json: file[1].parts[0], event: JSON.parse(file[1].parts[0]) };
}
const tick = () => new Promise((r) => setTimeout(r, 0));   // host realm — lets the kit's promises settle

function runKit(body, opts = {}) {
  const documentShim = {
    readyState: "complete", body,
    _all: () => body._all(),
    querySelectorAll(sel) { const a = attrName(sel); return [body, ...body._all()].filter((e) => a && a in e.attrs); },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
    createElement(tag) { return node(tag, {}); },
    addEventListener() {}, createRange() { return { selectNodeContents() {} }; }, execCommand() { return false; }
  };
  const sandbox = { document: documentShim, navigator: {}, Date, JSON, setTimeout: () => {}, console, window: {} };
  if (opts.net) { sandbox.fetch = opts.net.fetchShim; sandbox.FormData = FormDataShim; sandbox.Blob = BlobShim; }
  sandbox.window = sandbox; sandbox.self = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(kitSrc, sandbox);
  const text = sandbox.window.FinchBoard.payloadText();
  return {
    text, events: text.split("\n").filter(Boolean).map((l) => JSON.parse(l)),
    board: sandbox.window.FinchBoard, doc: documentShim, body
  };
}

/* The publish-injected config block. `raw` lets a scenario supply the UNRESOLVED token, which is
 * what an unpublished (or non-multiplayer) board actually carries. */
function stateConfigNode(cfg, raw) {
  return node("script", { "data-fb-state-config": "", _text: raw !== undefined ? raw : JSON.stringify(cfg) });
}
function stateBarNodes() {
  return [node("button", { "data-fb-submit": "" }), node("span", { "data-fb-state-status": "" })];
}
const stateStatus = (r) => r.doc.querySelector("[data-fb-state-status]").textContent;

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

/* ══════════════════════════════════════════════════════════════════════════════════════════
   SHARED STATE (multiplayer) — T2…T8.

   Framing that matters for anyone changing these: the copy-back path above is the CONTRACT and
   everything below is additive. If a scenario below forces a change to an assertion above, the
   change is wrong — the multiplayer layer is opt-in per board and may not alter a board that
   didn't opt in.
   ══════════════════════════════════════════════════════════════════════════════════════════ */
const norm = (t) => t.replace(/"ts":"[^"]+"/g, '"ts":"T"');
const LIVE = {
  docId: "wave2-a1b2c3d4",
  stateUrl: "https://staging-finch-proofs.s3.us-east-2.amazonaws.com/state/wave2-a1b2c3d4.json",
  postUrl: "https://staging-finch-proofs.s3.us-east-2.amazonaws.com/",
  keyPrefix: "events/wave2-a1b2c3d4/",
  fields: { policy: "POLICY-B64", "x-amz-signature": "SIG-HEX", "x-amz-algorithm": "AWS4-HMAC-SHA256" },
  expiresAt: new Date(Date.now() + 3600e3).toISOString(),
  pollMs: 20000
};
const vote = (id, name, item, key, ts) => ({
  v: 2, board: "docx-wave2", wave: "Document Extraction wave 2", type: "vote",
  id, ts, actor: { kind: "human", name }, item, itemKind: "steer", key
});

/* ---- T2 — a board with NO state config behaves EXACTLY as today ---- */
function plainBoard(extra = []) {
  return linkParents(node("body", BOARD, [
    node("input", { "data-fb-voter": "", _value: "sam" }),
    node("div", { "data-fb-item": "cmt-t2", "data-fb-kind": "steer" }, [
      node("input", { "data-fb-key": "needs-research", _checked: true }),
      node("textarea", { "data-fb-note": "", _value: "a note" })
    ]),
    ...extra
  ]));
}
const t2base = runKit(plainBoard());                                   // no net shim at all
const t2netA = makeNet();
const t2none = runKit(plainBoard(), { net: t2netA });                  // net available, no config
const t2netB = makeNet();
/* The realistic "not configured" case is not an absent tag — it is a board carrying the tag with
   the token still unresolved, i.e. composed but never published, or opened straight off disk. */
const t2token = runKit(plainBoard([stateConfigNode(null, "__PROVE_STATE_CONFIG__")]), { net: t2netB });
await tick();

assert.strictEqual(t2netA.calls.length, 0, "no state config: the kit issues ZERO network requests");
assert.strictEqual(t2netB.calls.length, 0, "unresolved config token: still ZERO network requests");
assert.strictEqual(t2none.board.stateConfig(), null, "no config node ⇒ STATE stays null");
assert.strictEqual(t2token.board.stateConfig(), null, "an unresolved __PROVE_STATE_CONFIG__ token is NOT a config");
assert.strictEqual(norm(t2none.text), norm(t2base.text), "payload byte-identical with the transport code present");
assert.strictEqual(norm(t2token.text), norm(t2base.text), "an unpublished board's payload is byte-identical too");
assert.strictEqual(t2none.doc.querySelector("[data-fb-submit]"), null,
  "no config ⇒ no submit control is injected — the page is not even visually different");

/* ---- T3 — submit posts humanEvents() ONLY; no council actor in any POST body ---- */
const t3net = makeNet({ post: () => ({ ok: true, status: 204, headers: { get: () => null } }) });
const t3 = runKit(linkParents(node("body",
  { ...BOARD, "data-fb-panel-roster": "4", "data-fb-panel-report": "builds/r.md" }, [
    ...stateBarNodes(), stateConfigNode(LIVE),
    node("input", { "data-fb-voter": "", _value: "Yarik Fedin" }),
    node("div", { "data-fb-item": "cmt-abc", "data-fb-kind": "steer" }, [
      node("input", { "data-fb-key": "needs-research", _checked: true }),
      node("input", { "data-fb-key": "seems-like-a-ticket", _checked: false }),
      node("textarea", { "data-fb-note": "", _value: "also check the 20-page OCR cap" })
    ]),
    mark("cmt-abc", "needs-research", "Skeptic", "🔍", 5, "one query away.", false)
  ])), { net: t3net });
await tick();
const t3ok = await t3.board.submit();
await tick();

assert.strictEqual(t3ok, true, "a named voter with picks submits successfully");
assert.strictEqual(t3net.posts().length, 2, "one POST per event — a vote and a note (state-append takes ONE object per key)");
assert.ok(t3.events.some((e) => e.actor.kind === "council"),
  "the board really does carry a council mark — so the absence below is a choice, not an empty panel");
for (const p of t3net.posts()) {
  const b = bodyEvent(p);
  assert.strictEqual(p.url, LIVE.postUrl, "POSTs go to the presigned postUrl");
  assert.strictEqual(b.fileKey, "file", "`file` is the LAST form field — S3's presigned POST requires it");
  assert.strictEqual(b.event.actor.kind, "human", "every posted event is a human's");
  assert.ok(!/"kind"\s*:\s*"council"/.test(b.json), "NO council actor in a POST body — council marks are static markup");
  assert.ok(!/data-fb-panel|rosterVersion/.test(b.json), "no panel metadata leaks into the transport either");
  const keyField = b.fd.entries.find((e) => e[0] === "key");
  assert.ok(keyField && keyField[1].startsWith(LIVE.keyPrefix), "the object key stays under the signed prefix");
  for (const k of Object.keys(LIVE.fields)) {
    assert.ok(b.fd.entries.some((e) => e[0] === k), `signed policy field ${k} is present`);
  }
}

/* ---- T4 — read-side fold: duplicate id collapses, later ts supersedes ---- */
const t4doc = { docId: LIVE.docId, events: [
  vote("v:h:dana:cmt-abc:needs-research", "dana", "cmt-abc", "needs-research", "2026-07-31T10:00:00Z"),
  vote("v:h:dana:cmt-abc:needs-research", "dana", "cmt-abc", "needs-research", "2026-07-31T10:00:00Z"),  // blind re-append
  vote("v:h:mo:cmt-abc:needs-research", "Mo", "cmt-abc", "needs-research", "2026-07-31T09:00:00Z"),
  vote("v:h:mo:cmt-abc:seems-like-a-ticket", "Mo", "cmt-abc", "seems-like-a-ticket", "2026-07-31T11:00:00Z")
] };
const t4net = makeNet({ get: (n) => (n === 1 ? ok200(t4doc, '"etag-1"') : { ok: false, status: 304, headers: { get: () => null } }) });
const slotNR = node("span", { "data-fb-marks": "needs-research" });
const slotST = node("span", { "data-fb-marks": "seems-like-a-ticket" });
const t4 = runKit(linkParents(node("body", BOARD, [
  ...stateBarNodes(), stateConfigNode(LIVE),
  node("input", { "data-fb-voter": "", _value: "yarik" }),
  node("div", { "data-fb-item": "cmt-abc", "data-fb-kind": "steer" }, [
    node("label", {}, [node("input", { "data-fb-key": "needs-research", _checked: true }), slotNR]),
    node("label", {}, [node("input", { "data-fb-key": "seems-like-a-ticket", _checked: false }), slotST])
  ])
])), { net: t4net });
await tick();

const t4folded = t4.board.fold(t4doc.events);
assert.strictEqual(t4folded.length, 2,
  "4 logged events fold to 2: the duplicate id collapses, and Mo's earlier vote is superseded by their later one");
assert.ok(t4folded.some((e) => e.id === "v:h:dana:cmt-abc:needs-research"), "dana's single vote survives");
assert.ok(!t4folded.some((e) => e.id === "v:h:mo:cmt-abc:needs-research"),
  "THE POINT: Mo changed their mind — the earlier answer is retracted, not left standing alongside");
assert.strictEqual(slotNR.children.length, 1, "the kit owns exactly one host element in the slot");
assert.strictEqual(slotNR.children[0].children.length, 1, "one mark rendered for needs-research (dana), not two");
assert.strictEqual(slotNR.children[0].children[0].textContent, "DA", "initials, not a name dump");
assert.strictEqual(slotST.children[0].children[0].textContent, "MO", "Mo's surviving vote renders on the option they moved to");
assert.strictEqual(t4net.gets()[0].headers["If-None-Match"], undefined, "the first poll sends no If-None-Match (nothing to compare)");
assert.strictEqual(t4net.gets()[0].init.cache, "no-store", "polls bypass the HTTP cache; freshness comes from the ETag");
await t4.board.poll(); await tick();
assert.strictEqual(t4net.gets()[1].headers["If-None-Match"], '"etag-1"', "the second poll is conditional on the ETag it stored");
assert.strictEqual(slotNR.children[0].children.length, 1, "a 304 re-renders nothing — zero bytes, zero DOM churn");

/* ---- T5 — two blank-named voters must never merge ---- */
const t5net = makeNet({ post: () => ({ ok: true, status: 204, headers: { get: () => null } }) });
const t5 = runKit(linkParents(node("body", BOARD, [
  ...stateBarNodes(), stateConfigNode(LIVE),
  node("input", { "data-fb-voter": "", _value: "   " }),          // whitespace-only: slug() ⇒ ""
  node("div", { "data-fb-item": "cmt-abc", "data-fb-kind": "steer" }, [
    node("input", { "data-fb-key": "needs-research", _checked: true })
  ])
])), { net: t5net });
await tick();
const t5r = await t5.board.submit();
assert.strictEqual(t5r, false, "a blank voter name refuses to submit");
assert.strictEqual(t5net.posts().length, 0, "…and posts nothing, so no h:anon event can ever reach the doc");
assert.ok(/name/i.test(stateStatus(t5)), "…and says why, rather than failing silently");
assert.ok(t5.doc.querySelector("[data-fb-voter]")._focused, "…and puts the cursor where the fix is");
assert.ok(t5.text.length > 0 && t5.events.length === 1,
  "copy-back is UNCHANGED by the guard — a blank name still copies, exactly as before");
/* Why the guard is load-bearing rather than fussy — this is the damage it prevents: */
const collided = t5.board.fold([
  { id: "v:h:anon:cmt-abc:needs-research", ts: "2026-07-31T10:00:00Z", type: "vote", actor: { kind: "human", name: "" }, item: "cmt-abc", key: "needs-research" },
  { id: "v:h:anon:cmt-abc:seems-like-a-ticket", ts: "2026-07-31T11:00:00Z", type: "vote", actor: { kind: "human", name: "" }, item: "cmt-abc", key: "seems-like-a-ticket" }
]);
assert.strictEqual(collided.length, 1,
  "two blank names ARE one actor to the supersede rule — the first voter's answer is destroyed, which is exactly why submit refuses");

/* ---- T6 — every degraded path leaves copy-back working and states a reason ---- */
function degradedBoard(cfg, net) {
  return runKit(linkParents(node("body", BOARD, [
    ...stateBarNodes(), stateConfigNode(cfg),
    node("input", { "data-fb-voter": "", _value: "dana" }),
    node("div", { "data-fb-item": "cmt-abc", "data-fb-kind": "steer" }, [
      node("input", { "data-fb-key": "needs-research", _checked: true })
    ])
  ])), { net });
}
/* 6a. EXPIRED-ON-ARRIVAL — the modal state, not an edge case: the write window is the publishing
   session's own credential, so most visitors arrive after it lapsed. */
const t6aNet = makeNet();
const t6a = degradedBoard({ ...LIVE, expiresAt: "2020-01-01T00:00:00Z" }, t6aNet);
await tick();
assert.strictEqual(await t6a.board.submit(), false, "an expired presign refuses to submit");
assert.strictEqual(t6aNet.posts().length, 0, "…without firing a doomed POST");
assert.ok(t6a.doc.querySelector("[data-fb-submit]").disabled === true, "…the button is visibly disabled, not dead-looking");
assert.ok(/2020-01-01T00:00:00Z/.test(stateStatus(t6a)), "…the status names WHEN it closed");
assert.ok(/Copy answers/.test(stateStatus(t6a)), "…and points at the path that still works");
assert.ok(t6a.events.length === 1, "…and that path genuinely still works");
assert.ok(t6aNet.gets().length === 1, "an expired WRITE grant does not disable the READ — state/* is public");

/* 6b. The POST itself fails. */
const t6bNet = makeNet({ post: () => ({ ok: false, status: 503, headers: { get: () => null } }) });
const t6b = degradedBoard(LIVE, t6bNet);
await tick();
assert.strictEqual(await t6b.board.submit(), false, "a failed POST reports failure rather than a false success");
assert.ok(/did not post/.test(stateStatus(t6b)) && /503/.test(stateStatus(t6b)), "…names the count and the HTTP status");
assert.ok(/Copy answers/.test(stateStatus(t6b)), "…and routes the voter to copy-back");

/* 6c. Publish happened while signing was unavailable — a READ-ONLY config. */
const t6cNet = makeNet();
const t6c = degradedBoard({ docId: LIVE.docId, stateUrl: LIVE.stateUrl, pollMs: 20000,
  submitDisabledReason: "could not export AWS credentials for the presign" }, t6cNet);
await tick();
assert.strictEqual(await t6c.board.submit(), false, "no write grant ⇒ no submit");
assert.strictEqual(t6cNet.posts().length, 0, "…and nothing is posted anywhere");
assert.ok(/could not export AWS credentials/.test(stateStatus(t6c)),
  "…the publish-time reason is surfaced verbatim, so the fix is diagnosable from the page");
assert.strictEqual(t6cNet.gets().length, 1, "…while the read path still polls — signing failure degrades, it does not kill");

/* ---- T7 — every string off the wire is inert ---- */
const EVIL = '"><img src=x onerror=alert(1)>';
const t7net = makeNet();
const t7 = degradedBoard(LIVE, t7net);                       // no [data-fb-marks] ⇒ exercises the presence fallback
await tick();
const htmlWritesBefore = HTML_WRITES.length;
t7.board.applyState({ docId: LIVE.docId, events: [
  vote("v:h:evil:cmt-abc:needs-research", EVIL, "cmt-abc", "needs-research", "2026-07-31T10:00:00Z")
] });
const presence = t7.doc.querySelector("[data-fb-presence]");
assert.ok(presence, "a board with no per-key slots still surfaces the marks via the presence fallback");
const evilMark = presence.children[0].children[0].children[1];
assert.strictEqual(evilMark.textContent, '"O', "a hostile display name renders as two inert initial characters");
assert.ok(!/img|onerror/.test(evilMark.textContent), "no markup survives into the rendered text");
assert.strictEqual(evilMark.attrs.title, EVIL + " picked this",
  "the raw name lives in an ATTRIBUTE (set via setAttribute, never parsed as HTML)");
assert.strictEqual(HTML_WRITES.length, htmlWritesBefore, "rendering polled data assigns innerHTML ZERO times");
assert.ok(HTML_WRITES.every((w) => !/onerror|img src/.test(w.html)),
  "no innerHTML write anywhere in the kit's lifetime carries wire data");
assert.strictEqual(presence.children[0].children[0].children[0].textContent, "needs-research",
  "the option key label is text too — board-authored, but there is no second escaping rule to forget");

/* ---- T8 — council marks are byte-identical across a poll cycle ---- */
const t8doc = { docId: LIVE.docId, events: [
  vote("v:h:dana:cmt-abc:needs-research", "dana", "cmt-abc", "needs-research", "2026-07-31T10:00:00Z")
] };
const t8net = makeNet({ get: () => ok200(t8doc) });
/* The council mark and the human-mark slot deliberately share ONE parent — the weak version of
   this test puts them in different containers, where nothing could have gone wrong anyway. */
const t8slot = node("span", { "data-fb-marks": "needs-research" }, [
  mark("cmt-abc", "needs-research", "Skeptic", "🔍", 5, "The failing case is one query away.", false)
]);
const t8 = runKit(linkParents(node("body",
  { ...BOARD, "data-fb-panel-roster": "4", "data-fb-panel-report": "builds/r.md" }, [
    ...stateBarNodes(), stateConfigNode(LIVE),
    node("input", { "data-fb-voter": "", _value: "yarik" }),
    node("div", { "data-fb-item": "cmt-abc", "data-fb-kind": "steer" }, [
      node("label", {}, [node("input", { "data-fb-key": "needs-research", _checked: true }), t8slot])
    ])
  ])), { net: t8net });
const councilBefore = t8.doc.querySelectorAll("[data-fb-panel]").map(fingerprint);
const payloadBefore = norm(t8.board.payloadText());
await tick();                                     // the initial poll lands and renders
await t8.board.poll(); await tick();               // …and a second cycle on top of it
const councilAfter = t8.doc.querySelectorAll("[data-fb-panel]").map(fingerprint);
assert.strictEqual(t8slot.children.length, 2, "the poll DID render — one council mark plus the kit's own host");
assert.strictEqual(t8slot.children[1].children.length, 1, "…and the host holds the teammate's mark (not a vacuous pass)");
assert.deepStrictEqual(councilAfter, councilBefore,
  "council marks are byte-identical across two poll cycles — the kit clears only its own host, never a sibling");
assert.strictEqual(norm(t8.board.payloadText()), payloadBefore,
  "and the payload the board emits is unchanged by polling — the transport reads, it does not rewrite the board");

/* ---- No running tally before this voter has voted (¶INV_PANEL_VOTES_ARE_A_READ_NOT_A_VERDICT) ---- */
const t9net = makeNet({ get: () => ok200(t4doc) });
const t9slot = node("span", { "data-fb-marks": "needs-research" });
const t9 = runKit(linkParents(node("body", BOARD, [
  ...stateBarNodes(), stateConfigNode(LIVE),
  node("input", { "data-fb-voter": "", _value: "yarik" }),
  node("div", { "data-fb-item": "cmt-abc", "data-fb-kind": "steer" }, [
    node("label", {}, [node("input", { "data-fb-key": "needs-research", _checked: false }), t9slot])
  ])
])), { net: t9net });
await tick();
assert.strictEqual(t9slot.children[0].children.length, 0,
  "a voter who has picked nothing sees NO marks — a live tally anchors an independent read into a sequential one");
assert.ok(!/\b[0-9]+ (votes?|teammates?)\b/.test(stateStatus(t9)),
  "…and no count either: a bare count is the anchor, the marks are only how it shows");
t9.doc.querySelector("[data-fb-key]").checked = true;
t9.board.render();
assert.strictEqual(t9slot.children[0].children.length, 1, "…and it reveals the moment they make their own pick");

console.log("board-widgets.test: PASS — 32 assertions (v2 event shape, actor.kind on every event, "
  + "council marks incl. an untouched item, incomplete-mark skip, human-only tally, id dedupe, "
  + "shared ts, no-panel board, older-markup compat, v1/v2 discrimination) "
  + "+ 62 shared-state assertions (T2 no-config parity incl. an unresolved token · T3 humanEvents-only "
  + "POSTs, file-last, signed prefix · T4 read-side dedupe+supersede, conditional GET, 304 no-op · "
  + "T5 blank-name refusal + the collision it prevents · T6 expired / failed-POST / no-write-grant "
  + "all degrade to copy-back with a reason · T7 polled text inert, zero innerHTML writes · "
  + "T8 council marks byte-identical across two poll cycles · no-tally-before-you-vote)");
