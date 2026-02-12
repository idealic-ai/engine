### §CMD_RECOVER_SESSION
**Definition**: Re-initialize skill context after a context overflow restart.
**Implementation**: Handled by the `/session continue` subcommand. Protocol lives in `~/.claude/skills/session/references/continue-protocol.md`.
**Trigger**: Automatically invoked by `engine session restart` — you don't call this manually.

**What it does**:
1. Activates the session
2. Loads standards (COMMANDS.md, INVARIANTS.md, TAGS.md)
3. Reads dehydrated context
4. Loads required files and skill templates
5. Loads original skill protocol
6. Skips to saved phase and resumes work

**See**: `~/.claude/skills/session/SKILL.md` for the full `/session` skill, and `references/continue-protocol.md` for the recovery protocol.
