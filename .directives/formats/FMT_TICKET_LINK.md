### ¶FMT_TICKET_LINK

**When to use**: EVERY mention of a tracker issue key — in chat or in a `.md` artifact — renders as a **labeled link** to the issue, never a bare key. The file-link sibling (`¶FMT_FILE_LINK`) for tickets.

**Rules** (config-driven — do NOT hardcode the tracker):
*   Source the **issue-key prefix** and the **issue-URL template** from the project's `## Tracker` config (the project `CLAUDE.md`) — e.g. Finch: prefix `FIN`, URL `https://linear.app/finchclaims/issue/<KEY>`. Other projects set their own; this format never bakes in a specific tracker.
*   Render `[<KEY>](<issue-url-with-KEY-substituted>)` — e.g. `[FIN-3141](https://linear.app/finchclaims/issue/FIN-3141)`.
*   Applies to keys matching the project's prefix (`FIN-3141`). A bare key with no `## Tracker` config configured → leave as plain text (nothing to link to).

```markdown
Fixed in [FIN-3141](https://linear.app/finchclaims/issue/FIN-3141); follow-up is [FIN-3200](https://linear.app/finchclaims/issue/FIN-3200).
```

**Anti-pattern**: a bare `FIN-3141` in prose when a `## Tracker` issue-URL is configured; hardcoding a tracker URL in the engine instead of sourcing it from the project config.
