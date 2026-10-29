#!/bin/bash
# worktree.sh — the worktree disposal ceremony. See ¶CMD_DISPOSE_WORKTREE.
#
# Reached as `engine worktree` through engine.sh's generic subcommand fallback.
#
# The install is reinstallable; the tree may hold uncommitted work. So dropping
# the install is the default offer and the only reversible one, and anything that
# removes a tree is opt-in, refuses dirty/untracked content, and goes through
# `git worktree remove` rather than rm -rf.

set -uo pipefail

PROG="engine worktree"

# ── small helpers ───────────────────────────────────────────────────────────

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
note() { printf '%s\n' "$*"; }

# Refusal: a guard fired. Exit 2 so a caller can tell it from a clean no-op.
refuse() { printf 'REFUSED: %s\n' "$*" >&2; REFUSALS=$((REFUSALS + 1)); }

have_timeout() { command -v timeout >/dev/null 2>&1; }

# du -sk under a time bound; prints KiB, or nothing when it could not finish.
bounded_du_k() {
  local p="$1" secs="${2:-120}" out
  if have_timeout; then
    out=$(timeout "$secs" du -sk "$p" 2>/dev/null)
  else
    out=$(du -sk "$p" 2>/dev/null)
  fi
  printf '%s\n' "$out" | awk 'NR==1{print $1}'
}

# Absolute, symlink-resolved for a directory that exists; absolute-only otherwise.
# /tmp/x resolves to /private/tmp/x, which is the spelling git registered.
abspath() {
  local p="$1"
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  if [ -d "$p" ]; then (cd "$p" 2>/dev/null && pwd -P) || printf '%s\n' "$p"
  else printf '%s\n' "$p"; fi
}

# ── the repository ──────────────────────────────────────────────────────────

REPO=""
resolve_repo() {
  if [ -n "$REPO" ]; then
    REPO=$(abspath "$REPO")
    git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 \
      || die "not a git repository: $REPO"
  else
    REPO=$(git rev-parse --show-toplevel 2>/dev/null)
    [ -n "$REPO" ] || die "not inside a git repository — pass --repo <path>"
  fi
}

porcelain() { git -C "$REPO" worktree list --porcelain 2>/dev/null; }

# Every registered path, one per line. substr, not $2 — a path may hold spaces.
registered_paths() { porcelain | awk '/^worktree /{print substr($0, 10)}'; }

# ⭐ The registration check. Grep the PORCELAIN spelling, whole line, fixed
# string: the human form column-aligns and appends "[branch] locked", and a
# loose match would also hit a path that merely PREFIXES a registered one.
#
# ⛔ The answer is CAPTURED and tested for emptiness, never read out of the
# pipeline's status. `grep -q` exits on its first match; once the listing is
# larger than the pipe buffer git is still writing, takes SIGPIPE, dies 141, and
# `pipefail` hands that 141 back as the check's answer — so an early match reads
# as "not registered" while a late one works. Measured: the -q shape returns 141
# above ~64 KB of listing and 0 below it.
is_registered() {
  local p="$1" hit
  hit=$(porcelain | grep -xF "worktree $p")
  [ -n "$hit" ]
}

# The attribute lines of one path's stanza (branch / locked / prunable / …).
# awk reads to EOF rather than exiting at the stanza end, for the same reason.
wt_attrs() {
  local p="$1"
  porcelain | awk -v t="worktree $p" '
    $0 == t { inside = 1; next }
    inside && /^[[:space:]]*$/ { inside = 0; next }
    inside { print }
  '
}

# Same shape, and here a false negative would let remove-tree through on a
# locked tree — this one fails OPEN if read from a pipeline status.
is_locked() {
  local hit
  hit=$(wt_attrs "$1" | grep '^locked')
  [ -n "$hit" ]
}

# The main worktree's .git is a DIRECTORY; a linked worktree's is a FILE.
is_main_worktree() { [ -d "$1/.git" ]; }

# healthy | dangling | broken
health_of() {
  local p="$1"
  if [ ! -d "$p" ];       then printf 'dangling\n'
  elif [ -e "$p/.git" ];  then printf 'healthy\n'
  else                         printf 'broken\n'; fi
}

# Any registered directory present on disk whose .git file is gone.
broken_paths() {
  local p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ "$(health_of "$p")" = "broken" ] && printf '%s\n' "$p"
  done < <(registered_paths)
}

# real | skeleton | farm | trivial — for an existing node_modules directory.
#
# Classifying first is load-bearing: a COUNT of node_modules overstates what is
# reclaimable, because a skeleton (directories, no files) and a symlink farm both
# look like fat installs by entry count and free nothing.
install_class() {
  local nm="$1" ent lk
  ent=$(find "$nm" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
  lk=$(find "$nm" -maxdepth 1 -mindepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
  ent=${ent:-0}; lk=${lk:-0}
  if [ "$ent" -lt 10 ]; then printf 'trivial\n'; return; fi
  if [ $((lk * 2)) -gt "$ent" ]; then printf 'farm\n'; return; fi
  if [ -n "$(find "$nm" -type f -print -quit 2>/dev/null)" ]; then
    printf 'real\n'
  else
    printf 'skeleton\n'
  fi
}

# ── census ──────────────────────────────────────────────────────────────────

cmd_census() {
  local sample_stride="${SAMPLE_STRIDE:-30}" measure_all="${MEASURE_ALL:-0}"
  local p total=0 healthy=0 dangling=0 broken=0
  local locked prunable
  local real=0 skeleton=0 farm=0 trivial=0 installs=0
  local -a real_list=()

  note "Repo: $REPO"

  while IFS= read -r p; do
    [ -z "$p" ] && continue
    total=$((total + 1))
    case "$(health_of "$p")" in
      healthy)  healthy=$((healthy + 1)) ;;
      dangling) dangling=$((dangling + 1)) ;;
      broken)   broken=$((broken + 1)) ;;
    esac
    if [ -d "$p/node_modules" ] && [ ! -L "$p/node_modules" ]; then
      installs=$((installs + 1))
      case "$(install_class "$p/node_modules")" in
        real)     real=$((real + 1)); real_list+=("$p/node_modules") ;;
        skeleton) skeleton=$((skeleton + 1)) ;;
        farm)     farm=$((farm + 1)) ;;
        trivial)  trivial=$((trivial + 1)) ;;
      esac
    fi
  done < <(registered_paths)

  # grep -c PRINTS 0 and EXITS 1 on no match — `|| true` or the next test errors.
  locked=$(porcelain | grep -c '^locked' || true)
  prunable=$(porcelain | grep -c '^prunable' || true)

  note ""
  note "Registrations: $total"
  printf '  %-9s %5d\n' healthy "$healthy"
  printf '  %-9s %5d  %s\n' dangling "$dangling" "registered path absent from disk"
  printf '  %-9s %5d  %s\n' broken "$broken" "directory present, .git file gone — REPAIR, never prune"
  printf '  %-9s %5d  %s\n' locked "$locked" "a lock suppresses prunable; it is not a guard"
  printf '  %-9s %5d  %s\n' prunable "$prunable" "git's own count — it cannot tell dangling from broken"

  note ""
  note "Installs (top-level node_modules under a registered worktree): $installs"
  printf '  %-12s %5d  %s\n' real "$real" "holds files — this is the reclaimable class"
  printf '  %-12s %5d  %s\n' skeleton "$skeleton" "directories only, zero files — du reports 0, frees nothing"
  printf '  %-12s %5d  %s\n' symlink-farm "$farm" "majority of entries are symlinks — frees nothing"
  printf '  %-12s %5d  %s\n' trivial "$trivial" "fewer than 10 entries"

  note ""
  if [ "$real" -eq 0 ]; then
    note "Reclaimable install bytes: 0 (no install holds files)"
    note "Nothing to drop. The trees themselves are not census's business."
    return 0
  fi

  if [ "$measure_all" = "1" ]; then
    local sum=0 n=0 v
    for nm in ${real_list[@]+"${real_list[@]}"}; do
      v=$(bounded_du_k "$nm" 180)
      [ -z "$v" ] && continue
      sum=$((sum + v)); n=$((n + 1))
    done
    printf 'Reclaimable install bytes: %s GiB\n' "$(awk -v k="$sum" 'BEGIN{printf "%.0f", k/1048576}')"
    note "  MEASURED over $n of $real real installs with du -sk."
    return 0
  fi

  # Deterministic stride sample inside the real class — reproducible, and it
  # never walks 300+ trees. du over this population is slow; each call is bounded.
  local -a samples=()
  local i=0 v
  for nm in ${real_list[@]+"${real_list[@]}"}; do
    i=$((i + 1))
    [ $(( (i - 1) % sample_stride )) -eq 0 ] || continue
    v=$(bounded_du_k "$nm" 120)
    [ -n "$v" ] && samples+=("$v")
  done

  if [ "${#samples[@]}" -eq 0 ]; then
    note "Reclaimable install bytes: UNKNOWN — every sampled du exceeded its time bound."
    return 0
  fi

  local median
  median=$(printf '%s\n' ${samples[@]+"${samples[@]}"} | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}')
  printf 'Reclaimable install bytes: ~%s GiB\n' \
    "$(awk -v m="$median" -v n="$real" 'BEGIN{printf "%.0f", m*n/1048576}')"
  printf '  EXTRAPOLATED from %d of %d real installs sampled with du -sk (median %s MiB).\n' \
    "${#samples[@]}" "$real" "$(awk -v m="$median" 'BEGIN{printf "%.0f", m/1024}')"
  note "  This is not a measurement of $real. Pass --measure-all for the exact figure (slow)."
  offer_safe_disposal
}

# The safe disposal, named as a command the reader can run. The install is
# reinstallable; the tree may hold uncommitted work — so this is the only
# disposal census offers, and it offers it as a dry run.
offer_safe_disposal() {
  note ""
  note "The safe disposal is the install, not the tree (see ¶CMD_DISPOSE_WORKTREE):"
  note "  $PROG --repo '$REPO' drop-install --all              # dry run"
  note "  $PROG --repo '$REPO' drop-install --all --apply      # act"
  note "Locked worktrees are skipped — a lane may be mid-run."
}

# ── check ───────────────────────────────────────────────────────────────────

cmd_check() {
  [ "$#" -ge 1 ] || die "check needs a path"
  local raw p rc=0
  for raw in "$@"; do
    p=$(abspath "$raw")
    if is_registered "$p"; then
      printf 'REGISTERED  %-9s %s\n' "$(health_of "$p")" "$p"
      is_locked "$p" && printf '            locked: %s\n' "$(wt_attrs "$p" | sed -n 's/^locked *//p')"
    else
      printf 'not a registered worktree  %s\n' "$p"
      rc=1
    fi
  done
  return $rc
}

# ── drop-install (the default disposal, and the reversible one) ─────────────

# Every registered worktree whose install holds files. The targets of --all.
real_install_worktrees() {
  local p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    is_main_worktree "$p" && continue
    [ "$INCLUDE_LOCKED" != "1" ] && is_locked "$p" && continue
    [ -d "$p/node_modules" ] || continue
    [ -L "$p/node_modules" ] && continue
    [ "$(install_class "$p/node_modules")" = "real" ] && printf '%s\n' "$p"
  done < <(registered_paths)
}

cmd_drop_install() {
  local -a targets=()
  if [ "${ALL:-0}" = "1" ]; then
    local t
    while IFS= read -r t; do [ -n "$t" ] && targets+=("$t"); done < <(real_install_worktrees)
    [ "${#targets[@]}" -gt 0 ] || { note "No real install to drop."; return 0; }
    note "--all selected ${#targets[@]} worktree(s) whose install holds files."
    [ "${MEASURE:-0}" = "1" ] || MEASURE_EACH=0
    set -- ${targets[@]+"${targets[@]}"}
  fi
  [ "$#" -ge 1 ] || die "drop-install needs a path (or --all)"
  local raw p nm freed=0 acted=0
  for raw in "$@"; do
    p=$(abspath "$raw")
    nm="$p/node_modules"

    if ! is_registered "$p"; then
      refuse "$p is not a registered worktree (run: $PROG check '$raw')"; continue
    fi
    if is_main_worktree "$p"; then
      refuse "$p is the MAIN worktree — dropping its install breaks the live clone"; continue
    fi
    # A lock is no guard against prune, but it IS a claim on the tree: dropping
    # the install under a lane that is mid-run breaks that lane's build.
    if [ "$INCLUDE_LOCKED" != "1" ] && is_locked "$p"; then
      refuse "$p is locked ($(wt_attrs "$p" | sed -n 's/^locked *//p')) — a lane may be mid-run; pass --include-locked to override"
      continue
    fi
    if [ -L "$nm" ]; then
      refuse "$nm is a symlink — removing it could reach a shared store"; continue
    fi
    if [ ! -d "$nm" ]; then
      note "SKIP     no install at $nm"; continue
    fi

    # du over this population is slow — a per-path measurement across the whole
    # fleet would cost minutes before anything happened. So --all does not
    # measure unless asked; census already carries the sampled estimate.
    local kib=""
    if [ "$MEASURE_EACH" = "1" ]; then kib=$(bounded_du_k "$nm" 120); fi
    local size_note
    if [ -n "$kib" ]; then
      size_note=$(awk -v k="$kib" 'BEGIN{printf "%.0f MiB", k/1024}')
    else
      size_note="size unmeasured"
    fi

    if [ "$APPLY" != "1" ]; then
      printf 'would drop  %-14s %s\n' "$size_note" "$nm"
      continue
    fi
    rm -rf -- "$nm"
    if [ -d "$nm" ]; then
      refuse "failed to remove $nm"
    else
      printf 'dropped     %-14s %s\n' "$size_note" "$nm"
      acted=$((acted + 1))
      [ -n "$kib" ] && freed=$((freed + kib))
    fi
  done

  if [ "$APPLY" = "1" ]; then
    printf 'Dropped %d install(s), %s reclaimed. Reinstall with your package manager.\n' \
      "$acted" "$(awk -v k="$freed" 'BEGIN{printf "%.1f GiB", k/1048576}')"
  else
    note "Dry run. Nothing was removed. Add --apply to act."
  fi
}

# ── remove-tree (opt-in, and the destructive one) ───────────────────────────

cmd_remove_tree() {
  [ "$#" -ge 1 ] || die "remove-tree needs a path"
  local raw p status
  for raw in "$@"; do
    p=$(abspath "$raw")

    if ! is_registered "$p"; then
      refuse "$p is not a registered worktree (run: $PROG check '$raw')"; continue
    fi
    if is_main_worktree "$p"; then
      refuse "$p is the MAIN worktree, not a disposable one"; continue
    fi
    if is_locked "$p"; then
      refuse "$p is locked ($(wt_attrs "$p" | sed -n 's/^locked *//p')) — unlock deliberately first"; continue
    fi
    if [ ! -d "$p" ]; then
      refuse "$p is a dangling registration, not a tree — see '$PROG repair' then '$PROG prune'"; continue
    fi
    if [ ! -e "$p/.git" ]; then
      refuse "$p is BROKEN (its .git file is gone) — run '$PROG repair' first, never prune"; continue
    fi

    # Uncommitted OR untracked content. Ignored paths (node_modules) don't count.
    status=$(git -C "$p" status --porcelain 2>/dev/null)
    if [ -n "$status" ]; then
      refuse "$p has $(printf '%s\n' "$status" | wc -l | tr -d ' ') uncommitted or untracked path(s) — it may hold the only copy"
      continue
    fi

    case "$p" in
      /private/tmp/*|/tmp/*)
        note "NOTE     $p is under /private/tmp, where this machine runs a reaper." ;;
    esac

    if [ "$APPLY" != "1" ]; then
      printf 'would remove  %s\n' "$p"; continue
    fi
    # ⛔ git worktree remove, never rm -rf: the half that matters lives in the
    # main clone's .git/worktrees/ and rm leaves it pointing at nothing.
    if git -C "$REPO" worktree remove -- "$p" 2>&1; then
      printf 'removed       %s\n' "$p"
    else
      refuse "git worktree remove failed for $p"
    fi
  done
  [ "$APPLY" = "1" ] || note "Dry run. Nothing was removed. Add --apply to act."
}

# ── repair, then prune — the order is the whole point ───────────────────────

cmd_repair() {
  local n; n=$(broken_paths | wc -l | tr -d ' ')
  note "Broken registrations (directory present, .git file gone): ${n:-0}"
  broken_paths | sed 's/^/  /'
  if [ "$APPLY" != "1" ]; then
    note "Dry run. Add --apply to run 'git worktree repair'."
    return 0
  fi
  # repair is restorative: it rewrites pointers, never removes a registration.
  # Expect two noisy stderr lines per worktree; they are not failures.
  git -C "$REPO" worktree repair 2>&1 | sed 's/^/  /'
  note "Repaired. Re-run '$PROG census' before any prune."
}

cmd_prune() {
  local n; n=$(broken_paths | wc -l | tr -d ' ')
  n=${n:-0}
  if [ "$n" -gt 0 ]; then
    refuse "$n broken registration(s) present — prune cannot tell them from dangling ones and would DEREGISTER them, destroying the admin dir holding their HEAD and index. Run '$PROG repair --apply' first."
    broken_paths | sed 's/^/  /' >&2
    return 2
  fi
  note "No broken registrations. Prune is safe for the dangling ones."
  if [ "$APPLY" != "1" ]; then
    git -C "$REPO" worktree prune --dry-run --verbose 2>&1 | sed 's/^/  /'
    note "Dry run. Add --apply to prune."
    return 0
  fi
  git -C "$REPO" worktree prune --verbose 2>&1 | sed 's/^/  /'
}

# ── usage ───────────────────────────────────────────────────────────────────

cmd_help() {
  cat <<EOF
$PROG — the worktree disposal ceremony (see ¶CMD_DISPOSE_WORKTREE)

  census                    population by health class, install classes,
                            reclaimable install bytes   [default]
  check <path>...           is this a registered worktree? ask before removing
                            ANY directory, including one git calls untracked
  drop-install <path>...    remove the install. The safe disposal, and the only
                            reversible one — ~84% of a worktree's cost
  remove-tree <path>...     remove the tree. Opt-in. Refuses uncommitted or
                            untracked content, a locked tree, the main worktree,
                            and a broken registration; uses git worktree remove
  repair                    restore broken registrations. ALWAYS BEFORE PRUNE
  prune                     clear dangling registrations. Refuses while any
                            broken registration exists

Flags
  --apply                   act. Without it every subcommand is a dry run
  --all                     drop-install: every worktree whose install holds
                            files, skipping locked ones and the main clone
  --include-locked          drop-install: do not skip a locked worktree
  --measure                 drop-install --all: du each target (slow over this
                            population; census's sampled estimate is cheaper)
  --repo <path>             the repository (default: the one containing \$PWD)
  --measure-all             census: du every real install instead of sampling
  --sample-stride <n>       census: sample every nth real install (default 30)
EOF
}

# ── argument parsing ────────────────────────────────────────────────────────

APPLY=0
ALL=0
MEASURE=0
MEASURE_EACH=1
INCLUDE_LOCKED=0
REFUSALS=0
MEASURE_ALL=0
SAMPLE_STRIDE=30
SUB=""
ARGS=()

# engine.sh execs us with the subcommand name still in $1.
[ "${1:-}" = "worktree" ] && shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)          APPLY=1 ;;
    --all)            ALL=1 ;;
    --measure)        MEASURE=1 ;;
    --include-locked) INCLUDE_LOCKED=1 ;;
    --measure-all)    MEASURE_ALL=1 ;;
    --sample-stride)  shift; SAMPLE_STRIDE="${1:-30}" ;;
    --repo)           shift; REPO="${1:-}" ;;
    -h|--help|help)   cmd_help; exit 0 ;;
    --*)              die "unknown flag: $1" ;;
    *)
      if [ -z "$SUB" ]; then SUB="$1"; else ARGS+=("$1"); fi ;;
  esac
  shift
done

resolve_repo

case "${SUB:-census}" in
  census)        cmd_census ;;
  check)         cmd_check        ${ARGS[@]+"${ARGS[@]}"} ;;
  drop-install)  cmd_drop_install  ${ARGS[@]+"${ARGS[@]}"} ;;
  remove-tree)   cmd_remove_tree   ${ARGS[@]+"${ARGS[@]}"} ;;
  repair)        cmd_repair ;;
  prune)         cmd_prune ;;
  *)             die "unknown subcommand: $SUB (try '$PROG help')" ;;
esac
rc=$?

[ "$REFUSALS" -gt 0 ] && exit 2
exit $rc
