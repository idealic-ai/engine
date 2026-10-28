# Coordinate Log Schemas (The Decision Recorder)
**Usage**: Capture coordinator decisions, escalations, and worker interactions. Do not log routine option selections.
**Requirement**: Every entry header MUST use a `## ` heading. Timestamps are auto-injected by `engine log`.

## 🪜 Escalations (live — one row per hop a question makes into or out of this seat)
*The escalation register. It is **not a new row format**. It is `skills/loom/assets/TEMPLATE_LOOM_LOG.md`'s `📨 Seat handovers` row (IDE-162), kept as a live block in this session's own log the way IDE-130's registers are, plus one `disposition` cell. A pass-up is a vertical seat handover, so the handover row's rules carry over unchanged: write the row **before** the send; `sent` is a delivery reading and never a boolean; silence is not an ack; the row closes on the receiving seat's own words.*

*From, To: a `received` row is From = `seat`, To = this seat. A `sent` row is From = this seat, To = `seat`. `seat` is `operator` for a seat with no parent. The tier's falsifier is counted from these rows (`¶INV_HOP_IS_ROWED`).*

*`disposition` is a closed grammar, written by THIS seat: `answered` (ruled here, with class, condition and reversal in the matching `✅ Autonomous Decision`) · `probed` · `councilled` · `absorbed` · `passed up` · `superseded — passed up to <seat>` (a deliberate re-pass; the `ack` cell is left alone, because the sender never closes its own row) · `open`. On a `sent` row it reads `passed up`, and the row stays open until `ack` holds the receiving seat's own words. ⚠️ IDE-162's ack half is weak ("routing still happens by message"). An answer that reached only this seat's chat is not an ack until it is written into the row.*

*One row per ask, keyed by `ask:<id>` in `member links` (the /ask id, or `hop.sh ask-id` for an AskUserQuestion). `hop.sh rowed` checks for it before a row is written, so a worker that `await-next` re-emits is not rowed twice. A floor or reserved item carries `reserved-for: operator` at the start of its topic cell, and on such a row only the operator's answer closes `ack`.*

*`/sweep` must recognise this block or its rows read as UNROWED. That means adding `🪜 Escalations` to IDE-155's recognised list, a change that belongs to `/sweep`'s owner.*

| direction | seat (from-name · pane id) | the topic | member links | sent | ack | disposition |
|-----------|----------------------------|-----------|--------------|------|-----|-------------|
| [`received` \| `sent`] | `manager:director` · `%114` \| `operator` | [`reserved-for: operator` — when marked] [the question, as the receiving seat will read it] | [`ask:<id>` · /ask file path · worker pane · ticket key] | [timestamp · `queued` \| `delivered` \| `send failed — [what]` \| `re-pinged HH:MM`] | [`taken` — [the answer, in the seat's words] \| `declined — [why]` \| `open — [what leaves it open]`] | [`answered` \| `probed` \| `councilled` \| `absorbed` \| `passed up` \| `superseded — passed up to <seat>` \| `open`] |

## ⬆️ Pass-up
*   **From**: `[this seat]` → **To**: `[parent seat · pane id | operator]`
*   **Raised by**: `[the seat that asked — never this seat for a ruling; its own forks always pass up]`
*   **Question**: "[Brief question summary]"
*   **Why it could not be ruled here**: [hop.sh may-rule reason | category rule | low confidence after probe]
*   **Reserved for**: [`operator` — floor or reserved class; forward only | —]
*   **Edge reading**: [hop.sh target exit and stderr — e.g. `exit 3: 'manager:ghost' names no live pane — skipped to manager:director`]
*   **Recommendation**: "[lean · why · falsifier]"
*   **Carrier**: [/ask file path (per /ask) | one-line note — /ask not installed]
*   **Register row**: [the `sent` row written before this send]

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
*   **Raised by**: `[the asking seat — a ruling on this seat's own fork is forbidden]`
*   **Class**: [orientation | a class the installed grant holds — never E, F, G, nor H while unmarked]
*   **Condition**: "[the grant condition this ruling relied on]"
*   **Reversal**: "[what would reverse it]"

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
*   **Resolved by**: [operator | the parent seat that answered a pass-up — `seat · pane id`]
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
