/* board-swipe.js — a drag accelerator for BINARY decisions on a decision board.
 *
 *   [data-fb-item][data-fb-kind="consolidation"|"adopt-cancel"] with exactly two
 *   [data-fb-key] inputs gets a DECIDE BAR rendered directly above its option rows.
 *   Drag the bar left or right past the threshold and it commits by calling
 *   input.click() — so the layer IS the click path and the emitted event is the
 *   click-path event by construction, not by resemblance.
 *
 * Load AFTER board-widgets.js. It reads no kit internals and writes no kit state:
 * the checked input is the only store, so a row click, a keyboard arrow and a drag
 * are the same fact and the bar re-reads itself from `change`.
 *
 * The three settled facts this file is built on:
 *   - `input.click()`, never `.checked = true` + a synthetic event.
 *   - `touch-action: pan-y`, and only on the ~44px bar. `none` measured 0px of page
 *     scroll over every card; there is no vertical gesture here and must not be one.
 *   - `steer` items carry 3–5 options and have no left/right. Allowlist, never guess.
 *
 * Zero-JS: every rule in board-swipe.css is scoped under `html.board-swipe-on`,
 * which only this file sets, and the bar is injected only by this file. Script off
 * ⇒ no class, no bar, no rule — the kit's own option rows, untouched.
 */
(function () {
  "use strict";

  var BOARD_SWIPE_VERSION = 1;

  /* Binary kinds ONLY. A kind absent from this list is never bound — including an
     unknown future kind, which must fail closed rather than be swiped as a coin flip. */
  var BINARY_KINDS = { consolidation: 1, "adopt-cancel": 1 };

  /* Direction is SEMANTIC first: the affirmative option goes right. DOM order is only
     the fallback, and even then the bar prints both option labels at its ends, so the
     reader never has to infer which way is which. */
  var AFFIRMATIVE = /^(approve|adopt|accept|yes|keep|merge|confirm|proceed|ship)$/i;
  var NEGATIVE = /^(reject|cancel|decline|no|drop|separate|defer|hold|skip)$/i;

  var CLAIM = 8;          // px of travel before the gesture claims an axis
  var THRESHOLD = 84;     // px of horizontal travel before a release commits
  var TRAVEL = 44;        // px the thumb may translate. The BLOCK never moves.

  var census = { version: BOARD_SWIPE_VERSION, bound: [], skipped: [] };
  window.__boardSwipe = census;

  function text(el) { return el ? (el.textContent || "").trim() : ""; }

  function labelFor(input) {
    var lab = input.closest ? input.closest("label") : null;
    var t = lab ? text(lab.querySelector(".fb-opt-label")) : "";
    if (!t && lab) t = text(lab).split("\n")[0];
    if (!t) t = input.getAttribute("data-fb-key") || "";
    return t.length > 30 ? t.slice(0, 29) + "…" : t;
  }

  /* Mirror exactly what a person clicking that row would do — no more. On radios the
     click is the whole story. On a checkbox pair the sibling has to be cleared first,
     which is also just a click; the kit derives the payload from live checked state,
     so the result is the state a person would have produced. Never retract: a drag is
     an assertion, and click()-ing an already-checked box would undo it. */
  function commit(target, sibling) {
    if (target.checked) return "already";
    if (target.type === "checkbox" && sibling.checked) sibling.click();
    target.click();
    return "committed";
  }

  function bind(item) {
    var kind = item.getAttribute("data-fb-kind") || "";
    var id = item.getAttribute("data-fb-item") || "(unnamed)";
    var inputs = item.querySelectorAll("[data-fb-key]");

    function skip(why) { census.skipped.push({ item: id, kind: kind, opts: inputs.length, why: why }); return false; }

    if (!BINARY_KINDS[kind]) return skip("kind-not-binary");
    if (inputs.length !== 2) return skip("not-two-options");
    var a = inputs[0], b = inputs[1];
    if (a.tagName !== "INPUT" || b.tagName !== "INPUT") return skip("not-inputs");
    if (a.type !== b.type || (a.type !== "radio" && a.type !== "checkbox")) return skip("unsupported-input");

    var ka = a.getAttribute("data-fb-key") || "", kb = b.getAttribute("data-fb-key") || "";
    var right = a, left = b, how = "dom-order";
    if (AFFIRMATIVE.test(ka) && NEGATIVE.test(kb)) { right = a; left = b; how = "semantic"; }
    else if (AFFIRMATIVE.test(kb) && NEGATIVE.test(ka)) { right = b; left = a; how = "semantic"; }

    var host = item.querySelector(".fb-options");
    var anchor = host || (a.closest ? a.closest("label") : null);
    if (!anchor || !anchor.parentNode) return skip("no-insertion-point");

    var bar = document.createElement("div");
    bar.className = "bswipe";
    bar.setAttribute("data-bswipe", id);
    bar.innerHTML =
      '<div class="bswipe-track" aria-hidden="true">' +
        '<span class="bswipe-end bswipe-end-l"><span class="bswipe-arrow">←</span><span class="bswipe-endlab"></span></span>' +
        '<span class="bswipe-end bswipe-end-r"><span class="bswipe-endlab"></span><span class="bswipe-arrow">→</span></span>' +
        '<span class="bswipe-thumb"><span class="bswipe-status"></span></span>' +
      '</div>' +
      '<button type="button" class="bswipe-note">Note ↓</button>';
    bar.querySelector(".bswipe-end-l .bswipe-endlab").textContent = labelFor(left);
    bar.querySelector(".bswipe-end-r .bswipe-endlab").textContent = labelFor(right);
    anchor.parentNode.insertBefore(bar, anchor);

    var track = bar.querySelector(".bswipe-track");
    var thumb = bar.querySelector(".bswipe-thumb");
    var status = bar.querySelector(".bswipe-status");
    var noteBtn = bar.querySelector(".bswipe-note");

    var note = item.querySelector("[data-fb-note]");
    if (!note) noteBtn.remove();
    else {
      noteBtn.setAttribute("aria-label", "Write a note on this decision");
      noteBtn.addEventListener("click", function () {
        note.focus();
        if (note.scrollIntoView) note.scrollIntoView({ block: "nearest" });
      });
    }

    /* The bar renders FROM the inputs, never from its own memory. That is what keeps a
       keyboard vote, a row click and a drag the same state instead of two. */
    function render() {
      var picked = right.checked ? "r" : (left.checked ? "l" : "");
      bar.setAttribute("data-bswipe-state", picked || "open");
      status.textContent = picked === "r" ? "✓ " + labelFor(right)
                         : picked === "l" ? "✓ " + labelFor(left)
                         : "drag to decide";
    }

    var x0 = 0, y0 = 0, axis = null, live = false, pid = null, dir = "";

    function place(dx) {
      /* Rubber band: full travel to the threshold, then a hard stop. The gesture must
         READ as directional without moving anything a reader might be looking at. */
      var t = Math.max(-1, Math.min(1, dx / THRESHOLD)) * TRAVEL;
      thumb.style.transform = "translateX(" + t.toFixed(1) + "px)";
      dir = Math.abs(dx) < THRESHOLD ? "" : (dx > 0 ? "r" : "l");
      if (dir) bar.setAttribute("data-bswipe-dir", dir); else bar.removeAttribute("data-bswipe-dir");
      /* Mid-drag the thumb reports the PENDING decision, not the standing one. Leaving
         the standing one up while the bar washes the other way reads as a contradiction. */
      status.textContent = dir ? "release · " + labelFor(dir === "r" ? right : left) : "drag to decide";
    }

    function release() {
      thumb.style.transform = "";
      bar.removeAttribute("data-bswipe-dir");
      bar.removeAttribute("data-bswipe-live");
      axis = null; live = false; pid = null; dir = "";
      render();
    }

    track.addEventListener("pointerdown", function (e) {
      if (e.button !== undefined && e.button !== 0) return;
      x0 = e.clientX; y0 = e.clientY; axis = null; live = true; pid = e.pointerId;
    });

    track.addEventListener("pointermove", function (e) {
      if (!live || e.pointerId !== pid) return;
      var dx = e.clientX - x0, dy = e.clientY - y0;
      if (!axis) {
        if (Math.abs(dx) < CLAIM && Math.abs(dy) < CLAIM) return;
        /* A vertical intent belongs to the page, always. We hand it straight back —
           `touch-action: pan-y` means the browser is already scrolling by this point. */
        if (Math.abs(dy) > Math.abs(dx)) { live = false; return; }
        axis = "x";
        bar.setAttribute("data-bswipe-live", "");
        try { track.setPointerCapture(pid); } catch (err) { /* capture is a nicety */ }
      }
      place(dx);
    });

    track.addEventListener("pointerup", function (e) {
      if (!live || (pid !== null && e.pointerId !== pid)) { release(); return; }
      var dx = e.clientX - x0;
      if (axis === "x" && Math.abs(dx) >= THRESHOLD) commit(dx > 0 ? right : left, dx > 0 ? left : right);
      release();
    });
    track.addEventListener("pointercancel", release);

    item.addEventListener("change", render);
    render();

    census.bound.push({ item: id, kind: kind, right: right.getAttribute("data-fb-key"),
                        left: left.getAttribute("data-fb-key"), direction: how });
    return true;
  }

  function start() {
    var items = document.querySelectorAll("[data-fb-item]");
    if (!items.length) return;
    document.documentElement.classList.add("board-swipe-on");
    for (var i = 0; i < items.length; i++) bind(items[i]);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
