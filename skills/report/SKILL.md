---
name: report
description: "Get back into the flow of a session in one glance. A read-only ORIENTATION report — not what-did-we-do-and-was-it-good (that's /summarize) but where do things stand RIGHT NOW: what work was done, where the branch is (git), where the ticket stands (Linear), what's blocked on YOUR decision, and what's next. The orchestrator writes its own live bearings, then a subagent scans the raw transcript JSONL (dropping read-noise, KEEPING every decision/state-bearing call — AskUserQuestion, Skill/Task, plan-accept, commit/ticket/PR), reconstructs the state BLIND, flags stale narrative artifacts, and reconciles against the bearings, transcript-authoritative. Reuses /graph to render the work trajectory (only when it actually branches) — phases, divergences, snapshots, milestones, plan completion, where you are now, what's upcoming — then walks you through every open thread. Saved to builds/ by default; degrades gracefully (no ticket/plan/thin transcript → report whatever exists). Dual audience: a human returning cold, and the agent itself getting its bearings. A building block: it orients and reports, never touches code/git/ticket content. Triggers: \"/report\", \"where are we\", \"where do things stand\", \"what's the state of this session\", \"get me back in the flow\", \"orient me\", \"where did we leave off — on STATE, not on what-we-did\", \"I'm lost — catch me up on the state\"."
version: 1.0
tier: lightweight
args: "[-- <what you most want re-oriented on>]"
---

Get back into the flow of a session in one glance. `/report` is the **present-tense orientation** sibling of the workflow family. Where `/summarize` reports *backward* (what did we do, was it good, interrogate it) and `/session status` prints thin mechanical state (`.state.json` phase, lifecycle), `/report` answers the question you actually have when you return to a window cold: **"where do things stand right now, what's waiting on me, and what's next?"** — with a rendered state graph.

It is read-only (`¶INV_REPORT_READ_ONLY`) and sessionless, and runs *within* the active session: locate the transcript → write the orchestrator's own bearings → spawn a transcript-scanning subagent (file handoff to `builds/`) → reconcile → graph → render → walk the open threads → save. `<trailDir> = <sessionDir>/builds/`.

**Dual audience.** The report serves two readers at once: a **human** returning after a break (or after `/clear` — the session persists and is reactivated), and the **agent itself** re-establishing its bearings. Both need the same thing — the current state, grounded in what actually happened, not a hopeful summary.

**Hard boundaries.** Not `/summarize` (never reviews work *quality*, runs the inverse-ask palette, or dwells on the past beyond what establishes the present). Not `/snapshot` (never commits, posts to a ticket, or re-runs a gate). Not `/session` (a rich re-orientation, not a state dump). A bug or risk it notices is an open-thread line item, not a repair.

# /report Protocol

## 1. Locate the transcript & resolve targets

Establish the ground-truth sources, degrading gracefully (`¶INV_REPORT_GRACEFUL`) — a missing source narrows the report, never aborts it.

- **The active session** (`<sessionDir>`): its `*_LOG.md`, plan (if present), `DIALOGUE.md`, and `builds/`.
- **The raw transcript JSONL** (`<transcript>`) — the subagent's primary source (§3). Resolve it **deterministically** from the session id Claude Code exports (`¶INV_REPORT_TRANSCRIPT_IDENTITY`) — never by newest-mtime, which under multiple open windows returns a *sibling* window's file:
  ```bash
  SLUG=$(pwd | sed 's#[/.]#-#g')                       # Claude slugifies cwd: / and . -> -
  TRANSCRIPT="$HOME/.claude/projects/$SLUG/${CLAUDE_CODE_SESSION_ID}.jsonl"
  # Fallback ONLY if the env var is unset or the file is missing:
  if [ -z "$CLAUDE_CODE_SESSION_ID" ] || [ ! -f "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(ls -t "$HOME/.claude/projects/$SLUG"/*.jsonl 2>/dev/null | head -1)
    # Mechanical verify: the tail must contain THIS session's dir, else it's the wrong window.
    tail -c 20000 "$TRANSCRIPT" 2>/dev/null | grep -q "$(basename "$sessionDir")" || TRANSCRIPT=""
  fi
  ```
  If `<transcript>` ends up empty, the subagent falls back to `DIALOGUE.md` + `*_LOG.md` (already tool-call-free) — thinner, but never a hard fail, and never the wrong window's transcript. The orchestrator resolves the path and passes the substituted absolute path to the subagent.
- **The ticket(s)** — derive the Linear key from the session's `tickets[]` (`.state.json`) or the branch name (`fin-2833-…` → `FIN-2833`). Read-only. **Sanity-check relevance**: a branch-derived key may be unrelated to this session's actual work (e.g. an engine-tooling session on a feature branch) — flag low-relevance rather than presenting it as *the* ticket. No key → skip the section.
- **Git — the repo(s) the work actually landed in** (`¶INV_REPORT_GIT_FOLLOWS_WORK`). Do NOT assume cwd-git is the work's repo. Report cwd git, AND any other repo the session actually modified (e.g. an engine/skill session edits `~/.claude/engine` — a *separate* repo; cwd-git is then unrelated). For each: branch, dirty-file count, last commit; ahead/behind vs base **only if** an upstream/base is set (guard it). Use `git log --oneline -n 10` (safe on young branches — never `HEAD~10..` which errors under 10 commits).

**Echo one line:** `Orienting on <session "<slug>"> — transcript <id|fallback>, ticket <KEY(rel?)|none>, work-repo <path>. Building bearings…`

## 2. Orchestrator's own bearings

Write down what **you** (the orchestrator) currently believe the state to be, from your own in-context memory. Do it now so it's captured — but it is a **hypothesis to be checked**, not the answer (`¶INV_REPORT_RECONCILE`). Keep it tight (you hand it to the subagent in §3): the goal as you understand it, what you think was just done, what you believe is pending, and — honestly — where you're **unsure** or may have lost the thread. On a cold start with little context, say so plainly; the transcript scan then carries the load.

## 3. Spawn the transcript-scanning subagent (file handoff)

> **Before dispatching — `§CMD_LOG_SKILL_INVOCATION`**: log this dispatch to the session log (why + context-pack pointer + one-line re-tread) so a restarted session can re-tread it. Fire it as the last step before the `Task`/`Agent` handoff.

Spawn **one** subagent (`general-purpose` or `analyzer`) to reconstruct the state from `<transcript>`. **File handoff** (`¶INV_REPORT_FILE_HANDOFF`): it WRITES its full digest to `<trailDir>/REPORT_DIGEST.md` and RETURNS only a 6–10 line summary — keeping the orchestrator lean and leaving a durable artifact beside the other `builds/` files. Run it **foreground** (§4–§8 need it).

**Guard:** if neither `<transcript>` nor `DIALOGUE.md`/`*_LOG.md` exists, skip the subagent — the orchestrator does git + ticket directly.

Construct a fully self-contained prompt:

> **ROLE:** You are a **session cartographer**. Reconstruct the TRUE current state of a work session from its raw transcript. You READ and RECONSTRUCT; you never mutate, commit, post, fix, or re-run a gate.
>
> **PRIMARY SOURCE — the raw transcript:** Read `<transcript>` (JSONL, one message/line). **Filter as you read (`¶INV_REPORT_TRANSCRIPT_FILTER`)** — the cut line is *decision/state-bearing* vs *read-noise*, NOT "only AskUserQuestion":
> - **KEEP** every `user` text message and every `assistant` text block (reasoning, plans, claims).
> - **KEEP, unfiltered, all decision/state-bearing tool calls + results**: `AskUserQuestion` (both sides — the decision record), `Skill`/`Task` invocation headers (name + one-line input + one-line result — these are the major moves: `/build`, `/snapshot`, `/experiment`, `/ticket`, `/pr`), `ExitPlanMode` (plan acceptance), and any commit/ticket/PR-producing call + its result (`git commit`, linear `save_*`, `gh pr create` → the SHAs / keys / URLs the narrating text often omits).
> - **DROP** read/inspection noise: `Read`, `Grep`, `Glob`, read-only `Bash`, and `engine log` appends. Note *that* such work happened from surrounding text; don't ingest the payloads.
> - If `<transcript>` is absent/empty, fall back to `DIALOGUE.md` + `*_LOG.md` and say so.
>
> **RECONSTRUCT BLIND FIRST (`¶INV_REPORT_RECONCILE`):** Derive your State line, Work-done, Pending, Open-threads, and Graph-inputs from the transcript **before** you read the orchestrator's bearings. Do not read the bearings block below until your independent reconstruction is written. This prevents anchoring on a possibly-wrong narrative.
>
> **STALENESS CHECK (always run — `¶INV_REPORT_STALENESS`):** Compare the mtime of every *narrative* artifact (the debrief and other non-log `*.md`, the plan, and — if fetched — the ticket/PR body) against the timestamp of the last substantive log entry / commit. **Flag any narrative artifact that predates the last real work as stale** (`stat -f %m` on macOS). "Artifact X was written before verdict/work Y" is consistently the single highest-value finding — surface each stale artifact in Open threads, and in Reconciliation deltas when it changes the state read.
>
> **ALSO READ (state, not narrative), read-only:** git for **every repo the work touched** (cwd, and e.g. `~/.claude/engine` for engine work — label which holds this session's work and whether committed) — `git -C <repo> status --porcelain` + `git -C <repo> log --oneline -n 10`; the plan file's `[x]`/`[ ]` **if one exists** (many skills have none — skip silently); the Linear ticket via MCP **only if** a relevant key is given.
>
> **THEN — and only then — read the orchestrator's bearings and diff:**
> `<paste the §2 bearings note verbatim>`
> Where the transcript contradicts or outruns the bearings, the transcript wins; capture each mismatch in the deltas section.
>
> **WRITE the full digest to `<trailDir>/REPORT_DIGEST.md`** with these sections, then RETURN a 6–10 line summary (state line + the headline finding + counts):
> 1. **State line** — one sentence: where the work stands right now.
> 2. **Work done** — 3–6 substantive things, most recent first.
> 3. **Git state** — per repo, labeled; which holds this session's work; committed or not.
> 4. **Ticket state** — status + most relevant point, or "none / branch-derived <KEY> (unrelated)".
> 5. **Pending on the user** — decisions/questions explicitly awaiting the human (mine unresolved AskUserQuestion exchanges + direct asks).
> 6. **What's next** — immediate next actions, ordered.
> 7. **Open threads / dangling** — unanswered questions, `#needs-*` tags, deferred items, stale artifacts, "come back to X" — each with a one-line disposition hint.
> 8. **Graph inputs** — ordered trajectory nodes (milestones, phase/branch divergences, snapshots=commits, decision points, plan steps) each marked done/current/upcoming; AND a one-word verdict `branches` | `linear` on whether the trajectory actually forks (drives §5's gate).
> 9. **Reconciliation deltas** — where your (transcript-first) reconstruction differs from the bearings, including any stale-artifact corrections.

## 4. Reconcile & assemble

Read `<trailDir>/REPORT_DIGEST.md`. The subagent's transcript-first reconstruction is authoritative on facts; your §2 bearings contribute only *unstated intent* (what you were about to do) — never override a transcript fact with a bearing. Surfacing a reconciliation delta (§3.9) is often the single most useful line for an agent that had lost the thread.

## 5. Render the flowgraph — reuse /graph, gated on real structure

**Gate first** (`¶INV_VISUALIZE_STRUCTURE_WITH_GRAPH`): render a flowgraph only when the trajectory actually **branches / loops / diverges** (digest §8 verdict = `branches`). If it's `linear` or thin (degraded path → a flat commit list), **skip the graph** — the ordered "What's next" list is clearer; a flowgraph of `1→2→3` is noise.

When it does branch, invoke `/graph` **inline** via the Skill tool (tell it to render **once**, no revision prompt) over the digest's graph-inputs, as a **trajectory graph** in the `§CMD_FLOWGRAPH` Status & Trajectory vocabulary — never freehand glyphs (`§INV_VISUALIZE_STRUCTURE_WITH_GRAPH`):
- done → `✓`; upcoming → `○`; dropped/cancelled → `✗`; stale → `⚠` (pairs with the staleness check);
- current position → `◄ HERE` (exactly once); snapshots → `▣ <sha>`; pivots → `╰► ⟨branched-off⟩`;
- decisions → `◆` with the outcome annotated (`◆ … → chose X` / `◆ (OPEN)`).

Wrap in a code fence.

## 6. Render the report

Render the assembled report in chat (graph included when §5 rendered one), using the shape in `assets/TEMPLATE_REPORT.md` (the skill's base dir — do not hardcode `~/.claude`). **Match the project's prose density and stick to the template's plain section headers — no decorative emoji** unless the template itself carries them (the project leans terse-and-plain; do not freehand decoration on top of the shape). Lead with the **state line** and a compact **state strip** (branch · work-repo committed? · dirty · [plan x/y — omit if no plan] · open-threads), then the **reconciliation deltas** (near the top — it's the payload), then: work done → git (per repo) → ticket → the flowgraph (or ordered next-list if gated out) → pending-on-you → what's next → open threads.

## 7. Walk every open thread

Walk the user through **each** open thread / pending decision (digest §5 + §7) for disposition — the thorough close is what turns a report into being *back in the flow*. Batch via `AskUserQuestion` (4 per batch, `§INV_BATCH_SIZE_4`). Per thread offer disposition: **address now** / **defer (tag)** / **dismiss** / **note & move on** — and always honor an **"explain first"** request (a returning human often needs the *why* before deciding, not just fix/defer/dismiss): explain the thread's stakes, then re-present its disposition. "Address now" = route it (resume the work, or hand to the owning skill) — never fix code inside `/report`. "Defer (tag)" applies an orientation `#needs-*` bookkeeping tag (permitted by `¶INV_REPORT_READ_ONLY`'s scope — it touches no code/git/ticket content). Zero open threads → say so and skip to §8.

## 8. Save (default) & stop

Save the report **by default** (`¶INV_REPORT_SAVE_BY_DEFAULT`) — it's a durable artifact, not an ephemeral glance. Write it to `<sessionDir>/builds/REPORT.md`, latest-wins (overwrite on re-run). The digest already sits beside it at `<trailDir>/REPORT_DIGEST.md`. Report the saved path (clickable), then **stop**.

## Constraints

- **`¶INV_REPORT_READ_ONLY`** — `/report` never mutates **code, git, or ticket content**: no commits, no ticket posts, no code edits, no gate/test re-runs. **Permitted**: writing its own report + digest under `<trailDir>`, and applying orientation `#needs-*` bookkeeping tags during the §7 thread-walk (session-state bookkeeping only). A bug or risk it notices is an open-thread line item, not a repair.
- **`¶INV_REPORT_ORIENTATION_NOT_REVIEW`** — Forward/present-facing: where are we, what's blocked, what's next. Disjoint from `/summarize` — it does NOT judge work quality, run goal-vs-actual retrospection, or offer the inverse-ask palette. "Was this good / interrogate what we did" → route to `/summarize`. Past events appear only insofar as they establish the present state.
- **`¶INV_REPORT_TRANSCRIPT_IDENTITY`** — Resolve the transcript by session **identity** (`$CLAUDE_CODE_SESSION_ID`), never by newest-mtime. With multiple windows open, newest-`.jsonl` is routinely a sibling session; the mtime path is a last-resort fallback and must be verified against this session's dir before use.
- **`¶INV_REPORT_TRANSCRIPT_FILTER`** — The subagent drops read/inspection noise but **retains all decision/state-bearing calls**: AskUserQuestion (unfiltered), Skill/Task invocations, ExitPlanMode, and commit/ticket/PR calls (with their SHAs/keys/URLs) — plus all user + assistant text.
- **`¶INV_REPORT_RECONCILE`** — The subagent reconstructs from the transcript **blind first**, then reads the orchestrator's bearings only to diff for the deltas section. Transcript-authoritative on facts; bearings add unstated intent only. Reconciliation deltas are surfaced, not hidden.
- **`¶INV_REPORT_STALENESS`** — The subagent always checks narrative-artifact mtimes against the last substantive work and flags any that predate it (a debrief/ticket/PR body written before the last real work). Stale-narrative is a recurring highest-value finding — name it, don't hope it emerges.
- **`¶INV_REPORT_FILE_HANDOFF`** — Subagent→orchestrator handoff is via file: the digest is written to `<trailDir>/REPORT_DIGEST.md` (returning only a short summary), and the final report is saved to `<sessionDir>/builds/REPORT.md`. Both are durable artifacts beside the other `builds/` files.
- **`¶INV_REPORT_SAVE_BY_DEFAULT`** — The report is saved by default (not offered/ephemeral), latest-wins.
- **`¶INV_REPORT_GIT_FOLLOWS_WORK`** — Report git for the repo(s) the session actually modified, not cwd by assumption; cwd-git can be entirely unrelated (e.g. engine work under `~/.claude/engine`).
- **`¶INV_REPORT_GRACEFUL`** — Degrade, never hard-fail. No ticket → skip. No plan → omit plan segment. No transcript → DIALOGUE + log; none of those → skip the subagent, orchestrator does git + ticket. Young branch → `-n 10`, guarded ahead/behind. Always render whatever exists.
- **Subagent for the transcript read; interactive walk stays with the orchestrator.**
- **Lightweight + sessionless.** Locate → bearings → scan (file handoff) → reconcile → graph (gated) → render → walk → save, then stop.
