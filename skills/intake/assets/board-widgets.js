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
 *   [data-fb-panel-roster] [data-fb-panel-report]  — council run metadata (anywhere; first wins)
 *   [data-fb-copy]     — the copy button (auto-created if absent)
 *   [data-fb-payload]  — the visible payload box (auto-created if absent)
 *
 * Shared-state (multiplayer) markup — ENTIRELY OPTIONAL. A board with no [data-fb-state-config]
 * behaves exactly as it did before this existed: copy-back only, and no network request at all.
 *   [data-fb-state-config]  — a <script type="application/json"> whose text is the publish-injected
 *      config {docId, stateUrl, pollMs, postUrl?, keyPrefix?, fields?, expiresAt?,
 *      submitDisabledReason?}. Unresolved/absent/unparseable ⇒ not configured ⇒ today's board.
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
  var submitted = false;
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

  function setStateStatus(msg) {
    var el = document.querySelector("[data-fb-state-status]");
    if (el) el.textContent = msg;
  }

  function voterName() {
    var el = document.querySelector("[data-fb-voter]");
    return el ? txt(el) : "";
  }

  /* Expiry is a first-class rendered state, not a warning banner. */
  function expiryMs() {
    if (!STATE || !STATE.expiresAt) return null;
    var t = Date.parse(STATE.expiresAt);
    return isNaN(t) ? null : t;
  }

  function submitGate() {
    if (!STATE) return { ok: false, reason: "this board has no shared-state config" };
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

  function refreshLiveness() {
    if (!STATE) return;
    var gate = submitGate();
    var btn = document.querySelector("[data-fb-submit]");
    if (btn) {
      btn.disabled = !gate.ok;
      if (btn.setAttribute) btn.setAttribute("aria-disabled", gate.ok ? "false" : "true");
    }
    if (!gate.ok) { setStateStatus(gate.reason + COPY_BACK); return; }
    var exp = expiryMs();
    var left = exp == null ? null : exp - Date.now();
    if (left != null && left < 1800000) {
      setStateStatus("Heads up: this board stops accepting answers at " + STATE.expiresAt + COPY_BACK);
      return;
    }
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
    fd.append("key", STATE.keyPrefix + Date.now() + "-" + Math.random().toString(16).slice(2, 10) + ".json");
    fd.append("Content-Type", "application/json");
    fd.append("file", new Blob([JSON.stringify(ev)], { type: "application/json" }));  // file LAST
    return fetch(STATE.postUrl, { method: "POST", body: fd }).then(function (r) {
      if (!(r.status === 204 || r.ok)) throw new Error("HTTP " + r.status);
      return true;
    });
  }

  function submit() {
    var gate = submitGate();
    if (!gate.ok) { setStateStatus(gate.reason + COPY_BACK); return Promise.resolve(false); }

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
    var events = humanEvents(meta, new Date().toISOString());
    if (!events.length) { setStateStatus("Nothing to submit yet — make a pick first."); return Promise.resolve(false); }

    setStateStatus("Submitting " + events.length + "…");
    var failed = 0, firstErr = "";
    return Promise.all(events.map(function (ev) {
      return postOne(ev).then(null, function (e) { failed++; if (!firstErr) firstErr = e && e.message ? e.message : String(e); });
    })).then(function () {
      if (failed) {
        setStateStatus(failed + " of " + events.length + " answers did not post (" + firstErr + ")" + COPY_BACK);
        return false;
      }
      submitted = true;
      setStateStatus("Submitted " + events.length + " ✓ — they show up here once the fold runs (agent-run, a few times a day).");
      renderState();
      pollDelay = POLL_MIN;
      return true;
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

  /* The local voter's own picks — a running tally shown BEFORE someone has answered turns an
     independent read into an anchored one, which leaves ¶INV_PANEL_VOTES_ARE_A_READ_NOT_A_VERDICT
     literally true while hollowing it out. So: no marks, and no count either, until they pick. */
  function hasLocalPicks() {
    if (submitted) return true;
    var containers = document.querySelectorAll("[data-fb-item]");
    for (var i = 0; i < containers.length; i++) {
      var inputs = containers[i].querySelectorAll("[data-fb-key]");
      for (var j = 0; j < inputs.length; j++) if (inputs[j].checked) return true;
    }
    return false;
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
    var reveal = hasLocalPicks();
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
      if (r.status === 404) { lastEtag = null; slower(1.6); return null; }  // nothing folded yet
      if (!r.ok) throw new Error("HTTP " + r.status);
      lastEtag = (r.headers && r.headers.get) ? r.headers.get("ETag") : null;
      return r.json();
    }).then(function (doc) {
      if (doc) {
        lastEvents = (doc && doc.events) || [];
        pollDelay = POLL_MIN;                                    // it moved — look again sooner
        renderState();
      }
      refreshLiveness();
    }, function (e) {
      slower(2);
      setStateStatus("Could not read the shared board (" + (e && e.message ? e.message : e) + ")" + COPY_BACK);
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

  function wireState() {
    STATE = readStateConfig();
    if (!STATE) return;                 // no config ⇒ no bar, no listener, no fetch, no behaviour change
    ensureStateBar();
    var btn = document.querySelector("[data-fb-submit]");
    if (btn) btn.addEventListener("click", submit);
    refreshLiveness();
    poll();
  }

  function wire() {
    ensureCopyBar();
    wirePanelMarks();
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

  window.FinchBoard = {
    buildEvents: buildEvents, payloadText: payloadText, copy: copy, refresh: refreshPreview,
    /* Shared-state surface, exported so it is testable without a browser and a live bucket. */
    fold: foldEvents, submit: submit, render: renderState, liveness: refreshLiveness, poll: poll,
    stateConfig: function () { return STATE; },
    applyState: function (doc) { lastEvents = (doc && doc.events) || []; renderState(); }
  };
})();
