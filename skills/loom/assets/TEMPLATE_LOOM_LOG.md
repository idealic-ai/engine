# Loom Log (The Conductor's Journal)
**Usage**: Track the weave — thread intake, the live ledger, conflicts brokered, escalations, and each thread's advance through the chain.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## ▶️ Loom Opened
*   **Batch**: [what tickets/tasks are in scope]
*   **Dispositions**: Autonomy=[Automagic|Careful|Allow-agents] · Council=[selective|auto-after-pr|none] · Interrogation=[Reasonable|Thorough|None] · Detail=[Low|Balanced|High]

## 🧵 Ledger (live — rewrite in place as threads advance)
*The session's spine. One row per thread. Stages: triaged → interrogated → building → scrutinized → snapshotted → pr'd → council'd.*

| threadId | ticket | stage | PR | status |
|----------|--------|-------|----|--------|
| FIN-XXXX | [title] | building | — | in flight |
| A | [title] | interrogated | — | queued (wave 2) |

## 🌊 Wave
*   **Wave**: [N]
*   **Threads fanned out**: [threadIds]
*   **Partition**: [disjoint file sets, or note what serialized to a later wave and why]

## 📡 Relay / Conflict
*   **Event**: [file claim | conflict | deadlock | escalation]
*   **Threads**: [who ⇄ who]
*   **Resolution**: [first-claim-wins → loser deferred | granted | escalated to user → decision]

## ⬆️ Escalation
*   **Trigger**: [cyclic deadlock | build-fails-after-retries | scrutinize MUST-FIX | thread loopback]
*   **Thread**: [threadId]
*   **Posed as**: [the plain-language choice shown to the operator]
*   **Decision**: [what the user chose / recommended default taken]

## 🔧 Progress
*   **Thread**: [threadId]
*   **Stage advance**: [from → to]
*   **Notes**: [Build Report path, critique outcome, snapshot/pr/council result]

## 🅿️ Parked
*   **Thread**: [threadId]
*   **Reason**: [not ripe (triangulate) | overlapping files (deferred) | user parked]

## 💡 Decision
*   **Choice**: "Chose A over B."
*   **Why**: "Reasoning."
