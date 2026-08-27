---
name: ticket-search
description: "Surface RELATED and DUPLICATE Linear tickets for the work in front of you, before you build. A read-only subagent runs `engine ticket-search` (standalone) or navigates the startup SRC_RELATED_TICKETS candidates (session-startup), deep-reads each promising ticket via §CMD_READ_RELATED_TICKET (full body + state + comments, kept inside the subagent so ticket bodies never flood the main loop), then writes a two-goal report — related-for-context AND a loud duplicate/overlapping-work callout split by Linear state (completed=already built · canceled=deliberately dropped · everything-else=open, may be duplicating). You then triage each ticket (read / subscribe / fold-into-scope / dismiss). A building block: it investigates + reports + triages, then STOPS — it never fixes, files, subscribes, or commits automatically. Triggers: \"ticket-search\", \"find related tickets\", \"any tickets like this\", \"am I duplicating work\", \"search linear for related work\"."
version: 1.0
tier: lightweight
args: "[<query / topic to search — omit at session-startup, when SRC_RELATED_TICKETS is already in context>]"
---

Find out whether the work in front of you has already been built, is being built right now, or was deliberately dropped — *before* you build it. `/ticket-search` hands a **search intent** (a query, or the active session's `taskSummary`) to a background subagent that finds the related and duplicate Linear tickets, deep-reads the promising ones read-only, and comes back with a two-goal **Ticket Search Report**: (1) related tickets for context, and (2) a loud, separate **duplicate / overlapping work** callout. You then triage each ticket finding-by-finding.

This is a **read-only, delegated building block** — the ticket-facing cousin of `/probe`. Where `/probe` sweeps code + DB + tickets to answer an open question, `/ticket-search` is single-purpose: it answers *"what already exists in Linear near this work?"*. As a building block it produces a briefing, not a change: it never edits code, never writes to the database, **never subscribes, comments on, files, or transitions a ticket**, never commits. It investigates, reports, triages, and stops. Subscribing, folding a duplicate into scope, or opening a coordinating thread is *your* call afterward (via `engine ticket subscribe`, `/build`, `/communicate`) — not this skill's.

*Crucial constraint:* `/ticket-search` does NOT own a session. It reads the *active* session's context and writes its paper trail directly into that session's `builds/`.

*Why a subagent (not inline):* deep-reading a ticket pulls its full description **and its entire comment thread** into context. Doing that for a handful of candidates would flood the main loop with ticket prose you'll never re-read. The subagent absorbs that heavy read and returns only the distilled report — context isolation is the whole reason this is delegated.

# /ticket-search Protocol

## 1. Frame the Search, Mode, Sources & Trail

**A. The Search Intent** (what you're checking for prior/parallel work on)
Resolve the topic from the arguments, else the active session's `taskSummary` / the current ticket / recent conversation. State it as **the body of work whose neighbors you want** — e.g. "adding ticket-search to session startup", "flat-detector multi-page room handling", "Gemini truncation retries". This intent seeds the CLI search (standalone) and frames which startup candidates are worth a deep read.

**B. The Mode** (this decides §2's dispatch — detect it, state it)
- **Standalone** — the user invoked `/ticket-search "<query>"`, and there is **no** `SRC_RELATED_TICKETS` block in context. The subagent runs the CLI **first** (`engine ticket-search "<query>" --json`) to get ranked candidates, then navigates the top hits.
- **Startup** — invoked during context ingestion (`§CMD_INGEST_CONTEXT_BEFORE_WORK`), and a `## SRC_RELATED_TICKETS` block that `session.sh activate` already emitted **is present** in context. The subagent **SKIPS the CLI** — the search already ran at activate — and navigates the already-emitted candidate summaries directly.

*Detection rule:* summaries present in context → **startup**; args given and/or no summaries → **standalone**. State which mode you chose in one line, with the reason. If genuinely ambiguous, ask ONE `AskUserQuestion`.

**C. The Sources** (where the answer lives)
One source: **Linear tickets** (via the `engine ticket-search` CLI for discovery + the Linear MCP read tools for navigation). No code, no DB. State the **read-only boundary** explicitly: no ticket creates, comments, status changes, or subscribes; no commits.

**D. The Trail**
Set `<trailDir> = <sessionDir>/builds/`. **No active session?** Standalone "am I duplicating work?" runs are a first-class entry point and may fire with no session: if `<sessionDir>` is unresolved, fall back to `<trailDir> = ./builds/` (cwd) — or, if the user prefers a session, offer to activate one — and still deliver the relay + triage in-chat regardless. Never skip the report for want of a session.
Mint a short, kebab-case `<slug>` from the intent (e.g. `ticket-search-startup`, `flat-detector-multipage`).
*Crucial:* Before minting a new slug, run `ls <trailDir>`. If an existing `<slug>_*.md` clearly matches this work (same chunk / ticket / topic), REUSE that slug so this clusters with the `/probe`, `/build`, and `/scrutinize` artifacts for the same work.

**Acknowledge:** Echo back your setup in exactly one line:
`Ticket-searching: <intent> — mode: <standalone|startup>; trail: <trailDir>/<slug>_TICKET_SEARCH.md.`

## 2. Dispatch the Navigator — Read-Only Subagent

**Backgroundable.** This dispatch is a composable building block: run it in the background (`run_in_background: true`) so the orchestrator keeps working while it runs, and you're notified when the report lands. Run it in the foreground only if you need the answer before your very next step. There is **no fan-out** here — one source, one navigator, always.

**Use the wait — don't idle.** While the navigator runs: (a) **anticipate** which candidates are most likely dups vs mere context, from what you already know of the work; (b) **surface open questions to the user now** (`AskUserQuestion`) — e.g. "if there's an open backlog ticket for this, fold it in or coordinate?" — so their answers are in hand when triage starts; (c) **prep the next move** — the likely `engine ticket subscribe` / `/build` fold-in. Don't block; the completion notification brings you back to §3 with momentum.

Build the subagent's prompt to be entirely self-contained — it cannot see your memory or the session history:

> You are a **ticket navigator sent to find prior and parallel work**. Your job is to answer ONE question with evidence from Linear: *what already exists near this body of work — for context, and (louder) as a possible DUPLICATE?* You are strictly READ-ONLY.
>
> **1. The Mission**
> - **Search intent (the work whose neighbors you want):** `<intent>`
> - **Mode:** `<standalone | startup>`
>   - *standalone* → FIRST run `engine ticket-search "<query>" --json` to get ranked candidate hits (default: include-closed ON, limit 10). Then navigate the top hits.
>   - *startup* → do NOT run the CLI. The candidate summaries are already below; navigate them directly.
> - **Candidate summaries (startup only):** `<the SRC_RELATED_TICKETS block, verbatim>` — each row is `{identifier, title, url, state, stateType, project, score, snippet}`.
> - **Team scope (optional):** `<--team KEY, or org-wide>`.
>
> **2. Rules of Engagement (READ-ONLY — hard)**
> - **Change nothing.** No ticket creates, comments, status changes, or subscribes. No file writes outside your report. No commits. If acting on a finding seems to require a write (subscribe, comment, fold-in), that is a **suggested action to report**, not an action to take.
> - **Navigate every deep-read through `§CMD_READ_RELATED_TICKET`.** Do NOT hand-roll a bare `get_issue`. For each candidate worth a full read, apply that atom: load the Linear MCP read tools via `ToolSearch` (`select:mcp__linear__get_issue,mcp__linear__list_comments`), then `get_issue` (KEY → title, url, `state{name,type}`, priority, description, assignee, project, updatedAt) → read `state` from that same payload → `list_comments` on the pinned issue id. It returns the normalized `{ key, title, url, state, stateType, priority, description, assignee, project, updatedAt, comments[] }` — classify from that, never a raw payload.
> - **The heavy read stays with YOU.** Full descriptions and comment threads are why you exist — absorb them here and return only the distilled report. Never paste whole ticket bodies or comment threads back to the orchestrator.
> - **No Linear MCP? Report and stop.** Headless / no `mcp__linear__*` → you cannot navigate; report the skipped reads (which KEYs, and that the MCP was absent) and stop. Never hang, never guess a ticket's contents.
> - **Git safety (`¶INV_NO_DESTRUCTIVE_GIT`):** the tree is always dirty with other agents' work. NEVER run tree/index-destructive git (`stash`/`checkout`/`reset`/`clean`/`rm`/`add`). Read committed files with `git show HEAD:<path>`. Read-only git is fine.
>
> **3. How to Navigate & Classify**
> - **Triage the candidate list first, then deep-read selectively.** Not every hit deserves a full body+comments read — a low-score, plainly-unrelated title can be dismissed from the summary alone (say so). Deep-read the ones whose title/snippet plausibly touch this work; a deep-read is required for anything you'll place in the duplicate callout.
> - **Two goals, kept separate:**
>   - **(a) Related for context** — a ticket that informs the work (prior decision, adjacent system, useful precedent) but is NOT the same deliverable.
>   - **(b) Duplicate / overlapping work** — a ticket that IS, in whole or part, the same deliverable. This is the loud, headline finding — the thing a new session most needs to know before building.
> - **Classify every duplicate/overlap by `stateType`** (the atom's normalized `state.type` — classify TOTALLY across Linear's six `WorkflowState.type` values, never a partial enum, or the common case falls through):
>   - `completed` → **already built** → reuse / skip.
>   - `canceled` → **deliberately dropped** → investigate WHY before rebuilding (a canceled duplicate was abandoned, NOT built — do NOT tell the reader to "reuse" it; read the ticket/comments for the reason it was dropped).
>   - **everything else** (`triage`, `backlog`, `unstarted`, `started`) → **open / not-yet-built → coordinate, may be duplicating**. A backlog/triage ticket someone else already filed is *the* headline dup case — it lands in the open bucket, never falls through.
>   - **unknown / missing `stateType`** (the atom's VERIFY-BEFORE-SHIP caveat: `get_issue` may not return `state.type`) → **treat as open + flag "state unconfirmed" for the human** (fail-open, mirroring the CLI). Never silently drop it.
> - **Evidence or it's an opinion.** Every finding cites the ticket KEY + its state + the ticket's own words (a quoted line of the description or a comment) that make it related or a dup. Never paraphrase what you could quote.
> - **Honest coverage.** If the CLI returned nothing, or every candidate was plainly unrelated, say exactly that — "no related tickets found" is a complete, successful search. Report which candidates you deep-read vs dismissed-from-summary, and why.
>
> **4. Output Contract**
> WRITE your report to `<REPORT_PATH>` using the Ticket Search Report template (this skill's `assets/TEMPLATE_TICKET_SEARCH.md` — the orchestrator gives you its base dir; **do not hardcode `~/.claude`**). Fill EVERY subagent-owned section of the template: **§0 Headline** (the one-line answer the relay leads with), **§1 Related for context** (ranked: `[KEY] · title · state · why-related · link`), **§2 ⚠️ Duplicate / overlapping work** (each `[KEY] · state · overlap rationale`, split by the stateType buckets above), **§3 Suggested actions** (per ticket: read / subscribe (`engine ticket subscribe <KEY>`) / fold-into-scope / dismiss — SUGGEST only, never done), and **§4 Coverage** (which candidates you deep-read vs dismissed-from-summary). Leave only §5 Triage Outcomes blank — that is the orchestrator's. Then RETURN a 4–6 line summary + the report path + the **numbered ticket findings** (the orchestrator triages by these). Do NOT dump the full report into your return message — the orchestrator reads the file.

**Substituting `<REPORT_PATH>`:** always the single `<trailDir>/<slug>_TICKET_SEARCH.md` (no fan-out). Hand the agent the **fully-substituted absolute path**, never a placeholder.

**Substituting `<LOGGING>`:** tell the agent to append its navigation notebook via `engine log <the active session's log path>` every ~5 tool calls — a **heartbeat hook BLOCKS after 10 tool calls without a log**. Its notebook (which KEYs it read, what each ticket's state + gist was, the dup/context verdict) is the raw material the report synthesizes.

**Before dispatching — `§CMD_LOG_SKILL_INVOCATION`**: log this dispatch to the session log (why + the mode + a one-line re-tread) so a restarted session can re-tread it. Fire it as the last step before the `Task`/`Agent` handoff.

Dispatch to the background by default (`run_in_background: true`).

## 3. Report Intake & Relay

Read the report.

**Spot-check the load-bearing evidence.** Don't re-navigate every ticket — but don't take the dup callout on faith either. For any ticket the subagent placed in the **duplicate / overlapping** bucket, sanity-check its state and overlap claim: the `stateType` split is load-bearing (a `completed` dup means "already built, stop"; an open one means "coordinate now"), and a misread state sends the whole triage the wrong way. If a dup verdict rests on a comment you can't see, flag it as unconfirmed.

**Relay, answer-first.** Lead with the headline: *is this work a duplicate, and of what?* — the single most decision-relevant fact — then the related-for-context tickets, then any blind spots. Keep it tight; the full report is on disk. Link it (`§CMD_LINK_FILE`).

## 4. Triage — Walk the Findings with the User

The interactive `AskUserQuestion` walkthrough is where the search turns into a decision. The user, not the model, decides each ticket's fate. Run it explicitly. NEVER dump findings as bare text and assume the user's intent.

This is `§CMD_WALK_THROUGH_RESULTS`. Do NOT use the `§CMD_TAG_TRIAGE` default — use the ticket-search decision set below.

**The Walkthrough Routine:**

1. **Granularity Gate (1× `AskUserQuestion`):**
   Ask: "How do you want to walk the N tickets?" (`§ASK_WALKTHROUGH_GRANULARITY`). Options (single-select): **Each** (one at a time) · **Groups** (batches of 4) · **Smart** (≤4 → Each, 5–12 → Groups) · **Dups-first** (walk the duplicate/overlapping bucket only; accept the context list as-is) · **None** (accept the report as-is; skip to §5).

2. **Per-Ticket Evaluation (Context Block + `AskUserQuestion`):**
   For each ticket (or batch), present a mandatory 2-part context block in chat (`§FMT_CONTEXT_BLOCK`):
   *   `Line 1:` `[KEY]: <title> — <state>, <related-for-context | DUPLICATE:already-built | DUPLICATE:dropped | DUPLICATE:open>`
   *   `Line 2:` `<what the ticket shows / the overlap> | <why it matters to this work> | <suggested action>`

   Then call `AskUserQuestion` with the ticket KEY as the header and this option tree:
   - **Subscribe** — track it going forward. Collected for an `engine ticket subscribe <KEY>` you offer in §5 (never auto-run here).
   - **Fold into scope** — an open/overlapping ticket whose work belongs in what you're building now. Collected for a `/build` (or plan-update) handoff.
   - **Read** — worth the user opening it themselves before deciding. Surface the link.
   - **Coordinate** — an open dup owned by someone else; reach out rather than duplicate. Collected for a `/communicate` handoff.
   - **Dismiss** — acknowledged, no action (record the user's reason if given — e.g. "canceled for a reason that no longer applies, proceeding anyway").
   - **Discuss** — needs more detail, or you disagree. Answer in chat, then re-present this ticket.

3. **Batch Shortcuts:**
   Honor natural-language shortcuts immediately ("subscribe to the two open dups, dismiss the rest", "fold in FIN-1234 only", "dismiss all the completed ones"). Apply them to all remaining tickets.

**Assemble the outcome:** the per-ticket fates plus any user amendments. The subagent's classification is *advice*; the fate is the user's *call*.

## 5. Next Steps (Ask — Don't Auto-Chain) & Trail

**Execute the fates by offer, never automatically.** Present the collected outcomes and offer the chains via `AskUserQuestion` — the user decides whether to run them now, later, or not at all:
- **Subscribe** → `engine ticket subscribe <KEY>` — the ONLY write this whole flow can produce, and only on the user's explicit go. Never auto-subscribe.
- **Fold into scope** → `Skill(build, "<the ticket's work, folded into this build>")` or a plan-update note.
- **Coordinate** → `Skill(communicate, "<the open dup + what to ask the owner>")`.
- **Read** → surface the link; no chain.
- **Dismissed** → note it in the session artifact.

*Crucial:* keep the human gate. Do NOT auto-execute a chain, and above all **do NOT auto-subscribe** — surfacing a ticket is this skill's job; acting on it is the user's.

**Append to the trail.** APPEND the triage outcome (per-ticket fate + reason) to `<trailDir>/<slug>_TICKET_SEARCH.md`. Append rather than rewrite, so a killed or resumed run never loses history. The report persists even on a partial or blocked search.

**Feed the ledger (compounding loop).** Append the durable finding to `<trailDir>/LESSONS.md` as terse bullets via `engine log` — the settled fact, not the narrative.
*(Illustrative — adapt, don't copy: "FIN-1180 already ships related-tickets search in intake (Done) — reuse its CLI seam, don't rebuild.")*
The next `/build`, `/probe`, or `/ticket` reads these, so a settled dup answer shapes the next handoff instead of evaporating.

Then **stop**. `/ticket-search` surfaces, reports, and triages — nothing more.

## Constraints
- **Read-only, absolutely.** No ticket creates, comments, status changes, or **subscribes**; no code edits; no DB writes; no commits; no tree/index-destructive git (`¶INV_NO_DESTRUCTIVE_GIT` — the tree is always dirty with other agents' work). A write the answer seems to require (subscribe, fold-in, coordinate) is a **suggested action**, not an action taken.
- **Building block — surfaces, never advances.** It produces a briefing plus triage decisions, then stops. Subscribing is `engine ticket subscribe`'s job (on the user's go); folding a dup in is `/build`'s; coordinating is `/communicate`'s; filing a new ticket is `/ticket`'s.
- **Navigate through the atom.** Every deep-read routes through `§CMD_READ_RELATED_TICKET` — never a hand-rolled `get_issue` — so the `{ key, …, stateType, comments[] }` shape stays identical across every site that reads a candidate ticket.
- **The dup split is load-bearing and TOTAL.** Classify every duplicate/overlap by `state.type` across all six Linear values: `completed` = already built (reuse/skip) · `canceled` = deliberately dropped (investigate WHY, do NOT "reuse") · `triage`/`backlog`/`unstarted`/`started` = open, may be duplicating (coordinate). A backlog ticket someone filed is the headline dup — it must never fall through to the completed bucket.
- **Two goals, kept separate in the report.** Related-for-context (section 1) and duplicate/overlapping (section 2) are distinct — the dup callout is loud and on its own, because "you may be about to rebuild something" is the finding that changes what happens next.
- **Context isolation is the point.** Heavy ticket bodies + comment threads stay inside the subagent; only the distilled report crosses back. That's why this is delegated, not inline.
- **Honest coverage.** "No related tickets found" or "the MCP was absent, here's what I couldn't read" is a complete, successful search. Never manufacture a ticket's contents or guess a state.
- **User owns the fate.** The subagent's classification is advice; subscribe / fold-in / read / coordinate / dismiss is the user's call via `AskUserQuestion`. Chains are offered, never auto-run — and subscribe is never auto-run.
- **Sessionless.** No `engine session activate`; it reads the active session and writes into its `builds/`. `§INV_LISTS_INSTEAD_OF_TABLES` throughout — the report is `§FMT_*` lists, never tables.
