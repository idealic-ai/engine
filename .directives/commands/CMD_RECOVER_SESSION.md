### ¶CMD_RECOVER_SESSION
**Definition**: Re-initialize skill context after a context overflow restart.
**Implementation**: Handled by the `/session continue` subcommand. Protocol lives in `~/.claude/skills/session/references/continue-protocol.md`.
**Trigger**: Automatically invoked by `engine session restart` — you don't call this manually.

**What it does**:
1. Activates the session
2. Loads standards (COMMANDS.md, INVARIANTS.md, SIGILS.md)
3. Reads dehydrated context
4. Loads required files and skill templates
5. Loads original skill protocol
6. Skips to saved phase and resumes work

**See**: `~/.claude/skills/session/SKILL.md` for the full `/session` skill, and `references/continue-protocol.md` for the recovery protocol.

**Constraints**:
*   **`¶INV_TRUST_CACHED_CONTEXT`**: Do not re-read files already loaded from the dehydrated context.
*   **`¶INV_PROTOCOL_IS_TASK`**: The recovery protocol defines the task — do not skip steps.

---

## PROOF FOR §CMD_RECOVER_SESSION

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "executed": {
      "type": "string",
      "description": "What was accomplished (3-7 word self-quote)"
    },
    "recoverySucceeded": {
      "type": "string",
      "description": "Recovery outcome (e.g., 'recovered at Phase 3' or 'failed: no state')"
    },
    "sessionRecovered": {
      "type": "string",
      "description": "Absolute path to the recovered session directory"
    },
    "phaseResumed": {
      "type": "string",
      "description": "The phase resumed after recovery"
    },
    "filesLoaded": {
      "type": "string",
      "description": "Count and scope of files loaded (e.g., '6 files: log, plan, 4 source')"
    }
  },
  "required": ["executed", "recoverySucceeded"],
  "additionalProperties": false
}
```
