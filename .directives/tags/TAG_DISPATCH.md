## ¶TAG_DISPATCH
*   **Purpose**: Maps `#needs-*` tags to their resolving skills and defines daemon dispatch behavior. Used by `/delegation-claim`, daemon, and `/find-tagged` to route deferred work to the correct skill.
*   **Rule**: Every `#needs-X` tag maps to exactly one skill `/X`. See `¶INV_1_TO_1_TAG_SKILL`.
*   **Daemon monitors**: `#delegated-*` only (NOT `#needs-*` or `#next-*`). See `¶INV_NEEDS_IS_STAGING`, `¶INV_NEXT_IS_IMMEDIATE`.
*   **Registry**:

*   **brainstorm**
  *   **Resolving Skill**: `/brainstorm`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 1 (exploration unblocks decisions)

*   **direct**
  *   **Resolving Skill**: `/direct`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 1.5 (vision unblocks coordinator)

*   **research**
  *   **Resolving Skill**: `/research`
  *   **Mode**: async (Gemini)
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 2 (queue early)

*   **fix**
  *   **Resolving Skill**: `/fix`
  *   **Mode**: interactive/agent
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 3 (bugs block progress)

*   **implementation**
  *   **Resolving Skill**: `/implement`
  *   **Mode**: interactive/agent
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 4

*   **loop**
  *   **Resolving Skill**: `/loop`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 4.5 (iteration workloads)

*   **chores**
  *   **Resolving Skill**: `/chores`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 5 (quick wins, filler)

*   **documentation**
  *   **Resolving Skill**: `/document`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: Yes
  *   **Priority**: 6

*   **review**
  *   **Resolving Skill**: `/review`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: No (user-invoked only)
  *   **Priority**: 7

*   **rework**
  *   **Resolving Skill**: `/review`
  *   **Mode**: interactive
  *   **Daemon-Dispatchable**: No (user-invoked only)
  *   **Priority**: 7

*   **Extensibility**: To add a new dispatchable tag, add a row to this table and create the corresponding `§FEED_*` section above. The tag noun MUST match the skill name (`¶INV_1_TO_1_TAG_SKILL`).
*   **Priority**: Resolves in priority order (1 first). Brainstorming unblocks decisions; research is async so queue early; fixes unblock progress; implementation is the main work; chores fill gaps; documentation after code; review last.
*   **Daemon-Dispatchable**: Only tags marked "Yes" will be picked up by the daemon when in `#delegated-*` state. Tags marked "No" are resolved manually by the user.
*   **Immediate path**: Any daemon-dispatchable tag also supports `#next-X` (immediate next-skill execution). `#next-X` items are auto-claimed by the matching skill on activation. `/delegation-review` surfaces stale `#next-X` items for re-routing.
