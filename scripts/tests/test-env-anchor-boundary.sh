#!/bin/bash
# tests/test-env-anchor-boundary.sh — where env_anchor_dir's climb must STOP.
#
# Run: bash ~/.claude/engine/scripts/tests/test-env-anchor-boundary.sh
#      ENV_ANCHOR_LIB=/path/to/a/copy/of/env-lib.sh bash tests/test-env-anchor-boundary.sh
#
# env_anchor_dir derives a project root by inverting how the session path was built:
# strip everything from the first `/sessions/` segment, then climb to a project marker.
# The climb has to satisfy three demands that pull against each other, and this file is
# one planted offender per demand:
#
#   A  A CHECKOUT WITH NO `.claude/` OF ITS OWN IS STILL A PROJECT. An unbounded climb
#      walks out of it and keeps going until it finds a `.claude` — on a real machine,
#      the one in $HOME. The project's own `.env` is then read by nothing and a HOME
#      dotfile governs it.
#   B  A BARE $PWD WITH NO `/sessions/` SEGMENT GETS NO ANCHOR AT ALL. There is no
#      structural starting point, so a loud "no anchor" beats a quiet wrong one.
#   C  A STRAY `.claude/` INSIDE `sessions/` MUST NOT CAPTURE THE CLIMB.
#
# Fixing A naively breaks B (a general $PWD walk-up) or C (dropping the climb). Each
# case below is therefore run against the shipped lib AND against the two naive
# candidate fixes, which is the only way to show the case discriminates rather than
# merely agreeing with whatever is in the file.
#
# D and E are the guards the fix must not cost: WORKSPACE nesting still climbs out of
# the workspace subdir, and $HOME is never selected as an anchor.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENVLIB="${ENV_ANCHOR_LIB:-$HOME/.claude/engine/scripts/env-lib.sh}"
[ -f "$ENVLIB" ] || { echo "no env-lib at $ENVLIB" >&2; exit 1; }
echo "lib under test: $ENVLIB"

# PHYSICAL path: macOS mktemp hands back /var/folders/... while `cd -P` resolves to
# /private/var/folders/..., and an identity assertion on an absolute path would then
# compare two spellings of the same directory.
WORK=$(cd "$(mktemp -d)" && pwd -P)
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && /bin/rm -rf "$WORK"; }
trap cleanup EXIT

export CLAUDE_SUPERVISOR_PID="$$"

# ── mkouter — an ANCESTOR that carries a `.claude` and is not a repo. ──────────
# This is the $HOME shape, planted inside the sandbox so the case does not depend on
# the operator's real home directory. Without an ancestor like this, a temp-dir
# fixture cannot reproduce the defect at all: the climb finds no marker, falls back
# to the stripped path, and passes for the wrong reason.
mkouter() {
  local d="$1"
  mkdir -p "$d/.claude"
}

# ── mkouter_home — the same ancestor, usable as a $HOME override. ─────────────
# session.sh sources $HOME/.claude/scripts/lib.sh, so a fake home needs a real engine
# behind its marker or discovery dies and the case measures nothing. A SYMLINK to the
# operator's own .claude satisfies both: `[ -d ]` is true through it (so the ancestor
# still carries a capturing marker) and the engine scripts are reachable.
mkouter_home() {
  local d="$1"
  mkdir -p "$d"
  ln -s "$HOME/.claude" "$d/.claude"
}

# ── mkcheckout — a repo-shaped checkout with an ACTIVE session. ────────────────
#   $1 dir · $2 markers: "git" | "claude" | "git+claude" | "none"
# The session is discovered through session.sh's PID cache, seeded here. That is how
# the real case resolves (the cache is keyed on the pid and owes nothing to $PWD), and
# it keeps discovery from depending on the very anchor rule under test.
mkcheckout() {
  local d="$1" markers="${2:-git}"
  mkdir -p "$d/sessions/t" "$d/.session-cache"
  case "$markers" in
    *git*) mkdir -p "$d/.git" ;;
  esac
  case "$markers" in
    *claude*) mkdir -p "$d/.claude" ;;
  esac
  printf '{"pid": %s}\n' "$CLAUDE_SUPERVISOR_PID" > "$d/sessions/t/.state.json"
  /bin/rm -f "$d/.session-cache"/* 2>/dev/null
  printf '%s\n' "$d/sessions/t" > "$d/.session-cache/claude-session-cache-$CLAUDE_SUPERVISOR_PID"
}

# anchor_of DIR CACHEDIR [SUBDIR] [WORKSPACE] [HOME_OVERRIDE]
anchor_of() {
  local root="$1" cache="$2" sub="${3:-.}" ws="${4:-}" homeover="${5:-}"
  ( cd "$root/$sub" || return 1
    export CLAUDE_SESSION_CACHE_DIR="$cache"
    [ -n "$ws" ] && export WORKSPACE="$ws"
    [ -n "$homeover" ] && export HOME="$homeover"
    source "$ENVLIB" 2>/dev/null
    env_anchor_dir 2>/dev/null )
}

# anchor_rc DIR CACHEDIR [SUBDIR] → the return code, which is the whole point of case B.
anchor_rc() {
  local root="$1" cache="$2" sub="${3:-.}"
  ( cd "$root/$sub" || return 99
    export CLAUDE_SESSION_CACHE_DIR="$cache"
    source "$ENVLIB" 2>/dev/null
    env_anchor_dir >/dev/null 2>&1; echo $? )
}

# ══ A. THE KIT CASE — a checkout with no `.claude/` of its own ═════════════════
#
# Shape: <outer with .claude>/<checkout with .git, no .claude>/sessions/t.
# The climb must stop at the checkout. An unbounded climb reaches <outer> and every
# credential in the checkout's own .env then reads as absent.
echo "Case A: a checkout with no .claude/ anchors on itself, not on a .claude ancestor"
A_OUT="$WORK/a"; A_CO="$A_OUT/checkout"
mkouter "$A_OUT"; mkcheckout "$A_CO" git
printf 'ANCHOR_BOUNDARY=planted-in-the-checkout\n' > "$A_CO/.env"
printf 'ANCHOR_BOUNDARY=planted-in-the-ancestor\n' > "$A_OUT/.env"

A_ROOT=$(anchor_of "$A_CO" "$A_CO/.session-cache")
if [ "$A_ROOT" = "$A_CO" ]; then
  pass "A1: the anchor is the checkout ($A_CO)"
else
  fail "A1: anchor stops at the checkout" "$A_CO" "$A_ROOT"
fi

mkdir -p "$A_CO/deep/deeper"
A_SUB=$(anchor_of "$A_CO" "$A_CO/.session-cache" deep/deeper)
if [ "$A_SUB" = "$A_CO" ]; then
  pass "A2: same answer from a subdirectory of the checkout"
else
  fail "A2: subdir agrees" "$A_CO" "$A_SUB"
fi

# DISK TRUTH, and a DISCRIMINATING one: both candidate directories hold the key, with
# different values. A resolver pointed at the wrong one still returns a value, so the
# only reading that can tell them apart is WHICH value comes back.
A_DISK=$(source "$ENVLIB"; extract_env_key "$A_CO/.env" ANCHOR_BOUNDARY)
A_RES=$(cd "$A_CO/deep" && export CLAUDE_SESSION_CACHE_DIR="$A_CO/.session-cache"; \
        source "$ENVLIB"; ENV_SKIP_MANIFEST_DEFAULT=1 resolve_env_key ANCHOR_BOUNDARY 2>/dev/null)
if [ "$A_DISK" = "planted-in-the-checkout" ] && [ "$A_RES" = "$A_DISK" ]; then
  pass "A3: the checkout's own .env is what resolves (not the ancestor's)"
else
  fail "A3: the checkout's .env resolves" "both 'planted-in-the-checkout'" \
       "disk='$A_DISK' resolved='$A_RES'"
fi

# ══ B. THE GUARD — a bare $PWD with no `/sessions/` segment gets NO anchor ═════
#
# No session, and no `/sessions/` anywhere in $PWD. There is no structural starting
# point, so the resolver must refuse (ENV_NO_ANCHOR_RC=3) rather than climb from $PWD
# and quietly select the ancestor's `.claude`. A general walk-up passes case A and
# fails here — that is why both cases exist.
echo "Case B: a bare \$PWD with no /sessions/ segment is refused, loudly"
B_OUT="$WORK/b"; B_CO="$B_OUT/checkout"
mkouter "$B_OUT"; mkdir -p "$B_CO/.git" "$B_CO/deep" "$B_OUT/empty-cache"
printf 'ANCHOR_BOUNDARY=planted-in-the-ancestor\n' > "$B_OUT/.env"
printf 'ANCHOR_BOUNDARY=planted-in-the-checkout\n' > "$B_CO/.env"

B_ANCHOR=$(anchor_of "$B_CO" "$B_OUT/empty-cache" deep)
B_RC=$(anchor_rc "$B_CO" "$B_OUT/empty-cache" deep)
if [ -z "$B_ANCHOR" ] && [ "$B_RC" = "3" ]; then
  pass "B1: no session + no /sessions/ in \$PWD → empty anchor, rc 3"
else
  fail "B1: refuses a bare \$PWD" "empty anchor + rc 3" "anchor='$B_ANCHOR' rc=$B_RC"
fi

B_RES=$(cd "$B_CO/deep" && export CLAUDE_SESSION_CACHE_DIR="$B_OUT/empty-cache"; \
        source "$ENVLIB"; ENV_SKIP_MANIFEST_DEFAULT=1 resolve_env_key ANCHOR_BOUNDARY 2>/dev/null)
if [ -z "$B_RES" ]; then
  pass "B2: nothing resolves from a refused anchor — no dotfile is consulted at all"
else
  fail "B2: refused anchor resolves nothing" "empty" "$B_RES"
fi

# ══ C. THE OTHER GUARD — a stray `.claude/` inside sessions/ ══════════════════
#
# Shape: <checkout>/sessions/.claude/. The strip-first order excludes the sessions/
# subtree structurally, so the climb never visits it. A fix that replaces the strip
# with a climb from the session dir fails here.
#
# The checkout carries its OWN `.claude` here, deliberately: that isolates the stray
# from case A. With no marker of its own the climb would leave the checkout for reasons
# that have nothing to do with the stray, and the case would be a second copy of A.
echo "Case C: a stray .claude/ inside sessions/ cannot capture the anchor"
C_OUT="$WORK/c"; C_CO="$C_OUT/checkout"
mkouter "$C_OUT"; mkcheckout "$C_CO" git+claude
mkdir -p "$C_CO/sessions/.claude" "$C_CO/sessions/t/.claude" "$C_CO/deep"
printf 'ANCHOR_BOUNDARY=planted-in-the-checkout\n' > "$C_CO/.env"
printf 'ANCHOR_BOUNDARY=planted-in-the-stray\n' > "$C_CO/sessions/.env"

C_ROOT=$(anchor_of "$C_CO" "$C_CO/.session-cache")
C_SUB=$(anchor_of "$C_CO" "$C_CO/.session-cache" deep)
if [ "$C_ROOT" = "$C_CO" ] && [ "$C_SUB" = "$C_CO" ]; then
  pass "C1: the anchor is the checkout, not the stray .claude inside sessions/"
else
  fail "C1: stray .claude excluded" "$C_CO (both)" "root='$C_ROOT' subdir='$C_SUB'"
fi

# STRUCTURAL: no anchor this suite produces may sit on or inside a sessions/ segment.
C_BAD=""
for a in "$A_ROOT" "$A_SUB" "$C_ROOT" "$C_SUB"; do
  case "$a" in */sessions|*/sessions/*) C_BAD="$C_BAD [$a]" ;; esac
done
if [ -z "$C_BAD" ]; then
  pass "C2: no anchor lands on or inside a sessions/ segment"
else
  fail "C2: anchor escapes sessions/" "no sessions/ segment" "$C_BAD"
fi

# ══ D. WORKSPACE NESTING — the climb the fix must keep ════════════════════════
#
# sessions live at <root>/<WORKSPACE>/sessions, the dotfiles and the `.claude` marker
# at <root>. Stripping alone stops at the workspace dir. Bounding the climb at a repo
# boundary must not shorten it: there is no boundary between the two.
echo "Case D: WORKSPACE nesting still climbs out of the workspace subdir"
D_ROOT="$WORK/d"
mkdir -p "$D_ROOT/.claude" "$D_ROOT/.git" "$D_ROOT/apps/web/sessions/t" "$D_ROOT/.session-cache"
printf '{"pid": %s}\n' "$CLAUDE_SUPERVISOR_PID" > "$D_ROOT/apps/web/sessions/t/.state.json"
printf '%s\n' "$D_ROOT/apps/web/sessions/t" > "$D_ROOT/.session-cache/claude-session-cache-$CLAUDE_SUPERVISOR_PID"
printf 'ANCHOR_BOUNDARY=planted-at-the-workspace-root\n' > "$D_ROOT/.env"

D_A=$(anchor_of "$D_ROOT" "$D_ROOT/.session-cache" . apps/web)
if [ "$D_A" = "$D_ROOT" ]; then
  pass "D1: the anchor climbs out of apps/web to the repo root"
else
  fail "D1: workspace climb" "$D_ROOT" "$D_A"
fi

D_RES=$(cd "$D_ROOT/apps/web" && export CLAUDE_SESSION_CACHE_DIR="$D_ROOT/.session-cache" WORKSPACE=apps/web; \
        source "$ENVLIB"; ENV_SKIP_MANIFEST_DEFAULT=1 resolve_env_key ANCHOR_BOUNDARY 2>/dev/null)
if [ "$D_RES" = "planted-at-the-workspace-root" ]; then
  pass "D2: the repo-root credential resolves from inside the workspace"
else
  fail "D2: workspace disk truth" "planted-at-the-workspace-root" "$D_RES"
fi

# ══ E. $HOME IS NEVER AN ANCHOR ═══════════════════════════════════════════════
#
# A checkout with NO marker of its own under a $HOME that carries a `.claude`. The
# climb has nothing to stop it but $HOME itself, and selecting $HOME is the exact
# failure the no-general-walk-up guard describes: it appears to work, then the anchor
# moves and the credentials vanish. The structurally-derived directory is kept instead.
echo "Case E: \$HOME is never selected as the anchor"
E_HOME="$WORK/e-home"; E_CO="$E_HOME/work/checkout"
mkouter_home "$E_HOME"; mkcheckout "$E_CO" none
printf 'ANCHOR_BOUNDARY=planted-in-the-home\n' > "$E_HOME/.env"
printf 'ANCHOR_BOUNDARY=planted-in-the-markerless-checkout\n' > "$E_CO/.env"

E_A=$(anchor_of "$E_CO" "$E_CO/.session-cache" . "" "$E_HOME")
if [ "$E_A" = "$E_CO" ]; then
  pass "E1: a markerless checkout under a .claude-carrying \$HOME anchors on itself"
elif [ "$E_A" = "$E_HOME" ]; then
  fail "E1: \$HOME refused" "$E_CO" "$E_HOME (the home directory was selected)"
else
  fail "E1: \$HOME refused" "$E_CO" "$E_A"
fi

exit_with_results
