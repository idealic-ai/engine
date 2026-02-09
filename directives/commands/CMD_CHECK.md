### §CMD_CHECK
**Definition**: Validates session artifacts before deactivation. Runs 3 validations sequentially — all must pass for `checkPassed=true` in `.state.json`.
**Trigger**: Called during synthesis phase, before `§CMD_GENERATE_DEBRIEF_USING_TEMPLATE`. Agents use `§CMD_PROCESS_TAG_PROMOTIONS` and `§CMD_PROCESS_CHECKLISTS` to address failures, then re-run check.

**Usage**:
```bash
# Tag scan + request files only (no checklists)
session.sh check <path> < /dev/null

# Tag scan + checklist validation + request files
session.sh check <path> <<'EOF'
## CHECKLIST: /absolute/path/to/CHECKLIST.md
- [x] Item that was verified
EOF
```

---

## Validation 1: Tag Scan (`¶INV_ESCAPE_BY_DEFAULT`)

**Purpose**: Ensures no bare unescaped inline lifecycle tags remain in session artifacts.

**What it checks**: Scans all `.md` files in the session directory for bare `#needs-*`, `#active-*`, `#done-*` tags. Excludes:
*   Tags on the `**Tags**:` line (those are intentional)
*   Backtick-escaped references (`` `#needs-*` ``)

**On failure**: Exits 1 with a list of bare tags found (file:line: tag — context). Agent must address each via `§CMD_PROCESS_TAG_PROMOTIONS` (promote, acknowledge, or escape), then set `tagCheckPassed=true`:
```bash
session.sh update <path> tagCheckPassed true
```

**Skip condition**: `tagCheckPassed=true` in `.state.json` (tags already addressed).

---

## Validation 2: Checklist Processing (`¶INV_CHECKLIST_BEFORE_CLOSE`)

**Purpose**: Ensures all discovered CHECKLIST.md files have been processed and quoted back.

**What it checks**: Reads `discoveredChecklists[]` from `.state.json`. For each discovered checklist, validates that stdin contains a matching `## CHECKLIST: /path` block with at least one checklist item (`- [x]` or `- [ ]`).

**On failure**: Exits 1 with missing or empty checklist blocks. Agent must process checklists via `§CMD_PROCESS_CHECKLISTS` (read `CMD_PROCESS_CHECKLISTS.md` for the algorithm), then re-run check with results on stdin.

**Skip condition**: `discoveredChecklists` is empty or missing (no checklists to process).

---

## Validation 3: Request Files (`¶INV_REQUEST_BEFORE_CLOSE`)

**Purpose**: Ensures all request files this session is fulfilling have been properly completed.

**What it checks**: Reads `requestFiles[]` from `.state.json`. For every file:
1.  **Exists**: The file must exist at the declared path.
2.  **No bare `#needs-*` tags**: The entire file is scanned — all `#needs-*` tags must be resolved (swapped to `#done-*`) or backtick-escaped. Backtick-escaped references (`` `#needs-*` ``) are excluded.
3.  **`## Response` section** (formal REQUEST files only): If the filename contains "REQUEST", it must additionally have a `## Response` section.

**On failure**: Exits 1 with a list of unfulfilled files and their specific failures. Agent must resolve all bare `#needs-*` tags (swap to `#done-*` or backtick-escape), and for REQUEST files also add a `## Response` section. Then re-run check.

**Skip condition**: `requestFiles` is empty/missing (no requests to fulfill) or `requestCheckPassed=true`.

**Response section format** (Type A only):
```markdown
## Response
Fulfilled by: sessions/YYYY_MM_DD_TOPIC/
Summary: [1-2 lines of what was done]
```

---

## State Fields

| Field | Type | Set By | Purpose |
|-------|------|--------|---------|
| `tagCheckPassed` | boolean | `session.sh update` | Skips Validation 1 on re-run |
| `checkPassed` | boolean | `session.sh check` | Master gate — all validations passed |
| `requestCheckPassed` | boolean | `session.sh check` | Skips Validation 3 on re-run |
| `discoveredChecklists` | string[] | `session.sh activate` | Input for Validation 2 |
| `requestFiles` | string[] | `session.sh activate` | Input for Validation 3 |
