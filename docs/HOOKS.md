# Fleet Notification Hooks

This document describes the tmux notification system for the Claude Code fleet.

## State Model (v2)

| Priority | State | Color | Meaning | Clears When |
|----------|-------|-------|---------|-------------|
| 1 | `error` | Red BG | Tool denied, hook failure | Manual clear or success |
| 2 | `unchecked` | Orange BG | Needs user input (not yet seen) | Focus pane → `checked` |
| 3 | `working` | Blue BG | Agent actively processing | Stop → `done` |
| 4 | `checked` | Gray BG | User saw it (not yet responded) | User responds → `working` |
| 5 | `done` | No color | Agent finished, awaiting next task | Default state |

## State Transitions

```
                    ┌──────────────────┐
                    │      done        │ (no color)
                    └────────┬─────────┘
                             │ Notification hook
                             ▼
                    ┌──────────────────┐
                    │   unchecked      │ (orange)
                    └────────┬─────────┘
                             │ User focuses pane
                             ▼
                    ┌──────────────────┐
                    │    checked       │ (gray)
                    └────────┬─────────┘
                             │ User responds (UserPromptSubmit)
                             ▼
                    ┌──────────────────┐
                    │    working       │ (blue)
                    └────────┬─────────┘
                             │ Stop hook
                             ▼
                    ┌──────────────────┐
                    │      done        │ (no color)
                    └──────────────────┘

Error can occur at any point and persists until cleared.
```

## Hook Triggers

### Working State (Blue)

| Hook | Trigger | File |
|------|---------|------|
| `PreToolUse` | Before any tool call | `~/.claude/hooks/pre-tool-use-overflow.sh` |
| `UserPromptSubmit` | When user sends a message | `~/.claude/hooks/user-prompt-working.sh` |

### Done State (Clear)

| Hook | Trigger | File |
|------|---------|------|
| `Stop` | When Claude's turn ends (normal) | `~/.claude/hooks/stop-notify.sh` |
| `SessionEnd` | When session ends | `~/.claude/hooks/session-end-notify.sh` |
| `PostToolUseFailure` | When tool fails/interrupted | `~/.claude/hooks/post-tool-failure-notify.sh` |

**Note:** `Stop` does not fire on user interrupt. `PostToolUseFailure` may help catch interrupted tools.

### Unchecked State (Orange)

| Hook | Matcher | Trigger | File |
|------|---------|---------|------|
| `Notification` | `permission_prompt` | Claude needs permission | `~/.claude/hooks/notification-attention.sh` |
| `Notification` | `idle_prompt` | 60+ seconds idle | `~/.claude/hooks/notification-attention.sh` |
| `Notification` | `elicitation_dialog` | MCP tool needs input | `~/.claude/hooks/notification-attention.sh` |

### Checked State (Gray)

| Trigger | Mechanism |
|---------|-----------|
| User focuses pane with `unchecked` | tmux `pane-focus-in` hook |

### Error State (Red)

| Hook | Trigger | File |
|------|---------|------|
| `PreToolUse` (deny) | Context overflow blocks tool | `~/.claude/hooks/pre-tool-use-overflow.sh` |

## Window Aggregation

The window tab shows the highest-priority state from all child panes:

```
error > unchecked > working > checked > done
```

If any pane has `error`, the window shows red.
If no errors but any pane has `unchecked`, the window shows orange.
If no errors/unchecked but any pane has `working`, the window shows blue.
If no errors/unchecked/working but any pane has `checked`, the window shows gray.
Otherwise, no color (done).

## File Locations

```
~/.claude/
├── hooks/
│   ├── pre-tool-use-overflow.sh   # working + error
│   ├── stop-notify.sh             # done
│   ├── notification-attention.sh  # unchecked
│   └── user-prompt-working.sh     # working
├── scripts/
│   └── fleet.sh                   # notify command
├── skills/fleet/assets/
│   └── tmux.conf                  # background color display + focus hook
└── settings.json                  # hook registration
```

## Manual Control

Set notification state manually:

```bash
~/.claude/scripts/fleet.sh notify <state>
```

States: `error`, `unchecked`, `working`, `checked`, `done`

Clear notification:

```bash
~/.claude/scripts/fleet.sh notify done
```

Transition unchecked to checked (simulates focus):

```bash
~/.claude/scripts/fleet.sh notify-check <pane_id>
```

## Configuration

Hooks are registered in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [...],
    "Stop": [...],
    "Notification": [...],
    "UserPromptSubmit": [...]
  }
}
```

Run `engine.sh` to configure hooks automatically.

## Typical Flow

```
User types message
    ↓
UserPromptSubmit → working (blue)
    ↓
Claude uses tools
    ↓
PreToolUse → working (blue, maintained)
    ↓
Claude finishes turn
    ↓
Stop → done (no color)
    ↓
[If Claude needs permission]
    ↓
Notification(permission_prompt) → unchecked (orange)
    ↓
[User focuses pane]
    ↓
pane-focus-in → checked (gray)
    ↓
[User responds]
    ↓
UserPromptSubmit → working (blue)
    ↓
...
```

## Color Reference (Catppuccin Mocha)

| State | Background | Hex |
|-------|------------|-----|
| error | Red (Maroon) | `#f38ba8` |
| unchecked | Peach | `#fab387` |
| working | Blue | `#89b4fa` |
| checked | Surface1 | `#45475a` |
| done | Base | `#1e1e2e` |

## Troubleshooting

**Colors not showing:**
- Reload tmux config: `Ctrl+b r` (in fleet session)
- Check you're in fleet socket: `echo $TMUX` should contain "fleet"

**Wrong pane shows color:**
- Hooks use `$FLEET_PANE_ID` (set by run.sh) or `$TMUX_PANE` to target the originating pane
- If neither is set, falls back to focused pane

**Hooks not firing:**
- Check `~/.claude/settings.json` has hooks configured
- Run `engine.sh --report` to verify hook status

**Focus hook not working:**
- The `pane-focus-in` hook requires tmux 3.0+
- Check with: `tmux -V`
