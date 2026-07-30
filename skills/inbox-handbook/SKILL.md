---
name: inbox-handbook
description: "Manage the intake projects' Inbox Handbook documents — the per-project guides whose `## What triage will chase` section IS the triage recipe. Four modes: show (fetch a handbook or just its recipe), capture (turn what a session learned into a Keep/Add/Cut proposal dropped into 🟦 Documentation), reconcile (diff the five hand-synced copies and repair drift), audit (check a handbook's claims against Linear). The read/repair companion to /inbox-post, which only drops items in. Triggers: \"show me the triage recipe\", \"what does the handbook say\", \"the recipe was wrong\", \"capture what we learned into the handbook\", \"are the handbooks out of sync\", \"inbox-handbook\"."
version: 1.0
tier: lightweight
args: "[show|capture|reconcile|audit] [project] [--recipe]"
---

Keeps the intake handbooks **true** — readable when you need them, corrected when a run proves them wrong, and consistent across their copies.

# /inbox-handbook Protocol (The Handbook Keeper)

[!!!] This is a **sessionless utility** skill. No session directory, no logging, no debrief — same pattern as `/inbox-post`, `/session`, `/engine`. Its one exception: `capture` writes its trail into the *active* session's `builds/` when one exists.

## The single job

A handbook is only worth having if a person can find it, trust it, and fix it. Every mode serves one of those: **show** makes it findable at the moment of use, **capture** and **audit** make it trustworthy, **reconcile** keeps its copies from quietly disagreeing. If a proposed feature doesn't serve one of the three, it doesn't belong here.

## What it does (and does not)

*   **It does**: read, propose corrections to, reconcile, and audit the per-project **Inbox Handbook** Linear Documents.
*   **It does NOT**: create handbooks (`/intake` owns channel and handbook creation), drop inbox items (`/inbox-post`), promote anything to a tracked ticket (`/intake`'s ripeness gate), or edit engine directives (`§CMD_MANAGE_DIRECTIVES` owns `¶INV_*` and `¶PTF_*`).

## The surface

Five intake projects each carry **their own complete copy**, attached to the project so it appears in that project's sidebar, all titled `Inbox Handbook — how this project's intake inboxes work`. **There is no parent document and no inheritance** — a team-level copy existed, was found to have no home in the Linear UI (nothing surfaces it from a project), and was retired. Do not propose re-creating it.

Each handbook has a stable skeleton:

*   **Shared sections** — commonly Dropping something · The channels · 📋 Report template · What happens next · How a comment becomes a ticket · The intake projects, kept in sync **by hand** across the copies. **Treat that as an observation, not a fixed list**: the section SET itself drifts. A real example — the Intake System handbook carries a `## Data handling` section (standing rules, dated attributions, mirrored from the project description precisely because a dispatched sub-agent cannot read the project) that Differ's copy does not have at all. Derive the sections from the documents, never from a hardcoded list.
*   **`## What triage will chase`** — the **recipe**, and the only genuinely per-project section: it names the tools that identify a subject in *that* project (Temporal for Differ, the staging DB + PostHog for Email Classification). Divergence here is **correct, not drift**. `reconcile` never touches it; only `capture` proposes changes to it.

Most recipes follow an `Identify → Reproduce → Relate → Report` skeleton. Treat that skeleton as load-bearing: a correction branches a step, it does not reverse one.

## Reference assets (read at boot)

*   **`~/.claude/engine/skills/inbox-post/assets/INBOX_REGISTRY.md`** — the shared cache, co-owned with `/inbox-post`. Its `## The handbook` section maps every project to its handbook **doc id + slugId**; the per-project sections map the 🟦 Documentation channel ticket this skill posts to. **Resolve by doc id**, cross-check the slugId, and never parse the human-readable URL words — retitling a document re-slugs those while the 12-hex slugId stays put. On a miss, fall back to discovery (`list_documents(query: "Inbox Handbook")`, or `list_projects(includeMilestones: true)` client-filtered to projects with an `Inboxes` milestone) and **self-heal** the registry, exactly as `/inbox-post` does. The registry is a cache; Linear is the source of truth.

## Modes

Infer the mode from the args and the context. If it is genuinely ambiguous, resolve it with ONE `AskUserQuestion` (`§CMD_ASK_QUESTION_WITH_COMPLETE_CONTEXT`) — never guess between a read and a write.

### `show` — read a handbook (read-only)

1.  Resolve the project (explicit arg → active `/intake` session's project → working context → ask).
2.  Resolve the doc id from the registry; `get_document(id)`.
3.  Render the whole handbook, or with `--recipe`, only `## What triage will chase`.
4.  If that section is absent (a young project), say so plainly — that is a finding, not an error, and it is worth surfacing before someone triages without a recipe.

**Use it before the work, not after.** A recipe read at the start of a triage is the difference between following it and reconstructing it.

### `capture` — session learnings → a Keep/Add/Cut proposal

Invoked directly, or by `§CMD_OFFER_HANDBOOK_CAPTURE` at a skill's synthesis.

1.  **Fetch the recipe the session actually followed** (`show --recipe`). Without it there is nothing to measure against, and the output degrades into generic advice.
2.  **Fill the seven buckets** of `assets/TEMPLATE_FRICTION_LOG.md` from the session's own evidence — log, DIALOGUE, `builds/`, the commands actually run. Every line must be traceable to something that happened; **no speculative recipe advice**.
3.  **Reduce to a Keep/Add/Cut delta** (`assets/TEMPLATE_RECIPE_DELTA.md`). This is the payload — buckets 1–6 are its evidence, bucket 7 is the proposal. A capture that reports friction without a delta is not applicable and should not be posted.
    *   **Keep is not politeness.** Naming what was right is what stops the next editor cutting the parts that are working.
    *   **Cut is mandatory, not optional.** The delta must state its net effect on handbook length, and a handbook that only ever grows stops being read.
4.  **Write the trail** to the active session's `builds/` (`§CMD_LINK_FILE`). If there is no active session, write nothing to disk and present the delta in chat.
5.  **Post** the delta as a comment to that project's 🟦 **Documentation** channel via `§CMD_POST_TICKET_COMMENT`. Reference tickets with `§FMT_TICKET_LINK` and specific comments with `§FMT_TICKET_COMMENT_LINK`.
6.  **Cross-project learnings go to the current project's handbook only**, with their breadth flagged in the proposal ("this likely applies to the other four"). **Never fan out** — a human decides whether one learning becomes five edits.

**Direct handbook edit is an escalation, not the default.** Offer it as an explicit per-run confirm after the delta exists and the user has seen it; the default door is the Documentation drop, because the intake system's own rule is that it proposes and a human confirms.

### `reconcile` — diff the copies, repair drift (writes on one confirm)

1.  Fetch all five handbooks and **derive each one's section set from its own headings**. Do not diff against a remembered list of sections — the set is one of the things that drifts.
2.  Report **set-level drift first**: sections present in some copies and absent in others. This is the failure mode a within-section diff cannot see, and it is the more consequential one — an absent section means a reader of that copy never learns the thing at all. A section that appears in only one copy is **not automatically a gap to fill**: it may be deliberately project-specific, like the recipe. Surface it for a human call; never auto-propagate a section.
3.  Then diff the **shared sections** copy-to-copy. Exclude `## What triage will chase` and state that you excluded it — a reader who sees five different recipes in a "drift" report will not trust the rest. Report per section: which copies agree, which lag, what the difference is. **Zero drift is a valid result** — say "in sync" and write nothing.
4.  Ask the user to designate the source-of-truth copy, and confirm **once**, having shown the diff.
5.  Write only the sections that actually differ, only to the copies that lag, via `save_document`. **Before each write, verify the fetched document's `project.name` matches the intended project** — a stale registry row must never redirect a write.
6.  Capture each target's pre-edit content into the session trail (or chat, if sessionless) so a manual revert is possible without Linear's history.

This is the highest-blast-radius action in the skill: up to four document writes on one confirm. The diff-then-single-confirm shape is deliberate — routing a mechanical sync through five review queues creates five chances to apply it differently, which re-creates the drift it was repairing.

### `audit` — check a handbook against reality (read-only)

For one project or all five, verify what the handbook and registry claim:

*   Every channel ticket referenced still resolves, and its title still matches its channel.
*   No channel description still links the **retired** team-level handbook slug `7f5f9c302585` — if one does, it should be repointed at its own project's handbook.
*   The handbook's channel list matches the project's actual `Inboxes` milestone (the set is contextual per project — a project may not have all eight, and that is correct).
*   Registry rows agree with Linear; self-heal the ones that don't.

Report findings; propose fixes through the normal doors. `audit` never writes a handbook itself.

## Write-policy matrix

*   **`show`, `audit`** — read-only. The registry self-heal is the only write, and it is local.
*   **`capture`** — proposes into 🟦 Documentation. Direct handbook edit only on an explicit per-run confirm.
*   **`reconcile`** — diff first, one confirm, then direct writes to lagging copies. Shared sections only.

## Constraints

*   **Never invent handbook inheritance.** A parent document was tried and retired for a measured reason. If a problem seems to need one, that is a signal to state the tradeoff, not to build it.
*   **Never flatten `## What triage will chase`** into one generic recipe across projects. It names the tools that work in *that* project.
*   **Evidence-backed only** — every proposed line traces to something that actually happened in a run.
*   **`¶INV_QUESTION_GATE_OVER_TEXT_GATE`**: mode disambiguation, the capture triage, the reconcile confirm, and the direct-edit escalation are all `AskUserQuestion`.
*   **`¶INV_LISTS_INSTEAD_OF_TABLES`** in everything this skill writes.

## Keeping the registry fresh

`/intake` owns handbook and channel creation; this skill **consumes and repairs** the map it shares with `/inbox-post`. When a project or handbook changes, the discovery fallback keeps this skill correct and rewrites the affected rows. Never copy the registry into this skill's own assets — a second cache of the same project identity is the duplication problem one level down.
