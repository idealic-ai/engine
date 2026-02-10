# Fix Debriefing (The Diagnostic Report)
**Tags**: #needs-review
**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/FIX.md`.

## 1. Executive Summary
*Status: [Resolved / Partial / Unresolved]*

*   **The Problem**: [Detailed summary of the issue — what was broken, who was affected, how it manifested]
*   **The Outcome**: [Detailed summary of the result — what was fixed, what remains]
*   **Fix Mode**: [General / TDD / Hotfix / Custom]
*   **Key Artifacts**:
    *   `src/path/to/fixed_file.ts` (Root cause fix)
    *   `src/path/to/test.ts` (Regression test)

## Related Sessions
*Prior work that informed this session (from session-search). Omit if none.*

*   `sessions/YYYY_MM_DD_TOPIC/DEBRIEF.md` — [Why it was relevant]

## 2. The Story of the Investigation (Narrative)
*Describe the diagnostic journey. Was it a quick find or a deep rabbit hole?*
"We started with the error message, which pointed at the wrong layer. The first two hypotheses were dead ends. On the third attempt, we discovered the root cause was a race condition in the event handler. The fix itself was trivial once the cause was found."

## 3. Plan vs. Reality (Deviation Analysis)
*Compare the `FIX_PLAN.md` to the actual investigation. Where did we pivot?*

### 🔀 Deviation 1: [Topic/Step]
*   **The Plan**: "We planned to investigate the database layer first."
*   **The Reality**: "The root cause was in the middleware, not the database."
*   **The Reason**: "The error message was misleading — it pointed to a query timeout, but the actual cause was a middleware that held the connection pool."

### 🔀 Deviation 2: [Topic/Step]
*   **The Plan**: ...
*   **The Reality**: ...
*   **The Reason**: ...

<!-- WALKTHROUGH RESULTS -->
## 4. Root Cause Analysis & Decisions
*For each significant bug found, document the forensic trail.*

### Bug 1: [Name]
*   **Symptom**: "API returns 500 on POST /claims."
*   **Root Cause**: "The middleware was holding the DB connection pool during auth validation."
*   **The Fix**: "Released the connection before the auth check."
*   **User Choice**: [Fix Code / Fix Test / Remove Test / Workaround] (If applicable)
*   **Confidence**: [Definitive / Strong / Moderate]

### Bug 2: [Name]
*   **Symptom**:
*   **Root Cause**:
*   **The Fix**:

## 5. The "War Story" (Key Friction)
*The hardest moment of the investigation — the misleading clue, the red herring, the "aha" moment.*

*   **The Trap**: "The error message said 'connection timeout' which sent us down the database path."
*   **The Symptom**: "Intermittent 500 errors under load."
*   **The Debug Trace**: "We profiled the DB, checked connection limits, reviewed queries — all clean."
*   **The Fix**: "The middleware was the bottleneck, not the database."
*   **The Lesson**: "Always profile the full request lifecycle, not just the layer mentioned in the error."

<!-- WALKTHROUGH RESULTS -->
## 6. The "Technical Debt" Ledger
*What shortcuts did we take or discover during fixing?*

### 💸 Debt Item 1: [Title]
*   **The Hack**: "Added a 5-second timeout as a safety net."
*   **The Cost**: "Masks the real issue if the middleware regresses."
*   **The Plan**: "Refactor the middleware to release connections properly."

### 💸 Debt Item 2: [Title]
*   ...

## 7. System Health (The Garden)
*What did we learn about the system's overall health?*

*   **Fragility**: "The connection pool has no monitoring — we only discovered the leak under load."
*   **Complexity**: "The middleware chain is 7 layers deep — hard to trace request flow."
*   **Zombie Code**: "Found 2 unused error handlers in the middleware stack."
*   **Coverage Gaps**: Where are we flying blind?
*   **Improvements**: What was pruned, refactored, or hardened?

<!-- WALKTHROUGH RESULTS -->
## 8. The "Parking Lot" (Unresolved)
*Issues we couldn't resolve in the timebox.*

*   **Issue**:
*   **Status**: [Skipped / Stuck / Needs More Data]
*   **Next Steps**: "Needs a dedicated Analysis Session / Performance Profiling / Production Logs."

<!-- WALKTHROUGH RESULTS -->
## 9. "Btw, I also noticed..." (Side Discoveries)
*Unrelated things found while investigating.*

*   **The Smell**: "The error logging doesn't include request IDs — impossible to correlate in production."
*   **The Curiosity**: "The auth middleware runs twice on WebSocket upgrade requests."
*   **The Sidetrack**: "The health check endpoint doesn't actually check database connectivity."

## 10. Agent's Expert Opinion (Subjective)
*Your unfiltered thoughts on the session.*

### 1. The Task Review (Subjective)
*   **Value**: "This was a critical fix — production was intermittently failing."
*   **Clarity**: "The initial report was vague, but reproduction was straightforward."
*   **Engagement**: "The misleading error message made this genuinely challenging."

### 2. The Result Audit (Honest)
*   **Quality**: "The fix is correct but the timeout safety net is tech debt."
*   **Robustness**: "Should hold under current load, but the connection pool needs monitoring."
*   **Completeness**: "Root cause fixed, but the broader middleware issue needs refactoring."

### 3. Personal Commentary (Unfiltered)
*   **The Watch**: "The middleware stack needs simplification — 7 layers is too many."
*   **The Surprise**: "The error message was completely misleading."
*   **The Advice**: "Add request-scoped connection tracking before the next load test."
