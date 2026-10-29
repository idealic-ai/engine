#!/bin/bash
# ~/.claude/scripts/migrate-fleet-pane-ids.sh — One-time migration for scoped fleetPaneId
#
# Related:
#   Docs: (~/.claude/docs/)
#     FLEET.md — Fleet pane ID format (scoped composite IDs)
#
# Migrates existing .state.json files from old format (e.g., "MCP") to new scoped format
# (e.g., "fleet:MCP"). Creates backups before modifying.
#
# Usage:
#   migrate-fleet-pane-ids.sh [sessions_dir]
#
# Examples:
#   migrate-fleet-pane-ids.sh                    # Uses $PWD/sessions
#   migrate-fleet-pane-ids.sh ~/project/sessions # Explicit path

#
# Rename mode (rename a live seat and rebind its sessions in one step):
#   migrate-fleet-pane-ids.sh --rename <old-label> <new-label> [--window W] [--session S]
#       [--roots DIR...] [--max-age-days N] [--live [--socket SOCK] [--pane %ID]] [--apply]
#
#   Rebinds every .state.json whose fleetPaneId is <session>:<window>:<old-label> to
#   <session>:<window>:<new-label>. The legacy mode above skips any id containing ':'
#   (it only scopes bare ids), so it cannot rename a seat; this mode exists for that.
#
#   --window W        only ids in window W (and, with --live, only panes in window W)
#   --session S       only ids / panes in tmux session S
#   --roots DIR...    session roots to scan (default: $PWD/sessions). Roots are deduped
#                     by realpath, so a symlinked root is not processed twice.
#   --max-age-days N  only session dirs modified within N days, the window run.sh resumes
#                     from (default ${FLEET_RESUME_MAX_AGE_DAYS:-7}). 0 takes every age.
#                     An older binding is reported as STALE and left alone.
#   --live            also rename the pane's @pane_label and every pane option naming it:
#                     @pane_manager == old, @pane_parent == W:old, an @pane_manages
#                     element == old. Requires --window. Uses set-option -p only, which
#                     never moves focus and restarts nothing.
#                     A RESTART IS STILL REQUIRED: run.sh reads FLEET_PANE and FLEET_MANAGES
#                     once, at its start, and exports them to every claude it launches,
#                     restarts included. Until run.sh is restarted in the renamed pane AND
#                     in its manager's pane, the seat still calls itself <window>:<old> and
#                     the manager still awaits <old>. The tool moves the tmux options and the
#                     sessions; it cannot reach a running process's environment.
#                     The dry run also lists (DANGLING) every @pane_manages element that
#                     names no live pane's label, @pane_fleet_id or title. It changes none.
#   --socket SOCK     tmux socket for --live (default: the socket in $TMUX, else "fleet")
#   --pane %ID        with --live, the one pane to rename when the label is duplicated
#   --apply           write. Without it the run is a dry run and changes nothing.
#   --force           allow rebinding sessions when no live pane will carry the new label
#
#   Refuses (exit 2, nothing written) on: old == new, a ':' or ',' in a label, an id
#   <..>:<new> already bound inside the age window, a live pane already carrying the new
#   label, or a duplicated live label with no --pane. Every write is read back. A failure
#   during --apply rolls back everything this run changed and prints the summary (exit 1).
#
# Idle check (run before a rename; it can fail):
#   migrate-fleet-pane-ids.sh --idle-check <%pane> [--socket SOCK]
#
#   IDLE (exit 0) only when ALL hold:
#     - the pane runs an agent (a `claude` process under the pane);
#     - that agent has no live child process (a running Bash tool, a background shell or a
#       test run is a child). Not counted: caffeinate (its keep-awake helper), a defunct
#       (state Z) zombie, and a long-lived `claude daemon` child — all present at idle;
#     - the screen shows the input box: a line starting with ❯ right under one rule (─)
#       and, after any further draft lines, a closing rule. A multi-line draft is fine; an
#       open question's menu (❯ with no rules around it) is not a box;
#     - the box does not read "Press up to edit queued messages" (a turn is running and the
#       operator's messages wait behind it);
#     - nothing above the box shows a running turn: an active spinner — a glyph, a
#       capitalised verb, "…", then " (" as in "✶ Deliberating… (3m 33s · ↓ 11.9k tokens)"
#       or "✢ Reticulating… (running Stop hooks… 1/2 · 3s)" — or "esc to interrupt". A
#       finished turn reads "✻ Crunched for 49s · done", with no ellipsis, and is idle;
#     - the footer below the box shows no "N shells" / "background task" count and no
#       running-subagent row (◯). Its "N agents" count includes finished agents, so it is
#       printed as a NOTE and does not make the seat BUSY.
#   Otherwise BUSY (exit 1), one line per reason, every reason printed. A missing pane is
#   exit 2. The check is read-only (display-message, capture-pane, ps).

set -euo pipefail

# ---------------------------------------------------------------------------------------
# Idle check
# ---------------------------------------------------------------------------------------
idle_check_main() {
  local pane="" socket="" busy=0 pane_pid agent kids screen m
  shift  # --idle-check
  pane="${1:-}"
  if [ -z "$pane" ] || [[ "$pane" == --* ]]; then echo "ERROR: --idle-check needs <%pane>" >&2; return 2; fi
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --socket) socket="${2:?--socket needs a value}"; shift 2 ;;
      *) echo "ERROR: unknown argument: $1" >&2; return 2 ;;
    esac
  done
  if [ -z "$socket" ]; then
    if [ -n "${TMUX:-}" ]; then socket=$(basename "${TMUX%%,*}"); else socket="fleet"; fi
  fi
  pane_pid=$(tmux -L "$socket" display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null) || pane_pid=""
  if [ -z "$pane_pid" ]; then echo "ERROR: no pane $pane on tmux socket '$socket'" >&2; return 2; fi

  # The agent: the first `claude` process found walking down from the pane's shell
  local procs
  procs=$(ps -A -o pid=,ppid=,stat=,command=)
  agent=$(printf '%s\n' "$procs" | awk -v root="$pane_pid" '
    { pid=$1; pp=$2; $1=""; $2=""; $3=""; sub(/^ +/, ""); cmd[pid]=$0; kids[pp]=kids[pp] " " pid }
    END { q[1]=root; h=1; t=1
          while (h <= t) { p=q[h++]
            if (cmd[p] ~ /(^|[ \/])claude( |$)/) { print p; exit }
            n=split(kids[p], a, " "); for (i=1; i<=n; i++) q[++t]=a[i] } }')
  echo "IDLE-CHECK $pane (socket $socket, pane pid $pane_pid, agent pid ${agent:-none})"
  if [ -z "$agent" ]; then
    echo "BUSY: no agent (claude) process under the pane; nothing to judge idle"; busy=1
  else
    # Not work: caffeinate (keep-awake), a zombie (state Z, already exited), `claude daemon`
    kids=$(printf '%s\n' "$procs" | awk -v a="$agent" '$2 == a {
      pid=$1; st=$3; $1=""; $2=""; $3=""; sub(/^ +/, ""); split($0, w, " "); n=split(w[1], b, "/")
      if (st ~ /^Z/) { print "SKIP " pid " zombie " substr($0, 1, 40); next }
      if (b[n] == "caffeinate") next
      if ($0 ~ /(^|[ \/])claude daemon( |$)/) { print "SKIP " pid " daemon " substr($0, 1, 60); next }
      print "KID " pid " " substr($0, 1, 80) }')
    while IFS= read -r m; do
      case "$m" in
        KID\ *)  echo "BUSY: agent child process: ${m#KID }"; busy=1 ;;
        SKIP\ *) echo "NOTE: not counted as work: ${m#SKIP }" ;;
      esac
    done <<< "$kids"
  fi
  # The screen. The input box is the LAST stretch that opens with a rule (─), whose next
  # line starts with ❯, and that closes at the next rule; a ❯ elsewhere is a menu cursor or
  # a queued message shown above the box. Above the box: the spinner of a running turn, read
  # over the WHOLE region (a todo list or queued messages push it far up). Inside the box:
  # "Press up to edit queued messages". Below the box (or, with no box, below the last rule):
  # the footer's background counts and running-subagent rows. Conversation text is indented
  # and never matches the column-0 spinner, so "ran 5 shell commands" is not read as work.
  screen=$(tmux -L "$socket" capture-pane -p -t "$pane" 2>/dev/null || true)
  while IFS= read -r m; do
    case "$m" in
      NOPROMPT) echo "BUSY: the input box (❯ between two rules) is not visible"; busy=1 ;;
      TURN\ *)  echo "BUSY: a turn is running: ${m#TURN }"; busy=1 ;;
      QUEUED)   echo "BUSY: the input box reads \"Press up to edit queued messages\" (a turn is running)"; busy=1 ;;
      BG\ *)    echo "BUSY: background work in the footer: ${m#BG }"; busy=1 ;;
      AGENT\ *) echo "BUSY: a subagent is running (footer row: ${m#AGENT })"; busy=1 ;;
      COUNT\ *) echo "NOTE: the footer counts ${m#COUNT }; finished agents count too, so only a running row (◯) is BUSY" ;;
    esac
  done < <(printf '%s\n' "$screen" | awk '
    { l[NR] = $0 }
    END {
      a = 0; b = 0; prev = 0; last = 0
      for (i = 1; i <= NR; i++) if (l[i] ~ /^─/) {
        if (prev && i > prev + 1 && l[prev + 1] ~ /^❯/) { a = prev; b = i }
        prev = i; last = i }
      if (!a) print "NOPROMPT"
      top = a ? a - 1 : NR
      for (i = 1; i <= top; i++)
        if (l[i] ~ /^[^ ]+ [A-Z][A-Za-z-]+… \(/ || l[i] ~ /esc to interrupt/) { print "TURN " substr(l[i], 1, 70); break }
      for (i = a + 1; a && i < b; i++) if (l[i] ~ /Press up to edit queued messages/) { print "QUEUED"; break }
      from = a ? b + 1 : (last ? last + 1 : NR + 1)
      for (i = from; i <= NR; i++) { s = l[i]
        if (s ~ /^ *◯ /) { sub(/^ *◯ +/, "", s); print "AGENT " substr(s, 1, 60); continue }
        if (match(s, /[0-9]+ agents?/)) print "COUNT " substr(s, RSTART, RLENGTH)
        while (match(s, /[0-9]+ (shells?|background tasks?)/)) {
          print "BG " substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) } }
    }')
  if [ "$busy" = 1 ]; then echo "=> BUSY"; return 1; fi
  echo "=> IDLE"
  return 0
}

if [ "${1:-}" = "--idle-check" ]; then
  idle_check_main "$@"
  exit $?
fi

# ---------------------------------------------------------------------------------------
# Rename mode
# ---------------------------------------------------------------------------------------
rename_main() {
  local old="" new="" window="" tsess="" apply=0 live=0 socket="" pane="" force=0
  local max_age="${FLEET_RESUME_MAX_AGE_DAYS:-7}"
  local roots=()

  shift  # --rename
  old="${1:-}"; new="${2:-}"
  if [ -z "$old" ] || [ -z "$new" ] || [[ "$old" == --* ]] || [[ "$new" == --* ]]; then
    echo "ERROR: --rename needs <old-label> <new-label>" >&2; return 2
  fi
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --window)       window="${2:?--window needs a value}"; shift 2 ;;
      --session)      tsess="${2:?--session needs a value}"; shift 2 ;;
      --max-age-days) max_age="${2:?--max-age-days needs a value}"; shift 2 ;;
      --socket)       socket="${2:?--socket needs a value}"; shift 2 ;;
      --pane)         pane="${2:?--pane needs a value}"; shift 2 ;;
      --live)         live=1; shift ;;
      --apply)        apply=1; shift ;;
      --force)        force=1; shift ;;
      --roots)
        shift
        while [ $# -gt 0 ] && [[ "$1" != --* ]]; do roots+=("$1"); shift; done ;;
      *) echo "ERROR: unknown argument: $1" >&2; return 2 ;;
    esac
  done

  if [ "$old" = "$new" ]; then echo "ERROR: old and new label are the same: $old" >&2; return 2; fi
  if [[ "$new" == *:* || "$new" == *,* || "$old" == *:* || "$old" == *,* ]]; then
    echo "ERROR: a label may not contain ':' or ',' (it is a segment of fleetPaneId and an element of @pane_manages)" >&2
    return 2
  fi
  if ! [[ "$max_age" =~ ^[0-9]+$ ]]; then echo "ERROR: --max-age-days must be a whole number" >&2; return 2; fi
  if [ "$live" = 1 ] && [ -z "$window" ]; then echo "ERROR: --live requires --window" >&2; return 2; fi
  [ ${#roots[@]} -eq 0 ] && roots=("$PWD/sessions")

  local mode="DRY RUN"; [ "$apply" = 1 ] && mode="APPLY"
  echo "[$mode] rename label '$old' -> '$new'${window:+ in window '$window'}${tsess:+ of session '$tsess'}"

  # Dedupe roots by realpath (a symlinked root is the same files)
  local real_roots=() r rp s seen
  for r in "${roots[@]}"; do
    if [ ! -d "$r" ]; then echo "WARN: root not found, skipped: $r" >&2; continue; fi
    rp=$(cd -P "$r" && pwd)
    seen=0
    for s in ${real_roots[@]+"${real_roots[@]}"}; do [ "$s" = "$rp" ] && seen=1; done
    if [ "$seen" = 1 ]; then echo "NOTE: root $r is $rp, already scanned"; continue; fi
    real_roots+=("$rp")
  done

  # id_parts <id> -> sets _s _w _l (session, window, label); a 2-part id has no window
  id_parts() {
    local id="$1" rest
    _l="${id##*:}"; rest="${id%:*}"
    if [[ "$rest" == *:* ]]; then _w="${rest##*:}"; _s="${rest%:*}"; else _w=""; _s="$rest"; fi
  }
  in_window() {  # <session dir> -> 0 when inside the age window
    [ "$max_age" = 0 ] && return 0
    [ -n "$(find "$1" -maxdepth 0 -mtime "-$max_age" 2>/dev/null)" ]
  }

  # Pass 1: plan the session rebinds (writes nothing)
  local targets=() f id d stale=0 lower_old lower_l seen_files=""
  lower_old=$(printf '%s' "$old" | tr '[:upper:]' '[:lower:]')
  for rp in ${real_roots[@]+"${real_roots[@]}"}; do
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      # One file, one visit: a session DIR can be symlinked from another root (finch ->
      # kit), so dedupe on the real path and judge its age on the real dir, not the link.
      d=$(cd -P "$(dirname "$f")" 2>/dev/null && pwd) || continue
      f="$d/.state.json"
      case $'\n'"$seen_files"$'\n' in *$'\n'"$f"$'\n'*) continue ;; esac
      seen_files="$seen_files"$'\n'"$f"
      id=$(jq -r '.fleetPaneId // ""' "$f" 2>/dev/null || echo "")
      [ -n "$id" ] || continue
      [[ "$id" == *:* ]] || continue   # a bare id is the legacy mode's business
      id_parts "$id"
      if [ -n "$window" ] && [ "$_w" != "$window" ]; then continue; fi
      if [ -n "$tsess" ] && [ "$_s" != "$tsess" ]; then continue; fi
      if [ "$_l" = "$new" ] && in_window "$d"; then
        echo "REFUSE: $id is already bound by $d; renaming onto it would give one pane two sessions. Nothing written." >&2
        return 2
      fi
      if [ "$_l" != "$old" ]; then
        lower_l=$(printf '%s' "$_l" | tr '[:upper:]' '[:lower:]')
        if [ "$lower_l" = "$lower_old" ] && [ "$_l" != "$new" ]; then
          echo "CASE-VARIANT (not matched): $d -> $id"
        fi
        continue
      fi
      if ! in_window "$d"; then
        echo "STALE (outside ${max_age}d resume window, left alone): $d -> $id"
        stale=$((stale + 1))
        continue
      fi
      targets+=("$f")
    done < <(find -L "$rp" -name ".state.json" -type f 2>/dev/null)
  done

  # Pass 2: plan the live pane options (writes nothing)
  local tm=() label_pane="" opt_plan=() rows p_id p_sess p_win p_label matches=() clash="" m
  if [ "$live" = 1 ]; then
    if [ -z "$socket" ]; then
      if [ -n "${TMUX:-}" ]; then socket=$(basename "${TMUX%%,*}"); else socket="fleet"; fi
    fi
    tm=(tmux -L "$socket")
    rows=$("${tm[@]}" list-panes -a -F '#{pane_id}	#{session_name}	#{window_name}	#{@pane_label}' 2>/dev/null) || {
      echo "ERROR: cannot list panes on tmux socket '$socket'" >&2; return 2; }
    while IFS=$'\t' read -r p_id p_sess p_win p_label; do
      [ -n "$p_id" ] || continue
      if [ -n "$tsess" ] && [ "$p_sess" != "$tsess" ]; then continue; fi
      [ "$p_label" = "$new" ] && clash="$clash $p_id($p_win)"
      if [ "$p_win" = "$window" ] && [ "$p_label" = "$old" ]; then matches+=("$p_id"); fi
    done <<< "$rows"
    if [ -n "$clash" ]; then
      echo "REFUSE: label '$new' is already carried by pane(s):$clash; fleet.sh resolves @pane_manager by label alone. Nothing written." >&2
      return 2
    fi
    if [ -n "$pane" ]; then
      local ok=0
      for m in ${matches[@]+"${matches[@]}"}; do [ "$m" = "$pane" ] && ok=1; done
      if [ "$ok" = 0 ]; then echo "REFUSE: pane $pane is not labelled '$old' in window '$window'" >&2; return 2; fi
      label_pane="$pane"
    elif [ ${#matches[@]} -eq 1 ]; then
      label_pane="${matches[0]}"
    elif [ ${#matches[@]} -eq 0 ]; then
      echo "NOTE: no live pane labelled '$old' in window '$window'; no label to rename"
    else
      echo "REFUSE: ${#matches[@]} panes carry '$old' in window '$window' (${matches[*]}); pick one with --pane" >&2
      return 2
    fi
    # NIT-4: name every @pane_manages element that matches no live pane (report only)
    local US=$'\x1f' known="" dang_rows k_p k_s k_l k_f k_t k_m
    dang_rows=$("${tm[@]}" list-panes -a -F "#{pane_id}${US}#{session_name}${US}#{@pane_label}${US}#{@pane_fleet_id}${US}#{pane_title}${US}#{@pane_manages}" 2>/dev/null || true)
    while IFS="$US" read -r k_p k_s k_l k_f k_t k_m; do
      [ -n "$k_p" ] || continue
      if [ -n "$tsess" ] && [ "$k_s" != "$tsess" ]; then continue; fi
      # a live title carries a status glyph ("✳ domain:handbook"): compare without it too
      known="$known"$'\n'"$k_l"$'\n'"$k_f"$'\n'"$k_t"$'\n'"${k_t#* }"
    done <<< "$dang_rows"
    while IFS="$US" read -r k_p k_s k_l k_f k_t k_m; do
      [ -n "$k_p" ] && [ -n "$k_m" ] || continue
      if [ -n "$tsess" ] && [ "$k_s" != "$tsess" ]; then continue; fi
      while IFS= read -r m; do
        [ -n "$m" ] || continue
        case $'\n'"$known"$'\n' in *$'\n'"$m"$'\n'*) continue ;; esac
        echo "DANGLING: $k_p @pane_manages element '$m' matches no live pane label, fleet id or title (left alone)"
      done < <(printf '%s\n' "$k_m" | tr ',' '\n')
    done <<< "$dang_rows"
    if [ -n "$label_pane" ]; then
      opt_plan+=("$label_pane	@pane_label	$old	$new")
      # References only move when no other pane keeps the old label; otherwise they are ambiguous
      local others=$(( ${#matches[@]} - 1 ))
      if [ "$others" -gt 0 ]; then
        echo "NOTE: $others other pane(s) keep '$old'; references to it are ambiguous and left alone"
      else
        local v nv o changed
        while IFS=$'\t' read -r p_id p_sess p_win p_label; do
          [ -n "$p_id" ] || continue
          if [ -n "$tsess" ] && [ "$p_sess" != "$tsess" ]; then continue; fi
          v=$("${tm[@]}" show-options -p -v -t "$p_id" @pane_manager 2>/dev/null || true)
          if [ "$v" = "$old" ]; then opt_plan+=("$p_id	@pane_manager	$v	$new"); fi
          v=$("${tm[@]}" show-options -p -v -t "$p_id" @pane_parent 2>/dev/null || true)
          if [ "$v" = "$window:$old" ]; then opt_plan+=("$p_id	@pane_parent	$v	$window:$new"); fi
          v=$("${tm[@]}" show-options -p -v -t "$p_id" @pane_manages 2>/dev/null || true)
          if [ -n "$v" ]; then
            nv=""; changed=0
            while IFS= read -r o; do
              if [ "$o" = "$old" ]; then o="$new"; changed=1; fi
              nv="${nv:+$nv,}$o"
            done < <(printf '%s\n' "$v" | tr ',' '\n')
            if [ "$changed" = 1 ]; then opt_plan+=("$p_id	@pane_manages	$v	$nv"); fi
          fi
        done <<< "$rows"
      fi
    fi
  fi

  # S3: a session rebound onto a label no live pane carries is orphaned, not renamed
  if [ ${#targets[@]} -gt 0 ] && [ -z "$label_pane" ] && [ "$force" = 0 ]; then
    echo "REFUSE: ${#targets[@]} in-window session(s) would be rebound to '<..>:$new', but no live pane will carry '$new'" \
         "(no --live, or no pane labelled '$old' in window '$window'). Use --live with the right --window, or --force. Nothing written." >&2
    return 2
  fi

  # Report the plan
  local t new_id row row_p row_o row_v row_n
  if [ "$apply" = 0 ]; then
    for t in ${targets[@]+"${targets[@]}"}; do
      id=$(jq -r '.fleetPaneId' "$t"); new_id="${id%:*}:$new"
      echo "WOULD REBIND: $(dirname "$t") : $id -> $new_id"
    done
    for row in ${opt_plan[@]+"${opt_plan[@]}"}; do
      IFS=$'\t' read -r row_p row_o row_v row_n <<< "$row"
      echo "WOULD SET: $row_p $row_o '$row_v' -> '$row_n'"
    done
    echo ""
    echo "Dry run: would rebind ${#targets[@]} session(s), set ${#opt_plan[@]} pane option(s); stale left: $stale"
    echo "Rebound: 0"
    return 0
  fi

  # Apply. Order: live options first (the step most likely to fail: a pane can close), then
  # sessions. Any failure rolls back what this run already changed, and the summary is
  # always printed, so a run never stops half-applied and silent.
  local ts rebound=0 errs=0 tmpf got applied_opts=() rewritten=()
  ts=$(date +%Y%m%dT%H%M%S)
  summary() {
    echo ""
    echo "Rebound: $rebound"
    echo "Pane options set: ${#applied_opts[@]}"
    echo "Stale left: $stale"
    echo "Errors: $errs"
  }
  rollback() {
    local rr rp ro rv rn
    for rr in ${rewritten[@]+"${rewritten[@]}"}; do
      cp -p "$rr.bak-rename-$ts" "$rr" && echo "ROLLED BACK: $rr" >&2
    done
    for rr in ${applied_opts[@]+"${applied_opts[@]}"}; do
      IFS=$'\t' read -r rp ro rv rn <<< "$rr"
      "${tm[@]}" set-option -p -t "$rp" "$ro" "$rv" 2>/dev/null && echo "ROLLED BACK: $rp $ro -> '$rv'" >&2
    done
    rebound=0; applied_opts=()
  }

  for row in ${opt_plan[@]+"${opt_plan[@]}"}; do
    IFS=$'\t' read -r row_p row_o row_v row_n <<< "$row"
    if ! "${tm[@]}" set-option -p -t "$row_p" "$row_o" "$row_n" 2>/dev/null; then
      echo "ERROR: set-option failed on $row_p $row_o" >&2; errs=$((errs + 1)); break
    fi
    applied_opts+=("$row")
    got=$("${tm[@]}" show-options -p -v -t "$row_p" "$row_o" 2>/dev/null || true)
    if [ "$got" = "$row_n" ]; then
      if [ "$row_o" = "@pane_label" ]; then
        echo "LABEL (read back): $row_p '$row_v' -> '$got'"
      else
        echo "OPTION (read back): $row_p $row_o '$row_v' -> '$got'"
      fi
    else
      echo "ERROR: $row_p $row_o read back '$got', expected '$row_n'" >&2; errs=$((errs + 1)); break
    fi
  done
  if [ "$errs" -gt 0 ]; then rollback; summary; return 1; fi

  # The live options are applied by now, so under set -e every command below is guarded:
  # an unguarded failure would kill the run with the label moved, no rollback, no summary.
  for t in ${targets[@]+"${targets[@]}"}; do
    if ! id=$(jq -r '.fleetPaneId' "$t" 2>/dev/null) || [ -z "$id" ]; then
      echo "ERROR: cannot read fleetPaneId from $t" >&2; errs=$((errs + 1)); break
    fi
    new_id="${id%:*}:$new"
    # Defence in depth: the real-path dedupe in pass 1 means one run never visits a file
    # twice, so within a run this guard cannot fire. It catches a second run inside the same
    # second, and it keeps a future change to the dedupe from overwriting a backup that
    # holds the original id. test_existing_backup_is_never_overwritten reaches it by pinning
    # the timestamp with a fake `date`.
    if [ -e "$t.bak-rename-$ts" ]; then
      echo "ERROR: backup $t.bak-rename-$ts already exists; refusing to overwrite it" >&2
      errs=$((errs + 1)); break
    fi
    if ! cp -p "$t" "$t.bak-rename-$ts"; then
      echo "ERROR: cannot back up $t; nothing rewritten for it" >&2; errs=$((errs + 1)); break
    fi
    tmpf="$t.tmp.$$"
    if jq --arg id "$new_id" '.fleetPaneId = $id' "$t" > "$tmpf" && mv "$tmpf" "$t"; then
      rewritten+=("$t")
      got=$(jq -r '.fleetPaneId' "$t" 2>/dev/null) || got=""
      if [ "$got" = "$new_id" ]; then
        echo "REBOUND (read back): $(dirname "$t") : $id -> $got"
        rebound=$((rebound + 1))
      else
        echo "ERROR: read back $got, expected $new_id" >&2; errs=$((errs + 1)); break
      fi
    else
      rm -f "$tmpf"; echo "ERROR: failed to rewrite $t" >&2; errs=$((errs + 1)); break
    fi
  done
  if [ "$errs" -gt 0 ]; then rollback; summary; return 1; fi

  summary
}

if [ "${1:-}" = "--rename" ]; then
  rename_main "$@"
  exit $?
fi


SESSIONS_DIR="${1:-$PWD/sessions}"
DEFAULT_PREFIX="fleet"  # Default tmux session name for fleet

if [ ! -d "$SESSIONS_DIR" ]; then
  echo "ERROR: Sessions directory not found: $SESSIONS_DIR" >&2
  exit 1
fi

echo "Migrating fleetPaneId in: $SESSIONS_DIR"
echo "New format: {tmux_session}:{pane_label} (e.g., fleet:MCP)"
echo ""

migrated=0
skipped=0
errors=0

# Find all .state.json files
while IFS= read -r agent_file; do
  [ -f "$agent_file" ] || continue

  # Get current fleetPaneId
  fleet_pane_id=$(jq -r '.fleetPaneId // ""' "$agent_file" 2>/dev/null || echo "")

  if [ -z "$fleet_pane_id" ]; then
    # No fleetPaneId, skip
    continue
  fi

  if [[ "$fleet_pane_id" == *":"* ]]; then
    # Already scoped, skip
    echo "SKIP (already scoped): $agent_file -> $fleet_pane_id"
    ((skipped++))
    continue
  fi

  # Needs migration — create backup first
  backup_file="${agent_file}.bak"
  cp "$agent_file" "$backup_file"

  # Update to scoped format
  new_fleet_pane_id="${DEFAULT_PREFIX}:${fleet_pane_id}"

  if jq --arg new_id "$new_fleet_pane_id" '.fleetPaneId = $new_id' "$agent_file" > "$agent_file.tmp"; then
    mv "$agent_file.tmp" "$agent_file"
    echo "MIGRATED: $agent_file"
    echo "  Old: $fleet_pane_id"
    echo "  New: $new_fleet_pane_id"
    ((migrated++))
  else
    echo "ERROR: Failed to migrate $agent_file" >&2
    # Restore from backup
    mv "$backup_file" "$agent_file"
    ((errors++))
  fi

done < <(find -L "$SESSIONS_DIR" -name ".state.json" -type f 2>/dev/null)

echo ""
echo "Migration complete:"
echo "  Migrated: $migrated"
echo "  Skipped (already scoped): $skipped"
echo "  Errors: $errors"

if [ $errors -gt 0 ]; then
  exit 1
fi
