### §CMD_GATE_PHASE
**Definition**: Standardized phase boundary menu. Presents options to proceed (with proof), walk through current output, go back, or take a skill-specific action. Derives current/next/previous phases from the `phases` array in `.state.json`.
**Concept**: "What do you want to do at this phase boundary?"
**Trigger**: Called by skill protocols at phase boundaries.

---

## Configuration

Each invocation is configured inline in the skill's SKILL.md. Since the phases array declares the sequence, only the optional `custom` field is needed:

```
Execute `§CMD_GATE_PHASE`.
```

Or with a custom 4th option:

```
Execute `§CMD_GATE_PHASE`:
  custom: "Label | Description"
```

**Fields**:
*   `custom` — Optional 4th option. Format: `"Label | Description"`. If omitted, the menu has 3 options.

**Derived from `.state.json`**:
*   `currentPhase` — Read from `.state.json`. Used as the completed phase in the question text.
*   `nextPhase` — The next sequential phase in the `phases` array (sort by major, minor; find first after current).
*   `prevPhase` — The previous phase in the `phases` array (sort by major, minor; find last before current).

---

## Algorithm

### Step 1: Derive Phases

Read `currentPhase` from `.state.json`. Look up the `phases` array to determine:
*   **Next phase**: First entry after current (by major.minor order).
*   **Previous phase**: Last entry before current (by major.minor order).
*   **Current phase proof fields**: The `proof` array on the current phase entry (if declared). Proof validates what was just completed (FROM validation).

### Step 2: Present Menu

Execute `AskUserQuestion` (multiSelect: false):

> "Phase [currentPhase] complete. How to proceed?"
> - **"Proceed to [nextPhase]"** — Continue to the next phase
> - **"Walkthrough"** — Review this phase's output before moving on
> - **"Go back to [prevPhase]"** — Return to the previous phase
> - **"[custom label]"** *(if configured)* — [custom description]

**Option order**: Proceed (default forward path) > Walkthrough > Go back > Custom.

### Step 3: Execute Choice

*   **"Proceed"**: Pipe proof fields via STDIN to `engine session phase` for the current phase (proving it was completed). If the current phase declares `proof` fields, you MUST provide them as `key: value` lines. See **Proof-Gated Transitions** below.

*   **"Walkthrough"**: Invoke `§CMD_WALK_THROUGH_RESULTS` ad-hoc on the current phase's artifacts. After the walk-through completes, **re-present this same menu**.

*   **"Go back"**: Fire `§CMD_UPDATE_PHASE` with `prevPhase` and `--user-approved "User chose 'Go back to [prevPhase]'"`. Return control to the skill protocol for the previous phase.

*   **"[custom]"**: Execute the skill-specific action described in the custom option. The skill protocol defines what this does (e.g., skip forward, launch agent, run verification).

*   **"Other" (free-text)**: The user typed something outside the options. Treat as new input:
    *   If it describes new requirements -> route to interrogation phase (use `§CMD_UPDATE_PHASE` with `--user-approved`).
    *   If it's a clarification -> answer in chat, then re-present the menu.

---

## Proof-Gated Transitions

When the current phase (being left) declares `proof` fields in the phases array, the agent must pipe proof as `key: value` lines via STDIN to `engine session phase`. This is FROM validation — you prove what you just completed, not what you're about to start.

**Example** (leaving Phase 1: Context Ingestion which declares `proof: ["context_sources_presented", "files_loaded", "user_confirmed"]`):
```bash
engine session phase sessions/DIR "2: Interrogation" <<'EOF'
context_sources_presented: menu shown with 3 RAG items
files_loaded: 5 files loaded
user_confirmed: yes
EOF
```

**Validation**: `session.sh` checks that all proof fields declared on the current phase are present and non-blank. Missing or unfilled fields reject the transition (exit 1).

**No proof declared**: If the current phase has no `proof` array, the transition proceeds normally without STDIN.

---

## Constraints

*   **Max 4 options**: AskUserQuestion limit. 3 core + 1 custom. If no custom, 3 options (+ implicit "Other").
*   **Walkthrough is always available**: `§CMD_WALK_THROUGH_RESULTS` works ad-hoc on whatever artifacts exist in the session directory.
*   **Go back uses --user-approved**: Backward transitions are non-sequential per `§CMD_UPDATE_PHASE` enforcement. The user's menu choice is auto-quoted as the approval reason.
*   **Re-presentation after walkthrough**: After a walkthrough completes, the menu is shown again.
*   **First phase edge case**: If there is no previous phase, omit the "Go back" option. Menu becomes 2 core + optional custom.

---

## Special Cases

**Do NOT use this command for**:
*   **Phase 0 -> Phase 1** -> Setup always proceeds to the next phase. No user question needed — just flow through.
*   **`§CMD_EXECUTE_INTERROGATION_PROTOCOL` exit gate** -> The interrogation protocol handles its own exit with depth-based gating. However, when the user selects "Proceed to next phase", fire this command for the actual transition.
*   **`§CMD_PARALLEL_HANDOFF` boundaries** -> Plan -> Build transitions that offer agent handoff keep their specialized menu.
*   **Synthesis phase transitions** -> Post-synthesis uses `§CMD_CLOSE_SESSION`.
