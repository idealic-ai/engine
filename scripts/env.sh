#!/bin/bash
# env.sh — engine env <doctor|setup|env-example>: per-domain credential scaffolding.
#
# One credential manifest PER DOMAIN (skills/<domain>/assets/CREDENTIALS.manifest) is
# the single source of truth; this command reads it to (a) VERIFY the operator's setup
# (doctor), (b) WALK the operator through the secret ones (setup), and (c) GENERATE the
# committed `.env.example` (env-example). All three derive from the manifest so the
# anti-drift tool does not itself drift. `--domain` selects which manifest, so a design
# operator is never blocked on a credential only an intake wave needs.
#
# Usage:
#   engine env doctor [--domain <name>] [--env-example <path>]
#                                                 Red/green preflight of every credential.
#                                                 Exits non-zero iff a REQUIRED cred is missing
#                                                 (so a caller can gate). Reads no API secrets;
#                                                 the only network touch is the timed
#                                                 `claude mcp list` MCP-reachability probe.
#                                                 Seeds missing non-secret defaults into their
#                                                 dotfile. --env-example asserts a committed
#                                                 .env.example agrees with the manifest.
#   engine env setup [--domain <name>] [--non-interactive]
#                                                 Wizard: prompt for each missing SECRET row,
#                                                 write it to its gitignored dotfile.
#                                                 --non-interactive (alias --dry-run) echoes
#                                                 what it WOULD write, writes nothing.
#                                                 WITH NO --domain it walks EVERY domain that
#                                                 has a manifest — a new teammate does not
#                                                 know they are an "intake person". One
#                                                 domain failing does not strand the rest.
#                                                 The DOCTOR deliberately does NOT do this:
#                                                 its per-domain scoping is the guard that
#                                                 keeps a design operator from being blocked
#                                                 by a credential only intake needs.
#   engine env env-example [--domain <name>]      Print the manifest-derived `.env.example` to
#                                                 stdout (secret NAMES with empty values, non-
#                                                 secret defaults filled). Redirect to a file.
#   engine env provision --tier <triage|member> [--person <name>] [--account <id>]
#                        [--apply] [--reconcile] [--clerk-only] [--no-clerk]
#                        [--email <addr>] [--out <path>]
#                                                 Derive the agent's IAM policy FROM THE
#                                                 MANIFEST's `required` tiers and mint the
#                                                 operator's own <name>-agent user.
#                                                 --reconcile compares the attached policy
#                                                 against what the manifest now derives and
#                                                 (with --apply) replaces it, so a grant
#                                                 SHRINKS when a manifest row goes away.
#                                                 Exit 0 in sync / 1 drifted / 2 cannot run,
#                                                 so a dry run is usable as a gate. Anything
#                                                 else on the user is reported, never touched.
#                                                 --apply always reads a typed confirmation
#                                                 of the account id; there is no flag for it.
#                                                 --apply ALSO creates the app login in the
#                                                 Clerk instance CLERK_SECRET_KEY points at
#                                                 and stores its password in Secrets Manager;
#                                                 --no-clerk skips that half, --clerk-only
#                                                 does only it (the mint refuses early once a
#                                                 profile exists, which would otherwise take
#                                                 the app login down with it).
#                                                 Provisioning for SOMEONE ELSE writes a 0600
#                                                 delivery file (--out) in the format
#                                                 `setup --aws-key` consumes, and leaves your
#                                                 own FINCH_AGENT_AWS_PROFILE alone.
#   engine env resolve <KEY> [--show-value]       Say WHERE a credential resolves from and
#                                                 whether it is present. The VALUE is not
#                                                 printed unless --show-value is passed, so
#                                                 the default is safe in scrollback, shell
#                                                 history and a screenshare. Exits non-zero
#                                                 when the key resolves nowhere.
#
# `--domain` defaults to `intake`.
#
# `.env.local` is the one file an operator needs for the keys the manifest homes there,
# and the ONLY file a secret is ever written to. A key is READ from `.env.local` first and
# `.env` second (env-lib.sh owns the rule), so setups that keep keys in `.env` keep
# working. Rows the manifest pins to `.env` must stay there — their reader is out-of-band.
#
# Test seams:
#   ENV_MANIFEST         override the manifest path (default: the domain's assets copy).
#   ENV_MCP_LIST_OUTPUT  when SET (even empty), used verbatim instead of `claude mcp list`
#                        (empty string = "command unavailable" → degrade to WARN).
#   (resolution is project-scoped: no global engine-home dotfile is ever consulted.)
set -uo pipefail

# Walk the symlink chain before looking for the sibling lib: a test harness may symlink
# this script into a fake HOME where scripts/env-lib.sh does not exist next to the link.
_ENV_SH_SRC="${BASH_SOURCE[0]:-$0}"
while [ -L "$_ENV_SH_SRC" ]; do
  _ENV_SH_DIR="$(cd -P "$(dirname "$_ENV_SH_SRC")" && pwd)"
  _ENV_SH_SRC="$(readlink "$_ENV_SH_SRC")"
  case "$_ENV_SH_SRC" in /*) ;; *) _ENV_SH_SRC="$_ENV_SH_DIR/$_ENV_SH_SRC" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$_ENV_SH_SRC")" && pwd)"
# extract_env_key / resolve_env_key — grep a KEY=value out of a dotfile WITHOUT sourcing it.
if [ -f "$SCRIPT_DIR/env-lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/env-lib.sh"
else
  echo "env: missing required $SCRIPT_DIR/env-lib.sh" >&2
  exit 1
fi

USAGE_LINES='11,36p'

# --- Colors (mirror doctor.sh) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Counters (doctor) ---
PASSES=0
WARNS=0
FAILS=0

pass()  { PASSES=$((PASSES + 1)); printf "  ${GREEN}PASS${NC}  %-24s %s\n" "$1" "${2:-}"; }
warn()  { WARNS=$((WARNS + 1));   printf "  ${YELLOW}WARN${NC}  %-24s %s\n" "$1" "${2:-}"; }
fail()  { FAILS=$((FAILS + 1));   printf "  ${RED}FAIL${NC}  %-24s %s\n" "$1" "${2:-}"; }
note()  {                          printf "  ${CYAN}NOTE${NC}  %-24s %s\n" "$1" "${2:-}"; }
seed()  { PASSES=$((PASSES + 1)); printf "  ${GREEN}SEED${NC}  %-24s %s\n" "$1" "${2:-}"; }

# --- Domain + manifest ---
DOMAIN="intake"

# The manifest reader lives in env-lib.sh (env_manifest_path / env_manifest_rows) —
# ONE parser, shared with env_load_domain. Rows arrive \037-separated, 10 fields:
# key service required secret default dotfile how check_type check_arg source_type
# The doctor/wizard/generator check the `core` rows on TOP of the named domain's, so a
# credential every session needs is never skipped just because you asked about `design`.
# Dedup is by KEY, core first. `env_load_domain` deliberately does NOT compose this way —
# loading is per-domain, so sourcing /prove's helper cannot sweep in a live Slack token.
manifest_rows() {
  if [ "$DOMAIN" = "core" ]; then env_manifest_rows core; return; fi
  { env_manifest_rows core; env_manifest_rows "$DOMAIN"; } | awk -F'\037' 'NF && !seen[$1]++'
}

# True if a KEY= line exists in the dotfile (even with an empty value). Presence
# is line existence, NOT a non-empty value — so seeding stays idempotent.
# An optional `export ` prefix counts (env-lib.sh's reader accepts it too) — otherwise
# the seed path treats "I could not parse it" as "it is not there" and appends a second,
# conflicting definition of a key the operator already set.
key_line_present() {
  local dotfile="$1" key="$2"
  [ -n "$dotfile" ] && [ -f "$dotfile" ] && grep -qE "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$dotfile"
}

# Replace the value of the FIRST existing KEY= line in a dotfile, in place —
# fills a present-but-empty key without appending a duplicate. An `export ` prefix is
# matched (mirroring key_line_present) and preserved, so filling a value does not
# silently strip the operator's export.
fill_env_key() {
  local dotfile="$1" key="$2" value="$3" tmp rc
  tmp="$(mktemp)" || return 1
  awk -v k="$key" -v v="$value" '
    !filled && $0 ~ ("^[[:space:]]*(export[[:space:]]+)?" k "[[:space:]]*=") {
      pre = ($0 ~ ("^[[:space:]]*export[[:space:]]+")) ? "export " : ""
      print pre k "=" v; filled = 1; next
    }
    { print }
  ' "$dotfile" > "$tmp" || { rm -f "$tmp"; return 1; }
  cat "$tmp" > "$dotfile"; rc=$?
  rm -f "$tmp"
  return $rc
}

# Dotfiles the doctor/wizard may WRITE to, most-preferred first: the row's manifest
# home and ./.env.local. `./.env` is NOT a write target — a secret row's home is always
# .env.local, so a live token can never be written into a file that may be committed.
# (`.env` stays fully READABLE; only the rows the manifest pins there — PROVE_S3_*,
# whose out-of-band reader opens nothing else — are ever seeded into it.)
# Paths are ANCHORED to the session's project root, exactly like the reader's
# env_key_files. Moving one without the other is §PTF_CHECKER_SEARCH_SET_EXCEEDS_CONSUMER
# in mirror image: setup would write where doctor will not read.
writable_dotfiles() {
  local preferred="$1" root
  root="$(env_anchor_dir)" || return "$ENV_NO_ANCHOR_RC"
  { [ -n "$preferred" ] && env_anchored_path "$preferred" && printf '\n'
    printf '%s/%s\n' "$root" ".env.local"; } | awk 'NF && !seen[$0]++'
}

# locate_key_line KEY PREFERRED → the first writable dotfile that already carries a
# KEY= line (even an empty one), else non-zero. Fills happen where the line actually
# is, so a blank key in .env is never orphaned by a value written to .env.local.
locate_key_line() {
  local key="$1" preferred="$2" f
  while IFS= read -r f; do
    if key_line_present "$f" "$key"; then printf '%s' "$f"; return 0; fi
  done < <(writable_dotfiles "$preferred")
  return 1
}

# --- Presence check (shared by doctor + setup) ---
# key_present KEY DOTFILE CHECK_TYPE [CHECK_ARG] → 0 present, 1 missing,
# 2 cannot-verify (mcp cmd absent), 3 no session anchor. CHECK_ARG is the mcp
# server / binary name. Only `file-key` needs the anchor; env-present reads a live
# env var, and binary/mcp/note ask the machine, not the project.
key_present() {
  local key="$1" dotfile="$2" check="$3" arg="${4:-}"
  case "$check" in
    file-key)
      # The manifest's dotfile is the PREFERRED home, not the only one searched:
      # resolve_env_key falls through to <anchor>/.env.local / <anchor>/.env.
      local rc _v
      _v="$(resolve_env_key "$key" "$dotfile" 2>/dev/null)"; rc=$?
      # Only the PREFIX is inspected; the value itself never leaves this branch.
      [ "$rc" -eq 0 ] && env_is_placeholder "$_v" && { _v=""; return 4; }
      _v=""
      [ "$rc" -eq 0 ] && return 0
      [ "$rc" -eq "$ENV_NO_ANCHOR_RC" ] && return 3
      return 1 ;;
    env-present)
      [ -n "${!key:-}" ] || return 1
      # An AWS profile NAME being set says nothing about whether it still authenticates,
      # and a human profile carries login_session — it expires daily by design. Reporting
      # the name as PASS meant pointing at a DEAD profile scored better than leaving it
      # unset: 23 PASS/4 WARN became 24 PASS/3 WARN. Same shape as a placeholder value.
      # The agent-profile check already makes this call; this is the same probe, reused.
      case "$key" in
        AWS_PROFILE|*_AWS_PROFILE)
          if [ -n "${ENV_STS_ARN+set}" ]; then
            echo "env: ⚠️  TEST SEAM ACTIVE — ENV_STS_ARN is set (no AWS call was made)" >&2
            return 0
          fi
          command -v aws >/dev/null 2>&1 || return 0   # cannot check ≠ broken; BIN_AWS owns that
          _sts_probe_cached "${!key}" >/dev/null 2>&1 && return 0
          return 5 ;;
      esac
      return 0 ;;
    binary)
      command -v "$arg" >/dev/null 2>&1 && return 0
      return 1 ;;
    mcp)
      local out server_line
      mcp_list_output; out="$MCP_LIST_OUT"
      [ -n "${MCP_PROBE_CAUSE:-}" ] && return 2
      [ -z "$out" ] && return 2
      server_line="$(printf '%s' "$out" | grep -E "^[[:space:]]*${arg}:" | head -1)"
      # Server not listed / format unrecognized → cannot verify (WARN, never a
      # hard FAIL that could false-block Phase 0 on a `claude mcp list` format drift).
      [ -z "$server_line" ] && return 2
      # An explicit unhealthy state is a real miss (req → FAIL). Check it BEFORE the
      # connected match so "not connected"/"disconnected" don't slip through.
      printf '%s' "$server_line" | grep -qiE 'need.? auth|authenticat|not connected|disconnect|fail|error|unreachable|timed? ?out' && return 1
      printf '%s' "$server_line" | grep -qi 'connected' && return 0
      return 2 ;;
    note)   return 0 ;;
    *)      return 1 ;;
  esac
}

# `claude mcp list` output, honoring the ENV_MCP_LIST_OUTPUT test seam.
#
# Sets MCP_PROBE_CAUSE so a caller can say WHY verification failed. "We could not check"
# and "it is fine" are different facts, and the three causes need three different
# actions: install the CLI · retry/raise the budget · go authenticate.
#
# ⚠️ CWD-PINNED TO THE SESSION ANCHOR. `claude mcp list` is CWD-scoped — measured 1
# server from ~/.claude/engine vs 5 from the finch root — so an unpinned probe passes or
# fails on which directory you happen to be standing in.
#
# ⚠️ The budget is PER SERVER, not one shared bound: 5 servers cost ~7.5s warm, so a
# single 15s cap is ~2x the real cost and collapses as the server count grows.
MCP_PROBE_CAUSE=""
MCP_SECONDS_PER_SERVER=8
MCP_LIST_OUT=""
MCP_UNBOUNDED=""
MCP_CACHE_AGE=""
_MCP_PROBED=""
_MCP_FS=$'\037'

# ⚠️ Sets GLOBALS and prints nothing. It used to print, and the caller captured it with
# `$(mcp_list_output)` — a SUBSHELL, so every cause it recorded was discarded on the way
# out and every failure collapsed to the same generic message. Probing once and assigning
# is also what keeps the per-server budget from being re-spent on every row.
mcp_list_output() {
  [ -n "$_MCP_PROBED" ] && return 0
  _MCP_PROBED=1
  MCP_PROBE_CAUSE=""; MCP_LIST_OUT=""; MCP_UNBOUNDED=""

  [ -n "${ENV_MCP_NO_TIMEOUT:-}" ] && MCP_UNBOUNDED=1
  if [ -n "${ENV_MCP_NO_BINARY:-}" ]; then MCP_PROBE_CAUSE="no-binary"; return 0; fi
  if [ -n "${ENV_MCP_TIMED_OUT:-}" ]; then MCP_PROBE_CAUSE="timed-out"; return 0; fi
  if [ -n "${ENV_MCP_LIST_OUTPUT+set}" ]; then
    MCP_LIST_OUT="$ENV_MCP_LIST_OUTPUT"
    [ -z "$MCP_LIST_OUT" ] && MCP_PROBE_CAUSE="empty"
    return 0
  fi
  if ! command -v claude >/dev/null 2>&1; then MCP_PROBE_CAUSE="no-binary"; return 0; fi

  local n t="" anchor rc
  n="$(manifest_rows 2>/dev/null | grep -c "${_MCP_FS}mcp${_MCP_FS}" || true)"
  [ "${n:-0}" -gt 0 ] || n=1
  if command -v timeout >/dev/null 2>&1;    then t="timeout $((n * MCP_SECONDS_PER_SERVER))"
  elif command -v gtimeout >/dev/null 2>&1; then t="gtimeout $((n * MCP_SECONDS_PER_SERVER))"
  else MCP_UNBOUNDED=1; fi

  anchor="$(env_anchor_dir 2>/dev/null)" || anchor="$PWD"
  # ── cache ──────────────────────────────────────────────────────────────────
  # `claude mcp list` is essentially the entire runtime of this command — ~9s against
  # ~2s for everything else — which is what stops the doctor being runnable at skill
  # startup. MCP auth state changes only when someone completes an OAuth consent, so it
  # is worth remembering for a short while.
  #
  # ⚠️ Only a SUCCESSFUL probe is cached. Remembering a timeout would make one transient
  # hiccup stick for the whole TTL, and the doctor treats unverifiable as failing — so a
  # cached failure would block a wave that is actually fine.
  local cache_ttl="${ENV_MCP_CACHE_TTL:-300}" cache_file="" cache_age=""
  if [ "$cache_ttl" -gt 0 ] 2>/dev/null; then
    local akey
    akey="$(printf '%s' "${anchor:-.}" | shasum -a 256 2>/dev/null | cut -c1-16)"
    # A STABLE directory, not $TMPDIR. Some shells and sandboxes hand out a fresh TMPDIR
    # per invocation, and a cache that moves is a cache that never hits — it would look
    # like caching had simply not worked.
    local cdir="${XDG_CACHE_HOME:-$HOME/.cache}/engine"
    mkdir -p "$cdir" 2>/dev/null || cdir="${TMPDIR:-/tmp}"
    [ -n "$akey" ] && cache_file="${cdir}/mcp-probe-${akey}"
  fi
  if [ -n "$cache_file" ] && [ -z "${ENV_MCP_NO_CACHE:-}" ] && [ -f "$cache_file" ]; then
    local now mtime
    now="$(date +%s)"
    mtime="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)"
    cache_age=$(( now - mtime ))
    if [ "$cache_age" -ge 0 ] && [ "$cache_age" -lt "$cache_ttl" ]; then
      MCP_LIST_OUT="$(cat "$cache_file" 2>/dev/null)"
      if [ -n "$MCP_LIST_OUT" ]; then
        MCP_CACHE_AGE="$cache_age"
        return 0
      fi
    fi
  fi

  MCP_LIST_OUT="$(cd "$anchor" 2>/dev/null && $t claude mcp list 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$t" ]; then MCP_PROBE_CAUSE="timed-out"; MCP_LIST_OUT=""; return 0; fi
  [ -z "$MCP_LIST_OUT" ] && MCP_PROBE_CAUSE="empty"
  if [ -n "$MCP_LIST_OUT" ] && [ -n "$cache_file" ]; then
    ( umask 077; printf '%s' "$MCP_LIST_OUT" > "$cache_file" ) 2>/dev/null || true
  fi
  return 0
}

# The unverifiable message, by cause — named so the reader knows WHICH action to take.
mcp_cause_hint() {
  case "${MCP_PROBE_CAUSE:-}" in
    no-binary) printf 'the `claude` binary is not on PATH, so MCP state cannot be checked at all' ;;
    timed-out) printf 'the MCP probe timed out (budget %ss per server) — retry, or the server is wedged' "$MCP_SECONDS_PER_SERVER" ;;
    *)         printf '`claude mcp list` reported nothing usable for it' ;;
  esac
}

# Miss severity by `required`: req→fail, else→warn.
report_miss() {
  local required="$1" key="$2" how="$3"
  case "$required" in
    req) fail "$key" "$how" ;;
    *)   warn "$key" "$how" ;;
  esac
}

# --- .env.example generation (the single generator; doctor + env-example both use it) ---
# Prints only the real env-var rows (file-key / env-present); MCP, binaries, runtime
# secrets and unwired notes are documented in the header, not as dotfile keys.
gen_env_example() {
  cat <<'HDR'
# .env.example — intake operator credentials. GENERATED from CREDENTIALS.manifest
# (engine env env-example --domain intake). Do not hand-edit; regenerate after a manifest change.
#
# Each `--- <file> ---` group below names the file its keys belong in. They are NOT
# interchangeable, so copy each group into the file it names:
#   .env.local  — read from .env.local first and .env second (so an existing .env setup
#                 keeps working, and a key in both files resolves to the .env.local one),
#                 and the only file `engine env doctor|setup` ever writes.
#   .env        — the home for those keys, and PROVE_S3_* are REQUIRED there: their
#                 reader (skills/prove/assets/_prove-s3-env.sh) never opens .env.local.
# Secrets carry an empty value here (never a real token). Non-secret defaults are filled.
#
# NOT dotfile keys (documented, set up out-of-band):
#   linear-server (MCP)  — interactive OAuth in Claude Code; all /intake writes are MCP-only
#   notion (MCP)         — interactive OAuth; project-creation / KB steps only
#   posthog (MCP)        — interactive OAuth; product-analytics signals during triage
#   github (MCP)         — interactive OAuth; reads the PRs/issues a signal cites
#   aws, session-manager-plugin — binaries; install AWS CLI v2 + the SSM plugin
#   AWS_PROFILE          — a static IAM profile name, exported in your shell (this setup has NO SSO)
#   FINCH_DB_RO_SECRET   — Secrets Manager name staging/finch/db-ro-url, fetched at runtime
HDR
  local key service required secret default dotfile how check arg src sname sfield sregion sprofile
  local last_dotfile=""
  while IFS=$'\037' read -r key service required secret default dotfile how check arg src sname sfield sregion sprofile; do
    case "$check" in file-key|env-present) ;; *) continue ;; esac
    # The "read from .env.local first" promise is only true for rows homed THERE; the
    # .env group has an out-of-band reader (skills/prove/assets/_prove-s3-env.sh walks
    # to the nearest .env and never opens .env.local), so it is labelled REQUIRED.
    local label
    case "$dotfile" in
      .env.local) label="$dotfile (read here first, then .env; fresh values are written here)" ;;
      .env)       label="$dotfile (home for these keys; PROVE_S3_* are REQUIRED here — _prove-s3-env.sh reads the nearest .env, never .env.local)" ;;
      "")         dotfile="(exported env)"; label="$dotfile" ;;
      *)          label="$dotfile (preferred home)" ;;
    esac
    if [ "$dotfile" != "$last_dotfile" ]; then
      printf '\n# --- %s ---\n' "$label"
      last_dotfile="$dotfile"
    fi
    printf '# how: %s\n' "$how"
    if [ "$secret" = "true" ] || [ -z "$default" ]; then
      printf '%s=\n' "$key"
    else
      printf '%s=%s\n' "$key" "$default"
    fi
  done < <(manifest_rows)
}

# Names of secret env-var rows — the drift check compares these by NAME only
# (their value is intentionally blank in .env.example, never a real token).
manifest_secret_keys() {
  local key service required secret default dotfile how check arg src sname sfield sregion sprofile
  while IFS=$'\037' read -r key service required secret default dotfile how check arg src sname sfield sregion sprofile; do
    case "$check" in file-key|env-present) ;; *) continue ;; esac
    [ "$secret" = "true" ] && printf '%s\n' "$key"
  done < <(manifest_rows)
}

# Normalize a stream of KEY=VALUE lines for the drift comparison: blank the value
# of every secret key (name-only compare), keep non-secret values (so a drifted
# DEFAULT is caught), then sort. Both sides run through this before diffing.
normalize_env_kv() {
  local secrets; secrets="$(manifest_secret_keys)"
  SECRETS="$secrets" awk '
    BEGIN { n = split(ENVIRON["SECRETS"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") sec[a[i]] = 1 }
    { eq = index($0, "="); k = substr($0, 1, eq - 1); if (k in sec) print k "="; else print }
  ' | sort -u
}

# --- doctor ---
cmd_doctor() {
  env_anchor_prime   # resolve the anchor ONCE; every later subshell inherits it
  local env_example=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) DOMAIN="${2:-}"; shift 2 ;;
      --domain=*) DOMAIN="${1#*=}"; shift ;;
      --env-example) env_example="${2:-}"; shift 2 ;;
      --env-example=*) env_example="${1#*=}"; shift ;;
      -h|--help) sed -n "$USAGE_LINES" "$0"; return 0 ;;
      *) echo "env doctor: unknown flag '$1'" >&2; return 1 ;;
    esac
  done

  # A manifest that yields no rows is a broken setup, not a clean bill of health — the
  # doctor would otherwise print a header and exit 0 having verified nothing at all.
  if [ -z "$(manifest_rows 2>/dev/null)" ]; then
    printf "${BOLD}=== $DOMAIN credentials ===${NC}\n"
    fail "manifest" "no credential rows for domain '$DOMAIN' (looked in $(env_manifest_path "$DOMAIN")) — nothing was checked"
    printf "${BOLD}===${NC} ${GREEN}%d PASS${NC} | ${YELLOW}%d WARN${NC} | ${RED}%d FAIL${NC}\n" "$PASSES" "$WARNS" "$FAILS"
    return 1
  fi
  printf "${BOLD}=== $DOMAIN credentials ===${NC}\n"
  # ONE line about the anchor, not one per credential. `key_present` maps a non-zero
  # resolver return to "missing", so a bare throw would render every dotfile-backed row
  # as a FAIL — a false red on the one command whose whole job is to be trusted.
  local anchor="" no_anchor=0
  if anchor="$(env_anchor_dir 2>/dev/null)"; then
    note "anchor" "$anchor"
  else
    no_anchor=1
    fail "no session anchor" "engine env resolves credentials relative to the current session's project root, and there is no session here — run inside one (engine session activate <path>). Checks that do not read the project still ran below."
  fi
  local key service required secret default dotfile how check arg src sname sfield sregion sprofile rc
  while IFS=$'\037' read -r key service required secret default dotfile how check arg src sname sfield sregion sprofile; do
    key_present "$key" "$dotfile" "$check" "$arg"; rc=$?
    if [ "$rc" -eq 3 ] || { [ "$no_anchor" -eq 1 ] && [ "$check" = "file-key" ]; }; then
      # Distinct from "missing": we did not look, so we do not know.
      note "$key" "not checked (no session anchor)"
      continue
    fi
    if [ "$rc" -eq 5 ]; then
      # Severity follows `required`, as every other miss does. A lapsed HUMAN profile is
      # expected and routine, so on a triage row this warns rather than blocking.
      report_miss "$required" "$key" "is set to '${!key:-?}', but that profile does not authenticate — the session has expired or the profile is gone. Run 'aws login' (an agent profile never lapses; a human one does). ($service)"
      continue
    fi
    if [ "$rc" -eq 4 ]; then
      # PRESENT BUT A STAND-IN. Reporting this green would mean the doctor's whole
      # output stops being evidence: the row is set, and set to something that cannot work.
      # Severity follows `required`, exactly as a miss does: a placeholder IS a miss that
      # happens to occupy the line, so a `req` row holding one must block, not warn.
      report_miss "$required" "$key" "holds a PLACEHOLDER value, not a real credential — it is present but cannot work. Replace it, then re-run. ($service)"
      continue
    fi
    if [ "$rc" -eq 0 ]; then
      case "$check" in
        note) note "$key" "$how" ;;
        *)    pass "$key" "$service" ;;
      esac
      continue
    fi
    if [ "$rc" -eq 2 ]; then
      # ⚠️ REVERSAL (5/3): an unverifiable REQUIRED server now BLOCKS. "We could not
      # check" is not "it is fine", and reporting the second is how a wave reaches
      # Phase 5 before discovering it cannot write. Severity still follows `required`,
      # so an optional server only warns. Accepted cost: a `claude mcp list` format
      # drift hard-blocks until the parser is patched.
      report_miss "$required" "$key" "cannot verify $arg — $(mcp_cause_hint). Run /mcp in Claude Code to check it. ($how)"
      continue
    fi
    # Seed a missing non-secret default into its dotfile, then it is present.
    # A present-but-empty KEY= line is filled in place — never duplicated.
    if [ "$check" = "file-key" ] && [ "$secret" != "true" ] && [ -n "$default" ] && [ -n "$dotfile" ]; then
      local target
      if target="$(locate_key_line "$key" "$dotfile")"; then
        fill_env_key "$target" "$key" "$default" && seed "$key" "filled empty default '$default' → $target" \
          || warn "$key" "could not fill empty default in $target — $how"
      else
        local newfile; newfile="$(env_anchored_path "$dotfile")" || newfile=""
        if [ -n "$newfile" ] && printf '%s=%s\n' "$key" "$default" >> "$newfile"; then
          seed "$key" "seeded default '$default' → $newfile"
        else
          warn "$key" "could not seed default into ${newfile:-$dotfile} — $how"
        fi
      fi
      continue
    fi
    report_miss "$required" "$key" "$how"
  done < <(manifest_rows)

  # A probe that ran without a bound is a REPORTED condition, not a silent one — on a
  # stock mac neither `timeout` nor `gtimeout` exists, which is exactly the fresh machine
  # this onboarding serves.
  if [ -n "${MCP_UNBOUNDED:-}" ]; then
    warn "mcp probe" "neither timeout nor gtimeout is installed, so the MCP probe ran UNBOUNDED — install coreutils to bound it"
  fi

  # --- AWS agent profile (only for a domain that declares it) ---
  if manifest_rows 2>/dev/null | cut -d"$(printf '\037')" -f1 | grep -qx 'FINCH_AGENT_AWS_PROFILE'; then
    check_aws_agent_profile
  fi

  # --- .env.example ↔ manifest agreement (non-fatal drift check) ---
  [ -z "$env_example" ] && [ -f "./.env.example" ] && env_example="./.env.example"
  if [ -n "$env_example" ] && [ -f "$env_example" ]; then
    printf "${BOLD}=== .env.example agreement ===${NC}\n"
    local expected committed
    expected="$(gen_env_example | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' | normalize_env_kv)"
    committed="$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_example" | normalize_env_kv)"
    if [ "$committed" = "$expected" ]; then
      pass ".env.example" "matches the manifest (keys + non-secret defaults)"
    else
      warn ".env.example" "DRIFT from manifest — regenerate with 'engine env env-example --domain $DOMAIN > $env_example'"
      diff <(printf '%s\n' "$expected") <(printf '%s\n' "$committed") | sed 's/^/        /'
    fi
  fi

  # --- Summary ---
  # ⚠️ A SEAM-INFLUENCED RUN MUST NEVER LOOK GREEN. The seams are settable by anyone and
  # `Bash(engine *)` is blanket-allowed, so an unmarked green here would be a bypass of
  # the very gate Phase 0 relies on.
  # A cached MCP verdict is still a verdict about a moment that has passed. Say so, so a
  # green nobody re-probed cannot be mistaken for one that was just checked.
  if [ -n "${MCP_CACHE_AGE:-}" ]; then
    printf "${CYAN}note:${NC} MCP state was read from cache (%ss old, TTL %ss). Re-run with ENV_MCP_NO_CACHE=1 to probe live.\n" \
      "$MCP_CACHE_AGE" "${ENV_MCP_CACHE_TTL:-300}"
  fi
  local _seams; _seams="$(env_active_seams)"
  if [ -n "$_seams" ]; then
    printf "${YELLOW}⚠️  SEAM-INFLUENCED RUN — this result was produced with test seams set:%s${NC}\n" "$_seams"
    printf "${YELLOW}    It is NOT a verification of your real setup. Re-run with those unset.${NC}\n"
  fi
  printf "${BOLD}===${NC} "
  printf "${GREEN}%d PASS${NC} | ${YELLOW}%d WARN${NC} | " "$PASSES" "$WARNS"
  if [ "$FAILS" -gt 0 ]; then printf "${RED}%d FAIL${NC}\n" "$FAILS"; else printf "${GREEN}%d FAIL${NC}\n" "$FAILS"; fi

  # The structural gap this scaffolding cannot close: Linear/Notion MCP writes need
  # interactive OAuth, so a headless / cron wave can READ a project but never record the
  # outcome (save_comment / save_status_update are MCP-only). Surface it every run.
  printf "${CYAN}note:${NC} MCP writes (Linear, Notion) require an interactive OAuth session — headless/cron waves cannot post comments, status updates, or documents.\n"

  [ "$FAILS" -eq 0 ]
}

# ── 5/2: the AWS agent-profile check ──────────────────────────────────────────
#
# THREE checks, because they need three different actions:
#   1. the profile exists in ~/.aws/credentials   → install the delivered key
#   2. it has NO `login_session` in ~/.aws/config → remove it; that is the expiry trap
#   3. sts authenticates under it                 → the key is live, not revoked
#
# Unconditional for a domain that DECLARES AWS: no "skip it when everything already
# resolves" shortcut — that was explicitly rejected. But a domain with no AWS row is
# never blocked on AWS, for the same reason SLACK_INTAKE_TOKEN is not a core row.
#
# ⚠️ The fix message says `aws login`, never `aws sso login` (there is no SSO on this
# account) — and it deliberately does NOT point a NEWCOMER at `aws login`: that is the
# human MFA flow, and it is precisely what creates the expiring session.
check_aws_agent_profile() {
  # Split declarations deliberately: in one `local a=… b="$a/…"` statement bash 3.2
  # declares every name (unset) before assigning, so `$a` on the same line trips `set -u`.
  local home="${ENV_AWS_HOME:-$HOME}"
  local profile="" creds="" conf=""
  creds="$home/.aws/credentials"; conf="$home/.aws/config"

  profile="$(resolve_env_key FINCH_AGENT_AWS_PROFILE 2>/dev/null)" || profile=""
  if [ -z "$profile" ]; then
    fail "AWS agent profile" "FINCH_AGENT_AWS_PROFILE is not set — install your delivered key with 'engine env setup --aws-key <path>', or self-provision with 'engine env provision --person <you> --tier <triage|member>'"
    return 1
  fi

  if [ ! -f "$creds" ] || ! grep -qE "^\[$profile\]" "$creds" 2>/dev/null; then
    fail "AWS agent profile" "profile [$profile] is not in $creds — install your delivered key with 'engine env setup --aws-key <path>' (it writes the right shape; hand-copying the [default] block is what causes daily expiry)"
    return 1
  fi

  # The expiry trap. `login_session` is opt-in PER PROFILE and is what makes a profile
  # expire and demand MFA. An agent profile must have no ~/.aws/config block at all.
  if [ -f "$conf" ] && awk -v p="$profile" '
        $0 ~ "^\\[profile " p "\\]" || $0 ~ "^\\[" p "\\]" { inp=1; next }
        /^\[/ { inp=0 }
        inp && /login_session/ { found=1 }
        END { exit !found }' "$conf" 2>/dev/null; then
    fail "AWS agent profile" "[$profile] has a login_session entry in $conf — that makes the agent key EXPIRE and prompt for MFA. Delete that config block; the profile needs no config entry at all."
    return 1
  fi

  local arn=""
  if [ -n "${ENV_STS_ARN+set}" ]; then
    echo "env: ⚠️  TEST SEAM ACTIVE — ENV_STS_ARN is set (no AWS call was made)" >&2
    arn="$ENV_STS_ARN"
  elif command -v aws >/dev/null 2>&1; then
    # Through the cache: this single call was the doctor's largest remaining cost on a
    # machine where spawning a process is expensive. A success is remembered briefly; a
    # failure never is, because a revoked key must surface on the next run.
    arn="$(_sts_probe_cached "$profile" 2>/dev/null || true)"
  fi
  if [ -z "$arn" ]; then
    fail "AWS agent profile" "[$profile] exists but does not authenticate — the key is wrong or has been revoked. Ask for a fresh one and install it with 'engine env setup --aws-key <path>'. (If this is your HUMAN profile whose session lapsed, that one is fixed with 'aws login' — but an agent profile never lapses, so this is not that.)"
    return 1
  fi
  pass "AWS agent profile" "[$profile] → $arn"
  return 0
}

# ── agent-profile primitives ──────────────────────────────────────────────────
#
# Shared by `setup --aws-key` (a key minted FOR you and delivered) and `provision
# --apply` (a key you mint yourself). Both end in the same place, so they share one
# implementation rather than two that drift.
#
# ⚠️ NEITHER writes ~/.aws/config. The ABSENCE of a config block is the mechanism: no
# block means no `login_session`, which is what makes an agent profile never expire and
# never prompt for MFA.

_agent_profile_exists() {
  local profile="$1" home="${ENV_AWS_HOME:-$HOME}"
  [ -f "$home/.aws/credentials" ] && grep -qE "^\[$profile\]" "$home/.aws/credentials"
}

_agent_profile_write() {
  local profile="$1" akid="$2" secret="$3" home="${ENV_AWS_HOME:-$HOME}"
  local creds="$home/.aws/credentials"
  mkdir -p "$home/.aws" || return 1
  local before=""; [ -f "$creds" ] && before="$(cat "$creds")"
  { [ -n "$before" ] && printf '%s\n' "$before"
    printf '[%s]\naws_access_key_id = %s\naws_secret_access_key = %s\n' "$profile" "$akid" "$secret"; } > "$creds.tmp" || return 1
  chmod 600 "$creds.tmp" 2>/dev/null
  mv "$creds.tmp" "$creds" || return 1
  chmod 600 "$creds" 2>/dev/null
  return 0
}

_agent_profile_remove() {
  # Undoes a write. A profile that never authenticated must not be left behind — the
  # operator would read it as installed and the failure would resurface days later.
  local profile="$1" home="${ENV_AWS_HOME:-$HOME}" creds
  creds="$home/.aws/credentials"
  [ -f "$creds" ] || return 0
  awk -v p="[$profile]" '$0==p{skip=1;next} /^\[/{skip=0} !skip' "$creds" > "$creds.tmp" \
    && mv "$creds.tmp" "$creds"
  chmod 600 "$creds" 2>/dev/null
  return 0
}

_agent_profile_verify() {
  # → caller ARN on stdout; non-zero when it never authenticated. A freshly minted key
  # is eventually consistent in IAM, so ONE call reports a working key as broken —
  # hence the retry, which callers minting a key pass a count for.
  local profile="$1" tries="${2:-1}" arn="" i=0
  if [ -n "${ENV_STS_ARN+set}" ]; then
    echo "env: ⚠️  TEST SEAM ACTIVE — ENV_STS_ARN is set (no AWS call was made)" >&2
    printf '%s' "$ENV_STS_ARN"; return 0
  fi
  command -v aws >/dev/null 2>&1 || return 1
  while [ "$i" -lt "$tries" ]; do
    arn="$(AWS_PROFILE="$profile" aws sts get-caller-identity --profile "$profile" --query Arn --output text 2>/dev/null || true)"
    [ -n "$arn" ] && { printf '%s' "$arn"; return 0; }
    i=$((i + 1))
    [ "$i" -lt "$tries" ] && sleep 2
  done
  return 1
}

# ── _sts_probe_cached <profile> ───────────────────────────────────────────────
#
# An `aws sts` call is a process spawn plus a network round trip — on a machine that
# scans every exec it measured 4.5s, which alone would keep the doctor off a skill
# startup path. A session's validity does not change second to second, so a SUCCESS is
# remembered briefly.
#
# ⚠️ Success only, and only in the DOCTOR. A failure is never cached: an expired session
# is the thing this is here to notice, and a sticky failure would keep reporting one
# after `aws login` fixed it. Provisioning and key installation always probe live —
# there, a cached yes about a rotated key would be a wrong answer with consequences.
_sts_probe_cached() {
  local profile="$1" ttl="${ENV_STS_CACHE_TTL:-300}" cdir cfile now mtime age
  if [ -n "${ENV_STS_ARN+set}" ]; then printf '%s' "$ENV_STS_ARN"; return 0; fi
  command -v aws >/dev/null 2>&1 || return 1
  cdir="${XDG_CACHE_HOME:-$HOME/.cache}/engine"
  mkdir -p "$cdir" 2>/dev/null && cfile="$cdir/sts-${profile//[^A-Za-z0-9_.-]/_}"
  if [ -n "$cfile" ] && [ -z "${ENV_STS_NO_CACHE:-}" ] && [ -f "$cfile" ] && [ "$ttl" -gt 0 ] 2>/dev/null; then
    now="$(date +%s)"
    mtime="$(stat -f %m "$cfile" 2>/dev/null || stat -c %Y "$cfile" 2>/dev/null || echo 0)"
    age=$(( now - mtime ))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$ttl" ]; then
      local cached; cached="$(cat "$cfile" 2>/dev/null)"
      [ -n "$cached" ] && { printf '%s' "$cached"; return 0; }
    fi
  fi
  local arn
  arn="$(AWS_PROFILE="$profile" aws sts get-caller-identity --profile "$profile" \
         --query Arn --output text 2>/dev/null || true)"
  [ -n "$arn" ] || return 1
  [ -n "$cfile" ] && ( umask 077; printf '%s' "$arn" > "$cfile" ) 2>/dev/null || true
  printf '%s' "$arn"
  return 0
}

_agent_key_verify_env() {
  # → caller ARN on stdout. Verifies a key through the ENVIRONMENT, touching no file.
  # Installing a key in order to check it is what silently left another person's
  # credential in the provisioner's ~/.aws/credentials.
  local akid="$1" secret="$2" tries="${3:-1}" arn="" i=0
  if [ -n "${ENV_STS_ARN+set}" ]; then
    echo "env: ⚠️  TEST SEAM ACTIVE — ENV_STS_ARN is set (no AWS call was made)" >&2
    printf '%s' "$ENV_STS_ARN"; return 0
  fi
  command -v aws >/dev/null 2>&1 || return 1
  while [ "$i" -lt "$tries" ]; do
    arn="$(AWS_ACCESS_KEY_ID="$akid" AWS_SECRET_ACCESS_KEY="$secret" \
           AWS_SESSION_TOKEN="" AWS_PROFILE="" \
           aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)"
    [ -n "$arn" ] && { printf '%s' "$arn"; return 0; }
    i=$((i + 1))
    [ "$i" -lt "$tries" ] && sleep 2
  done
  return 1
}

_agent_key_deliver() {
  # The SENDER half of the delivery pair. `setup --aws-key` has always been able to
  # RECEIVE a delivered credentials file, validate it, install it and shred it — but
  # nothing produced one, so provisioning for someone else had nowhere to put the key
  # except the provisioner's own machine.
  local user="$1" akid="$2" secret="$3" out="$4"
  [ -n "$out" ] || out="$HOME/${user}.credentials"
  if [ -e "$out" ]; then
    echo "env provision: $out already exists — an undelivered key may be sitting there. Move it aside, then re-run." >&2
    return 1
  fi
  ( umask 077; printf '[%s]\naws_access_key_id = %s\naws_secret_access_key = %s\n' \
      "$user" "$akid" "$secret" > "$out" ) || return 1
  chmod 600 "$out" 2>/dev/null
  printf '%s' "$out"
  return 0
}

_agent_profile_record() {
  # The profile NAME, never the key — no credential material enters the engine's storage.
  local profile="$1" target
  target="$(env_anchored_path ".env.local")" || target=""
  [ -n "$target" ] || return 0
  if grep -qE '^[[:space:]]*(export[[:space:]]+)?FINCH_AGENT_AWS_PROFILE[[:space:]]*=' "$target" 2>/dev/null; then
    fill_env_key "$target" FINCH_AGENT_AWS_PROFILE "$profile"
  else
    printf 'FINCH_AGENT_AWS_PROFILE=%s\n' "$profile" >> "$target"
  fi
  printf "  ${GREEN}ok${NC}    recorded FINCH_AGENT_AWS_PROFILE=%s → %s\n" "$profile" "$target"
  return 0
}

# ── 5/2b: provision ───────────────────────────────────────────────────────────
#
# THE POLICY IS DERIVED FROM THE MANIFEST'S `required` TIERS, never hand-written.
# `triage` is the reader line, `boards` the publisher line — which is what makes the
# four-valued `required` vocabulary load-bearing rather than dead weight, and what stops
# policy and manifest drifting apart.
#
# ⚠️ The ARN allowlist below is a CONSTANT IN CODE, so a manifest edit cannot widen the
# grant without a code change. It is NOT a security boundary — the `engineers` group
# carries AdministratorAccess, so anyone there can hand-write any policy. Its value is
# preventing an ACCIDENTAL over-grant, and scoping the AGENT precisely because the human
# account is admin: the agent must not inherit that power.
ENV_PROVISION_ARN_ALLOWLIST='arn:aws:secretsmanager:*:*:secret:staging/finch/*|arn:aws:s3:::staging-finch-*|arn:aws:ec2:*:*:instance/*|arn:aws:ssm:*::document/AWS-StartPortForwardingSessionToRemoteHost|arn:aws:ssm:*:*:session/*'

_arn_allowed() {
  local arn="$1" pat
  local IFS='|'
  for pat in $ENV_PROVISION_ARN_ALLOWLIST; do
    case "$arn" in $pat) return 0 ;; esac
  done
  return 1
}

# ── _provision_reconcile <user> <policy-name> <desired-policy> <apply> <account> ──
#
# A policy minted yesterday does not shrink when a manifest row is removed — `provision`
# only ever wrote. Reconcile closes that: it re-derives from the manifest and compares
# against what IAM actually holds.
#
# ⚠️ It reconciles ONE inline policy — the one this tool owns. Anything else on the user,
# inline or managed, is REPORTED AND LEFT ALONE. Silently deleting a grant someone
# attached by hand would be a worse failure than the drift it is fixing.
#
# Exit: 0 in sync (or applied), 1 drifted, 2 could not run. So a dry run is usable as a gate.
# ── _iam_user_state <user> ────────────────────────────────────────────────────
#
# → "present" | "absent" | "unauthenticated" | "error <msg>"
#
# `aws iam get-user` fails for reasons that demand opposite actions, and treating every
# failure as "absent" tells an operator whose session merely lapsed to re-provision —
# which then trips the profile-exists refusal and leaves them with two wrong answers.
_iam_user_state() {
  local user="$1" err out rc
  err="$(mktemp "${TMPDIR:-/tmp}/engine-iam-err.XXXXXX")" || { printf 'error mktemp failed'; return 0; }
  out="$(aws iam get-user --user-name "$user" 2>"$err")"; rc=$?
  if [ "$rc" -eq 0 ]; then rm -f "$err"; printf 'present'; return 0; fi
  if grep -qi 'NoSuchEntity\|cannot be found' "$err"; then rm -f "$err"; printf 'absent'; return 0; fi
  if grep -qi 'session has expired\|ExpiredToken\|Unable to locate credentials\|InvalidClientTokenId\|reauthenticate' "$err"; then
    rm -f "$err"; printf 'unauthenticated'; return 0
  fi
  printf 'error %s' "$(tr -d '\n' < "$err" | cut -c1-200)"
  rm -f "$err"
  return 0
}

_iam_state_complain() {
  # One phrasing for the two states neither caller can act on, so they cannot drift.
  local state="$1" what="$2"
  case "$state" in
    unauthenticated)
      echo "$what: your AWS session has expired — IAM cannot be read. Run 'aws login' (this is the HUMAN profile; an agent profile never lapses) and retry." >&2 ;;
    error*)
      echo "$what: could not read IAM — ${state#error }" >&2 ;;
  esac
}

_provision_reconcile() {
  local user="$1" policy_name="$2" desired="$3" apply="$4" account="$5"
  command -v aws >/dev/null 2>&1 || { echo "env provision --reconcile: the aws CLI is not on PATH." >&2; return 2; }
  command -v jq  >/dev/null 2>&1 || { echo "env provision --reconcile: jq is not on PATH." >&2; return 2; }

  local state; state="$(_iam_user_state "$user")"
  case "$state" in
    present) ;;
    absent)
      echo "env provision --reconcile: IAM user $user does not exist — there is nothing to reconcile. Provision it first with --tier <tier> --apply." >&2
      return 2 ;;
    *) _iam_state_complain "$state" "env provision --reconcile"; return 2 ;;
  esac

  local live=""
  live="$(aws iam get-user-policy --user-name "$user" --policy-name "$policy_name" \
          --query 'PolicyDocument' --output json 2>/dev/null)" || live=""

  # Normalise BOTH sides before comparing. Statement order and key order are not
  # semantics, and IAM does not preserve either — without this every reconcile would
  # report drift that is not there, and the command would be ignored within a week.
  local canon='{Version:"2012-10-17", Statement: ((.Statement // []) | sort_by(.Sid // ""))}'
  local d_norm l_norm
  d_norm="$(printf '%s' "$desired" | jq -S "$canon" 2>/dev/null)" || d_norm=""
  [ -n "$d_norm" ] || { echo "env provision --reconcile: could not read the derived policy." >&2; return 2; }
  if [ -n "$live" ]; then
    l_norm="$(printf '%s' "$live" | jq -S "$canon" 2>/dev/null)" || l_norm=""
  fi

  printf "${BOLD}=== reconcile %s / %s ===${NC}\n" "$user" "$policy_name"

  local drift=0
  if [ -z "$l_norm" ]; then
    printf "  ${YELLOW}absent${NC}   the policy is not attached at all — every statement below is missing\n"
    drift=1
    printf '%s' "$d_norm" | jq -r '.Statement[] | "  + " + (.Sid // "(no Sid)")'
  elif [ "$d_norm" = "$l_norm" ]; then
    printf "  ${GREEN}in sync${NC}  the attached policy matches what the manifest derives\n"
  else
    drift=1
    local sid
    while IFS= read -r sid; do
      [ -n "$sid" ] || continue
      local d_stmt l_stmt
      d_stmt="$(printf '%s' "$d_norm" | jq -S --arg s "$sid" '.Statement[] | select((.Sid // "") == $s)')"
      l_stmt="$(printf '%s' "$l_norm" | jq -S --arg s "$sid" '.Statement[] | select((.Sid // "") == $s)')"
      if   [ -z "$l_stmt" ]; then printf "  ${YELLOW}+ add${NC}     %s\n" "$sid"
      elif [ -z "$d_stmt" ]; then printf "  ${YELLOW}- remove${NC}  %s — the manifest no longer derives it\n" "$sid"
      elif [ "$d_stmt" != "$l_stmt" ]; then printf "  ${YELLOW}~ change${NC}  %s\n" "$sid"
      fi
    done < <( { printf '%s' "$d_norm" | jq -r '.Statement[].Sid // "(no Sid)"'
                printf '%s' "$l_norm" | jq -r '.Statement[].Sid // "(no Sid)"'; } | sort -u )
  fi

  # Everything else on the user is surfaced, never touched. An operator who cannot see
  # a hand-attached grant cannot reason about what the agent can actually do.
  local other stale=0
  other="$(aws iam list-user-policies --user-name "$user" --output json 2>/dev/null \
           | jq -r --arg p "$policy_name" '(.PolicyNames // [])[] | select(. != $p)' 2>/dev/null)"
  while IFS= read -r other_name; do
    [ -n "$other_name" ] || continue
    case "$other_name" in
      "$policy_name"-*)
        # OURS, from when the tier was part of the name. Not unmanaged — but still not
        # deleted here: this command does not remove grants, so it names the one command
        # that does and leaves the decision with a human.
        stale=1
        printf "  ${YELLOW}STALE${NC}    inline policy '%s' is an OLD policy of this tool, from when the tier was part of the name.\n" "$other_name"
        printf "           It is still in force and AWS UNIONS inline policies, so it keeps granting whatever it grants.\n"
        printf "           Remove it by hand:  aws iam delete-user-policy --user-name %s --policy-name %s\n" "$user" "$other_name" ;;
      *)
        printf "  ${CYAN}unmanaged${NC}  inline policy '%s' — reported, never modified\n" "$other_name" ;;
    esac
  done <<< "$other"
  other="$(aws iam list-attached-user-policies --user-name "$user" --output json 2>/dev/null \
           | jq -r '(.AttachedPolicies // [])[].PolicyName' 2>/dev/null)"
  while IFS= read -r other_name; do
    [ -n "$other_name" ] || continue
    printf "  ${CYAN}unmanaged${NC}  attached managed policy '%s' — reported, never modified\n" "$other_name"
  done <<< "$other"

  if [ "$drift" -eq 0 ]; then
    if [ "$stale" -eq 1 ]; then
      # The owned policy matches, but the EFFECTIVE grant is the union with the stale one.
      # Reporting "in sync" here would be the exact false green this command exists to end.
      printf "${YELLOW}not clean:${NC} the owned policy matches the manifest, but a STALE policy above is still attached — the agent's effective grant is the union of both.\n" >&2
      return 1
    fi
    [ "$apply" -eq 1 ] && printf "${BOLD}nothing to apply.${NC}\n"
    return 0
  fi
  if [ "$apply" -eq 0 ]; then
    printf "${BOLD}dry-run:${NC} nothing was changed. Re-run with --apply to make IAM match the manifest.\n"
    return 1
  fi

  printf "${BOLD}About to replace inline policy %s on %s in account %s.${NC}\n" "$policy_name" "$user" "$account"
  printf "Type the account id to confirm: "
  local typed=""
  IFS= read -r typed || typed=""
  printf "\n"
  if [ "$typed" != "$account" ]; then
    echo "env provision --reconcile: --apply requires a typed confirmation of the account id ($account). Nothing was changed." >&2
    return 1
  fi

  local pfile perr rc_put
  pfile="$(mktemp "${TMPDIR:-/tmp}/engine-reconcile-policy.XXXXXX")" || return 2
  perr="$(mktemp "${TMPDIR:-/tmp}/engine-reconcile-err.XXXXXX")" || { rm -f "$pfile"; return 2; }
  chmod 600 "$pfile" 2>/dev/null
  # COMPACT, not pretty. IAM caps the AGGREGATE inline-policy size for a user at 2048
  # bytes, and whitespace counts — pretty-printing this document costs ~530 of them,
  # which is a third of the budget spent on indentation.
  printf '%s\n' "$d_norm" | jq -c . > "$pfile" 2>/dev/null || printf '%s\n' "$d_norm" > "$pfile"
  # put-user-policy REPLACES the document wholesale, which is exactly why reconcile can
  # shrink a grant — there is no per-statement delete to get wrong.
  aws iam put-user-policy --user-name "$user" --policy-name "$policy_name" \
      --policy-document "file://$pfile" >/dev/null 2>"$perr"; rc_put=$?
  rm -f "$pfile"
  if [ "$rc_put" -ne 0 ]; then
    echo "env provision --reconcile: could not replace $policy_name. The previous policy is still in force." >&2
    # The cause, not just the failure. A swallowed AWS error sent an operator looking in
    # the wrong place three times over in this subsystem alone.
    sed 's/^/       /' "$perr" >&2
    if grep -qi 'LimitExceeded\|policy size' "$perr" 2>/dev/null; then
      echo "       This is the AGGREGATE inline-policy cap for an IAM user (2048 bytes), not the size of this one document." >&2
      [ "$stale" -eq 1 ] && echo "       A STALE policy above is still attached and counts against that budget — remove it first, then re-run." >&2
    fi
    rm -f "$perr"
    return 2
  fi
  rm -f "$perr"

  # Re-read rather than trust the write: a silent partial apply would leave the operator
  # believing a grant was removed when it was not.
  local after
  after="$(aws iam get-user-policy --user-name "$user" --policy-name "$policy_name" \
           --query 'PolicyDocument' --output json 2>/dev/null | jq -S "$canon" 2>/dev/null)"
  if [ "$after" = "$d_norm" ]; then
    printf "  ${GREEN}ok${NC}    %s now matches the manifest\n" "$policy_name"
    return 0
  fi
  echo "env provision --reconcile: wrote $policy_name but re-reading it does not match the manifest." >&2
  return 2
}

# ── _provision_clerk_account <agent-user> <email> <secret-id> ─────────────────
#
# Creates the app login and puts it straight into Secrets Manager. The person never
# types a password and never receives one: they get an AWS key by hand, and the app
# credential arrives through `engine env setup`, readable only by their own agent policy.
#
# ⚠️ The identity is created in whichever Clerk instance CLERK_SECRET_KEY points at. That
# key is not necessarily environment-scoped — where one key is shared across environments,
# an account made "for QA" can sign in to production. The instance is printed so the
# operator sees which one they are writing to.
#
# Never fails the run: the AWS half is already applied by this point, and losing it over
# an identity-provider hiccup would leave a minted key with no record of why.
_provision_clerk_account() {
  local user="$1" email="$2" secret_id="$3" region="${4:-us-east-2}"
  local key; key="$(resolve_env_key CLERK_SECRET_KEY 2>/dev/null || true)"
  if [ -z "$key" ]; then
    printf "  ${CYAN}note${NC}  no CLERK_SECRET_KEY resolves, so no app login was created. Add it and re-run, or create the account by hand.\n"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || { printf "  ${YELLOW}warn${NC}  curl is not on PATH — no app login was created.\n"; return 0; }

  # Only the instance-kind prefix (sk_test / sk_live) is ever shown. Anything longer
  # starts revealing the key itself.
  printf "  ${CYAN}clerk${NC}  creating %s in the Clerk instance for key %s…\n" "$email" "$(printf '%s' "$key" | cut -c1-7)"

  local pw
  pw="$(openssl rand -base64 30 2>/dev/null | tr -d '\n' | tr '/+=' 'xyz')" || pw=""
  [ -n "$pw" ] || { printf "  ${YELLOW}warn${NC}  could not generate a password — no app login was created.\n"; return 0; }
  pw="${pw}Aa1!"

  local body resp code
  body="$(mktemp "${TMPDIR:-/tmp}/engine-clerk-body.XXXXXX")" || return 0
  chmod 600 "$body" 2>/dev/null
  # first/last name are required by instance configuration, not by the API in general —
  # so this payload is shaped by what the instance asks for, and the error path below
  # reports `long_message`, which is where Clerk says WHICH field it wanted.
  local given family
  given="$(printf '%s' "${user%-agent}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
  family="Agent"
  jq -nc --arg e "$email" --arg p "$pw" --arg f "$given" --arg l "$family" \
     '{email_address:[$e], password:$p, skip_password_checks:true,
       first_name:$f, last_name:$l}' > "$body" 2>/dev/null
  resp="$(curl -sS -o - -w '\n%{http_code}' -X POST 'https://api.clerk.com/v1/users' \
          -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
          --data @"$body" 2>/dev/null)"
  rm -f "$body"
  code="$(printf '%s' "$resp" | tail -1)"
  resp="$(printf '%s' "$resp" | sed '$d')"

  case "$code" in
    200|201)
      printf "  ${GREEN}ok${NC}    created Clerk user %s\n" "$(printf '%s' "$resp" | jq -r '.id // "?"' 2>/dev/null)" ;;
    422)
      # Already there. Do NOT reset the password — another provisioning run, or the
      # person themselves, may already hold it, and a silent rotation locks them out.
      if printf '%s' "$resp" | grep -q 'form_identifier_exists'; then
        printf "  ${CYAN}note${NC}  a Clerk user already exists for %s — left untouched, and no password was written (rotating it would lock out whoever holds the current one).\n" "$email"
        return 0
      fi
      printf "  ${YELLOW}warn${NC}  Clerk refused the request (422): %s\n" "$(printf '%s' "$resp" | jq -r '[.errors[]? | (.long_message // .message)] | join("; ") // "unknown"' 2>/dev/null)"
      return 0 ;;
    *)
      printf "  ${YELLOW}warn${NC}  Clerk returned %s — no app login was created. %s\n" "$code" \
        "$(printf '%s' "$resp" | jq -r '[.errors[]? | (.long_message // .message)] | join("; ") // ""' 2>/dev/null)"
      return 0 ;;
  esac

  # The password exists in exactly one durable place, and it is not this machine.
  local sfile
  sfile="$(mktemp "${TMPDIR:-/tmp}/engine-clerk-secret.XXXXXX")" || return 0
  chmod 600 "$sfile" 2>/dev/null
  jq -nc --arg e "$email" --arg p "$pw" '{email:$e, password:$p}' > "$sfile" 2>/dev/null
  if aws secretsmanager create-secret --region "$region" --name "$secret_id" \
       --description "Agent app login for $user (engine env provision)" \
       --secret-string "file://$sfile" >/dev/null 2>&1; then
    printf "  ${GREEN}ok${NC}    wrote the app login to %s\n" "$secret_id"
  elif aws secretsmanager put-secret-value --region "$region" --secret-id "$secret_id" \
       --secret-string "file://$sfile" >/dev/null 2>&1; then
    printf "  ${GREEN}ok${NC}    updated the app login at %s\n" "$secret_id"
  else
    printf "  ${RED}warn${NC}  the Clerk user was created but its password could NOT be stored at %s.\n" "$secret_id" >&2
    printf "           Nobody can retrieve it — delete the Clerk user and re-run rather than leaving an unusable account.\n" >&2
  fi
  rm -f "$sfile"
  pw=""
  return 0
}

cmd_provision() {
  local person="" tier="" apply=0 account="" reconcile=0 out="" email="" want_clerk=1 clerk_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --person) person="${2:-}"; shift 2 ;;
      --person=*) person="${1#*=}"; shift ;;
      --tier) tier="${2:-}"; shift 2 ;;
      --tier=*) tier="${1#*=}"; shift ;;
      --account) account="${2:-}"; shift 2 ;;
      --account=*) account="${1#*=}"; shift ;;
      --domain) DOMAIN="${2:-}"; shift 2 ;;
      --apply) apply=1; shift ;;
      --reconcile) reconcile=1; shift ;;
      --out) out="${2:-}"; shift 2 ;;
      --out=*) out="${1#*=}"; shift ;;
      --email) email="${2:-}"; shift 2 ;;
      --email=*) email="${1#*=}"; shift ;;
      --no-clerk) want_clerk=0; shift ;;
      --clerk-only) clerk_only=1; shift ;;
      -h|--help) sed -n "$USAGE_LINES" "$0"; return 0 ;;
      *) echo "env provision: unknown flag '$1'" >&2; return 1 ;;
    esac
  done

  # A seam makes a real IAM mutation run against faked inputs, and `Bash(engine *)` is
  # blanket-allowed. Refuse outright — not "warn", not "only for --apply".
  local seams; seams="$(env_active_seams)"
  if [ -n "$seams" ]; then
    echo "env provision: refusing to run with test seams set:$seams" >&2
    echo "               provision mints real IAM principals; it must never run against faked inputs." >&2
    return 1
  fi

  case "$tier" in
    triage|member) ;;
    "") echo "env provision: --tier <triage|member> is required (member = the normal tier: read the DB secret, tunnel, AND publish boards; triage = the reduced one, no publishing)" >&2; return 1 ;;
    *)  echo "env provision: unknown tier '$tier' — use member or triage. ('engineer' was renamed: publishing a board is not an engineering act, and everyone who triages needs it.)" >&2; return 1 ;;
  esac

  person="$(env_infer_person "$person")" || return 1
  local user="${person}-agent"

  if [ -z "$account" ]; then
    command -v aws >/dev/null 2>&1 && account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  fi
  [ -n "$account" ] || { echo "env provision: cannot determine the AWS account id — pass --account <id>" >&2; return 1; }

  # ---- derive resources FROM THE MANIFEST ----
  local key service required secret default dotfile how check arg src sname sfield sregion sprofile
  local db_secret="" region="" bucket="" prefix="" bastion_tag="" login_secret=""
  local state_prefix="" events_prefix=""
  while IFS=$'\037' read -r key service required secret default dotfile how check arg src sname sfield sregion sprofile; do
    case "$key" in
      FINCH_DB_RO_SECRET) db_secret="${sname:-$default}" ;;
      FINCH_BASTION_TAG)  bastion_tag="$default" ;;
      FINCH_AGENT_APP_*)  login_secret="$sname" ;;
      AWS_REGION)         region="$default" ;;
      PROVE_S3_BUCKET)        [ "$tier" = "member" ] && bucket="$default" ;;
      PROVE_S3_PREFIX)        [ "$tier" = "member" ] && prefix="$default" ;;
      PROVE_S3_STATE_PREFIX)  [ "$tier" = "member" ] && state_prefix="$default" ;;
      PROVE_S3_EVENTS_PREFIX) [ "$tier" = "member" ] && events_prefix="$default" ;;
    esac
  done < <(manifest_rows)
  region="${region:-us-east-2}"

  # The app login on its own. Without this, the Clerk half is unreachable for anyone who
  # already has an AWS profile — the mint refuses early to avoid orphaning a key, and
  # that refusal would take the app login down with it.
  if [ "$clerk_only" -eq 1 ]; then
    [ -n "$email" ] || email="${user}@finchclaims.com"
    local target="${login_secret//<person>/$user}"
    if [ -z "$login_secret" ]; then
      echo "env provision --clerk-only: no manifest row declares the agent login secret, so there is nowhere to store the password." >&2
      return 2
    fi
    printf "${BOLD}=== app login for %s ===${NC}\n" "$user"
    printf "  email   %s\n  secret  %s\n" "$email" "$target"
    if [ "$apply" -eq 0 ]; then
      printf "${BOLD}dry-run:${NC} nothing was created. Re-run with --apply.\n"
      return 0
    fi
    printf "${BOLD}About to create an app login in the Clerk instance your CLERK_SECRET_KEY points at, and store its password in Secrets Manager.${NC}\n"
    printf "Type the account id to confirm: "
    local typed=""; IFS= read -r typed || typed=""; printf "\n"
    if [ "$typed" != "$account" ]; then
      echo "env provision --clerk-only: requires a typed confirmation of the account id ($account). Nothing was created." >&2
      return 1
    fi
    _provision_clerk_account "$user" "$email" "$target" "$region"
    return $?
  fi

  local -a stmts=() dropped=() underivable=()
  local arn
  if [ -n "$db_secret" ]; then
    arn="arn:aws:secretsmanager:${region}:${account}:secret:${db_secret}*"
    if _arn_allowed "$arn"; then
      stmts[${#stmts[@]}]="$(jq -nc --arg r "$arn" '{Sid:"ReadOnlyDbSecret",Effect:"Allow",Action:["secretsmanager:GetSecretValue"],Resource:[$r]}')"
    else
      dropped[${#dropped[@]}]="$arn"
    fi
  fi
  if [ -n "$bucket" ]; then
    # A published board is not one upload. The page lands under the board prefix; viewers
    # append events; the agent folds those into state under compare-and-swap (get the ETag,
    # put with --if-match) and deletes the event it folded. Granting only the upload made
    # the tier look like it could publish while the interactive half died on AccessDenied.
    arn="arn:aws:s3:::${bucket}/${prefix:-proofs}/*"
    if _arn_allowed "$arn"; then
      stmts[${#stmts[@]}]="$(jq -nc --arg r "$arn" '{Sid:"PublishBoards",Effect:"Allow",Action:["s3:PutObject","s3:PutObjectAcl"],Resource:[$r]}')"
    else
      dropped[${#dropped[@]}]="$arn"
    fi
    if [ -n "$state_prefix" ]; then
      arn="arn:aws:s3:::${bucket}/${state_prefix}/*"
      if _arn_allowed "$arn"; then
        stmts[${#stmts[@]}]="$(jq -nc --arg r "$arn" '{Sid:"FoldBoardState",Effect:"Allow",Action:["s3:GetObject","s3:PutObject"],Resource:[$r]}')"
      else
        dropped[${#dropped[@]}]="$arn"
      fi
    else
      underivable[${#underivable[@]}]="board state — no manifest row declares the state prefix (PROVE_S3_STATE_PREFIX), so the CAS fold cannot be granted."
    fi
    if [ -n "$events_prefix" ]; then
      # No PutObject: events are written by VIEWERS through a presigned URL, not by this
      # key. It reads each event, folds it, and deletes it.
      arn="arn:aws:s3:::${bucket}/${events_prefix}/*"
      if _arn_allowed "$arn"; then
        stmts[${#stmts[@]}]="$(jq -nc --arg r "$arn" '{Sid:"DrainBoardEvents",Effect:"Allow",Action:["s3:GetObject","s3:DeleteObject"],Resource:[$r]}')"
      else
        dropped[${#dropped[@]}]="$arn"
      fi
      # ListBucket is a BUCKET-level action — it takes the bucket ARN, not an object ARN,
      # and is confined to the event prefix by condition rather than by resource.
      arn="arn:aws:s3:::${bucket}"
      if _arn_allowed "$arn"; then
        stmts[${#stmts[@]}]="$(jq -nc --arg r "$arn" --arg p "${events_prefix}/" \
          '{Sid:"ListBoardEvents",Effect:"Allow",Action:["s3:ListBucket"],Resource:[$r],
            Condition:{StringLike:{"s3:prefix":[($p + "*")]}}}')"
      else
        dropped[${#dropped[@]}]="$arn"
      fi
    else
      underivable[${#underivable[@]}]="board events — no manifest row declares the events prefix (PROVE_S3_EVENTS_PREFIX), so the drain cannot be granted."
    fi
  fi
  # The tunnel's bastion is discovered BY TAG, so the grant CONDITIONS on that tag rather
  # than pinning an instance id that changes whenever the bastion is replaced. Both come
  # from the manifest; nothing here is hardcoded.
  if [ -n "$bastion_tag" ]; then
    arn="arn:aws:ec2:${region}:${account}:instance/*"
    if _arn_allowed "$arn"; then
      stmts[${#stmts[@]}]="$(jq -nc --arg r "$arn" --arg tag "$bastion_tag" \
        --arg doc "arn:aws:ssm:${region}::document/AWS-StartPortForwardingSessionToRemoteHost" '
        {Sid:"TunnelToBastion",Effect:"Allow",Action:["ssm:StartSession"],Resource:[$r,$doc],
         Condition:{StringEquals:{"ssm:resourceTag/Name":$tag}}}')"
      stmts[${#stmts[@]}]="$(jq -nc '{Sid:"DiscoverBastionByTag",Effect:"Allow",Action:["ec2:DescribeInstances"],Resource:["*"]}')"
      stmts[${#stmts[@]}]="$(jq -nc --arg r "arn:aws:ssm:${region}:${account}:session/*" '{Sid:"ManageOwnSession",Effect:"Allow",Action:["ssm:TerminateSession","ssm:ResumeSession"],Resource:[$r]}')"
    else
      dropped[${#dropped[@]}]="$arn"
    fi
  else
    # The guard STAYS. It is the right shape for the next gap, and --apply still refuses
    # while anything is underivable rather than minting a policy that silently under-grants.
    underivable[${#underivable[@]}]="ssm:StartSession — no manifest row declares the bastion tag (FINCH_BASTION_TAG), so the tunnel grant cannot be derived. Add the row; it is deliberately NOT hardcoded here."
  fi

  # The agent's OWN login secret — never a wildcard across everyone's. That scoping is
  # most of why per-person accounts beat a shared one.
  if [ -n "$login_secret" ]; then
    arn="arn:aws:secretsmanager:${region}:${account}:secret:${login_secret//<person>/$user}-*"
    if _arn_allowed "$arn"; then
      stmts[${#stmts[@]}]="$(jq -nc --arg r "$arn" '{Sid:"ReadOwnAgentLogin",Effect:"Allow",Action:["secretsmanager:GetSecretValue"],Resource:[$r]}')"
    else
      dropped[${#dropped[@]}]="$arn"
    fi
  fi

  local policy
  policy="$(printf '%s\n' "${stmts[@]+"${stmts[@]}"}" | jq -s '{Version:"2012-10-17", Statement: .}')"

  printf "${BOLD}=== provision %s (tier: %s, account: %s) ===${NC}\n" "$user" "$tier" "$account"
  printf "${CYAN}Policy derived from the manifest's '%s' rows:${NC}\n" "$tier"
  printf '%s\n' "$policy"
  local i=0
  while [ "$i" -lt "${#dropped[@]}" ]; do
    printf "  ${YELLOW}dropped${NC}  %s — outside the ARN allowlist in env.sh (a manifest edit cannot widen the grant)\n" "${dropped[$i]}"; i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "${#underivable[@]}" ]; do
    printf "  ${YELLOW}UNDERIVABLE${NC}  %s\n" "${underivable[$i]}"; i=$((i + 1))
  done
  printf "  ${CYAN}note${NC}  the minted profile gets NO ~/.aws/config entry — the ABSENCE of login_session is what makes an agent key never expire.\n"

  # ⚠️ THE TIER IS NOT IN THE NAME. It is CONTENT, and naming it made a downgrade
  # impossible: `engine-<domain>-engineer` and `engine-<domain>-triage` are two policies,
  # AWS unions inline policies, so reconciling downward ADDED a second grant and left the
  # S3 write in place. One name per domain means reconcile replaces one document, and a
  # downgrade shrinks by construction.
  local policy_name="engine-${DOMAIN}"

  if [ "$reconcile" -eq 1 ]; then
    if [ "${#underivable[@]}" -gt 0 ]; then
      echo "env provision --reconcile: refusing while part of the policy is UNDERIVABLE from the manifest (see above) — reconciling to a partial derivation would REMOVE a grant that is merely underived." >&2
      return 2
    fi
    _provision_reconcile "$user" "$policy_name" "$policy" "$apply" "$account"
    return $?
  fi

  if [ "$apply" -eq 0 ]; then
    printf "${BOLD}dry-run:${NC} nothing was created. Review the policy above, then re-run with --apply.\n"
    return 0
  fi

  if [ "${#underivable[@]}" -gt 0 ]; then
    echo "env provision: refusing --apply while part of the policy is UNDERIVABLE from the manifest (see above). Minting a partial policy would silently under-grant." >&2
    return 1
  fi
  # THE CONFIRMATION IS READ, NEVER FLAGGED. A `--yes`-shaped flag would make minting
  # reachable from any automated `Bash(engine *)` call, which is the same hole the seam
  # refusal above closes. A read gets EOF in that context and aborts on its own.
  printf "${BOLD}About to mint IAM user %s in account %s.${NC}\n" "$user" "$account"
  [ "$want_clerk" -eq 1 ] && printf "${BOLD}This ALSO creates an app login in the Clerk instance your CLERK_SECRET_KEY points at, and stores its password in Secrets Manager.${NC} Pass --no-clerk to skip that half.\n"
  printf "Type the account id to confirm: "
  local typed=""
  IFS= read -r typed || typed=""
  printf "\n"
  if [ "$typed" != "$account" ]; then
    echo "env provision: --apply requires a typed confirmation of the account id ($account). Nothing was created." >&2
    return 1
  fi

  command -v aws >/dev/null 2>&1 || { echo "env provision: the aws CLI is not on PATH. Nothing was created." >&2; return 1; }
  command -v jq  >/dev/null 2>&1 || { echo "env provision: jq is not on PATH. Nothing was created." >&2; return 1; }

  # Refuse BEFORE anything is minted. A key created for a profile we then decline to
  # write is an orphan credential the operator has no way to see.
  if _agent_profile_exists "$user"; then
    echo "env provision: profile [$user] already exists in ~/.aws/credentials — remove it first if you are rotating the key. Nothing was created." >&2
    return 1
  fi

  local state; state="$(_iam_user_state "$user")"
  case "$state" in
    present)
      printf "  ${CYAN}note${NC}  IAM user %s already exists — reusing it; the policy and key are applied to it.\n" "$user" ;;
    absent)
      if aws iam create-user --user-name "$user" \
           --tags "Key=managed-by,Value=engine-env-provision" "Key=tier,Value=$tier" >/dev/null 2>&1; then
        printf "  ${GREEN}ok${NC}    created IAM user %s\n" "$user"
      else
        echo "env provision: could not create IAM user $user. Nothing was created." >&2
        return 1
      fi ;;
    *)
      _iam_state_complain "$state" "env provision"
      echo "               Nothing was created." >&2
      return 1 ;;
  esac

  # The policy goes through a 0600 temp file rather than a pipe: `file://` is the only
  # form the CLI reads identically across versions, and the document is not secret but
  # is worth not leaving world-readable.
  local pfile rc_put
  pfile="$(mktemp "${TMPDIR:-/tmp}/engine-provision-policy.XXXXXX")" || return 1
  chmod 600 "$pfile" 2>/dev/null
  printf '%s\n' "$policy" > "$pfile"
  aws iam put-user-policy --user-name "$user" --policy-name "$policy_name" \
      --policy-document "file://$pfile" >/dev/null 2>&1; rc_put=$?
  rm -f "$pfile"
  if [ "$rc_put" -ne 0 ]; then
    echo "env provision: could not attach inline policy $policy_name to $user. The user exists but is UNGRANTED." >&2
    return 1
  fi
  printf "  ${GREEN}ok${NC}    attached inline policy %s\n" "$policy_name"

  # AWS caps a user at two access keys and fails the third with an error that does not
  # say so. Check first, so the operator gets the real reason.
  local nkeys
  nkeys="$(aws iam list-access-keys --user-name "$user" --query 'length(AccessKeyMetadata)' --output text 2>/dev/null || echo 0)"
  case "$nkeys" in ''|*[!0-9]*) nkeys=0 ;; esac
  if [ "$nkeys" -ge 2 ]; then
    echo "env provision: $user already holds $nkeys access keys and AWS allows 2. Delete one, then re-run." >&2
    return 1
  fi

  local keyjson akid skey
  keyjson="$(aws iam create-access-key --user-name "$user" --output json 2>/dev/null)" || keyjson=""
  akid="$(printf '%s' "$keyjson" | jq -r '.AccessKey.AccessKeyId // empty' 2>/dev/null)"
  skey="$(printf '%s' "$keyjson" | jq -r '.AccessKey.SecretAccessKey // empty' 2>/dev/null)"
  keyjson=""
  if [ -z "$akid" ] || [ -z "$skey" ]; then
    echo "env provision: could not mint an access key for $user." >&2
    return 1
  fi
  printf "  ${GREEN}ok${NC}    minted access key %s\n" "$akid"

  # VERIFY BEFORE INSTALLING, through the environment. Writing a profile in order to
  # test it means a key that never worked still lands in a file someone must clean up.
  local arn
  if ! arn="$(_agent_key_verify_env "$akid" "$skey" 6)"; then
    aws iam delete-access-key --user-name "$user" --access-key-id "$akid" >/dev/null 2>&1
    echo "env provision: the minted key for $user never authenticated. It was DELETED; the IAM user and its policy remain. Nothing was written to disk." >&2
    return 1
  fi

  if ! _agent_profile_write "$user" "$akid" "$skey"; then
    aws iam delete-access-key --user-name "$user" --access-key-id "$akid" >/dev/null 2>&1
    echo "env provision: could not write ~/.aws/credentials — the key just minted was DELETED so it cannot leak. Nothing usable was left behind." >&2
    return 1
  fi
  printf "  ${GREEN}ok${NC}    profile ${BOLD}%s${NC} authenticates as %s\n" "$user" "$arn"

  # ⚠️ RECORD THE PROFILE ONLY WHEN IT IS YOUR OWN. FINCH_AGENT_AWS_PROFILE is the
  # answer to "who am I to the engine" — writing someone else's there while provisioning
  # FOR them repoints the provisioner's own doctor, setup and secret fetches at that
  # person's identity. Retaining their key is fine; adopting it is not.
  local caller; caller="$(env_infer_person "" 2>/dev/null || true)"
  if [ -n "$caller" ] && [ "${caller}-agent" = "$user" ]; then
    _agent_profile_record "$user"
  else
    printf "  ${CYAN}note${NC}  %s is not your own agent profile, so FINCH_AGENT_AWS_PROFILE was left alone.\n" "$user"
    local dfile
    if dfile="$(_agent_key_deliver "$user" "$akid" "$skey" "$out")"; then
      printf "  ${GREEN}ok${NC}    delivery file written: ${BOLD}%s${NC} (0600)\n" "$dfile"
      printf "           Send it to them, then have them run:  engine env setup --aws-key <path>\n"
      printf "           That command validates the key, installs it, and SHREDS the file. Delete your copy once they confirm.\n"
    else
      printf "  ${YELLOW}warn${NC}  no delivery file was written — the key is installed locally as [%s] but you have nothing to send.\n" "$user"
    fi
  fi
  skey=""

  if [ "$want_clerk" -eq 1 ]; then
    [ -n "$email" ] || email="${user}@finchclaims.com"
    _provision_clerk_account "$user" "$email" "${login_secret//<person>/$user}" "$region"
  else
    printf "  ${CYAN}note${NC}  --no-clerk: no app login was created, so the agent-login secret stays as it was.\n"
  fi

  printf "${BOLD}done:${NC} %s is provisioned at the %s tier. Re-run 'engine env doctor --domain %s' to watch the FAIL clear.\n" "$user" "$tier" "$DOMAIN"
  return 0
}

# ── install_aws_key <delivered-file> [person] ─────────────────────────────────
#
# For the population that CANNOT self-provision — sales, insurance, design. They have no
# AWS account, so their key is minted for them and delivered, and `aws configure` fails
# them SILENTLY: they hand-copy the `[default]` block, inherit its `login_session`, and
# are then blocked daily by the very tool meant to help. So the engine GUARANTEES the
# shape rather than hoping for it.
#
# ⚠️ It writes ~/.aws/credentials and NEVER ~/.aws/config. That is the whole mechanism:
# `finch-base` and `prove-signer` have no config entry at all and authenticate with no
# login and no MFA. THE SAFE SHAPE IS THE ABSENCE OF A CONFIG BLOCK, not the presence of
# a correct one — so there is nothing here that could emit `login_session`.
#
# Validate → write → verify → shred, in that order. A malformed file must cost nothing
# and must NOT be shredded: it is the operator's only copy.
install_aws_key() {
  local src="$1" person="${2:-}" home="${ENV_AWS_HOME:-$HOME}"
  [ -f "$src" ] || { echo "env setup --aws-key: no such file: $src" >&2; return 1; }

  local akid secret
  akid="$(grep -E '^[[:space:]]*aws_access_key_id[[:space:]]*=' "$src" 2>/dev/null | head -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
  secret="$(grep -E '^[[:space:]]*aws_secret_access_key[[:space:]]*=' "$src" 2>/dev/null | head -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
  if [ -z "$akid" ] || [ -z "$secret" ]; then
    echo "env setup --aws-key: $src does not look like an AWS credentials file (needs aws_access_key_id and aws_secret_access_key). Nothing was written; your file was NOT removed." >&2
    return 1
  fi
  if ! printf '%s' "$akid" | grep -qE '^[A-Z0-9]{16,}$'; then
    echo "env setup --aws-key: the access key id in $src is not the expected shape. Nothing was written; your file was NOT removed." >&2
    return 1
  fi

  person="$(env_infer_person "$person")" || return 1
  local profile="${person}-agent" creds="$home/.aws/credentials"

  if _agent_profile_exists "$profile"; then
    echo "env setup --aws-key: profile [$profile] already exists in $creds — remove it first if you are rotating the key. Nothing was written." >&2
    return 1
  fi

  _agent_profile_write "$profile" "$akid" "$secret" || return 1

  # Verify BEFORE shredding — an unverified key plus a deleted source is unrecoverable.
  # One try: a DELIVERED key is minutes old at least, so IAM consistency is not in play.
  local arn
  if ! arn="$(_agent_profile_verify "$profile" 1)" || [ -z "$arn" ]; then
    echo "env setup --aws-key: wrote [$profile] but it did not authenticate. The key may be wrong or already revoked — your delivered file has been KEPT so you can retry." >&2
    return 1
  fi
  printf "  ${GREEN}ok${NC}    installed profile ${BOLD}%s${NC} — authenticates as %s\n" "$profile" "$arn"

  # No ~/.aws/config entry is created, so `login_session` cannot exist for this profile.
  if [ -f "$home/.aws/config" ] && grep -qE "^\[profile $profile\]" "$home/.aws/config"; then
    warn "$profile" "a ~/.aws/config block exists for this profile — if it carries login_session the profile WILL expire; remove it"
  fi

  _agent_profile_record "$profile"

  # Shred: the key must stop living in ~/Downloads. `rm -P` overwrites on macOS.
  rm -P "$src" 2>/dev/null || { : > "$src"; rm -f "$src"; }
  printf "  ${GREEN}ok${NC}    shredded the delivered key file (%s)\n" "$src"
  return 0
}

# --- setup ---
# RESOLVE EVERYTHING FIRST, THEN WRITE ONCE. A prompted value and a fetched one can
# fail in different ways, and a half-written .env.local is worse than an unwritten one:
# the operator cannot tell which rows landed. So nothing touches disk until every row
# has produced a value.
# ── _resolve_person_secret_name <manifest-secret-name> ────────────────────────
#
# `<person>` makes a login secret PER-PERSON: the manifest is static, the path is not.
# ⚠️ IT EXPANDS TO THE AGENT NAME (`<person>-agent`), NOT the person — provision derives
# its grant the same way, and a bare person name names a path the agent's own policy
# does not cover, so the fetch could not succeed even where the secret exists.
#
# The profile comes through the RESOLVER, never a raw env var: it is recorded in
# .env.local, which an unexported variable lookup cannot see.
_resolve_person_secret_name() {
  local sname="$1" who=""
  case "$sname" in
    *"<person>"*) ;;
    *) printf '%s' "$sname"; return 0 ;;
  esac
  who="$(resolve_env_key FINCH_AGENT_AWS_PROFILE 2>/dev/null || true)"
  if [ -z "$who" ]; then
    who="$(env_infer_person "" 2>/dev/null || true)"
    [ -n "$who" ] && who="${who}-agent"
  fi
  [ -n "$who" ] || return 1
  printf '%s' "${sname//<person>/$who}"
}

gitignore_verdict() {
  # → "ok" | "unprotected" | "no-repo".  A secret must not be written where git would
  # happily commit it; outside a repo there is nothing to commit to, so that WARNS.
  local target="$1" dir
  dir="$(dirname "$target")"
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf 'no-repo'; return 0; }
  if git -C "$dir" check-ignore -q "$target" 2>/dev/null; then printf 'ok'; else printf 'unprotected'; fi
}

cmd_setup() {
  env_anchor_prime   # resolve the anchor ONCE; every later subshell inherits it
  local dry=0 aws_key="" person="" domain_given=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) DOMAIN="${2:-}"; domain_given=1; shift 2 ;;
      --domain=*) DOMAIN="${1#*=}"; domain_given=1; shift ;;
      --aws-key) aws_key="${2:-}"; shift 2 ;;
      --aws-key=*) aws_key="${1#*=}"; shift ;;
      --person) person="${2:-}"; shift 2 ;;
      --person=*) person="${1#*=}"; shift ;;
      --non-interactive|--dry-run) dry=1; shift ;;
      -h|--help) sed -n "$USAGE_LINES" "$0"; return 0 ;;
      *) echo "env setup: unknown flag '$1'" >&2; return 1 ;;
    esac
  done
  [ -n "$aws_key" ] && { install_aws_key "$aws_key" "$person"; return $?; }

  # WITH NO --domain, WALK EVERY DOMAIN. A new teammate does not know they are an
  # "intake person", and asking them to name a domain before they know what domains are
  # is the same shape of problem this command exists to remove.
  #
  # ⚠️ The DOCTOR deliberately does NOT do this. Its per-domain scoping IS the guard that
  # keeps a design operator from being blocked by a Slack token an intake wave needs.
  # Setup has no such hazard: a row it cannot fill is skipped, not a gate.
  # A pinned ENV_MANIFEST means there IS exactly one manifest — every domain would
  # resolve to the same file, so walking would ask the same questions four times.
  if [ "$domain_given" -eq 0 ] && [ -z "${ENV_MANIFEST:-}" ]; then
    local d rc_all=0 rc_one failed=""
    for d in $(env_list_domains); do
      printf "${BOLD}── %s ──${NC}\n" "$d"
      # One domain's failure must not strand the others — the operator would be left
      # having set up an arbitrary prefix of their environment with no way to tell which.
      cmd_setup --domain "$d" ${dry:+--non-interactive} ${person:+--person "$person"}
      rc_one=$?
      [ "$rc_one" -eq 0 ] || { rc_all=1; failed="$failed $d"; }
      printf "\n"
    done
    if [ -n "$failed" ]; then
      printf "${YELLOW}incomplete:${NC} these domains did not finish:%s — re-run with --domain <name> to see why.\n" "$failed" >&2
    fi
    return "$rc_all"
  fi

  printf "${BOLD}$DOMAIN setup${NC} — writes missing SECRET credentials to their gitignored dotfile.\n"
  [ "$dry" -eq 1 ] && printf "${YELLOW}(dry-run: nothing will be written)${NC}\n"
  printf "\n"

  local key service required secret default dotfile how check arg src sname sfield sregion sprofile
  local wrote=0 val rc target newfile verdict
  local -a p_keys=() p_vals=() n=0

  # ---- PHASE 1: resolve every row. Nothing is written in this loop. ----
  # The manifest is read on fd 3 so the loop body's interactive `read -rs val`
  # reads the operator's input from stdin — not the next manifest row.
  while IFS=$'\037' read -r key service required secret default dotfile how check arg src sname sfield sregion sprofile <&3; do
    # `secret` says how SENSITIVE a value is; `source` says where it COMES FROM. A
    # non-secret row sourced from Secrets Manager still has to be fetched — the doctor
    # only seeds non-secret DEFAULTS, and an aws-secret row has none, so skipping it
    # here left the row with no writer at all.
    [ "$secret" = "true" ] || [ "$src" = "aws-secret" ] || continue
    [ "$check" = "file-key" ] || continue   # only dotfile-backed rows are wizard-writable
    if key_present "$key" "$dotfile" "$check" "$arg"; then
      printf "  ${GREEN}have${NC}  %-22s (already set)\n" "$key"
      continue
    fi
    if [ "$dry" -eq 1 ]; then
      if [ "$src" = "aws-secret" ]; then
        printf "  ${CYAN}would-fetch${NC}  %-22s ← aws-secret %s → %s\n" "$key" \
          "$(_resolve_person_secret_name "$sname" 2>/dev/null || printf '%s' "$sname")" "$dotfile"
      else
        printf "  ${CYAN}would-write${NC}  %-22s → %s\n" "$key" "$dotfile"
      fi
      printf "        how: %s\n" "$how"
      wrote=$((wrote + 1))
      continue
    fi

    if [ "$src" = "aws-secret" ]; then
      # FETCHED, never prompted — the operator cannot type a value that lives in
      # Secrets Manager, and asking them to would invite them to invent one.
      local resolved_name agent_profile
      if ! resolved_name="$(_resolve_person_secret_name "$sname")"; then
        printf "  ${RED}abort${NC}  %s needs a per-person secret path but who you are could not be determined. Nothing has been written.\n" "$key" >&2
        return 1
      fi
      printf "  ${CYAN}fetch${NC}  %-22s ← aws-secret %s\n" "$key" "$resolved_name"
      agent_profile="$(resolve_env_key FINCH_AGENT_AWS_PROFILE 2>/dev/null || true)"
      val="$(env_fetch_aws_secret "$resolved_name" "$sfield" "$sregion" "${sprofile:-$agent_profile}")"; rc=$?
      if [ "$rc" -ne 0 ]; then
        printf "  ${RED}abort${NC}  %s could not be fetched — nothing has been written.\n" "$key" >&2
        return "$rc"
      fi
    else
      printf "  ${YELLOW}missing${NC}  %-22s\n        how: %s\n" "$key" "$how"
      printf "        enter value for %s (blank to skip): " "$key"
      val=""
      read -rs val; printf "\n"
      [ -n "$val" ] || { printf "        skipped.\n"; continue; }
    fi

    # Refuse to stage a secret for a target git would commit. Checked BEFORE any write,
    # so a refusal costs nothing and leaves the file exactly as it was.
    target="$(locate_key_line "$key" "$dotfile")" || target=""
    newfile="$target"
    [ -n "$newfile" ] || newfile="$(env_anchored_path "$dotfile")" || newfile=""
    if [ -z "$newfile" ]; then
      printf "  ${RED}abort${NC}  no session anchor — cannot place %s. Nothing has been written.\n" "$key" >&2
      return 3
    fi
    verdict="$(gitignore_verdict "$newfile")"
    case "$verdict" in
      unprotected)
        printf "  ${RED}refused${NC}  %s → %s is NOT gitignored — a secret written there would be committed.\n" "$key" "$newfile" >&2
        printf "           Add it to .gitignore, then re-run. Nothing has been written.\n" >&2
        return 1 ;;
      no-repo)
        printf "  ${YELLOW}note${NC}  %s is outside a git repo — cannot verify it is ignored; proceeding.\n" "$newfile" >&2 ;;
    esac

    p_keys[$n]="$key|$newfile|$target"; p_vals[$n]="$val"; n=$((n + 1))
  done 3< <(manifest_rows)

  # ---- PHASE 2: every row resolved. Now, and only now, write. ----
  local i=0 spec k f tgt
  while [ "$i" -lt "$n" ]; do
    spec="${p_keys[$i]}"; k="${spec%%|*}"; spec="${spec#*|}"; f="${spec%%|*}"; tgt="${spec#*|}"
    # Quote on write so extract_env_key round-trips the value exactly (its read
    # strips one quote layer AFTER trimming, so surrounding/internal spaces survive).
    if [ -n "$tgt" ]; then
      # A KEY= line already exists (present-but-empty, else key_present passed and we
      # never reached here) — fill it WHERE IT IS rather than appending a duplicate.
      fill_env_key "$tgt" "$k" "\"${p_vals[$i]}\"" \
        && { printf "        wrote %s → %s (filled in place)\n" "$k" "$tgt"; wrote=$((wrote + 1)); } \
        || printf "        ${RED}failed${NC} to write %s\n" "$k"
    else
      if printf '%s=%s\n' "$k" "\"${p_vals[$i]}\"" >> "$f"; then
        printf "        wrote %s → %s\n" "$k" "$f"; wrote=$((wrote + 1))
      else
        printf "        ${RED}failed${NC} to write %s\n" "$k"
      fi
    fi
    i=$((i + 1))
  done

  printf "\n"
  if [ "$dry" -eq 1 ]; then
    printf "${BOLD}dry-run:${NC} %d secret(s) would be prompted. Run without --non-interactive to write them.\n" "$wrote"
  else
    printf "${BOLD}done:${NC} %d secret(s) written. Run 'engine env doctor --domain $DOMAIN' to verify.\n" "$wrote"
  fi
}

# --- env-example ---
cmd_env_example() {
  env_anchor_prime   # resolve the anchor ONCE; every later subshell inherits it
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) DOMAIN="${2:-}"; shift 2 ;;
      --domain=*) DOMAIN="${1#*=}"; shift ;;
      -h|--help) sed -n "$USAGE_LINES" "$0"; return 0 ;;
      *) echo "env env-example: unknown flag '$1'" >&2; return 1 ;;
    esac
  done
  gen_env_example
}

# --- resolve ---
# Answers "where does this credential come from?" without answering "what is it?".
# Walks the SAME chain resolve_env_key walks (env var → env_key_files) through the same
# extract_env_key, so the answer cannot contradict what a consumer will actually read.
cmd_resolve() {
  env_anchor_prime   # resolve the anchor ONCE; every later subshell inherits it
  local key="" show=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --show-value) show=1; shift ;;
      --domain) DOMAIN="${2:-}"; shift 2 ;;
      --domain=*) DOMAIN="${1#*=}"; shift ;;
      -h|--help) sed -n "$USAGE_LINES" "$0"; return 0 ;;
      -*) echo "env resolve: unknown flag '$1'" >&2; return 1 ;;
      *)
        [ -n "$key" ] && { echo "env resolve: one KEY at a time (got '$1' after '$key')" >&2; return 1; }
        key="$1"; shift ;;
    esac
  done
  [ -n "$key" ] || { echo "env resolve: a KEY is required — engine env resolve <KEY> [--show-value]" >&2; return 1; }
  # Guard the indirect expansion below: `${!key}` on a non-identifier is a bash error,
  # and manifest rows legitimately carry non-identifier names (MCP servers, BIN_* probes).
  case "$key" in
    [A-Za-z_]*) printf '%s' "$key" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || { echo "env resolve: '$key' is not an env-var name" >&2; return 1; } ;;
    *) echo "env resolve: '$key' is not an env-var name" >&2; return 1 ;;
  esac

  local src="" val="" f searched=""
  if [ -n "${!key:-}" ]; then
    src="environment (exported $key)"; val="${!key}"
  elif ! env_anchor_dir >/dev/null 2>&1; then
    echo "$key: no session anchor — engine env resolves credentials relative to the current session's project root; run inside an engine session (engine session activate <path>)" >&2
    return "$ENV_NO_ANCHOR_RC"
  else
    while IFS= read -r f; do
      searched="${searched:+$searched, }$f"
      if val="$(extract_env_key "$f" "$key")" && [ -n "$val" ]; then
        src="$f"
        notice_shadowed_env_key "$key" "$f" "$val"
        break
      fi
      val=""
    done < <(env_key_files)
  fi

  if [ -z "$src" ]; then
    echo "$key: not found (searched: environment, ${searched:-<no files>})" >&2
    return 1
  fi
  if [ "$show" -eq 1 ]; then printf '%s\n' "$val"; return 0; fi
  printf '%s: present (source: %s)\n' "$key" "$src"
}

# --- Dispatch ---
case "${1:-}" in
  doctor)      shift; cmd_doctor "$@" ;;
  setup)       shift; cmd_setup "$@" ;;
  env-example) shift; cmd_env_example "$@" ;;
  resolve)     shift; cmd_resolve "$@" ;;
  provision)   shift; cmd_provision "$@" ;;
  ""|-h|--help|help) sed -n "$USAGE_LINES" "$0" ;;
  *) echo "env: unknown subcommand '$1'" >&2; sed -n "$USAGE_LINES" "$0"; exit 1 ;;
esac
