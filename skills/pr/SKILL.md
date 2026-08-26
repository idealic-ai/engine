---
name: pr
description: "Open a pull request for the current branch with a CONTEXT-MAXED body. A PR-writer subagent reads the branch commits + diff, the linked ticket(s), and the full builds/ trail (build reports, critiques, verdicts, decisions) to draft a rich PR description — Summary, linked ticket + acceptance checklist, Changes + Verification, Decisions/Risks/CI-gates. Context-aware about the branch: on a MIXED branch it offers to cherry-pick just the target ticket's commits onto a fresh branch (never rewriting the shared branch); on a clean branch it pushes as-is. One confirm → push → gh pr create (base branch from the project's § Tracker config — dev for finch — draft or ready), then requests an automated Copilot review and runs one background watch over the reviewers (Copilot + the Codex connector, the latter gated on its 👀 reaction), the CI check runs on the head commit, and mergeability — exiting only into a named state (complete / checks-red / replies-owed / draft / blocked / stalled) and re-arming when a fix push moves the head. It relays failing check names with their annotations as path:line alongside the review findings, treats each finding as a claim to verify rather than an instruction, and posts a reply on the PR thread recording every finding's disposition — accepted, rejected with the evidence, or deferred with a destination. A PR is complete only when the gates pass AND every review comment carries a reply. A building block: it opens the PR, watches it to a named state, and records dispositions — it applies no fix on its own authority and never merges. Triggers: \"open a PR\", \"create a pull request\", \"PR this\", \"raise a PR\", \"ship this for review\"."
version: 1.0
tier: lightweight
args: "[<base branch override, default: CLAUDE.md § Tracker PR base — dev for finch>] [--dry-run] [-- <PR title / framing override>]"
---

Open a pull request for the current branch with a **context-maxed** description. A PR-writer subagent reads *everything* — the branch commits, the diff, the linked ticket(s), and the full `builds/` trail (build reports, critiques, verdicts, and the "whys") — to draft a rich, trustworthy PR body. This allows a human reviewer to trust the work without having to re-derive it. This skill is sessionless and lightweight: it runs *within* the active session, scopes the range, drafts the body, gets one confirmation, pushes, runs `gh pr create`, and stops.

This is **not `/snapshot`**. The `/snapshot` skill creates per-checkpoint commits and a ticket comment. The `/pr` skill operates at the **branch-level** — it rolls those checkpoints up into the entire slice of work for review. They compose perfectly: many `/snapshot` checkpoints culminate in one `/pr`. This is a **building block** with a boundary worth stating precisely: it opens the PR, watches it to a named terminal state, and records each review finding's disposition on the thread — and it *never* applies a fix on its own authority and *never* merges. "Complete" therefore extends past the moment the PR opens: the gates must pass and every review comment must carry a reply.

**Trail location:** The active session sets `<trailDir> = <sessionDir>/builds/`. The PR-writer subagent draws deep context from the session's `builds/` trail and log.

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

- **Resolve the tracker config (do this first):** Read CLAUDE.md's `## Tracker` block (the orchestrator sees CLAUDE.md; the subagent does NOT — resolve here, inject in §2). Resolve the **issue-key prefix** (`<PREFIX>` uppercase for keys `<PREFIX>-NNNN` / its lowercase for branches `<prefix>-NNNN-…`) and the **PR base branch** (`<base>`). Finch: prefix `FIN`, base `dev`. **Fallback — no `## Tracker` block** (unconfigured): keep today's behavior — detect a `FIN`-style key (uppercase-alpha prefix + `-NNNN`) from branch/commits/conversation, and default `<base>` to `dev`. Args override § Tracker for the base; the config is never a hard requirement.
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
- **Resolve the Trail:** `<trailDir> = <sessionDir>/builds/`. Pick a `<slug>` (kebab-case of the work or ticket). Before creating a new one, run `ls <trailDir>`. **REUSE** an existing `<slug>_*.md` that matches this work so the PR artifact clusters with the upstream build/snapshot artifacts under one name. Only mint a fresh slug for entirely new work.
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
>   - *If the trail is empty* (no build artifacts for this slug yet): draft from the commits, diff, and ticket, and explicitly note that the "Decisions & rationale" section is thinner because there is no trail to draw from.
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

> **Before dispatching — `§CMD_LOG_SKILL_INVOCATION`**: log this dispatch to the session log (why + context-pack pointer + one-line re-tread) so a restarted session can re-tread it. Fire it as the last step before the `Task`/`Agent` handoff.

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
4. **Request automated reviews + watch the PR to a terminal state (async, non-blocking):** Once the PR exists, request a GitHub Copilot review and poll in the *background* for Copilot, the Codex connector, **and the CI gates** — one loop, all three, so the run isn't blocked. Generic GitHub features; each degrades to a no-op where unavailable.
   - **Derive `<owner>` / `<repo>` / `<n>`** from the PR URL captured above (`github.com/<owner>/<repo>/pull/<n>`).
   - **Request Copilot** (only Copilot is *request-able*): prefer the GitHub MCP tool `request_copilot_review(owner, repo, pullNumber)` (load via `ToolSearch github`). Else `gh api --method POST repos/<owner>/<repo>/pulls/<n>/requested_reviewers -f 'reviewers[]=copilot-pull-request-reviewer[bot]'` (best-effort). If neither is available (no `gh`), skip + note it. Set `COP_EXPECTED=1` in the snippet when the request succeeded, `0` when it was skipped — a `0` tells the loop not to wait for a reviewer that was never asked.
   - **Codex is NOT requested** — the `chatgpt-codex-connector[bot]` is an opt-in connector that reviews on its own and **signals via a 👀 reaction on the PR body** (present while reviewing, *removed* when it posts). So `/pr` can't request it; it detects engagement and waits only when codex is actually engaged.
   - **Completeness has two conditions, not one.** A PR is complete when **the gates pass AND every review comment carries a reply recording its disposition** (§5). Green checks alone are half of it: a PR whose findings sit unanswered leaves the next reader unable to tell a considered rejection from an ignored comment. So the loop counts what is owed on the thread the same way it counts pending checks, and an owed reply keeps the PR out of `PR_COMPLETE`.
   - **The loop runs to a terminal state, and every exit is named.** Reviews landing is not the finish line: a red gate, a merge conflict, a missing required review, or an unanswered finding each leave the PR incomplete, and a poll that stops on reviews alone hands back an unfinished PR described as done. So the loop keeps four questions live at once — did the reviewers speak, are the checks green, is every finding answered, can the PR merge — and exits only into one of these:
     - `PR_COMPLETE` — nothing pending, nothing failing, reviewers settled, every review comment replied to, merge state clear. The only state that may be relayed as done.
     - `PR_CHECKS_RED` — a check failed. Stop and escalate with the check names and their annotations (§4); a red gate needs a decision, not another twenty seconds of waiting.
     - `PR_REPLIES_OWED` — gates pass, findings unanswered. Carries the owed ids (`c<id>` an inline comment, `r<id>` a review body). This is work the caller owes and can do now, which is why it is not a stall and not a block.
     - `PR_DRAFT` — everything else is in order but the PR is still a draft. A draft cannot be complete; flipping it to ready is the caller's call.
     - `PR_BLOCKED` — the PR cannot merge for a reason outside the caller's immediate control. The reason is named (`review_required` · `changes_requested` · `behind_base` · `merge_conflict` · `non_required_check_not_green` · `merge_state_unknown` · `unresolved:<state>`), because "blocked" on its own gives the user nothing to act on. Kept separate from `PR_REPLIES_OWED` on purpose: waiting on a human's approval is not the same obligation as owing that human an answer.
     - `PR_STALLED` — nothing pending and nothing changing. Say that plainly and hand back what it is still waiting on.
     - `PR_POLL_UNAVAILABLE` — no `gh`, or the API is unreachable. A no-op, never a completion.
     There is deliberately no timeout exit: a poll that expires quietly is indistinguishable from a poll that passed, which is how a failing gate stays invisible. The wall-clock bound is a heartbeat — on hitting it the loop reports what it is still waiting on and hands back, and §4 re-arms it when the PR is legitimately still in flight.
   - **How an owed reply is detected.** An inline review comment is answered when some comment carries its id in `in_reply_to_id`; a review *body* has no reply endpoint, so §5 answers it as an issue comment that **names the review id**, and the loop looks for that id in the PR's issue comments. Both are read off the API, so the completeness test is checked rather than asserted.
   - **The head SHA re-arms the watch.** Each tick re-reads `.head.sha`; when it moves, the settle state resets and the loop keeps watching. Addressing findings means pushing commits, which starts a fresh CI run and can start a fresh review round — that push is the exact moment a one-shot poll stops watching, so the ordinary open → findings → fix → push flow is the one that most needs the re-arm.
   - **Poll in the background** — `run_in_background: true`; always exits 0 so you are re-woken with a named state:
     ```bash
     OWNER=<owner>; REPO=<repo>; N=<n>
     COP_EXPECTED=1   # 0 when the Copilot review request was skipped or failed
     RXN="Accept: application/vnd.github.squirrel-girl-preview+json"
     BAD='.conclusion=="failure" or .conclusion=="timed_out" or .conclusion=="cancelled" or .conclusion=="action_required"'
     CR="repos/$OWNER/$REPO/commits"
     command -v gh >/dev/null 2>&1 || { echo "PR_POLL_UNAVAILABLE pr=$N reason=no_gh"; exit 0; }

     head=""; prev=""; quiet=0; unk=0
     for i in $(seq 1 135); do                                  # 20s ticks; the 45-min bound is a heartbeat, not a verdict
       sha=$(gh api "repos/$OWNER/$REPO/pulls/$N" --jq '.head.sha' 2>/dev/null)
       [ -n "$sha" ] || { echo "PR_POLL_UNAVAILABLE pr=$N reason=api_unreachable"; exit 0; }
       if [ "$sha" != "$head" ]; then head="$sha"; quiet=0; fi  # a fix push re-arms the watch

       pending=$(gh api "$CR/$sha/check-runs?per_page=100" --jq '[.check_runs[]|select(.status!="completed")]|length' 2>/dev/null || echo 0)
       failed=$(gh api "$CR/$sha/check-runs?per_page=100" --jq "[.check_runs[]|select($BAD)]|length" 2>/dev/null || echo 0)
       if [ "$failed" -gt 0 ]; then
         names=$(gh api "$CR/$sha/check-runs?per_page=100" --jq "[.check_runs[]|select($BAD)|.name]|join(\", \")" 2>/dev/null)
         ids=$(gh api "$CR/$sha/check-runs?per_page=100" --jq "[.check_runs[]|select($BAD)|.id|tostring]|join(\" \")" 2>/dev/null)
         echo "PR_CHECKS_RED pr=$N head=$sha failing=$failed names=\"$names\" run_ids=\"$ids\" pending=$pending"; exit 0
       fi

       cop=$(gh api "repos/$OWNER/$REPO/pulls/$N/reviews" --jq '[.[]|select(.user.login=="copilot-pull-request-reviewer[bot]")]|length' 2>/dev/null || echo 0)
       cdx=$(gh api "repos/$OWNER/$REPO/pulls/$N/reviews" --jq '[.[]|select(.user.login=="chatgpt-codex-connector[bot]")]|length' 2>/dev/null || echo 0)
       eyes=$(gh api "repos/$OWNER/$REPO/issues/$N/reactions" -H "$RXN" --jq '[.[]|select(.content=="eyes" and .user.login=="chatgpt-codex-connector[bot]")]|length' 2>/dev/null || echo 0)
       ok=$(gh api "repos/$OWNER/$REPO/issues/$N/reactions" -H "$RXN" --jq '[.[]|select(.content=="+1" and .user.login=="chatgpt-codex-connector[bot]")]|length' 2>/dev/null || echo 0)

       cop_done=0; if [ "$COP_EXPECTED" -eq 0 ] || [ "$cop" -gt 0 ]; then cop_done=1; fi
       cdx_done=0
       if [ "$cdx" -gt 0 ] || [ "$ok" -gt 0 ]; then cdx_done=1; fi                                          # posted a review, or a clean +1
       if [ "$eyes" -eq 0 ] && [ "$cdx" -eq 0 ] && [ "$ok" -eq 0 ] && [ "$i" -ge 3 ]; then cdx_done=1; fi   # never engaged after ~1min

       if [ "$pending" -eq 0 ] && [ "$cop_done" -eq 1 ] && [ "$cdx_done" -eq 1 ]; then
         # completeness condition 2: every finding carries a reply recording its disposition
         PC="repos/$OWNER/$REPO/pulls/$N"
         tops=$(gh api --paginate "$PC/comments?per_page=100" --jq '.[]|select(.in_reply_to_id==null)|.id' 2>/dev/null)
         reps=" $(gh api --paginate "$PC/comments?per_page=100" --jq '.[]|select(.in_reply_to_id!=null)|.in_reply_to_id' 2>/dev/null | tr '\n' ' ') "
         revs=$(gh api --paginate "$PC/reviews?per_page=100" --jq '.[]|select((.body//"")!="")|.id' 2>/dev/null)
         blob=" $(gh api --paginate "repos/$OWNER/$REPO/issues/$N/comments?per_page=100" --jq '.[].body' 2>/dev/null | tr '\n' ' ') "
         owed=0; owed_ids=""
         for id in $tops; do case "$reps" in *" $id "*) ;; *) owed=$((owed+1)); owed_ids="$owed_ids c$id" ;; esac; done
         for id in $revs; do case "$blob" in *"$id"*)      ;; *) owed=$((owed+1)); owed_ids="$owed_ids r$id" ;; esac; done
         if [ "$owed" -gt 0 ]; then                             # checked before merge state: this is work the caller owes now
           echo "PR_REPLIES_OWED pr=$N head=$sha owed=$owed ids=\"${owed_ids# }\""; exit 0
         fi

         ms=$(gh api graphql -f query="{repository(owner:\"$OWNER\",name:\"$REPO\"){pullRequest(number:$N){mergeStateStatus mergeable reviewDecision isDraft}}}" \
                --jq '.data.repository.pullRequest|"\(.mergeStateStatus) \(.mergeable) \(.reviewDecision) \(.isDraft)"' 2>/dev/null)
         [ -n "$ms" ] || ms="UNKNOWN UNKNOWN UNKNOWN false"     # an unreadable merge state is never reported as complete
         set -- $ms; state=$1; able=$2; rvw=$3; draft=$4
         if [ "$state" = "UNKNOWN" ] && [ "$unk" -lt 3 ]; then  # GitHub computes merge state lazily; re-ask for ~1 min
           unk=$((unk+1)); sleep 20; continue
         fi

         case "$state" in
           CLEAN|HAS_HOOKS) echo "PR_COMPLETE pr=$N head=$sha copilot=$cop codex_review=$cdx codex_ok=$ok replies_owed=0 merge_state=$state"; exit 0 ;;
           DRAFT) echo "PR_DRAFT pr=$N head=$sha copilot=$cop codex_review=$cdx replies_owed=0 mergeable=$able"; exit 0 ;;
         esac
         case "$state:$able:$rvw" in                            # first match wins; order is the priority
           *:CONFLICTING:*)       why=merge_conflict ;;
           BEHIND:*:*)            why=behind_base ;;
           DIRTY:*:*)             why=merge_conflict ;;
           UNSTABLE:*:*)          why=non_required_check_not_green ;;   # no failing check run, so: a red legacy commit status
           *:*:CHANGES_REQUESTED) why=changes_requested ;;
           *:*:REVIEW_REQUIRED)   why=review_required ;;                # readable even when merge state is not
           UNKNOWN:*:*)           why=merge_state_unknown ;;            # GitHub could not compute the merge commit
           *)                     why="unresolved:$state" ;;
         esac
         echo "PR_BLOCKED pr=$N head=$sha reason=$why merge_state=$state mergeable=$able review=$rvw copilot=$cop codex_review=$cdx replies_owed=0"; exit 0
       fi

       now="$sha|$pending|$failed|$cop|$cdx|$eyes|$ok"
       if [ "$now" = "$prev" ]; then quiet=$((quiet+1)); else quiet=0; fi
       prev="$now"
       if [ "$pending" -eq 0 ] && [ "$quiet" -ge 15 ]; then
         echo "PR_STALLED pr=$N head=$sha reason=no_change_5min waiting_on=reviews copilot=$cop codex_review=$cdx pending=0"; exit 0
       fi
       sleep 20
     done
     echo "PR_STALLED pr=$N head=$head reason=heartbeat_45min pending=$pending failed=$failed copilot=$cop codex_review=$cdx"; exit 0
     ```
     **Sizing:** 20s ticks. The heartbeat sits at 45 min because gating on CI means outlasting a real build *and* the re-armed run a fix push starts — a full build on this repo runs around five minutes, so the bound holds several sequential rounds rather than a single one. The quiet escalation is separate and much shorter: nothing pending and nothing changing for five minutes is a stall, not a slow build. **The 👀 gate**: while codex's eyes reaction is present the loop keeps waiting for its review; if codex never reacts within ~1 min (no eyes, no review, no +1) the loop stops waiting on codex — it isn't engaged on this PR. Give the Bash call a wake `description` — e.g. `PR <n> watch — on wake, relay checks + Copilot + Codex (§4)`.
     **Coverage note:** `check-runs` covers GitHub Actions and check-run integrations; a legacy commit *status* does not appear there. `mergeStateStatus` catches those as `UNSTABLE`, which the loop surfaces as `non_required_check_not_green` rather than as green.
5. **Report & Trail:** Stamp `<trailDir>/<slug>_PR.md` with the final outcome (PR URL, branch, base, draft/ready, gate flags). Provide the link to the user; note the PR watch is running — checks, Copilot and Codex — and that you will relay its named state when it lands (§4). **Optionally announce the PR on the linked ticket:** when a sibling agent (or a later session) would want to know the branch shipped, offer to post a short "PR opened: `<url>` — `Closes <PREFIX>-NNNN`" comment on the ticket. If you do, route it **through `§CMD_POST_TICKET_COMMENT`** (the canonical subscribe-check → `save_comment` → `engine ticket notify` atom, per `¶INV_TICKET_COMMENT_VIA_CMD`) so the sibling-notify fires — never a bare `save_comment`. Offer, don't force; skip when no ticket is linked. **Offer council (optional, `§CMD_OFFER_COUNCIL_REVIEW`):** offer a `/council` panel on the PR diff (`subject: pr <n>` — immutable via `gh pr diff`), dispatched in the background report-only so it runs parallel with the PR watch and is relayed when it lands. Offer, never force. **Feed the ledger:** append one terse bullet to `<trailDir>/LESSONS.md` (e.g., "PR opened, URL, closes `<PREFIX>-NNNN`") via `engine log`. **Then stop** (the background watch re-wakes you for §4, and §5 records the dispositions). Deciding each finding, applying any fix, and merging are your call, not this skill's. **Never merge.**

## 4. Relay the Checks and the Automated Reviews (on background-watch completion)

When the §3 watch re-wakes you, it carries one named state. Relay **the checks and the reviews together** — a failing gate is at least as actionable as a review nit, and a relay that mentions only reviewers reproduces the blindness this section exists to close. Report the `merge_state` / `reason` in every relay so the user sees whether the PR can actually merge.

**Say the state, never a word that sounds more finished than it is.** `PR_COMPLETE` is the only state that may be relayed as done. For every other state, lead with the failing, owed or blocking fact; the review findings come after it.

**On `PR_CHECKS_RED` — escalate with the offending lines, not a job URL.** The signal carries `names=` and `run_ids=`. For each id, pull the annotations: a `path:line — message` list turns a fix into a two-minute edit, whereas a link to the job makes the user re-derive what the watch already knows.
```bash
gh api "repos/<owner>/<repo>/check-runs/<check_run_id>/annotations" \
  --jq '.[]|"\(.path):\(.start_line) [\(.annotation_level)] \(.title) — \(.message)"'
```
Relay per failing check: its name, then its annotations. When a check exposes no annotations, say so and give its `details_url` (`gh api "repos/<owner>/<repo>/commits/<head>/check-runs?per_page=100" --jq '.check_runs[]|select(.id==<id>)|.details_url'`). Then offer `/fix`; re-arm the §3 watch after the fix push so the fresh CI run is watched too.

**On `PR_REPLIES_OWED`** — the gates pass and findings sit unanswered. Relay the findings (below), take the caller's disposition for each, then post the replies per §5 and re-arm the watch. This is the ordinary path, not an exception: a first watch on a reviewed PR almost always lands here.

**On `PR_BLOCKED`** — name the reason in the user's words: a required review is missing, the branch is behind base, the branch conflicts, changes were requested, a non-required check is not green, GitHub cannot compute the merge commit. Say what unblocks each; `/pr` does not merge, rebase, or approve.

**On `PR_DRAFT`** — everything else is in order and the PR is still a draft. Offer to flip it to ready; do not flip it unasked.

**On `PR_STALLED`** — say exactly that nothing has moved and what it was still waiting on. Do not present it as a pass. Offer to re-arm the watch or to stop watching.

**Disclose the review findings through `§CMD_ELICIT` rather than dumping a flat list** — automated reviewers are indiscriminate, so render each finding as a Decision Card (what's-at-stake · complexity · how-to-verify · advisory engagement, with a defeasible `my lean`) and lead with the triaged summary ("N worth addressing, M FYI") so the user sees which findings matter against which are noise. Label each card by reviewer (Copilot / Codex). `§CMD_ELICIT` **discloses + classifies attention**; the address/reject/defer choice (and any `/scrutinize`·`/fix` chain) is the caller's own. `/pr` applies no fix on its own authority — what it does with the outcome is record it on the thread (§5).

**A finding is a claim, not an instruction.** Automated reviewers routinely ask for handling of an edge case the application cannot reach, flag a pattern the codebase chose deliberately, or assert something about the code that is not true. So:
- **Evaluate each finding against the code before acting on it.** A finding whose premise is false, or whose edge case is unreachable, is **rejected with the reason** — a complete and correct outcome, not a skipped task.
- **Present "reject, because X" as a first-class option on every card**, alongside address and defer, carrying the evidence for the rejection. A reader who sees only address/defer will treat noise as work.
- **Never apply a change solely because a reviewer asked for it.** Verify the claim first, then address it, defer it, or reject it with a reason.
- Where a rejection is worth the reviewer knowing, replying on the PR thread with the reason is the right move — offer it, never do it automatically.
One live run illustrates the spread: on a single PR the same reviewers produced a finding that was real and load-bearing (a header claiming a completeness the file did not have, falsified against `package.json`), a finding that was real but pre-existing and untouched by the change, and a pair that were spelling preference. Same reviewer, same run, different correct responses — a uniform to-do list destroys that distinction.

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
  - **Codex clean pass** (`codex_ok=`>0 with `codex_review=0`): no written review — relay "Codex reviewed and approved (👍, no written findings)." This speaks for the reviewer only; it says nothing about the gates.
- **`PR_POLL_UNAVAILABLE`:** say the watch could not run and why (`no_gh` / `api_unreachable`). The PR is open; nothing was observed, so claim nothing about it.
- Once every finding has a disposition, go to **§5** and record them on the thread. Offer, don't auto-run, the rest: `/scrutinize` to triage the findings or `/fix` to address a red gate or an accepted finding. Applying a fix is the user's call; posting the disposition is not optional.

## 5. Record Each Disposition on the PR Thread

Every review comment gets a reply saying what happened to it. A PR thread where some findings were fixed and others silently passed over reads identically to one where nobody looked: **silence and disagreement are indistinguishable on a PR thread**, so the reply is the only durable record that a finding was considered. This is also the second half of the completeness test in §3 — an unanswered finding keeps the PR out of `PR_COMPLETE`.

**Replies go out after the caller has decided each finding, never before.** Do not invent a disposition to have something to post; where the caller has not decided, the reply is not written and the PR is not complete. Post one reply per finding, in the caller's decided terms:

- **Accepted** — what changed and where: the file and line, or the commit. "Fixed in `path/to/file.ts:42`" beats "done".
- **Rejected** — why, with the evidence that falsifies the finding: the code path that cannot be reached, the value that is already guaranteed, the deliberate choice and where it is written down. This is the highest-value reply of the three, because it is the only record that the finding was weighed rather than dropped.
- **Deferred** — that it is deferred and where it went: the ticket key, the followup section of the PR body, the file it was noted in. A deferral with no destination is a rejection wearing a friendlier word.

**Where each reply goes:**
- **An inline review comment** (`c<id>` in the `PR_REPLIES_OWED` signal) is replied to in its own thread. Prefer the GitHub MCP tool `add_reply_to_pull_request_comment` (load via `ToolSearch github`). Else:
  ```bash
  gh api --method POST "repos/<owner>/<repo>/pulls/<n>/comments/<comment_id>/replies" \
    --field body="<the disposition>"
  ```
- **A review body** (`r<id>`) has no reply endpoint — GitHub offers no per-review reply. Answer it as an issue comment on the PR that **names the review id**, which is what makes the answer detectable in §3's completeness count:
  ```bash
  gh api --method POST "repos/<owner>/<repo>/issues/<n>/comments" \
    --field body="Answering review <review_id> — <the dispositions>"
  ```
  A review body carrying no findings is answered in one line saying so; it still needs the answer, because the count cannot tell an empty review from an ignored one.
- **Body text goes through `--field`, never interpolated into the command string.** A rejection quotes code, and a body spliced inline lets backticks and `$` reach the shell — the same command-substitution hazard that makes `--body-file` mandatory in §3.

**Degradation:** no `gh` and no GitHub MCP means no replies. Say so plainly, name the findings that went unanswered, and report the PR as incomplete — never as done, and never with the replies claimed as posted.

**Then re-arm the §3 watch.** With the replies posted, the owed count is zero and the watch can reach `PR_COMPLETE` — or surface whatever else is still in the way.

## Constraints (Summary)
- **The PR is watched to a named terminal state — checks, reviewers, replies owed, mergeability:** after the PR opens, `/pr` requests a Copilot review and runs one background watch (re-woken via `run_in_background`) covering Copilot (requested), the Codex connector (opt-in — detected via its 👀 reaction, so `/pr` waits only when codex is engaged), the head commit's check runs, the unanswered-finding count, and `mergeStateStatus`. It exits only into `PR_COMPLETE`, `PR_CHECKS_RED`, `PR_REPLIES_OWED`, `PR_DRAFT`, `PR_BLOCKED`, `PR_STALLED` or `PR_POLL_UNAVAILABLE` — there is no quiet timeout, because a poll that expires reads exactly like a poll that passed. A head-SHA change re-arms the watch, so the fix push that follows a round of findings is watched rather than abandoned. `/pr` then RELAYS: failing check names with their `check-runs/<id>/annotations` as `path:line — message`, the merge state, the owed findings, and both review sets. It re-runs no gate and merges nothing. Missing `gh`/MCP or a reviewer that isn't enabled degrades to a no-op, never to a completion.
- **A PR is complete only when the gates pass AND every review comment has a reply:** green checks are half the test. The owed count is read off the API — an inline comment is answered when a comment carries its id in `in_reply_to_id`, a review body when an issue comment names the review id — so completeness is checked, not asserted.
- **Only `PR_COMPLETE` may be relayed as done:** a red gate, an owed reply, a draft, a blocked merge state, or a stall is reported by its named reason, leading the relay. No wording that sounds finished may cover a failing check or an unanswered finding.
- **Every finding's disposition is posted to the thread, after the caller decides it:** accepted says what changed and where, rejected says why with the evidence, deferred says where it went. Replies go to the inline comment's own thread (`pulls/<n>/comments/<id>/replies`) or, for a review body, to an issue comment naming the review id. `/pr` invents no disposition to have something to post, and where `gh`/MCP is missing it reports the findings unanswered and the PR incomplete rather than claiming replies it did not post.
- **A review finding is a claim to verify, not an instruction to obey:** each finding is checked against the code before anything is done with it, and one whose premise is false or whose edge case is unreachable is rejected with the reason — presented as a first-class option on the decision card alongside address and defer. Never apply a change solely because a reviewer asked; verify it, then address, defer, or reject with a reason.
- **Base from § Tracker (`dev` for finch), never `main` directly:** Resolve the PR base from CLAUDE.md § Tracker (defaulting to `dev` when absent). Overridable only by explicit arguments.
- **No history rewriting / no live-tree mutation:** No `rebase`, `reset`, `amend`, `push --force`, `stash`, or `switch -c` on the live tree. **The cherry-pick mechanism is `git worktree`** — a focused pick builds a NEW branch off base in a throwaway worktree and never touches the source branch or the working checkout. Abort (`--abort` + `worktree remove --force`) on any cherry-pick conflict; never force-resolve. The worktree-unavailable fallback requires a clean tree and restores the original branch as its last step.
- **Push is fast-forward-only:** Fetch and check ahead/behind before confirming. Surface divergence; a plain push (never `--force`) is rejected non-fast-forward if behind — let the user reconcile or take the clean fresh-branch path; never auto-`pull`/`rebase`.
- **Context-aware branch choice is surfaced, never silent:** Always offer push-whole vs. cherry-pick-the-target on mixed branches. Untagged/merge commits are shown as their own bucket and excluded from focused picks (merge commits force the whole-branch path); the user decides.
- **One confirm before push + PR:** Nothing pushes or opens a PR without the explicit confirm; push/PR happen only on "Create".
- **Body via `--body-file`, NEVER inline:** The subagent writes the body to `<trailDir>/<slug>_PR.md`, the orchestrator appends the trailer to that file and creates with `--body-file`; `--title` stays a short sanitized single value. Inline `--body "…"` is forbidden (backtick/`$` shell-substitution risk).
- **Gates flagged, not run:** `/pr` detects + flags any special CI gates the project documents (e.g. in CLAUDE.md/CONTRIBUTING.md) as a reviewer heads-up in the body; it does NOT run build/lint (CI does). It never claims a verification not present in the trail.
- **Building block — opens, watches, records; never fixes on its own authority, never merges:** It creates the PR (draft or ready), watches it to a named terminal state, and posts each finding's decided disposition. Deciding a finding, applying a fix, flipping draft to ready, and merging stay the caller's.
- **Claude Code trailer:** Must end every PR body.
- **Lightweight + sessionless:** Scope → draft → confirm → push + create → watch → relay → record dispositions. The PR-writer subagent stays read-only; all git/`gh` mutations are the orchestrator's, and each is gated — the push and PR on the §3 confirm, every reply on the caller's decision for that finding.
