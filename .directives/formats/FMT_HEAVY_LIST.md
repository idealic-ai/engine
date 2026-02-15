### ¶FMT_HEAVY_LIST

**When to use**: 5+ field entries or complex metadata. Full registry records, detailed subsystem docs, multi-field state descriptions.

**Rules**: Blank line between items. Bold key as title line, indented key-value pairs below (2-space indent). Use bold for sub-keys.

```markdown
*   **Sessions**
  *   **Entry Point**: `engine session`
  *   **What It Does**: Activate/deactivate sessions, phase tracking, heartbeat, context overflow recovery
  *   **Key Files**: `session.sh`, `.state.json`
  *   **Dependencies**: `lib.sh`, `json-schema-validate/`
  *   **Notes**: Core subsystem — all other subsystems depend on session state

*   **Tags**
  *   **Entry Point**: `engine tag`
  *   **What It Does**: Tag lifecycle management — add, remove, swap, find across session artifacts
  *   **Key Files**: `tag.sh`
  *   **Dependencies**: `lib.sh`
  *   **Notes**: Stateless coordination primitive for multi-agent work
```
