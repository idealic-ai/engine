# Oversight Debriefing (The Manager's Report)
**Tags**: #needs-review
**Filename Convention**: `sessions/[YYYY_MM_DD]_[TOPIC]/COORDINATE.md`.

## 1. Executive Summary
*Status: [Active / Completed / Interrupted]*

*   **Duration**: [How long the coordinator ran]
*   **Workers Monitored**: [N panes]
*   **Total Decisions**: [N autonomous + N escalated]
*   **Autonomy Rate**: [N%] (autonomous / total)

## Related Sessions
*Prior work that informed this session (from session-search). Omit if none.*

*   `sessions/YYYY_MM_DD_TOPIC/DEBRIEF.md` — [Why it was relevant]

## 2. Decision Summary

### Autonomous Decisions ([N])
| # | Pane | Question (brief) | Decision | Confidence |
|---|------|-------------------|----------|------------|
| 1 | @1   | Mode selection    | Chose General | High |

### Escalations ([N])
| # | Pane | Question (brief) | Reason | Human Decision |
|---|------|-------------------|--------|----------------|
| 1 | @2   | Delete old tests? | Category: deletion | Keep them |

### Pre-Escalation Probes ([N])
| # | Pane | Question | Probe Result | Final Outcome |
|---|------|----------|--------------|---------------|
| 1 | @1   | Auth strategy | Worker clarified: JWT | Decided: JWT |

## 3. Worker Activity

### Pane @[id]: [worker name]
*   **Tasks Completed**: [N]
*   **Skills Used**: [/implement, /test, ...]
*   **Decisions Made For**: [N]
*   **Escalations**: [N]
*   **Notable Events**: "[Brief narrative]"

## 4. Escalation Pattern Analysis
*What categories triggered escalation? Any patterns?*

*   **Most Common Category**: [category]
*   **Confidence Distribution**: [How often was the coordinator confident vs not]
*   **Recommendations**: "[Adjust threshold? Add new category rules?]"

## 5. Config Effectiveness
*How well did the config rules work?*

*   **Config Used**: `[path to coordinate.config.json]`
*   **Rules That Fired**: [List of category rules that triggered]
*   **Suggested Changes**: "[Any rules to add/remove/adjust]"

## 6. Agent's Expert Opinion (Subjective)

### 1. The Task Review (Subjective)
*   **Value**: "[Was the oversight useful?]"
*   **Efficiency**: "[How much human time was saved?]"
*   **Quality**: "[Were autonomous decisions correct?]"

### 2. The Result Audit (Honest)
*   **Mistakes**: "[Any decisions the coordinator got wrong?]"
*   **Missed Escalations**: "[Anything that should have been escalated but wasn't?]"
*   **Over-Escalations**: "[Anything escalated that could have been autonomous?]"

### 3. Personal Commentary (Unfiltered)
*   **The Worry**: "[What concerns the coordinator about the fleet's work]"
*   **The Surprise**: "[Unexpected observations]"
*   **The Advice**: "[Recommendations for the human]"
