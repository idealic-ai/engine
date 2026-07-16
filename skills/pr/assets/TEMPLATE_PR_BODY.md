# PR Body Template — <slug>
*The PR-writer subagent (`/pr` §2) fills this and WRITES the rendered body to `<trailDir>/<slug>_PR.md`. This file IS exactly what posts to GitHub (minus the Claude Code trailer, which the orchestrator appends at creation).*

*CRITICAL INSTRUCTIONS FOR SUBAGENT:*
*- **Context-Maxed:** Draw the "why" sections from the `builds/` trail (critiques, decisions, verdicts), not just the diff. The trail's *content* is distilled INTO this body — never link local `builds/` paths (the reviewer reads this on GitHub and cannot open session-local files).*
*- **Always-On Sections:** Must render every time.*
*- **Include-If-Present Sections:** Render ONLY if you have real content. Do not write "None" or "N/A" — just omit the section entirely.*
*- **No Hallucinations:** Do NOT include a commit SHA you haven't verified. NEVER claim a verification or test was run if it is not explicitly present in the trail.*
*- **NEVER write a bare `#<number>`.** GitHub autolinks `#1` to issue/PR #1 **in this repo** and renders it as that issue's **title** — so an acceptance item you wrote as "`#1` — alerts no longer labeled production" silently posts as "**Invite flow** #1 — alerts no longer labeled production", splicing an unrelated PR's name into your sentence. This has already happened in a real PR. It applies EVERYWHERE in the body (acceptance items, reviewer notes, risks), not just checklists. To enumerate, use `A1`/`A2` or `1.`/`2.` — never `#1`. Write `#N` **only** when you genuinely mean to reference that GitHub issue/PR. Same trap: bare `GH-123` and `org/repo#123` also autolink. If you must show a literal one, backtick it (`` `#1` `` renders as code and does not autolink). Linear keys (`FIN-3141`) are unaffected — they carry no `#`.*
*- **Adapt the Examples:** The blockquotes below are illustrative examples. Adapt them to the actual PR data; do not copy them literally.*

---

## Summary  — ALWAYS
*What this PR does + why it matters, written in a few tight lines that a reviewer reads first.*
> *(Illustrative — adapt, don't copy)*
> Migrates the estimate reconcile/matching core to read flat room entities on the now value-identical stable join key, and completes the `ScopeNanoid→RoomNanoid` rename. **Why:** removes the last `scope` readers from the reconcile spine, unblocking the scope-retirement chunks — safe now that the identity-model fix made the flat join key value-identical.

## Linked ticket + acceptance  — ALWAYS
*`Closes` the primary ticket (auto-detected), and `Relates to` any others the user kept. Pull the ticket's acceptance signals in as a checklist for the reviewer. **Fallback:** If there is NO linked ticket, render exactly "No linked ticket — drafted from commits/diff" and omit the checklist entirely (never leave an empty `Closes`).*
*If you label the items, use `A1`/`A2` — **never** `#1`/`#2`, which GitHub rewrites into unrelated PR titles (see CRITICAL INSTRUCTIONS above).*
> *(Illustrative — adapt, don't copy)*
> **Closes** FIN-2849 · **Relates to** FIN-2737
> ### Acceptance
> - [ ] **A1** — Reconcile/matching core reads flat room entities on the stable join key; parity proven against the **real assembler** (not the `projectScopesToFlat` oracle)
> - [ ] **A2** — `ScopeNanoid→RoomNanoid` rename complete (incl. `apps/web`); persisted `anchorId`/`anchorSideIds` unchanged
> - [ ] **A3** — `@finch/estimate` green; `tsc --noEmit` 0

## Changes  — ALWAYS
*What changed, grouped logically by area or package (derived from the diff + commits). Provide enough structure for a reviewer to navigate the PR, but avoid a literal, exhaustive file-by-file dump.*
> *(Illustrative — adapt, don't copy)*
> - `packages/estimate/{matching,canonical,combine,resolution}/` — reader-swap: scope entities → flat room entities on the shared nanoid key
> - `packages/estimate/.../recap-by-room.ts` — reconcile helpers re-pointed to flat
> - `apps/web/...` — `ScopeNanoid → RoomNanoid` type + local rename (no persisted-field change)

## Verification / testing  — ALWAYS
*What was actually RUN and the results, sourced strictly from the trail/snapshot reports. NEVER claim a gate was passed if you lack evidence in the trail. If you didn't run it, explicitly state: "Build + lint: left to CI".*
> *(Illustrative — adapt, don't copy)*
> - `cd packages/estimate && npx tsc --noEmit` → exit 0
> - `yarn workspace @finch/estimate test` → 304 suites green / 9 pre-existing skips
> - Identity/join parity proven against the real assembler (`flat-identity.test.ts`, 9/9) — not the blind projection oracle
> - Build + lint: left to CI

## Decisions & rationale  — ALWAYS
*The "why" that a diff cannot show — key architectural choices and reasoning, drawn from the critiques/trail. This is the core context-max payload. **Fallback:** When the trail is thin (e.g., standalone mode), keep this to a single honest line (e.g., "Standard refactor, no notable architectural decisions.") — do not manufacture content.*
> *(Illustrative — adapt, don't copy)*
> - Reader-swap only after the identity-model fix made `heading.nanoid == scope.nanoid` — before that the swap would have silently re-keyed rooms/items (the `@finch/estimate` suite is blind to it because the projection oracle copies `scope.nanoid` onto flats).
> - No data migration: durable identity (`claim_room_member.scopeNanoid`) is already scope-equal, so the in-memory change converges with storage.

## Risks / watch-outs  — ALWAYS
*Done-but-watch: latent hazards, assumptions, or areas needing careful review. **Fallback:** If the trail is thin, write a single honest line (e.g., "No notable risks identified.") — do not pad.*
> *(Illustrative — adapt, don't copy)*
> - The value-identity holds only in the no-scope end state; do not emit headings into a doc that still carries live scopes through `overlay()` (cross-entity nanoid collision) — the cutover avoids it, but flag at merge.
> - FE comparison-renderer nanoid resolution wasn't exhaustively audited — worth a reviewer eye.

## ⚠ CI gates triggered  — ALWAYS
*Special gates this diff trips. Flag the required action so CI doesn't surprise the reviewer. `/pr` flags these; it does not run them. Render "None detected" only if truly none.*
> *(Illustrative — adapt, don't copy)*
> - **None detected** — no Layer-4 normalizer, classifier-replay-watchlist, classifier-schema, or new-migration changes in this diff.
> *(Alternative Examples when present)*
> - Touches `normalizeAddressForMatch` → **Layer-4 `rule_version` bump required**.
> - New migration `apps/api/drizzle/0234_*.sql` → **needs a `_journal.json` entry**.

## Out-of-scope / followups  — INCLUDE IF PRESENT
*What this PR deliberately does NOT do, and any filed followup tickets.*
> *(Illustrative — adapt, don't copy)*
> - Chunk 6 (retire `fireOnRawScope`/`mergeContinuations`) and chunk 7 (schema flip) — separate slices.
> - Combine-decision-producer boundary — open question tracked on FIN-2849.

## Branch note  — INCLUDE IF PRESENT
*Render ONLY for a focused cherry-pick PR: explain how this branch relates to the shared source.*
> *(Illustrative — adapt, don't copy)*
> Focused PR: cherry-picked 3 of 11 commits for FIN-2849 off shared branch `fin-2712-deterministic-feature-metric-detection`.

## Alternatives considered  — INCLUDE IF PRESENT
*The architectural roads NOT taken and why. This pre-empts the reviewer's "why didn't you just do X?" and proves the design space was explored. Drawn from the trail's decisions.*
> *(Illustrative — adapt, don't copy)*
> Considered a data migration to rewrite all stored `anchorId`s to the new flat identities. Rejected: heavier and riskier than unifying the nanoid in the assembler first — the migration becomes unnecessary once the join key is value-identical.

## Reviewer focus areas  — INCLUDE IF PRESENT
*Direct the reviewer's limited attention: point out the most complex, risky, or controversial files/logic to look at closely, and explicitly state what can be safely skimmed. This saves time and catches real risk.*
> *(Illustrative — adapt, don't copy)*
> Look closely at `attributeTablesToRooms` in `identity.ts` — the doc-order attribution is load-bearing for item parenting. The `matching/item-reconciliation.ts` bucket-key swap is the other hot spot. The `apps/web` rename is purely mechanical — skim it.

## Screenshots / notes  — INCLUDE IF PRESENT
*UI diffs, before/after, or any note that helps the reviewer. Omit for non-UI.*

<!-- The orchestrator appends the trailer at create time: 🤖 Generated with [Claude Code](https://claude.com/claude-code) — do NOT add it here. -->

---

## Outcome *(stamped by the orchestrator after §3)*
<`→ opened <draft|ready> PR <url>` on branch `<branch>` → `<base>`; closes <PREFIX>-NNNN; gates: <flags>>
