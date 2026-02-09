# Testing Standards — Dispatch Daemon

The dispatch daemon currently has **no automated tests**. This file documents how to test it and the conventions to follow when adding tests.

## 1. Manual Testing

```bash
# Start the daemon
cd ~/Projects/finch
~/.claude/tools/dispatch-daemon/dispatch-daemon.sh start

# Create a test tag to trigger dispatch
echo '# Test Request
**Tags**: #needs-chores
## Context
Test dispatch.' > sessions/test-dispatch-request.md

# Watch the log for pickup
tail -f /tmp/dispatch-daemon.log

# Verify tag was claimed
grep -r '#active-chores' sessions/test-dispatch-request.md

# Clean up
rm sessions/test-dispatch-request.md
~/.claude/tools/dispatch-daemon/dispatch-daemon.sh stop
```

## 2. Test Plan (When Adding Automated Tests)

The daemon is a bash script with these testable concerns:

| Category | What to Test |
|----------|-------------|
| **Tag detection** | `#needs-*` tags on `**Tags**:` line are detected; backtick-escaped tags are ignored; body-only tags are ignored |
| **Claim atomicity** | `#needs-X` swapped to `#active-X` before agent spawn; no double-processing |
| **Debounce** | Rapid-fire events on same file within 2s window produce only one spawn |
| **Routing** | Each `#needs-X` tag maps to correct `/X` skill via `§TAG_DISPATCH` |
| **Graceful degradation** | Missing `fswatch` → clear error; missing `tmux` → clear error; stale PID file → handled |
| **Lifecycle** | `start` creates PID file; `stop` removes it; `status` reads it correctly |

### Recommended Approach

Follow the `engine/scripts/tests/` bash test framework:

```bash
#!/bin/bash
# test-dispatch-daemon.sh
set -uo pipefail

DAEMON="$HOME/.claude/tools/dispatch-daemon/dispatch-daemon.sh"
TMP_DIR=$(mktemp -d)

# Create mock sessions/ with a tagged file
mkdir -p "$TMP_DIR/sessions"
cat > "$TMP_DIR/sessions/TEST_REQUEST.md" <<'EOF'
# Test
**Tags**: #needs-chores
## Context
Test.
EOF

# Test tag detection (unit-test the grep/detection logic)
# Test claim logic (verify tag.sh swap is called)
# Test debounce (fire two events, verify single spawn)
```

## 3. Dependencies

*   **fswatch**: Required for file watching. `brew install fswatch`
*   **tmux**: Required for agent spawning. `brew install tmux`
*   **tag.sh**: Tag operations (part of engine)
*   **run.sh**: Claude process wrapper (part of engine)

Tests should mock `run.sh` to avoid spawning real Claude agents.

## 4. Constraints

*   **No real agent spawns in tests**: Mock `run.sh` to echo and exit 0.
*   **No real fswatch in unit tests**: Test the detection/routing logic directly, not the file watcher.
*   **Temp directory isolation**: Never write to real `sessions/` in tests.
