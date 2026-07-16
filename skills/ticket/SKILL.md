---
name: ticket
description: "Turn in-context work into one OR MORE well-framed tickets. A background agent analyzes the scope and drafts PREMISE-FIRST issues (problem, intent/why, constraints, non-goals, acceptance signals — NOT an algorithm), you calibrate each via questions, then it posts to Linear as a sub-issue of the current ticket (inheriting labels/assignee/project/team/cycle) or a new issue — chosen from context. Triggers: \"file a ticket\", \"make tickets\", \"open an issue for this\", \"ticket this up\", \"capture this as a ticket\", \"split this into tickets\"."
version: 1.0
tier: lightweight
args: "[<what to ticket / scope descriptor>] [-- <intent / framing override>]"
---

Translate a body of in-context work into one or more well-framed tickets. A background agent analyzes the scope, drafts PREMISE-FIRST tickets (the problem, the intent, the constraints, the non-goals, the acceptance signals — deliberately NOT a prescribed algorithm or solution), you calibrate each draft via questions, then it posts to the tracker. Sessionless: no session dir, no phases, no debrief — analyze → draft → calibrate → post, then stop. A **building block**: it drafts and files tickets from work; it never writes code, fixes bugs, or commits. When this run follows a `/build` or `/experiment`, it reuses that run's `<slug>` so the tickets cluster beside that work's report, and it feeds `LESSONS.md` so the tickets you file shape the next handoff.

This is distinct from just calling the tracker MCP directly. It front-loads a **premise-first draft** derived from actual work (so the ticket captures *why* and *what*, not a half-baked solution), runs an interactive **per-ticket calibration gate** (you own title, scope, labels, and placement), and makes the **sub-issue-vs-new** decision from context — inheriting the parent's metadata when it files under an existing ticket.

### Execution Mode: Engine vs. Standalone
Before proceeding, determine your environment. You are running under the workflow engine **if and only if `COMMANDS.md`** (the engine's core command standards, containing `§CMD_*` / `§INV_*` definitions) **is preloaded in your context** (the SessionStart hook injects it). This single check dictates every fallback below:
- **Engine Mode (`COMMANDS.md` present):** Active session. Use `engine log`, `<sessionDir>`, and `<trailDir> = <sessionDir>/builds/`. Draw scope/intent from the session's `DIALOGUE.md`, plan, and log. The `§CMD_*` references (e.g., `§CMD_WALK_THROUGH_RESULTS`) resolve to their engine definitions.
- **Standalone Mode (`COMMANDS.md` absent):** No session (teammate without the engine). Use the global `/tmp` trail dir and plain file appends (defined in §5). Draw scope/intent from the conversation and args. Treat every `§CMD_*`/`§FMT_*` reference as plain-English guidance (the surrounding prose describes the behavior: the calibration walk-through and the batch-confirm gate are spelled out in §3–§4). **Standalone limitations:** No session-slug parent source (parent detection falls back to branch + conversation only) and no session log/plan/`builds/` trail. Grounding comes from the git diff and the conversation digest the orchestrator inlines; expect thinner context.

**Tracker Note (Linear):**
This project files to **Linear**, via the `linear-server` MCP tools (`list_teams`, `list_issue_labels`, `list_issue_statuses`, `get_issue`, `list_issues`, `save_issue`) — the tracker and its tool set are constant; only the **issue-key prefix** and **team** vary per project and come from CLAUDE.md § Tracker (resolve them in §1, inject into the subagent prompt). Tickets use that prefix — `<PREFIX>-NNNN` (finch: `FIN`, so keys look like `FIN-3141`). `save_issue` both creates and updates. On create, it takes **human names/identifiers, not UUIDs** — `team`, `parentId` (accepts `"<PREFIX>-NNNN"` directly), `labels` (label NAMES), `assignee` (name/email/`"me"`), `project`, `cycle`, `state`, `priority` (int), `title`, `description` (Markdown). There is no separate ID-resolution step. Load tool schemas on demand (ToolSearch `linear`). If no Linear MCP is connected, degrade gracefully: draft and calibrate as usual, then hand the user the finalized ticket bodies in chat to copy-paste, noting that posting was skipped.

# /ticket Protocol

## 1. Scope & Goal

Establish the two anchors the run depends on: **what work** the ticket(s) come from, and **the intent** behind it.

**Resolve the tracker config (do this first):** Read CLAUDE.md's `## Tracker` block (the orchestrator sees CLAUDE.md; the subagent will NOT, so you must resolve here and inject in §2). Resolve: the **issue-key prefix** — `<PREFIX>` uppercase for keys (`<PREFIX>-NNNN`) and its lowercase form for branches (`<prefix>-NNNN-…`) — and the **team**. Finch's block gives prefix `FIN` / team `Finchclaims`. **Fallback — no `## Tracker` block** (unconfigured project, or standalone mode): keep today's behavior — detect a `FIN`-style key (an uppercase-alpha prefix + `-NNNN`) from the branch/slug/conversation at lower confidence. The config is never a hard requirement; absent it, degrade to detection, don't error.

**Scope** — the body of work to turn into ticket(s). Resolve from args, else infer and confirm:
- *(bare)* / a descriptor → the active session's log/plan/`DIALOGUE.md` (the current chunk / what we just did), else the recent conversation.
- `diff` → the uncommitted working-tree diff (`git status` + `git diff`) — ticket the change or the follow-ups it implies.
- `session` → the work described in the active session's artifacts.
- text after `--` → an intent/framing override (what these tickets are really *for*).
*If scope is ambiguous, present the candidates via `AskUserQuestion`.*

**Detect the context ticket** (drives placement in §3): Scan for a parent key `<PREFIX>-NNNN` (prefix from § Tracker) in the **session slug** (finch example, prefix=FIN: `2026_07_02_FIN_2737_...` → `FIN-2737`), the **git branch** (lowercase prefix: `<prefix>-2712-...` → `<PREFIX>-2712`), or the conversation. Standalone (no engine) has no session slug, so detection falls back to branch + conversation only — lower confidence, so lean harder on the §3 pick. Call `get_issue` now to resolve enough to display the parent's **title · state · team** at placement (and to read its labels/project/cycle for inheritance in §4). Note the confidence: a **branch-derived** key that contradicts a **slug-derived** key, or a parent that is **Done/Canceled/archived**, is a low-confidence CANDIDATE, not a default — §3 forces a pick in that case.

**Resolve the trail** (used in §2/§5): `<trailDir> = <sessionDir>/builds/` under an engine session, else `${TMPDIR:-/tmp}/finch-build-trail/<repo-basename>/` (`mkdir -p`). Pick a `<slug>` once — a short kebab-case string of the scope (e.g., `identity-model-fix`, `recap-flat-followups`). If this run follows a `/build` or `/experiment`, reuse that run's slug so the tickets sit beside its report. Otherwise, before minting a fresh slug, `ls <trailDir>` — if an existing `<slug>_*.md` clearly matches this work (same chunk / ticket / topic), REUSE that slug so the trail clusters under one name; only mint a new one for genuinely new work.

**Echo back in one line:** `Ticketing <scope> — intent: <intent>; context ticket: <<PREFIX>-NNNN "title" · state · team | none>; trail: <trailDir>/<slug>_TICKETS.md.`

## 2. Draft — Spawn the Drafting Agent (Background)

**Backgroundable & parallelizable.** This sub-agent dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working while it runs, and when the work splits into independent chunks, several such sub-agents can be fanned out in parallel and reconciled.

Spawn **one** background agent (a `general-purpose`/`analyzer`) to analyze the scope and draft the ticket(s). It does the heavy reading and framing; you keep the thread for calibration. Build its prompt so it is entirely self-contained. Use the exact prompt structure below:

> **System Prompt for Drafter:**
> You are drafting one or more **premise-first** tickets from a body of work. Your goal is to orient the future builder to the PROBLEM and its terrain, not to provide a line-by-line map. Point at the **general areas / modules** involved (dirs, file-groups — never an exhaustive path/line dump, which rots immediately), define "done" by observable **outcome**, and name the traps you already see. You cannot know everything up front and shouldn't pretend to — the implementor discovers the specifics. Your job is to bound the problem sharply and flag the landmines. Analyze the scope; do NOT write code or file anything.
>
> **Inputs:**
> - **Tracker config (resolved from CLAUDE.md § Tracker — the orchestrator fills these; you cannot read CLAUDE.md):** Linear (linear-server MCP) · issue-key prefix `<PREFIX>` (keys `<PREFIX>-NNNN`, branches `<prefix>-NNNN`) · team `<team>`. Use this prefix wherever a key/placement appears; do NOT assume `FIN`.
> - **Intent (what this work is for):** `<intent>`
> - **Scope to analyze:** `<scope + concrete pointers: session artifacts / git diff cmd / files / conversation digest>`
> - **Read for context:** `<session log / plan / build report / relevant modules>`
>
> **Rules of Engagement:**
> - **Decompose conservatively (SINGLE ticket by default).** Draft ONE coherent ticket unless the work has genuinely independent deliverables. **Split heuristic:** split only when the work touches **two decoupled systems that are deployable/assignable independently** (e.g., a schema migration AND a separate frontend surface that ship on their own cadence) — otherwise ONE ticket, one premise. Never inflate the count; the user merges/splits at calibration.
> - **PREMISE-FIRST, not a solution.** Each ticket states the PROBLEM and its BOUNDARIES, not how to code it. Fill the template fields (`assets/TEMPLATE_TICKET_DRAFT.md`) meticulously; the terse roster and its load-bearing nuances: `title` (crisp, outcome-oriented) · `type` (bug/feature/chore/tech-debt/spike — maps to a label, drives the rest) · `premise/problem` (grounded in the work) · `intent/why now` · `evidence/grounding` — **the anti-solutioning field** (general areas/modules + observed symptom + provenance; a representative pointer or two, NOT an exhaustive `file:line` dump that rots) · `constraints` · `non-goals` · `acceptance signals` (observable outcomes, not an algorithm) · `implementation traps` (conceptual "you'll be tempted to X, don't, because Y" — not a path dump) · `escalation triggers` — **the specific conditions under which the builder should STOP and return to the user** rather than guessing · `reproduction` (bugs only) · `open questions/unknowns` (incl. a split not taken) · `dependencies` (by DRAFT #: `blocked-by #2`/`blocks #3`/`relates-to #2`) · `suggested priority + labels` — labels are **SUGGESTED only, to be reconciled against the real team label set at §4.1** — the drafter doesn't know the team yet · `proposed placement`. Do NOT prescribe an implementation/algorithm; if the work implies one, note it as a brief optional "possible direction" at most (dropped from the filed ticket unless the user explicitly keeps it).
> - **Spike escape-hatch.** If the scope is fundamentally a research task with no genuine acceptance criteria yet, do NOT fabricate constraints/acceptance to fill the form — force **Type = `spike`** and heavily populate **Open questions / unknowns** instead, with acceptance framed as "the questions are answered."
> - **Return contract:** WRITE the draft(s) to `<trailDir>/<slug>_TICKETS.md` using the Ticket Draft template (this skill's `assets/TEMPLATE_TICKET_DRAFT.md` — the orchestrator gives you its path; do not hardcode `~/.claude`), one block per ticket. Per ticket, ALSO render the final postable `description` Markdown — the exact body `save_issue` will receive — into that ticket's block under a clearly-labeled **"Rendered description (postable)"** slot: the premise-first fields as `## Premise` / `## Intent` / `## Constraints` / `## Non-goals` / `## Acceptance` sections plus the Evidence/grounding and (bugs only) Reproduction headers, all already rendered, with any "possible direction" already **EXCLUDED unless the user flagged it to keep**. Render it complete and ready-to-post — §4 lifts this block VERBATIM. Then return a 3–5 line summary to the orchestrator: how many tickets, each title, and the proposed placement.

Prefer background execution (`run_in_background: true`) so the user can keep working; relay the summary when it lands. For a tiny, obvious single-ticket scope, you MAY draft inline instead of spawning — state this in one line if you do.

## 3. Calibrate — Walk the Drafts with the User

The interactive **calibration gate is the core of `/ticket`** — the user, not the model, finalizes each ticket before anything is posted. Run it explicitly; never post a draft as-is. Under the engine, this is `§CMD_WALK_THROUGH_RESULTS`; **standalone, run the routine below directly with `AskUserQuestion`**.

1. **Granularity Gate (One `AskUserQuestion`):** "How do you want to walk the N draft ticket(s)?"
   - **Each** (one at a time)
   - **Groups** (batches of ≤4)
   - **Accept all as drafted** (skip straight to the post gate).
   *Note: For a single ticket, skip this step and go straight to its calibration.*

2. **Per Ticket (or group of ≤4) — Context Block + `AskUserQuestion`:**
   First, present a 2-part context block in chat (`§FMT_CONTEXT_BLOCK`):
   - Line 1: `[#]: <title> — proposed placement`
   - Line 2: The premise + the acceptance signals + suggested priority/labels.
   Then, use `AskUserQuestion` (`header` = ticket number) with this option tree:
   - **Approve:** Take the draft as-is into the post set.
   - **Edit:** Adjust title / premise / scope / acceptance / priority / labels. Capture the change, re-show the finalized block.
   - **Split:** This should be N tickets; define the split (each gets its own premise).
   - **Merge:** Fold into another draft (name which).
   - **Drop:** Don't file this one.

3. **Placement Per Ticket:** For each ticket kept, confirm placement (this is the one decision `/ticket` makes from context, but the user always confirms it explicitly). **Echo the resolved parent** (`<PREFIX>-NNNN "title" · state · team`, from the §1 `get_issue`) so the decision shows what is being nested under:
   - **Detected parent, high confidence** (`<PREFIX>-NNNN`, open, same team as the target) → Default to **sub-issue** of it. Inherit **labels + assignee + team + project + cycle**; `title / premise / priority` stay per-ticket. Show the inherited set so the user can prune.
   - **Low-confidence parent** (branch-derived key ≠ slug-derived key, or parent is Done/Canceled/archived, or a different team) → Treat it as a **CANDIDATE, not a default**. Surface the candidate(s) **plus "new top-level"** via `AskUserQuestion` and **force a pick** — never silently nest.
   - **No parent detected** → Default to **new top-level issue**, baseline **status = Backlog, unassigned, no priority**. When the scope suggests sensible **labels / project** (from the work area, related issues, or the context ticket even if not a strict parent), **offer to apply them** — don't silently blank them, and don't force them.
   - **Sanity check:** Any parent must be **open** (not Done/Canceled/archived) and **on the same team** as the target before defaulting to sub-issue. If either fails, drop to the candidate branch above.

4. **Batch Shortcuts:** Honor these immediately. If the user says "all as sub-issues of `<PREFIX>-N`" or "drop the last one," apply it and move on. **"Approve all" is content-only** — it takes every draft's title/premise/fields as-is into the post set but does **NOT** decide placement; placement stays an explicit per-ticket confirm (and is re-confirmed at the §4 batch gate).

After the walk, assemble the **post set**: each finalized ticket with its resolved placement + fields. If nothing survives, report that and stop.

## 4. Post — To Linear (Single Batch Confirm)

Reconcile, dedup, confirm once, then create — and wire dependencies in a second pass. `save_issue` takes **human names/identifiers, not UUIDs**; there is no ID-resolution dance.

1. **Reconcile + Dedup** (the team is now known from §3 placement):
   - **Labels:** Pull the real team label set (`list_issue_labels`, team-scoped) and reconcile each ticket's SUGGESTED labels against it. Keep matches; **drop or flag any label not in the set** (surface the drop so the user can create it or pick another). The drafter never knew the team, so this is where suggested labels become real ones.
   - **Dedup:** Before building the create calls, run `list_issues` (`query` = the draft's title keywords, scoped to the target `team`) for each draft. If a plausible existing match turns up, hold it — you will surface it at the batch confirm (step 3) as **"possible duplicate of `<PREFIX>-NNNN`"**.

2. **Build one `save_issue` per ticket** — the real field shape:
   ```javascript
   save_issue({ team, parentId: "<PREFIX>-NNNN", title, description, priority, state, labels: [names], assignee, project, cycle })
   ```
   - **Sub-issue:** Set `parentId: "<PREFIX>-NNNN"` (the resolved-prefix identifier directly — no ID lookup) + the inherited `team` / `labels` / `assignee` / `project` / `cycle` (read off the parent via `get_issue`, used ONLY to copy those values), with the per-ticket `title`, `description`, and `priority`.
   - **New top-level:** Set `team` + the calibrated fields. **Pass `state: "backlog"`** — prefer the state **TYPE** `"backlog"` (robust if a team renamed its backlog status) so the issue actually lands in Backlog rather than the team default (which is Triage when enabled); if unsure the team has one, verify via `list_issue_statuses`.
   - **Map priority:** Word → int: None→0, Urgent→1, High→2, Medium→3, Low→4.
   - **`description` is Markdown:** **LIFT the drafter's "Rendered description (postable)" block VERBATIM** from `<trailDir>/<slug>_TICKETS.md` into `save_issue({ description })`. The drafter already rendered the premise-first body (section headers `## Premise` / `## Intent` / `## Constraints` / `## Non-goals` / `## Acceptance` + Evidence/grounding + any bug Reproduction, **"possible direction" excluded unless the user flagged it to keep**); the orchestrator does NOT re-render it. Apply only the edits the user made at calibration (§3) to that block before lifting.
   - **Dependencies:** Cross-ticket dependencies stay unset here (the sibling has no `<PREFIX>-NNNN` yet) — they are wired in step 4.

3. **Single Batch Confirm (`AskUserQuestion`, MANDATORY):** Posting is outward-facing and hard to undo. First, render the **full per-ticket set in a chat block** above the question. For each ticket, show: title, placement (`sub-issue of <PREFIX>-NNNN` | `new in <team>`), priority, labels, assignee, any **"possible duplicate of `<PREFIX>-NNNN`"** flag from step 1, and any **evidence to attach** (screenshots/artifacts — see below).
   Then ask **"Post all N to Linear?"** with options: **Post all / Edit one first / Cancel**.
   - On a flagged duplicate, offer **file anyway / skip / update instead** for that ticket.
   - On **"Edit one first"**, ask a follow-up `AskUserQuestion` for the ticket number, loop to that ticket's §3 calibration, then **re-present the full confirm**.
   - Only on **Post all** do you create.

4. **Create + Wire + Capture:** Run the `save_issue` create calls, collect each new issue's **identifier (`<PREFIX>-NNNN`) + URL**.
   **Then, second pass:** If any draft declared a cross-ticket dependency (by draft #), run a second `save_issue` per edge — map draft # → the newly-returned `<PREFIX>-NNNN` and set `blockedBy` / `blocks` / `relatedTo` (these are append-only and accept identifiers). If a create fails, report which and stop (don't retry blindly).

5. **Attach ready evidence (opt-in, after create):** If — and ONLY if — the agent already has supporting evidence **in hand from this run**, attach it to the matching filed issue. Qualifying: **screenshots / images** the agent captured (UI screenshots, overlay or diagram images, a chart) and **well-made standalone artifacts** that materially support the ticket (an evidence doc, an important report, a writeup — e.g. from `/writeup`, `/analyze`, or a design doc). **Do NOT attach internal session process artifacts** — session debriefs, `*_LOG.md`, `DIALOGUE.md`, plan files, or the build-trail reports (`*_BUILD.md`/`*_TICKETS.md` etc.) — and **never fabricate or generate a screenshot** just to have one; attach only what genuinely already exists. Attach via the Linear attachment flow to each ticket's `issueId` (`prepare_attachment_upload` → upload the bytes → `create_attachment_from_upload` for a local file; or `create_attachment` for a URL — load schemas via ToolSearch `linear`). Attaching is outward-facing, so the exact attachment set is shown in the step-3 batch confirm and nothing uploads without that approval; best-effort — an attach failure is reported, it does not abort the filed tickets.

## 5. Report

Summarize in chat: what was filed (each `<PREFIX>-NNNN` + URL + placement), what was dropped/merged, and any create that failed. Link the drafts trail (`§CMD_LINK_FILE`, or just state the path when standalone).

**Paper Trail** (Engine-optional): Update `<trailDir>/<slug>_TICKETS.md` — mark each draft with its outcome (`→ filed <PREFIX>-NNNN <url>` / `merged into #` / `dropped`). Append across the run so a killed/resumed run keeps the record.

**Feed the Ledger** (Compounding memory, same as `/build`+`/scrutinize`): Append the durable outcome to `<trailDir>/LESSONS.md` — one terse bullet: what was filed, the identifiers, and any framing decision worth carrying (e.g., *"Split the cutover into `<PREFIX>-A` identity + `<PREFIX>-B` reader-swap; `<PREFIX>-B` blocked on `<PREFIX>-A`"*). Under a session use `engine log`, else `printf … >> <trailDir>/LESSONS.md`. The next `/build`/`/scrutinize` reads these, so the tickets you filed shape the next handoff. Do NOT commit anything.

## Constraints
- **Premise, not algorithm.** Every ticket states the problem + boundaries + acceptance, never a prescribed implementation. If the work implies a solution, it's an optional one-liner at most — the ticket must survive a different approach.
- **Single by default.** Draft one coherent ticket unless the work genuinely splits (two decoupled, independently deployable/assignable systems); the user raises the count, the skill never inflates it.
- **The user owns every ticket.** The drafter proposes; title, scope, labels, placement, and the decision to file are all the user's via `AskUserQuestion`. Never post an un-calibrated draft.
- **Placement is context-driven, always confirmable.** A high-confidence parent (open, same team) → sub-issue inheriting labels+assignee+team+project+cycle; a low-confidence one → an explicit candidate pick, never a silent default; no parent → new issue posted with `state: "backlog"` (the baseline is *enforced*, not assumed — omitting `state` lets Linear fall to the team default), offering inferred labels/project. Placement is never swept up by "approve all"; the user confirms it explicitly and overrides either way.
- **One batch confirm before posting.** Posting is outward-facing and hard to undo — a single explicit confirm of the whole set is mandatory; there is no auto-post.
- **Paper trail always** (engine-optional). The drafts + outcomes persist to `<trailDir>/<slug>_TICKETS.md` and feed `LESSONS.md`, mirroring `/build`+`/scrutinize` — unless truly standalone with no tracker, where it degrades to chat-only.
- **Attach ready evidence, not process artifacts.** When the agent already has supporting screenshots/images or a well-made standalone artifact (evidence doc, important report, writeup) in hand, attach it to the filed issue (under the batch confirm, best-effort). NEVER attach session debriefs/logs/plans/build-trail files, and never fabricate a screenshot to fill the slot.
- **Sessionless + read-only on code.** `/ticket` owns no session dir and changes no code — it reads work and writes tickets. No commit unless the user asks.
- **Graceful without the tracker.** No Linear MCP → still draft + calibrate, hand over the finalized bodies to paste, note posting was skipped.
