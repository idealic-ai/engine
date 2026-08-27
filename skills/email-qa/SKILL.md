---
name: email-qa
description: "Email Classification QA bench — accept mis-classification instances live (screenshots/links) or drain them from the Email Classification Improvements Linear inbox, then per instance: probe staging forensics, apply a capture-first instance fix, classify against the root-cause taxonomy, decide the systemic fix (fold into a class ticket or dispatch /build), ledger it, and post the annotated instance back to the Linear inbox. Triggers: \"email qa\", \"classification QA\", \"this should have matched X\", \"triage the email inbox\", \"why did this email misroute\"."
version: 1.0
tier: protocol
---

Email Classification QA bench — live/drain triage of classification instances with a compounding taxonomy, capture-first fixes, builder dispatch, and a Linear paper trail.

# Email QA Protocol (The Triage Bench)

Execute §CMD_EXECUTE_SKILL_PHASES.

### Session Parameters
```json
{
  "taskType": "EMAIL_QA",
  "phases": [
    {"label": "0", "name": "Setup",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_PARSE_PARAMETERS", "§CMD_INGEST_CONTEXT_BEFORE_WORK"],
      "commands": [],
      "proof": ["mode", "sessionDir", "parametersParsed", "benchReady"], "gate": false},
    {"label": "1", "name": "Triage Loop",
      "steps": ["§CMD_REPORT_INTENT"],
      "commands": ["§CMD_APPEND_LOG", "§CMD_THINK_IN_LOG", "§CMD_ASK_USER_IF_STUCK", "§CMD_REFUSE_OFF_COURSE"],
      "proof": ["instancesHandled", "ledgerEntries", "logEntries"]},
    {"label": "2", "name": "Synthesis",
      "steps": ["§CMD_REPORT_INTENT", "§CMD_RUN_SYNTHESIS_PIPELINE"], "commands": [], "proof": [], "gate": false},
    {"label": "2.1", "name": "Checklists",
      "steps": ["§CMD_VALIDATE_ARTIFACTS", "§CMD_RESOLVE_BARE_TAGS", "§CMD_PROCESS_CHECKLISTS"], "commands": [], "proof": [], "gate": false},
    {"label": "2.2", "name": "Debrief",
      "steps": ["§CMD_GENERATE_DEBRIEF"], "commands": [], "proof": ["debriefFile", "debriefTags"], "gate": false},
    {"label": "2.3", "name": "Pipeline",
      "steps": ["§CMD_MANAGE_DIRECTIVES", "§CMD_PROCESS_DELEGATIONS", "§CMD_DISPATCH_APPROVAL", "§CMD_CAPTURE_SIDE_DISCOVERIES", "§CMD_RESOLVE_CROSS_SESSION_TAGS", "§CMD_MANAGE_BACKLINKS", "§CMD_MANAGE_ALERTS", "§CMD_REPORT_LEFTOVER_WORK"], "commands": [], "proof": [], "gate": false},
    {"label": "2.4", "name": "Close",
      "steps": ["§CMD_REPORT_ARTIFACTS", "§CMD_REPORT_SUMMARY", "§CMD_SURFACE_OPPORTUNITIES", "§CMD_CLOSE_SESSION", "§CMD_PRESENT_NEXT_STEPS"], "commands": [], "proof": [], "gate": false}
  ],
  "nextSkills": ["/build", "/scrutinize", "/pr", "/intake", "/ticket"],
  "directives": ["PITFALLS.md"],
  "logTemplate": "assets/TEMPLATE_EMAIL_QA_LOG.md",
  "debriefTemplate": "assets/TEMPLATE_EMAIL_QA.md"
}
```

---

## 0. Setup (Lazy Boot)

§CMD_REPORT_INTENT:
> 0: Opening the email-QA bench. Mode: ___ (live / drain).
> Focus: tunnel health, taxonomy + class tickets, deploy status.
> Not: worktrees, bundles, or secrets — those stand up on first need.

§CMD_EXECUTE_PHASE_STEPS(0.0.*)

**Boot checklist (cheap checks only — target < 1 minute):**
1.  **Tunnels**: `nc -z -w 2 localhost 15432` (pg) and `nc -z -w 2 127.0.0.1 16379` (redis); confirm URL files exist. If down → rebuild per `assets/OPS_TOOLKIT.md` § Tunnels (nohup + tunnel-keeper).
2.  **Taxonomy**: Read `assets/TAXONOMY.md`. Fetch the open consolidated class tickets from the Email Classification Improvements Linear project (`mcp linear list_issues` on the project) and note per-class status drift (a class whose PR merged since the last session gets its registry line updated NOW).
3.  **Chains in flight**: from the taxonomy status lines + class-anchor states, list every class sitting at an unfinished chain leg (rework owed, scrutinize pending, PR unopened, replay owed). These are BENCH WORK, not synthesis footnotes: present a dispatch menu (AskUserQuestion, ranked by hanging-height from the critique verdicts) offering to advance them as background builders while triage runs. Rework packs pull the ORIGIN session's build report + critique verdict + worktree state (OPS_TOOLKIT § Builders).
4.  **Deploy**: `gh run list --workflow deploy-staging.yml --limit 1` — a red/behind deploy changes what "the live pipeline should have done" means for fresh instances; note the deployed SHA in the log.
5.  **Mode**: If the user brought instances → LIVE. If invoked bare or with "drain" → DRAIN: pull the oldest unhandled comments from the 🔴 Observed problems channel ticket (FIN-3356) — plus any other inbox channels holding classification instances — where unhandled = no `[email-qa handled]` reply. Reporters NEVER classify or route (ten seconds, zero decisions — the intake doc rule); the BENCH does the classifying. In DRAIN mode, open with an **Inbox Census** (echo in chat + log): unhandled count, age spread, class mix guess, delta since the last Inbox Report.
6.  **Session ledger**: Create `FIX_LEDGER.md` in the session dir from `assets/TEMPLATE_FIX_LEDGER.md` if absent.

**Deferred until first needed** (recipes in `assets/OPS_TOOLKIT.md`): ops worktree + webpack bundle (only for re-drives), builder worktrees (only on dispatch), AWS/Algolia secrets (only for S3/search fixes), pncr jest vehicle env (only for claim deletions).

*Phase 0 always proceeds to Phase 1 — no transition question needed.*

---

## 1. Triage Loop
*The heart of the bench: one instance at a time, to done.*

§CMD_REPORT_INTENT:
> 1: Triaging ___ instances (___ mode). Ledger + inbox write-back per instance.
> Focus: probe → capture-first fix → classify → systemic decision → ledger → inbox-post.
> Not: consolidation/promotion (that is /intake's job); no review-grade overwrites; no un-gated Tier-1 changes.

§CMD_EXECUTE_PHASE_STEPS(1.0.*)

### Per-instance loop (run in full for EVERY instance)

**0. CAPTURE — inbox-post FIRST, before anything else.** The moment an instance arrives (live paste or drain pick-up), post the RAW report to the 🔴 Observed problems channel (FIN-3356) via /inbox-post or a direct comment: verbatim symptom, org, any ids/screenshot refs. No classification, no analysis — capture-first for signal, exactly like pre-images are capture-first for data. That comment IS the instance's Linear identity; every later write-back is a REPLY to it. (Drain mode: the comment already exists — skip to 1.)
   - **Screenshots go to Linear too.** Recover the reported image's file and attach it to FIN-3356 alongside the capture comment (`prepare_attachment_upload` → HTTP PUT the bytes → `create_attachment_from_upload`, title = the instance's short name; or embed via the returned URL in the comment body). Recovery: a *file-pasted* screenshot has a path; a *clipboard* paste does not — check `~/Desktop/Screenshot *.png` with mtime within a few minutes of the report and Read each candidate to VERIFY it shows the reported surface before attaching (Tom's Desktop holds unrelated shots; a mismatched attach is worse than none). Unrecoverable clipboard paste → say so in the capture comment and copy the screenshot's content into words (org, subjects, ids, chips). Also save any recovered file into the session dir (`screenshots/`) so the evidence survives Desktop cleanup.

**1. PROBE — evidence before opinion.** Use `assets/probes.sql` (adapt org/ids). Minimum forensics for a mis-route/mis-match:
   - The link row: `review_status`, `rationale` (head codes), `confidence`, `proposed_claim_id`, `candidate_claim_ids`, `match_sources`, `layer4_decision`, `layer4_dropped_claim_ids`, `fetch_quality`, `extracted_claim_number/address`.
   - Sender/recipient bindings: contact_email → contact → claim_contact (source, status, live-claim fanout).
   - The claim graph around the expected claim: twins (same title/property), refs (incl. normalized + zero-pad cores), property address, link/doc counts.
   - Read `rationale` codes against the taxonomy BEFORE forming a theory. The large classifier files false-empty under plain grep — perl/sed/node only (OPS_TOOLKIT § Traps).

**2. INSTANCE FIX — capture-first, guarded, reversible.**
   - Pre-image EVERY row you will touch to `pre-images/*.jsonl` (0600) BEFORE writing.
   - Allowed inline (pre-authorized shapes): proposal stamps onto queue rows (guard: `review_status='pending_review'/'parked'` AND current proposal NULL-or-known-wrong); ref strips of junk tokens; ref promotions (≥5 votes OR equivalent corroboration, collision-checked org-wide incl. zero-pad cores, O-vs-0 twin-checked); merge-retire of same-loss duplicate claims via the merge-claims pattern (+ reindex survivor / deindex loser); false-attach binding strips (evidence message must prove the false attach); stale Algolia object deletes (verify DB row gone first, save the object JSON, verify 404 after).
   - **Human-only (surface, never do)**: overwriting review-grade states (approved/auto_approved reassignments), claim deletions, tier enables/flag flips, destructive cleanup (per the Intake System doc), anything on an org outside the session's scope.
   - Bulk SQL: one guarded statement with a temp mapping table + `SET statement_timeout` — never psql-in-a-while-loop (it eats stdin and dies silently).

**3. CLASSIFY — against `assets/TAXONOMY.md`.**
   - Known class → increment the instance on its consolidated Linear ticket (comment with the instance details), note fix-status (shipped / PR pending / backtest-gated / data-recipe).
   - New class → this is a discovery: add a registry entry, create the consolidated class ticket via `/ticket` (Tom confirms creation — his gate), and decide leg 4.

**4. SYSTEMIC DECISION.**
   - Class already has a shipped/pending fix → nothing to build; link the instance.
   - Data-class (twins, missing refs, alias mappings, missing claims) → run the census recipe (OPS_TOOLKIT) and apply the evidence-gated data fix; big cohorts (>50 rows or new pattern) get an AskUserQuestion first.
   - Code-class without a fix → dispatch `/build` with a FULL context pack (goal, verbatim ask, staged evidence, traps, gates, return contract — pack conventions in OPS_TOOLKIT § Builders). Review chain default: **build → scrutinize → PR → codex**, plus `classifier-replay --base=origin/dev` whenever the diff touches watchlisted files (`.github/scripts/classifier-replay-watchlist.json`). **Tier-1 mechanism changes** (anything that widens automated blast radius): council+refuter added, AND the mechanism ships flag-gated default-OFF with a backtest arm measuring its cohort vs the fp-tiers bar — enable is Tom's call on the artifact, never the builder's or yours.

**5. LEDGER.** Append the instance to `FIX_LEDGER.md` (entry format in the template): symptom, instance fix + pre-image path, root cause + evidence, systemic fix + status, open decisions.

**6. WRITE-BACK (two comments — and this INCLUDES issues DISCOVERED mid-work, not just operator-reported ones).** Every discrete NEW issue an audit/executor/probe surfaces (a bad ref, a fake claim, a contamination shape, a near-miss) gets its OWN capture comment on the 🔴 channel — the channel's comment count IS the signal /intake reads; batch-grain roll-ups undercount it. Per-thread noise stays in reports; discrete issues each get a comment. (a) Annotated instance onto its CLASS ANCHOR ticket (org, link/claim ids, what was fixed, pre-image path, builder/PR link) — the per-class count that drives priority. (b) REPLY to the instance's own Observed-problems comment (created at step 0): `[email-qa handled]` + one line + the class-anchor link. The channel thus shows every report AND its resolution inline.

### Loop discipline
- Instances arrive mid-flight (screenshots while you work) — intake each into the ledger as `[N] reported` immediately, then process in order; never lose one.
- Builders run in the BACKGROUND; keep triaging while they build. On a builder landing: re-run its exact gate commands yourself before calling it green, append its `reusableFacts` to the session `builds/LESSONS.md`, update the class's registry line.
- **Chain events hit Linear in REAL TIME, not at synthesis.** On every chain transition (builder dispatched / landed+gates-reverified / scrutinize verdict / PR opened / PR merged / replay attested): comment the class anchor with the event + link, AND move the anchor's milestone to match (Inboxes ↔ Ready for action ↔ Needs decision). **On PR merge**: set the anchor's status to the team's merged-not-released state (Unreleased) and assign Tom — EXCEPT anchors whose open item is a pending decision (e.g. a dark-flag enable gate): those keep their status until the decision lands; assign Tom only. Synthesis only reconciles what the loop already posted — the board must be honest while builders run.
- Batch Tom's decisions (AskUserQuestion, ≤4 at a time) rather than interrupting per item; keep a running "owed decisions" list in the ledger.
- Cost posture: canary before every paid LLM pass; merged-resume discipline on re-drives; never re-pay for processed rows.

### Completion signal
When the user says done (or the drained chunk is exhausted), present the work-phase gate:
> "Bench session complete? [Keep triaging / Close session / Walk through the ledger]"

---

## 2. Synthesis
*Wrap up: the ledger is the star artifact.*

§CMD_REPORT_INTENT:
> 2: Synthesizing. ___ instances handled, ___ builders dispatched.
> Focus: ledger close-out → Linear, debrief, chain status.
> Not: new instance work.

§CMD_EXECUTE_PHASE_STEPS(2.0.*)

**Close-out specifics (before the debrief):**
1.  Post the **Inbox Report** to the Email Classification Improvements project (status update or Inbox comment) — STABLE format, same sections every session so consecutive reports read as a trend line and /intake waves can lift them: `Instances by class` · `Fixes applied (data / builders / PRs)` · `Inbox state (unhandled count + age, delta vs last report)` · `Chains in flight` · `Decisions owed`. The FIX_LEDGER is the detail behind it; link the session dir.
2.  Update `assets/TAXONOMY.md` fix-status lines to match reality (PRs opened/merged this session).
3.  Report the review-chain state per dispatched build (scrutinize done? PR open? replay run?) under Leftover Work — unfinished chains are the #1 carry-over.
4.  **Intake-wave check**: if the inbox holds unconsolidated handled instances or new classes were minted, PROMPT the operator: "intake wave due — run /intake on the project now?" (offer, never auto-run — consolidation/promotion stays a human-steered wave).

**Debrief notes** (for `EMAIL_QA.md`): per-class instance counts, biggest unlock of the session, taxonomy changes, chain states, owed decisions.

**Walk-through config**:
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Bench closed. Walk through the ledger?"
  debriefFile: "EMAIL_QA.md"
```

---

## Rules of Engagement
*   **The ledger is non-negotiable.** Every instance gets an entry, even "looked at it, no action".
*   **Evidence before writes; capture before mutations.** No fix without a probe; no write without a pre-image.
*   **Precision > recall** in every promotion/mapping decision; vote bars and collision checks are floors, not suggestions.
*   **Linear is the shared truth**: instances → Inbox (annotated), classes → consolidated tickets, consolidation/promotion → /intake's waves. This bench never runs Decision Boards.
*   **Escalation**: work outside the loop's shapes (schema changes, prompt changes, infra/lifecycle/IAM) → `§CMD_REFUSE_OFF_COURSE` or a Tom decision, not improvisation.

