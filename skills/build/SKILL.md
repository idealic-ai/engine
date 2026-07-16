---
name: build
description: "Hand a scoped implementation task to a builder sub-agent with a COMPLETE context pack assembled from the active session (goal, verbatim asks, plan slice, prior-chunk history, the whys, hard gates, scope guard), get back a structured Build Report to the session folder, then optionally chain into /scrutinize. Triggers: \"build this with an agent\", \"agent-build this chunk\", \"delegate this build\", \"context-rich handoff\"."
version: 1.0
tier: lightweight
args: "[<chunk / task descriptor>] [-- <goal override>]"
---

Delegate a tightly scoped implementation task to a `builder` sub-agent by arming it with a **complete, self-contained Context Pack**. You are the manager; the sub-agent is the doer. You assemble the context, dispatch the agent, verify its structured **Build Report**, and (optionally) chain into `/scrutinize`.

A **building block**: it delegates the build, verifies the gates, and reports the outcome; it never reviews its own work (that is `/scrutinize`'s job) and never commits (that is `/snapshot`'s job).
*Crucial constraint:* `/build` does NOT own a session. It reads the *active* session's artifacts and writes its paper trail directly into that session's folder.

This is fundamentally different from a vanilla agent handoff ("read this plan, start coding"). `/build` front-loads the **goal, the whys, prior-chunk history, strict scope boundaries, hard gates, and a return contract**. This ensures the sub-agent makes the decisions *you* would make, respects prior work, and leaves a durable paper trail the reviewer can start warm from. Remember the guiding law: *an agent's output quality is strictly bounded by the completeness of its context* (`§INV_REQUEST_IS_SELF_CONTAINED`).

### Execution Mode: Engine vs. Standalone
Before proceeding, determine your environment. You are running under the workflow engine **if and only if `COMMANDS.md`** (the engine's core command standards, containing `§CMD_*` / `§INV_*` definitions) **is preloaded in your context** (the SessionStart hook injects it). This single check dictates every fallback below:
- **Engine Mode (`COMMANDS.md` present):** An active session exists. Use `engine log`, `<sessionDir>`, and set `<trailDir> = <sessionDir>/builds/`. Draw context from the session's `DIALOGUE.md`, plan, and log.
- **Standalone Mode (`COMMANDS.md` absent):** You are assisting a teammate without the engine. No session exists. Use the global `/tmp` trail directory and plain file appends (defined in Step 1). Draw context directly from the conversation history, and treat any `§CMD_*`/`§FMT_*` reference below as plain-English guidance (the surrounding prose describes the behavior).

The rest of the protocol is identical either way — the Task/AskUserQuestion/Skill mechanics need no engine.

# /build Protocol

## 1. Anchor the Scope & Goal

First, establish the two anchors of the build. Resolve the **task** from the provided arguments, or fall back to the active session's plan (the current chunk). Define the **goal** in 1–3 clear sentences (text after `--` in the args overrides). Explicitly lock down the task boundary: which files / subsystems this build touches, and what it must absolutely NOT touch.

**Resolve the Artifact Location (`<trailDir>`).** Determine this once and use it everywhere below for the paper trail (`<trailDir>/<CHUNK>_BUILD.md`, `LESSONS.md`, etc.):
- **Engine Mode:** If `.state.json` has `sessionDir`, then `<trailDir> = <sessionDir>/builds/`. Ledger/log appends use `engine log`.
- **Standalone Mode:** If no engine/session, `<trailDir> = ${TMPDIR:-/tmp}/finch-build-trail/<repo-basename>/`. This is a STABLE global directory — the same across `/build` + `/scrutinize` runs so the ledger + report→pack coupling still work, and no repo pollution. Run `mkdir -p <trailDir>`. Ledger/log appends use a plain file append (e.g. `printf '## …\n…\n' >> <trailDir>/LESSONS.md`) instead of `engine log`, and **every** pack field draws from the conversation + the user's stated goal/args (no `DIALOGUE.md`/plan/log to read).

**Mint the `<CHUNK>` Slug.** The orchestrator (you) owns the slug, not the sub-agent. All three trail files (`<CHUNK>_CONTEXT_PACK.md`, `<CHUNK>_BUILD.md`, and `/scrutinize`'s `<CHUNK>_CRITIQUE.md`) MUST share one slug, **or the coupling silently breaks (`/scrutinize` won't find the pack and degrades to report-only)**.
1. Run `ls <trailDir>`.
2. If a matching slug from a prior run fits (same chunk / ticket / topic, so the trail clusters under one name), reuse it.
3. Otherwise, mint a new short, kebab-case slug of the task (e.g. `auth-middleware`, `recap-cluster-flat`).

*Crucial:* Compute this string now and reuse the identical string everywhere below. When you dispatch the builder (§3) you hand it the **fully-substituted absolute report path**, never a `<CHUNK>` placeholder to fill.

**Acknowledge:** Echo back your setup in exactly one line:
`Building <task> — goal: <goal>; scope: <file/subsystem boundary>; chunk: <CHUNK>; trail: <trailDir>.`

## 2. Assemble the Context Pack (The Differentiator)

**Read the Compounding Memory first.** Before writing anything, read `<trailDir>/LESSONS.md` (the lessons ledger, if it exists) and the most recent Build Report (`<trailDir>/*_BUILD.md`, newest). Extract its `reusableFacts`, `outOfScopeNoticed`, and `assumptionsThatCouldBeWrong`. These feed the pack so learnings compound instead of living in your working memory.

**Write the Pack.** Fill out `assets/TEMPLATE_CONTEXT_PACK.md` from the active session data, and **WRITE the filled pack to `<trailDir>/<CHUNK>_CONTEXT_PACK.md`** — do NOT just inline it into the prompt. This persisted file is a required half of the `/build`↔`/scrutinize` coupling: `/scrutinize`'s `build-report` mode reads it as the sibling artifact for goal/whys/scope/parity. Write it, then compose the same content into the dispatch prompt (§3).

Every field must earn its place — quality + structure, not volume. A "mirror this reference implementation" pointer beats paragraphs of prose. Fill these fields meticulously:
- **goal** — the core purpose of this build.
- **whatWasAsked** — the user's **verbatim** request(s) from `DIALOGUE.md`. Never paraphrase; the exact words carry hidden constraints.
- **planSlice** — this chunk's detail from the plan file.
- **sessionHistory** — a digest of prior chunks from the session log: what's done, what's committed vs. uncommitted, and any invariants/decisions already locked in — so the agent doesn't re-derive or undo.
- **whys** — the relevant decisions + rationale from `DIALOGUE.md` / log (why approach A over B, constraints the user set). This stops the agent from "fixing" deliberate choices.
- **carriedForwardLessons** — distilled facts/rulings from `LESSONS.md` + prior reports' `reusableFacts` this chunk needs. The compounding win.
- **referenceArt** — a specific file, function, or PR that serves as a structural template for this work (e.g. "mirror the pattern in `src/auth/jwt.ts`"). A reference pointer beats paragraphs of prose. Omit for entirely novel work.
- **inScopeFiles** — the authoritative file/area set the agent may change.
- **outOfScope** — explicit "do NOT touch" (other chunks, unrelated working-tree changes, no commit).
- **likelyTraps** — the predictable wrong turns THIS task invites, as "you'll be tempted to X — don't, because Y". Negative guidance pre-empts the mistakes. *(Illustrative — adapt, don't copy: "you'll be tempted to use a generic type here — don't, the downstream parser requires strict string enums.")*
- **parityOracle** — for behavior-preserving work: name the test(s) that ARE the contract (+ a before/after for one fixture if useful). Omit for greenfield.
- **gates** — the build/test/lint/type-check commands + machine-checkable pass criteria.
- **returnContract** — the Build Report schema the agent must fill.

**Confirm (if ambiguous).** For a large or ambiguous chunk, present the pack's scope + gates + out-of-scope via `AskUserQuestion` for a quick confirm/prune. For a small, well-scoped chunk, assemble silently and say so in one line.

## 3. Dispatch the Builder

**Backgroundable & parallelizable.** This sub-agent dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working while it runs, and when the work splits into independent chunks, several such sub-agents can be fanned out in parallel and reconciled.

Spawn **one** `builder` sub-agent — **prefer the background** (`run_in_background: true`) so you keep working (and can fan out other agents) while it runs and you're notified when it lands; run it in the **foreground** only if you need its Build Report before your next step. Construct its prompt from the Context Pack. The prompt MUST be entirely self-contained — the sub-agent cannot see your memory or session history. Use this exact template:

> You are executing ONE tightly-scoped build task as an autonomous agent. Do ONLY what's in scope; read the rest for context; do not wander, do not commit.
>
> **Frame of mind:** your Build Report is a *survival guide for the next agent who touches this code* — not a status update to a boss. Defend your choices with concrete reasons, expose the dead ends you hit so nobody repeats them, and ruthlessly interrogate whether your tests actually PROVE your claims or just happen to pass. Density and honesty over tidiness.
>
> - **Goal:** `<goal>`
> - **What the user actually asked (verbatim):** `<whatWasAsked>`
> - **This chunk's plan:** `<planSlice>` (full plan: `<plan path>`)
> - **Session history so far (do not re-derive / undo):** `<sessionHistory>`
> - **The whys / decisions already made (honor these, don't "fix" them):** `<whys>`
> - **Carried-forward lessons (established facts — rely on them, don't re-litigate):** `<carriedForwardLessons>`
> - **Reference art (mirror this pattern):** `<referenceArt>`
> - **In scope (only these):** `<inScopeFiles>`
> - **Out of scope (do NOT touch):** `<outOfScope>`
> - **Git Safety (hard rule — `¶INV_NO_DESTRUCTIVE_GIT`):** the tree is ALWAYS dirty with parallel-agent work. NEVER run tree/index-destructive git — no `git stash`, no `git checkout`/`git switch`/`git restore` of paths or branches, no `git reset --hard`, `git clean`, `git rm`, and above all NEVER `git checkout -- <path>` / `git checkout HEAD -- …` to "clean up" or capture a baseline (that silently destroys other agents' uncommitted work with no git-recoverable trace). Read a committed version with `git show HEAD:<path>`; open working files by explicit path. The ONLY allowed write is `git add -- <explicit path>`; do NOT commit (that is `/snapshot`'s job). A PreToolUse hook blocks these — if it blocks you, do NOT retry-to-bypass; STOP and report the blocker.
> - **Likely traps (you'll be tempted to do these — don't):** `<likelyTraps>`
> - **Parity oracle (behavior-preserving work — this test IS the contract):** `<parityOracle>`
> - **Hard gates (must all pass before you finish):** `<gates>` — run them; paste the EXACT command + exit code + summary.
> - **Logging discipline (engine mode only):** `<LOGGING>` — under an engine session the orchestrator substitutes the concrete session-log command here (`engine log <the active session's log path>`, appended every ~5 tool calls, **because a heartbeat hook BLOCKS after 10 tool calls without a log**). In standalone mode there is no heartbeat — OMIT this line entirely; the Build Report is the trail.
> - **Return contract:** when done, WRITE your report to `<trailDir>/<CHUNK>_BUILD.md` using the Build Report template (in THIS skill's `assets/TEMPLATE_BUILD_REPORT.md` — the orchestrator gives you its base dir; do not hardcode `~/.claude`) — fill EVERY field: approach + deviations, dead ends, authoritative `filesTouched`, autonomous decisions, self-flagged risks, **assumptionsThatCouldBeWrong**, **parityEvidence** (how you proved behavior held), **reusableFacts** (durable facts later chunks need), gate results as **exact-command→exit-code**, out-of-scope-noticed, blockers. Then return a 4–6 line summary + the report path.
> - **Escalate, don't paper over:** if an approved approach conflicts with the goal / a prior decision, or **would force `any` / a behavior change**, STOP and report the blocker with options rather than guessing.

*Note on isolation:* prefer `isolation: "worktree"` only if the build must run alongside other agents mutating the same files. Otherwise, standard execution is fine.

## 4. Report Intake & Independent Verification

When the sub-agent returns, read the Build Report. **You must re-run the gates yourself** (`§ verify, don't trust`) — re-run the **exact commands** the report lists under Gate results (not paraphrases), so you catch "green on my machine" drift. Do not take the agent's "all green" on faith.

**Feed the ledger.** Append the report's `reusableFacts` (and any hard-won correction to a wrong pack premise) to `<trailDir>/LESSONS.md`:
- Use `engine log` under a session, else a plain file append (`printf '## …\n…\n' >> <trailDir>/LESSONS.md`).
- Format as one terse bullet per fact. Keep it distilled (facts + rulings, not narrative). This is what makes the next `/build` smarter.

**Relay a concise summary:** approach + key deviations, files touched, verified gate results, and any self-flagged risks, assumptions, or blockers. Link the report (`§CMD_LINK_FILE`).

## 5. Optional /scrutinize (Ask — Don't Auto-Chain)

Offer via `AskUserQuestion` to run `/scrutinize` on the build, passing the Build Report so the critiquer starts warm and scoped:
`Skill(scrutinize, "build-report <trailDir>/<CHUNK>_BUILD.md")`
*Crucial:* keep the human gate. The user decides whether to review now, later, or skip. Do not auto-execute.

## Constraints & Invariants
- **Context pack is mandatory + self-contained.** Never dispatch without goal + verbatim ask + scope + gates. The agent must not need your memory.
- **Background by default.** One agent, dispatched to the background by default (foreground only when you need its report before the next step); the parent verifies when it lands. Independent chunks can be fanned out as parallel background agents.
- **Paper trail always.** Both the **Context Pack** (`<trailDir>/<CHUNK>_CONTEXT_PACK.md`, written in §2) and the **Build Report** (`<trailDir>/<CHUNK>_BUILD.md`, §3) are persisted — even on partial/blocked runs. The pack is not optional: `/scrutinize` reads it as the coupling's sibling artifact.
- **Scope guard.** The agent touches only `inScopeFiles`. Unrelated working-tree changes (prior chunks) are off-limits and are declared out-of-scope so `/scrutinize` won't misattribute them.
- **No commit** unless the user asks.
- **Git Safety (`¶INV_NO_DESTRUCTIVE_GIT`).** Neither the orchestrator nor the builder runs tree/index-destructive git (`stash`, `checkout`/`switch`/`restore` of paths or branches, `reset --hard`, `clean`, `rm`, `git add -A`/`-u`/`.`) — the tree is always dirty with parallel-agent churn, so any of these can silently erase another agent's uncommitted work with no recoverable trace. The only allowed write is `git add -- <explicit path>`; baselines come from `git show HEAD:<path>`. Committing is `/snapshot`'s job. Enforced by the one-strike hook.
- **Verify independently.** The parent re-runs the report's exact gate commands before reporting green.
- **Compounding memory.** `<trailDir>/LESSONS.md` is the append-only ledger of durable facts + rulings. `/build` reads it into every pack (`carriedForwardLessons`) and appends each report's `reusableFacts` to it; `/scrutinize` appends confirmed findings + resolved design decisions. Learnings compound across chunks instead of living in the orchestrator's working memory.
- **Distill, don't pad.** Context quality + structure beats volume — a "mirror this reference implementation" pointer and a sharp "likely traps" list outperform long prose. Padding dilutes the load-bearing parts.
