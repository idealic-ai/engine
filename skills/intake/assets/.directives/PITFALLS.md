# Proof-kit Pitfalls

<!-- Known gotchas and traps. Read before working here. -->
<!-- Each pitfall: ¶PTF_NAME bullet with Context → Trap → Mitigation sub-fields -->

Traps found while building and measuring the WARM PRINT proof kit (`assets/`). Every entry below was
paid for with a real defect: each one shipped, or nearly shipped, with every automated check green.

## Verification & measurement

These are the expensive ones. One wave produced **33 distinct defects — 27 found by looking at the
render, 6 by a check that refused to run.** For each of the 27, *no check existed that could see it*
— which is the claim to make, not "no check happened to fire". The entries here are why.

*   **¶PTF_GREEN_CHECK_ON_A_DESTROYED_PAGE**: A page can be certified and lying at the same time.
    *   **Context**: Any responsive or overflow check on a page whose blocks set `overflow:hidden`.
    *   **Trap**: `body.scrollWidth - body.clientWidth === 0` measured **0 at every width** on two live boards that were simultaneously destroying **234px and 283px** of prose — because an ancestor clips, so nothing reaches the body. The metric certified the exact pages it existed to catch.
    *   **Mitigation**: Assert **the thing the reader loses**, never a condition that usually accompanies it. Check per-element `scrollWidth > clientWidth` on clipping ancestors, starved tracks, and min-content floors *naming the culprit element*. Run both checks; the body-level one alone is worse than none because it grants confidence.

*   **¶PTF_ISOLATION_ERASES_THE_LAYER**: The isolation step removed the thing under test, and every reading came back PASS.
    *   **Context**: Measuring a background/ambient layer by hiding foreground text to sample the ground.
    *   **Trap**: `*{color:transparent}` also erases a `currentColor`-driven ambient layer. Every contrast reading passed — **on a page with no wash at all**. This is the inverse of `§PTF_COLOR_MIX_FLOAT_PARSE`: that one manufactures failures, this manufactures passes, and a pass is never re-examined.
    *   **Mitigation**: Print a control proving the layer *survived* isolation — re-sample a text-free strip in both the isolated and un-isolated render and require pixel identity, plus a distinct-colour count so a flat card can't masquerade as an intact wash.

*   **¶PTF_COLOR_MIX_FLOAT_PARSE**: A naive parser reads any `color-mix()` ground as near-black.
    *   **Context**: Computing contrast from `getComputedStyle()` values in this kit.
    *   **Trap**: `color-mix()` computes to `color(srgb 0.95 0.93 0.87)` in **0–1 floats**, not `rgb(0–255)`. Regexing digits and dividing by 255 turned a real 5.00:1 into 3.64:1, and produced phantom failures down to **1.31:1**. `.mod-head`, `.mod-foot` and several catalog grounds are all `color-mix()`.
    *   **Mitigation**: Print a parser control before any ratio — the same ground in `color-mix()`, hex and `color(srgb …)` spellings must yield one number. Refuse to report if they disagree.

*   **¶PTF_CLIP_IS_DOCUMENT_RELATIVE**: Screenshots of the wrong region, correctly sized, every check green.
    *   **Context**: Cropping a headless-Chrome screenshot to an element.
    *   **Trap**: Puppeteer's `clip` is **document-relative**; `getBoundingClientRect()` is **viewport-relative**. Feeding one to the other yields files that exist, are the right dimensions, and show the wrong part of the page — proving nothing while looking like evidence.
    *   **Mitigation**: Add `window.scrollX/scrollY` when converting, or screenshot the element handle directly. Open the PNG before citing it.

*   **¶PTF_DPR2_DOUBLES_THE_SCREENSHOT**: A working layout looks broken because the image is 2×.
    *   **Context**: Reading widths off a rendered PNG.
    *   **Trap**: At `deviceScaleFactor: 2` an entry measuring 985 CSS px renders 1970 image px. One agent nearly "fixed" a correct layout off this.
    *   **Mitigation**: Measure in the DOM, not in the image. Use images to *see* defects, never to size them.

*   **¶PTF_FIXED_PSEUDOS_BAND_THE_CROP**: Every clipped screenshot of a kit page comes out banded.
    *   **Context**: Cropping any page carrying the kit's page-level chrome.
    *   **Trap**: `body::before` / `body::after` are `position:fixed`, so a clipped capture repeats them at `viewportHeight − sectionTop` — which reads as a page defect and isn't one.
    *   **Mitigation**: Pin them `absolute` for capture, or capture full-page and crop afterwards.

*   **¶PTF_SCALE_INVARIANT_METRIC**: The metric certified a set that is illegible at the size it ships.
    *   **Context**: Choosing how many distinct shapes/marks a small mark can carry.
    *   **Trap**: Filled-shape IoU is nearly scale-invariant — hexagon↔octagon scored **0.094 at 10px and 0.104 at 24px** — and would have approved an 8-shape set in which four shapes are *one shape* at rail size (boundary separation 0.38–0.95px against the 1px of ink that draws them).
    *   **Mitigation**: Any legibility metric must have the render size in it. Compare boundary separation against stroke width at the **target** size, then verify by eye at 1:1.

*   **¶PTF_ALLOWLIST_IS_AN_UNCHECKED_PROMISE**: The exemption and the defect are one fact written twice.
    *   **Context**: Any check that skips a case because the page declares itself the good kind — an allowlist of "declared scrollers", "intentional" clips, known-wide tables.
    *   **Trap**: An allowlist entry is not an observation, it is a **promise that the hidden content is reachable**, and an exemption is the one construct that guarantees the promise is never tested. Generally: **a check whose scope is narrowed by a property the defect itself supplies is not a check.** One such allowlist sat *inside the sentence describing the mitigation*, in a file citing `¶PTF_GREEN_CHECK_ON_A_DESTROYED_PAGE` by name three lines above. Deleting it immediately found **six declared scrollers hiding 28.6–49.7% of their content at 390 — all six failing, three not keyboard-reachable at all.**
    *   **Mitigation**: **Never exempt, measure more.** Where a scroller actually hides something, demand four things of it: **P1 it moves** — set `scrollLeft` past the end and read it back; *a container that does not move is a clip wearing a scroller's class name* · **P2 keyboard-operable** · **P3 no clipping ancestor** · **P4 an authored cue painted at that viewport.** An entry that cannot pass all four is a defect, not an exemption.

## Layout & CSS

*   **¶PTF_1FR_FLOORS_AT_MIN_CONTENT**: The mobile collapse fires and cannot help.
    *   **Context**: A grid track holding prose plus any unbreakable atom (a ticket chip, `file:line`, a version string).
    *   **Trap**: `1fr` is `minmax(auto,1fr)` and cannot go below the content's min-content width. A `.cpv` track computed **545.812px inside a 312px box**, clipping 234px of prose — with the `@media` collapse *firing correctly*. No per-breakpoint bake fixes this; a baked variant emits the identical track.
    *   **Mitigation**: `minmax(0,1fr)` on the track **and** `min-width:0` on the child. See `§PTF_MIN_WIDTH_AND_MAX_WIDTH_ARE_A_PAIR`.

*   **¶PTF_MIN_WIDTH_AND_MAX_WIDTH_ARE_A_PAIR**: Half the fix looks like no fix.
    *   **Context**: Releasing a starved grid/flex track.
    *   **Trap**: `min-width:0` frees the **track**; `max-width:100%` on the inline atom makes the **chip** yield. Applying only one leaves the symptom intact and the diagnosis looking wrong.
    *   **Mitigation**: Both, or neither works. Note `overflow-wrap:anywhere` cannot break `white-space:nowrap` — an unbreakable atom stays unbreakable.

*   **¶PTF_MEDIA_ADDS_NO_SPECIFICITY**: A mobile rule that never applies.
    *   **Context**: Adding a `@media` collapse over an existing rule.
    *   **Trap**: `@media` contributes **zero** specificity, so `.mod-body > .cpv` (0,2,0) beats `@media{.cpv}` (0,1,0) at every width. A live sweep found 18 defeat pairs per page. The rule reads correct and is dead.
    *   **Mitigation**: A rung's selector must match or exceed the strongest un-queried rule on the same property. Verify by computed style at the target width, not by reading.

*   **¶PTF_ANYWHERE_NOT_BREAK_WORD**: The solvent that doesn't dissolve anything.
    *   **Context**: Letting long strings shrink a content-sized track.
    *   **Trap**: Per CSS Text, breaks from `overflow-wrap:anywhere` **are** counted in min-content intrinsic sizing; breaks from `break-word` are **not**. In a content-sized track only `anywhere` actually shrinks it — `break-word` wraps visually and leaves the track wide.
    *   **Mitigation**: `overflow-wrap:anywhere` for solvents. `break-word` is not a synonym.

*   **¶PTF_ELLIPSIS_INERT_ON_FLEX_ITEM**: A declared `text-overflow` that never fires.
    *   **Context**: A chip or label that slices mid-word instead of ellipsizing.
    *   **Trap**: `text-overflow` never applies to a flex item's own overflow. `.idstate{display:inline-flex}` carried `text-overflow:ellipsis` and cut its label mid-word — **`labelCutPx: 100`, identical at every width**, i.e. on desktop too, not a mobile defect at all.
    *   **Mitigation**: `display:inline-block` makes the existing declaration work. And remember CSS can wrap, hide, scroll or ellipsize text but **cannot shorten it** — a short form must be authored.

*   **¶PTF_SIBLING_MARGIN_IN_A_GRID**: Block-flow spacing leaks onto grid children, and `stretch` does not fix it.
    *   **Context**: A grid whose children also carry an adjacent-sibling margin from a stacked context.
    *   **Trap**: `.spec + .spec{margin-top:18px}` put the first card of every row 18px proud. The obvious fix is wrong: **`align-items:stretch` fills the *margin box***, so the other cards keep the offset and come out 18px shorter — bottoms flush, tops and heights still unequal, and the page looks fixed.
    *   **Mitigation**: Spacing between grid children belongs to `gap`, never a sibling margin. Fold the margin into the row gap (`gap: (rowGap+margin) colGap`) and zero the sibling rule so nothing moves.

*   **¶PTF_BOX_SIZING_SKIPS_PSEUDOS**: `*` does not mean every box.
    *   **Context**: Sizing a `::before`/`::after` band or rule.
    *   **Trap**: `*{box-sizing:border-box}` does **not** reach pseudo-elements. A band declared 18px rendered 28px and slid onto its label — visible only at 4× zoom.
    *   **Mitigation**: Include `*::before, *::after` in the reset, or set `box-sizing` on the pseudo itself.

*   **¶PTF_AFTER_PAINTS_OVER_CHILDREN**: The mask covered the thing it was masking.
    *   **Context**: Using `::after` as an overlay on an element that has children.
    *   **Trap**: `::after` paints **after** the element's children, so an overlay intended to shape a fill covered it instead — collapsing nine shapes × five fills to identical marks, with every element present, correctly sized, and every check green.
    *   **Mitigation**: Use `::before` with the child raised, or `mask-image` on the element. Verify by eye — this class of defect is invisible to structural assertions.

*   **¶PTF_FAMILY_SCOPED_SNIPPET**: Lifting the documented snippet yields unstyled markup.
    *   **Context**: Copying a creative pattern out of `CREATIVE_LAYOUTS.html`, as its own masthead instructs.
    *   **Trap**: `proof-creative.css` is **entirely family-scoped** — 591 `.fam-` selectors across six families; `.odiff` has *zero* standalone rules. Paste the snippet without its `.fam-*` wrapper and nothing applies. This is the leading suspect for why most of the 25 patterns have never been used.
    *   **Mitigation**: Copy the family wrapper with the snippet, or un-scope the pattern. Either way, say which — a snippet that silently renders unstyled teaches an author the pattern is broken.
