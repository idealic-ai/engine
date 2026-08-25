/* kit-behaviors.js — the DECISION LAYER behavior for /prove evidence pages (FIN-3566).
 *
 * BEHAVIOR ONLY. This script never injects, mutates, or reads styling — all appearance comes
 * from proof-blocks.css. It wires whatever decision widgets a page declares, by CONVENTION
 * (data-attributes + kit classes), so it composes onto any page with zero per-page glue:
 *
 *   Item scope       [data-decision-item] (or legacy .dxsec) — one decidable finding per element
 *   Owners           data-owner="rm yf"   — space-list of person keys on each input/textarea
 *   People chips      .ava[data-person] with .cnt[data-prog] · .pn holds the display name
 *   Dirty label      .unsaved[data-for=<key>]        — ANY number of them, all one state
 *   Submit           .submitbtn[data-submit=<key>]   — ANY number of them, all one state
 *   State chip       .idstate[data-state-for=<key>] with .idstate-n
 *   Acting-as pick   .idpop-pick[data-act-as=<key>]  — attribution only, gates nothing
 *   Stepper cluster  .stepper[data-person=<key>] with .stepbtn[data-step="-1|1"]
 *   View filter      .ava[href="#view-<key>"] — clicking scopes the page to that person
 *
 * Everything degrades: without JS, votes/notes still work as native form controls, popovers
 * still reveal (native popover), stepper/view anchors are plain in-page links (all visible).
 *
 * Enhancements added here:
 *   · reversible votes + a clear-× on radio verdict / single-select
 *   · baseline-vs-current dirty tracking, per-person progress + unsaved count
 *   · per-person submit (rebaselines that person's changed items) + beforeunload guard
 *   · universal note affordance (open/close, has-note state, Revise-nudge)
 *   · per-decision confirmation strip (reveal the note · skip · clear), built from `.noteaff`
 *   · view filter (dim items the active person doesn't own) + item stepper
 *
 * KIT_BEHAVIORS_VERSION = 1
 * Its own version, independent of board-widgets' SCHEMA_VERSION (it emits no payload) and of
 * proof-blocks (style turns over separately): publish-kit.sh reads this constant to mint
 * kit-behaviors.v<n>.js. Bump it when the data-attribute convention above breaks.
 *   v1 — the conventions above. Republished IN PLACE since, without a bump, because no
 *        convention broke; what changed is behaviour under the same attributes:
 *        · ONE STATE, MANY CONTROLS. `renderPerson` addressed the FIRST `.submitbtn` and the
 *          FIRST `.unsaved` for a key; the sticky bar's submit and the end-of-document mirror
 *          are two entry points onto one state, so it now renders EVERY node for the key.
 *          A page with one of each is byte-identical; a page with a mirror stops drifting.
 *        · `.idstate[data-state-for]` — the state chip's posted count, reflected from the same
 *          submit path. The chip's authored words are never rewritten: whether the fold has
 *          run is the transport's fact, not this script's, and it does not pretend to know.
 *        · the submitted count is CUMULATIVE rather than per-batch, so "3 posted" means three
 *          answers exist, which is what the chip and its explanation both claim.
 *        · `.idpop-pick[data-act-as]` — the acting-as switcher. It copies a name into the bar.
 *          It performs no check and implies none.
 *        · THE CONFIRMATION STRIP. Nothing new is asked of a page: the strip is constructed
 *          per `.noteaff`, which every decision block already authors, so the convention is
 *          unchanged and pages published against v1 pick the strip up on re-deploy. The
 *          Revise-nudge generalised from one option value to ANY decision — reveal only, never
 *          a focus move, which is what the nudge already did.
 */
(function () {
  'use strict';
  if (typeof document === 'undefined') return;

  var ITEM_SEL = '[data-decision-item], .dxsec';
  var VOTE_SEL = '.vseg input, .fbopt input';

  function all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
  function owners(node) { return (node.getAttribute('data-owner') || '').split(/\s+/).filter(Boolean); }
  function itemOf(node) { return node ? node.closest(ITEM_SEL) : null; }

  var inputs = all(VOTE_SEL);
  var notes = all('.notefield');
  if (!inputs.length && !notes.length && !all('.notebtn').length) return; // no decision layer on this page

  // ── discover people from the DOM (owner keys on inputs) + display names from .ava chips ──
  var peopleSet = {};
  inputs.concat(notes).forEach(function (n) { owners(n).forEach(function (o) { peopleSet[o] = true; }); });
  var PEOPLE = Object.keys(peopleSet);
  function displayName(key) {
    var av = document.querySelector('.ava[data-person="' + key + '"] .pn') || document.querySelector('.ava[data-person="' + key + '"]');
    return (av && av.textContent.trim()) || key;
  }

  // ── which items each person owns, in document order ──
  var itemsInOrder = all(ITEM_SEL);
  var owned = {}; PEOPLE.forEach(function (p) { owned[p] = []; });
  itemsInOrder.forEach(function (item) {
    var itemOwners = {};
    all(VOTE_SEL + ', .notefield', item).forEach(function (n) { owners(n).forEach(function (o) { itemOwners[o] = true; }); });
    Object.keys(itemOwners).forEach(function (o) { if (owned[o]) owned[o].push(item); });
  });
  function ownersOfItem(item) { return PEOPLE.filter(function (p) { return owned[p].indexOf(item) !== -1; }); }

  // ── signature / dirty (baseline-vs-current) ──
  function signature(item) {
    if (!item) return '';
    var vals = [];
    all(VOTE_SEL, item).forEach(function (i) {
      if (i.checked) vals.push((i.name || '') + '=' + (i.value || i.getAttribute('data-fb-key') || 'on'));
    });
    all('.notefield', item).forEach(function (t) { var v = (t.value || '').trim(); if (v) vals.push('note=' + v); });
    return vals.sort().join('|');
  }
  function hasSelection(item) { return !!(item && item.querySelector('.vseg input:checked, .fbopt input:checked')); }

  var baseline = new Map(), submitted = {}, subCount = {};
  PEOPLE.forEach(function (p) { submitted[p] = false; subCount[p] = 0; });
  itemsInOrder.forEach(function (item) { baseline.set(item, signature(item)); });
  function dirtyItems(p) { return owned[p].filter(function (item) { return signature(item) !== baseline.get(item); }); }
  function anyDirty() { return PEOPLE.some(function (p) { return dirtyItems(p).length > 0; }); }

  // ── render a person's progress + dirty label + submit state ──
  // EVERY node for a key, never the first one. The bar's submit and the end-of-document mirror
  // are two entry points onto ONE state: they share a data-submit key and there is no second
  // store, so enabling, disabling and re-baselining reach both or the page has lied about which
  // one is live. Same for the dirty label, the progress count and the state chip.
  function renderPerson(p) {
    var n = dirtyItems(p).length;
    var labs = all('.unsaved[data-for="' + p + '"]');
    var btns = all('.submitbtn[data-submit="' + p + '"]');
    var text, cls;
    if (n > 0) { text = n + ' unsaved'; cls = ''; }
    else if (submitted[p]) { text = 'Submitted ✓' + (subCount[p] ? (' ' + subCount[p]) : ''); cls = 'done'; }
    else { text = 'No changes'; cls = 'clean'; }
    labs.forEach(function (lab) {
      lab.classList.remove('done', 'clean');
      if (cls) lab.classList.add(cls);
      lab.textContent = text;
    });
    btns.forEach(function (btn) { btn.disabled = !(n > 0); });

    var total = owned[p].length, decided = owned[p].filter(hasSelection).length;
    all('.cnt[data-prog="' + p + '"]').forEach(function (prog) {
      prog.textContent = decided + '/' + total;
      prog.classList.toggle('full', total > 0 && decided === total);
      var av = prog.closest('.ava'); if (av) av.setAttribute('aria-label', displayName(p) + ' — ' + decided + ' of ' + total + ' items decided');
    });
    all('.idprog[data-prog="' + p + '"] .idprog-n, .idprog-n[data-prog="' + p + '"]').forEach(function (el) {
      el.textContent = decided + '/' + total;
    });

    // The STATE CHIP carries only what this script can honestly know: how many of this person's
    // answers have been posted. Whether the fold has run is the board transport's fact, not
    // ours, so the chip's authored text ("· not folded") is left exactly as the page wrote it.
    all('.idstate[data-state-for="' + p + '"]').forEach(function (chip) {
      var num = chip.querySelector('.idstate-n');
      if (num) num.textContent = subCount[p];
      chip.classList.toggle('is-posted', subCount[p] > 0);
    });
  }
  function renderAll() { PEOPLE.forEach(renderPerson); }
  function onChange(node) { var item = itemOf(node); if (item) ownersOfItem(item).forEach(renderPerson); }

  inputs.forEach(function (inp) { inp.addEventListener('change', function () { onChange(inp); }); });

  // ── note affordance: open/close, has-note state, Revise-nudge ──
  function refreshNoteBtn(aff) {
    if (!aff) return;
    var btn = aff.querySelector('.notebtn'), t = aff.querySelector('.notefield'); if (!btn || !t) return;
    var has = !!t.value.trim();
    aff.classList.toggle('has-note', has);
    if (btn.lastChild && btn.lastChild.nodeType === 3) btn.lastChild.nodeValue = has ? 'Note added' : 'Add a note';
  }
  notes.forEach(function (t) { t.addEventListener('input', function () { refreshNoteBtn(t.closest('.noteaff')); onChange(t); }); });
  all('.notebtn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var aff = btn.closest('.noteaff'); if (!aff) return;
      var wrap = aff.querySelector('.notewrap'); if (!wrap) return;
      var opening = wrap.hasAttribute('hidden');
      if (opening) { wrap.removeAttribute('hidden'); btn.setAttribute('aria-expanded', 'true'); var t = wrap.querySelector('.notefield'); if (t) t.focus(); }
      else { wrap.setAttribute('hidden', ''); btn.setAttribute('aria-expanded', 'false'); }
    });
  });
  function resetNudge(aff) {
    if (!aff) return;
    aff.classList.remove('nudge');
    var t = aff.querySelector('.notefield');
    if (t && !t.getAttribute('data-static-ph')) t.setAttribute('placeholder', 'Optional — add a reason or comment');
  }
  // ── per-decision CONFIRMATION STRIP: reveal on a decision, then skip · clear ──
  // A decision is answered with a confirmation, not with a second demand. The strip is built
  // from the DOM the page already authored (one per `.noteaff`), so no page has to compose it.
  //
  // REVEAL WITHOUT TAKING FOCUS. `.notebtn` focuses the field because opening the note is what
  // the user just asked for; a decision is not that. Focusing on every Approve springs the
  // on-screen keyboard over the answer the user is trying to confirm. The strip's own live
  // region carries the state change instead — which is also the ONLY spoken confirmation on a
  // phone, since the bar's `.unsaved` label is display:none below the 640px container tier.
  function scopeOf(node) { return node ? (node.closest('.decision, .yourcall, .mod-decision') || itemOf(node)) : null; }
  function affOf(scope) { return scope ? scope.querySelector('.noteaff') : null; }
  function stripOf(scope) { var a = affOf(scope); return a ? a.querySelector('.cfmstrip') : null; }

  all('.noteaff').forEach(function (aff) {
    if (aff.querySelector('.cfmstrip')) return;
    var strip = document.createElement('div');
    strip.className = 'cfmstrip'; strip.setAttribute('hidden', '');
    var say = document.createElement('span');
    say.className = 'cfm-say'; say.setAttribute('role', 'status');
    var skip = document.createElement('button');
    skip.className = 'cfm-skip'; skip.type = 'button'; skip.textContent = 'Skip note';
    var clear = document.createElement('button');
    clear.className = 'cfm-clear'; clear.type = 'button';
    clear.innerHTML = '<span class="cfm-ink"><span class="cfm-ux" aria-hidden="true">↺</span>Clear decision</span>';
    strip.appendChild(say); strip.appendChild(skip); strip.appendChild(clear);
    aff.appendChild(strip);
  });

  // What the user just chose, in their own words — the verdict segment, or a single-select's
  // label up to its dash. A multi-select has no single word, and saying one would be a lie.
  function chosenWord(inp) {
    var lab = inp.closest('label'); if (!lab) return 'Selection';
    if (lab.classList.contains('vopt')) {
      var seg = lab.querySelector('span:not(.vcensus):not(.chipx)');
      return (seg && seg.textContent.trim()) || (inp.value || 'Selection');
    }
    if (lab.classList.contains('multi')) return 'Selection';
    var fl = lab.querySelector('.fbopt-label');
    return fl ? fl.textContent.split(/[—–]/)[0].trim() : (inp.value || 'Selection');
  }

  function hideStrip(scope) { var s = stripOf(scope); if (s) s.setAttribute('hidden', ''); }

  function showStrip(scope, word) {
    var strip = stripOf(scope), aff = affOf(scope); if (!strip || !aff) return;
    var wrap = aff.querySelector('.notewrap'), nb = aff.querySelector('.notebtn');
    if (wrap && wrap.hasAttribute('hidden')) { wrap.removeAttribute('hidden'); if (nb) nb.setAttribute('aria-expanded', 'true'); }
    strip.removeAttribute('hidden');
    var clear = strip.querySelector('.cfm-clear');
    if (clear) clear.setAttribute('aria-label', 'Clear decision — removes ' + word);
    // Unhide FIRST, write the text on the next frame: a live region inside a display:none
    // subtree is not in the accessibility tree, so text set in the same tick announces nothing.
    // Only ever written when it CHANGES, which is what keeps one decision to one announcement.
    var say = strip.querySelector('.cfm-say'), msg = word + ' recorded';
    if (say && say.textContent !== msg) {
      requestAnimationFrame(function () { say.textContent = msg; });
    }
    // A decision taken near the fold puts its own confirmation off-screen. `scroll-margin` on
    // .cfmstrip keeps the landing clear of the sticky bar; motion is opt-out, not assumed.
    var box = strip.getBoundingClientRect();
    if (box.bottom > (window.innerHeight || 0)) {
      var still = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      strip.scrollIntoView({ behavior: still ? 'auto' : 'smooth', block: 'nearest' });
    }
  }

  // ── clear a vote — ONE path, two entry points (the chip ×/plate `clear`, and the strip) ──
  function clearInputs(list, scope, focusBack) {
    if (!list.length) return;
    list.forEach(function (i) {
      if (i.type === 'checkbox') { i.checked = false; }
      else { all('input[name="' + i.name + '"]').forEach(function (g) { g.checked = false; }); }
    });
    var sc = scope || scopeOf(list[0]);
    resetNudge(affOf(sc)); hideStrip(sc);
    onChange(list[0]);
    // Focus was on a control that just disappeared, or on a chip that just emptied. Put it back
    // on the decision so the next keystroke re-decides rather than landing nowhere.
    if (focusBack) { var f = sc && sc.querySelector(VOTE_SEL); if (f) f.focus(); }
  }
  function clearFrom(btn) {
    var label = btn.closest('label'); if (!label) return;
    var inp = label.querySelector('input'); if (!inp) return;
    clearInputs([inp], scopeOf(inp), false);
  }
  all('.chipx, .optx').forEach(function (btn) {
    btn.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); clearFrom(btn); });
  });

  all('.cfm-clear').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var sc = scopeOf(btn); if (!sc) return;
      clearInputs(all(VOTE_SEL, sc).filter(function (i) { return i.checked; }), sc, true);
    });
  });
  // SKIP dismisses the strip and records nothing. It closes the note only when the note is
  // empty — a skip must never destroy prose the user already typed. That is the whole
  // difference from Clear, which removes the decision and leaves the prose alone.
  all('.cfm-skip').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var strip = btn.closest('.cfmstrip'), aff = btn.closest('.noteaff'); if (!strip || !aff) return;
      var hadFocus = strip.contains(document.activeElement);
      strip.setAttribute('hidden', '');
      var t = aff.querySelector('.notefield'), wrap = aff.querySelector('.notewrap'), nb = aff.querySelector('.notebtn');
      if (wrap && t && !t.value.trim()) { wrap.setAttribute('hidden', ''); if (nb) nb.setAttribute('aria-expanded', 'false'); }
      if (hadFocus && nb) nb.focus();
    });
  });

  // A decision — any decision, not only Revise — reveals the confirmation. Revise additionally
  // keeps its nudge: it is the one verdict that asks for words, so it says so in the placeholder.
  inputs.forEach(function (inp) {
    inp.addEventListener('change', function () {
      var scope = scopeOf(inp); if (!scope) return;
      var aff = affOf(scope); if (!aff) return;
      var t = aff.querySelector('.notefield');
      if (inp.checked && inp.value === 'revise' && inp.closest('.vseg')) {
        aff.classList.add('nudge');
        if (t) t.setAttribute('placeholder', 'What should change?');
      } else { resetNudge(aff); }
      if (hasSelection(scope)) showStrip(scope, chosenWord(inp)); else hideStrip(scope);
    });
  });

  // ── per-person submit: rebaseline that person's changed items ──
  all('.submitbtn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var p = btn.getAttribute('data-submit'); if (!owned[p]) return;
      var changed = dirtyItems(p);
      changed.forEach(function (item) { baseline.set(item, signature(item)); });
      // cumulative, not per-batch: "3 posted" has to mean three answers are out there, which is
      // the number the state chip and the popover explanation are both talking about.
      submitted[p] = true; subCount[p] += changed.length;
      renderAll();
    });
  });

  // ── acting-as switcher: ATTRIBUTION ONLY ──
  // No check is performed, none is implied. This copies a chosen roundel + name into the bar's
  // identity button and records it as an attribute; it grants nothing and gates nothing.
  all('.idpop-pick[data-act-as]').forEach(function (pick) {
    pick.addEventListener('click', function () {
      var key = pick.getAttribute('data-act-as');
      var btn = document.querySelector('.idme-btn'); if (!btn) return;
      var srcR = pick.querySelector('.roundel'), dstR = btn.querySelector('.roundel');
      var srcN = pick.querySelector('.pn'), dstN = btn.querySelector('.pn');
      if (srcR && dstR) { dstR.textContent = srcR.textContent; dstR.className = srcR.className; }
      if (srcN && dstN) dstN.textContent = srcN.textContent;
      var bar = btn.closest('.idbar'); if (bar) bar.setAttribute('data-acting-as', key);
      var pop = pick.closest('[popover]');
      if (pop && pop.hidePopover) { try { pop.hidePopover(); } catch (e) { /* not open */ } }
    });
  });

  // ── beforeunload guard ──
  window.addEventListener('beforeunload', function (e) {
    if (anyDirty()) { e.preventDefault(); e.returnValue = 'You have unsubmitted decisions'; return e.returnValue; }
  });

  // ── view filter + item stepper (enhances #view-<key> anchors; degrades to all-visible) ──
  function viewKey() {
    var m = (location.hash || '').match(/^#view-(.+)$/);
    return (m && owned[m[1]]) ? m[1] : null;
  }
  var stepIdx = {};
  function applyView() {
    var key = viewKey();
    all('.ava').forEach(function (a) {
      var isActive = key && a.getAttribute('href') === '#view-' + key;
      a.classList.toggle('is-active', !!isActive);
    });
    all('.stepper').forEach(function (s) { s.classList.toggle('is-active', !!(key && s.getAttribute('data-person') === key)); });
    itemsInOrder.forEach(function (item) {
      var dim = key && ownersOfItem(item).indexOf(key) === -1;
      item.classList.toggle('dim', !!dim);
    });
  }
  function step(dir) {
    var key = viewKey(); if (!key) return false;
    var list = owned[key]; if (!list.length) return false;
    var cur = (stepIdx[key] == null) ? (dir > 0 ? -1 : 0) : stepIdx[key];
    var i = (cur + dir + list.length) % list.length;
    stepIdx[key] = i;
    if (list[i]) list[i].scrollIntoView({ behavior: 'smooth', block: 'center' });
    return true;
  }
  all('.stepbtn').forEach(function (b) {
    b.addEventListener('click', function (e) {
      if (viewKey()) { e.preventDefault(); step(parseInt(b.getAttribute('data-step'), 10) || 0); }
    });
  });
  window.addEventListener('hashchange', function () { stepIdx = {}; applyView(); });

  applyView();
  renderAll();
})();
