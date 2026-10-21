#!/bin/bash
# tests/test-env-credential-diagnosis.sh — what a credential FAILURE is allowed to say.
#
# Run: bash ~/.claude/engine/scripts/tests/test-env-credential-diagnosis.sh
#      ENV_ANCHOR_LIB=/path/to/a/copy/of/env-lib.sh bash tests/test-env-credential-diagnosis.sh
#
# The anchor decides which dotfiles a credential resolves from, and it is derived from the
# SESSION's path — so it is wherever a session keeps its artifacts, which need not be where
# the code lives. Two different failures then arrive as the same sentence:
#
#   1. The anchor holds NO dotfile (a session whose artifacts live off-repo). The key may
#      exist in several files none of which the anchor reaches. Remedy: move the session.
#   2. The anchor holds a dotfile that does not declare the key. Remedy: add the value.
#
# A message naming only the variable fits both, and the remedies are opposites. Every case
# here asserts the output names the ANCHOR and the PATHS SEARCHED, that the two cases are
# distinguishable from each other, and — the one unrecoverable mistake available — that no
# VALUE is ever printed.
#
# Fixture idiom (the session PID cache, the physical temp path, the planted ancestor) is
# test-env-anchor-boundary.sh's; the anchor rule itself is tested there, not here.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENVLIB="${ENV_ANCHOR_LIB:-$HOME/.claude/engine/scripts/env-lib.sh}"
[ -f "$ENVLIB" ] || { echo "no env-lib at $ENVLIB" >&2; exit 1; }
echo "lib under test: $ENVLIB"

WORK=$(cd "$(mktemp -d)" && pwd -P)
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && /bin/rm -rf "$WORK"; }
trap cleanup EXIT

export CLAUDE_SUPERVISOR_PID="$$"

# The planted value. Distinctive enough that a grep for it cannot match anything else,
# which is what makes the no-value-leaked assertions mean something.
SECRET="lin_api_PLANTED_VALUE_MUST_NEVER_BE_PRINTED_9f3a"

# mkcheckout DIR — a repo-shaped checkout with an ACTIVE session, discovered through
# session.sh's PID cache so discovery owes nothing to $PWD.
mkcheckout() {
  local d="$1"
  mkdir -p "$d/sessions/t" "$d/.git" "$d/.session-cache"
  printf '{"pid": %s}\n' "$CLAUDE_SUPERVISOR_PID" > "$d/sessions/t/.state.json"
  /bin/rm -f "$d/.session-cache"/* 2>/dev/null
  printf '%s\n' "$d/sessions/t" > "$d/.session-cache/claude-session-cache-$CLAUDE_SUPERVISOR_PID"
}

# diagnose DIR CACHEDIR KEY → everything the diagnosis wrote to stderr.
# stdout is discarded on purpose: a diagnosis that reached stdout would land in a
# transcript, and the point of the function is that it does not.
diagnose() {
  local root="$1" cache="$2" key="$3"
  ( cd "$root" || return 1
    export CLAUDE_SESSION_CACHE_DIR="$cache"
    unset "$key" 2>/dev/null
    source "$ENVLIB" 2>/dev/null
    ENV_SKIP_MANIFEST_DEFAULT=1 env_credential_diagnosis "$key" 2>&1 >/dev/null )
}

# key_source DIR CACHEDIR KEY → the path env_key_source names, on stdout.
key_source() {
  local root="$1" cache="$2" key="$3"
  ( cd "$root" || return 1
    export CLAUDE_SESSION_CACHE_DIR="$cache"
    unset "$key" 2>/dev/null
    source "$ENVLIB" 2>/dev/null
    env_key_source "$key" 2>/dev/null )
}

# ══ A. THE FUNCTION EXISTS AT ALL ═════════════════════════════════════════════
echo "Case A: the diagnosis seam is present"
A_HAVE=$( source "$ENVLIB" 2>/dev/null
          for fn in env_credential_diagnosis env_key_source; do
            type "$fn" >/dev/null 2>&1 || printf '%s ' "$fn"
          done )
if [ -z "$A_HAVE" ]; then
  pass "A1: env_credential_diagnosis and env_key_source are both defined"
else
  fail "A1: both seams defined" "both present" "missing: $A_HAVE"
fi

# ══ B. INSTANCE ONE — an anchor holding NO dotfile ════════════════════════════
#
# The measured shape: artifacts off-repo, so the anchor is a tree with no dotfile and no
# code, while the key sits in files the anchor never reaches. The failure must name the
# anchor and the paths, and must NOT claim the variable is simply unset.
echo "Case B: an anchor with no dotfile names the anchor and the paths it searched"
B_CO="$WORK/b/checkout"
mkcheckout "$B_CO"
# The key exists — in a sibling tree the anchor does not reach. This is the whole defect:
# "missing" was never true.
mkdir -p "$WORK/b/elsewhere"
printf 'LINEAR_API_KEY=%s\n' "$SECRET" > "$WORK/b/elsewhere/.env"

B_OUT=$(diagnose "$B_CO" "$B_CO/.session-cache" LINEAR_API_KEY)

if printf '%s' "$B_OUT" | grep -qF "$B_CO"; then
  pass "B1: the anchor is named in the failure"
else
  fail "B1: anchor named" "output containing $B_CO" "$B_OUT"
fi

if printf '%s' "$B_OUT" | grep -qF "$B_CO/.env.local" \
   && printf '%s' "$B_OUT" | grep -qF "$B_CO/.env"; then
  pass "B2: both searched paths are named"
else
  fail "B2: searched paths named" ".env.local and .env under the anchor" "$B_OUT"
fi

if printf '%s' "$B_OUT" | grep -qF "$SECRET"; then
  fail "B3: no value is printed" "the planted value absent" "THE VALUE LEAKED"
else
  pass "B3: no value reaches the output"
fi

# ══ C. INSTANCE TWO'S SIBLING — a dotfile that exists but lacks the key ═══════
#
# Same anchor, a dotfile present. The remedy is the opposite of case B's, so the two
# messages must be distinguishable. A single sentence for both is the defect.
echo "Case C: a present dotfile without the key reads differently from no dotfile at all"
C_CO="$WORK/c/checkout"
mkcheckout "$C_CO"
printf 'SOME_OTHER_KEY=irrelevant\n' > "$C_CO/.env"

C_OUT=$(diagnose "$C_CO" "$C_CO/.session-cache" LINEAR_API_KEY)

if printf '%s' "$C_OUT" | grep -qF "$C_CO/.env"; then
  pass "C1: the present dotfile is named"
else
  fail "C1: dotfile named" "output containing $C_CO/.env" "$C_OUT"
fi

# The discriminator. Both outputs name an anchor and two paths, so the shared vocabulary
# cannot tell them apart — only a per-path verdict can. Normalising the paths away leaves
# just the verdicts, and those must differ.
B_SHAPE=$(printf '%s' "$B_OUT" | sed "s#$B_CO#ANCHOR#g")
C_SHAPE=$(printf '%s' "$C_OUT" | sed "s#$C_CO#ANCHOR#g")
if [ "$B_SHAPE" != "$C_SHAPE" ]; then
  pass "C2: the two failures are distinguishable with the paths normalised away"
else
  fail "C2: the two failures differ" "different text" "identical: $B_SHAPE"
fi

# ══ D. THE CONTROL — the new message is not unconditional ═════════════════════
#
# Acceptance's own control: the same anchor, holding the value. Nothing may be diagnosed,
# because nothing failed. A message that fires here is noise rather than a reading.
echo "Case D: control — an anchor that holds the value resolves and reports its source"
D_CO="$WORK/d/checkout"
mkcheckout "$D_CO"
printf 'LINEAR_API_KEY=%s\n' "$SECRET" > "$D_CO/.env"

D_RES=$( cd "$D_CO" && export CLAUDE_SESSION_CACHE_DIR="$D_CO/.session-cache"
         unset LINEAR_API_KEY
         source "$ENVLIB" 2>/dev/null
         ENV_SKIP_MANIFEST_DEFAULT=1 resolve_env_key LINEAR_API_KEY 2>/dev/null )
if [ "$D_RES" = "$SECRET" ]; then
  pass "D1: the key still resolves where it exists (the fix is not a blanket failure)"
else
  fail "D1: control resolves" "the planted value" "got a different or empty value"
fi

D_SRC=$(key_source "$D_CO" "$D_CO/.session-cache" LINEAR_API_KEY)
if [ "$D_SRC" = "$D_CO/.env" ]; then
  pass "D2: env_key_source names the file the value came from"
else
  fail "D2: source named" "$D_CO/.env" "$D_SRC"
fi

if printf '%s' "$D_SRC" | grep -qF "$SECRET"; then
  fail "D3: the source is a path, not a value" "no value" "THE VALUE LEAKED"
else
  pass "D3: env_key_source emits a path and no value"
fi

# ══ E. INSTANCE TWO — two reachable dotfiles, different values ════════════════
#
# The silent half: the anchor chose between two values without saying so. The output must
# say WHICH file was used — and still not say what either holds.
echo "Case E: two dotfiles disagreeing — the output says which one was used"
E_CO="$WORK/e/checkout"
mkcheckout "$E_CO"
printf 'LINEAR_API_KEY=%s\n' "$SECRET"            > "$E_CO/.env.local"
printf 'LINEAR_API_KEY=%s\n' "lin_api_THE_OTHER"  > "$E_CO/.env"

E_SRC=$(key_source "$E_CO" "$E_CO/.session-cache" LINEAR_API_KEY)
if [ "$E_SRC" = "$E_CO/.env.local" ]; then
  pass "E1: the winning file is named, and it is the precedence winner"
else
  fail "E1: winner named" "$E_CO/.env.local" "$E_SRC"
fi

# env_key_source must agree with what resolve_env_key actually returns. A second reader
# that disagrees with the one that resolved the credential is worse than no reader.
E_RES=$( cd "$E_CO" && export CLAUDE_SESSION_CACHE_DIR="$E_CO/.session-cache"
         unset LINEAR_API_KEY
         source "$ENVLIB" 2>/dev/null
         ENV_SKIP_MANIFEST_DEFAULT=1 resolve_env_key LINEAR_API_KEY 2>/dev/null )
if [ "$E_RES" = "$SECRET" ]; then
  pass "E2: env_key_source agrees with the file resolve_env_key actually read"
else
  fail "E2: reader agrees with resolver" "the .env.local value" "a different file won"
fi

# ══ F. AN ENV VAR BEATS EVERY FILE, AND THE SOURCE SAYS SO ════════════════════
echo "Case F: a real environment variable is reported as the environment, not a file"
F_CO="$WORK/f/checkout"
mkcheckout "$F_CO"
printf 'LINEAR_API_KEY=%s\n' "lin_api_FROM_A_FILE" > "$F_CO/.env"

F_SRC=$( cd "$F_CO" && export CLAUDE_SESSION_CACHE_DIR="$F_CO/.session-cache"
         export LINEAR_API_KEY="$SECRET"
         source "$ENVLIB" 2>/dev/null
         env_key_source LINEAR_API_KEY 2>/dev/null )
if [ "$F_SRC" = "environment" ]; then
  pass "F1: an exported value reports 'environment'"
else
  fail "F1: environment reported" "environment" "$F_SRC"
fi

# ══ G. NO ANCHOR — still the specific message, not the generic one ════════════
#
# The branch the ticket rules out as the cause but which must keep working: no session and
# no /sessions/ segment in $PWD. The diagnosis must say there is no anchor rather than
# naming paths it never searched.
echo "Case G: no anchor at all is its own third outcome"
G_CO="$WORK/g/checkout"
mkdir -p "$G_CO/.git" "$WORK/g/empty-cache"
G_OUT=$(diagnose "$G_CO" "$WORK/g/empty-cache" LINEAR_API_KEY)
if printf '%s' "$G_OUT" | grep -qi "anchor"; then
  pass "G1: the no-anchor outcome still speaks of the anchor"
else
  fail "G1: no-anchor named" "output mentioning the anchor" "$G_OUT"
fi
if printf '%s' "$G_OUT" | grep -qF "$G_CO/.env"; then
  fail "G2: no path is claimed as searched" "no path named" "$G_OUT"
else
  pass "G2: no dotfile path is claimed as searched when none was"
fi

# ══ H. THE CALL SITES — no credential throw may name only the variable ═══════
#
# The four `:?` throws were one sentence apiece. A fix that lands the function and leaves
# the throws in place closes nothing, so the call sites are asserted here rather than by
# re-reading the diff.
echo "Case H: the credential call sites route through the diagnosis"
H_SCRIPTS="$(dirname "$ENVLIB")"
H_BAD=""
for f in linear-lib.sh ticket-search.sh gemini.sh research.sh; do
  [ -f "$H_SCRIPTS/$f" ] || continue
  if grep -q ':?[A-Z_]* is required' "$H_SCRIPTS/$f"; then
    H_BAD="$H_BAD $f"
  fi
done
if [ -z "$H_BAD" ]; then
  pass "H1: no call site still throws a variable-only 'is required'"
else
  fail "H1: no bare 'is required' throw" "none" "still present in:$H_BAD"
fi

# ticket-search.sh is absent on purpose: it reaches the diagnosis through linear-lib's
# _load_key, and Case J executes its failure path rather than grepping for the name.
H_MISSING=""
for f in linear-lib.sh gemini.sh research.sh; do
  [ -f "$H_SCRIPTS/$f" ] || continue
  grep -q 'env_credential_diagnosis' "$H_SCRIPTS/$f" || H_MISSING="$H_MISSING $f"
done
if [ -z "$H_MISSING" ]; then
  pass "H2: every call site calls env_credential_diagnosis"
else
  fail "H2: every call site diagnoses" "all three" "missing in:$H_MISSING"
fi

# Positive control for H: the pattern H1 forbids DOES match a planted copy of the old
# throw, so H1's zero is a reading and not a broken instrument.
H_CTRL="$WORK/h-control.sh"
printf '%s\n' ': "${LINEAR_API_KEY:?LINEAR_API_KEY is required — set it in your environment}"' > "$H_CTRL"
if grep -q ':?[A-Z_]* is required' "$H_CTRL"; then
  pass "H3: control — the forbidden pattern matches the old throw it describes"
else
  fail "H3: control matches" "a match against the planted old throw" "no match: H1 cannot discriminate"
fi

# ══ I. THE LIVE PATH: _load_key names the FILE, not "the environment" ═════════
# _load_key exports the key it resolved; read after that, the variable is its own source
# and every announcement says "environment". Driven end to end through linear-lib.
echo "Case I: linear-lib announces the dotfile the key came from"
I_CO="$WORK/i-co"
mkcheckout "$I_CO"
printf 'LINEAR_API_KEY=%s\n' "$SECRET" > "$I_CO/.env.local"
printf 'LINEAR_API_KEY=%s\n' "${SECRET}_other" > "$I_CO/.env"
I_ERR=$( cd "$I_CO" && export CLAUDE_SESSION_CACHE_DIR="$I_CO/.session-cache"
         unset LINEAR_API_KEY
         source "$ENVLIB" 2>/dev/null; source "$(dirname "$ENVLIB")/linear-lib.sh" 2>/dev/null
         _load_key 2>&1 >/dev/null; echo "rc=$?" )
case "$I_ERR" in
  *"from $I_CO/.env.local"*) pass "I1: the announcement names the winning dotfile" ;;
  *) fail "I1: names the dotfile" "from $I_CO/.env.local" "$I_ERR" ;;
esac
case "$I_ERR" in
  *PLANTED_VALUE*) fail "I2: no value in the announcement" "no value" "value printed" ;;
  *) pass "I2: no value in the announcement" ;;
esac

# The success path must stay silent about failure: the diagnosis is for a key that did not
# resolve, and a copy that prints it on the way to success would pass every case above.
case "$I_ERR" in
  *"rc=0"*) pass "I3: a resolving key returns 0" ;;
  *) fail "I3: rc 0 on success" "rc=0" "$I_ERR" ;;
esac
case "$I_ERR" in
  *"cannot authenticate"*|*"did not resolve"*) fail "I4: no failure text on the success path" "neither phrase" "$I_ERR" ;;
  *) pass "I4: neither 'cannot authenticate' nor 'did not resolve' appears on the success path" ;;
esac

# ══ J. ticket-search USES the shared _load_key (no second copy to drift) ══════
# Driven as the real script on the live path with a stub curl, on the same two-dotfile
# fixture: the announcement must name the dotfile, never "the environment".
echo "Case J: ticket-search announces the dotfile, from the shared function"
J_BIN="$WORK/j-bin"; mkdir -p "$J_BIN"
printf '#!/bin/bash\necho '"'"'{"data":{"searchIssues":{"nodes":[]}}}'"'"'\n' > "$J_BIN/curl"
chmod +x "$J_BIN/curl"
J_SCRIPTS="$(dirname "$ENVLIB")"
J_ERR=$( cd "$I_CO" && export CLAUDE_SESSION_CACHE_DIR="$I_CO/.session-cache"
         unset LINEAR_API_KEY TICKET_SEARCH_FIXTURE
         export ENGINE_SCRIPTS="$J_SCRIPTS" PATH="$J_BIN:$PATH"
         bash "$J_SCRIPTS/ticket-search.sh" "roof leak" 2>&1 >/dev/null )
case "$J_ERR" in
  *"from $I_CO/.env.local"*) pass "J1: ticket-search names the winning dotfile" ;;
  *) fail "J1: names the dotfile" "from $I_CO/.env.local" "$J_ERR" ;;
esac
case "$J_ERR" in
  *"from the environment"*) fail "J2: not mislabelled as the environment" "absent" "$J_ERR" ;;
  *) pass "J2: not mislabelled as the environment" ;;
esac
case "$J_ERR" in
  *"cannot authenticate"*|*PLANTED_VALUE*) fail "J3: success path silent about failure, no value" "neither" "$J_ERR" ;;
  *) pass "J3: success path carries no failure text and no value" ;;
esac
if [ -z "$(grep -n '^_load_key()' "$J_SCRIPTS/ticket-search.sh")" ]; then
  pass "J4: ticket-search defines no _load_key of its own"
else
  fail "J4: no private copy" "no _load_key definition" "$(grep -n '^_load_key()' "$J_SCRIPTS/ticket-search.sh")"
fi

# The failure branch of the same script, in an anchor whose dotfile lacks the key.
J_CO="$WORK/j-co"; mkcheckout "$J_CO"; printf 'OTHER=1\n' > "$J_CO/.env"
J_FAIL=$( cd "$J_CO" && export CLAUDE_SESSION_CACHE_DIR="$J_CO/.session-cache"
          unset LINEAR_API_KEY TICKET_SEARCH_FIXTURE
          export ENGINE_SCRIPTS="$J_SCRIPTS" ENV_SKIP_MANIFEST_DEFAULT=1 PATH="$J_BIN:$PATH"
          bash "$J_SCRIPTS/ticket-search.sh" "roof leak" 2>&1 >/dev/null )
case "$J_FAIL" in
  *"cannot authenticate"*"$J_CO"*) pass "J5: ticket-search's failure names the anchor (control for J3)" ;;
  *) fail "J5: failure names the anchor" "cannot authenticate + $J_CO" "$J_FAIL" ;;
esac

exit_with_results
