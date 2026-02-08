# Review Report: [TOPIC/DATE]
**Tags**: #needs-review
**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/REVIEW.md`.

## 1. Executive Summary
*   **Scope**: [N] debriefs validated across [M] sessions.
*   **Period**: Sessions from [date range or "all unvalidated"].
*   **Outcome**: [All Validated / Partial — N validated, M need rework / Conflicts Found]

## 2. Cross-Session Analysis
*Formal analysis of interactions between sessions. Each subsection MUST be filled (use "None detected" if clean).*

### 2.1 File Overlap
*Did multiple sessions touch the same files?*
*   **Finding**: [None detected / List of overlapping files with session references]
*   **Risk**: [None / Description of potential merge conflicts or stomped changes]

### 2.2 Schema & Interface Conflicts
*Did sessions make incompatible changes to shared types, APIs, or contracts?*
*   **Finding**: [None detected / List of conflicting changes]
*   **Risk**: [None / Description of type errors or runtime failures]

### 2.3 Contradictory Decisions
*Did one session decide X while another decided not-X?*
*   **Finding**: [None detected / List of contradictions with session references]
*   **Resolution**: [N/A / Which decision takes precedence and why]

### 2.4 Dependency Order
*Did any session depend on another session's output that might not be validated yet?*
*   **Finding**: [None detected / List of dependency chains]
*   **Recommendation**: [N/A / Suggested validation or implementation order]

## 3. Per-Debrief Verdicts
*Condensed summary card for each validated debrief.*

### 3.1 [Session Name] — [Debrief File]
*   **Verdict**: [Validated / Needs Rework]
*   **Goal**: [1-line session goal from debrief]
*   **Key Changes**: [2-3 bullet summary of what was done]
*   **Findings**: [Key checklist findings — only the relevant/interesting ones]
*   **User Notes**: [Any user comments or overrides during interrogation]

### 3.2 [Session Name] — [Debrief File]
*   ...

*(Repeat for each debrief)*

## 4. Leftovers & Follow-Up Work
*Actionable items discovered during validation. Each leftover includes a micro-dehydrated prompt for immediate use.*

### Leftover 1: [Title]
*   **Source**: `[Session/Debrief that spawned this]`
*   **Type**: [Simple — plain instruction, no command needed] or [Complex — needs a command protocol]
*   **Command**: `/[implement|debug|test|analyze]` *(omit for simple tasks)*
*   **Prompt**:
    > [Copy-pasteable instruction or micro-dehydrated prompt. Simple: "Delete `apps/foo/generate-v2.ts`". Complex: references the review report, original session, and describes the work needed.]
*   **Priority**: [High / Medium / Low]

### Leftover 2: [Title]
*   ...

*(Repeat for each leftover. Use "None — all sessions clean." if no leftovers.)*

## 5. Agent's Expert Opinion (Subjective)

### 1. The Review
*   **Overall Health**: "How does the codebase look after these sessions?"
*   **Biggest Risk**: "The one thing that worries me most."
*   **Biggest Win**: "The most impactful session result."

### 2. Process Observations
*   **Agent Quality**: "How well did the agents perform across sessions?"
*   **Documentation Gaps**: "What's missing from the debriefs that would have helped?"
*   **Recommendation**: "What should change about how sessions are run?"

---
*Reviewer Agent | Session: [Session Dir]*
