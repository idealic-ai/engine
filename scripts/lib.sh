#!/bin/bash
# ~/.claude/scripts/lib.sh — Shared utilities for session infrastructure
#
# Related:
#   Docs: (~/.claude/docs/)
#     CONTEXT_GUARDIAN.md — lib.sh API section, consumer list
#     ENGINE_TESTING.md — Testing patterns for lib functions
#   Invariants: (~/.claude/.directives/INVARIANTS.md)
#     (none directly — utility layer)
#
# Source this file at the top of scripts that need these functions:
#   source "$HOME/.claude/scripts/lib.sh"
#
# Functions:
#   safe_json_write FILE    — Reads JSON from stdin, validates, writes atomically with locking
#   hook_allow              — Outputs PreToolUse allow JSON and exits 0
#   hook_deny REASON GUIDANCE DEBUG_INFO — Outputs PreToolUse deny JSON and exits 0
#   timestamp               — Outputs UTC ISO timestamp
#   pid_exists PID          — Returns 0 if PID is running, 1 otherwise
#   notify_fleet STATE      — Send fleet notification if in fleet tmux (no-ops safely outside fleet)
#   state_read FILE FIELD [DEFAULT] — Read a field from .state.json with fallback
#   is_engine_cmd CMD SUBCMD — Returns 0 if CMD is "engine SUBCMD ..." (anchored regex)
#   is_engine_log_cmd CMD   — Returns 0 if CMD is an engine log invocation
#   is_engine_session_cmd CMD — Returns 0 if CMD is an engine session invocation
#   is_engine_tag_cmd CMD   — Returns 0 if CMD is an engine tag invocation
#   is_engine_glob_cmd CMD  — Returns 0 if CMD is an engine glob invocation
#   fleet_self              — This seat's window:label, live tmux first (exit 3 = launch-time cache)
#   fleet_parent [--live V] [--of SEAT] — This seat's parent, live @pane_parent first (exit 3 = cache)

# Guard against double-sourcing
[ -n "${_LIB_SH_LOADED:-}" ] && return 0
_LIB_SH_LOADED=1

# rotation_log EVENT DETAIL — Append to account rotation log
# Format: [YYYY-MM-DD HH:MM:SS] EVENT: detail
# Log file: ~/.claude/accounts/rotation.log
rotation_log() {
  local event="${1:?rotation_log requires EVENT}" detail="${2:-}"
  local log_dir="$HOME/.claude/accounts"
  local log_file="$log_dir/rotation.log"
  mkdir -p "$log_dir"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts] $event: $detail" >> "$log_file"
}

# notify_fleet STATE — Send fleet notification if in fleet tmux
# Safely no-ops outside fleet. STATE: working|done|error|unchecked
notify_fleet() {
  [ -n "${TMUX:-}" ] || return 0
  local socket
  local tmux_path
  tmux_path=$(echo "$TMUX" | cut -d, -f1)
  socket="${tmux_path##*/}"
  [[ "$socket" == "fleet" || "$socket" == fleet-* ]] || return 0
  "$HOME/.claude/scripts/fleet.sh" notify "$1" 2>/dev/null || true
}

# state_read FILE FIELD [DEFAULT] — Read a field from .state.json with fallback
state_read() {
  local file="${1:?state_read requires FILE}" field="${2:?state_read requires FIELD}" default="${3:-}"
  jq -r ".$field // \"$default\"" "$file" 2>/dev/null || echo "$default"
}

# timestamp — Outputs UTC ISO timestamp: 2026-02-08T16:00:00Z
timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# pid_exists PID — Returns 0 if PID is running, 1 otherwise
# Guard: PID must be a positive integer. kill -0 0 signals the entire process group.
pid_exists() {
  [ "$1" -gt 0 ] 2>/dev/null && kill -0 "$1" 2>/dev/null
}

# hook_allow — Outputs PreToolUse allow JSON and exits 0
hook_allow() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

# hook_deny REASON GUIDANCE DEBUG_INFO
#   Outputs PreToolUse deny JSON with reason and guidance.
#   DEBUG_INFO is only included when DEBUG=1.
#   All 3 args required (pass "" for empty).
hook_deny() {
  local reason="${1:?hook_deny requires REASON as arg 1}"
  local guidance="${2:?hook_deny requires GUIDANCE as arg 2}"
  local debug_info="${3?hook_deny requires DEBUG_INFO as arg 3}"

  local full_reason="$reason"
  if [ -n "$guidance" ]; then
    full_reason="${full_reason}\n${guidance}"
  fi
  if [ "${DEBUG:-}" = "1" ] && [ -n "$debug_info" ]; then
    full_reason="${full_reason}\n[DEBUG] ${debug_info}"
  fi

  jq -n --arg reason "$full_reason" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$reason}}'
  exit 0
}

# is_engine_cmd CMD SUBCMD — Returns 0 if CMD starts with "engine SUBCMD"
# Uses anchored regex: ^engine\s+SUBCMD(\s|$)
# The anchor prevents false positives from heredoc bodies.
is_engine_cmd() {
  local cmd="$1" subcmd="$2"
  local nl=$'\n'
  # Match `engine <subcmd>` at the start OR as a segment separated by &&, ;, |, or a
  # newline — so `cd path && engine log ...` and multi-line `cd path⏎engine log ...`
  # both count (heartbeat reset / hook whitelist). A newline is a command terminator,
  # so this stays as safe against quoted false positives as the other separators.
  [[ "$cmd" =~ (^|&&|;|[|]|$nl)[[:space:]]*engine[[:space:]]+"$subcmd"([[:space:]]|$) ]]
}

# Convenience wrappers for specific engine subcommands
is_engine_log_cmd()     { is_engine_cmd "$1" "log"; }
is_engine_session_cmd() { is_engine_cmd "$1" "session"; }
is_engine_tag_cmd()     { is_engine_cmd "$1" "tag"; }
is_engine_glob_cmd()    { is_engine_cmd "$1" "glob"; }

# --- Path normalization utilities ---

# normalize_preload_path PATH → canonical absolute path on stdout
#   1. Resolves ~ to $HOME
#   2. Resolves directory symlinks (e.g., ~/.claude/.directives/ → ~/.claude/engine/.directives/)
#   Outputs absolute paths for consistent dedup in preloadedFiles/pendingPreloads.
normalize_preload_path() {
  local path="$1"
  local resolved="${path/#\~/$HOME}"
  # Resolve directory symlinks (macOS compatible: cd + pwd -P)
  # Use parameter expansion instead of dirname/basename for zsh compatibility
  if [ -f "$resolved" ]; then
    local dir_part="${resolved%/*}"
    local base_part="${resolved##*/}"
    local real_dir
    real_dir=$(cd "$dir_part" 2>/dev/null && pwd -P) || real_dir="$dir_part"
    resolved="$real_dir/$base_part"
  fi
  echo "$resolved"
}

# get_session_start_seeds → JSON array of canonical seed paths on stdout
#   The one list of standards SessionStart injects in full. The hook's print loop iterates this
#   output and activation seeds from it, so a path is added or removed here and nowhere else.
#   Every entry is guarded on existence: the print loop can only inject what [ -f ] can read, and
#   a path recorded but never injected reads to PostToolUse dedup as already delivered, which
#   suppresses the later real injection.
#   PITFALLS.md, SIGILS.md and CMD_PARSE_PARAMETERS.md are on demand; PITFALLS is represented at
#   session start by generate_pitfalls_index rather than by its bytes.
SESSION_START_SEED_FILES=(COMMANDS.md INVARIANTS.md VOICE.md commands/CMD_DEHYDRATE.md commands/CMD_RESUME_SESSION.md commands/CMD_CONTINUE_ON_STOP.md)
get_session_start_seeds() {
  local engine_dir rel seeds='[]'
  engine_dir=$(cd "$HOME/.claude/.directives" 2>/dev/null && pwd -P) || engine_dir="$HOME/.claude/.directives"
  for rel in "${SESSION_START_SEED_FILES[@]}"; do
    [ -f "$engine_dir/$rel" ] || continue
    seeds=$(echo "$seeds" | jq --arg p "$engine_dir/$rel" '. + [$p]')
  done
  echo "$seeds"
}

# generate_pitfalls_index FILE... → per file, a "From <file>:" line and one line per ¶PTF_ name:
#   "- <severity marks> ¶PTF_NAME — <one-line trap>". Built from the files at call time, never
#   maintained by hand. Definition shapes: a bold bullet (**¶PTF_X**: trap, with optional marks such
#   as ⛔⛔ between the ** and the ¶; the trap may wrap onto following lines), a heading carrying the
#   name (trap after an em dash, else the entry's first paragraph), and an "Addendum to ¶PTF_X"
#   heading, which is not a definition. A real name that appears only in prose still gets a line;
#   placeholder names used to describe the format (¶PTF_NAME, ¶PTF_UPPER_SNAKE_CASE) are dropped.
PITFALLS_PLACEHOLDER_RE='^PTF_(X+|N|NAME|FOO|BAR|BAZ|EXAMPLE|SOMETHING|UPPER_SNAKE_CASE|YOUR_[A-Z0-9_]+)$'
generate_pitfalls_index() {
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    echo "From $f:"
    LC_ALL=C awk -v placeholder="$PITFALLS_PLACEHOLDER_RE" '
      function clean(t) {
        gsub(/\*\*/, "", t); gsub(/`/, "", t)
        sub(/^[[:space:]]*[*-][[:space:]]+/, "", t)
        sub(/^[[:space:]]*(The trap|Trap)[[:space:]]*:[[:space:]]*/, "", t)
        gsub(/[[:space:]]+/, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
        if (index(t, ". ") > 40) t = substr(t, 1, index(t, ". "))
        if (length(t) > 220) t = substr(t, 1, 217) "..."
        return t
      }
      function emit(name, trap, marks) {
        if (name in seen) return
        seen[name] = 1; order[++n] = name; text[name] = trap; mark[name] = marks
      }
      function flush() { if (pending != "") emit(pending, clean(para), pmarks); pending = ""; para = ""; pmarks = "" }
      pending != "" {
        if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^#/ || $0 ~ /^[[:space:]]*[*-][[:space:]]/) { if (para != "" || $0 ~ /^#/ || $0 ~ /^[[:space:]]*[*-][[:space:]]/) flush() }
        else { para = para (para == "" ? "" : " ") $0; next }
        if ($0 ~ /^[[:space:]]*$/) next
      }
      /^[[:space:]]*[*-][[:space:]]+\*\*[^*]*¶PTF_[A-Z0-9_]+[^*]*\*\*/ {
        match($0, /\*\*[^*]*¶PTF_/); marks = substr($0, RSTART + 2, RLENGTH - 8)
        sub(/^[[:space:]]+/, "", marks); sub(/[[:space:]]+$/, "", marks)
        match($0, /¶PTF_[A-Z0-9_]+/); name = substr($0, RSTART + 2, RLENGTH - 2)
        rest = substr($0, RSTART + RLENGTH); sub(/^[^*]*\*\*:?[[:space:]]*/, "", rest)
        if (name in seen) next
        pending = name; para = rest; pmarks = marks; next
      }
      /^#+[[:space:]]/ && /¶PTF_[A-Z0-9_]+/ && $0 !~ /[Aa]ddendum/ {
        match($0, /¶PTF_[A-Z0-9_]+/); name = substr($0, RSTART + 2, RLENGTH - 2)
        rest = substr($0, RSTART + RLENGTH)
        if (index(rest, " — ") > 0) { emit(name, clean(substr(rest, index(rest, " — ") + 5)), "") }
        else if (!(name in seen)) { pending = name; para = ""; pmarks = "" }
        next
      }
      {
        line = $0
        while (match(line, /¶PTF_[A-Z0-9_]+/)) {
          nm = substr(line, RSTART + 2, RLENGTH - 2)
          if (!(nm in mentioned)) { mentioned[nm] = 1; morder[++m] = nm }
          line = substr(line, RSTART + RLENGTH)
        }
      }
      END {
        flush()
        for (i = 1; i <= m; i++) if (!(morder[i] in seen) && morder[i] !~ placeholder) emit(morder[i], "(named in prose, no definition line)", "")
        for (i = 1; i <= n; i++) printf "- %s¶%s — %s\n", (mark[order[i]] != "" ? mark[order[i]] " " : ""), order[i], text[order[i]]
      }
    ' "$f"
  done
}

# heading_aligned_tail FILE MAX_BYTES → the file whole if it fits, else its last MAX_BYTES advanced
#   to the next "## " heading, behind a note naming what was cut. Append-only artifacts put
#   current state at the end, so the tail is the part worth delivering.
heading_aligned_tail() {
  local file="$1" max="$2" bytes tail_txt first
  bytes=$(wc -c < "$file" 2>/dev/null | tr -d ' ') || bytes=0
  if [ "${bytes:-0}" -le "$max" ]; then
    cat "$file" 2>/dev/null
    return 0
  fi
  tail_txt=$(tail -c "$max" "$file" 2>/dev/null || true)
  first=$(printf '%s' "$tail_txt" | grep -n '^## ' | head -n 1 | cut -d: -f1 || true)
  echo "[... earlier entries omitted; showing the most recent of $bytes bytes ...]"
  echo ""
  if [ -n "$first" ]; then
    printf '%s\n' "$tail_txt" | tail -n +"$first"
  else
    printf '%s\n' "$tail_txt"
  fi
}

# dialogue_tail FILE MAX_LINES MAX_BYTES → the newest entries of an append-only DIALOGUE.md
#   Starts at the first "## " heading inside the last MAX_LINES lines, then drops the oldest whole
#   entries until the excerpt fits MAX_BYTES. When even the newest entry is larger, its last
#   MAX_BYTES are shown, so the newest lines are always present. A pointer line precedes a cut.
dialogue_tail() {
  local file="$1" max_lines="$2" max_bytes="$3"
  LC_ALL=C awk -v maxl="$max_lines" -v maxb="$max_bytes" -v file="$file" '
    { len[NR] = length($0) + 1; txt[NR] = $0; if ($0 ~ /^## /) head[NR] = 1; total += len[NR] }
    END {
      n = NR; if (n == 0) exit
      start = n - maxl + 1; if (start < 1) start = 1
      if (start > 1) { s = start; while (s <= n && !(s in head)) s++; if (s <= n) start = s }
      bytes = 0; for (i = start; i <= n; i++) bytes += len[i]
      while (bytes > maxb) {
        s = start + 1; while (s <= n && !(s in head)) s++
        if (s > n) break
        for (i = start; i < s; i++) bytes -= len[i]
        start = s
      }
      if (start > 1 || bytes > maxb) {
        shown = n - start + 1
        printf "[DIALOGUE excerpt: %s is %d bytes, %d lines. Shown: the newest entries, as tail -n %d %s would; raise the N in tail -n N for earlier ones]\n\n", file, total, n, shown, file
      }
      if (bytes > maxb) {
        out = ""; for (i = start; i <= n; i++) out = out txt[i] "\n"
        printf "%s", substr(out, length(out) - maxb + 1)
      } else {
        for (i = start; i <= n; i++) print txt[i]
      }
    }
  ' "$file"
}

# loom_log_excerpt FILE [TAIL_BYTES] → pointer line, the latest Ledger block, the latest Hand-over
#   entry, then a heading-aligned tail (default 12 KB) of everything written after the later of
#   the two. Exit 1 when the file carries neither, so the caller falls back to heading_aligned_tail.
#   A Ledger heading is "🧵 Ledger" or "🧵 LEDGER" followed by "(", ":" or the end of the line, so
#   "LEDGER erratum" and a thread named "LEDGERNAME" are not ledgers.
loom_log_excerpt() {
  local file="$1" tail_bytes="${2:-12000}" ledger_line handover_line bytes lines later after
  ledger_line=$(grep -n -E '^## .*🧵 (LEDGER|Ledger)([[:space:]]*[(:]|[[:space:]]*$)' "$file" 2>/dev/null | tail -n 1 | cut -d: -f1 || true)
  handover_line=$(grep -n '^## .*🤝 Hand-over' "$file" 2>/dev/null | tail -n 1 | cut -d: -f1 || true)
  [ -n "$ledger_line" ] || [ -n "$handover_line" ] || return 1
  bytes=$(wc -c < "$file" | tr -d ' ')
  lines=$(wc -l < "$file" | tr -d ' ')
  echo "[Loom log excerpt: '$file' is $bytes bytes, $lines lines. Shown below: the latest Ledger block, the latest Hand-over entry, and the newest entries written after them. For the rest: grep -n '^## ' '$file' | tail -40, then sed -n '<from>,<to>p' '$file']"
  _loom_block() {
    awk -v s="$1" -v max=50000 -v label="$2" '
      NR == s { print label $0; got = length($0) + 1; next }
      NR > s && /^## / { exit }
      NR > s { got += length($0) + 1; if (got > max) { print "[... block cut at " max " bytes; read the rest from the log ...]"; exit } print }
    ' "$file"
  }
  if [ -n "$ledger_line" ] && [ -n "$handover_line" ] && [ "$ledger_line" = "$handover_line" ]; then
    echo ""; _loom_block "$ledger_line" ""
  elif [ -n "$ledger_line" ] && [ -n "$handover_line" ] && [ "$handover_line" -lt "$ledger_line" ]; then
    echo ""; _loom_block "$ledger_line" ""
    echo ""; echo "[The latest Hand-over below is OLDER than the Ledger above.]"; _loom_block "$handover_line" ""
  else
    [ -n "$ledger_line" ] && { echo ""; _loom_block "$ledger_line" ""; }
    [ -n "$handover_line" ] && { echo ""; _loom_block "$handover_line" ""; }
  fi
  later=$ledger_line
  if [ -z "$later" ] || { [ -n "$handover_line" ] && [ "$handover_line" -gt "$later" ]; }; then later=$handover_line; fi
  after=$(awk -v s="$later" 'NR > s && /^## / { print NR; exit }' "$file")
  if [ -n "$after" ]; then
    local tmp count
    tmp=$(mktemp "${TMPDIR:-/tmp}/loom-after.XXXXXX") || return 0
    tail -n +"$after" "$file" > "$tmp"
    count=$(grep -c '^## ' "$tmp" || true)
    echo ""
    echo "[Entries written after the latest marker: $count, from line $after. Newest last.]"
    heading_aligned_tail "$tmp" "$tail_bytes"
    rm -f "$tmp"
  fi
  return 0
}

# NOTE: filter_preseeded_paths() removed — replaced by seed file infrastructure.
# preload_ensure() + find_preload_state() handle pre-session dedup via seed files.

# extract_skill_preloads SKILL_NAME
#   Wrapper around resolve_phase_cmds for Phase 0.
#   Reads SKILL.md, extracts Phase 0 CMD files + template files.
#   Outputs normalized tilde-prefix paths (one per line) to stdout.
#   Does NOT check dedup — caller handles that.
extract_skill_preloads() {
  resolve_phase_cmds "$1" "0"
}

# --- Workspace path resolution utilities ---

# find_project_root [START_DIR] — Walk up from START_DIR (default $PWD) to the
# nearest ancestor containing a .claude/ directory (the engine's per-repo marker).
# Echoes the root and returns 0; returns 1 if none found (caller falls back to PWD).
# Anchors session resolution to the repo/worktree root so `cd` into a subfolder
# doesn't fork a stray sessions/ dir or break the statusline. A git worktree /
# agent worktree has its own .claude, so it correctly anchors to itself.
find_project_root() {
  local dir="${1:-$PWD}"
  dir=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.claude" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# resolve_sessions_dir — Absolute path to the project's sessions/ dir, anchored to
# the nearest .claude/ ancestor so it's stable regardless of the current subfolder.
# Falls back to $PWD/sessions when no .claude marker is found (pre-setup dir).
resolve_sessions_dir() {
  local root
  root=$(find_project_root) || root="$PWD"
  # WORKSPACE (e.g. apps/viewer/extraction) nests sessions under that subtree.
  if [ -n "${WORKSPACE:-}" ]; then
    echo "$root/$WORKSPACE/sessions"
  else
    echo "$root/sessions"
  fi
}

# resolve_session_path — Normalizes a session path argument
# Accepts 3 forms:
#   1. Bare name: "2026_02_14_X" → "$SESSIONS_DIR/2026_02_14_X"
#   2. With prefix: "sessions/2026_02_14_X" → "$SESSIONS_DIR/2026_02_14_X"
#   3. Full path: "epic/sessions/2026_02_14_X" → used as-is (must contain "sessions/")
# Does NOT validate existence — caller decides.
resolve_session_path() {
  local input="$1"
  local sessions_dir
  sessions_dir=$(resolve_sessions_dir)

  case "$input" in
    */sessions/*)
      # Full path with sessions/ segment — use as-is
      echo "$input"
      ;;
    sessions/*)
      # Strip "sessions/" prefix, prepend resolved sessions dir
      echo "$sessions_dir/${input#sessions/}"
      ;;
    *)
      # Bare session name — prepend resolved sessions dir
      echo "$sessions_dir/$input"
      ;;
  esac
}

# --- Directory exclusion utilities ---
# Standard directories to exclude from discovery/scanning
STANDARD_EXCLUDED_DIRS="node_modules .git sessions tmp dist build"

# is_excluded_dir DIR_PATH [EXCLUDED_LIST]
#   Returns 0 if the basename of DIR_PATH matches any excluded name.
#   Defaults to $STANDARD_EXCLUDED_DIRS if no second arg.
is_excluded_dir() {
  local dir_path="$1"
  local excluded="${2:-$STANDARD_EXCLUDED_DIRS}"
  local dir_name
  dir_name="${dir_path##*/}"
  for excl in $excluded; do
    if [ "$dir_name" = "$excl" ]; then
      return 0
    fi
  done
  return 1
}

# is_path_excluded DIR_PATH [EXCLUDED_LIST]
#   Returns 0 if any path component matches an excluded name.
#   Uses parameter expansion (Bash 3.2 safe). Defaults to $STANDARD_EXCLUDED_DIRS.
is_path_excluded() {
  local dir_path="$1"
  local excluded="${2:-$STANDARD_EXCLUDED_DIRS}"
  local remaining="$dir_path"
  while [ -n "$remaining" ]; do
    local component="${remaining%%/*}"
    if [ "$component" = "$remaining" ]; then
      remaining=""
    else
      remaining="${remaining#*/}"
    fi
    [ -z "$component" ] && continue
    for excl in $excluded; do
      if [ "$component" = "$excl" ]; then
        return 0
      fi
    done
  done
  return 1
}

# _acquire_lock LOCK_DIR [MAX_RETRIES] [STALE_SECS]
#   mkdir-based spinlock. On contention, reclaims when the recorded holder PID is
#   dead (deterministic — covers SIGKILL, since a dead PID can never release) OR
#   the lock is older than STALE_SECS (backstop for PID reuse, or a holder that
#   died before writing its pid). Records $$ in LOCK_DIR/pid on acquire.
#   Returns 0 on acquire, 1 on timeout.
_acquire_lock() {
  local lock_dir="$1"
  local max_retries="${2:-100}"
  local stale_secs="${3:-10}"
  local retries=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    retries=$((retries + 1))
    if [ "$retries" -ge "$max_retries" ]; then
      return 1
    fi
    # PID-aware reclaim: a dead holder can never release, so take it back now.
    local holder=""
    holder=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
    if [ -n "$holder" ] && ! pid_exists "$holder"; then
      rm -f "$lock_dir/pid" 2>/dev/null || true
      rmdir "$lock_dir" 2>/dev/null || true
      continue
    fi
    # Age backstop: covers the pre-pid-write window and PID reuse.
    # Uses stat instead of find -mmin (macOS find has no fractional -mmin).
    if [ -d "$lock_dir" ]; then
      local lock_mtime now_epoch lock_age
      lock_mtime=$(stat -f "%m" "$lock_dir" 2>/dev/null || echo "0")
      now_epoch=$(date +%s)
      lock_age=$((now_epoch - lock_mtime))
      if [ "$lock_age" -gt "$stale_secs" ]; then
        rm -f "$lock_dir/pid" 2>/dev/null || true
        rmdir "$lock_dir" 2>/dev/null || true
        continue
      fi
    fi
    sleep 0.01
  done
  echo "$$" > "$lock_dir/pid" 2>/dev/null || true
  return 0
}

# _release_lock LOCK_DIR — release a lock taken via _acquire_lock.
#   Removes the pid file first: the dir is non-empty, so a bare rmdir would fail.
_release_lock() {
  local lock_dir="$1"
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}

# _pid_is_alive PID — true when PID names an existing process, ours or not.
#   `kill -0` alone cannot answer this: it fails with EPERM when the process EXISTS but belongs to
#   another user, and only ESRCH means "gone". Treating every failure as death deletes the in-flight
#   temp of a live foreign-owned writer — the one case the reaper exists to protect.
#   The discriminator is `ps -p`'s exit status, not `kill`'s stderr: the shell's `kill` reports
#   `strerror(errno)`, so the message text moves with locale and differs between shells, while
#   `ps -p` answers existence without needing permission to signal. Status 0 = exists, 1 = no such
#   process, anything else (127 for a missing `ps`, or a `ps` failure) = unknown, and unknown is
#   reported as alive so the caller keeps the temp. A retained orphan is harmless; a deleted live
#   temp is not.
_pid_is_alive() {
  local pid="${1:?_pid_is_alive requires PID as arg 1}"
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  local ps_rc=0
  ps -p "$pid" >/dev/null 2>&1 || ps_rc=$?
  case "$ps_rc" in
    1) return 1 ;;
    *) return 0 ;;
  esac
}

# _reap_stale_temps FILE — remove `FILE.tmp.<pid>` siblings whose writer is gone.
#   The atomic write is `write tmp` then `mv`. A writer killed anywhere in between leaves the temp
#   behind — measured on a real backlog, most are complete and a third are truncated mid-write — and
#   neither a failure-path `rm -f` nor an EXIT trap covers it, since SIGKILL runs neither. Reclaim is
#   therefore deferred to the next writer: a temp whose pid is no longer alive has nobody left to mv
#   it. A pid reused by an unrelated live process survives this pass and is reaped on a later one.
#   Reaps for whatever FILE the caller passes, so it covers seed files as well as `.state.json`.
#   Call under the lock, before writing.
#
#   The `if` form is deliberate: under `set -e` a bare failing simple command in a loop body exits
#   the script, and an `if` compound returns 0 when its condition is false, so the body's last
#   command always succeeds. (`&&`/`||` operands are exempt from `set -e`, so that is not the hazard.)
_reap_stale_temps() {
  local file="${1:?_reap_stale_temps requires FILE as arg 1}"
  local tmp pid
  for tmp in "${file}".tmp.*; do
    [ -f "$tmp" ] || continue
    pid="${tmp##*.tmp.}"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    if [ "$pid" != "$$" ] && ! _pid_is_alive "$pid"; then
      rm -f "$tmp" 2>/dev/null || true
    fi
  done
}

# safe_json_write FILE
#   Reads JSON from stdin, validates with `jq empty`, writes atomically.
#   Uses a PID-aware mkdir spinlock (_acquire_lock) for concurrency safety.
#   Exit 1 on invalid JSON or write failure.
safe_json_write() {
  local file="${1:?safe_json_write requires FILE as arg 1}"
  local lock_dir="${file}.lock"
  local tmp_file="${file}.tmp.$$"
  local json

  # Read JSON from stdin
  json=$(cat)

  # Validate JSON
  if ! echo "$json" | jq empty 2>/dev/null; then
    echo "ERROR: safe_json_write: invalid JSON for $file" >&2
    return 1
  fi

  # Acquire lock (PID-aware + age-based stale reclaim)
  if ! _acquire_lock "$lock_dir"; then
    echo "ERROR: safe_json_write: lock timeout for $file" >&2
    return 1
  fi

  _reap_stale_temps "$file"

  # Write atomically: temp file + mv
  if echo "$json" > "$tmp_file" && mv "$tmp_file" "$file"; then
    _release_lock "$lock_dir"
    return 0
  else
    rm -f "$tmp_file"
    _release_lock "$lock_dir"
    echo "ERROR: safe_json_write: write failed for $file" >&2
    return 1
  fi
}

# safe_json_update FILE [JQ_ARGS...] JQ_FILTER
#   Atomic read-modify-write: acquires lock, reads FILE, applies jq filter, writes result.
#   Prevents TOCTOU race where `jq ... FILE | safe_json_write FILE` reads before locking.
#   All args after FILE are passed directly to jq (--arg, --argjson, then filter last).
safe_json_update() {
  local file="${1:?safe_json_update requires FILE as arg 1}"
  shift
  # remaining args: [jq_flags...] jq_filter

  local lock_dir="${file}.lock"
  local tmp_file="${file}.tmp.$$"

  # Acquire lock (PID-aware + age-based stale reclaim)
  if ! _acquire_lock "$lock_dir"; then
    echo "ERROR: safe_json_update: lock timeout for $file" >&2
    return 1
  fi

  _reap_stale_temps "$file"

  # Read + transform + write under lock
  local result
  if ! result=$(jq "$@" "$file" 2>/dev/null); then
    _release_lock "$lock_dir"
    echo "ERROR: safe_json_update: jq transform failed for $file" >&2
    return 1
  fi

  # Validate result
  if ! echo "$result" | jq empty 2>/dev/null; then
    _release_lock "$lock_dir"
    echo "ERROR: safe_json_update: invalid JSON result for $file" >&2
    return 1
  fi

  # Write atomically: temp file + mv
  if echo "$result" > "$tmp_file" && mv "$tmp_file" "$file"; then
    _release_lock "$lock_dir"
    return 0
  else
    rm -f "$tmp_file"
    _release_lock "$lock_dir"
    echo "ERROR: safe_json_update: write failed for $file" >&2
    return 1
  fi
}

# --- Input validation functions ---
# Boundary validation for user/LLM-provided strings.
# All validators exit 1 with stderr on failure (fail-hard).

# validate_tag TAG
#   Strips leading # if present. Validates: ^[a-z][a-z0-9-]*$
#   Outputs the clean tag (without #) on stdout.
#   Exit 1 on invalid input.
validate_tag() {
  local raw="${1:-}"
  # Strip leading #
  local tag="${raw#\#}"
  if [ -z "$tag" ]; then
    echo "ERROR: validate_tag: empty tag" >&2
    return 1
  fi
  if ! [[ "$tag" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR: validate_tag: invalid tag '$raw' (must match ^[a-z][a-z0-9-]*$)" >&2
    return 1
  fi
  echo "$tag"
}

# validate_subcmd SUBCMD
#   Validates: ^[a-z][a-z0-9-]+$ (minimum 2 chars)
#   Exit 1 on invalid input.
validate_subcmd() {
  local subcmd="${1:-}"
  if [ -z "$subcmd" ]; then
    echo "ERROR: validate_subcmd: empty subcommand" >&2
    return 1
  fi
  if ! [[ "$subcmd" =~ ^[a-z][a-z0-9-]+$ ]]; then
    echo "ERROR: validate_subcmd: invalid subcommand '$subcmd' (must match ^[a-z][a-z0-9-]+$)" >&2
    return 1
  fi
}

# validate_path PATH
#   Rejects ".." traversal components. Checks file or directory exists.
#   Exit 1 on invalid input.
validate_path() {
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "ERROR: validate_path: empty path" >&2
    return 1
  fi
  # Reject ".." path components
  if [[ "$path" == *".."* ]]; then
    echo "ERROR: validate_path: path traversal detected in '$path'" >&2
    return 1
  fi
  # Check existence (file or directory)
  if [ ! -e "$path" ]; then
    echo "ERROR: validate_path: path does not exist: '$path'" >&2
    return 1
  fi
}

# validate_phase PHASE_LABEL
#   Rejects sed metacharacters (/, &, \) and newlines.
#   Exit 1 on invalid input.
validate_phase() {
  local phase="${1:-}"
  if [ -z "$phase" ]; then
    echo "ERROR: validate_phase: empty phase label" >&2
    return 1
  fi
  # Reject sed metacharacters and newlines
  if [[ "$phase" == *"/"* ]] || [[ "$phase" == *"&"* ]] || [[ "$phase" == *"\\"* ]] || [[ "$phase" == *$'\n'* ]]; then
    echo "ERROR: validate_phase: invalid characters in phase label '$phase' (no /, &, \\, or newlines)" >&2
    return 1
  fi
}

# --- Rule evaluation engine ---
# Core evaluation function for the unified guard rule engine.
# Extracted from session.sh evaluate-guards for shared use between
# the hook (inline) and session.sh (backward compat wrapper).

# _resolve_payload_refs PAYLOAD_JSON STATE_FILE
#   Resolve "$fieldName" references in payload values from .state.json.
#   Two-pass resolution:
#     Pass 1 (whole-value): Strings starting with "$" get replaced entirely.
#       Example: "$pendingPreloads" → ["~/.claude/.directives/a.md", "~/.claude/.directives/b.md"]
#     Pass 2 (inline): Strings containing "$field" get interpolated in-place.
#       Example: "lifecycle: $lifecycle" → "lifecycle: completed"
#       Only substitutes scalar state values (string, number, boolean).
#   Returns the resolved payload JSON.
_resolve_payload_refs() {
  local payload="$1" state_file="$2"

  if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
    echo "$payload"
    return 0
  fi

  local resolved="$payload"

  # Pass 1: Whole-value $field resolution
  # Keys whose values are strings starting with "$" get replaced entirely
  local ref_keys
  ref_keys=$(echo "$payload" | jq -r 'to_entries[] | select(.value | type == "string" and startswith("$")) | .key' 2>/dev/null || echo "")

  if [ -n "$ref_keys" ]; then
    while IFS= read -r key; do
      [ -z "$key" ] && continue
      local ref_val field_name
      ref_val=$(echo "$payload" | jq -r --arg k "$key" '.[$k]')
      field_name="${ref_val#\$}"

      local state_val
      state_val=$(jq --arg f "$field_name" '.[$f] // null' "$state_file" 2>/dev/null || echo "null")

      if [ "$state_val" != "null" ]; then
        resolved=$(echo "$resolved" | jq --arg k "$key" --argjson v "$state_val" '.[$k] = $v')
      fi
    done <<< "$ref_keys"
  fi

  # Pass 2: Inline $field interpolation within string values
  # Handles strings like "lifecycle: $lifecycle, dir: $sessionDir"
  # Only substitutes scalar state values (string, number, boolean)
  local inline_keys
  inline_keys=$(echo "$resolved" | jq -r 'to_entries[] | select(.value | type == "string" and contains("$") and (startswith("$") | not)) | .key' 2>/dev/null || echo "")

  if [ -n "$inline_keys" ]; then
    while IFS= read -r key; do
      [ -z "$key" ] && continue
      local str_val
      str_val=$(echo "$resolved" | jq -r --arg k "$key" '.[$k]')
      local vars
      vars=$(echo "$str_val" | grep -oE '\$[a-zA-Z_][a-zA-Z0-9_]*' | sort -u | awk '{print length, $0}' | sort -rnk1 | awk '{print $2}' || echo "")
      if [ -n "$vars" ]; then
        local new_val="$str_val"
        while IFS= read -r var_ref; do
          [ -z "$var_ref" ] && continue
          local var_name="${var_ref#\$}"
          local var_val
          var_val=$(jq -r --arg f "$var_name" '.[$f] // null | if type == "string" or type == "number" or type == "boolean" then tostring else "" end' "$state_file" 2>/dev/null || echo "")
          if [ -n "$var_val" ]; then
            new_val="${new_val//$var_ref/$var_val}"
          fi
        done <<< "$vars"
        resolved=$(echo "$resolved" | jq --arg k "$key" --arg v "$new_val" '.[$k] = $v')
      fi
    done <<< "$inline_keys"
  fi

  echo "$resolved"
}

# evaluate_rules STATE_FILE GUARDS_FILE [TRANSCRIPT_KEY] [TOOL_NAME]
#   Evaluate all guard rules against current session state.
#   Outputs matched rules as a JSON array (sorted by priority) to stdout.
#   TRANSCRIPT_KEY is optional — used for perTranscriptToolCount trigger.
#   TOOL_NAME is optional — used for toolFilter exclusion (e.g., skip preload on Bash/Grep/Glob).
#
#   Reads: .state.json fields (contextUsage, lifecycle, currentPhase, etc.)
#   Reads: guards.json rules
#   Reads: config.sh for OVERFLOW_THRESHOLD
#
#   Returns 0 always (errors produce empty array).
evaluate_rules() {
  local state_file="${1:?evaluate_rules requires STATE_FILE}"
  local guards_file="${2:?evaluate_rules requires GUARDS_FILE}"
  local transcript_key="${3:-}"
  local tool_name="${4:-}"

  if [ ! -f "$state_file" ] || [ ! -f "$guards_file" ]; then
    echo "[]"
    return 0
  fi

  # Source config for OVERFLOW_THRESHOLD if present. Test-before-source: under
  # bash 3.2 a failed `source` exits under `set -e` before `|| true` runs.
  if [ -f "$HOME/.claude/engine/config.sh" ]; then
    source "$HOME/.claude/engine/config.sh"
  fi
  local overflow_threshold="${OVERFLOW_THRESHOLD:-0.76}"

  # Read current state
  local context_usage current_phase lifecycle
  context_usage=$(state_read "$state_file" "contextUsage" "0")
  current_phase=$(state_read "$state_file" "currentPhase" "")
  lifecycle=$(state_read "$state_file" "lifecycle" "")

  # Read existing injectedRules
  local injected_rules
  injected_rules=$(jq -r '.injectedRules // {}' "$state_file" 2>/dev/null || echo '{}')

  # Build new matched rules array
  local new_pending="[]"

  # Process each rule
  local rule_count
  rule_count=$(jq 'length' "$guards_file" 2>/dev/null || echo "0")
  local i
  for (( i=0; i<rule_count; i++ )); do
    local rule rule_id inject_freq trigger_type
    rule=$(jq ".[$i]" "$guards_file")
    rule_id=$(echo "$rule" | jq -r '.id')
    inject_freq=$(echo "$rule" | jq -r '.inject')
    trigger_type=$(echo "$rule" | jq -r '.trigger.type')

    # Skip inject:once rules already delivered
    if [ "$inject_freq" = "once" ]; then
      local already_injected
      already_injected=$(echo "$injected_rules" | jq -r --arg id "$rule_id" '.[$id] // "false"')
      if [ "$already_injected" = "true" ]; then
        continue
      fi
    fi

    # Skip rules excluded for this tool type (toolFilter.exclude)
    if [ -n "$tool_name" ]; then
      local excluded
      excluded=$(echo "$rule" | jq -r --arg t "$tool_name" '(.toolFilter.exclude // []) | any(. == $t)')
      if [ "$excluded" = "true" ]; then
        continue
      fi
      # Skip rules that only apply to specific tools (toolFilter.include)
      local has_include
      has_include=$(echo "$rule" | jq -r '.toolFilter.include // null | type')
      if [ "$has_include" = "array" ]; then
        local included
        included=$(echo "$rule" | jq -r --arg t "$tool_name" '.toolFilter.include | any(. == $t)')
        if [ "$included" != "true" ]; then
          continue
        fi
      fi
    fi

    local matched=false

    case "$trigger_type" in
      contextThreshold)
        local threshold
        threshold=$(echo "$rule" | jq -r '.trigger.condition.gte')
        # Resolve OVERFLOW_THRESHOLD reference
        if [ "$threshold" = "OVERFLOW_THRESHOLD" ]; then
          threshold="$overflow_threshold"
        fi
        if [ "$(echo "$context_usage >= $threshold" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
          matched=true
        fi
        ;;

      lifecycle)
        local no_active lifecycle_eq
        no_active=$(echo "$rule" | jq -r '.trigger.condition.noActiveSession // false')
        lifecycle_eq=$(echo "$rule" | jq -r '.trigger.condition.eq // ""')
        if [ "$no_active" = "true" ]; then
          if [ "$lifecycle" != "active" ] && [ "$lifecycle" != "idle" ] && [ "$lifecycle" != "resuming" ] && [ "$lifecycle" != "restarting" ]; then
            matched=true
          fi
        elif [ -n "$lifecycle_eq" ]; then
          if [ "$lifecycle" = "$lifecycle_eq" ]; then
            matched=true
          fi
        fi
        ;;

      phase)
        local phase_pattern
        phase_pattern=$(echo "$rule" | jq -r '.trigger.condition.matches')
        if [[ "$current_phase" == *"$phase_pattern"* ]]; then
          matched=true
        fi
        ;;

      toolCount)
        local field gte_field field_val threshold_val
        field=$(echo "$rule" | jq -r '.trigger.condition.field')
        gte_field=$(echo "$rule" | jq -r '.trigger.condition.gte')
        field_val=$(state_read "$state_file" "$field" "0")
        threshold_val=$(state_read "$state_file" "$gte_field" "999")
        if [ "$field_val" -ge "$threshold_val" ] 2>/dev/null; then
          matched=true
        fi
        ;;

      discovery)
        local disc_field non_empty
        disc_field=$(echo "$rule" | jq -r '.trigger.condition.field')
        non_empty=$(echo "$rule" | jq -r '.trigger.condition.nonEmpty // false')
        if [ "$non_empty" = "true" ]; then
          local field_len
          field_len=$(jq --arg f "$disc_field" '.[$f] // [] | length' "$state_file" 2>/dev/null || echo 0)
          if [ "$field_len" -gt 0 ]; then
            matched=true
          fi
        fi
        ;;

      perTranscriptToolCount)
        # Per-transcript counter trigger: reads toolCallsByTranscript[key]
        # Supports gte (>=) and eq (==) conditions
        if [ -n "$transcript_key" ]; then
          local counter_val
          counter_val=$(jq -r --arg key "$transcript_key" '(.toolCallsByTranscript // {})[$key] // 0' "$state_file" 2>/dev/null || echo "0")

          local gte_val eq_val
          gte_val=$(echo "$rule" | jq -r '.trigger.condition.gte // ""')
          eq_val=$(echo "$rule" | jq -r '.trigger.condition.eq // ""')

          if [ -n "$gte_val" ] && [ "$counter_val" -ge "$gte_val" ] 2>/dev/null; then
            matched=true
          elif [ -n "$eq_val" ] && [ "$counter_val" -eq "$eq_val" ] 2>/dev/null; then
            matched=true
          fi
        fi
        ;;

      *)
        # Unknown trigger type — skip
        continue
        ;;
    esac

    if [ "$matched" = "true" ]; then
      local mode urgency priority payload whitelist_arr
      mode=$(echo "$rule" | jq -r '.mode')
      urgency=$(echo "$rule" | jq -r '.urgency')
      priority=$(echo "$rule" | jq -r '.priority')
      payload=$(echo "$rule" | jq '.payload')

      # Dynamic payload resolution: resolve "$fieldName" references from .state.json
      # Example: payload.preload = "$pendingPreloads" → resolves to actual array from state
      payload=$(_resolve_payload_refs "$payload" "$state_file")

      whitelist_arr=$(echo "$rule" | jq '.whitelist // []')

      # appliesTo (optional): tool names this rule fires for. null = every tool (default).
      # Used to scope a rule to a positive tool set (e.g. heartbeat → reads only), which,
      # unlike the bypass whitelist, keeps non-listed tools unblocked by default — so writes
      # and every present/future MCP tool are structurally never blocked.
      local applies_to_arr
      applies_to_arr=$(echo "$rule" | jq '.appliesTo // null')

      local entry
      entry=$(jq -n \
        --arg ruleId "$rule_id" \
        --arg mode "$mode" \
        --arg urgency "$urgency" \
        --argjson priority "$priority" \
        --argjson payload "$payload" \
        --argjson whitelist "$whitelist_arr" \
        --argjson appliesTo "$applies_to_arr" \
        --arg evaluatedAt "$(timestamp)" \
        '{ruleId: $ruleId, mode: $mode, urgency: $urgency, priority: $priority, payload: $payload, whitelist: $whitelist, appliesTo: $appliesTo, evaluatedAt: $evaluatedAt}')

      new_pending=$(echo "$new_pending" | jq --argjson entry "$entry" '. + [$entry]')
    fi
  done

  # Sort by priority (lower number = higher priority)
  echo "$new_pending" | jq 'sort_by(.priority)'
}

# --- tmux guard utilities ---
# Used by guard framework hooks for paste mode delivery.
# All functions degrade gracefully outside tmux (¶INV_TMUX_AND_FLEET_OPTIONAL).

# tmux_paste TEXT
#   Send text to the CALLER'S tmux pane via send-keys (literal mode).
#   Uses $TMUX_PANE to target the correct pane, preventing cross-pane contamination
#   in multi-agent fleet setups. Falls back to active pane if $TMUX_PANE is unset.
#   Returns 1 if not inside tmux.
tmux_paste() {
  local text="${1:?tmux_paste requires TEXT as arg 1}"
  if [ -z "${TMUX:-}" ]; then
    return 1
  fi
  local target_flag=""
  if [ -n "${TMUX_PANE:-}" ]; then
    target_flag="-t $TMUX_PANE"
  fi
  # Use literal mode (-l) to avoid key interpretation, then send Enter
  tmux send-keys $target_flag -l "$text" 2>/dev/null && tmux send-keys $target_flag Enter 2>/dev/null
}

# tmux_interrupt_and_paste TEXT
#   Send Escape to cancel current generation, wait for settle, then paste.
#   The 0.5s delay gives Claude Code time to process the interrupt.
#   Uses $TMUX_PANE for pane targeting (same as tmux_paste).
#   Returns 1 if not inside tmux.
tmux_interrupt_and_paste() {
  local text="${1:?tmux_interrupt_and_paste requires TEXT as arg 1}"
  if [ -z "${TMUX:-}" ]; then
    return 1
  fi
  local target_flag=""
  if [ -n "${TMUX_PANE:-}" ]; then
    target_flag="-t $TMUX_PANE"
  fi
  # ESC cancels Claude Code's current generation
  tmux send-keys $target_flag Escape 2>/dev/null
  sleep 0.3
  # Second ESC for reliability (belt and suspenders)
  tmux send-keys $target_flag Escape 2>/dev/null
  sleep 0.3
  # Ctrl+U clears the textarea (any leftover typed text)
  tmux send-keys $target_flag C-u 2>/dev/null
  sleep 0.3
  # Now paste the text
  tmux_paste "$text"
}

# --- Whitelist matching utilities ---
# Used by the unified rule engine hook for tool whitelisting.

# PRIMARY_INPUT_FIELD — maps tool name to its primary input field for whitelist matching
# Hardcoded per plan: Bash→command, Read→file_path, Edit→file_path, Write→file_path,
# Skill→skill, Glob→pattern, Grep→pattern. All others → tool name only (no input match).
_primary_input_field() {
  case "$1" in
    Bash)  echo "command" ;;
    Read)  echo "file_path" ;;
    Edit)  echo "file_path" ;;
    Write) echo "file_path" ;;
    Skill) echo "skill" ;;
    Glob)  echo "pattern" ;;
    Grep)  echo "pattern" ;;
    *)     echo "" ;;
  esac
}

# match_whitelist_entry PATTERN TOOL_NAME TOOL_INPUT_VALUE
#   Matches a single whitelist pattern against a tool call.
#   Pattern format: "ToolName" or "ToolName(glob)"
#   Returns 0 (match) or 1 (no match).
#
#   Examples:
#     match_whitelist_entry "AskUserQuestion" "AskUserQuestion" ""        → 0
#     match_whitelist_entry "Read(~/.claude/*)" "Read" "~/.claude/foo.md" → 0
#     match_whitelist_entry "Bash(engine session *)" "Bash" "engine session activate" → 0
#     match_whitelist_entry "Read(~/.claude/*)" "Edit" "/some/file"       → 1
match_whitelist_entry() {
  local pattern="$1" tool_name="$2" tool_input="${3:-}"

  # Check if pattern has a glob: "ToolName(glob)"
  if [[ "$pattern" == *"("*")"* ]]; then
    # Extract tool part and glob part
    local pat_tool="${pattern%%(*}"
    local pat_glob="${pattern#*(}"
    pat_glob="${pat_glob%)}"

    # Tool name must match
    if [ "$pat_tool" != "$tool_name" ]; then
      return 1
    fi

    # Glob must match the tool input value
    # shellcheck disable=SC2053
    if [[ "$tool_input" == $pat_glob ]]; then
      return 0
    fi
    return 1
  else
    # Bare tool name match — "ToolName" matches any call to that tool
    if [ "$pattern" = "$tool_name" ]; then
      return 0
    fi
    return 1
  fi
}

# match_whitelist WHITELIST_JSON TOOL_NAME TOOL_INPUT_JSON
#   Check a tool against a JSON array of whitelist patterns.
#   Resolves the primary input field from TOOL_INPUT_JSON automatically.
#   Returns 0 if any pattern matches, 1 if none match.
#   Empty or null whitelist → returns 1 (no match = block all).
#
#   Usage:
#     match_whitelist '["AskUserQuestion","Bash(engine session *)"]' "Bash" '{"command":"engine session activate"}'
match_whitelist() {
  local whitelist_json="$1" tool_name="$2" tool_input_json="${3:-{\}}"

  # Empty or null whitelist means no whitelist → block all
  local wl_len
  wl_len=$(echo "$whitelist_json" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
  if [ "$wl_len" -eq 0 ]; then
    return 1
  fi

  # Resolve primary input value for this tool
  local input_field tool_input_value=""
  input_field=$(_primary_input_field "$tool_name")
  if [ -n "$input_field" ]; then
    tool_input_value=$(echo "$tool_input_json" | jq -r --arg f "$input_field" '.[$f] // ""' 2>/dev/null || echo "")
  fi

  # Check each pattern
  local i pattern
  for (( i=0; i<wl_len; i++ )); do
    pattern=$(echo "$whitelist_json" | jq -r ".[$i]" 2>/dev/null || echo "")
    if match_whitelist_entry "$pattern" "$tool_name" "$tool_input_value"; then
      return 0
    fi
  done

  return 1
}

# --- Reference resolution utilities ---

# resolve_refs FILE_PATH [DEPTH] [ALREADY_LOADED_JSON]
#   Scans FILE_PATH for unescaped §(CMD|FMT|INV|TAG)_ references.
#   Resolves each to a file path via convention-based prefix-to-folder mapping.
#   Recurses to DEPTH (default 2). Deduplicates against ALREADY_LOADED_JSON.
#   Walk-up resolution: starts from FILE_PATH's directory, walks up checking
#   .directives/{prefix_folder}/ at each level, falls back to engine .directives/.
#   Outputs resolved file paths (one per line, tilde-prefix normalized) to stdout.
#
#   Prefix-to-folder mapping:
#     CMD → commands/
#     FMT → formats/
#     INV → invariants/
#     TAG → tags/
#
#   Code fences (``` blocks) are stripped before scanning, so refs inside JSON
#   schemas (e.g. phases steps/commands arrays) are never extracted.
#   Only § (section sign) references are resolved, not ¶ (pilcrow) definitions.
#
#   Returns: 0 always. Empty output = no refs found or all already loaded.
resolve_refs() {
  local file_path="${1:-}"
  local depth="${2:-2}"
  local already_loaded_json="${3:-[]}"

  [ -n "$file_path" ] || return 0
  [ -f "$file_path" ] || return 0
  [ "$depth" -gt 0 ] 2>/dev/null || return 0

  # Two-pass regex: strip code fences + backtick spans, then extract § references
  # Pass 1: awk skips lines inside ``` code fences AND strips inline `code` spans
  # Pass 2: Extract bare §(CMD|FMT|INV|TAG)_NAME references
  local refs
  refs=$(awk '/^```/{skip=!skip; next} skip{next} {gsub(/`[^`]*`/, ""); print}' "$file_path" | grep -oE '§(CMD|FMT|INV|TAG)_[A-Z][A-Z0-9_]*' | sort -u || true)

  [ -n "$refs" ] || return 0

  # Resolve the starting directory for walk-up
  local start_dir
  start_dir=$(cd "${file_path%/*}" && pwd)

  # Project root detection (stop walk-up here)
  local project_root="${PROJECT_ROOT:-$(pwd)}"

  # Engine directives fallback
  local engine_directives="$HOME/.claude/engine/.directives"

  local new_depth=$((depth - 1))
  local collected=""

  while IFS= read -r ref; do
    [ -n "$ref" ] || continue

    # Extract prefix and name: §CMD_FOO → prefix=CMD, name=FOO, full=CMD_FOO
    local full_name="${ref#§}"
    local prefix="${full_name%%_*}"
    local ref_name="$full_name"

    # Prefix-to-folder mapping
    local folder
    case "$prefix" in
      CMD) folder="commands" ;;
      FMT) folder="formats" ;;
      INV) folder="invariants" ;;
      TAG) folder="tags" ;;
      *)   continue ;;
    esac

    # Walk-up resolution: check .directives/{folder}/ at each ancestor level
    local resolved=""
    local search_dir="$start_dir"
    while true; do
      local candidate="$search_dir/.directives/$folder/${ref_name}.md"
      if [ -f "$candidate" ]; then
        resolved="$candidate"
        break
      fi

      # Stop at project root or filesystem root
      if [ "$search_dir" = "$project_root" ] || [ "$search_dir" = "/" ] || [ -z "$search_dir" ]; then
        break
      fi

      # Move up one level
      search_dir="${search_dir%/*}"
    done

    # Fallback to engine .directives/
    if [ -z "$resolved" ]; then
      local engine_candidate="$engine_directives/$folder/${ref_name}.md"
      if [ -f "$engine_candidate" ]; then
        resolved="$engine_candidate"
      fi
    fi

    [ -n "$resolved" ] || continue

    # Normalize the path for dedup
    local normalized
    normalized=$(normalize_preload_path "$resolved")

    # Check against already_loaded list
    local already_present
    already_present=$(echo "$already_loaded_json" | jq -r --arg p "$normalized" 'any(. == $p)' 2>/dev/null || echo "false")
    if [ "$already_present" = "true" ]; then
      continue
    fi

    # Check against collected so far (prevent duplicates in output)
    case "$collected" in
      *"|$normalized|"*) continue ;;
    esac
    collected="${collected}|${normalized}|"

    # Output this resolved path
    echo "$normalized"

    # Recurse into the resolved file (depth - 1)
    if [ "$new_depth" -gt 0 ]; then
      # Add current file to already_loaded for recursion dedup
      local updated_loaded
      updated_loaded=$(echo "$already_loaded_json" | jq --arg p "$normalized" '. + [$p]' 2>/dev/null || echo "$already_loaded_json")
      local sub_refs
      sub_refs=$(resolve_refs "$resolved" "$new_depth" "$updated_loaded")
      if [ -n "$sub_refs" ]; then
        while IFS= read -r sub_path; do
          [ -n "$sub_path" ] || continue
          # Dedup against collected
          case "$collected" in
            *"|$sub_path|"*) continue ;;
          esac
          collected="${collected}|${sub_path}|"
          echo "$sub_path"
        done <<< "$sub_refs"
      fi
    fi
  done <<< "$refs"

  return 0
}

# --- Preload pipeline utilities ---

# _log_delivery HOOK EVENT FILE SOURCE
#   Structured delivery event logging, gated by PRELOAD_TEST_LOG env var.
#   Zero cost when env var is unset. Appends one JSON line per event.
#   Events: seed, direct-deliver, queue-pending, claim-deliver, skip-dedup, skip-inode, auto-expand
_log_delivery() {
  [ -n "${PRELOAD_TEST_LOG:-}" ] || return 0
  local hook="${1:-unknown}" event="${2:-unknown}" file="${3:-}" source="${4:-}"
  printf '{"hook":"%s","event":"%s","file":"%s","source":"%s","ts":"%s"}\n' \
    "$hook" "$event" "$file" "$source" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >> "$PRELOAD_TEST_LOG"
}

# find_preload_state [PID]
#   Returns the path to the preload tracking state file — seed or session.
#   Checks: 1) active session .state.json (by PID), 2) seed file, 3) creates seed.
#   PID defaults to $PPID (hooks are children of Claude).
#   Outputs path on stdout, returns 0. Returns 1 only if creation fails.
find_preload_state() {
  local target_pid="${1:-$PPID}"
  local sessions_dir
  sessions_dir=$(resolve_sessions_dir)

  # 1. Active session .state.json (by PID) — check if session.sh find works
  local session_dir
  session_dir=$("$HOME/.claude/scripts/session.sh" find 2>/dev/null || echo "")
  if [ -n "$session_dir" ] && [ -f "$session_dir/.state.json" ]; then
    echo "$session_dir/.state.json"
    return 0
  fi

  # 2. Seed file: sessions/.seeds/{pid}.json
  local seed_file="$sessions_dir/.seeds/${target_pid}.json"
  if [ -f "$seed_file" ]; then
    echo "$seed_file"
    return 0
  fi

  # 3. Create seed if neither exists
  mkdir -p "$sessions_dir/.seeds"
  local seeds_json
  seeds_json=$(get_session_start_seeds)
  jq -n --argjson pid "$target_pid" --argjson seeds "$seeds_json" '{
    pid: $pid,
    lifecycle: "seeding",
    preloadedFiles: $seeds,
    pendingPreloads: [],
    touchedDirs: {}
  }' > "$seed_file"
  echo "$seed_file"
  return 0
}

# _atomic_claim_preload NORMALIZED_PATH STATE_FILE
#   Atomically checks if a file is in preloadedFiles and claims it if not.
#   Uses the same mkdir lock as safe_json_write for mutual exclusion.
#   Prevents TOCTOU race when parallel hooks try to deliver the same file.
#   Echoes "claimed" if newly claimed, "already" if already present.
_atomic_claim_preload() {
  local normalized="$1" state_file="$2"
  local resolved="${normalized/#\~/$HOME}"
  local lock_dir="${state_file}.lock"

  # Acquire lock (PID-aware + age-based stale reclaim). Fail-safe: on timeout,
  # treat as claimed to avoid duplicate delivery.
  if ! _acquire_lock "$lock_dir"; then
    echo "already"
    return 0
  fi

  # Under lock: check preloadedFiles only (NOT pendingPreloads — files move
  # from pendingPreloads to preloadedFiles during normal delivery flow)
  local already
  already=$(jq -r --arg p "$normalized" --arg r "$resolved" '
    (.preloadedFiles // []) | any(. == $p or . == $r)
  ' "$state_file" 2>/dev/null || echo "false")

  if [ "$already" = "true" ]; then
    _release_lock "$lock_dir"
    echo "already"
    return 0
  fi

  # Claim: add to preloadedFiles
  jq --arg p "$normalized" '
    (.preloadedFiles //= []) | .preloadedFiles += [$p]
  ' "$state_file" > "${state_file}.tmp.$$"
  mv "${state_file}.tmp.$$" "$state_file"

  _release_lock "$lock_dir"
  echo "claimed"
  return 0
}

# _is_already_preloaded NORMALIZED_PATH STATE_FILE
#   Checks path + inode dedup against preloadedFiles in state.
#   Returns 0 if already preloaded, 1 if not.
_is_already_preloaded() {
  local normalized="$1" state_file="$2"
  [ -f "$state_file" ] || return 1

  local resolved="${normalized/#\~/$HOME}"

  # Path check (preloadedFiles only — pendingPreloads excluded so delivery path can consume queued files)
  local path_match
  path_match=$(jq -r --arg p "$normalized" --arg r "$resolved" \
    '(.preloadedFiles // []) | any(. == $p or . == $r)' "$state_file" 2>/dev/null || echo "false")
  if [ "$path_match" = "true" ]; then
    return 0
  fi

  # Inode check
  if [ -f "$resolved" ]; then
    local file_inode
    file_inode=$(stat -f "%i" "$resolved" 2>/dev/null || echo "")
    if [ -n "$file_inode" ]; then
      local inode_match
      inode_match=$(jq -r --arg inode "$file_inode" '
        (.preloadedFiles // []) | any(. as $p |
          ($p | sub("^~"; env.HOME)) as $resolved |
          (try (input | .inode) catch "") == $inode
        )' "$state_file" 2>/dev/null || echo "false")
      # Fallback: check inodes by iterating (jq can't stat files)
      # This is the slow path — only reached if path dedup missed
      local existing
      while IFS= read -r existing; do
        [ -z "$existing" ] && continue
        local existing_resolved="${existing/#\~/$HOME}"
        [ -f "$existing_resolved" ] || continue
        local existing_inode
        existing_inode=$(stat -f "%i" "$existing_resolved" 2>/dev/null || echo "")
        if [ "$existing_inode" = "$file_inode" ]; then
          return 0
        fi
      done < <(jq -r '(.preloadedFiles // []) | .[]' "$state_file" 2>/dev/null)
    fi
  fi

  return 1
}

# preload_ensure PATH SOURCE URGENCY
#   Single entry point for preloading. Handles normalize, dedup, deliver-or-queue, tracking.
#   URGENCY: "immediate" (atomic state update + return content) or "next" (queue to pendingPreloads)
#   Sets global _PRELOAD_RESULT: "delivered" | "queued" | "skipped"
#   For immediate: sets global _PRELOAD_CONTENT with [Preloaded: path]\ncontent
preload_ensure() {
  local path="$1" source="${2:-unknown}" urgency="${3:-next}"
  local state_file normalized
  _PRELOAD_RESULT="skipped"
  _PRELOAD_CONTENT=""

  # 1. Normalize path
  normalized=$(normalize_preload_path "$path")

  # 2. Find state (seed or session)
  state_file=$(find_preload_state)

  # 3. Check dedup (path + inode)
  if _is_already_preloaded "$normalized" "$state_file"; then
    _log_delivery "${HOOK_NAME:-unknown}" "skip-dedup" "$normalized" "$source"
    _PRELOAD_RESULT="skipped"
    return 0
  fi

  # 4. Deliver or queue
  if [ "$urgency" = "immediate" ]; then
    local resolved="${normalized/#\~/$HOME}"
    if [ ! -f "$resolved" ]; then
      _PRELOAD_RESULT="skipped"
      return 0
    fi
    local content
    content=$(cat "$resolved" 2>/dev/null || true)
    [ -n "$content" ] || { _PRELOAD_RESULT="skipped"; return 0; }
    # A large PITFALLS.md delivered whole lands past the harness's preview cut, which shows the reader
    # a couple of KB and records the file as read. Its index fits, and says how to read any entry.
    if [ "$(basename "$resolved")" = "PITFALLS.md" ] && [ "${#content}" -gt "${PITFALLS_INLINE_MAX:-8000}" ]; then
      content="[Pitfalls index for this file, $(wc -c < "$resolved" | tr -d ' ') bytes, too large to deliver whole. Read an entry with: grep -n -A12 '¶PTF_<NAME>' '$resolved']
$(generate_pitfalls_index "$resolved")"
    fi

    # Atomic state update under lock — add to preloadedFiles
    safe_json_update "$state_file" --arg p "$normalized" '
      (.preloadedFiles //= []) |
      if (.preloadedFiles | index($p)) then .
      else .preloadedFiles += [$p]
      end
    '

    # Override detection: local CMD shadows a global CMD with same basename
    local override_header=""
    local basename_file
    basename_file=$(basename "$resolved")
    if [[ "$basename_file" == CMD_*.md ]] && [[ "$resolved" != *"engine/.directives/commands/"* ]]; then
      local global_match
      global_match=$(jq -r --arg bn "$basename_file" '.preloadedFiles // [] | .[] | select(endswith($bn)) | select(contains("engine/.directives/commands/"))' "$state_file" 2>/dev/null || echo "")
      if [ -n "$global_match" ]; then
        override_header="[Override: shadows $global_match]\n"
        _log_delivery "${HOOK_NAME:-unknown}" "override-detect" "$normalized" "shadows $global_match"
      fi
    fi

    _PRELOAD_CONTENT="${override_header}[Preloaded: $normalized]\n$content"
    _PRELOAD_RESULT="delivered"
    _log_delivery "${HOOK_NAME:-unknown}" "direct-deliver" "$normalized" "$source"
  else
    # Queue to pendingPreloads
    safe_json_update "$state_file" --arg p "$normalized" '
      (.pendingPreloads //= []) |
      if (.pendingPreloads | index($p)) then .
      else .pendingPreloads += [$p]
      end
    '

    _PRELOAD_RESULT="queued"
    _log_delivery "${HOOK_NAME:-unknown}" "queue-pending" "$normalized" "$source"
  fi

  # 5. Auto-expand: scan for § refs and queue them
  _auto_expand_refs "$normalized" "$state_file" "$source"

  return 0
}

# _auto_expand_refs NORMALIZED_PATH STATE_FILE SOURCE
#   Scans a file for § references and queues discovered refs via preload_ensure(next).
#   SKILL.md: allows FMT/INV refs but skips CMD refs (preserves lazy per-phase loading).
_auto_expand_refs() {
  local file="$1" state_file="$2" source="${3:-}"
  # Re-entrancy guard (fail-safe): expand each file at most once per hook
  # process. A §-reference cycle among not-yet-delivered ("next") files would
  # otherwise recurse forever here (preload_ensure <-> _auto_expand_refs): the
  # queue path records to .pendingPreloads while the visited-set only checks
  # .preloadedFiles, so a cycle is never detected. Bounds recursion to the
  # count of distinct files. §PTF_PRELOAD_EXPAND_CYCLE
  case "${_EXPANDED_REFS:-}" in
    *"|${file}|"*) return 0 ;;
  esac
  _EXPANDED_REFS="${_EXPANDED_REFS:-}|${file}|"
  local resolved="${file/#\~/$HOME}"
  [ -f "$resolved" ] || return 0

  local already_loaded
  already_loaded=$(jq -c '.preloadedFiles // []' "$state_file" 2>/dev/null || echo '[]')

  # depth=1: no explicit recursion — pipeline handles it naturally
  # resolve_refs() already strips code fences (``` blocks), so CMD refs inside
  # JSON schemas (phases steps/commands arrays) are never extracted.
  # All remaining refs are legitimate prose references — allow them all through.
  local refs
  refs=$(resolve_refs "$resolved" 1 "$already_loaded") || true
  [ -n "$refs" ] || return 0

  while IFS= read -r ref_path; do
    [ -z "$ref_path" ] && continue
    _log_delivery "${HOOK_NAME:-unknown}" "auto-expand" "$ref_path" "auto-expand($file)"
    # Queue the ref — don't deliver immediately (pipeline recursion)
    local old_result="$_PRELOAD_RESULT"
    preload_ensure "$ref_path" "auto-expand($file)" "next"
    _PRELOAD_RESULT="$old_result"
  done <<< "$refs"
}

# resolve_phase_cmds SKILL_NAME PHASE_LABEL
#   Unified CMD resolution for any phase. Reads SKILL.md JSON block,
#   finds the phase matching PHASE_LABEL, extracts steps[] + commands[] arrays.
#   Resolves each §CMD_* to a normalized file path.
#   Also outputs template paths for Phase 0 (logTemplate, debriefTemplate, planTemplate).
#   Outputs one path per line to stdout.
resolve_phase_cmds() {
  local skill_name="$1" phase_label="$2"
  local skill_dir="$HOME/.claude/skills/$skill_name"
  local skill_file="$skill_dir/SKILL.md"
  [ -f "$skill_file" ] || return 0

  # Extract JSON block from SKILL.md
  local params_json
  params_json=$(sed -n '/^```json$/,/^```$/p' "$skill_file" | sed '1d;$d' 2>/dev/null || echo "")
  [ -n "$params_json" ] || return 0

  # Find the phase entry matching phase_label
  # Phase labels can be "0", "1", "3.A", etc.
  local phase_cmds
  phase_cmds=$(echo "$params_json" | jq -r --arg label "$phase_label" '
    (.phases // []) as $phases |
    (($phases | map(select(.label == $label)) | first) //
     ($phases | map(select(
       (.label | tostring) == $label or
       (if .minor == 0 then "\(.major)" else "\(.major).\(.minor)" end) == $label
     )) | first) // null) |
    if . == null then empty
    else ((.steps // []) + (.commands // [])) | .[] | select(startswith("§CMD_"))
    end
  ' 2>/dev/null || echo "")

  local cmd_dir="$HOME/.claude/engine/.directives/commands"
  local seen_cmds=""
  if [ -n "$phase_cmds" ]; then
    while IFS= read -r field; do
      [ -n "$field" ] || continue
      local name="${field#§CMD_}"
      # Strip lowercase suffix (proof sub-field): GENERATE_DEBRIEF_file → GENERATE_DEBRIEF
      name=$(echo "$name" | sed -E 's/_[a-z][a-z_]*$//')
      case "$seen_cmds" in *"|${name}|"*) continue ;; esac
      seen_cmds="${seen_cmds}|${name}|"
      local cmd_file="$cmd_dir/CMD_${name}.md"
      [ -f "$cmd_file" ] || continue
      normalize_preload_path "$cmd_file"
    done <<< "$phase_cmds"
  fi

  # Always output template files — templates are needed throughout the session
  # (log template for logging, debrief template for synthesis, plan template for planning)
  local template_paths
  template_paths=$(echo "$params_json" | jq -r '[.logTemplate, .debriefTemplate, .planTemplate] | .[] // empty' 2>/dev/null || echo "")
  if [ -n "$template_paths" ]; then
    while IFS= read -r rel_path; do
      [ -n "$rel_path" ] || continue
      local candidate="$skill_dir/$rel_path"
      [ -f "$candidate" ] || continue
      normalize_preload_path "$candidate"
    done <<< "$template_paths"
  fi
}

# clear_agent_context SESSION_DIR
#   Force a context reset. In tmux: interrupt + paste "/session dehydrate restart".
#   Without tmux: signal session.sh restart for the wrapper to handle.
#   This is the generalized "clear context" primitive — intent over mechanism.
clear_agent_context() {
  local session_dir="${1:?clear_agent_context requires SESSION_DIR as arg 1}"
  if [ -n "${TMUX:-}" ]; then
    # tmux path: interrupt + paste dehydrate command
    tmux_interrupt_and_paste "/session dehydrate restart --session $session_dir"
  else
    # No tmux: signal restart via session.sh (wrapper picks it up)
    "$HOME/.claude/scripts/session.sh" restart "$session_dir" 2>/dev/null || true
  fi
}

# ---- Fleet identity: the live tmux pane wins over run.sh's launch-time cache ----
# run.sh exports FLEET_PANE (window:label) and FLEET_PARENT at launch. A seat renamed or
# re-parented since then still carries its old values in them, so any reader that trusts them
# acts under its old identity (domain:stats read "domain:domain"). These two functions read the
# live pane first, name the cache on stderr when it disagrees, and fall back to the cache only
# when tmux cannot be read — flagged with exit 3 and a stderr note.
#
#   fleet_self                          → this seat's window:label
#   fleet_parent [--live V] [--of SEAT] → this seat's parent seat; empty stdout = no parent
#       --live V  the caller already read the live edge (hop.sh, from its tree); "-" = none
#       --of SEAT names the seat in the stale warning
#   exit 0  live value on stdout (warning on stderr if the cache differed)
#   exit 3  tmux unreadable: the launch-time cache on stdout, flagged on stderr
#   exit 1  tmux unreadable and no cache: nothing on stdout
#   exit 2  usage error (fleet_parent)
#
# "Readable" means: $TMUX_PANE is set, the agent's own server is known ($TMUX, or an explicit
# FLEET_TMUX_SOCKET), and the pane is a fleet seat (it has a window name and an @pane_label).
# Label and parent come from ONE display call, so a pane that is not a seat never yields a
# "live: no parent" either. Without $TMUX a bare `tmux` would reach the default server, where
# the same %N is somebody else's pane — so there is no live read then, only the cache.
#
# Env: FLEET_TMUX_SOCKET — tmux -L socket for the live read (default: the server $TMUX names,
#                          addressed with -S so a stray -L/default server is never consulted)
#      FLEET_LIVE_PANES  — test seam: a file in hop.sh's live-tree shape
#                          ("<window:label> <pane_id> <parent or ->" per line), read instead of tmux
#      FLEET_WARN_PREFIX — the stderr prefix (default "fleet"; hop.sh passes "hop")
#      FLEET_WARN_ONCE_DIR — when set, each distinct stale warning (pane, cache, live) is printed
#                          once, stamped in this dir (await-next sets it: it runs every loop turn)
# Bash 3.2 safe (§PTF_BASH32_COMPATIBILITY): no arrays, no arithmetic, every var defaulted.

_fleet_tmux() {
  if [ -n "${FLEET_TMUX_SOCKET:-}" ]; then
    tmux -L "$FLEET_TMUX_SOCKET" "$@"
  elif [ -n "${TMUX:-}" ]; then
    tmux -S "${TMUX%%,*}" "$@"
  else
    return 1
  fi
}

# _fleet_live_read — "<window:label>|<parent or ->" for $TMUX_PANE, or exit 1 when unreadable.
_fleet_live_read() {
  local pane="${TMUX_PANE:-}" out="" label="" parent=""
  [ -n "$pane" ] || return 1
  if [ -n "${FLEET_LIVE_PANES:-}" ]; then
    [ -r "$FLEET_LIVE_PANES" ] || return 1
    out=$(awk -v p="$pane" '$2 == p { print $1 "|" ($3 == "" ? "-" : $3); exit }' "$FLEET_LIVE_PANES" 2>/dev/null) || return 1
  else
    # _fleet_tmux refuses (exit 1) when neither $TMUX nor FLEET_TMUX_SOCKET names a server.
    out=$(_fleet_tmux display -p -t "$pane" '#{window_name}:#{@pane_label}|#{?@pane_parent,#{@pane_parent},-}' 2>/dev/null) || return 1
  fi
  label="${out%%|*}"
  case "$out" in *"|"*) parent="${out#*|}" ;; *) parent="" ;; esac
  # A pane with no window name or no @pane_label is not a live fleet seat: neither value is live.
  case "$label" in ""|:*|*:) return 1 ;; esac
  printf '%s|%s\n' "$label" "$parent"
}

# _fleet_warn <key> <message> — stderr, once per key when FLEET_WARN_ONCE_DIR is set.
_fleet_warn() {
  local dir="${FLEET_WARN_ONCE_DIR:-}" stamp=""
  if [ -n "$dir" ]; then
    stamp="$dir/$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
    [ -e "$stamp" ] && return 0
    mkdir -p "$dir" 2>/dev/null && : > "$stamp" 2>/dev/null
  fi
  echo "$2" >&2
}

fleet_self() {
  local pfx="${FLEET_WARN_PREFIX:-fleet}" cache="${FLEET_PANE:-}" out="" live=""
  if out=$(_fleet_live_read); then
    live="${out%%|*}"
    if [ -n "$cache" ] && [ "$cache" != "$live" ]; then
      _fleet_warn "self|${TMUX_PANE:-}|$cache|$live" "$pfx: FLEET_PANE '$cache' is stale; using the live pane label '$live'"
    fi
    printf '%s\n' "$live"
    return 0
  fi
  if [ -n "$cache" ]; then
    echo "$pfx: cannot read the live pane label; using the launch-time FLEET_PANE '$cache' (cache)" >&2
    printf '%s\n' "$cache"
    return 3
  fi
  echo "$pfx: cannot resolve this seat's identity (no live pane label, no FLEET_PANE)" >&2
  return 1
}

fleet_parent() {
  local pfx="${FLEET_WARN_PREFIX:-fleet}" cache="${FLEET_PARENT:-}" live="" have=0 of="" of_txt="" out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --live) live="${2:-}"; [ -n "$live" ] && have=1; shift; [ $# -gt 0 ] && shift ;;
      --of) of="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      *) echo "$pfx: fleet_parent: unknown argument $1" >&2; return 2 ;;
    esac
  done
  if [ "$have" = 0 ] && out=$(_fleet_live_read); then
    live="${out#*|}"
    [ -n "$live" ] && have=1
  fi
  if [ "$have" = 1 ]; then
    [ "$live" = "-" ] && live=""
    [ -n "$of" ] && of_txt=" of '$of'"
    if [ -n "$cache" ] && [ "$cache" != "$live" ]; then
      _fleet_warn "parent|${TMUX_PANE:-}|$of|$cache|$live" \
        "$pfx: FLEET_PARENT '$cache' is stale; using the live @pane_parent '${live:-none}'$of_txt"
    elif [ -z "$cache" ] && [ -n "$live" ]; then
      _fleet_warn "parent-unset|${TMUX_PANE:-}|$of|$live" "$pfx: FLEET_PARENT unset; using live @pane_parent '$live'"
    fi
    [ -n "$live" ] && printf '%s\n' "$live"
    return 0
  fi
  if [ -n "$cache" ]; then
    echo "$pfx: cannot read the live @pane_parent; using the launch-time FLEET_PARENT '$cache' (cache)" >&2
    printf '%s\n' "$cache"
    return 3
  fi
  echo "$pfx: cannot resolve this seat's parent (no live @pane_parent, no FLEET_PARENT)" >&2
  return 1
}
