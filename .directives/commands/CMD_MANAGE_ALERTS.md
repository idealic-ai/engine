### ¶CMD_MANAGE_ALERTS
**Definition**: During synthesis, checks whether the current session's work warrants raising or resolving an alert. Replaces the former `/alert-raise` and `/alert-resolve` standalone skills.
**Classification**: STATIC
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
1.  **Discover**: Run `engine tag find '#active-alert' --tags-only` in `sessions/`. The `--tags-only` flag restricts to Tags-line matches (Pass 1 only), eliminating false positives from body text that discusses `#active-alert` without being tagged with it.
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
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape tag references in chat output and log entries; bare tags only on `**Tags**:` lines or in `engine tag` commands.

---

## PROOF FOR §CMD_MANAGE_ALERTS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "alertsRaised": {
      "type": "string",
      "description": "Count and topics of alerts raised (e.g., '1 raised: schema migration')"
    },
    "alertsResolved": {
      "type": "string",
      "description": "Count and topics of alerts resolved"
    }
  },
  "required": ["executed", "alertsRaised", "alertsResolved"],
  "additionalProperties": false
}
```
