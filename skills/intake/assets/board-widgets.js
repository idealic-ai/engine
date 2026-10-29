/* Decision Board widget kit — framework-free, CSP-safe (inline-embed this whole file).
 *
 * Contract: the render agent writes CREATIVE, declarative HTML with data-fb-* attributes;
 * this kit supplies STABLE behavior + emits the EXACT event stream in PAYLOAD_SCHEMA.md (v2).
 * Presentation is free (¶INV_BOARD_HANDOFF_IS_FIXED_PRESENTATION_IS_FREE); the payload shape is not.
 *
 * Markup the kit reads:
 *   [data-fb-board="<slug>"] [data-fb-wave="<project> wave <n>"]  — board metadata (anywhere; first wins)
 *   [data-fb-voter]                                               — optional voter name input
 *   [data-fb-item="<id>"] [data-fb-kind="steer|consolidation|adopt-cancel"]  — a widget container
 *      within it: <input data-fb-key="<option-key>">   checked → a `vote` event
 *                 [data-fb-field="milestone|reason|..."] value → a `field` event
 *                 [data-fb-note] value → a `note` event
 *   [data-fb-panel="<item-id>"]  — ONE static council mark, rendered by the agent, read never written.
 *      Carries: data-fb-panel-key, -lens, -icon, -weight, -why, -alt, -thin.
 *      Position-independent by design: the item id is on the attribute, so the agent may place
 *      marks wherever the layout wants without the kit depending on nesting.
 *   [data-fb-disclose="context|comparison|sources"]  — an expandable block of GROUNDS on an option.
 *      Native <details>; the summary is the visible line, the body is what unfolds. Optional
 *      [data-fb-disclose-key="<option-key>"] binds it to one option row; the item comes from the
 *      enclosing [data-fb-item]. The kit stamps [data-fb-disclose-invalid="true"] on an unknown
 *      kind. Read-only toward the payload: a disclosure emits no event and alters none.
 *   [data-fb-panel-roster] [data-fb-panel-report]  — council run metadata (anywhere; first wins)
 *   [data-fb-copy]     — the copy button (auto-created if absent)
 *   [data-fb-payload]  — the visible payload box (auto-created if absent)
 *
 * Shared-state (multiplayer) markup — ENTIRELY OPTIONAL. A board with no [data-fb-state-config]
 * behaves exactly as it did before this existed: copy-back only, and no network request at all.
 *   [data-fb-state-config]  — a <script type="application/json"> whose text is the publish-injected
 *      config {docId, stateUrl, pollMs, stateKey?, stateVerified?, stateUnreadableReason?,
 *      postUrl?, listUrl?, keyPrefix?, fields?, expiresAt?,
 *      expirySeconds?, expiryRequested?, expiryClampedBy?, submitDisabledReason?}.
 *      listUrl is the READ-BACK grant (sign-post.py): a presigned list of this board's own events
 *      prefix, in the store this page POSTS to. With it, a Submit says "Stored at HH:MM" only for
 *      keys that store lists back (or events, matched on id AND ts, already in the state doc), and
 *      only when that store is the one stateUrl reads — a listing on another store says nothing
 *      about what the fold will find. Without it (an older publish) the page says the store
 *      accepted the POST and never says "stored".
 *   [data-fb-retry] [data-fb-copy-unsent]  — kit-owned, auto-created (hidden) if absent. Shown when
 *      a Submit did not demonstrably land: its answers are kept in localStorage under
 *      fb:outbox:<docId> (memory when storage refuses), copyable, and re-sent by the next Submit.
 *      stateVerified says the publish wrote the state document AND read it back 200 with no
 *      credential. It is what turns a later 403/404 from "nothing folded yet" into a reported
 *      failure: while nothing ever wrote the document those two were the same observation, and a
 *      refused board waited calmly forever looking unfolded. stateUnreadableReason carries the
 *      publish's own finding when the readback did NOT come back 200, so the page says so on its
 *      first paint rather than after a poll.
 *      expiryClampedBy says WHY the window is the length it is — "credential" when the signing
 *      credential dies before the requested window (a session token yields minutes, not days),
 *      "s3-max" when the request exceeded S3's 7-day ceiling, null when nothing shortened it.
 *      Unresolved/absent/unparseable ⇒ not configured ⇒ today's board.
 *   [data-fb-submit] [data-fb-state-status]  — submit control + status line (auto-created if absent)
 *   [data-fb-marks="<option-key>"]  — where OTHER people's marks are appended for that option
 *   [data-fb-presence]              — fallback marks container for boards with no per-key slots
 */
(function () {
  "use strict";
  var SCHEMA_VERSION = 2;

  function firstAttr(name) {
    var el = document.querySelector("[" + name + "]");
    return el ? el.getAttribute(name) : "";
  }
  function txt(el) { return el ? String(el.value != null ? el.value : el.textContent).trim() : ""; }
  function attr(el, name) { var v = el.getAttribute(name); return v == null ? "" : v; }
  function slug(s) { return String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""); }

  /* Council marks are STATIC — rendered into the board, identical in every reader's copy.
     Deterministic ids let N pastes of the same events collapse to one at ingest. */
  function councilEvents(meta, ts) {
    var out = [];
    var marks = document.querySelectorAll("[data-fb-panel]");
    for (var i = 0; i < marks.length; i++) {
      var m = marks[i];
      var item = attr(m, "data-fb-panel");
      var key = attr(m, "data-fb-panel-key");
      var lens = attr(m, "data-fb-panel-lens");
      if (!item || !key || !lens) continue; // an incomplete mark is decoration, not a vote
      var weight = parseInt(attr(m, "data-fb-panel-weight"), 10);
      out.push({
        v: SCHEMA_VERSION, board: meta.board, wave: meta.wave, type: "vote",
        id: "v:c:" + slug(lens) + ":" + item + ":" + key,
        ts: ts,
        actor: {
          kind: "council", lens: lens, icon: attr(m, "data-fb-panel-icon"),
          rosterVersion: parseInt(firstAttr("data-fb-panel-roster"), 10) || null,
          report: firstAttr("data-fb-panel-report")
        },
        item: item, itemKind: attr(m, "data-fb-panel-kind") || "steer", key: key,
        weight: isNaN(weight) ? null : weight,
        why: attr(m, "data-fb-panel-why"),
        alternative: attr(m, "data-fb-panel-alt"),
        thinGrounds: attr(m, "data-fb-panel-thin") === "true"
      });
    }
    return out;
  }

  function humanEvents(meta, ts) {
    var out = [];
    var voterEl = document.querySelector("[data-fb-voter]");
    var name = voterEl ? txt(voterEl) : "";
    var actor = { kind: "human", name: name };
    var aid = "h:" + (slug(name) || "anon");
    var containers = document.querySelectorAll("[data-fb-item]");
    for (var i = 0; i < containers.length; i++) {
      var c = containers[i];
      var item = c.getAttribute("data-fb-item");
      var itemKind = c.getAttribute("data-fb-kind") || "steer";
      var base = { v: SCHEMA_VERSION, board: meta.board, wave: meta.wave, ts: ts, actor: actor, item: item };

      c.querySelectorAll("[data-fb-key]").forEach(function (inp) {
        if (!inp.checked) return;
        var key = inp.getAttribute("data-fb-key");
        out.push(Object.assign({}, base, {
          type: "vote", id: "v:" + aid + ":" + item + ":" + key, itemKind: itemKind, key: key
        }));
      });
      c.querySelectorAll("[data-fb-field]").forEach(function (f) {
        var value = txt(f);
        if (!value) return;
        var field = f.getAttribute("data-fb-field");
        out.push(Object.assign({}, base, {
          type: "field", id: "f:" + aid + ":" + item + ":" + field, field: field, value: value
        }));
      });
      var noteEl = c.querySelector("[data-fb-note]");
      var note = noteEl ? txt(noteEl) : "";
      if (note) {
        out.push(Object.assign({}, base, { type: "note", id: "n:" + aid + ":" + item, note: note }));
      }
    }
    return out;
  }

  /* One ts for the whole copy action — the ingest supersede rule keys off it:
     for each (actor, item) only the greatest-ts events count, so a re-copy retracts
     an unchecked box instead of leaving the earlier paste's vote standing. */
  function buildEvents() {
    var meta = { board: firstAttr("data-fb-board"), wave: firstAttr("data-fb-wave") };
    var ts = new Date().toISOString();
    return councilEvents(meta, ts).concat(humanEvents(meta, ts));
  }

  function payloadText() {
    return buildEvents().map(function (e) { return JSON.stringify(e); }).join("\n");
  }

  function refreshPreview() {
    var box = document.querySelector("[data-fb-payload]");
    if (box) box.textContent = payloadText();
  }

  function fallbackCopy(text, box) {
    try {
      var sel = window.getSelection(); var range = document.createRange();
      if (box) { range.selectNodeContents(box); sel.removeAllRanges(); sel.addRange(range); }
      var ok = document.execCommand && document.execCommand("copy");
      if (sel) sel.removeAllRanges();
      return !!ok;
    } catch (e) { return false; }
  }

  function copy() {
    var text = payloadText();
    var box = document.querySelector("[data-fb-payload]");
    if (box) box.textContent = text;
    var msg = document.querySelector("[data-fb-copied]");
    function done(ok) {
      if (!msg) return;
      msg.textContent = ok ? "Copied ✓ — paste back into the wave" : "Copy the box below manually";
      msg.classList.add("fb-show");
      setTimeout(function () { msg.classList.remove("fb-show"); }, 2600);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(fallbackCopy(text, box)); });
    } else {
      done(fallbackCopy(text, box));
    }
  }

  function ensureCopyBar() {
    if (document.querySelector("[data-fb-copy]")) return; // agent supplied one
    var bar = document.createElement("div");
    bar.className = "fb-copybar";
    bar.innerHTML =
      '<input class="fb-voter" data-fb-voter placeholder="your name (for the vote tally)">' +
      '<button type="button" class="fb-copybtn" data-fb-copy>Copy answers</button>' +
      '<span class="fb-copied" data-fb-copied></span>';
    var pre = document.createElement("pre");
    pre.className = "fb-payload"; pre.setAttribute("data-fb-payload", "");
    document.body.appendChild(bar); document.body.appendChild(pre);
  }

  /* A council mark's reasoning must be reachable without hover — hover excludes touch and
     keyboard, and a mark whose reasoning cannot be reached is AI judgment presented as
     authority with the audit trail hidden. Click/focus toggles the same comment hover shows. */
  function wirePanelMarks() {
    document.addEventListener("click", function (e) {
      var mark = e.target.closest && e.target.closest("[data-fb-panel]");
      if (!mark) return;
      var open = mark.getAttribute("data-fb-panel-open") === "true";
      mark.setAttribute("data-fb-panel-open", open ? "false" : "true");
      mark.setAttribute("aria-expanded", open ? "false" : "true");
    });
  }

  /* ── Disclosures: the grounds an option is chosen ON ─────────────────────────────────
     The kinds are a CLOSED set, and that is the load-bearing part. A disclosure is author-written
     material a reader needs in order to decide — why this matters, what the alternatives cost,
     where it came from. With no `recommendation` kind, an agent's lean has no kind to arrive
     under, so the thing the reveal gate withholds is unexpressible here rather than discouraged.

     Native <details> by the kit's own alphabet, which records `⌄ Expand` as a declined affordance
     because the disc triangle already discloses. It also costs no listener: the browser handles
     keyboard focus and tap, and a <summary> toggle fires `toggle`, never `change`, so it cannot
     reach the preview/render handlers below.

     Deliberately absent from the payload and from positionsTaken(): expanding the grounds is
     reading, not answering. A record of which grounds someone opened would be a reading trail, and
     routing it into the position gate would unblind the tally for a reader who has decided
     nothing — the trade the gate exists to refuse. */
  var DISCLOSE_KINDS = { context: 1, comparison: 1, sources: 1 };

  function discloseKindOk(kind) {
    return Object.prototype.hasOwnProperty.call(DISCLOSE_KINDS, kind);
  }

  function readDisclosure(el) {
    var host = el.closest ? el.closest("[data-fb-item]") : null;
    var key = el.getAttribute("data-fb-disclose-key");
    var kind = attr(el, "data-fb-disclose");
    return {
      item: host ? attr(host, "data-fb-item") : null,   // null, never a neighbour's id
      key: key == null ? null : key,
      kind: kind,
      valid: discloseKindOk(kind),
      open: el.hasAttribute("open"),
      wasOpen: el.fbShippedOpen === true
    };
  }

  function disclosures() {
    var nodes = document.querySelectorAll("[data-fb-disclose]"), out = [];
    for (var i = 0; i < nodes.length; i++) out.push(readDisclosure(nodes[i]));
    return out;
  }

  /* Closed at first paint on every option, enforced rather than asked for: a board whose options
     arrive pre-expanded is the tall item the render spec measured, and the correction is recorded
     on the node (fbShippedOpen, the kit's own mark-without-an-attribute idiom) so the author's
     mistake stays visible instead of being quietly absorbed. */
  function wireDisclosures() {
    var nodes = document.querySelectorAll("[data-fb-disclose]");
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (!discloseKindOk(attr(el, "data-fb-disclose"))) el.setAttribute("data-fb-disclose-invalid", "true");
      if (el.hasAttribute("open")) { el.fbShippedOpen = true; el.removeAttribute("open"); }
    }
  }

  /* ══════════════════════════════════════════════════════════════════════════════════════
     SHARED STATE — voting in the page instead of copying a payload out of it.

     Everything below is inert unless the board carries a [data-fb-state-config]. That is not a
     nicety: copy-back is the path that still works when the presign has expired, when signing
     was unavailable at publish, or when a POST fails — and with a write window bounded by the
     publishing session's own credential (hours), EXPIRED-ON-ARRIVAL IS THE MODAL STATE, not an
     edge case. So the copy bar is never removed, hidden, or demoted when state is configured.
     ══════════════════════════════════════════════════════════════════════════════════════ */
  var STATE = null;          // parsed config, or null — null means "behave exactly as before"
  var lastEtag = null;       // conditional-GET token; a matching poll is 304 + zero bytes
  var lastEvents = null;     // last polled event log, kept so a local pick can re-render cheaply
  var docSeen = false;       // a state doc was READ for this board — turns a later 403 into an error
  /* A REFUSED read and an UNFOLDED board were the same thing on the page: both showed "an empty
     board means not folded yet". readBroken is the sticky reason that makes them different, and it
     outranks that sentence in the status line — the sentence is precisely the lie when the read is
     refused, because nothing ever prompts anyone to look. [data-prove-state-read] carries the same
     fact as an attribute so a reader that is not a human can tell them apart too. */
  var readBroken = null;
  var superseded = null;     // {docId, url} once a polled doc says this board was republished
  var receipt = null;        // this voter's own submit receipt, restored from localStorage on load
  /* The fold is AGENT-RUN and lands a few times a day. Polling at the reference demo's 1.5s
     would buy nothing and cost a request every 1.5s forever, so: a slow floor, and back off both
     on error AND on an unchanged doc. A landed change resets to the floor, which is when a
     reader is actually likely to see more arrive. */
  var POLL_MIN = 20000, POLL_MAX = 300000;
  var pollDelay = POLL_MIN;

  function readStateConfig() {
    var el = document.querySelector("[data-fb-state-config]");
    if (!el) return null;
    var raw = String(el.textContent == null ? "" : el.textContent).trim();
    if (!raw) return null;
    var cfg = null;
    try { cfg = JSON.parse(raw); } catch (e) { return null; }  // unresolved token → not configured
    if (!cfg || typeof cfg !== "object" || !cfg.stateUrl) return null;
    return cfg;
  }

  /* The kit toggles .fb-pending on this element and every style it needs hangs off
     .fb-statestatus — so the kit owns that class rather than trusting the board to supply it.
     A board that places its own status element (the render spec invites exactly that) otherwise
     gets an unstyled one AND suppresses ensureStateBar's properly-classed injection, so the
     status renders invisibly. Found the hard way: it made a working fix look like a failure. */
  function statusEl() {
    var el = document.querySelector("[data-fb-state-status]");
    if (el && el.classList) el.classList.add("fb-statestatus");
    return el;
  }

  function setStateStatus(msg) {
    var el = statusEl();
    if (el) el.textContent = msg;
  }

  /* One machine-readable word for the read half, on <html>: "ok" (a document was read),
     "broken" (it answered, and not with the document), "unverified" (the publish could not
     confirm the document reads anonymously), "waiting" (nothing read yet, nothing refused).
     In the `prove-` TRANSPORT namespace, not `data-fb-*`: the kit WRITES this, a render agent
     never authors it, and data-fb-* is the authoring vocabulary the render spec has to name. */
  function markReadState(word) {
    var root = document.documentElement;
    if (root && root.setAttribute) root.setAttribute("data-prove-state-read", word);
  }

  function voterName() {
    var el = document.querySelector("[data-fb-voter]");
    return el ? txt(el) : "";
  }

  /* ── The voter's own receipt ─────────────────────────────────────────────────────────
     A submit lands in events/<docId>/ and reaches the board only when an agent runs the fold.
     NOTHING schedules that fold — polling detects it, it never causes it — so the wait is
     unbounded by design. Across a reload the in-page "Submitted N ✓" is gone and the board is
     still empty, which is how a successful submit came to look like a failure.

     So it is written down, keyed by docId, and holds ONLY this voter's own event ids and when
     they were sent: nothing about anyone else, on nobody else's device. `pending` is the CLAIM
     — "sent, not folded in yet" — and it is the part that can become a lie, so it is retired the
     moment every stored id appears in a fetched doc. The ids themselves are KEPT: they are how
     this device still recognises its own position on the next reload, and dropping them would
     blank the tally for someone who demonstrably voted. */
  function storageArea() {
    try { return window.localStorage || null; } catch (e) { return null; }   // private mode / file:// throw
  }
  function receiptKey() { return STATE && STATE.docId ? "fb:receipt:" + STATE.docId : null; }

  function readReceipt() {
    var area = storageArea(), key = receiptKey(), raw = null, r = null;
    if (!area || !key) return null;
    try { raw = area.getItem(key); } catch (e) { return null; }
    if (!raw) return null;
    try { r = JSON.parse(raw); } catch (e) { return null; }   // unreadable ⇒ no receipt, gate stays shut
    if (!r || typeof r !== "object" || !Array.isArray(r.ids) || !r.ids.length) return null;
    var out = { ids: r.ids.slice(), ts: typeof r.ts === "string" ? r.ts : "", pending: r.pending !== false };
    if (r.verified === true) out.verified = true;
    return out;
  }
  function writeReceipt(r) {
    var area = storageArea(), key = receiptKey();
    if (!area || !key) return;
    try { area.setItem(key, JSON.stringify(r)); } catch (e) { /* full or blocked: the page still works */ }
  }
  function recordReceipt(ids, verified) {
    if (!ids || !ids.length) return;
    receipt = { ids: ids.slice(), ts: new Date().toISOString(), pending: true };
    if (verified) receipt.verified = true;    // only ever set by a read-back that found every key
    writeReceipt(receipt);
  }
  function reconcileReceipt(doc) {
    if (!receipt || !receipt.pending) return;
    var seen = Object.create(null), evs = (doc && doc.events) || [], i;
    for (i = 0; i < evs.length; i++) if (evs[i] && evs[i].id) seen[evs[i].id] = true;
    for (i = 0; i < receipt.ids.length; i++) {
      if (!Object.prototype.hasOwnProperty.call(seen, receipt.ids[i])) return;   // still waiting on one
    }
    receipt.pending = false;
    writeReceipt(receipt);
  }
  /* States a fact and names the reason. No countdown: there is no schedule to count down to, and
     inventing one would be a second lie on top of the one this replaces. */
  function receiptNote() {
    if (!receipt || !receipt.pending) return "";
    var n = receipt.ids.length, one = n === 1;
    /* "stored" is said only for a receipt a read-back confirmed. An unverified one keeps the older,
       weaker word: the store accepted the POST, which is not the same claim. */
    if (receipt.verified) {
      return "Your " + n + (one ? " answer was" : " answers were") + " stored"
        + (receipt.ts ? " at " + hhmm(new Date(receipt.ts)) : "") + " ✓ and "
        + (one ? "is" : "are") + " not on the shared board yet — " + (one ? "it appears" : "they appear")
        + " once an agent runs the fold. Nothing schedules it, so there is no countdown; if this is still here much later, ask the wave to run it.";
    }
    return "Your " + n + (one ? " answer" : " answers") + " posted ✓"
      + (receipt.ts ? " at " + receipt.ts : "")
      + (one ? " and is" : " and are") + " not on the shared board yet — "
      + (one ? "it appears" : "they appear") + " once an agent runs the fold. Nothing "
      + "schedules it, so there is no countdown; if this is still here much later, ask the wave to run it.";
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n; }
  function hhmm(d) { return isNaN(d.getTime()) ? "" : pad2(d.getHours()) + ":" + pad2(d.getMinutes()); }

  /* ── Unsent answers: kept on this device until the store has them ──────────────────────
     A submit that cannot reach the store (offline, the write window closed, the page opened
     somewhere other than where it was published) used to leave nothing behind but a sentence,
     and a reload lost even that. So the answers that did not demonstrably land are kept — in
     memory always, in localStorage when the browser allows it — shown with a copy button, and
     re-sent by the next Submit. Only this voter's own events, keyed by docId, on their device.
     They leave the outbox only when a read-back finds them in the store. */
  var unsent = [];           // events not yet confirmed stored, in memory even when storage refuses
  var unsentKept = true;     // false when the browser refused to keep them (private mode, quota)
  var outcome = null;        // {ok, text}: the last submit's verdict — sticky, so a poll cannot paint over it
  function outboxKey() { return STATE && STATE.docId ? "fb:outbox:" + STATE.docId : null; }
  function readOutbox() {
    var area = storageArea(), key = outboxKey(), raw = null, v = null;
    if (!area || !key) return [];
    try { raw = area.getItem(key); } catch (e) { return []; }
    if (!raw) return [];
    try { v = JSON.parse(raw); } catch (e) { return []; }
    if (!Array.isArray(v)) return [];
    return v.filter(function (ev) { return ev && typeof ev === "object" && typeof ev.id === "string"; });
  }
  function writeOutbox(evs) {
    unsent = evs.slice();
    var area = storageArea(), key = outboxKey();
    if (!area || !key) { unsentKept = !evs.length; return; }
    try {
      if (evs.length) area.setItem(key, JSON.stringify(evs)); else area.removeItem(key);
      unsentKept = true;
    } catch (e) { unsentKept = !evs.length; }
  }
  /* Merge this Submit's fresh answers over what is still unsent. An unsent event on an item the
     voter has just answered again is dropped rather than re-sent: the fresh one supersedes it
     anyway (greatest ts per actor and item), and re-posting it would only resurrect a retracted
     pick in the inbox. */
  function withUnsent(fresh) {
    var taken = Object.create(null), out = [], i, ev;
    for (i = 0; i < fresh.length; i++) {
      taken["id:" + fresh[i].id] = true;
      taken["ai:" + actorKey(fresh[i].actor) + "|" + fresh[i].item] = true;
    }
    for (i = 0; i < unsent.length; i++) {
      ev = unsent[i];
      if (taken["id:" + ev.id] || taken["ai:" + actorKey(ev.actor) + "|" + ev.item]) continue;
      out.push(ev);
    }
    return out.concat(fresh);
  }
  function unsentText() { return unsent.map(function (e) { return JSON.stringify(e); }).join("\n"); }
  function keptClause() {
    var n = unsent.length;
    if (!n) return "";
    return unsentKept
      ? " " + (n === 1 ? "That answer is" : "Those " + n + " answers are") + " kept on this device for Retry and “Copy unsent answers”."
      : " This browser would not keep them, so use “Copy unsent answers” now, before you leave the page.";
  }
  function copyUnsent() {
    var text = unsentText();
    if (!text) return Promise.resolve(false);
    var box = document.querySelector("[data-fb-payload]");
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).then(function () { return true; },
        function () { if (box) box.textContent = text; return fallbackCopy(text, box); });
    }
    if (box) box.textContent = text;
    return Promise.resolve(fallbackCopy(text, box));
  }

  /* Expiry is a first-class rendered state, not a warning banner. */
  function expiryMs() {
    if (!STATE || !STATE.expiresAt) return null;
    var t = Date.parse(STATE.expiresAt);
    return isNaN(t) ? null : t;
  }

  function submitGate() {
    if (!STATE) return { ok: false, reason: "this board has no shared-state config" };
    /* Answering a superseded board writes into a document the live board never polls. Saying where
       to answer instead is the whole point of the pointer; leaving the button live would collect
       answers nothing reads. */
    if (superseded) {
      return { ok: false, reason: "this board was republished as " + superseded.docId
        + " — answer on " + superseded.url + " instead" };
    }
    if (writeClosed) return { ok: false, reason: writeClosed };
    if (!STATE.postUrl || !STATE.fields || !STATE.keyPrefix) {
      return { ok: false, reason: STATE.submitDisabledReason || "this board was published without a write grant" };
    }
    var exp = expiryMs();
    if (exp != null && Date.now() >= exp) {
      return { ok: false, reason: "the write window closed at " + STATE.expiresAt };
    }
    return { ok: true, reason: "" };
  }

  var COPY_BACK = " — use “Copy answers” below and paste into the wave; that path always works.";

  function withNote(note, msg) { return note ? note + " " + msg : msg; }

  function refreshLiveness() {
    if (!STATE) return;
    /* The voter's own outcome leads. A closed write window matters, but not more than "the
       answers you already sent are safe" — that is the sentence whose absence filed this bug. */
    var note = receiptNote();
    var el = statusEl();
    if (el && el.classList) {
      if (note) el.classList.add("fb-pending"); else el.classList.remove("fb-pending");
    }
    var gate = submitGate();
    var btn = document.querySelector("[data-fb-submit]");
    if (btn) {
      btn.disabled = !gate.ok;
      if (btn.setAttribute) btn.setAttribute("aria-disabled", gate.ok ? "false" : "true");
    }
    showUnsentControls(gate);
    /* The voter's own last Submit outranks everything else on the line: a failed one is the fact
       they must act on, and a confirmed one is the receipt they came for. */
    if (outcome && !outcome.ok) {
      setStateStatus(outcome.text + keptClause() + (gate.ok || outcome.text.indexOf(gate.reason) >= 0 ? "" : " " + gate.reason + ".") + COPY_BACK);
      return;
    }
    if (outcome && outcome.ok && receipt && receipt.pending) { setStateStatus(outcome.text); return; }
    /* The read failure leads when there is one. A board whose state cannot be read is not a board
       waiting for a fold, and the submit reason underneath it is the lesser fact. */
    if (readBroken) {
      setStateStatus(withNote(note, readBroken + (gate.ok ? "" : " " + gate.reason) + COPY_BACK));
      return;
    }
    if (!gate.ok) { setStateStatus(withNote(note, gate.reason + COPY_BACK)); return; }
    var exp = expiryMs();
    var left = exp == null ? null : exp - Date.now();
    if (left != null && left < 1800000) {
      setStateStatus(withNote(note, "Heads up: this board stops accepting answers at " + STATE.expiresAt + COPY_BACK));
      return;
    }
    if (note) { setStateStatus(note + COPY_BACK); return; }
    setStateStatus("Answers post to the shared board. Other people's marks appear after an agent "
      + "runs the fold — a few times a day — so an empty board means \"not folded yet\", not \"broken\".");
  }

  /* ── Submit ──────────────────────────────────────────────────────────────────────────
     Posts humanEvents() ONLY. buildEvents() prepends councilEvents(), which are static markup
     already present in every reader's copy of the board — posting them would republish the whole
     panel block once per voter into a world-readable doc for exactly zero gain.
     One event per object, because state-append.sh appends exactly one JSON object per key. */
  function postOne(ev) {
    var fd = new FormData();
    var f = STATE.fields;
    Object.keys(f).forEach(function (k) { fd.append(k, f[k]); });
    var key = STATE.keyPrefix + Date.now() + "-" + Math.random().toString(16).slice(2, 10) + ".json";
    fd.append("key", key);
    fd.append("Content-Type", "application/json");
    fd.append("file", new Blob([JSON.stringify(ev)], { type: "application/json" }));  // file LAST
    /* A rejected fetch never reached the store at all — offline, a dead network, or a page opened
       somewhere other than where it was published (file://, another origin). One name for it. */
    return fetch(STATE.postUrl, { method: "POST", body: fd }).then(null, function () {
      throw new Error("Unreachable");
    }).then(function (r) {
      if (r.status === 204 || r.ok) return key;
      /* S3 names the cause in the body and the status alone does not: a 400 carrying
         ExpiredToken means "the write window closed", which the voter can act on, whereas
         "HTTP 400" is noise. Observed live — a board whose expiresAt claimed seven days
         posting into a credential that had already died with its session.
         The status is always the fallback: a body we cannot read must never cost the voter
         the one fact we do have. */
      var fallback = "HTTP " + r.status;
      if (typeof r.text !== "function") throw new Error(fallback);
      return r.text().then(function (body) {
        var m = /<Code>([^<]+)<\/Code>/.exec(body || "");
        throw new Error(m ? m[1] : fallback);
      }, function () { throw new Error(fallback); });
    });
  }

  /* The write grant can die before the clock the board was told about — expiresAt is signed
     for the nominal maximum, but a session-scoped credential expires with the session. So an
     expiry can arrive as a rejection rather than as a deadline, and it must read the same way. */
  var POST_ERRORS = {
    ExpiredToken: "the write window closed early (the board's own expiry date was optimistic)",
    TokenRefreshRequired: "the write window closed early (the board's own expiry date was optimistic)",
    AccessDenied: "this board's write grant was refused",
    EntityTooLarge: "that answer was too large for this board",
    RequestTimeout: "the connection timed out",
    Unreachable: "the store could not be reached (offline, or this page was opened somewhere other than where it was published)"
  };
  function explainPostError(code) {
    return POST_ERRORS[code] || (/^HTTP /.test(code) ? code : code);
  }

  /* A rejection from S3 outranks the board's own expiry claim: expiresAt is a prediction made at
     publish, the rejection is the service answering now. Once the grant is refused the board says
     so ONCE and routes to copy-back, rather than leaving a live-looking button that fails per click.
     Only codes that mean "this grant will not work again" latch — a too-large answer or a timed-out
     connection is about THAT attempt, and closing voting for either would shut the board for the
     wrong reason. Unknown codes do not latch: an unrecognised failure is not evidence of a dead grant. */
  var LATCH_CODES = { ExpiredToken: 1, TokenRefreshRequired: 1, AccessDenied: 1 };
  var writeClosed = null;

  function latchIfAuthoritative(code) {
    if (writeClosed || !LATCH_CODES[code]) return false;
    writeClosed = explainPostError(code);
    return true;
  }

  /* ── Read-back: "stored" is something the store says, not something the POST implied ───────
     A 2xx from the presigned POST is the store taking the bytes. The incident this exists for was
     a board whose answer read as submitted while the events inbox the fold listed was empty. So
     after posting, the page LISTS its own events prefix with the publish-minted listUrl and checks
     every key it wrote is there. A key that is not listed may already have been folded — the fold
     deletes what it folds — so the state document is checked for its event id before calling it
     missing. Resolves {missing: [events], error: string|null}. */
  function xmlText(s) {
    return String(s).replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'").replace(/&amp;/g, "&");
  }
  /* Which store a URL addresses: its origin plus bucket. Path-style (a local MinIO:
     http://host:port/<bucket>/…) takes the bucket from the first path segment; AWS virtual-host
     (https://<bucket>.s3.<region>.amazonaws.com/…) carries it in the host. Regex, not URL(): the
     kit runs where URL may not exist. */
  function storeOf(u) {
    var m = /^(https?:\/\/([^\/?#]+))(\/[^?#]*)?/i.exec(String(u || ""));
    if (!m) return "";
    var origin = m[1].toLowerCase(), host = m[2].toLowerCase();
    if (/^[^.]+\.s3[.-]/.test(host)) return origin;
    var seg = /^\/([^\/]+)/.exec(m[3] || "");
    return origin + "/" + (seg ? seg[1] : "");
  }

  function readBack(sent) {
    return fetch(STATE.listUrl, { cache: "no-store" }).then(null, function () {
      throw new Error("Unreachable");
    }).then(function (r) {
      if (!r.ok) {
        var fallback = "HTTP " + r.status;
        if (typeof r.text !== "function") throw new Error(fallback);
        return r.text().then(function (body) {
          var m = /<Code>([^<]+)<\/Code>/.exec(body || "");
          throw new Error(m ? m[1] : fallback);
        }, function () { throw new Error(fallback); });
      }
      return r.text();
    }).then(function (body) {
      var listed = Object.create(null), re = /<Key>([^<]*)<\/Key>/g, m;
      while ((m = re.exec(body || ""))) listed[xmlText(m[1])] = true;
      var missing = sent.filter(function (x) { return !listed[x.key]; });
      if (!missing.length) return { missing: [], error: null };
      /* ListObjectsV2 answers at most 1000 keys. A key not on a TRUNCATED page may be on the next,
         so its absence there is "not confirmed", never "not stored". */
      var truncated = /<IsTruncated>\s*true\s*<\/IsTruncated>/i.test(body || "");
      return fetch(STATE.stateUrl, { cache: "no-store" }).then(function (r) {
        return r && r.ok && typeof r.json === "function" ? r.json() : null;
      }).then(function (doc) {
        /* Folded already only if the doc holds THIS event: same id AND same ts. Ids are
           deterministic per voter and item, so an edited answer shares its id with the earlier
           one already in the doc — matching on id alone read the old answer as the new one stored. */
        var seen = Object.create(null), evs = (doc && doc.events) || [], i;
        for (i = 0; i < evs.length; i++) if (evs[i] && evs[i].id) seen[evs[i].id + "\u0000" + evs[i].ts] = true;
        var still = missing.filter(function (x) { return !seen[x.ev.id + "\u0000" + x.ev.ts]; });
        return { missing: still, error: still.length && truncated
          ? "the inbox listing was cut off at its first page, so the missing answers may be on a later one" : null };
      }, function () {
        return { missing: missing, error: truncated
          ? "the inbox listing was cut off at its first page, so the missing answers may be on a later one" : null };
      });
    }).then(null, function (e) {
      return { missing: sent, error: explainPostError(e && e.message ? e.message : String(e)) };
    });
  }

  function submit() {
    outcome = null;
    var gate = submitGate();
    if (!gate.ok) {
      /* The write is closed, but the answer on screen is still the voter's. Keep it (with a name,
         so it is attributable), so that a reload does not lose it and a later Submit can send it. */
      var gname = voterName();
      if (slug(gname)) {
        var gmeta = { board: firstAttr("data-fb-board"), wave: firstAttr("data-fb-wave") };
        var gfresh = humanEvents(gmeta, new Date().toISOString());
        if (gfresh.length) writeOutbox(withUnsent(gfresh));
      }
      if (unsent.length) {
        outcome = { ok: false, text: "Not sent: " + gate.reason + "." };
        refreshLiveness();
      } else {
        setStateStatus(gate.reason + COPY_BACK);
      }
      return Promise.resolve(false);
    }

    /* A blank name is not a minor validation miss. humanEvents() keys ids as h:<slug>||anon, so
       two unnamed voters become ONE actor, and the greatest-ts supersede rule then deletes the
       earlier one's answers outright — silent, total data loss with no error anywhere. */
    var name = voterName();
    if (!slug(name)) {
      setStateStatus("Add your name before submitting — unnamed answers would land as one shared "
        + "actor and overwrite each other. (Copy answers works without a name.)");
      var vin = document.querySelector("[data-fb-voter]");
      if (vin && vin.focus) vin.focus();
      return Promise.resolve(false);
    }

    var meta = { board: firstAttr("data-fb-board"), wave: firstAttr("data-fb-wave") };
    var fresh = humanEvents(meta, new Date().toISOString());
    /* The next Submit re-sends whatever an earlier one could not get into the store. */
    var events = withUnsent(fresh);
    if (!events.length) { setStateStatus("Nothing to submit yet — make a pick first."); return Promise.resolve(false); }

    setStateStatus("Submitting " + events.length + "…");
    var failed = 0, firstErr = "", sent = [];
    return Promise.all(events.map(function (ev) {
      return postOne(ev).then(function (key) { sent.push({ ev: ev, key: key }); },
        function (e) { failed++; if (!firstErr) firstErr = e && e.message ? e.message : String(e); });
    })).then(function () {
      if (failed) {
        /* Everything from this attempt stays unsent — including the ones that posted, because
           nothing has confirmed them yet; a duplicate in the inbox is collapsed by id at read time,
           a lost answer is not recoverable. Latch first, then render: refreshLiveness() disables
           the control off the new gate, and the specific "N of M" line is the verdict. */
        writeOutbox(events);
        latchIfAuthoritative(firstErr);
        outcome = { ok: false, text: failed + " of " + events.length + " answers did not post — "
          + explainPostError(firstErr) + "." };
        refreshLiveness();
        return false;
      }
      var ids = events.map(function (ev) { return ev.id; });
      if (!STATE.listUrl) {
        /* A board published before the read-back grant existed. The store took the POST and that
           is all this page can know, so it says exactly that — and never the word "stored". */
        writeOutbox([]);
        recordReceipt(ids);
        setStateStatus("Sent " + events.length + " — the store accepted them, but this board was "
          + "published without a read-back grant, so it cannot confirm they were stored. They show "
          + "up here once the fold runs (agent-run, a few times a day).");
        renderState();
        pollDelay = POLL_MIN;
        return true;
      }
      /* The read-back lists the store this page POSTED to. The fold reads the store the board's
         shared state lives on. If those are two stores, a listing proves nothing about what the
         fold will find — which is the incident's own shape — so "Stored" is refused outright. */
      if (storeOf(STATE.listUrl) !== storeOf(STATE.stateUrl)) {
        writeOutbox(events);
        outcome = { ok: false, text: "Not confirmed: this board checks its answers on " + storeOf(STATE.listUrl)
          + " but reads its shared state from " + storeOf(STATE.stateUrl)
          + ", so it cannot say the fold that feeds this board will find them." };
        refreshLiveness();
        return false;
      }
      setStateStatus("Sent " + events.length + " — checking the store has them…");
      return readBack(sent).then(function (res) {
        if (res.error || res.missing.length) {
          var gone = res.error ? events : res.missing.map(function (x) { return x.ev; });
          writeOutbox(gone);
          outcome = { ok: false, text: res.error
            ? "Not confirmed: the answers were sent, but the store could not be read back to check them — " + res.error + "."
            : "Not stored: " + res.missing.length + " of " + events.length + " answers were sent but are not in the store." };
          refreshLiveness();
          return false;
        }
        /* Only on a clean, confirmed sweep: a receipt that can never retire would sit there
           claiming "waiting" forever. It is also what tells the reveal which items this person
           just answered. */
        writeOutbox([]);
        recordReceipt(ids, true);
        outcome = { ok: true, text: "Stored at " + hhmm(new Date()) + " ✓ — " + events.length
          + (events.length === 1 ? " answer is" : " answers are") + " listed in this board's inbox, on the store its "
          + "shared state is read from; " + (events.length === 1 ? "it appears" : "they appear")
          + " here once an agent folds that inbox (a few times a day)." };
        renderState();
        refreshLiveness();
        pollDelay = POLL_MIN;
        return true;
      });
    });
  }

  /* ── Read-side fold ──────────────────────────────────────────────────────────────────
     state/<doc>.json is an append-only LOG. The fold (state-append.sh) blind-appends and inspects
     nothing, so duplicates and superseded answers are EXPECTED to be sitting in the doc. Every
     reader applies PAYLOAD_SCHEMA.md's rules at read time — this widget here, the wave at ingest.
     Deliberately not pushed into the fold: a shell script cannot import a markdown contract, and
     the moment it reimplements one there are two rule-sets to keep in step. */
  function actorKey(a) {
    if (!a || !a.kind) return "?:unknown";
    if (a.kind === "council") return "c:" + slug(a.lens);
    if (a.kind === "human") return "h:" + (slug(a.name) || "anon");
    return "r:" + (slug(a.id || a.handle) || "anon");
  }

  function tsMs(ev) { var t = Date.parse(ev && ev.ts); return isNaN(t) ? 0 : t; }

  function foldEvents(events) {
    var byId = Object.create(null), order = [], i, ev, k, t;
    for (i = 0; i < (events || []).length; i++) {
      ev = events[i];
      if (!ev || !ev.id) continue;                 // an id-less record cannot be deduped; drop it
      if (!Object.prototype.hasOwnProperty.call(byId, ev.id)) order.push(ev.id);
      byId[ev.id] = ev;                            // same id appended twice: the later copy wins
    }
    var best = Object.create(null);
    for (i = 0; i < order.length; i++) {
      ev = byId[order[i]];
      k = actorKey(ev.actor) + "\u0000" + ev.item;
      t = tsMs(ev);
      if (!Object.prototype.hasOwnProperty.call(best, k) || t > best[k]) best[k] = t;
    }
    var out = [];
    for (i = 0; i < order.length; i++) {
      ev = byId[order[i]];
      k = actorKey(ev.actor) + "\u0000" + ev.item;
      if (tsMs(ev) === best[k]) out.push(ev);       // per (actor,item), only the greatest ts stands
    }
    return out;
  }

  /* ── Render other people's marks ─────────────────────────────────────────────────────
     Two hard rules, both load-bearing:
     1. NEVER touch a [data-fb-panel] node. Council marks are static markup and a poll must leave
        them byte-identical; the kit only ever writes into its own host element.
     2. EVERY string from the polled doc goes in via textContent / setAttribute, never innerHTML.
        The doc is world-readable and anyone with the presign can write to it. */
  function initials(name) {
    var parts = String(name || "").trim().split(/\s+/);
    var clean = [];
    for (var i = 0; i < parts.length; i++) if (parts[i]) clean.push(parts[i]);
    if (!clean.length) return "?";
    if (clean.length === 1) return clean[0].slice(0, 2).toUpperCase();
    return (clean[0].charAt(0) + clean[clean.length - 1].charAt(0)).toUpperCase();
  }

  /* Which items has this person taken a position on? A running tally shown BEFORE they have turns
     an independent read into an anchored one, which leaves ¶INV_PANEL_VOTES_ARE_A_READ_NOT_A_VERDICT
     literally true while hollowing it out. So: no marks, and no count either, until they answer.

     The question is asked PER ITEM. A board carries several decisions, and a page-wide reading —
     one tick anywhere opens everything — hands the reader everyone else's answer to the decisions
     they have not thought about yet, which is the anchoring the gate exists to prevent.
     ¶INV_REVEAL_IS_PER_ITEM.

     Deliberately NOT "is a checkbox ticked right now": a reload restores no ticks, so that reading
     hides the tally from someone who has already voted — the gate firing on the wrong question.
     A stored receipt is this person having answered; it is not a weakening of the gate. */

  /* An event id reads "<t>:h:<actor-slug>:<item>[:<key-or-field>]". The actor slug never holds a
     colon (slug() strips them), but an item id, an option key and a field name all may —
     `measure:extraction-count` is a real key and `finding:ENG-3461` a real item id — so the tail
     is never split on ":". It is read against what the board DECLARES, and a declared item alone
     is not enough to read it with: `finding` + key `ENG-3461` and the item `finding:ENG-3461`
     spell the same tail, so matching by item (longest or otherwise) picks the wrong one in one
     direction or the other. The whole tail must equal item + ":" + a key or field that item
     carries — or the item itself for a note, the one id shape that legitimately ends there.

     Two items that can both account for one tail resolve to NEITHER. Guessing opens an untouched
     decision half the time, which is the gate failing open, and that is the harm it exists to
     prevent — so an ambiguous id fails shut. */
  function itemFromEventId(id, declared) {
    var parts = String(id || "").split(":");
    var kind = parts[0], rest = parts.slice(3).join(":"), hit = "", best = "", d, i;
    for (i = 0; i < declared.length; i++) {
      d = declared[i];
      if (!d.id) continue;
      if (kind === "n" ? rest === d.id : !!d.tails[kind + ":" + rest]) {
        if (hit && hit !== d.id) return "";
        hit = d.id;
      }
    }
    if (hit) return hit;
    /* The tail names an option this board no longer declares — a receipt written before the board
       was recomposed. Failing shut would blind someone who demonstrably did vote, so the item
       prefix still recovers it. An exact tail cannot land here: a vote and a field id always carry
       a trailing segment, so `rest === item` for either is a mis-read, not a stale key. */
    for (i = 0; i < declared.length; i++) {
      d = declared[i].id;
      if (d && rest.indexOf(d + ":") === 0 && d.length > best.length) best = d;
    }
    return best;
  }

  function positionsTaken() {
    var taken = Object.create(null);
    var containers = document.querySelectorAll("[data-fb-item]");
    var declared = [], c, d, els, ids, it, i, j;
    for (i = 0; i < containers.length; i++) {
      c = containers[i];
      d = { id: attr(c, "data-fb-item"), tails: Object.create(null) };
      els = c.querySelectorAll("[data-fb-key]");
      for (j = 0; j < els.length; j++) {
        d.tails["v:" + d.id + ":" + attr(els[j], "data-fb-key")] = true;
        if (els[j].checked) taken[d.id] = true;
      }
      els = c.querySelectorAll("[data-fb-field]");
      for (j = 0; j < els.length; j++) d.tails["f:" + d.id + ":" + attr(els[j], "data-fb-field")] = true;
      declared.push(d);
    }
    /* The receipt stands in for the ticks a reload erased — for the items it names and no others.
       It also covers the submit that just happened: recordReceipt() sets it in memory even when
       the device refuses to store it, so there is no separate page-wide "submitted" reading. */
    ids = (receipt && receipt.ids) || [];
    for (i = 0; i < ids.length; i++) {
      it = itemFromEventId(ids[i], declared);
      if (it) taken[it] = true;
    }
    return taken;
  }

  function ownHost(parent, cls) {
    var kids = parent.children || [];
    for (var i = 0; i < kids.length; i++) if (kids[i] && kids[i].fbOwned) return kids[i];
    var host = document.createElement("span");
    host.className = cls;
    host.fbOwned = true;          // the kit clears ONLY this element; siblings (council marks) stand
    parent.appendChild(host);
    return host;
  }

  function markNode(ev) {
    var b = document.createElement("span");
    b.className = "fb-mark fb-mark-human";
    b.textContent = initials(ev.actor && ev.actor.name);
    b.setAttribute("title", (ev.actor && ev.actor.name ? ev.actor.name : "a teammate") + " picked this");
    return b;
  }

  function renderState() {
    if (!STATE || !lastEvents) return;
    var folded = foldEvents(lastEvents);
    var revealed = positionsTaken();
    var byItemKey = Object.create(null);
    for (var i = 0; i < folded.length; i++) {
      var ev = folded[i];
      if (ev.type !== "vote" || !ev.actor || ev.actor.kind !== "human") continue;
      var k = ev.item + "\u0000" + ev.key;
      (byItemKey[k] = byItemKey[k] || []).push(ev);
    }

    var containers = document.querySelectorAll("[data-fb-item]");
    for (i = 0; i < containers.length; i++) {
      var c = containers[i], item = attr(c, "data-fb-item");
      var reveal = !!revealed[item];                 // this item's own gate, never the page's
      var slots = c.querySelectorAll("[data-fb-marks]");
      var covered = Object.create(null), s, key, host, votes, j;
      for (s = 0; s < slots.length; s++) {
        key = attr(slots[s], "data-fb-marks");
        covered[key] = true;
        host = ownHost(slots[s], "fb-humanmarks");
        host.replaceChildren();
        votes = reveal ? (byItemKey[item + "\u0000" + key] || []) : [];
        for (j = 0; j < votes.length; j++) host.appendChild(markNode(votes[j]));
      }
      /* Boards with no per-key slots still show the marks, just less prettily — a board that
         predates the slot contract must not silently render multiplayer as "nobody voted". */
      var orphans = [];
      var keyInputs = c.querySelectorAll("[data-fb-key]");
      for (j = 0; j < keyInputs.length; j++) {
        key = attr(keyInputs[j], "data-fb-key");
        if (covered[key]) continue;
        votes = reveal ? (byItemKey[item + "\u0000" + key] || []) : [];
        if (votes.length) orphans.push({ key: key, votes: votes });
      }
      if (!orphans.length && !c.querySelector("[data-fb-presence]")) continue;
      var box = c.querySelector("[data-fb-presence]");
      if (!box) {
        box = document.createElement("div");
        box.className = "fb-presence";
        box.setAttribute("data-fb-presence", "");
        c.appendChild(box);
      }
      host = ownHost(box, "fb-presence-rows");
      host.replaceChildren();
      for (j = 0; j < orphans.length; j++) {
        var row = document.createElement("div");
        row.className = "fb-presence-row";
        var lab = document.createElement("span");
        lab.className = "fb-presence-key";
        lab.textContent = orphans[j].key;                       // an option key is board-authored…
        row.appendChild(lab);
        for (s = 0; s < orphans[j].votes.length; s++) row.appendChild(markNode(orphans[j].votes[s]));
        host.appendChild(row);                                  // …a voter name is not: textContent only
      }
    }
  }

  /* ── Poll ────────────────────────────────────────────────────────────────────────────
     Conditional GET. Every CAS fold rewrites the doc, so its ETag changes on exactly the updates
     that matter and an unchanged poll is 304 + zero bytes. Same-origin, so the ETag header is
     readable without a CORS expose-header grant. */
  function schedulePoll() {
    if (!STATE) return;
    setTimeout(poll, pollDelay);
  }

  function slower(factor) { pollDelay = Math.min(Math.round(pollDelay * factor), POLL_MAX); }

  function poll() {
    if (!STATE || typeof fetch !== "function") return;
    var headers = {};
    if (lastEtag) headers["If-None-Match"] = lastEtag;
    return fetch(STATE.stateUrl, { cache: "no-store", headers: headers }).then(function (r) {
      if (r.status === 304) { slower(1.6); return null; }        // unchanged — nothing transferred
      /* A missing or refused state document. Which of the two it is used to be unanswerable, so
         this arm forgave both and the board rendered "not folded yet" forever.
         The publish now WRITES the document and reads it back with no credential, and says so in
         stateVerified. So: verified once (by the publish or by a read here) ⇒ a 403/404 is a
         genuine failure and is reported. Not verified ⇒ keep forgiving it, because an older page
         or a store that refuses the prefix genuinely cannot tell — but say THAT rather than
         claiming nothing has been folded. */
      if (r.status === 404 || r.status === 403) {
        lastEtag = null;
        slower(1.6);
        /* 404 and 403 are different facts and only one of them was ever ambiguous. A 404 proves
           the prefix IS served and the object simply is not there — which, on a board whose
           document was never verified, is the honest pre-fold state and keeps the words the kit
           already had. A 403 proves nothing about the object, only that the reader was refused. */
        if (r.status === 404 && !(STATE.stateVerified || docSeen)) {
          readBroken = null;
          markReadState("waiting");
          return null;
        }
        if (STATE.stateVerified || docSeen) {
          /* Same opening phrase as the fetch-rejection path on purpose: "the read failed" is one
             fact with one name, however the failure arrived. */
          readBroken = "Could not read the shared board (HTTP " + r.status + " on its state document"
            + (STATE.stateKey ? " " + STATE.stateKey : "") + "). Answers already submitted are not lost, "
            + "but nothing anyone sends can be shown here until that read works";
          markReadState("broken");
        } else {
          /* A page published before the state document was written cannot tell the two cases
             apart — so it says that, rather than the reassuring "not folded yet" it used to say.
             Claiming nothing has been folded is the one sentence that stops anyone looking. */
          readBroken = "Cannot tell whether anything has been folded into this board — its state "
            + "document answered HTTP " + r.status + " and this publish never confirmed the document "
            + "is readable, so an empty board here is not evidence that nothing was answered";
          markReadState("unverified");
        }
        return null;
      }
      if (!r.ok) throw new Error("HTTP " + r.status);
      docSeen = true;
      readBroken = null;
      markReadState("ok");
      lastEtag = (r.headers && r.headers.get) ? r.headers.get("ETag") : null;
      return r.json();
    }).then(function (doc) {
      if (doc) {
        lastEvents = (doc && doc.events) || [];
        if (doc.supersededBy && doc.supersededBy.url) superseded = doc.supersededBy;
        reconcileReceipt(doc);
        pollDelay = POLL_MIN;                                    // it moved — look again sooner
        renderState();
      }
      refreshLiveness();
    }, function (e) {
      slower(2);
      /* Sticky, so refreshLiveness cannot paint over it on the next tick — which is how a read
         failure came to be invisible: the quiet arm returned through the SUCCESS path and the
         liveness line re-rendered the submit reason on top of it. */
      readBroken = "Could not read the shared board (" + (e && e.message ? e.message : e) + ")";
      markReadState("broken");
      refreshLiveness();
    }).then(schedulePoll, schedulePoll);
  }

  function ensureStateBar() {
    if (document.querySelector("[data-fb-submit]") && document.querySelector("[data-fb-state-status]")) return;
    var bar = document.createElement("div");
    bar.className = "fb-statebar";
    bar.innerHTML =
      '<button type="button" class="fb-submitbtn" data-fb-submit>Submit to the shared board</button>' +
      '<span class="fb-statestatus" data-fb-state-status></span>';
    document.body.appendChild(bar);
  }

  function ensureUnsentBar() {
    if (document.querySelector("[data-fb-retry]")) return;
    var bar = document.createElement("div");
    bar.className = "fb-unsentbar";
    bar.innerHTML =
      '<button type="button" class="fb-retrybtn" data-fb-retry hidden>Retry</button>' +
      '<button type="button" class="fb-copybtn" data-fb-copy-unsent hidden>Copy unsent answers</button>';
    document.body.appendChild(bar);
  }
  function showUnsentControls(gate) {
    var retry = document.querySelector("[data-fb-retry]");
    var cp = document.querySelector("[data-fb-copy-unsent]");
    var failedNow = !!(outcome && !outcome.ok);
    function vis(el, on) { if (!el) return; if (on) el.removeAttribute("hidden"); else el.setAttribute("hidden", ""); }
    vis(retry, failedNow);
    if (retry) retry.disabled = !gate.ok;
    vis(cp, unsent.length > 0);
  }

  function wireState() {
    STATE = readStateConfig();
    if (!STATE) return;                 // no config ⇒ no bar, no listener, no fetch, no behaviour change
    receipt = readReceipt();            // …and no storage read either: a board that did not opt in stays untouched
    /* The publish already answered the readability question with a credential-free GET. Carry its
       finding to the first paint rather than making every reader wait a poll to learn it. */
    if (STATE.stateUnreadableReason) {
      readBroken = "This board was published with an unreadable shared state: " + STATE.stateUnreadableReason;
      markReadState("broken");
    } else {
      markReadState(STATE.stateVerified ? "waiting" : "unverified");
    }
    ensureStateBar();
    ensureUnsentBar();
    /* Answers an earlier visit could not get into the store. Said first, because they are the
       one thing on this page that exists nowhere else. */
    unsent = readOutbox();
    if (unsent.length) {
      outcome = { ok: false, text: "An earlier Submit did not reach the store." };
    }
    var btn = document.querySelector("[data-fb-submit]");
    if (btn) btn.addEventListener("click", submit);
    var rbtn = document.querySelector("[data-fb-retry]");
    if (rbtn) rbtn.addEventListener("click", submit);
    var cbtn = document.querySelector("[data-fb-copy-unsent]");
    if (cbtn) cbtn.addEventListener("click", copyUnsent);
    refreshLiveness();
    poll();
  }

  function wire() {
    ensureCopyBar();
    wirePanelMarks();
    wireDisclosures();
    var btn = document.querySelector("[data-fb-copy]");
    if (btn) btn.addEventListener("click", copy);
    document.addEventListener("change", function (e) {
      if (e.target.closest && e.target.closest("[data-fb-item]")) { refreshPreview(); renderState(); }
    });
    document.addEventListener("input", function (e) {
      if (e.target.closest && (e.target.closest("[data-fb-item]") || e.target.hasAttribute("data-fb-voter"))) refreshPreview();
    });
    refreshPreview();
    wireState();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", wire);
  else wire();

  window.ProveBoard = {
    buildEvents: buildEvents, payloadText: payloadText, copy: copy, refresh: refreshPreview,
    /* Shared-state surface, exported so it is testable without a browser and a live bucket. */
    /* The kit's read of the board's disclosures, so the device is verifiable without a browser.
       A read only — nothing here opens, closes or records a reader's expansion. */
    disclosures: disclosures,
    fold: foldEvents, submit: submit, render: renderState, liveness: refreshLiveness, poll: poll,
    /* The submit verdict and the unsent answers it kept, readable without a browser. */
    submitOutcome: function () { return outcome; },
    unsent: function () { return unsent.slice(); }, unsentText: unsentText, copyUnsent: copyUnsent,
    stateConfig: function () { return STATE; },
    /* The read half's own verdict, so a test can assert that a refusal and an unfolded board are
       different observations without driving a browser. */
    readState: function () { return { broken: readBroken, docSeen: docSeen, superseded: superseded }; },
    applyState: function (doc) { lastEvents = (doc && doc.events) || []; renderState(); }
  };
})();
