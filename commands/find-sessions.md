---
description: Finds sessions by tag, date, topic, or time. Usage: /find-sessions #needs-review
version: 2.0
---

Parse `$ARGUMENTS` to determine the subcommand:

- **Starts with `#`**: Run `~/.claude/scripts/find-sessions.sh tag '$ARGUMENTS' --debriefs`
- **`today`/`yesterday`/`recent`/`active`/`all`**: Run `~/.claude/scripts/find-sessions.sh $ARGUMENTS --debriefs`
- **A date like `2026_02_03`**: Run `~/.claude/scripts/find-sessions.sh date $ARGUMENTS --debriefs`
- **Any other word**: Run `~/.claude/scripts/find-sessions.sh topic $ARGUMENTS --debriefs`
- **No arguments**: Run `~/.claude/scripts/find-sessions.sh recent --debriefs`

If the user appended `--files`, replace `--debriefs` with `--files`.

Show the results as a clean list. If no sessions found, say "No sessions found."

This is a lightweight command — no session dir, no log, no standards loading. Just run the script and show results.
