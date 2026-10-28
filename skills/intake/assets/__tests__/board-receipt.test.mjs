/* The board's submit receipt — "stored at HH:MM" only when the store says so.
 *
 * The defect: a board submit could fail to reach the store and still look submitted. After the
 * POST, the page now lists its own events prefix (the publish-minted `listUrl`) and shows "Stored
 * at HH:MM" only for keys the listing returns (or ids already folded into the state doc). Anything
 * else is an error with Retry, and the answers are kept on the device — with a copy button — and
 * re-sent by the next Submit. Browser storage that throws must never break any of it.
 *
 * No browser, no store: the real board-widgets.js runs in a vm over a minimal DOM shim with a
 * recording fetch, the same technique as board-widgets.test.mjs.
 *
 * Run:  node ~/.claude/engine/skills/intake/assets/__tests__/board-receipt.test.mjs
 */
import assert from "node:assert";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const kitSrc = fs.readFileSync(path.join(here, "..", "board-widgets.js"), "utf8");

function attrName(sel) { const m = /^\[([a-z0-9-]+)\]$/i.exec(sel.trim()); return m ? m[1] : null; }
function node(tag, attrs = {}, kids = []) {
  const n = {
    tag, attrs, children: kids, value: attrs._value, checked: !!attrs._checked,
    textContent: attrs._text || "", disabled: false, _listeners: {},
    getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; },
    setAttribute(k, v) { this.attrs[k] = v; },
    removeAttribute(k) { delete this.attrs[k]; },
    hasAttribute(k) { return k in this.attrs; },
    appendChild(c) { this.children.push(c); c._parent = this; return c; },
    replaceChildren(...k2) { this.children = k2; for (const c of k2) c._parent = this; },
    focus() {}, addEventListener(t, f) { (this._listeners[t] = this._listeners[t] || []).push(f); },
    classList: { add() {}, remove() {}, contains() { return false; } },
    _all() { let out = []; for (const c of this.children) { out.push(c); out = out.concat(c._all()); } return out; },
    querySelectorAll(sel) { const a = attrName(sel); return this._all().filter((e) => a && a in e.attrs); },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
    closest(sel) { const a = attrName(sel); let e = this; while (e) { if (a && a in e.attrs) return e; e = e._parent; } return null; }
  };
  for (const c of kids) c._parent = n;
  return n;
}
function linkParents(n) { for (const c of n.children) { c._parent = n; linkParents(c); } return n; }

class FormDataShim { constructor() { this.entries = []; } append(k, v) { this.entries.push([k, v]); } }
class BlobShim { constructor(parts, o) { this.parts = parts; this.type = o && o.type; } }

const LIVE = {
  docId: "rcpt-board-1a2b3c4d", stateUrl: "https://b.s3.us-east-2.amazonaws.com/state/rcpt-board-1a2b3c4d.json",
  pollMs: 20000, postUrl: "https://b.s3.us-east-2.amazonaws.com/", keyPrefix: "events/rcpt-board-1a2b3c4d/",
  fields: { policy: "p", "x-amz-signature": "s" }, expiresAt: "2099-01-01T00:00:00Z",
  listUrl: "https://b.s3.us-east-2.amazonaws.com/?list-type=2&prefix=events%2Frcpt-board-1a2b3c4d%2F&X-Amz-Signature=x"
};
const OUTBOX = "fb:outbox:" + LIVE.docId, RECEIPT = "fb:receipt:" + LIVE.docId;

/* The store, simulated by what it answers. `postKeys` records every key a POST wrote; the list
 * answers with whichever of them `listHas` lets through — which is how a store that took the POST
 * but does not hold the object (the incident) is modelled. */
function makeStoreNet(o = {}) {
  const calls = [], postKeys = [];
  const fetchShim = (url, init) => {
    const method = (init && init.method) || "GET";
    calls.push({ url, method, init: init || {} });
    if (method === "POST") {
      if (o.offline) return Promise.reject(new TypeError("Failed to fetch"));
      const key = init.body.entries.find((e) => e[0] === "key")[1];
      if (o.postStatus && o.postStatus !== 204) return Promise.resolve({ ok: false, status: o.postStatus, headers: { get: () => null } });
      postKeys.push({ key, body: JSON.parse(init.body.entries[init.body.entries.length - 1][1].parts[0]) });
      return Promise.resolve({ ok: true, status: 204, headers: { get: () => null } });
    }
    if (url === LIVE.listUrl || (url && String(url).includes("list-type=2"))) {
      if (o.listOffline) return Promise.reject(new TypeError("Failed to fetch"));
      if (o.listStatus) {
        return Promise.resolve({ ok: false, status: o.listStatus, headers: { get: () => null },
          text: () => Promise.resolve("<Error><Code>AccessDenied</Code></Error>") });
      }
      const keys = postKeys.filter((p) => (o.listHas ? o.listHas(p) : true)).map((p) => p.key);
      const xml = '<?xml version="1.0"?><ListBucketResult>' + keys.map((k) => "<Contents><Key>" + k + "</Key></Contents>").join("") + "</ListBucketResult>";
      return Promise.resolve({ ok: true, status: 200, headers: { get: () => null }, text: () => Promise.resolve(xml) });
    }
    if (o.stateDoc) {
      const doc = typeof o.stateDoc === "function" ? o.stateDoc(postKeys) : o.stateDoc;
      return Promise.resolve({ ok: true, status: 200, headers: { get: () => '"e"' }, json: () => Promise.resolve(doc) });
    }
    return Promise.resolve({ ok: false, status: 404, headers: { get: () => null } });
  };
  return { calls, postKeys, fetchShim, posts: () => calls.filter((c) => c.method === "POST"),
    lists: () => calls.filter((c) => String(c.url).includes("list-type=2")) };
}
function makeStorage(seed = {}, mode = "ok") {
  const map = Object.create(null);
  for (const k of Object.keys(seed)) map[k] = String(seed[k]);
  const boom = () => { throw new Error("SecurityError: storage is disabled"); };
  return {
    getItem: mode === "throws" ? boom : (k) => (k in map ? map[k] : null),
    setItem: mode === "ok" ? (k, v) => { map[k] = String(v); } : boom,
    removeItem: mode === "ok" ? (k) => { delete map[k]; } : boom,
    map
  };
}
/* A submit that THROWS (storage refusing a write, say) is a failed check, not a crashed run. */
const sub = async (b) => { try { return await b.kit.submit(); } catch (e) { return "threw: " + e.message; } };
const tick = () => new Promise((r) => setTimeout(r, 0));

function board(picks, { cfg = LIVE, net, storage, storageGetterThrows, voter = "Dana" } = {}) {
  const items = picks.map(([item, key]) => node("div", { "data-fb-item": item, "data-fb-kind": "steer" }, [
    node("input", { "data-fb-key": key, _checked: true })
  ]));
  const body = linkParents(node("body", { "data-fb-board": "rcpt", "data-fb-wave": "w1" }, [
    node("button", { "data-fb-submit": "" }), node("span", { "data-fb-state-status": "" }),
    node("button", { "data-fb-retry": "", hidden: "" }), node("button", { "data-fb-copy-unsent": "", hidden: "" }),
    node("button", { "data-fb-copy": "" }), node("pre", { "data-fb-payload": "" }),
    node("script", { "data-fb-state-config": "", _text: JSON.stringify(cfg) }),
    node("input", { "data-fb-voter": "", _value: voter }),
    ...items
  ]));
  const documentShim = {
    readyState: "complete", body,
    querySelectorAll(sel) { const a = attrName(sel); return [body, ...body._all()].filter((e) => a && a in e.attrs); },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
    createElement(tag) { return node(tag, {}); },
    addEventListener() {}, createRange() { return { selectNodeContents() {} }; }, execCommand() { return false; }
  };
  const clip = { text: null };
  const sandbox = { document: documentShim, Date, JSON, setTimeout: () => {}, console,
    navigator: { clipboard: { writeText: (t) => { clip.text = t; return Promise.resolve(); } } },
    fetch: net.fetchShim, FormData: FormDataShim, Blob: BlobShim };
  sandbox.window = sandbox; sandbox.self = sandbox;
  if (storageGetterThrows) Object.defineProperty(sandbox, "localStorage", { get() { throw new Error("SecurityError"); } });
  else sandbox.localStorage = storage;
  vm.createContext(sandbox);
  vm.runInContext(kitSrc, sandbox);
  const q = (a) => documentShim.querySelector("[" + a + "]");
  return { kit: sandbox.window.ProveBoard, clip, status: () => q("data-fb-state-status").textContent,
    retryShown: () => !q("data-fb-retry").hasAttribute("hidden"), copyShown: () => !q("data-fb-copy-unsent").hasAttribute("hidden"),
    retryBtn: q("data-fb-retry"), body };
}
const kept = (st) => (st.map[OUTBOX] ? JSON.parse(st.map[OUTBOX]) : []);
/* Every check runs and reports, rather than stopping at the first: a planted defect should show
 * WHICH scenarios it breaks, not only that one did. */
let n = 0; const failures = [];
const check = (c, m) => { n++; try { assert.ok(c, m); console.log("  ok   " + m); } catch (e) { failures.push(m); console.log("  FAIL " + m); } };
process.on("unhandledRejection", (e) => { failures.push("unhandled: " + (e && e.message)); });

/* ---- B1 — the store has it: "Stored at HH:MM", a verified receipt, nothing kept ---- */
{
  const net = makeStoreNet(), st = makeStorage();
  const b = board([["q1", "yes"]], { net, storage: st }); await tick();
  check((await sub(b)) === true, "B1 a submit whose key the store lists succeeds");
  check(net.lists().length === 1, "B1 …and it was READ BACK — the POST's 2xx alone did not decide it");
  check(/^Stored at \d\d:\d\d ✓/.test(b.status()), "B1 the status says 'Stored at HH:MM' — got: " + b.status());
  check(JSON.parse(st.map[RECEIPT]).verified === true, "B1 the receipt records that a read-back confirmed it");
  check(!(OUTBOX in st.map), "B1 nothing is left in the outbox");
  check(!b.retryShown() && !b.copyShown(), "B1 no Retry and no copy-unsent on a confirmed submit");
  await b.kit.poll(); await tick();
  check(/^Stored at/.test(b.status()), "B1 a later poll does not paint over the receipt");
}

/* ---- B2 — THE INCIDENT: the POST is accepted, the store does not hold it ---- */
{
  const net = makeStoreNet({ listHas: () => false }), st = makeStorage();
  const b = board([["q1", "yes"], ["q2", "no"]], { net, storage: st }); await tick();
  check((await sub(b)) === false, "B2 a submit the store does not list is NOT a success");
  check(!/stored at/i.test(b.status()) && /Not stored: 2 of 2/.test(b.status()), "B2 the status says it is not stored — got: " + b.status());
  check(b.retryShown(), "B2 Retry is offered");
  check(b.copyShown(), "B2 'Copy unsent answers' is offered");
  check(kept(st).length === 2, "B2 both answers are kept on the device");
  check(!(RECEIPT in st.map), "B2 no receipt claims they were posted");
  await b.kit.poll(); await tick();
  check(/Not stored/.test(b.status()), "B2 the error is sticky across a poll");
}

/* ---- B3 — not listed, but already folded: the state doc carries the id ---- */
{
  const net = makeStoreNet({ listHas: () => false, stateDoc: (pk) => ({ docId: LIVE.docId, events: pk.map((p) => p.body) }) });
  const b = board([["q1", "yes"]], { net, storage: makeStorage() }); await tick();
  check((await sub(b)) === true, "B3 a key the fold already consumed still counts as stored (found by id in the state doc)");
  check(/^Stored at/.test(b.status()), "B3 …and says so");
}

/* ---- B4 — the read-back itself is refused ---- */
{
  const net = makeStoreNet({ listStatus: 403 }), st = makeStorage();
  const b = board([["q1", "yes"]], { net, storage: st }); await tick();
  check((await sub(b)) === false, "B4 an unreadable store is not a confirmation");
  check(/could not be read back/.test(b.status()) && /refused/.test(b.status()), "B4 it names why (AccessDenied → refused) — got: " + b.status());
  check(kept(st).length === 1 && b.retryShown(), "B4 the answer is kept and Retry is offered");
}

/* ---- B5 — offline: kept, copyable, survives a reload, re-sent by the next Submit ---- */
{
  const st = makeStorage();
  const off = makeStoreNet({ offline: true });
  const b = board([["q1", "yes"]], { net: off, storage: st }); await tick();
  check((await sub(b)) === false, "B5 an offline submit fails");
  check(/could not be reached/.test(b.status()) && /kept on this device/.test(b.status()), "B5 it says unreachable, and that the answer is kept — got: " + b.status());
  check(await b.kit.copyUnsent(), "B5 copy-unsent copies");
  const line = JSON.parse(b.clip.text);
  check(line.item === "q1" && line.key === "yes" && line.actor.name === "Dana", "B5 …the voter's own answer, as a pasteable payload line");
  /* the reload: a fresh page over the same storage, with NOTHING ticked */
  const on = makeStoreNet();
  const r = board([], { net: on, storage: st }); await tick();
  check(/An earlier Submit did not reach the store/.test(r.status()) && r.copyShown(), "B5 after a reload the kept answer is announced, copy offered");
  check((await sub(r)) === true, "B5 the next Submit re-sends it, with no pick on screen");
  check(on.postKeys.length === 1 && on.postKeys[0].body.id === line.id, "B5 …exactly the kept event");
  check(!(OUTBOX in st.map) && /^Stored at/.test(r.status()), "B5 …and once stored it leaves the outbox");
}

/* ---- B6 — a re-answer supersedes the kept pick instead of resurrecting it ---- */
{
  const st = makeStorage();
  const b = board([["q1", "yes"], ["q2", "maybe"]], { net: makeStoreNet({ offline: true }), storage: st }); await tick();
  await sub(b);
  const net = makeStoreNet();
  const r = board([["q1", "no"]], { net, storage: st }); await tick();
  check((await sub(r)) === true, "B6 the re-send succeeds");
  const sent = net.postKeys.map((p) => p.body.item + "=" + p.body.key).sort();
  check(JSON.stringify(sent) === JSON.stringify(["q1=no", "q2=maybe"]), "B6 q1's fresh answer replaces the kept one; q2's kept answer is re-sent — got " + sent);
}

/* ---- B7 — storage that throws breaks nothing ---- */
{
  for (const [label, opts] of [["getter throws", { storageGetterThrows: true }], ["every call throws", { storage: makeStorage({}, "throws") }]]) {
    const b = board([["q1", "yes"]], { net: makeStoreNet({ offline: true }), ...opts }); await tick();
    check((await sub(b)) === false, "B7 " + label + ": the submit still runs and fails honestly");
    check(/would not keep them/.test(b.status()), "B7 " + label + ": it says the browser would not keep them — got: " + b.status());
    check(b.copyShown() && (await b.kit.copyUnsent()) && /"q1"/.test(b.clip.text), "B7 " + label + ": copy still works, from memory");
    const ok = board([["q1", "yes"]], { net: makeStoreNet(), ...opts }); await tick();
    check((await sub(ok)) === true && /^Stored at/.test(ok.status()), "B7 " + label + ": a good submit is still confirmed");
  }
}

/* ---- B8 — an older board (no listUrl) never says "stored" ---- */
{
  const { listUrl, ...OLD } = LIVE;
  const net = makeStoreNet();
  const b = board([["q1", "yes"]], { cfg: OLD, net, storage: makeStorage() }); await tick();
  check((await sub(b)) === true, "B8 an older board still submits");
  check(!/stored at/i.test(b.status()) && /cannot confirm/.test(b.status()), "B8 …and says it cannot confirm, never 'stored' — got: " + b.status());
  check(net.lists().length === 0, "B8 …and invents no read-back");
}

/* ---- B9 — a closed write window keeps the answer rather than dropping it ---- */
{
  const st = makeStorage();
  const net = makeStoreNet();
  const b = board([["q1", "yes"]], { cfg: { ...LIVE, expiresAt: "2020-01-01T00:00:00Z" }, net, storage: st }); await tick();
  check((await sub(b)) === false && net.posts().length === 0, "B9 an expired board posts nothing");
  check(kept(st).length === 1 && b.copyShown() && /Not sent/.test(b.status()), "B9 …and keeps the answer with copy offered — got: " + b.status());
  check(b.retryBtn.disabled === true, "B9 Retry is disabled while the window is closed");
}

if (failures.length) { console.log("board-receipt.test: FAIL — " + failures.length + " of " + n + " checks failed"); process.exit(1); }
console.log("board-receipt.test: PASS — " + n + " assertions (B1 stored-at only on read-back · B2 accepted-but-absent is an error with Retry · "
  + "B3 already-folded counts · B4 refused read-back · B5 offline keep/copy/reload/re-send · B6 no resurrection · "
  + "B7 throwing storage · B8 older board never says stored · B9 closed window keeps the answer)");
