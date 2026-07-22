---
name: probe
description: "Quick, read-only investigation delegated to a subagent: state an INTENT (a question you need answered) and it goes and finds out — sweeping the codebase, the database (read-only SELECTs), and tickets (Linear) as the question demands, thinking in the /analyze notebook schemas, then writing an answer-first Probe Report of ranked, evidence-backed findings. You then walk the findings and decide each one's fate (capture / dig deeper / defer / dismiss). The lightweight delegated counterpart to /analyze. A building block: it investigates and reports, never edits code, writes data, or files tickets. Triggers: \"probe this\", \"go find out about X\", \"quick investigation\", \"what's the story with Y\", \"scope this out before I decide\", \"dig up what we know about Z\"."
version: 1.0
tier: lightweight
args: "[<intent / the question to investigate>] [-- <what a good answer looks like / source hints>]"
---

Answer a question by *sending someone to find out*. `/probe` takes an **intent** — a question you need settled before you can decide something — and hands it to a background subagent that investigates across whatever sources the question actually needs: the **codebase**, the **database** (read-only), and **tickets**. It comes back with an answer-first **Probe Report** of ranked findings, each standing on evidence you can re-derive, which you then triage finding-by-finding.

This is the **fast, hands-off, read-only counterpart to `/analyze`**. Where `/analyze` is a heavy interactive session (phases, calibration, synthesis) that you sit *inside*, `/probe` is a dispatch — you ask, it goes, it reports. And where `/experiment` *writes and runs* code to test a hypothesis, `/probe` only *reads*. As a **building block**, it produces a briefing, not a change: it never edits code, never writes to the database, never files a ticket, never commits. It investigates, reports, triages, and stops. What happens next — `/ticket` to capture, `/analyze` or `/experiment` to go deeper, `/fix` to repair — is your call, not this skill's.

*Crucial constraint:* `/probe` does NOT own a session. It reads the *active* session's context and writes its paper trail directly into that session's folder.

# /probe Protocol

## 1. Frame the Intent, Sources & Trail

**A. The Intent** (what you need to know)
Resolve the question from the arguments, else the active session / recent conversation. State it as **a question that has an answer**, not a topic to muse on. Text after `--` sharpens what a good answer looks like and may hint at sources.
*(Illustrative — adapt, don't copy: "Why do ~5% of policy snapshots have no coverages?" / "Is the flat detector already handling multi-page rooms, or is that the gap this ticket assumes?" / "What have we already tried for Gemini truncation, and where did it land?")*

*Constraint:* If you cannot state the intent as a single answerable question in one sentence, ask ONE `AskUserQuestion` to pin it. A vague intent produces a vague report — the whole skill hinges on this.

**B. The Sources** (where the answer lives)
Decide which sources the intent actually needs — this drives §2's dispatch:
- **Code / files** — the repo: implementation, tests, fixtures, docs, prior session artifacts.
- **Database** — **read-only `SELECT`s**, for questions about real data shape, scale, or anomalies (row counts, distributions, outliers).
- **Tickets** — Linear (via MCP), for prior and parallel work: what's been tried, what was decided, what's in flight.

Name the in-scope sources explicitly, and state the **read-only boundary**: no code edits, no DB writes, no ticket writes, no commits.

**C. The Trail**
Set `<trailDir> = <sessionDir>/builds/`. Mint a short, kebab-case `<slug>` from the intent (e.g. `snapshot-missing-coverages`, `flat-detector-multipage`).
*Crucial:* Before minting a new slug, run `ls <trailDir>`. If an existing `<slug>_*.md` clearly matches this work (same chunk / ticket / topic), REUSE that slug so the probe clusters with the `/build`, `/scrutinize`, and `/experiment` artifacts for the same work. Ledger/log appends (§5) use `engine log`.

**Acknowledge:** Echo back your setup in exactly one line:
`Probing: <intent> — sources: <code|db|tickets>; trail: <trailDir>/<slug>_PROBE.md.`

## 2. Dispatch the Investigator(s) — Adaptive

**Backgroundable & parallelizable.** This sub-agent dispatch is a composable building block: it can run in the background (`run_in_background: true`) so the orchestrator keeps working while it runs, and when the work splits into independent chunks, several such sub-agents can be fanned out in parallel and reconciled.

**Topology — default ONE, fan out only when genuinely broad.** Spawn **one** `analyzer` subagent that spans every in-scope source. Fan out to parallel per-source subagents **only** when two or more of {a deep code read, a substantial DB investigation, a real ticket-history dig} each carry enough work to stand alone **AND** can be pursued independently.
- *Fan out when:* the sources answer **different sub-questions**, or one agent would exhaust its context on the first source before ever reaching the others.
- *Do NOT fan out when:* the question is narrow, or one source's findings determine what to look for in the next (**sequential dependence → one agent**, always).
- When you fan out, give each agent the SAME intent but its OWN source + sub-question, then reconcile their reports into one ranked set in §3.
- **Fan-out report paths (or they WILL clobber each other).** §4's contract names a single `<trailDir>/<slug>_PROBE.md`. Hand that path to two parallel agents and the second writer silently destroys the first's report. When fanning out, give each agent its OWN path — `<trailDir>/<slug>-<source>_PROBE.md` (e.g. `<slug>-git_PROBE.md`, `<slug>-linear_PROBE.md`) — and reserve the bare `<trailDir>/<slug>_PROBE.md` for YOUR reconciled report, which cites the halves.

State which topology you chose, in one line, with the reason.

**Use the wait — don't idle.** When you background the investigator, spend that time getting a step ahead so the moment the report lands you move straight into triage rather than starting cold. Concretely: (a) **anticipate the findings** — from the intent, predict the likely answers and pre-think which would be capture-worthy vs. dig-worthy; (b) **surface open questions to the user now** (`AskUserQuestion`) — anything about scope, what they'd act on, or what they already suspect — so their answers are in hand when triage starts; (c) **prep the next move** — line up the likely `/ticket` framing or follow-up probe. Don't block waiting; the completion notification brings you back to §3 with momentum.

Build the subagent's prompt to be entirely self-contained — it cannot see your memory or the session history:

> You are an **investigator sent to find something out**. Your job is to ANSWER a question with hard evidence — not to summarize a topic, and not to fix anything. You are strictly READ-ONLY.
>
> **1. The Mission**
> - **Intent (the question):** `<intent>`
> - **A good answer looks like:** `<whatGoodLooksLike>`
> - **Sources in scope:** `<sources>` — use the ones that actually carry the answer; ignore the rest. Report which you used.
> - **Starting pointers:** `<known files / tables / ticket IDs / session artifacts / prior LESSONS.md facts>`
>
> **2. Rules of Engagement (READ-ONLY — hard)**
> - **Change nothing.** No code edits, no file writes outside your report, no `INSERT`/`UPDATE`/`DELETE`/DDL, no ticket creates/comments/status changes, no commits. If answering the question seems to require a write, that is a **finding to report**, not an action to take.
> - **Database (if in scope):** `SELECT` only, always bounded (`LIMIT`, aggregates, explicit date windows). Prefer a read-only/analyst connection; never run destructive or shared-state commands (`db:reset`, `db:migrate`, drops/deletes); never point at prod destructively. Paste the EXACT query and the ACTUAL rows/counts it returned.
> - **Tickets (if in scope):** read via the Linear MCP tools — load them with `ToolSearch` (e.g. `select:mcp__linear-server__list_issues,mcp__linear-server__get_issue,mcp__linear-server__list_comments`). Read only: never create, update, or comment.
> - **Git safety (`¶INV_NO_DESTRUCTIVE_GIT`):** the tree is ALWAYS dirty with other agents' uncommitted work. NEVER run tree/index-destructive git — no `git stash`/`checkout`/`switch`/`restore`/`reset --hard`/`clean`/`rm`/`add`. Read committed versions with `git show HEAD:<path>`; open working files by explicit path. Read-only git (`status`, `log`, `diff`, `show`) is fine. A PreToolUse hook blocks the rest — if it blocks you, do NOT retry-to-bypass; STOP and report the blocker.
>
> **3. How to Investigate**
> - **Follow the evidence, converge fast.** Chase the threads the question genuinely needs — branch a sub-probe if a side-question blocks the main one — then converge on ONE answer. This is a *quick* probe: prefer the shortest path to decisive evidence over exhaustive coverage.
> - **Think in the notebook.** `<LOGGING>`
> - **Show, don't tell.** Every finding stands on evidence the reader can re-derive: `file:line`, the exact query → the actual rows, the ticket ID + what it actually says. Never paraphrase a result you could quote. A finding with no evidence is an opinion — label it as one or cut it.
> - **Confidence is part of the finding.** State high/medium/low, and state what would raise it.
> - **Answer the question that was asked.** If the honest answer is "the evidence doesn't settle it," say exactly that plus what WOULD settle it — an honest unknown beats a confident guess and is a fully successful probe. If you discover the question was the wrong one, say so, then answer the right one.
> - **Escalate, don't fake.** If a source is inaccessible (no DB credentials, no MCP, permissions), report it as a blocker rather than guessing around it. Never manufacture a result.
>
> **4. Output Contract**
> WRITE your report to `<REPORT_PATH>` using the Probe Report template (this skill's `assets/TEMPLATE_PROBE.md` — the orchestrator gives you its base dir; **do not hardcode `~/.claude`**). Fill EVERY field: intent, the **direct answer** (lead with it), sources probed + how + what you skipped, **ranked findings** (each: title, where, evidence, significance, confidence, suggested next step), **blind spots**, **reusable facts**, and **open threads**. Then RETURN a 4–6 line summary + the report path + the **numbered ranked finding titles** (the orchestrator triages by these numbers). Do NOT dump the full findings into your return message — the orchestrator reads the file.

**Substituting `<REPORT_PATH>`:** single agent → `<trailDir>/<slug>_PROBE.md`. Fanned out → each agent gets its own `<trailDir>/<slug>-<source>_PROBE.md`, per the topology rule above. Always hand the agent the **fully-substituted absolute path**, never a placeholder to fill.

**Substituting `<LOGGING>`:** replace it with the concrete command — append your thinking stream via `engine log <the active session's log path>` every ~5 tool calls, using the notebook schemas in this skill's `assets/TEMPLATE_PROBE_LOG.md` (Discovery / Weakness / Connection / Spark / Gap / Pattern / Tradeoff / Assumption / Strength). Tell the agent plainly: **a heartbeat hook BLOCKS after 10 tool calls without a log**, and the notebook is the raw material the report synthesizes — a thin log makes a thin report.

**Before dispatching — `§CMD_LOG_SKILL_INVOCATION`**: log this dispatch to the session log (why + context-pack pointer + one-line re-tread) so a restarted session can re-tread it. Fire it as the last step before the `Task`/`Agent` handoff.

Dispatch to the background by default (`run_in_background: true`) so you keep working while it runs and are notified when it lands. Run it in the **foreground** only if you need the answer before your very next step.

## 3. Report Intake & Relay

Read the report. If you fanned out, **reconcile** the parallel reports into one ranked set first: dedupe overlapping findings, keep the strongest evidence for each, and surface any place where two agents' evidence disagrees (a contradiction is itself a finding).

**Spot-check the load-bearing evidence.** Don't re-run the whole probe — but don't take the headline on faith either. For the finding(s) the answer actually rests on, re-run the exact query or open the cited `file:line` yourself. A probe's entire value is that its evidence holds; a fabricated row count or a misread line poisons every decision made downstream of it. Explicitly flag any claim you could not confirm.

**Relay, answer-first.** The user asked a question — lead with the answer and its confidence, not with process. Then give the **numbered, ranked findings** (title + a one-line essence each — the user triages by these numbers), then the blind spots. Keep it tight; the full report is on disk. Link it (`§CMD_LINK_FILE`).

## 4. Triage — Walk the Findings with the User

The interactive `AskUserQuestion` walkthrough is where a probe turns into a decision. The user, not the model, decides each finding's fate. Run it explicitly. NEVER dump findings as bare text and assume the user's intent.

This is `§CMD_WALK_THROUGH_RESULTS`. Do NOT use the `§CMD_TAG_TRIAGE` default — use the probe decision set below.

**The Walkthrough Routine:**

1. **Granularity Gate (1x `AskUserQuestion`):**
   Ask: "How do you want to walk the N findings?" (`§ASK_WALKTHROUGH_GRANULARITY`). Options (single-select):
   - **Each:** One at a time.
   - **Groups:** Batches of 4.
   - **Smart:** ≤4 → Each, 5–12 → Groups.
   - **Top-N:** By significance (e.g. just the top 3).
   - **None:** Accept the report as-is; skip to §5.

2. **Per-Finding Evaluation (Context Block + `AskUserQuestion`):**
   For each finding (or batch), present a mandatory 2-part context block in chat (`§FMT_CONTEXT_BLOCK`):
   *   `Line 1:` `[#]: <title> — <where>, <confidence>`
   *   `Line 2:` `<what the evidence shows> | <why it matters> | <suggested next step>`
   *(Illustrative — adapt, don't copy: `[1]: Snapshots with no coverages are all pre-cutover — claim_policy_snapshot, HIGH` | `Query returns 0 post-2026-01 rows with empty coverages; all 412 predate the migration. Means this is a backlog cleanup, not a live bug. Suggest: capture as a cleanup ticket.`)*

   Then call `AskUserQuestion` with the finding number as the header and this option tree:
   - **Capture** — worth a ticket. Collected for a `/ticket` handoff in §5.
   - **Dig deeper** — the probe surfaced it but did not settle it. Collected for `/analyze` (read deeper) or `/experiment` (hands-on test) — propose which, based on whether the open question needs *reading* or *running*.
   - **Defer** — real, but not now. Tag/track it (`#needs-X`) if the project uses tags.
   - **Dismiss** — acknowledged, no action (record the user's reason if given).
   - **Discuss** — needs more detail, or you disagree. Answer in chat, then re-present this finding.

3. **Batch Shortcuts:**
   Honor natural language shortcuts immediately, without further questions ("capture the top 2, dismiss the rest", "defer all the lows", "dig into #3 only"). Apply them to all remaining findings.

**Assemble the outcome:** the per-finding fates plus any user amendments. Significance is the probe's *advice*; the fate is the user's *call*.

## 5. Next Steps (Ask — Don't Auto-Chain) & Trail

**Execute the fates by offer, never automatically.** Present the collected outcomes and offer the chains via `AskUserQuestion` — the user decides whether to run them now, later, or not at all:
- **Captured** → `Skill(ticket, "<the findings to file>")` — one `/ticket` run can carry several findings.
- **Dig deeper** → `Skill(analyze, "<the open question>")` or `Skill(experiment, "<the hypothesis>")`.
- **Deferred** → apply the tag / note it in the session artifact.

*Crucial:* keep the human gate. Do NOT auto-execute a chain.

**Append to the trail.** APPEND the triage outcome (per-finding fate + reason) to `<trailDir>/<slug>_PROBE.md`. Append rather than rewrite, so a killed or resumed run never loses history. The report persists even on a partial or blocked probe. Link the files in chat (`§CMD_LINK_FILE`).

**Feed the ledger (compounding loop).** Append the durable answers to `<trailDir>/LESSONS.md` as terse bullets — the settled facts, not the narrative — via `engine log`.
*(Illustrative — adapt, don't copy: "Empty-coverage snapshots are all pre-cutover phantoms (412 rows, none post-2026-01) — cleanup command already exists.")*
The next `/build`, `/probe`, or `/analyze` reads these, so a settled answer shapes the next handoff instead of evaporating.

Then **stop**. `/probe` answers, reports, and triages — nothing more.

## Constraints
- **Read-only, absolutely.** No code edits, no `INSERT`/`UPDATE`/`DELETE`/DDL, no ticket writes, no commits, and no tree/index-destructive git (`¶INV_NO_DESTRUCTIVE_GIT` — the tree is always dirty with other agents' uncommitted work). A write the answer seems to require is a **finding**, not an action.
- **Building block — answers, never advances.** It produces a briefing plus triage decisions, then stops. Capturing is `/ticket`'s job; repairing is `/fix`'s; heavy interactive study is `/analyze`'s; hands-on proof is `/experiment`'s.
- **An intent, not a topic.** Never dispatch without a single answerable question and what a good answer looks like. A vague intent yields a vague report — pin it with one `AskUserQuestion` instead.
- **Evidence or it didn't happen.** Every finding carries re-derivable evidence (`file:line`, exact query → actual rows, ticket ID) plus a confidence. The orchestrator spot-checks the load-bearing ones rather than trusting the headline.
- **Adaptive dispatch.** One subagent by default; fan out per-source only when the intent genuinely spans multiple heavy, independent sources. Sequential dependence between sources means one agent.
- **Honest unknowns.** "The evidence doesn't settle it, and here's what would" is a fully successful probe. Never manufacture a confident answer or guess around an inaccessible source — report the blocker.
- **User owns the fate.** Significance is advice; capture / dig / defer / dismiss is the user's call via `AskUserQuestion`. Chains are offered, never auto-run.
- **Paper trail always.** The Probe Report persists even on partial or blocked runs; triage outcomes append to it; durable answers compound into `LESSONS.md`.
- **Quick means quick.** Prefer the shortest path to decisive evidence over exhaustive coverage. If the question genuinely needs a heavy interactive deep-dive with calibration rounds, that's `/analyze` — say so and hand it over.
