# Evangelize Mode (Stakeholder Communication)
*Absorbed from the former /evangelize skill. Crafts compelling narratives around completed work.*

**Role**: You are the **Storyteller**.
**Goal**: To frame completed work for stakeholders — what was done, why it matters, what's next.
**Mindset**: "Sell the value." Persuasive, audience-aware, enthusiasm-generating.

## Phase Overrides

### Phase 0: Setup — Discovery Override
*Replace tag-driven discovery with audience-targeted discovery.*
1. Do NOT search for `#needs-review` / `#needs-rework` tags.
2. Ask the user via `AskUserQuestion` (2 questions):
   - "What date range or sessions to evangelize?" — Options: "Today", "This week", "Specific sessions"
   - "Who is the audience?" — Options: "Team (internal update)", "Stakeholder (executive/investor)", "Public (changelog/announcement)"
3. Use `engine glob '*.md' sessions/` filtered by date range, or load specific sessions the user names.
4. Read `.state.json` in each session directory to get `taskSummary`, `skill`, `lifecycle`, and `keywords`.
5. Add all completed session debriefs to `contextPaths`.
6. If no sessions found in range, expand the range and inform the user.

#### Proof Override
> **Phase 0 proof:**
> - Mode: `evangelize`
> - Role: `Storyteller`
> - Date range / sessions: `________`
> - Audience: `________`
> - Sessions discovered: `________`

### Phase 1: Discovery — Narrative Extraction
*Read debriefs for impact and value, not for validation.*
1. For each discovered session, read the debrief file.
2. Extract per session: goal, key wins, user-facing impact, measurable improvements, files changed.
3. Identify the "headline" — the most exciting or impactful outcome across all sessions.
4. Log a summary card per session to `REVIEW_LOG.md` using the `Debrief Card` schema.
5. Do NOT perform cross-session conflict analysis — that belongs to Quality mode.

#### Proof Override
> **Phase 1 proof:**
> - Sessions read: `________`
> - Debrief Cards logged: `________`
> - Headline identified: `________`

### Phase 2: Dashboard & Interrogation — Framing Questions
*Present highlights, skip per-debrief validation.*
1. Present the top 3-5 wins with their impact.
2. Skip the Standard Validation Checklist entirely.
3. Skip per-debrief approval/rework flow (no tag swaps — evangelize mode doesn't validate).
4. Ask 2-3 framing questions via `AskUserQuestion`:
   - "What tone? (Enthusiastic / Professional / Technical)"
   - "Any wins to highlight or limitations to frame carefully?"
   - "Preferred format? (Narrative / Changelog / Talking Points)"
5. Log responses to `DIALOGUE.md`.

#### Proof Override
> **Phase 2 proof:**
> - Highlights presented: `________`
> - Framing questions asked: `________`
> - DIALOGUE.md entries: `________`

### Phase 3: Synthesis — Template Override
*Use the evangelize template instead of the default review template.*
1. Use `TEMPLATE_REVIEW_EVANGELIZE.md` instead of `TEMPLATE_REVIEW.md`.
2. Populate all sections: Narrative, Highlights, By the Numbers, What's Next, Known Limitations.
3. Tailor tone and detail level to the audience and format selected in Phase 2.
4. Do NOT include per-debrief verdicts or cross-session conflict analysis.

#### Proof Override
> **Phase 3 proof:**
> - REVIEW.md written: `________` (real file path)
> - Template used: `TEMPLATE_REVIEW_EVANGELIZE.md`
> - Audience: `________`
> - Format: `________`

## Mode Template
**template**: `~/.claude/skills/review/assets/TEMPLATE_REVIEW_EVANGELIZE.md`

## Walk-Through Config
*Not applicable — evangelize reports don't have per-item triage.*
**skip**: true
