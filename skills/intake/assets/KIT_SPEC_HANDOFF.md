# Retired

`KIT_SPEC_HANDOFF.md` is retired. It specified a page's reproducibility record — 25 numbered rules
for a `data-handoff` block — and **that machine was never built**. `grep -rao 'data-handoff'
idea-cli/` returns 0. The word `handoff` occurs once in the whole CLI, in a prose line of
`lib/cli.ts`. 74,486 B of contract with no enforcement anywhere.

Nothing superseded it, and that is the honest statement: the subject is unowned, not moved.

**Falsifier**: if a handoff record ever ships, this document is *un-retired* rather than rewritten —
its rules were never wrong, only unimplemented. The body is kept verbatim for that reason.

**Its own census was wrong**: line 5 announced "Twenty-one numbered rules"; the file had 25.

**Its `fullPage` ceiling was wrong in both halves** — it restated `~7,900 CSS px` three times. The
real ceiling is **16,384** (`idea-cli/lib/shots.ts:67`) and the failure is **silent**: `capturedH ==
docH`, right dimensions, wrong pixels. See `KIT_SPEC_CHECKING.md` rule 9, which is corrected.

Body, verbatim: **`_attic/D11_RETIRED_KIT_SPEC_HANDOFF.md.txt`**.
