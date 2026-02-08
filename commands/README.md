# Light Commands

Flat-file commands that run inline without session overhead. Unlike skills (which have full protocols, logging, and session directories), commands are lightweight utilities — they execute a script, show results, and return.

Commands live as `.md` files in `engine/commands/`. Each file has YAML frontmatter (`description`, `version`) and a short execution protocol. They're symlinked into `~/.claude/commands/` by `engine.sh`.

## Command Reference

| Command | Description | Usage |
|---------|-------------|-------|
| `/details` | Records a structured Q&A exchange — captures user assertions, agent responses, and decisions verbatim | `/details` |
| `/find-sessions` | Searches sessions by tag, date, topic, or time | `/find-sessions #needs-review`, `/find-sessions today` |
| `/find-tagged` | Finds files containing a specific tag | `/find-tagged #needs-review` |
| `/fleet` | Interactive multi-agent workspace designer — configures tmux panes and agent roles | `/fleet` |

## Commands vs Skills

| | Commands | Skills |
|---|---------|--------|
| **Protocol** | 1-3 steps | Multi-phase (Setup → Research → Synthesis) |
| **Session** | No session directory | Creates `sessions/YYYY_MM_DD_TOPIC/` |
| **Logging** | No log file | Append-only `*_LOG.md` |
| **Standards** | Some load standards, some don't | Always load standards |
| **Output** | Inline chat results | Files (debrief, plan, log) |
| **Location** | `engine/commands/*.md` | `engine/skills/<name>/SKILL.md` |

## Adding a Command

Create a new `.md` file in `engine/commands/` with:

```yaml
---
description: One-line description of what the command does.
version: 1.0
---
```

Then write the execution protocol below the frontmatter. Keep it simple — if it needs phases, logging, or a session directory, it should be a skill instead.
