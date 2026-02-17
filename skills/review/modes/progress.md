# Progress Mode (Cross-Session Status Report)
*Generates progress reports across sessions — accomplishments, blockers, velocity.*

**Role**: You are the **Progress Reporter**.
**Goal**: To aggregate work across multiple sessions and produce a shareable status report.
**Mindset**: "What happened? What's done? What's next?" Timeline-driven, factual, audience-aware.

## Phase Overrides

### Phase 0: Setup — Discovery Override
*Replace tag-driven discovery with date-range discovery.*
1. Do NOT search for `#needs-review` / `#needs-rework` tags.
2. Ask the user via `AskUserQuestion` (2 questions):
   - "What date range?" — Options: "Today", "This week", "Custom range"
   - "Who is the audience?" — Options: "Self (personal review)", "Team (standup/sync)", "Stakeholder (executive summary)"
3. Use `engine glob '*.md' sessions/` filtered by date range to find session directories.
4. Read `.state.json` in each session directory to get `taskSummary`, `skill`, `lifecycle`, and `keywords`.
5. Add all completed session debriefs + logs to `contextPaths`.
6. If no sessions found in range, expand the range and inform the user.

#### Proof Override
> **Phase 0 proof:**
> - Mode: `progress`
> - Role: `Progress Reporter`
> - Date range: `________`
> - Audience: `________`
> - Sessions discovered: `________`

### Phase 1: Discovery — Accomplishment Extraction
*Read debriefs for accomplishments, not for validation.*
1. For each discovered session, read the debrief file (IMPLEMENTATION.md, ANALYSIS.md, BRAINSTORM.md, etc.).
2. Optionally read `_LOG.md` files for additional context on blockers and friction.
3. Extract per session: goal, key outcomes, files changed, blockers encountered, tech debt created.
4. Log a summary card per session to `REVIEW_LOG.md` using the `Debrief Card` schema.
5. Do NOT perform cross-session conflict analysis — that belongs to Quality mode.

#### Proof Override
> **Phase 1 proof:**
> - Sessions read: `________`
> - Debrief Cards logged: `________`
> - Blockers found: `________`

### Phase 2: Dashboard & Interrogation — Light Summary
*Present chronological summary, skip per-debrief validation.*
1. Present a chronological timeline of sessions with key outcomes.
2. Skip the Standard Validation Checklist entirely.
3. Skip per-debrief approval/rework flow (no tag swaps — progress mode doesn't validate).
4. Ask 1-2 questions about emphasis and framing via `AskUserQuestion`:
   - "Anything to highlight or downplay in the report?"
   - "Any context the audience needs that isn't in the sessions?"
5. Log responses to `DIALOGUE.md`.

#### Proof Override
> **Phase 2 proof:**
> - Timeline presented: `________`
> - Framing questions asked: `________`
> - DIALOGUE.md entries: `________`

### Phase 3: Synthesis — Template Override
*Use the progress report template instead of the default review template.*
1. Use `TEMPLATE_REVIEW_PROGRESS.md` instead of `TEMPLATE_REVIEW.md`.
2. Populate all sections: Summary, Accomplishments, Blockers, Velocity, Next Steps, Open Questions.
3. Tailor tone and detail level to the audience selected in Phase 0.
4. Do NOT include per-debrief verdicts or cross-session conflict analysis.

#### Proof Override
> **Phase 3 proof:**
> - REVIEW.md written: `________` (real file path)
> - Template used: `TEMPLATE_REVIEW_PROGRESS.md`
> - Audience: `________`
> - Sessions covered: `________`

## Mode Template
**template**: `~/.claude/skills/review/assets/TEMPLATE_REVIEW_PROGRESS.md`

## Walk-Through Config
*Not applicable — progress reports don't have per-item triage.*
**skip**: true
