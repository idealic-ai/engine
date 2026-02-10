# Adversarial Analysis: [Subject Under Scrutiny]
**Tags**: #needs-review
**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/BRAINSTORM.md`

## 1. Executive Summary
*   **Subject**: [What was stress-tested — a design, architecture, plan, or assumption set]
*   **Verdict**: [Robust / Fragile / Mixed — one-word assessment + 1-sentence summary]
*   **Critical Findings**: [Count] assumptions challenged, [Count] failure modes identified, [Count] survived scrutiny

## Related Sessions
*Prior work that informed this session (from session-search). Omit if none.*

*   `sessions/YYYY_MM_DD_TOPIC/DEBRIEF.md` — [Why it was relevant]

## 2. Assumption Audit
*Every assumption we found and challenged. The goal is to make the implicit explicit.*

### Assumption 1: [Statement — what was taken for granted]
*   **Status**: [Validated / Invalidated / Unverifiable]
*   **Evidence**: [What supports or contradicts this assumption]
*   **Impact if Wrong**: [What breaks if this assumption fails]
*   **Mitigation**: [How to protect against assumption failure]

### Assumption 2: [Statement]
*   **Status**: [Validated / Invalidated / Unverifiable]
*   **Evidence**: [Support or contradiction]
*   **Impact if Wrong**: [Consequences]
*   **Mitigation**: [Protection]

*(Repeat for all identified assumptions.)*

## 3. Failure Scenario Register
*Assume the subject failed. Here's how.*

### Scenario 1: [Failure Title]
*   **Trigger**: [What event or condition causes this failure]
*   **Mechanism**: [How does the failure propagate — the chain of events]
*   **Blast Radius**: [What gets affected — scope of damage]
*   **Likelihood**: [High / Medium / Low]
*   **Severity**: [Critical / High / Medium / Low]
*   **Detection**: [How would we know this is happening? How fast?]
*   **Recovery**: [What do we do when this happens]

### Scenario 2: [Failure Title]
*   **Trigger**: [Condition]
*   **Mechanism**: [Chain]
*   **Blast Radius**: [Scope]
*   **Likelihood**: [H/M/L]
*   **Severity**: [C/H/M/L]
*   **Detection**: [Signal]
*   **Recovery**: [Response]

*(Repeat for all identified scenarios.)*

## 4. Counter-Arguments
*The strongest arguments against the current approach — steelmanned, not strawmanned.*

### Counter 1: [The Argument]
*   **Source**: [Who would make this argument — what perspective]
*   **Strength**: [Strong / Moderate / Weak — how compelling is it]
*   **Response**: [How the current approach addresses or fails to address this]

### Counter 2: [The Argument]
*   **Source**: [Perspective]
*   **Strength**: [S/M/W]
*   **Response**: [Rebuttal or acknowledgment]

## 5. Risk Matrix

| Risk | Likelihood | Severity | Risk Score | Mitigation Status |
|------|-----------|----------|------------|-------------------|
| [Risk 1] | [H/M/L] | [C/H/M/L] | [H/M/L] | [Mitigated / Unmitigated / Accepted] |
| [Risk 2] | [H/M/L] | [C/H/M/L] | [H/M/L] | [Status] |
| [Risk 3] | [H/M/L] | [C/H/M/L] | [H/M/L] | [Status] |

## 6. Survival Analysis
*Which aspects of the subject withstood scrutiny and which didn't.*

### Survived
*   [Aspect that held up under stress-testing + why it's robust]
*   [Aspect that held up]

### Weakened
*   [Aspect that partially broke + what needs strengthening]
*   [Aspect that partially broke]

### Broken
*   [Aspect that failed scrutiny + recommended action]
*   [Aspect that failed]

## 7. Recommendations
1.  **Immediate**: [Action to address critical findings]
2.  **Strengthen**: [Action to harden weakened areas]
3.  **Monitor**: [What to watch for — early warning signals]
4.  **Accept**: [Risks deliberately accepted with rationale]

## 8. Agent's Expert Opinion (Subjective)

### 1. The Scrutiny Review
*   **Thoroughness**: [How deeply did we probe — High/Medium/Low]
*   **Biggest Concern**: [The one thing that worries me most]
*   **Biggest Surprise**: [What I didn't expect to find]
*   **Overall Assessment**: [Honest evaluation of the subject's resilience]

---
*Red Team Lead | Session: [Session Dir]*
