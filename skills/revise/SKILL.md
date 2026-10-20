---
name: revise
description: "Take one landed change and make the documentation's CLAIMS about it true again. A claim-scoped documentation block: it locates every sentence in the docs that asserts something about what this change touched, rules each claim true / falsified / unverifiable against the code with a control, dispatches a writer sub-agent to repair only the falsified ones, and returns a structured Revise Report. Dispatchable as a lane — it owns one diff, never the tree. Triggers: \"the docs now lie about this\", \"patch the docs for this change\", \"revise the claims this thread falsified\", \"doc the landed thread\", \"what do the docs say about X and is it still true\"."
version: 1.0
tier: lightweight
args: "[<change descriptor | build-report path | git range | file set>] [-- <claim-scope override>]"
---

Repair the documentation claims one change falsified. You are handed a landed change — a thread's Build Report, a git range, or a file set — and your job is narrow: find what the docs **say** about what that change touched, rule each statement against the code, and repair the statements that are now false.

A **building block**, and the lightweight sibling of `/document`: it takes a scoped change, assembles a self-contained context pack, dispatches a writer lane, and returns a structured **Revise Report**. It owns no session, runs in the background, and several can run at once over disjoint doc sets. `/document` is protocol-tier — a whole session with phases, a plan, a debrief and a synthesis pipeline — so a conductor cannot fan it out per thread. This is the piece that fans out.

## What this owns, and what it is forbidden to do

**Owns**: one change's claim surface. A *claim* is one located sentence — path, line, the words — asserting something a reader could check against the code. The job is to rule it and, when it is false, make it true.

**Forbidden here, and the reason in each case** — route each to `/document` instead:
- **Index and table-of-contents reconciliation** (`docs/TOC.md` and its kin). A diff cannot scope an index: the index's correctness is a property of the whole tree, so a lane holding one diff would either guess or never finish.
- **Sweeping for stale pages this change did not touch.** A page nothing in the diff reaches is not this lane's finding, however wrong it looks — pick it up and the lane's scope is the tree again.
- **Auditing counts, cross-references or link health across the tree.** Same reason: the subject is the tree, not the change.
- **Giving an undocumented change a home.** Where a new page or section belongs is a structural decision about the tree. A change with no existing claim about it yields a register row and an escalation — never a page this lane invents.

Each of these leaves as a **register row** in the Revise Report's `## Register rows owed`, naming the work and its destination. Writing the row is the whole of this lane's duty toward it.

**Also forbidden**: editing a claim that is still true. A claim the change did not falsify is left byte-for-byte, and the report names it as left standing so the next lane does not re-check it. Rewording true prose is how a doc lane produces a diff nobody can review.

# /revise Protocol

## 1. Anchor the change

Resolve **what changed** — in order of preference, because each is more authoritative than the next:
1. A thread's Build Report `## Files touched (authoritative)` list, which is the in-scope set its own builder declared.
2. An explicit file set in the args.
3. A git range, read with `git diff --stat <range>` and `git show`. Never `git stash`/`checkout`/`restore` to get a baseline — read the committed side with `git show <rev>:<path>` (`§INV_NO_DESTRUCTIVE_GIT`).

Then resolve **what changed about it** — not the file list but the *subjects*: the behaviours, contracts, defaults, thresholds, names and file locations a reader could have been told. A rename and a threshold change falsify different sentences.

**Establish TRACKED before reading any path's state as clean.** `git status --porcelain` on an untracked path prints nothing and exits 0 whatever it holds, so run `git ls-files --error-unmatch <path>` first. An untracked doc cannot be diffed against anything and its "before" is not recoverable — say so in the report rather than implying a baseline.

**Resolve the trail.** `<trailDir> = <sessionDir>/builds/` from the active session; the slug is the thread's own where there is one, so the trail clusters under one name. Echo one line: `Revising <change> — subjects: <…>; doc scope: <…>; chunk: <CHUNK>; trail: <trailDir>.`

## 2. Build the claim inventory (the differentiator)

This is the step that makes the lane worth dispatching: **a list of located sentences, each with a verdict**, rather than a list of files to look at.

Search the documentation for the subjects, not the filenames — a page that describes a default by its behaviour never mentions the file that implements it. Sweep the project's documentation roots, the `.directives/` files, the skills' own text where the change is in a skill, and any runbook the change's commands appear in.

For each hit, record a claim: **path:line · the sentence · what it asserts · verdict · the measurement.**

- **true** — leave it. Name it in the report.
- **falsified** — the change made this sentence wrong. This is the work.
- **unverifiable** — the sentence asserts something no command here can check. Say which command would, and row it; never upgrade it to true because it looks plausible.

**Every verdict is an instrument reading before it is a fact.** A zero carries a positive control **in the same invocation** — and a control term the document itself documents cannot be a negative control for that document, so pick a token the file does not contain. `grep -c` counts lines, not occurrences; use `grep -o | wc -l` when the number is occurrences and say which one produced it. `git grep -E` is POSIX ERE with no `\b`, `\s`, `\d` or `\w`, and those escapes match nothing while exiting as though the pattern were absent. zsh does not word-split an unquoted `$VAR`, so a file list in a variable arrives as one filename and returns a clean zero per term.

**A pattern that matches what both versions share cannot tell them apart.** When you check whether a claim is still true, match the thing that is structurally new, not the vocabulary common to the old sentence and the new behaviour.

**Counts are a claim class of their own.** A sentence stating a count — *"the three positions"*, *"both halves"* — is falsified by any change to the set, and correcting the number buys one more edit next time. Replace the count with the named members and let the reader count.

## 3. Dispatch the reviser

Spawn one `writer` sub-agent, **background by default** (`run_in_background: true`), its `description` leading with the thread's bracketed id where this runs inside a loom. The prompt is self-contained — the lane cannot see your context:

> You are repairing documentation claims one landed change falsified. Repair only the claims listed. Do not sweep, do not reword what is true, do not create pages.
>
> - **The change:** `<subjects + authoritative file list>`
> - **The claims to repair:** `<path:line · sentence · what it asserts · what is now true instead>` — each one, with the new fact stated.
> - **Claims ruled still true (do NOT touch):** `<list>` — these are settled; editing one is a defect.
> - **Out of bounds:** the tree's index/TOC, pages this change does not reach, count audits, and creating a new page or section for anything undocumented. Report those back; do not act on them.
> - **The stale twin (`¶INV_REVISE_FIX_THE_SECOND_COPY`):** a page holds a second copy of its own claims — an overview paragraph, a scope block, a summary table, a frontmatter `description`. After editing a claim, re-read those parts of **the same file** and fix the twin. A skill's `description` frontmatter is the first thing a model reads and is the twin most often missed. This is in scope; the tree's index is not.
> - **Git safety (`§INV_NO_DESTRUCTIVE_GIT`):** the tree is dirty with parallel work. No `stash`, `checkout`/`switch`/`restore` of paths, `reset --hard`, `clean`, `rm`, `add -A`/`-u`/`.`. Read a committed version with `git show <rev>:<path>`. Do not commit.
> - **Progress log:** `<the concrete absolute `engine log <path>` command>` — appended every few tool calls. An `engine log` with a RELATIVE path writes to a different sessions root, silently, at exit 0, so the path is absolute.
> - **Return contract:** write your report to `<trailDir>/<CHUNK>_REVISE.md` from `assets/TEMPLATE_REVISE_REPORT.md` (the orchestrator gives you this skill's base dir; do not hardcode a home path), filling every field — including `## Claims left standing`, `## Stale twins checked` and `## Register rows owed`, which are the fields the next lane reads. Then return a short summary and the report path.
> - **Escalate rather than invent:** a claim whose new truth you cannot establish, a change with no claim about it anywhere, or a repair that would require a new page — stop on that item, keep the rest, and report it.

## 4. Intake and the authority check

Read the report. **Re-rule a sample of the verdicts yourself**, re-running the exact commands the report lists — a verdict is the whole product here, so taking it on faith leaves the lane unverified. Re-run every `unverifiable` and every `true` on a claim the change plainly touched: those are the two verdicts that hide work.

Then check what a writer lane most often gets wrong:
- **Did a true claim get edited?** Diff the touched docs against the claim inventory; an edit outside the falsified set is a scope breach and is reverted by editing it back, never by `git checkout`.
- **Is the stale twin actually fixed?** Open the edited file's own overview, scope block and frontmatter and read them. A claim repaired in the body while the summary still carries the old version reads as though the page were checked.

Relay the verdict counts with their denominators, the files touched, and the register rows owed. Link the report.

## Constraints & invariants

- **`¶INV_REVISE_IS_CLAIM_SCOPED`**: a doc is edited only against a named, located claim this change falsified. No file is "updated" because it looked stale — forbidden because a lane allowed one unlocated edit has the whole tree in scope again, which is the job this block exists to not do.
- **`¶INV_REVISE_LEAVES_TRUE_CLAIMS_ALONE`**: a claim ruled true is left byte-for-byte and named in the report. Rewording true prose produces a diff a reviewer cannot separate from a repair.
- **`¶INV_REVISE_FIX_THE_SECOND_COPY`**: a page holds a second copy of its own claims in its overview, scope block, summary and frontmatter `description`; after a repair those are re-read in the same file. In scope; the tree's index is not.
- **`¶INV_REVISE_NEVER_HOUSES_THE_UNDOCUMENTED`**: a change nothing documents yields a register row and an escalation, never a page this lane invents — where a page belongs is a decision about the tree, and `/document` owns the tree.
- **`¶INV_REVISE_EVERY_VERDICT_CARRIES_ITS_INSTRUMENT`**: a verdict states the command that produced it and the control run in the same invocation. An `unverifiable` naming the command that would settle it is a result; a plausible `true` is not.
- **`§INV_A_PROBE_WRITES_ITS_ANSWER_DOWN`**: the Revise Report is written even on a blocked or partial run. A claim inventory that dies with a lane's context is the expensive loss — it is most of the work.
- **`§INV_NO_DESTRUCTIVE_GIT`**: neither the orchestrator nor the writer runs tree/index-destructive git. Committing is `/snapshot`'s job.
- **No commit, no tracker write, no code change.** This block edits documentation and reports. A code defect it finds is a register row.
