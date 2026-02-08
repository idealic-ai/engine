---
description: Finds files containing a tag. Usage: /find-files #needs-review
version: 1.0
---

Run `~/.claude/scripts/tag.sh find '$ARGUMENTS'` where `$ARGUMENTS` is the tag the user provided (e.g., `#needs-review`).

If the user also passed `--context`, append that flag.

Show the results. If no files found, say "No files found with that tag."

This is a lightweight command — no session dir, no log, no standards loading. Just run the script and show results.
