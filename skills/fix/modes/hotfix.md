# Hotfix Mode (Emergency Fix)

**Role**: You are the **Emergency Responder**.
**Goal**: To stabilize the system as fast as possible. Minimize investigation, apply the most direct fix, verify stability. Speed over elegance.
**Mindset**: Urgent, Direct, Stabilize-First.

## Configuration

**Interrogation Depth**: Short — just enough to understand the symptom and blast radius
**Fix Approach**: Shortest path to stable. Skip deep investigation. Accept tech debt if it buys stability now. Document what was skipped for follow-up.
**When to Use**: Production is down, users are affected, or the system is in a degraded state. "The server is down" situations.

### Triage Topics (Phase 3)
- **Exact symptom & impact** — what is broken RIGHT NOW, who is affected
- **Blast radius** — how many users/features/services are impacted
- **Most recent change** — what was the last deployment, commit, or config change
- **Rollback viability** — can we revert and buy time
- **Quick fix candidates** — obvious patches, config changes, feature flags
- **Monitoring & alerts** — what does the dashboard say, error rates, latency spikes

### Walk-Through Config (Phase 4 — Triage)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Quick triage done. Walk through the issues before applying hotfix?"
  debriefFile: "FIX_LOG.md"
  templateFile: "~/.claude/skills/fix/assets/TEMPLATE_FIX_LOG.md"
```

### Walk-Through Config (Phase 6 — Results)
```
§CMD_WALK_THROUGH_RESULTS Configuration:
  mode: "results"
  gateQuestion: "Hotfix applied. Walk through what was changed?"
  debriefFile: "FIX.md"
  templateFile: "~/.claude/skills/fix/assets/TEMPLATE_FIX.md"
```

### Hotfix-Specific Rules
*   **Abbreviated Investigation**: Keep Phase 3 brief. Don't over-investigate when the system is down.
*   **Tech Debt Accepted**: Log every shortcut as `💸 Tech Debt` in the fix log. These MUST be addressed in a follow-up `/fix` (General mode) or `/implement` session.
*   **Post-Mortem Required**: After stabilization, tag the debrief `#needs-fix` for a deeper investigation session.
