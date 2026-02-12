### §CMD_MANAGE_ALERTS
**Definition**: During synthesis, checks whether the current session's work warrants raising or resolving an alert. Replaces the former `/alert-raise` and `/alert-resolve` standalone skills.
**Trigger**: Called during synthesis, after `§CMD_GENERATE_DEBRIEF` and before `§CMD_REPORT_ARTIFACTS`. Agents should also call this proactively when they begin work that will temporarily break shared systems.

**Algorithm**:

#### Alert Raise Check
1.  **Evaluate**: Does this session's work temporarily break shared systems or change behavior that other agents depend on?
    *   Examples: modifying shared schemas, changing API contracts, restructuring file layouts, renaming conventions
    *   If NO: skip to Alert Resolve Check.
2.  **If YES**: Create an alert file:
    ```bash
    # Create the alert file in the session directory
    cat > "$SESSION_DIR/ALERT_RAISE_[TOPIC].md" << 'ALERT'
    # Alert: [Brief description of what's broken/changing]
    **Tags**: #active-alert

    ## What Changed
    [1-3 bullet points describing the change]

    ## Impact
    [Who/what is affected. Which agents, files, or workflows need to be aware.]

    ## Expected Duration
    [When this will be resolved — "this session", "next session", "after X is done"]

    ## Workaround
    [If any — how to work around the breakage until resolved. "None" if unavoidable.]
    ALERT
    ```
3.  **Tag**: The file is created with `#active-alert` on its Tags line. This makes it discoverable by `§CMD_FIND_TAGGED_FILES` and loaded into new agent sessions via `§FEED_ALERTS`.

#### Alert Resolve Check
1.  **Discover**: Run `engine tag find '#active-alert'` in `sessions/`.
2.  **For each active alert**: Read the alert file. Evaluate whether this session's work resolves the issue described.
3.  **If resolved**:
    ```bash
    engine tag swap "$ALERT_FILE" '#active-alert' '#done-alert'
    ```
    Append a `## Resolution` section to the alert file:
    ```markdown
    ## Resolution
    *   **Date**: [YYYY-MM-DD]
    *   **Resolved by**: [session directory]
    *   **Action**: [What was done to resolve]
    ```
4.  **If NOT resolved**: Leave the alert active. No action needed.
5.  **Report**: If any alerts were raised or resolved, log to the session's `_LOG.md`:
    ```bash
    engine log [sessionDir]/[LOG_NAME].md <<'EOF'
    ## 🚨 Alert Management
    *   **Raised**: [N] alerts ([list topics])
    *   **Resolved**: [N] alerts ([list topics])
    *   **Still Active**: [N] alerts
    EOF
    ```

**Constraints**:
*   **Non-blocking on empty**: If no alerts to raise or resolve, skip silently.
*   **Judgment-based**: The agent uses judgment to assess whether work warrants an alert. Not every change needs one — only changes that affect shared systems or break other agents' expectations.
*   **Proactive raising**: Agents should raise alerts at the START of disruptive work, not just at synthesis. Call the raise portion as soon as you know you'll break something.
*   **Tag operations only**: Uses `engine tag add` and `engine tag swap`. No new scripts needed.

---

## PROOF FOR §CMD_MANAGE_ALERTS

This command is a synthesis pipeline step. It produces no standalone proof fields — its execution is tracked by the pipeline orchestrator (`§CMD_RUN_SYNTHESIS_PIPELINE`).
