# Intake Curation Log
**Usage**: Append-only stream of intake actions. Track what came in, how it was organized, what was promoted, what was synced.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `log.sh`.

## ▶️ Pass Opened
*   **Initiative**: [which improvement / Linear Project]
*   **Project**: [Linear Project URL/ID]
*   **Watermark**: [last-synced Inbox comment timestamp]

## 📥 Ingest
*   **Source**: [Inbox comments / Inboxes-milestone threads / dropped in chat]
*   **Count**: [N new items]
*   **Excluded**: [N self-authored replies filtered]
*   **Watermark advanced to**: [timestamp — AFTER items written to doc]

## 🧩 Organize
*   **Clustered**: [N raw items → M clusters]
*   **Dedup**: [links drawn — "seems like Y"]
*   **Classified**: [conversational / research / action counts]
*   **Ranked**: [top clusters by impact + the proof/evidence pointer (reserved seam)]

## 🎫 Promote
*   **Nominated (ripe)**: [items that passed the checklist]
*   **Confirmed by user**: [which]
*   **Filed**: `FIN-XXX` under [milestone] — brief: [type]
*   **Deferred**: [items kept marinating + why]

## 🔄 Sync
*   **Project description**: [updated / unchanged]
*   **Project Update posted**: [summary — marinating / ripe / filed / rejection + staleness counts]
*   **Research snapshot**: [updated / n/a]

## 💡 Note / Decision
*   **Observation**: [something noticed while curating]
*   **Choice**: [a judgment made + why]
