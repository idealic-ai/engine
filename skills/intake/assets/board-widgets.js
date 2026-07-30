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

  function wire() {
    ensureCopyBar();
    wirePanelMarks();
    var btn = document.querySelector("[data-fb-copy]");
    if (btn) btn.addEventListener("click", copy);
    document.addEventListener("change", function (e) {
      if (e.target.closest && e.target.closest("[data-fb-item]")) refreshPreview();
    });
    document.addEventListener("input", function (e) {
      if (e.target.closest && (e.target.closest("[data-fb-item]") || e.target.hasAttribute("data-fb-voter"))) refreshPreview();
    });
    refreshPreview();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", wire);
  else wire();

  window.FinchBoard = { buildEvents: buildEvents, payloadText: payloadText, copy: copy, refresh: refreshPreview };
})();
