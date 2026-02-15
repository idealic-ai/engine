### ¶CMD_VALIDATE_ARTIFACTS
**Definition**: Validates session artifacts before deactivation. Runs 3 validations sequentially — all must pass for `checkPassed=true` in `.state.json`.
**Usage**:
```bash
# Tag scan + request files only (no checklists)
engine session check <path> < /dev/null

# Tag scan + checklist validation + request files
engine session check <path> <<'EOF'
## CHECKLIST: /absolute/path/to/CHECKLIST.md
- [x] Item that was verified
EOF
```

---

## Validation 1: Tag Scan (`¶INV_ESCAPE_BY_DEFAULT`)

**Purpose**: Ensures no bare unescaped inline lifecycle tags remain in session artifacts.

**What it checks**: Scans all `.md` files in the session directory for bare `#needs-*`, `#claimed-*`, `#done-*` tags. Excludes:
*   Tags on the `**Tags**:` line (those are intentional)
*   Backtick-escaped references (`` `#needs-*` ``)

**On failure**: Exits 1 with a list of bare tags found (file:line: tag — context). Agent must address each via `§CMD_RESOLVE_BARE_TAGS` (promote, acknowledge, or escape), then set `tagCheckPassed=true`:
```bash
engine session update <path> tagCheckPassed true
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

- **`tagCheckPassed`**
  **Type**: boolean
  **Set By**: `engine session update`
  **Purpose**: Skips Validation 1 on re-run

- **`checkPassed`**
  **Type**: boolean
  **Set By**: `engine session check`
  **Purpose**: Master gate — all validations passed

- **`requestCheckPassed`**
  **Type**: boolean
  **Set By**: `engine session check`
  **Purpose**: Skips Validation 3 on re-run

- **`discoveredChecklists`**
  **Type**: string[]
  **Set By**: `engine session activate`
  **Purpose**: Input for Validation 2

- **`requestFiles`**
  **Type**: string[]
  **Set By**: `engine session activate`
  **Purpose**: Input for Validation 3

**Constraints**:
*   **`¶INV_ESCAPE_BY_DEFAULT`**: Backtick-escape tag references in validation output; bare tags only on `**Tags**:` lines or intentional inline.

---

## PROOF FOR §CMD_VALIDATE_ARTIFACTS

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "validationsPassed": {
      "type": "string",
      "description": "Count and names of passing validations (e.g., '3 passed: tags, checklists, requests')"
    },
    "validationsFailed": {
      "type": "string",
      "description": "Count and details of failures (e.g., '0 failed' or '1 failed: bare tags found')"
    }
  },
  "required": ["executed", "validationsPassed", "validationsFailed"],
  "additionalProperties": false
}
```
