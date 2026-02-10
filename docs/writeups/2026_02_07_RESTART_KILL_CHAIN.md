# Writeup: Context Overflow Restart — Kill Chain Failures

*Created: 2026-02-07*

## Problem

Context overflow restarts leave **zombie Claude processes** and break the **statusline**. Three distinct bugs compound into a completely broken restart experience:

1. **Zombie Claude**: The old Claude process survives the restart — `session.sh restart` fails to kill it. The old process holds a PID lock in `.state.json`, blocking reactivation by the new Claude.
2. **Statusline "No session"**: After restart, the statusline can't find the session because it looks up by `FLEET_PANE_ID` from the env, which diverges from the pane ID in `.state.json`.
3. **Restart theft**: A different `run.sh` instance (in a different fleet pane) steals the restart prompt because `find_restart_agent_json()` scans globally with no pane scoping.

**Observed failure**: Claude overflows → dehydrate writes state → `session.sh restart` writes `ready-to-kill` → old Claude doesn't die → a different run.sh grabs the restart → new Claude spawns in the wrong pane → can't activate (PID lock) → statusline shows "No session" → operator is blind.

## Context

The restart flow involves four components working in sequence:

```
session.sh restart  →  writes ready-to-kill to .state.json
                    →  attempts to kill Claude via SIGTERM
run.sh              →  detects Claude exit, finds restart prompt
                    →  spawns new Claude with /reanchor prompt
statusline.sh       →  finds session by FLEET_PANE_ID env var
                    →  updates .state.json with contextUsage + sessionId
```

**The fundamental architectural tension**: `run.sh` runs Claude in the **foreground** (required for TUI rendering). This means run.sh is **blocked** — it can't poll, can't kill, can't do anything until Claude exits. The current design has Claude kill itself via `session.sh restart`, which is fragile.

## Related

*Sessions and documents that informed this writeup:*

- `sessions/2026_02_07_FLEET_SESSION_PID_ANALYSIS/BRAINSTORM_LOG.md` — Initial brainstorm on PID management
- `sessions/2026_02_07_RESTART_KILL_STATUSLINE_BUGS/ANALYSIS_LOG.md` — Root cause analysis
- `~/.claude/docs/SESSION_LIFECYCLE.md` — Lifecycle reference (has inaccuracies, see § Doc Updates below)

## Root Causes

### Bug 1: Self-Kill Is Unreliable

**File**: `~/.claude/scripts/session.sh` lines 266-282

The kill mechanism has two fragilities:

**Gate on `CLAUDE_WRAPPER_PID`** (line 266): The kill is wrapped in `if [ -n "${CLAUDE_WRAPPER_PID:-}" ]`. This env var is set by `run.sh` (`export CLAUDE_WRAPPER_PID=$$`) and must propagate through: run.sh → Claude → Bash tool → shell → session.sh. If any link breaks, the kill is silently skipped and a WARNING is printed instead.

**Self-referential kill** (lines 269-274): session.sh walks the process tree to find Claude's PID (`$PPID` → bash → Claude) and sends SIGTERM. But this runs *inside* Claude's own Bash tool. Claude may defer SIGTERM during tool execution, catch and ignore it, or the process tree walk may find the wrong PID if there are intermediate processes (sandboxes, wrappers).

```
session.sh (child of)
  → bash shell (child of)
    → Claude ← SIGTERM sent here, from its own grandchild
```

Even when the kill fires, Claude 57128 survived — confirmed still running with `S+` (sleeping, foreground) state, parent run.sh 57045 still blocked waiting.

### Bug 2: Fleet Pane ID Three-Way Mismatch

**Files**: `run.sh` line 90, `session.sh` line 88, `statusline.sh` line 65

Three components independently capture the fleet pane ID at different times:

| Source | When captured | Value observed |
|--------|-------------|----------------|
| `run.sh` env (`FLEET_PANE_ID`) | At run.sh startup | `yarik-fleet:company:SDK` |
| `session.sh activate` (`.state.json`) | At session activation | `yarik-fleet:meta:Sessions` |
| `fleet.sh pane-id` (live) | Right now | `yarik-fleet:company:Future` |

The statusline uses the env var (source 1) to look up sessions, but `.state.json` has source 2. They don't match → "No session."

This happens because after a restart, the new run.sh may be in a different pane than the one that activated the session. Or tmux pane labels changed between captures.

### Bug 3: Global Restart Scan

**File**: `~/.claude/scripts/run.sh` lines 236-248

`find_restart_agent_json()` scans ALL `sessions/*/.state.json` for `status=ready-to-kill`. No PID filter, no pane filter. First match wins.

When the intended run.sh is still blocked (waiting for its zombie Claude), a *different* run.sh whose Claude exited normally picks up the restart. This run.sh is in the wrong pane, inherits the wrong env, and spawns a Claude that can't activate.

## Proposed Fix: fswatch Restart Watchdog

Replace the self-kill architecture with an event-driven external watchdog.

### Design

`session.sh restart` becomes **state-only** — it writes `ready-to-kill` to `.state.json` and exits. No kill attempt.

`run.sh` spawns a **watchdog co-process** before Claude starts. The watchdog uses `fswatch` (FSEvents on macOS — already a project dependency via `await-tag.sh`) to monitor `.state.json` changes. When it detects `ready-to-kill` on the current pane's session, it kills Claude from the outside. Claude exits → run.sh unblocks → restart loop continues.

```
┌─────────────────────────────────────────┐
│ run.sh                                   │
│                                          │
│   ┌──────────────┐   ┌───────────────┐  │
│   │  Claude (fg)  │   │  Watchdog (bg)│  │
│   │  TUI active   │   │  fswatch on   │  │
│   │               │   │  sessions/    │  │
│   └──────┬───────┘   └──────┬────────┘  │
│          │                   │           │
│          │  Bash tool calls  │           │
│          │  session.sh       │           │
│          │  restart          │           │
│          │       │           │           │
│          │       ▼           │           │
│          │  .state.json ◄────┤ fswatch   │
│          │  ready-to-kill    │ fires     │
│          │                   │           │
│          │  ◄────────────────┤           │
│          │  kill -TERM       │           │
│          │                   │           │
│          ▼                   │           │
│     Claude exits             │           │
│     run.sh unblocks ─────────┤ cleanup   │
│     finds restart prompt                 │
│     loops                                │
└─────────────────────────────────────────┘
```

### Implementation: run.sh Watchdog

```bash
# Spawns a background watchdog that monitors .state.json for ready-to-kill.
# When detected (scoped to our fleet pane), kills Claude from outside.
# Uses fswatch (FSEvents) — event-driven, no polling.
start_restart_watchdog() {
  local sessions_dir="$PWD/sessions"
  [ -d "$sessions_dir" ] || return 0

  (
    # Wait for Claude to start, discover its PID
    local claude_pid=""
    for i in $(seq 1 20); do
      claude_pid=$(pgrep -P $$ | head -1)
      [ -n "$claude_pid" ] && break
      sleep 0.25
    done
    [ -z "$claude_pid" ] && exit 0

    # Watch for .state.json modifications — event-driven
    fswatch --event Updated -r "$sessions_dir" 2>/dev/null \
      | grep --line-buffered '\.agent\.json$' \
      | while read -r changed_file; do
          [ -f "$changed_file" ] || continue

          status=$(jq -r '.status // ""' "$changed_file" 2>/dev/null)
          [ "$status" != "ready-to-kill" ] && continue

          # Scope: only react to OUR pane's session
          if [ -n "${FLEET_PANE_ID:-}" ]; then
            pane=$(jq -r '.fleetPaneId // ""' "$changed_file" 2>/dev/null)
            [ "$pane" != "$FLEET_PANE_ID" ] && continue
          fi

          # Kill Claude — TERM first, KILL as fallback
          kill -TERM "$claude_pid" 2>/dev/null
          sleep 1
          kill -0 "$claude_pid" 2>/dev/null && kill -KILL "$claude_pid" 2>/dev/null
          break
        done
  ) &
  echo $!
}
```

### Implementation: run.sh Loop Changes

```bash
while true; do
  # Start watchdog BEFORE Claude
  WATCHDOG=$(start_restart_watchdog)

  if [ -n "$RESTART_PROMPT" ]; then
    # ... existing restart logic (spawn Claude with prompt) ...
  else
    run_claude
  fi

  # Claude exited — cleanup watchdog
  [ -n "$WATCHDOG" ] && kill "$WATCHDOG" 2>/dev/null || true

  # ... existing restart detection (scoped by FLEET_PANE_ID) ...
done
```

### Implementation: session.sh restart Simplification

```bash
restart)
    # Read current state
    SKILL=$(jq -r '.skill' "$AGENT_FILE")
    CURRENT_PHASE=$(jq -r '.currentPhase // "Phase 1: Setup"' "$AGENT_FILE")
    PROMPT="/reanchor --session $DIR --skill $SKILL --phase \"$CURRENT_PHASE\" --continue"

    # Write restart state — watchdog handles the kill
    jq --arg ts "$(timestamp)" --arg prompt "$PROMPT" \
      '.status = "ready-to-kill" | .lastHeartbeat = $ts | .restartPrompt = $prompt | .contextUsage = 0 | del(.sessionId)' \
      "$AGENT_FILE" > "$AGENT_FILE.tmp" && mv "$AGENT_FILE.tmp" "$AGENT_FILE"

    echo "Restart prepared. Watchdog will terminate Claude."
    exit 0
    ;;
```

The `CLAUDE_WRAPPER_PID` env var, the process tree walk, and the self-kill block (old lines 266-281) are all deleted.

### Implementation: Scoped find_restart_agent_json

```bash
find_restart_agent_json() {
  local sessions_dir="$PWD/sessions"
  [ -d "$sessions_dir" ] || return 1

  find -L "$sessions_dir" -name ".state.json" -type f 2>/dev/null | while read -r f; do
    local status=$(jq -r '.status // ""' "$f" 2>/dev/null)
    local prompt=$(jq -r '.restartPrompt // ""' "$f" 2>/dev/null)
    if [ "$status" = "ready-to-kill" ] && [ -n "$prompt" ]; then
      # Scope to our pane in fleet mode
      if [ -n "${FLEET_PANE_ID:-}" ]; then
        local pane=$(jq -r '.fleetPaneId // ""' "$f" 2>/dev/null)
        [ "$pane" != "$FLEET_PANE_ID" ] && continue
      fi
      echo "$f"
      return 0
    fi
  done
}
```

### Implementation: Statusline PID-First Lookup

Fix `statusline.sh` to try PID match first (always correct — PPID is the current Claude), fleet pane as fallback:

```bash
find_session_dir() {
  # ...

  # Strategy 1: PID match (works in ALL modes — PPID is always current Claude)
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    local file_pid
    file_pid=$(jq -r '.pid // 0' "$f" 2>/dev/null)
    if [ "$file_pid" = "$claude_pid" ]; then
      agent_file="$f"
      break
    fi
  done < <(find -L "$sessions_dir" -name ".state.json" -type f 2>/dev/null)

  # Strategy 2: Fleet pane fallback (for first tick before session.sh activate writes PID)
  if [ -z "$agent_file" ] && [ -n "$fleet_pane_id" ]; then
    # ... existing fleet lookup ...
  fi
}
```

## Deletions

| Item | Reason |
|------|--------|
| `CLAUDE_WRAPPER_PID` env var (run.sh line 233) | No longer needed — watchdog replaces the gate |
| Self-kill block (session.sh lines 266-281) | Watchdog kills from outside |
| Process tree walk (`ps -o ppid=`) | No longer needed |
| `CLAUDE_WRAPPER_PID` check in session.sh | Entire if/else block removed |

## SESSION_LIFECYCLE.md Updates Required

### Inaccuracies to Fix

1. **S4 (line 217-218)**: "Kills Claude process (SIGTERM)" → Should describe the watchdog: "Writes `ready-to-kill` to `.state.json`. The restart watchdog (fswatch) detects the change and sends SIGTERM to Claude from outside."

2. **S4 (line 222-223)**: "run.sh detects Claude exit" → Add: "run.sh's restart scan is scoped by `FLEET_PANE_ID` to prevent cross-pane restart theft."

3. **Section 6, session.sh restart** (line 427): Remove "Kill Claude" from responsibilities. Add: "State-only — writes `ready-to-kill` + `restartPrompt`. Does not kill."

4. **Section 6, statusline.sh** (line 440): "fleetPaneId-first (fleet mode) or PID (non-fleet)" → "PID-first (all modes), fleet pane fallback for first tick."

### Missing Race Conditions to Add

**R6: Fleet Pane ID Divergence**
- Three independent captures (`run.sh` env, `session.sh activate`, `fleet.sh pane-id` live) can return different values if pane labels change or process migrates.
- **Mitigation**: Statusline uses PID-first lookup. Pane ID from env is a fallback only.

**R7: Watchdog vs Normal Exit Race**
- Claude exits normally (user quits) at the same instant watchdog tries to kill.
- **Mitigation**: `kill -TERM` with `|| true`. `kill -0` check before SIGKILL escalation.

### New Component to Document

**Restart Watchdog** (run.sh co-process):
- Spawned before each Claude invocation
- Uses `fswatch` (FSEvents) on `sessions/` directory
- Detects `ready-to-kill` status in `.state.json`, scoped by `FLEET_PANE_ID`
- Kills Claude via SIGTERM (escalates to SIGKILL after 1s)
- Cleaned up when Claude exits (any reason)

## Risk Assessment

**Reversibility**: Easy. If the watchdog causes issues, revert to the self-kill by re-adding the old `session.sh restart` kill block. The watchdog is additive — removing it restores the old behavior.

**Edge cases**:
- `fswatch` not installed → watchdog silently exits (`2>/dev/null`), falls back to old behavior (session.sh self-kill should be kept as a degraded fallback)
- `sessions/` doesn't exist at startup → watchdog exits early, starts on next loop iteration
- Multiple `.state.json` changes in rapid succession → `grep --line-buffered` ensures each event is processed sequentially
- Non-fleet mode → pane scope check is skipped, watchdog reacts to any `ready-to-kill`

## Decision

**Status**: Ready for implementation.

**Scope**: 4 files changed:
1. `~/.claude/scripts/run.sh` — add watchdog, scope restart scan
2. `~/.claude/scripts/session.sh` — simplify restart to state-only
3. `~/.claude/tools/statusline.sh` — PID-first lookup
4. `~/.claude/docs/SESSION_LIFECYCLE.md` — fix inaccuracies, add R6/R7, document watchdog
