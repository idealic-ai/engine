# Coordinate Log Schemas (The Decision Recorder)
**Usage**: Capture coordinator decisions, escalations, and worker interactions. Do not log routine option selections.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `engine log`.

## 🔍 Worker Question Detected
*   **Pane**: `[pane_id]`
*   **Worker Skill**: `[skill_name]`
*   **Question**: "[The AskUserQuestion text]"
*   **Options**: [List of available options]
*   **Context**: "[Surrounding preamble text from the worker]"

## ✅ Autonomous Decision
*   **Pane**: `[pane_id]`
*   **Question**: "[Brief question summary]"
*   **Decision**: "[What was chosen and why]"
*   **Confidence**: [High / Medium]
*   **Response Sent**: "[Exact text sent via tmux send-keys]"

## ⚠️ Pre-Escalation Probe
*   **Pane**: `[pane_id]`
*   **Question**: "[Brief question summary]"
*   **Initial Confidence**: [Low]
*   **Probe Sent**: "[Text sent to request explanation]"
*   **Worker Response**: "[What the worker explained]"
*   **Outcome**: [Decided autonomously / Escalated to human]

## 🚨 Escalation to Human
*   **Pane**: `[pane_id]`
*   **Question**: "[The full question text]"
*   **Reason**: [Category rule: {category} / Low confidence after probe / Unknown context]
*   **Worker Blocked**: Yes — awaiting human input
*   **Human Action Required**: "[What the human needs to do]"

## 🔄 Human Resolution
*   **Pane**: `[pane_id]`
*   **Original Escalation**: "[Brief reference]"
*   **Human Decision**: "[What the human chose]"
*   **Learning**: "[What this teaches the coordinator for future decisions]"

## 📊 Task Transition
*   **Pane**: `[pane_id]`
*   **Previous Task**: "[Skill + summary]"
*   **New Task**: "[Skill + summary]"
*   **Trigger**: [Worker completed synthesis / Coordinator redirected / Human assigned]

## 👁️ Observation
*   **Focus**: `[Topic]`
*   **Detail**: "[What was noticed]"
*   **Implication**: "[Why it matters]"
*   **Action**: [Logged only / Will escalate if pattern continues]

## 💤 Idle Check
*   **Duration**: "[Time since last worker activity]"
*   **Active Panes**: [N]
*   **Blocked Panes**: [N waiting on human]
*   **Status**: [All workers active / Some idle / Fleet quiet]
