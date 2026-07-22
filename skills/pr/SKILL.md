---
name: pr
description: "Open a pull request for the current branch with a CONTEXT-MAXED body. A PR-writer subagent reads the branch commits + diff, the linked ticket(s), and the full builds/ trail (build reports, critiques, verdicts, decisions) to draft a rich PR description — Summary, linked ticket + acceptance checklist, Changes + Verification, Decisions/Risks/CI-gates. Context-aware about the branch: on a MIXED branch it offers to cherry-pick just the target ticket's commits onto a fresh branch (never rewriting the shared branch); on a clean branch it pushes as-is. One confirm → push → gh pr create (base branch from the project's § Tracker config — dev for finch — draft or ready), then requests an automated Copilot review and polls the background for both Copilot and the Codex connector (the latter gated on its 👀 reaction), relaying the findings when they land. A building block: it opens the PR and surfaces the review, never addresses feedback or merges. Triggers: \"open a PR\", \"create a pull request\", \"PR this\", \"raise a PR\", \"ship this for review\"."
version: 1.0
tier: lightweight
args: "[<base branch override, default: CLAUDE.md § Tracker PR base — dev for finch>] [--dry-run] [-- <PR title / framing override>]"
---

Open a pull request for the current branch with a **context-maxed** description. A PR-writer subagent reads *everything* — the branch commits, the diff, the linked ticket(s), and the full `builds/` trail (build reports, critiques, verdicts, and the "whys") — to draft a rich, trustworthy PR body. This allows a human reviewer to trust the work without having to re-derive it. This skill is sessionless and lightweight: it runs *within* the active session, scopes the range, drafts the body, gets one confirmation, pushes, runs `gh pr create`, and stops.

This is **not `/snapshot`**. The `/snapshot` skill creates per-checkpoint commits and a ticket comment. The `/pr` skill operates at the **branch-level** — it rolls those checkpoints up into the entire slice of work for review. They compose perfectly: many `/snapshot` checkpoints culminate in one `/pr`. This is a **building block**: it opens the PR, but it *never* merges it.

### Execution Mode: Engine vs. Standalone
Before proceeding, determine your environment. You are running under the workflow engine **if and only if `COMMANDS.md`** (the engine's core command standards, containing `§CMD_*` / `§INV_*` definitions) **is preloaded in your context** (the SessionStart hook injects it). This single check dictates every fallback below.
- **Engine Mode (`COMMANDS.md` present):** You are in an active session. Set `<trailDir> = <sessionDir>/builds/`. The PR-writer subagent will draw deep context from the session's `builds/` trail and log.
- **Standalone Mode (`COMMANDS.md` absent):** You are running without a session. Set `<trailDir> = ${TMPDIR:-/tmp}/finch-build-trail/<repo-basename>/`. Treat `§CMD_*` references as plain-English guidelines. **Note the degradation:** In standalone mode, there is no session `builds/` trail. The PR body must be drafted solely from the branch commits, the diff, the linked ticket, and the conversation digest. Expect a thinner "Decisions & rationale" section.

**Hard Repo Rules (Enforce Strictly):**
- **Target Branch:** PRs target the **configured base branch** (CLAUDE.md § Tracker "PR base branch"; `dev` for finch), **never `main` directly** (`gh pr create --base <base>`). Resolve `<base>` in §1 (args override § Tracker; absent both, fall back to `dev`).
- **CI Boundaries:** Build and lint are **CI's job**. Do NOT run them here. Instead, flag special CI gates in the PR body (see §2).
- **Attribution:** All PR bodies must end with the trailer: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **Consent:** Push and PR creation happen ONLY after explicit user confirmation.

**Tracker Integration:**
We use **Linear** via the `linear-server` MCP — the tracker + its tools are constant; only the **issue-key prefix** varies per project and comes from CLAUDE.md § Tracker (resolve it in §1, inject into the subagent prompt; keys are `<PREFIX>-NNNN` — `FIN` for finch). Use the `get_issue` tool to read the linked ticket's title and acceptance criteria. Load this on demand via ToolSearch `linear`. GitHub integration is handled via the `gh` CLI. If no tracker is found or linked, draft the PR from the commits/diff, explicitly note the absence of a ticket, and skip the acceptance checklist.

**Preview / dry-run mode:** If invoked with `--dry-run` (or the user asks to preview the body without pushing), run §1 and §2 normally, then **STOP after the PR-writer writes `<trailDir>/<slug>_PR.md`** — do NOT enter §3 (no confirm, no push, no `gh pr create`). Report the file path so a cautious user can hand-edit the body in their editor, then re-run `/pr` without `--dry-run` to push it.

# /pr Protocol

## 1. Scope & Base Branch

Establish the base branch, the commit range, the branching strategy, and the linked ticket(s).

- **Resolve the tracker config (do this first):** Read CLAUDE.md's `## Tracker` block (the orchestrator sees CLAUDE.md; the subagent does NOT — resolve here, inject in §2). Resolve the **issue-key prefix** (`<PREFIX>` uppercase for keys `<PREFIX>-NNNN` / its lowercase for branches `<prefix>-NNNN-…`) and the **PR base branch** (`<base>`). Finch: prefix `FIN`, base `dev`. **Fallback — no `## Tracker` block** (unconfigured/standalone): keep today's behavior — detect a `FIN`-style key (uppercase-alpha prefix + `-NNNN`) from branch/commits/conversation, and default `<base>` to `dev`. Args override § Tracker for the base; the config is never a hard requirement.
- **Base branch:** The default is `<base>` (from § Tracker → `dev` for finch), which can be overridden by arguments. Determine the current branch using `git branch --show-current`.
- **Sync & Divergence Pre-check (CRITICAL):** Before asking for confirmation, run `git fetch`. Then, report if the branch is ahead/behind upstream using `git status -sb` or `git rev-list --left-right --count @{u}...HEAD`.
  - If the branch is **BEHIND**, surface this immediately. A standard push (never `--force`) will be rejected as non-fast-forward.
  - Do **NOT** attempt to auto-resolve (no `git pull` or `git rebase` — that is dangerous history mutation).
  - Instead, force the user to either reconcile manually OR steer them to the **cherry-pick/fresh-branch path** (which sidesteps the divergence by pushing a clean new branch). Never proceed silently into a push that will fail.
- **Show the range:** Run `git log <base>..HEAD --oneline` (to see the commits) and `git diff <base>...HEAD --stat` (to see the shape). Render both in the terminal so the user sees exactly what the PR will contain.
- **Isolation Check (Do this FIRST):** Check if the current checkout is already isolated. This usually makes cherry-picking unnecessary.
  - If the CWD is a **linked `git worktree`** (`git rev-parse --git-common-dir` ≠ `git rev-parse --git-dir`, or CWD is a non-main entry in `git worktree list`), OR
  - If the branch is **CLEAN** (all `<base>..HEAD` commits belong to the single target ticket).
  - **Action:** If either is true, the branch is already a focused slice. **Push it as-is and skip the cherry-pick machinery entirely.** The cherry-pick path is a fallback for shared/MIXED branches in the main working tree only.
- **Branch Strategy (Context-Aware Decision):** Group the `<base>..HEAD` commits by their ticket identifier (e.g., `<PREFIX>-NNNN` in the commit messages).
  - **CLEAN branch:** All commits belong to the target ticket. → **Push the whole branch** as-is.
  - **MIXED branch:** Commits for multiple tickets are interleaved (common on shared branches). → **SURFACE this** to the user via `AskUserQuestion`. Offer two choices:
    1.  **Push the whole branch:** The PR covers everything currently on it.
    2.  **Cherry-pick target commits:** Create a fresh branch (`<prefix>-<ticket>-<slug>`) and cherry-pick ONLY the target ticket's commits for a focused PR.
    **Let the user confirm/trim the exact commit set either way.**
  - **Untagged & Merge Commits:** Show these in their own bucket. **WARN** the user that they are excluded from a focused cherry-pick. If an excluded intermediate commit is a dependency for a target commit, it will surface as a conflict or an incomplete PR.
  - **Merge Commit Rule:** REFUSE to include merge commits in a cherry-pick set. They require `-m <parent>` and break focused picks. If the range contains merge commits, you MUST use the whole-branch path.
  - **Conflict Handling:** The cherry-pick preserves commit order and stops on the first conflict. This surfaces broken dependencies loudly. Never silently drop work.
  - **No Silent Decisions:** Never push a mixed branch whole without asking; you might accidentally PR someone else's work.
- **Detect Linked Ticket(s):** Extract `<PREFIX>-NNNN` (prefix from § Tracker) from the branch name, commit messages, or conversation (args `--` overrides this). Use `get_issue` on the **primary** ticket to fetch its title and acceptance signals. If there are multiple tickets, ask the user to pick the **primary** (`Closes`), and for the others, ask if they should be related (`Relates`) or ignored. Do not auto-relate everything.
- **Resolve the Trail:** Determine `<trailDir>` based on your execution mode. Pick a `<slug>` (kebab-case of the work or ticket). Before creating a new one, run `ls <trailDir>`. **REUSE** an existing `<slug>_*.md` that matches this work so the PR artifact clusters with the upstream build/snapshot artifacts under one name. Only mint a fresh slug for entirely new work.
- **Echo Status:** Print exactly one line back to the user: `PR for <branch> → <base> (<n> commits, <strategy: whole | cherry-pick <k>>); closes <<PREFIX>-NNNN "title">; trail: <trailDir>/<slug>_PR.md.`

## 2. Draft — Spawn the PR-Writer Subagent

**Backgroundable & parallelizable.** This sub-agent dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working while it runs, and when the work splits into independent chunks, several such sub-agents can be fanned out in parallel and reconciled.

Spawn **one** subagent (using a `general-purpose` or `analyzer` role) to assemble the richest, most honest PR body possible. This subagent is **read-only**: it reads and drafts, but it NEVER pushes, creates the PR, or touches git state.

Construct its prompt to be entirely self-contained. Use the following prompt structure:

> **SYSTEM PROMPT FOR PR-WRITER SUBAGENT:**
> You are an expert engineer **selling this architectural change to a skeptical maintainer** who has zero context on this session. Do NOT simply regurgitate the git diff. Your job is to explain the WHY, prove the change is safe, surface the roads not taken, and direct the reviewer's attention to the most complex or fragile parts. Read WIDELY and draft a rich, honest body. **CRITICAL: You are read-only. Do NOT push, create the PR, cherry-pick, or change any git state.**
>
> - **Tracker config (resolved from CLAUDE.md § Tracker — the orchestrator fills these; you cannot read CLAUDE.md):** Linear (linear-server MCP) · issue-key prefix `<PREFIX>` (keys `<PREFIX>-NNNN`, branches `<prefix>-NNNN`) · PR base `<base>`. Use this prefix for every linked-ticket reference; do NOT assume `FIN`.
> - **The Change:** Branch `<branch>` → base `<base>`. Commits: `<git log <base>..HEAD --oneline output, or the cherry-pick set>`. Shape: `git diff <base>...HEAD --stat`. Read the actual diff for the substantive files to understand the implementation.
> - **Linked Ticket(s):** `<primary <PREFIX>-NNNN — title + acceptance from get_issue>`; related: `<others>`. **If there is NO linked ticket**, explicitly state "No linked ticket — drafted from commits/diff" in the Linked-ticket section instead of leaving an empty `Closes`, and skip the acceptance checklist.
> - **Max Context (READ THE FULL TRAIL):** In `<trailDir>`, read THIS work's `<slug>_*.md` files (e.g., `_SNAPSHOT.md` — `/snapshot` feeds `/pr` — `_BUILD.md`, `_CONTEXT_PACK.md`, `_CRITIQUE.md`, `_FIX.md`, `_EXPERIMENT.md`, `_TICKETS.md`), plus `LESSONS.md` and the session log. These files contain the DECISIONS, critique findings, verification results, and risks — everything the diff cannot show.
>   - *Note:* In a long session, `builds/` holds unrelated slugs. Scope your reading to this work's `<slug>`, skimming others only if directly relevant.
>   - *Standalone Mode:* The trail may be absent. If so, draft from the commits, diff, and ticket, and explicitly note that the "Decisions & rationale" section is thinner because there is no session trail to draw from.
>
> - **CI Gates Detection:** If the project documents special CI gates that specific file/function changes trigger (typically in its `CLAUDE.md` / `CONTRIBUTING.md` — e.g. "editing X requires a version bump", "touching Y needs a regenerated attestation", "a new migration needs a journal entry"), detect whether this diff trips any of them and flag them in the body as a reviewer heads-up. If the project documents no such gates, skip this. (Do NOT run build/lint yourself; that is CI's job.)
>
> - **Drafting the Body:** Use the provided template (this skill's `assets/TEMPLATE_PR_BODY.md` — the orchestrator gives you its base dir; **do not hardcode `~/.claude`**).
>   - *Always-On Sections:* Summary (what + why), Linked ticket + acceptance checklist, Changes (by area), Verification/testing (what was actually run + results from the trail; NEVER claim a gate you can't see in the trail), Decisions & rationale, Risks/watch-outs, and ⚠ CI gates.
>   - *Include-If-Present Sections:* Out-of-scope/followups, Alternatives considered (architectural roads tried and rejected), Reviewer focus areas (where the human should look closely), Branch note (if a cherry-pick), Screenshots/notes.
>   - *NEVER write a bare `#<number>` anywhere in the body:* GitHub autolinks `#1` to issue/PR #1 in the repo and renders it as **that issue's title**, splicing an unrelated PR name into your sentence (this has already shipped in a real PR — acceptance items numbered `#1`–`#4` posted as "Invite flow #1", "Add Claude Code GitHub Workflow #3"). Enumerate with `A1`/`1.` instead; use `#N` only to genuinely reference that issue. Linear keys (`FIN-3141`) are safe.
>
> - **Return Contract:** WRITE the drafted body to `<trailDir>/<slug>_PR.md` (Markdown format, exactly as it will post, but WITHOUT the Claude Code trailer — the orchestrator handles that). Then, return to the orchestrator with:
>   1. The proposed PR title.
>   2. A draft-vs-ready recommendation.
>   3. The detected CI gate flags.
>   4. A 3-line summary of the PR.

Dispatch this subagent to the background by default (`run_in_background: true`) so you keep working while it drafts; relay the results when it lands. Run it in the **foreground** only if you need the drafted body before your next step.

**Preview / dry-run stop:** If this run is a `--dry-run` / preview, STOP HERE. Report the written `<trailDir>/<slug>_PR.md` path (plus the proposed title + gate flags) and do not proceed to §3 — no confirm, no push, no `gh pr create`. The user can hand-edit the body, then re-run `/pr` without `--dry-run` to push.

## 3. Confirm, Push & Create (Single Confirm)

> **HARD RULE — NO HISTORY REWRITING / NO LIVE-TREE MUTATION.**
> `/pr` NEVER uses `git rebase`, `git reset`, `git commit --amend`, or `git push --force`. It NEVER uses `git stash` (forbidden). It NEVER uses `git switch -c` or checkouts to mutate the current/shared branch or the live working checkout. (The ONE exception — a `git worktree`-unavailable fallback on a verified-CLEAN tree — is spelled out in §3; it `switch -c`s a NEW branch off `<base>` and restores the original branch as its final step, never mutating the shared branch.)
>
> **The cherry-pick mechanism relies exclusively on `git worktree`.** A focused pick builds a NEW branch off `<base>` in a *separate throwaway worktree*. This guarantees the user's original branch, checkout, and dirty working tree remain untouched.
> - On ANY cherry-pick conflict: run `--abort`, remove the worktree, STOP, and surface the error to the user. Never auto-resolve or use `-X` force.
> - If a focused PR cannot be built cleanly, hand control back to the user. Do not force it.

1. **Relay the Plan:** Present the following to the user: branch strategy (push-whole vs. cherry-pick `<k>` commits onto `<prefix>-<ticket>-<slug>`), base branch, proposed title, draft-vs-ready status, ticket links (`Closes` primary + `Relates` others), detected **CI gate flags**, and the rendered PR body (or a digest + trail link if it is very long).
2. **Confirm (MANDATORY):** Use `AskUserQuestion` to get explicit permission. This action pushes code and opens an outward PR.
   - Present the summary: **Title · Base (`<base>`) · Strategy · Draft|Ready · Closes/Relates · Gate Flags · Body**.
   - Offer options: **Create PR / Edit one first / Cancel**.
   - If "Edit one first", ask what to change (title, strategy, draft/ready, body, links), loop back, and re-present the plan.
3. **Execute on "Create" (Strict Order):**
   - **Append the Trailer:** The subagent wrote the body to `<trailDir>/<slug>_PR.md`. Append the string `🤖 Generated with [Claude Code](https://claude.com/claude-code)` to the end of that FILE.
   - **SECURITY WARNING:** Always create the PR using **`--body-file <path>`**. NEVER pass the body inline via `--body "..."`. The body contains backticks and `$` characters. Passing it inline allows bash to perform **command-substitution**, which corrupts the body and creates a severe remote-code-execution vulnerability (e.g., a trail containing `` `rm -rf...` `` would execute).
   - **Path A: Whole-Branch (Clean branch, or user chose push-whole):**
     ```bash
     git push -u origin <the-branch-being-prd>  # Safe feature branch push; never --force
     gh pr create --base <base> --title "<title>" --body-file <trailDir>/<slug>_PR.md [--draft]
     ```
     *(Note: `--title` must be a single, short, sanitized value).*
   - **Path B: Cherry-Pick (Focused PR via `git worktree`, NEVER `git switch -c` the live tree):**
     ```bash
     # <tmp-path> must be a scratch dir OUTSIDE the repo tree
     git worktree add -b <prefix>-<ticket>-<slug> <tmp-path> <base>
     git -C <tmp-path> cherry-pick <target-commits-in-order>
     git -C <tmp-path> push -u origin <prefix>-<ticket>-<slug>
     gh pr create --base <base> --head <prefix>-<ticket>-<slug> --title "<title>" --body-file <trailDir>/<slug>_PR.md [--draft]
     git worktree remove <tmp-path>
     ```
     - *Conflict handling:* On ANY conflict, run `git -C <tmp-path> cherry-pick --abort`, then `git worktree remove --force <tmp-path>`, and **STOP**. Never force-resolve, never `-X`. The live checkout stays on the original branch throughout.
     - *Fallback if `git worktree` is unavailable:* This REQUIRES a clean working tree. If the tree is dirty, STOP and tell the user to `/snapshot` or commit their edits first (never `git stash`, never `git switch -c` a dirty tree). Only on a clean tree may you fall back to `git switch -c <prefix>-<ticket>-<slug> <base>`, cherry-pick, push, and then **`git switch <original-branch>`** as the absolute final step to restore the checkout. The live checkout stays on the original branch throughout.
   - Capture the resulting **PR URL**.
4. **Request automated reviews + poll (async, non-blocking):** Once the PR exists, request a GitHub Copilot review and poll in the *background* for BOTH Copilot **and** the Codex connector, so the run isn't blocked. Generic GitHub features; each degrades to a no-op where unavailable.
   - **Derive `<owner>` / `<repo>` / `<n>`** from the PR URL captured above (`github.com/<owner>/<repo>/pull/<n>`).
   - **Request Copilot** (only Copilot is *request-able*): prefer the GitHub MCP tool `request_copilot_review(owner, repo, pullNumber)` (load via `ToolSearch github`). Else `gh api --method POST repos/<owner>/<repo>/pulls/<n>/requested_reviewers -f 'reviewers[]=copilot-pull-request-reviewer[bot]'` (best-effort). If neither is available (standalone / no `gh`), skip + note it.
   - **Codex is NOT requested** — the `chatgpt-codex-connector[bot]` is an opt-in connector that reviews on its own and **signals via a 👀 reaction on the PR body** (present while reviewing, *removed* when it posts). So `/pr` can't request it; it detects engagement and waits only when codex is actually engaged.
   - **Poll both in the background** — `run_in_background: true`; exits 0 on settle OR timeout so you're always re-woken:
     ```bash
     OWNER=<owner>; REPO=<repo>; N=<n>
     RXN="Accept: application/vnd.github.squirrel-girl-preview+json"
     for i in $(seq 1 40); do
       cop=$(gh api "repos/$OWNER/$REPO/pulls/$N/reviews" --jq '[.[]|select(.user.login=="copilot-pull-request-reviewer[bot]")]|length' 2>/dev/null || echo 0)
       cdx=$(gh api "repos/$OWNER/$REPO/pulls/$N/reviews" --jq '[.[]|select(.user.login=="chatgpt-codex-connector[bot]")]|length' 2>/dev/null || echo 0)
       eyes=$(gh api "repos/$OWNER/$REPO/issues/$N/reactions" -H "$RXN" --jq '[.[]|select(.content=="eyes" and .user.login=="chatgpt-codex-connector[bot]")]|length' 2>/dev/null || echo 0)
       ok=$(gh api "repos/$OWNER/$REPO/issues/$N/reactions" -H "$RXN" --jq '[.[]|select(.content=="+1" and .user.login=="chatgpt-codex-connector[bot]")]|length' 2>/dev/null || echo 0)
       codex_settled=0; if [ "$cdx" -gt 0 ] || [ "$ok" -gt 0 ]; then codex_settled=1; fi   # posted a review, or a clean +1
       codex_idle=0;    if [ "$eyes" -eq 0 ] && [ "$cdx" -eq 0 ] && [ "$ok" -eq 0 ] && [ "$i" -ge 3 ]; then codex_idle=1; fi  # never engaged after ~1min
       if [ "$cop" -gt 0 ] && { [ "$codex_settled" -eq 1 ] || [ "$codex_idle" -eq 1 ]; }; then
         echo "REVIEWS_SETTLED pr=$N copilot=$cop codex_review=$cdx codex_ok=$ok"; exit 0
       fi
       sleep 20
     done
     echo "REVIEWS_TIMEOUT pr=$N copilot=$cop codex_review=$cdx codex_ok=$ok"; exit 0
     ```
     (~13-min ceiling; Copilot lands in 1–3 min.) **The 👀 gate**: while codex's eyes reaction is present the loop keeps waiting for its review; if codex never reacts within ~1 min (no eyes, no review, no +1) the loop stops waiting on codex — it isn't engaged on this PR. Give the Bash call a wake `description` — e.g. `Review poll PR <n> — on wake, relay Copilot + Codex (§4)`.
5. **Report & Trail:** Stamp `<trailDir>/<slug>_PR.md` with the final outcome (PR URL, branch, base, draft/ready, gate flags). Provide the link to the user; note the Copilot poll is running and you'll relay it when it lands (§4). **Offer council (optional, `§CMD_OFFER_COUNCIL_REVIEW`):** offer a `/council` panel on the PR diff (`subject: pr <n>` — immutable via `gh pr diff`), dispatched in the background report-only so it runs parallel with the Copilot poll and is relayed when it lands. Offer, never force. **Feed the ledger:** append one terse bullet to `<trailDir>/LESSONS.md` (e.g., "PR opened, URL, closes `<PREFIX>-NNNN`") — `engine log` under a session, else a plain file append (`printf '## …\n…\n' >> <trailDir>/LESSONS.md`). **Then stop** (the background poll re-wakes you for §4). Reviewing, addressing feedback, and merging are your call, not this skill's. **Never merge.**

## 4. Relay the Automated Reviews (on background-poll completion)

When the §3 poll re-wakes you (`REVIEWS_SETTLED` / `REVIEWS_TIMEOUT`, carrying `copilot=`/`codex_review=`/`codex_ok=` counts), fetch whatever landed (queries below), then **disclose it through `§CMD_ELICIT` (standalone) rather than dumping a flat list** — automated reviewers are indiscriminate, so render each finding as a Decision Card (what's-at-stake · complexity · how-to-verify · advisory engagement, with a defeasible `my lean`) and lead with the triaged summary ("N worth addressing, M FYI") so the user sees which findings actually matter vs. noise. Label each card by reviewer (Copilot / Codex). `/pr` stays read-only — `§CMD_ELICIT` only **discloses + classifies attention**; the address/ignore choice (and any `/scrutinize`·`/fix` chain) is the caller's own, offered after the disclosure — it never addresses or merges.
- **Copilot** (`copilot=`>0): summary body + inline findings (`file:line — essence`):
  ```bash
  gh api "repos/<owner>/<repo>/pulls/<n>/reviews"  --jq '.[]|select(.user.login=="copilot-pull-request-reviewer[bot]")|.body'
  gh api "repos/<owner>/<repo>/pulls/<n>/comments" --jq '.[]|select(.user.login=="Copilot")|"\(.path):\(.line) — \(.body)"'
  ```
- **Codex** (`codex_review=`>0): its review is a formal PR review (body starts `### 💡 Codex Review`) + inline findings:
  ```bash
  gh api "repos/<owner>/<repo>/pulls/<n>/reviews"  --jq '.[]|select(.user.login=="chatgpt-codex-connector[bot]")|.body'
  gh api "repos/<owner>/<repo>/pulls/<n>/comments" --jq '.[]|select(.user.login=="chatgpt-codex-connector[bot]")|"\(.path):\(.line) — \(.body)"'
  ```
  - **Codex clean pass** (`codex_ok=`>0 with `codex_review=0`): no written review — relay "Codex reviewed and approved (👍, no written findings)."
- Then **stop** — offer, don't auto-run: `/scrutinize` to triage the findings or `/fix` to address them. Acting on either review is the user's call.
- **`REVIEWS_TIMEOUT`:** relay whatever DID land (per the signal's counts) and note any reviewer that didn't appear in the window (slow, not enabled, or — for Codex — never engaged). The PR is open regardless; don't block on it.

## Constraints (Summary)
- **Automated reviews are requested/detected + polled, never acted on:** after the PR opens, `/pr` requests a Copilot review and polls in the background (re-woken via `run_in_background`) for BOTH Copilot (requested) and the Codex connector (opt-in — detected via its 👀 reaction on the PR, gated so `/pr` only waits when codex is actually engaged), then RELAYS both sets of findings — it never addresses or merges them. Each degrades to a no-op where that reviewer isn't enabled or `gh`/MCP is unavailable.
- **Base from § Tracker (`dev` for finch), never `main` directly:** Resolve the PR base from CLAUDE.md § Tracker (defaulting to `dev` when absent). Overridable only by explicit arguments.
- **No history rewriting / no live-tree mutation:** No `rebase`, `reset`, `amend`, `push --force`, `stash`, or `switch -c` on the live tree. **The cherry-pick mechanism is `git worktree`** — a focused pick builds a NEW branch off base in a throwaway worktree and never touches the source branch or the working checkout. Abort (`--abort` + `worktree remove --force`) on any cherry-pick conflict; never force-resolve. The worktree-unavailable fallback requires a clean tree and restores the original branch as its last step.
- **Push is fast-forward-only:** Fetch and check ahead/behind before confirming. Surface divergence; a plain push (never `--force`) is rejected non-fast-forward if behind — let the user reconcile or take the clean fresh-branch path; never auto-`pull`/`rebase`.
- **Context-aware branch choice is surfaced, never silent:** Always offer push-whole vs. cherry-pick-the-target on mixed branches. Untagged/merge commits are shown as their own bucket and excluded from focused picks (merge commits force the whole-branch path); the user decides.
- **One confirm before push + PR:** Nothing pushes or opens a PR without the explicit confirm; push/PR happen only on "Create".
- **Body via `--body-file`, NEVER inline:** The subagent writes the body to `<trailDir>/<slug>_PR.md`, the orchestrator appends the trailer to that file and creates with `--body-file`; `--title` stays a short sanitized single value. Inline `--body "…"` is forbidden (backtick/`$` shell-substitution risk).
- **Gates flagged, not run:** `/pr` detects + flags any special CI gates the project documents (e.g. in CLAUDE.md/CONTRIBUTING.md) as a reviewer heads-up in the body; it does NOT run build/lint (CI does). It never claims a verification not present in the trail.
- **Building block — opens, never merges:** It creates the PR (draft or ready) and stops; reviewing/merging is out of scope.
- **Claude Code trailer:** Must end every PR body.
- **Lightweight + sessionless:** Scope → draft → confirm → push + create, then stop. The subagent is read-only; all git/`gh` mutations are the orchestrator's, post-confirm.
