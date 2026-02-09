#!/bin/bash
# fleet.sh — Fleet management commands
# Usage: fleet.sh <command> [args]
#
# Commands:
#   start [workgroup]    Start fleet (or specific workgroup)
#   stop [workgroup]     Stop fleet (or specific workgroup)
#   status               Show running fleet sessions and workers
#   list                 List configured fleets
#   attach [session]     Attach to fleet session
#
# Fleet configs stored in Google Drive: {gdrive}/{username}/assets/fleet/
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Fleet architecture, commands, config format
#     SESSION_LIFECYCLE.md — Fleet session discovery and binding
#     DAEMON.md — Worker coordination
#   Invariants: (~/.claude/directives/INVARIANTS.md)
#     ¶INV_TMUX_AND_FLEET_OPTIONAL — Core requirement for fleet
#     ¶INV_CLAIM_BEFORE_WORK — Worker coordination pattern

set -euo pipefail

TMUX_CONF="$HOME/.claude/skills/fleet/assets/tmux.conf"

# Socket naming: "fleet" (default) or "fleet-{workgroup}" (per-workgroup isolation)
get_fleet_socket() {
    local workgroup="${1:-}"
    if [[ -n "$workgroup" ]]; then
        echo "fleet-${workgroup}"
    else
        echo "fleet"
    fi
}

# Auto-detect current fleet socket from $TMUX env var (when inside a fleet pane)
# Falls back to "fleet" if not in tmux or not in a fleet socket
get_current_socket() {
    if [[ -n "${TMUX:-}" ]]; then
        local socket_name
        socket_name=$(echo "$TMUX" | cut -d, -f1 | xargs basename 2>/dev/null || echo "")
        if [[ "$socket_name" == fleet || "$socket_name" == fleet-* ]]; then
            echo "$socket_name"
            return
        fi
    fi
    echo "fleet"
}

# Check if a socket name is a fleet socket (fleet or fleet-*)
is_fleet_socket() {
    local name="$1"
    [[ "$name" == "fleet" || "$name" == fleet-* ]]
}

# Derive workgroup from socket name (fleet-project → project, fleet → "")
socket_to_workgroup() {
    local socket="$1"
    if [[ "$socket" == fleet-* ]]; then
        echo "${socket#fleet-}"
    else
        echo ""
    fi
}

# tmux command for a specific socket (used by commands that know their target)
fleet_tmux() {
    local socket="${1:?fleet_tmux requires socket name}"
    shift
    tmux -L "$socket" "$@"
}

# Default TMUX_CMD for backward compat within commands that auto-detect context
# Commands that need a specific socket should use fleet_tmux() instead
CURRENT_SOCKET=$(get_current_socket)
TMUX_CMD="tmux -L $CURRENT_SOCKET"

# Derive fleet base from user-info.sh data-root
# Fleet configs live at: {data-root}/{user}/assets/fleet
# data-root resolves correctly in both local and remote engine modes
get_fleet_base() {
    local data_root user_id
    data_root=$("$HOME/.claude/scripts/user-info.sh" data-root 2>/dev/null || echo "")
    user_id=$("$HOME/.claude/scripts/user-info.sh" username 2>/dev/null || echo "unknown")
    if [[ -z "$data_root" || "$user_id" == "unknown" ]]; then
        echo ""
        return
    fi
    echo "$data_root/$user_id/assets/fleet"
}

# Get current user from user-info.sh
get_user_id() {
    "$HOME/.claude/scripts/user-info.sh" username 2>/dev/null || echo "unknown"
}

USER_ID=$(get_user_id)
FLEET_BASE=$(get_fleet_base)

get_config_path() {
    local workgroup="${1:-}"
    if [[ -n "$workgroup" ]]; then
        echo "$FLEET_BASE/${USER_ID}-${workgroup}.yml"
    else
        echo "$FLEET_BASE/${USER_ID}-fleet.yml"
    fi
}

# Helper: Update window notify state by aggregating pane states
# Priority: error > unchecked > working > checked > done
update_window_notify() {
    # Get all pane notify states in current window
    local states
    states=$($TMUX_CMD list-panes -F '#{@pane_notify}' 2>/dev/null || echo "")

    # Determine highest priority state
    if echo "$states" | grep -q "error"; then
        $TMUX_CMD set-option -w @window_notify "error" 2>/dev/null || true
    elif echo "$states" | grep -q "unchecked"; then
        $TMUX_CMD set-option -w @window_notify "unchecked" 2>/dev/null || true
    elif echo "$states" | grep -q "working"; then
        $TMUX_CMD set-option -w @window_notify "working" 2>/dev/null || true
    elif echo "$states" | grep -q "checked"; then
        $TMUX_CMD set-option -w @window_notify "checked" 2>/dev/null || true
    else
        $TMUX_CMD set-option -w @window_notify "done" 2>/dev/null || true
    fi

    # Force immediate status bar redraw so window tab colors update instantly
    # (setting @window_notify alone doesn't trigger a redraw — tmux waits for status-interval)
    $TMUX_CMD refresh-client -S 2>/dev/null || true
}


cmd_start() {
    local workgroup="${1:-}"
    local session_name
    local config_file
    local socket

    # Setup is handled by engine CLI (auto-setup on first run).
    # fleet.sh no longer invokes engine.sh directly — callers should use `engine` entrypoint.

    socket=$(get_fleet_socket "$workgroup")
    if [[ -n "$workgroup" ]]; then
        session_name="${USER_ID}-${workgroup}"
    else
        session_name="${USER_ID}-fleet"
    fi
    config_file=$(get_config_path "$workgroup")

    if [[ ! -f "$config_file" ]]; then
        echo "Error: Config not found: $config_file"
        echo "Run /fleet to generate your fleet configuration first."
        exit 1
    fi

    # Check if already running on this socket
    if fleet_tmux "$socket" has-session -t "$session_name" 2>/dev/null; then
        echo "Fleet '$session_name' is already running (socket: $socket). Attaching..."
        fleet_tmux "$socket" attach -t "$session_name"
    else
        echo "Starting fleet '$session_name' (socket: $socket)..."
        # Kill stale server on THIS socket only (preserves other fleet sockets)
        fleet_tmux "$socket" kill-server 2>/dev/null || true
        # Use -p to specify config path directly (no ~/.tmuxinator needed)
        tmuxinator start -p "$config_file"
    fi
}

cmd_stop() {
    local workgroup="${1:-}"
    local session_name
    local socket

    socket=$(get_fleet_socket "$workgroup")
    if [[ -n "$workgroup" ]]; then
        session_name="${USER_ID}-${workgroup}"
    else
        session_name="${USER_ID}-fleet"
    fi

    if fleet_tmux "$socket" has-session -t "$session_name" 2>/dev/null; then
        echo "Stopping fleet '$session_name' (socket: $socket)..."
        fleet_tmux "$socket" kill-session -t "$session_name"
        echo "Stopped."
    else
        echo "Fleet '$session_name' is not running (socket: $socket)."
    fi
}

cmd_status() {
    echo "=== Fleet Status ==="
    echo ""
    echo "User: $USER_ID"
    echo "Fleet dir: $FLEET_BASE"
    echo ""

    # Show all configs with running/stopped status
    echo "Fleet configs:"
    if [[ -d "$FLEET_BASE" ]]; then
        for config in "$FLEET_BASE"/${USER_ID}-*.yml; do
            [[ -f "$config" ]] || continue
            local name socket session_name status_label
            name=$(basename "$config" .yml)
            # Derive workgroup: {user}-fleet → "", {user}-project → "project"
            local suffix="${name#${USER_ID}-}"
            if [[ "$suffix" == "fleet" ]]; then
                socket="fleet"
                session_name="${USER_ID}-fleet"
            else
                socket="fleet-${suffix}"
                session_name="${name}"
            fi
            if fleet_tmux "$socket" has-session -t "$session_name" 2>/dev/null; then
                status_label="RUNNING"
            else
                status_label="stopped"
            fi
            echo "  $name ($status_label) [socket: $socket]"
        done
    else
        echo "  (fleet directory not created yet)"
    fi
    echo ""

    # Show running tmux sessions across all fleet sockets
    echo "Running sessions:"
    local found_sessions=false
    # Check default fleet socket
    if fleet_tmux "fleet" ls 2>/dev/null | grep -qE "^${USER_ID}"; then
        fleet_tmux "fleet" ls 2>/dev/null | grep -E "^${USER_ID}" | sed 's/^/  [fleet] /'
        found_sessions=true
    fi
    # Check workgroup sockets
    if [[ -d "$FLEET_BASE" ]]; then
        for config in "$FLEET_BASE"/${USER_ID}-*.yml; do
            [[ -f "$config" ]] || continue
            local cname csuffix csocket
            cname=$(basename "$config" .yml)
            csuffix="${cname#${USER_ID}-}"
            [[ "$csuffix" == "fleet" ]] && continue  # Already checked above
            csocket="fleet-${csuffix}"
            if fleet_tmux "$csocket" ls 2>/dev/null | grep -qE "^${USER_ID}"; then
                fleet_tmux "$csocket" ls 2>/dev/null | grep -E "^${USER_ID}" | sed "s/^/  [$csocket] /"
                found_sessions=true
            fi
        done
    fi
    if [[ "$found_sessions" == "false" ]]; then
        echo "  (none)"
    fi
    echo ""

    # Show registered workers
    local workers_dir="$HOME/.claude/fleet/workers"
    if [[ -d "$workers_dir" ]] && ls "$workers_dir"/*.md 2>/dev/null | head -1 > /dev/null; then
        echo "Registered workers:"
        for worker in "$workers_dir"/*.md; do
            local wname wstatus
            wname=$(basename "$worker" .md)
            wstatus=$(grep -o '#idle\|#working\|#has-work' "$worker" 2>/dev/null | head -1 || echo "unknown")
            echo "  $wname ($wstatus)"
        done
    fi
}

cmd_list() {
    echo "=== Available Fleet Configs ==="
    echo "Location: $FLEET_BASE"
    echo ""

    if [[ ! -d "$FLEET_BASE" ]]; then
        echo "  (fleet directory not created yet)"
        return
    fi

    # List yml files in fleet dir with running status
    local found=false
    for config in "$FLEET_BASE"/${USER_ID}-*.yml; do
        [[ -f "$config" ]] || continue
        found=true
        local name suffix socket session_name status_indicator
        name=$(basename "$config" .yml)
        suffix="${name#${USER_ID}-}"
        if [[ "$suffix" == "fleet" ]]; then
            socket="fleet"
            session_name="${USER_ID}-fleet"
        else
            socket="fleet-${suffix}"
            session_name="${name}"
        fi
        if fleet_tmux "$socket" has-session -t "$session_name" 2>/dev/null; then
            status_indicator="●"
        else
            status_indicator="○"
        fi
        echo "  $status_indicator $name  [socket: $socket]"
    done
    if [[ "$found" == "false" ]]; then
        echo "  (none)"
    fi
}

cmd_attach() {
    local session="${1:-${USER_ID}-fleet}"

    # Determine which socket this session lives on
    # Try to match session name to a known fleet socket
    local socket="fleet"  # default
    if [[ "$session" == *-* ]] && [[ "$session" != *-fleet ]]; then
        # e.g., yarik-project → try fleet-project socket
        local suffix="${session#${USER_ID}-}"
        if [[ -n "$suffix" && "$suffix" != "fleet" ]]; then
            local candidate_socket="fleet-${suffix}"
            if fleet_tmux "$candidate_socket" has-session -t "$session" 2>/dev/null; then
                socket="$candidate_socket"
            fi
        fi
    fi

    if fleet_tmux "$socket" has-session -t "$session" 2>/dev/null; then
        fleet_tmux "$socket" attach -t "$session"
    else
        echo "Session '$session' not found."
        echo ""
        echo "Running sessions across all fleet sockets:"
        # Check all known sockets
        fleet_tmux "fleet" ls 2>/dev/null | sed 's/^/  [fleet] /' || true
        if [[ -d "$FLEET_BASE" ]]; then
            for config in "$FLEET_BASE"/${USER_ID}-*.yml; do
                [[ -f "$config" ]] || continue
                local cname csuffix csocket
                cname=$(basename "$config" .yml)
                csuffix="${cname#${USER_ID}-}"
                [[ "$csuffix" == "fleet" ]] && continue
                csocket="fleet-${csuffix}"
                fleet_tmux "$csocket" ls 2>/dev/null | sed "s/^/  [$csocket] /" || true
            done
        fi
    fi
}

cmd_init() {
    # Create fleet directory structure
    if [[ -z "$GDRIVE_BASE" ]]; then
        echo "Error: Could not detect Google Drive path."
        exit 1
    fi

    echo "Creating fleet directory: $FLEET_BASE"
    mkdir -p "$FLEET_BASE"
    echo "Done. Run /fleet to configure your fleet."
}

cmd_wait() {
    # Simple dim message
    local dim="\033[2m"
    local reset="\033[0m"

    clear
    echo ""
    echo ""
    printf "${dim}      ⏸  Reserved Slot${reset}\n"
    echo ""
    printf "${dim}      Press 'a' to activate${reset}\n"

    while true; do
        read -rsn1 key
        case "$key" in
            a|A)
                cmd_activate
                break
                ;;
        esac
    done
}

cmd_activate() {
    local name="${1:-}"

    # Gather pane context
    local pane_id="$TMUX_PANE"
    local current_label=$($TMUX_CMD display-message -p '#{@pane_label}' 2>/dev/null || echo "Future")
    local window_name=$($TMUX_CMD display-message -p '#W' 2>/dev/null || echo "unknown")
    local window_index=$($TMUX_CMD display-message -p '#I' 2>/dev/null || echo "?")
    local pane_index=$($TMUX_CMD display-message -p '#P' 2>/dev/null || echo "?")
    local pane_title_var="${TMUX_PANE_TITLE:-unknown}"

    # Get config path
    local config_path
    config_path=$(get_config_path)

    # If name provided directly, just set and launch
    if [[ -n "$name" ]]; then
        $TMUX_CMD set-option -p @pane_label "$name"
        clear
        exec ~/.claude/scripts/run.sh --agent operator "/fleet activate

Pane activated with name: $name
Tab: $window_name (window $window_index)
Pane ID: $pane_title_var
Fleet config: $config_path

Please update the fleet config at $config_path to make this permanent (find pane block by TMUX_PANE_TITLE=\"$pane_title_var\")."
    fi

    # Get config path for the prompt
    local config_path
    config_path=$(get_config_path)

    # Otherwise, launch claude with fleet skill to do interrogation
    clear
    exec ~/.claude/scripts/run.sh --agent operator "/fleet activate

This is a reserved pane that needs configuration.

Current context:
- Tab: $window_name (window $window_index, pane $pane_index)
- Pane ID: $pane_title_var
- Current label: $current_label
- Fleet config: $config_path

Please help configure this agent:
1. Ask what kind of work this pane should handle
2. Suggest a name and agent type
3. Update the pane label: tmux -L fleet set-option -p @pane_label 'NewName'
4. Update the fleet yml at: $config_path (find the pane block by TMUX_PANE_TITLE=\"$pane_title_var\")"
}

cmd_notify() {
    local state="${1:-}"

    if [[ -z "$state" ]]; then
        echo "Usage: fleet.sh notify <error|unchecked|working|checked|done>"
        exit 1
    fi

    # Validate state
    case "$state" in
        error|unchecked|working|checked|done) ;;
        *)
            echo "Invalid state: $state (must be error|unchecked|working|checked|done)"
            exit 1
            ;;
    esac

    # Target the pane where this command originated
    local target_pane="${TMUX_PANE:-}"
    if [[ -n "$target_pane" ]]; then
        # State-check debounce: skip visual update if state hasn't changed
        # (INV_SKIP_REDUNDANT_STYLE_APPLY — redundant select-pane -P calls cause flash)
        local prev_state
        prev_state=$($TMUX_CMD display -p -t "$target_pane" '#{@pane_notify}' 2>/dev/null || echo "")

        # Skip pane update if state unchanged, but still refresh window aggregate
        # (other panes may have changed externally — window needs recomputation)
        if [[ "$prev_state" == "$state" ]]; then
            update_window_notify
            return
        fi

        # State priority for debounce: higher = more urgent
        # error(4) > unchecked(3) > working(2) > checked(1) > done(0)
        local prev_priority=0 new_priority=0
        case "$prev_state" in
            error) prev_priority=4 ;; unchecked) prev_priority=3 ;;
            working) prev_priority=2 ;; checked) prev_priority=1 ;; *) prev_priority=0 ;;
        esac
        case "$state" in
            error) new_priority=4 ;; unchecked) new_priority=3 ;;
            working) new_priority=2 ;; checked) new_priority=1 ;; *) new_priority=0 ;;
        esac

        # Debounce file per pane (uses pane ID with % replaced to be filename-safe)
        local debounce_dir="/tmp/fleet-debounce"
        mkdir -p "$debounce_dir" 2>/dev/null || true
        local safe_pane="${target_pane//%/_}"
        local debounce_file="$debounce_dir/$safe_pane"

        # Data layer: ALWAYS apply immediately (tests and queries depend on this)
        _apply_notify_data "$target_pane" "$state"

        if [[ "$new_priority" -ge "$prev_priority" ]]; then
            # Upgrade (or same priority): apply visual immediately, cancel pending downgrade
            echo "$state" > "$debounce_file" 2>/dev/null || true
            _apply_notify_visual "$target_pane" "$state"
        else
            # Downgrade: defer visual by 200ms to prevent flash
            # Data layer already applied above — only the select-pane -P is deferred
            echo "$state" > "$debounce_file" 2>/dev/null || true
            (
                sleep 0.2
                local current_intent
                current_intent=$(cat "$debounce_file" 2>/dev/null || echo "")
                if [[ "$current_intent" == "$state" ]]; then
                    _apply_notify_visual "$target_pane" "$state"
                fi
            ) &
            disown 2>/dev/null || true
        fi
    else
        $TMUX_CMD set-option -p @pane_notify "$state" 2>/dev/null || true
        update_window_notify
    fi
}

# Helper: Apply data layer only (@pane_notify + window aggregate)
# Always called synchronously so tests and queries see the state immediately.
_apply_notify_data() {
    local target_pane="$1" state="$2"
    $TMUX_CMD set-option -p -t "$target_pane" @pane_notify "$state" 2>/dev/null || true
    update_window_notify
}

# Helper: Apply visual layer only (select-pane -P bg color)
# This is the part that can be deferred on downgrades to prevent flash.
_apply_notify_visual() {
    local target_pane="$1" state="$2"

    local color
    case "$state" in
        error)     color="#3d2020" ;;
        unchecked) color="#081a10" ;;
        working)   color="#080c10" ;;
        checked)   color="#0a1005" ;;
        *)         color="#0a0a0a" ;;
    esac

    local active_pane
    active_pane=$($TMUX_CMD display -p '#{pane_id}' 2>/dev/null || echo "")
    if [[ "$target_pane" == "$active_pane" ]]; then
        # Focused pane — skip style to avoid flash/distraction while user is looking at it
        :
    else
        # Unfocused pane — suppress hooks + set style + restore focus in one atomic tmux call
        $TMUX_CMD set -g @suppress_focus_hook 1 \; \
            select-pane -t "$target_pane" -P "bg=$color" \; \
            select-pane -t "$active_pane" \; \
            set -g @suppress_focus_hook 0 \
            2>/dev/null || true
    fi
}

cmd_notify_clear() {
    # Clear pane notify state to done (called by focus hook or explicit clear)
    local target_pane="${TMUX_PANE:-}"
    if [[ -n "$target_pane" ]]; then
        $TMUX_CMD set-option -p -t "$target_pane" @pane_notify "done" 2>/dev/null || true
    else
        $TMUX_CMD set-option -p @pane_notify "done" 2>/dev/null || true
    fi

    # Update window aggregate
    update_window_notify
}

cmd_notify_check() {
    # Transition unchecked → checked when user focuses pane (called by tmux focus hook)
    local target_pane="${1:-}"
    if [[ -z "$target_pane" ]]; then
        echo "Usage: fleet.sh notify-check <pane_id>"
        exit 1
    fi

    # Only transition if currently unchecked
    local current_state
    current_state=$($TMUX_CMD display-message -p -t "$target_pane" '#{@pane_notify}' 2>/dev/null || echo "")
    if [[ "$current_state" == "unchecked" ]]; then
        $TMUX_CMD set-option -p -t "$target_pane" @pane_notify "checked" 2>/dev/null || true
        update_window_notify
    fi
}

cmd_pane_id() {
    # Generate composite pane ID: {session}:{window}:{pane_label}
    # Used by run.sh to identify which session belongs to which pane
    # Returns empty string if not in fleet tmux

    # Check if we're in tmux at all
    if [[ -z "${TMUX:-}" ]]; then
        return 1
    fi

    # Check if this is a fleet socket (fleet or fleet-*)
    local current_socket
    current_socket=$(echo "$TMUX" | cut -d, -f1 | xargs basename 2>/dev/null || echo "")
    if ! is_fleet_socket "$current_socket"; then
        return 1
    fi

    # Get components using $TMUX_PANE to target the pane where this script runs
    # (not the focused pane, which is what display-message -p returns without -t)
    local tmux_cmd="tmux -L $current_socket"
    local session_name window_name pane_label
    session_name=$($tmux_cmd display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null || echo "")
    window_name=$($tmux_cmd display-message -p -t "$TMUX_PANE" '#{window_name}' 2>/dev/null || echo "")
    pane_label=$($tmux_cmd display-message -p -t "$TMUX_PANE" '#{@pane_label}' 2>/dev/null || echo "")

    # All three must be present
    if [[ -z "$session_name" ]] || [[ -z "$window_name" ]] || [[ -z "$pane_label" ]]; then
        return 1
    fi

    echo "${session_name}:${window_name}:${pane_label}"
}

cmd_help() {
    cat <<EOF
fleet.sh — Fleet management commands

Usage: fleet.sh <command> [args]

Commands:
  start [workgroup]    Start fleet (or specific workgroup) on its own tmux socket
  stop [workgroup]     Stop fleet (or specific workgroup)
  status               Show all fleet configs with running/stopped status
  list                 List configured fleets with status indicators
  attach [session]     Attach to fleet session (auto-detects socket)
  wait                 Wait mode for reserved slots (press 'a' to activate)
  activate [name]      Activate a reserved slot with Claude guidance
  notify <state>       Set pane notification state (error|unchecked|working|checked|done)
  notify-check <pane>  Transition unchecked→checked (called by tmux focus hook)
  notify-clear         Clear pane notification to done
  pane-id              Output composite pane ID (session:window:label) for session binding
  config-path [group]  Output path to fleet yml config (default: main fleet)
  init                 Create fleet directory in Google Drive

Socket naming:
  Default fleet:   socket "fleet"           → session "${USER_ID}-fleet"
  Workgroup fleet: socket "fleet-{group}"   → session "${USER_ID}-{group}"

Fleet configs stored at:
  $FLEET_BASE

Examples:
  fleet.sh start                  # Start default fleet (socket: fleet)
  fleet.sh start project          # Start project fleet (socket: fleet-project)
  fleet.sh stop                   # Stop default fleet
  fleet.sh stop project           # Stop project fleet only
  fleet.sh status                 # Show all configs + running status
  fleet.sh attach ${USER_ID}-fleet      # Attach to default fleet
  fleet.sh attach ${USER_ID}-project    # Attach to project fleet
  fleet.sh activate "Auth"        # Activate slot named "Auth"
  fleet.sh activate               # Interactive activation
EOF
}

# Main dispatch
case "${1:-help}" in
    start)    cmd_start "${2:-}" ;;
    stop)     cmd_stop "${2:-}" ;;
    status)   cmd_status ;;
    list)     cmd_list ;;
    attach)   cmd_attach "${2:-}" ;;
    wait)     cmd_wait ;;
    activate) cmd_activate "${2:-}" ;;
    notify)   cmd_notify "${2:-}" ;;
    notify-check) cmd_notify_check "${2:-}" ;;
    notify-clear) cmd_notify_clear ;;
    pane-id)  cmd_pane_id ;;
    config-path) get_config_path "${2:-}" ;;
    init)     cmd_init ;;
    help|-h|--help) cmd_help ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'fleet.sh help' for usage."
        exit 1
        ;;
esac
