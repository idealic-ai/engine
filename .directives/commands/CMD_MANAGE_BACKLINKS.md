### ¶CMD_MANAGE_BACKLINKS
**Definition**: During synthesis, creates and maintains cross-document links between related sessions and artifacts. Ensures the knowledge graph is connected — continuations, analysis→implementation chains, delegation flows, and topical relationships are all discoverable.
**Classification**: STATIC

**Why**: Sessions don't exist in isolation. An analysis session produces findings that drive an implementation session. A session overflows and continues in a new context. A delegation creates a requester→responder chain. Without backlinks, these relationships are invisible — the knowledge graph is a collection of disconnected nodes.

**Link Types**:

- **Continuation**
  **Forward Link**: `Continued in: [session]`
  **Backward Link**: `Continued from: [session]`
  **When**: Session overflow restart, `/session continue`, same-topic follow-up

- **Derived work**
  **Forward Link**: `Informed: [session]`
  **Backward Link**: `Based on: [session]`
  **When**: Analysis → implementation, brainstorm → implementation, research → implementation

- **Delegation**
  **Forward Link**: `Delegated to: [session]`
  **Backward Link**: `Requested by: [session]`
  **When**: REQUEST/RESPONSE file chains

- **Related**
  **Forward Link**: `See also: [session]`
  **Backward Link**: `See also: [session]`
  **When**: Same topic, different angle (symmetric)

**Algorithm**:

1.  **Detect Relationships**: From the current session's context, identify:
    *   **Continuations**: Was this session created via `/session continue`? Check `phaseHistory` for `♻️ Context Overflow Restart` or `♻️ Manual Session Resume` entries. Check `DETAILS.md` for continuation references.
    *   **Derived work**: Does the session's `contextPaths` or `ragDiscoveredPaths` reference another session's debrief? Did the user mention a prior session during interrogation?
    *   **Delegations**: Are there REQUEST files in this session pointing to other sessions? Are there RESPONSE files written by this session for other sessions' requests?
    *   **Related**: Do RAG search results from activation suggest topically similar sessions?
2.  **Collect Candidates**: For each detected relationship, record:
    *   Source session (current)
    *   Target session (the related one)
    *   Link type (continuation, derived, delegation, related)
    *   Evidence (how the relationship was detected)
3.  **If No Candidates**: Output in chat: "No cross-session relationships detected." No log entry.
4.  **Auto-Apply All Links**: For each candidate, add a `## Related Sessions` section to both debriefs (or append to existing). No user prompt — all detected links are created automatically.
    *   **In current session's debrief**:
        ```markdown
        ## Related Sessions
        *   **[Link type]**: [target session path] — [one-line context]
        ```
    *   **In target session's debrief** (backward link):
        ```markdown
        ## Related Sessions
        *   **[Backward link type]**: [current session path] — [one-line context]
        ```
    *   If the target debrief doesn't exist (session incomplete or no debrief), skip the backward link and log: "Target debrief not found for [session]. Forward link only."
    *   If a `## Related Sessions` section already exists, append to it (don't duplicate existing links).
5.  **Report**: "Added N backlinks across M sessions." or skip silently if none.

**Constraints**:
*   **Debrief-only**: Links are added to debrief files (IMPLEMENTATION.md, ANALYSIS.md, etc.), not logs or plans. Debriefs are the durable artifacts.
*   **Idempotent**: Check existing `## Related Sessions` entries before adding. Never create duplicate links.
*   **Conservative**: Only create links with clear evidence. "Same general topic" is not enough — there must be a concrete connection (shared files, explicit references, delegation chain).
*   **Bidirectional**: Every link creates entries in BOTH debriefs (forward + backward). This ensures discoverability from either direction.

---

## PROOF FOR §CMD_MANAGE_BACKLINKS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "linksAdded": {
      "type": "string",
      "description": "Count and types of links added (e.g., '3 links: 2 continuation, 1 derived')"
    },
    "sessionsLinked": {
      "type": "string",
      "description": "Count of sessions linked (e.g., '2 sessions received new links')"
    }
  },
  "required": ["executed", "linksAdded", "sessionsLinked"],
  "additionalProperties": false
}
```
