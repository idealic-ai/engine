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
#   engine env doctor [--domain <name>] [--tier <consumer>] [--env-example <path>]
#                                                 Red/green preflight of every credential.
#                                                 --tier names the CONSUMER asking (intake,
#                                                 triage, boards, provisioner): only rows
#                                                 that consumer needs are evaluated, at the
#                                                 severity declared FOR it. A triage run is
#                                                 not stopped by a Slack token it never
#                                                 uses, and IS stopped by an app login it
#                                                 cannot work without. Omit it and every
#                                                 row is evaluated at its own `required`.
#                                                 Exits non-zero iff a REQUIRED cred is missing
#                                                 (so a caller can gate). Reads no API secrets;
#                                                 the only network touch is the timed
#                                                 `claude mcp list` MCP-reachability probe.
#                                                 Seeds missing non-secret defaults into their
#                                                 dotfile. --env-example asserts a committed
#                                                 .env.example agrees with the manifest.
#   engine env setup [--domain <name>] [--non-interactive] [--refresh]
#                                                 Wizard: prompt for each missing SECRET row,
#                                                 write it to its gitignored dotfile.
#                                                 --non-interactive (alias --dry-run) echoes
#                                                 what it WOULD write, writes nothing.
#                                                 --refresh re-fetches rows sourced from
#                                                 Secrets Manager even when the dotfile
#                                                 already holds a value — that copy is a
#                                                 CACHE, and a stale one is invisible since
#                                                 the doctor passes on presence, not on
#                                                 correctness. Prompted rows are never
#                                                 touched: they have no upstream, so
#                                                 rewriting one only discards what a person
#                                                 went and obtained.
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
#                                                 TWO documents: a SHARED customer-managed
#                                                 policy engine-<domain>-<tier> attached to
#                                                 every agent of that tier, plus a small
#                                                 per-user INLINE policy engine-<domain>
#                                                 carrying only the secrets that name that
#                                                 person. The shared half is what keeps a new
#                                                 grant off the 2048-byte inline budget.
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
      printf '%s' "$server_line" | grep -qiE "$MCP_UNHEALTHY_RE" && return 1
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
# The row-level "explicitly unhealthy" pattern. ONE definition, read by the verdict AND
# by the cache guard below, so the two can never disagree about what healthy means.
MCP_UNHEALTHY_RE='need.? auth|authenticat|not connected|disconnect|fail|error|unreachable|timed? ?out'
MCP_PROBE_CAUSE=""
MCP_SECONDS_PER_SERVER=8
MCP_LIST_OUT=""
MCP_UNBOUNDED=""
MCP_CACHE_AGE=""
_MCP_PROBED=""
_MCP_FS=$'\037'

# Cacheable ⇔ EVERY row is healthy. Non-empty output is a different fact: `claude mcp
# list` reports a per-row degradation — a tools-fetch timeout on an otherwise-connected
# server — in a perfectly well-formed line, and remembering that for the whole TTL keeps
# the doctor FAILing long after the server recovered. An unhealthy state is also the one
# state that changes the moment the operator goes and fixes it, so it must never be
# remembered; paying the live probe until it is green is the point.
mcp_output_cacheable() {
  [ -n "$1" ] || return 1
  printf '%s' "$1" | grep -qiE "$MCP_UNHEALTHY_RE" && return 1
  return 0
}

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
  # ⚠️ Only an ALL-HEALTHY probe is cached (`mcp_output_cacheable`). Remembering a
  # timeout would make one transient hiccup stick for the whole TTL, and the doctor
  # treats unverifiable as failing — so a cached failure would block a wave that is
  # actually fine. "The command printed something" is NOT that guarantee: it is what
  # this guard used to test, and a `Connected · tools fetch failed` row rode straight
  # through it into a five-minute FAIL.
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
      if mcp_output_cacheable "$MCP_LIST_OUT"; then
        MCP_CACHE_AGE="$cache_age"
        return 0
      fi
      # Written by an older build that cached on non-emptiness alone. Drop it and probe
      # live, so the fix heals the caches it inherits instead of waiting out their TTL.
      MCP_LIST_OUT=""; rm -f "$cache_file" 2>/dev/null || true
    fi
  fi

  MCP_LIST_OUT="$(cd "$anchor" 2>/dev/null && $t claude mcp list 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$t" ]; then MCP_PROBE_CAUSE="timed-out"; MCP_LIST_OUT=""; return 0; fi
  [ -z "$MCP_LIST_OUT" ] && MCP_PROBE_CAUSE="empty"
  if [ -n "$cache_file" ] && mcp_output_cacheable "$MCP_LIST_OUT"; then
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
# Write a non-secret manifest default into its dotfile. Prints the destination on
# stdout and returns 0 when written; returns 1 when it could not be.
#
# Shared by doctor AND setup deliberately. A non-secret row carrying a manifest default
# needs neither a prompt nor a network fetch, so whichever command runs first should be
# able to write it. It used to live only in the doctor, which meant AWS_REGION — the
# region every Secrets Manager fetch needs, since an agent profile has no ~/.aws/config —
# was written by `env doctor` and never by `env setup`, so setup's own fetches failed
# unless doctor happened to have run first.
#
# A present-but-empty KEY= line is filled IN PLACE, never duplicated, so seeding is
# idempotent.
seed_nonsecret_default() {
  local key="$1" default="$2" dotfile="$3" target newfile
  if target="$(locate_key_line "$key" "$dotfile")"; then
    fill_env_key "$target" "$key" "$default" || return 1
    printf '%s' "$target"; return 0
  fi
  newfile="$(env_anchored_path "$dotfile")" || return 1
  [ -n "$newfile" ] || return 1
  printf '%s=%s\n' "$key" "$default" >> "$newfile" || return 1
  printf '%s' "$newfile"; return 0
}

cmd_doctor() {
  env_anchor_prime   # resolve the anchor ONCE; every later subshell inherits it
  local env_example=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) DOMAIN="${2:-}"; shift 2 ;;
      --domain=*) DOMAIN="${1#*=}"; shift ;;
      --env-example) env_example="${2:-}"; shift 2 ;;
      --env-example=*) env_example="${1#*=}"; shift ;;
      --tier) ENV_ACTIVE_TIER="${2:-}"; shift 2 ;;
      --tier=*) ENV_ACTIVE_TIER="${1#*=}"; shift ;;
      -h|--help) sed -n "$USAGE_LINES" "$0"; return 0 ;;
      *) echo "env doctor: unknown flag '$1'" >&2; return 1 ;;
    esac
  done
  # The tier is a GLOBAL because manifest_rows is reached through several subshells;
  # env_manifest_rows reads it and does the filtering + severity resolution in jq.
  export ENV_ACTIVE_TIER

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
    fail "no session anchor" "engine env resolves credentials relative to the current session's project ROOT. Two things must both be true and neither is: you are in an engine session, AND you are inside a repo checkout rather than your home folder. Open the repo in Claude Code and type /do, then re-run. (Raw equivalent: engine session activate <path>, from inside the checkout.) Checks that do not read the project still ran below."
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
    # UNSET, not emptied. `AWS_PROFILE=""` makes the CLI look for a profile *named*
    # empty and fail with "The config profile () could not be found" — so verification
    # could never succeed whenever a profile was exported, which is the normal case for
    # the operator running this. The key looked dead and was deleted as a precaution.
    arn="$(env -u AWS_PROFILE -u AWS_SESSION_TOKEN \
           AWS_ACCESS_KEY_ID="$akid" AWS_SECRET_ACCESS_KEY="$secret" \
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
ENV_PROVISION_ARN_ALLOWLIST='arn:aws:secretsmanager:*:*:secret:staging/finch/*|arn:aws:s3:::staging-finch-*|arn:aws:ec2:*:*:instance/*|arn:aws:ssm:*::document/AWS-StartPortForwardingSessionToRemoteHost|arn:aws:ssm:*:*:session/*|arn:aws:rds:*:*:db:staging-finch-*'

_arn_allowed() {
  local arn="$1" pat
  local IFS='|'
  for pat in $ENV_PROVISION_ARN_ALLOWLIST; do
    case "$arn" in $pat) return 0 ;; esac
  done
  return 1
}

# IAM's two document caps. The inline one is an AGGREGATE over every inline policy on the
# user; the managed one is per document. Both are counted here on the MINIFIED document,
# which is what gets written.
ENV_PROVISION_INLINE_CAP=2048
ENV_PROVISION_MANAGED_CAP=6144

# ── _provision_policy_doc  <statement JSON, one per line, on stdin> ───────────
#
# → one policy document. MERGES unconditioned statements that share an Effect+Action
# into one, unioning their Resources. IAM caps a document's size and the four
# secretsmanager:GetSecretValue grants cost ~300 bytes in per-statement scaffolding
# alone — splitting TunnelToBastion once pushed the document to 2271 and IAM refused it.
# Semantics are identical: same Effect, same Action, no Condition on either side, so
# unioning Resources cannot widen or narrow what is allowed.
#
# ⚠️ The cost is real and is NOT free: the per-grant Sids (ReadOnlyDbSecret,
# ReadOwnAgentLogin, ReadOwnGeminiKey, ReadSharedTokens) collapse into one, so the ARNs
# become the only record of why each secret is granted. They are self-describing enough
# to carry that. Statements WITH a Condition are never merged.
#
# ⚠️ ONE function for BOTH documents. The shared managed policy and the per-person inline
# policy are merged by the same code on purpose — two copies of this jq would drift, and
# a drift here changes what an agent may do.
_provision_policy_doc() {
  local raw; raw="$(cat)"
  jq -s '
    [ .[] | select(has("Condition") | not) ]
      | group_by(.Effect + "\u0000" + (.Action | sort | join(",")))
      | map(if length == 1 then .[0]
            else { Sid: (.[0].Sid), Effect: .[0].Effect, Action: .[0].Action,
                   Resource: ([ .[].Resource[] ] | unique) }
            end)
      | . as $merged
      | { Version:"2012-10-17",
          Statement: ($merged + [ $ARGS.positional[0][] | select(has("Condition")) ]) }
    ' --jsonargs "$(printf '%s\n' "$raw" | jq -sc .)" <<< "$raw"
}

# ── _provision_doc_size <document> ────────────────────────────────────────────
# Bytes of the MINIFIED document — the form actually written to IAM. Sizing the pretty
# form would over-report by ~530 bytes and send an operator hunting for a cap problem
# that is entirely indentation.
_provision_doc_size() {
  printf '%s' "$1" | jq -c . 2>/dev/null | tr -d '\n' | wc -c | tr -d ' '
}

# ── _provision_report_size <document> <cap> <label> ───────────────────────────
# Prints the size next to its cap and RETURNS 1 when it is over. The cap failure this
# tool actually hit was discovered at PutUserPolicy, from an error naming neither the
# document nor the number — so the number is printed on every dry run, before anyone
# tries to write it.
_provision_report_size() {
  local doc="$1" cap="$2" label="$3" n
  n="$(_provision_doc_size "$doc")"
  case "$n" in ''|*[!0-9]*) printf "  ${YELLOW}size${NC}     could not measure the %s document.\n" "$label"; return 1 ;; esac
  if [ "$n" -gt "$cap" ]; then
    printf "  ${RED}OVER CAP${NC} %s is %s bytes minified against IAM's %s-byte cap — IAM will refuse it.\n" "$label" "$n" "$cap"
    return 1
  fi
  printf "  ${GREEN}size${NC}     %s bytes minified, cap %s (%s to spare)\n" "$n" "$cap" "$((cap - n))"
  return 0
}

# ── _provision_managed_arn <account> <policy-name> ────────────────────────────
_provision_managed_arn() {
  printf 'arn:aws:iam::%s:policy/%s' "$1" "$2"
}

# ── _provision_managed_sync <user> <name> <arn> <desired> <apply> <account> <domain> [confirmed] ──
#
# The SHARED half. One customer-managed policy per (domain, tier), attached to every agent
# of that tier, so a new grant costs bytes ONCE instead of once per person — the 2048-byte
# aggregate inline cap is what refused the last grant, and this is what takes the shared
# statements out of that budget entirely.
#
# ⚠️ ACCOUNT-WIDE SHARED STATE, unlike an inline policy. Two people provisioning at the
# same moment both mutate this one document. That is safe here only because the document
# is DERIVED — same manifest, same account, same tier gives byte-identical output — so
# concurrent writers converge rather than fight. The cost of a race is a wasted version,
# not a wrong grant, and the skip-when-identical below means the common case writes
# nothing at all. What a race CANNOT do is silently differ: the verify re-reads.
#
# ⚠️ IAM keeps at most FIVE versions of a managed policy and returns LimitExceeded on the
# sixth. The oldest non-default versions are pruned before a new one is created, so an
# update path that is run repeatedly does not brick itself.
#
# ⚠️ It does NOT detach anything, including a sibling tier's policy of its own name. Same
# rule the inline reconciler follows: this command does not remove grants, it names the
# command that does. A sibling left attached IS reported, and reported as drift.
#
# Exit: 0 in sync (or applied), 1 drifted, 2 could not run.
_provision_managed_sync() {
  local user="$1" name="$2" arn="$3" desired="$4" apply="$5" account="$6" domain="$7" confirmed="${8:-0}"
  command -v aws >/dev/null 2>&1 || { echo "env provision: the aws CLI is not on PATH." >&2; return 2; }
  command -v jq  >/dev/null 2>&1 || { echo "env provision: jq is not on PATH." >&2; return 2; }

  local canon='{Version:"2012-10-17", Statement: ((.Statement // []) | sort_by(.Sid // ""))}'
  local d_norm; d_norm="$(printf '%s' "$desired" | jq -S "$canon" 2>/dev/null)" || d_norm=""
  [ -n "$d_norm" ] || { echo "env provision: could not read the derived shared policy." >&2; return 2; }

  printf "${BOLD}=== shared policy %s ===${NC}\n" "$name"

  local exists=0 default_ver="" l_norm=""
  default_ver="$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null)" || default_ver=""
  case "$default_ver" in ''|None) default_ver="" ;; *) exists=1 ;; esac
  if [ "$exists" -eq 1 ]; then
    # get-policy-version returns the document URL-ENCODED on some CLI/API paths and as an
    # object on others. --output json plus a jq that accepts either keeps this from being
    # a version-dependent coin flip.
    l_norm="$(aws iam get-policy-version --policy-arn "$arn" --version-id "$default_ver" \
              --query 'PolicyVersion.Document' --output json 2>/dev/null \
              | jq -S 'if type == "string" then fromjson else . end | '"$canon" 2>/dev/null)" || l_norm=""
  fi

  local drift=0
  if [ "$exists" -eq 0 ]; then
    drift=1
    printf "  ${YELLOW}absent${NC}   the shared policy does not exist yet — it would be created with %s statement(s)\n" \
      "$(printf '%s' "$d_norm" | jq -r '.Statement | length')"
  elif [ -z "$l_norm" ]; then
    drift=1
    printf "  ${YELLOW}unreadable${NC} %s exists but its default version %s could not be read — treating as drifted\n" "$name" "$default_ver"
  elif [ "$d_norm" = "$l_norm" ]; then
    printf "  ${GREEN}in sync${NC}  %s (version %s) already matches what the manifest derives — no new version would be created\n" "$name" "$default_ver"
  else
    drift=1
    local sid d_stmt l_stmt
    while IFS= read -r sid; do
      [ -n "$sid" ] || continue
      d_stmt="$(printf '%s' "$d_norm" | jq -S --arg s "$sid" '.Statement[] | select((.Sid // "") == $s)')"
      l_stmt="$(printf '%s' "$l_norm" | jq -S --arg s "$sid" '.Statement[] | select((.Sid // "") == $s)')"
      if   [ -z "$l_stmt" ]; then printf "  ${YELLOW}+ add${NC}     %s\n" "$sid"
      elif [ -z "$d_stmt" ]; then printf "  ${YELLOW}- remove${NC}  %s — the manifest no longer derives it\n" "$sid"
      elif [ "$d_stmt" != "$l_stmt" ]; then printf "  ${YELLOW}~ change${NC}  %s\n" "$sid"
      fi
    done < <( { printf '%s' "$d_norm" | jq -r '.Statement[].Sid // "(no Sid)"'
                printf '%s' "$l_norm" | jq -r '.Statement[].Sid // "(no Sid)"'; } | sort -u )
  fi

  # Attachment is a separate fact from content. A policy whose document is perfect and
  # whose attachment is missing grants nothing, and the two failures look identical from
  # the agent's side — an AccessDenied.
  local attached=0 sibling="" attached_names=""
  attached_names="$(aws iam list-attached-user-policies --user-name "$user" --output json 2>/dev/null \
                    | jq -r '(.AttachedPolicies // [])[].PolicyName' 2>/dev/null)"
  local an
  while IFS= read -r an; do
    [ -n "$an" ] || continue
    if [ "$an" = "$name" ]; then attached=1; continue; fi
    case "$an" in
      "engine-${domain}-"*) sibling="$sibling $an" ;;
    esac
  done <<< "$attached_names"

  if [ "$attached" -eq 1 ]; then
    printf "  ${GREEN}attached${NC} %s is attached to %s\n" "$name" "$user"
  else
    drift=1
    printf "  ${YELLOW}detached${NC} %s is NOT attached to %s — the shared grants are not in force for them\n" "$name" "$user"
  fi
  if [ -n "$sibling" ]; then
    drift=1
    for an in $sibling; do
      printf "  ${YELLOW}STALE${NC}    another tier's shared policy '%s' is still attached. AWS UNIONS policies, so %s keeps whatever it grants and this tier's downgrade has not happened.\n" "$an" "$an"
      printf "           Detach it by hand:  aws iam detach-user-policy --user-name %s --policy-arn %s\n" "$user" "$(_provision_managed_arn "$account" "$an")"
    done
  fi

  if [ "$drift" -eq 0 ]; then
    [ "$apply" -eq 1 ] && printf "${BOLD}shared policy: nothing to apply.${NC}\n"
    return 0
  fi
  if [ "$apply" -eq 0 ]; then
    printf "${BOLD}dry-run:${NC} the shared policy was not created, changed or attached.\n"
    return 1
  fi
  if [ -n "$sibling" ]; then
    echo "env provision: refusing to apply while another tier's shared policy is attached to $user — detach it first (command above), or the tiers union and the downgrade does not happen." >&2
    return 1
  fi

  # ⚠️ ONE GESTURE PER OPERATION, and the mint has already taken it. Asking a second time
  # here would leave a freshly created IAM user ungranted whenever the operator hesitated
  # over a prompt they had no reason to expect. --reconcile confirms here on its own,
  # because there the shared write is a distinct decision with a wider blast radius than
  # the per-user one that follows it.
  if [ "$confirmed" -ne 1 ]; then
    printf "${BOLD}About to write the SHARED policy %s in account %s. It is attached to EVERY %s agent, not just %s.${NC}\n" "$name" "$account" "${name##*-}" "$user"
    printf "Type the account id to confirm: "
    local typed=""; IFS= read -r typed || typed=""; printf "\n"
    if [ "$typed" != "$account" ]; then
      echo "env provision: writing the shared policy requires a typed confirmation of the account id ($account). Nothing was changed." >&2
      return 1
    fi
  fi

  local pfile perr rc
  pfile="$(mktemp "${TMPDIR:-/tmp}/engine-managed-policy.XXXXXX")" || return 2
  perr="$(mktemp "${TMPDIR:-/tmp}/engine-managed-err.XXXXXX")" || { rm -f "$pfile"; return 2; }
  chmod 600 "$pfile" 2>/dev/null
  printf '%s\n' "$d_norm" | jq -c . > "$pfile" 2>/dev/null || printf '%s\n' "$d_norm" > "$pfile"

  if [ "$exists" -eq 0 ]; then
    aws iam create-policy --policy-name "$name" --policy-document "file://$pfile" \
        --description "Shared grants for engine ${domain} agents. DERIVED from the credentials manifest by 'engine env provision' — edit the manifest, not this policy." \
        >/dev/null 2>"$perr"; rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "env provision: could not create the shared policy $name." >&2
      sed 's/^/       /' "$perr" >&2; rm -f "$pfile" "$perr"; return 2
    fi
    printf "  ${GREEN}ok${NC}    created shared policy %s\n" "$name"
  elif [ "$d_norm" != "$l_norm" ] || [ -z "$l_norm" ]; then
    # PRUNE BEFORE CREATING. IAM allows five versions and the create is what fails, so
    # pruning afterwards is pruning after the error. Only non-default versions are
    # deletable; the oldest go first.
    local vers v
    vers="$(aws iam list-policy-versions --policy-arn "$arn" --output json 2>/dev/null \
            | jq -r '[(.Versions // [])[] | select(.IsDefaultVersion | not)]
                     | sort_by(.CreateDate) | .[].VersionId' 2>/dev/null)"
    local nver; nver="$(printf '%s\n' "$vers" | grep -c '[^[:space:]]' || true)"
    case "$nver" in ''|*[!0-9]*) nver=0 ;; esac
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      [ "$nver" -lt 4 ] && break
      if aws iam delete-policy-version --policy-arn "$arn" --version-id "$v" >/dev/null 2>&1; then
        printf "  ${CYAN}pruned${NC}  old version %s of %s (IAM keeps five)\n" "$v" "$name"
        nver=$((nver - 1))
      else
        break
      fi
    done <<< "$vers"
    aws iam create-policy-version --policy-arn "$arn" --policy-document "file://$pfile" \
        --set-as-default >/dev/null 2>"$perr"; rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "env provision: could not update the shared policy $name. The previous version is still the default and still in force." >&2
      sed 's/^/       /' "$perr" >&2
      grep -qi 'LimitExceeded' "$perr" 2>/dev/null && echo "       IAM keeps five versions of a managed policy. Delete one: aws iam list-policy-versions --policy-arn $arn" >&2
      rm -f "$pfile" "$perr"; return 2
    fi
    printf "  ${GREEN}ok${NC}    updated shared policy %s to a new default version\n" "$name"
  fi
  rm -f "$pfile" "$perr"

  if [ "$attached" -eq 0 ]; then
    if aws iam attach-user-policy --user-name "$user" --policy-arn "$arn" >/dev/null 2>&1; then
      printf "  ${GREEN}ok${NC}    attached %s to %s\n" "$name" "$user"
    else
      echo "env provision: created or updated $name but could not attach it to $user. The shared grants are NOT in force for them." >&2
      return 2
    fi
  fi

  # Re-read rather than trust the writes. Believing an unverified apply is how the inline
  # half previously reported a grant that was not there.
  local after_ver after_doc after_attached
  after_ver="$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null)"
  after_doc="$(aws iam get-policy-version --policy-arn "$arn" --version-id "$after_ver" \
               --query 'PolicyVersion.Document' --output json 2>/dev/null \
               | jq -S 'if type == "string" then fromjson else . end | '"$canon" 2>/dev/null)"
  after_attached="$(aws iam list-attached-user-policies --user-name "$user" --output json 2>/dev/null \
                    | jq -r --arg n "$name" '[(.AttachedPolicies // [])[] | select(.PolicyName == $n)] | length' 2>/dev/null)"
  if [ "$after_doc" = "$d_norm" ] && [ "${after_attached:-0}" = "1" ]; then
    printf "  ${GREEN}ok${NC}    %s matches the manifest and is attached to %s\n" "$name" "$user"
    return 0
  fi
  echo "env provision: wrote $name but re-reading it does not match the manifest, or it is not attached." >&2
  return 2
}

# ── _provision_reconcile <user> <policy-name> <desired> <apply> <account> <owned-managed> <shared-desired> ──
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
  local user="$1" policy_name="$2" desired="$3" apply="$4" account="$5" owned_managed="${6:-}" shared_desired="${7:-}"
  # Everything the agent will still be granted after this reconcile — the shared document
  # AND the new inline one — flattened to comparable (action, resource, condition) triples.
  # A Sid is a label; this is the grant. Used to tell MOVED from REMOVED below, and to
  # answer the only question that matters: does anything in force today stop being granted.
  local carried_pairs=""
  carried_pairs="$(printf '%s\n%s\n' "$shared_desired" "$desired" | jq -sc '
      [ .[] | .Statement[] | . as $s | $s.Action[] as $a | $s.Resource[] as $r
        | {a:$a, r:$r, c:($s.Condition // null)} ] | unique' 2>/dev/null)" || carried_pairs=""
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
      elif [ -z "$d_stmt" ]; then
        # MOVED IS NOT REMOVED, and conflating the two is how an operator aborts a correct
        # migration. Every grant this tool took out of the inline document went into the
        # shared one; a statement whose every (action, resource, condition) triple is
        # carried there is reported as moved. Anything else really is going away.
        if [ -n "$carried_pairs" ] && printf '%s' "$l_stmt" | jq -e --argjson shared "$carried_pairs" '
             . as $s
             | [ $s.Action[] as $a | $s.Resource[] as $r | {a:$a, r:$r, c:($s.Condition // null)} ]
             | all(. as $p | $shared | any(. == $p))' >/dev/null 2>&1; then
          printf "  ${CYAN}→ moved${NC}   %s — every grant in it is carried by the two documents above, not lost\n" "$sid"
        else
          printf "  ${YELLOW}- remove${NC}  %s — the manifest no longer derives it\n" "$sid"
        fi
      elif [ "$d_stmt" != "$l_stmt" ]; then printf "  ${YELLOW}~ change${NC}  %s\n" "$sid"
      fi
    done < <( { printf '%s' "$d_norm" | jq -r '.Statement[].Sid // "(no Sid)"'
                printf '%s' "$l_norm" | jq -r '.Statement[].Sid // "(no Sid)"'; } | sort -u )
    # The Sid lines above are advisory — the merge pass renames statements, so a Sid
    # appearing or vanishing is not by itself a grant appearing or vanishing. THIS is the
    # safety question, asked on triples: does anything in force today stop being granted?
    # Shrinking IS sometimes the point (a manifest row went away), so this is stated, not
    # alarmed about. What it must never do is stay silent.
    local losing
    losing="$(printf '%s' "$l_norm" | jq -r --argjson carried "$carried_pairs" '
        [ .Statement[] | . as $s | $s.Action[] as $a | $s.Resource[] as $r
          | {a:$a, r:$r, c:($s.Condition // null)} ] | unique
        | map(select(. as $p | ($carried | any(. == $p)) | not))
        | .[] | "           " + .a + " on " + .r' 2>/dev/null)"
    if [ -z "$losing" ]; then
      printf "  ${GREEN}no loss${NC}  every (action, resource) in force today is still granted by the two documents above\n"
    else
      printf "  ${YELLOW}LOSING${NC}   these grants go away when this is applied:\n"
      printf '%s\n' "$losing"
    fi
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
  # The shared policy this tool owns is handled by _provision_managed_sync and is NOT
  # unmanaged — calling it that here would train an operator to ignore the one line that
  # tells them a hand-attached grant exists.
  other="$(aws iam list-attached-user-policies --user-name "$user" --output json 2>/dev/null \
           | jq -r --arg o "$owned_managed" '(.AttachedPolicies // [])[].PolicyName | select(. != $o)' 2>/dev/null)"
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
      # KEEP THE ID. The app `user` row is keyed on clerk_user_id (NOT NULL, unique), so
      # whoever creates that row needs this value — and it is returned exactly once, here.
      PROVISION_CLERK_USER_ID="$(printf '%s' "$resp" | jq -r '.id // ""' 2>/dev/null)"
      printf "  ${GREEN}ok${NC}    created Clerk user %s\n" "${PROVISION_CLERK_USER_ID:-?}"
      PROVISION_CLERK_OK=1 ;;
    422)
      # Already there. Do NOT reset the password — another provisioning run, or the
      # person themselves, may already hold it, and a silent rotation locks them out.
      if printf '%s' "$resp" | grep -q 'form_identifier_exists'; then
        printf "  ${CYAN}note${NC}  a Clerk user already exists for %s — left untouched, and no password was written (rotating it would lock out whoever holds the current one).\n" "$email"
        PROVISION_CLERK_OK=1
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
    _deliver_password_via_slack "$user" "$email"
  elif aws secretsmanager put-secret-value --region "$region" --secret-id "$secret_id" \
       --secret-string "file://$sfile" >/dev/null 2>&1; then
    printf "  ${GREEN}ok${NC}    updated the app login at %s\n" "$secret_id"
    _deliver_password_via_slack "$user" "$email"
  else
    printf "  ${RED}warn${NC}  the Clerk user was created but its password could NOT be stored at %s.\n" "$secret_id" >&2
    printf "           Nobody can retrieve it — delete the Clerk user and re-run rather than leaving an unusable account.\n" >&2
  fi
  rm -f "$sfile"
  pw=""
  return 0
}

# ── _slack_api <token> <method> [curl args...] ────────────────────────────────
# ── _agent_login_email <agent-user> ───────────────────────────────────────────
#
# PLUS, NOT DASH. `rob-agent@finchclaims.com` requires a mailbox that does not exist;
# `rob+agent@finchclaims.com` is sub-addressing and lands in Rob's existing inbox. The
# identity provider sends verification and password-reset mail, so an address nobody
# receives makes the account unrecoverable the first time it matters.
#
# The DASH form is correct everywhere it is an identifier rather than an address — the
# IAM user, the AWS profile, the Secrets Manager path — because none of those deliver
# mail and `+` reads badly in an ARN.
# ── _agent_login_local <agent-user> ───────────────────────────────────────────
#
# The local-part of the login identity: `yarik-agent` → `yarik+agent`. The agent-login
# SECRET is keyed on this rather than on the identifier, because what it holds is a
# login. Keeping the two spellings straight is the whole point: the IAM user, the AWS
# profile and the ARN are identifiers and stay dashed; anything naming the login —
# the address and the secret that holds it — is plus-addressed.
_agent_login_local() {
  printf '%s+agent' "${1%-agent}"
}

_agent_login_email() {
  printf '%s@finchclaims.com' "$(_agent_login_local "$1")"
}

_slack_api() {
  local token="$1" method="$2"; shift 2
  curl -sS "https://slack.com/api/${method}" -H "Authorization: Bearer $token" "$@" 2>/dev/null
}

# ── _deliver_via_slack <agent-user> <person> <key-file> ───────────────────────
#
# Hands the key to its owner over a Slack DM: a short message saying what to run, the
# key as a file, and the setup guide.
#
# ⚠️ THIS PUTS A CREDENTIAL IN CHAT HISTORY. A file attachment is not a pasted secret,
# but it is still retained by workspace policy, downloadable by anyone with access to
# the conversation, and present in exports. It is an accepted trade for a key that is
# narrowly scoped, revocable per person, and shredded by the receiving command — not a
# general licence to send secrets over Slack.
#
# Never fails the run. By the time this is reached the account exists and the key file
# is written; losing that over a chat API would be the worst possible trade.
# ── _slack_dm_channel <person> ────────────────────────────────────────────────
#
# Resolves ONE person to ONE open DM channel id on stdout, empty on failure. Extracted
# because the key and the app password are sent as SEPARATE messages (so either can be
# deleted without taking the other with it) and a second copy of this lookup would mean
# a second interactive prompt for the same human in the same run.
#
# MEMOISED per person: the fallback prompt reads stdin, and asking twice for one delivery
# is how an operator ends up answering the second one blind — the second read gets EOF,
# resolves to empty, and SILENTLY SKIPS the send. Measured: that is exactly what happened.
#
# ⚠️ THE RESULT COMES BACK IN `ENGINE_DM_CHANNEL`, NOT ON STDOUT, and that is the whole
# reason the memo works. An earlier version echoed the id, so every caller wrapped it in
# `$( )` — a SUBSHELL — and the cache assignment died with the subshell every time. A
# function that memoises cannot also return through stdout.
_slack_dm_channel() {
  local person="$1"
  ENGINE_DM_CHANNEL=""
  local cache_var; cache_var="_ENGINE_DM_CHAN_$(printf '%s' "$person" | tr -c 'A-Za-z0-9' '_')"
  local cached="${!cache_var:-}"
  if [ -n "$cached" ]; then ENGINE_DM_CHANNEL="$cached"; return 0; fi

  local token; token="$(resolve_env_key SLACK_INTAKE_TOKEN 2>/dev/null || true)"
  [ -n "$token" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1

  # The WORK address is the join key, even where someone's chat account is registered
  # to a personal one — an agent identity is a work identity.
  local email="${person}@finchclaims.com" resp uid=""
  resp="$(_slack_api "$token" "users.lookupByEmail?email=${email}")"
  uid="$(printf '%s' "$resp" | jq -r '.user.id // empty' 2>/dev/null)"

  if [ -z "$uid" ]; then
    local err; err="$(printf '%s' "$resp" | jq -r '.error // "unknown"' 2>/dev/null)"
    case "$err" in
      missing_scope)
        printf "  ${YELLOW}warn${NC}  the Slack app lacks ${BOLD}users:read.email${NC} — cannot look anyone up.\n" >&2
        return 1 ;;
    esac
    printf "  ${YELLOW}note${NC}  no Slack user for %s (%s).\n" "$email" "$err" >&2
    printf "        Enter the Slack email to DM (blank to skip and hand things over yourself): " >&2
    local typed=""; IFS= read -r typed || typed=""
    [ -n "$typed" ] || return 1
    resp="$(_slack_api "$token" "users.lookupByEmail?email=${typed}")"
    uid="$(printf '%s' "$resp" | jq -r '.user.id // empty' 2>/dev/null)"
    [ -n "$uid" ] || { printf "  ${YELLOW}warn${NC}  no Slack user for %s either.\n" "$typed" >&2; return 1; }
  fi

  local chan
  resp="$(_slack_api "$token" "conversations.open" -H 'Content-Type: application/json' \
          --data "$(jq -nc --arg u "$uid" '{users:$u}')")"
  chan="$(printf '%s' "$resp" | jq -r '.channel.id // empty' 2>/dev/null)"
  if [ -z "$chan" ]; then
    printf "  ${YELLOW}warn${NC}  could not open a DM (%s). Missing ${BOLD}im:write${NC}?\n" \
      "$(printf '%s' "$resp" | jq -r '.error // "unknown"' 2>/dev/null)" >&2
    return 1
  fi
  eval "$cache_var=\$chan"
  ENGINE_DM_CHANNEL="$chan"
  return 0
}

# ── _deliver_password_via_slack <agent-user> <login-email> ────────────────────
#
# A SEPARATE message from the key, deliberately. Two credentials in one message can only
# be deleted together, and they have different lifetimes: the key file is consumed by
# `env setup` and should be deleted immediately, while the password is the thing the
# holder keeps.
#
# ⚠️ IT DOES NOT CARRY THE PASSWORD, deliberately. An earlier version did, and the
# objection that killed it is the right one: a plaintext credential in a DM is permanent,
# searchable, and sits in the recipient's account as well as ours — for an account that
# reads across every organisation. The password is already in Secrets Manager and only
# that person's own agent policy can read it, so the message carries the COMMAND instead.
# Anything that reintroduces the secret here reintroduces the leak.
#
# ⚠️ AND IT MUST NOT BE CHANGED. The stored Secrets Manager value is what triage runs
# authenticate with; a human changing the password in the app breaks every subsequent run
# with no error, no counter and no alarm — the failure is an absence. That is why the
# instruction is in the message rather than in a doc nobody opens.
#
# Never fails the run: the account exists and the password is stored by this point, so a
# Slack hiccup costs a message, not the credential.
_deliver_password_via_slack() {
  local user="$1" login_email="$2"
  local person="${user%-agent}"
  local token; token="$(resolve_env_key SLACK_INTAKE_TOKEN 2>/dev/null || true)"
  [ -n "$token" ] || { printf "  ${CYAN}note${NC}  no Slack token — the app password was NOT sent. It is in Secrets Manager.\n"; return 0; }
  command -v curl >/dev/null 2>&1 || return 0

  local chan; _slack_dm_channel "$person" || {
    printf "  ${CYAN}note${NC}  app password NOT sent; it is readable with 'engine env resolve FINCH_AGENT_APP_PASSWORD --show-value'.\n"; return 0; }
  chan="$ENGINE_DM_CHANNEL"
  [ -n "$chan" ] || return 0

  local msg
  msg="*Your Finch agent app login* — this is the account the triage agents sign in as, and it is yours.

\`${login_email}\`

*The password is not in this message, on purpose.* It lives in Secrets Manager and only your own agent policy can read it. When you need it:
\`\`\`
engine env resolve FINCH_AGENT_APP_PASSWORD --show-value
\`\`\`
(Run \`engine env setup\` first if you have not — that is what fetches it to your machine.)

:warning: *Do not change this password.* Agents authenticate with the stored copy, so changing it in the app breaks every triage run afterwards — silently, with no error anywhere. If it ever must be rotated, do it through \`engine env provision\` so the stored copy moves with it.

*What this account can do*: it reads across organisations and is refused on writes. It is not a second personal account — it exists so an agent acting on your behalf is attributable to you.

Sent separately from your key on purpose, so you can delete either message on its own."

  local resp; resp="$(_slack_api "$token" "chat.postMessage" -H 'Content-Type: application/json' \
          --data "$(jq -nc --arg c "$chan" --arg t "$msg" '{channel:$c, text:$t}')")"
  if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null)" = "true" ]; then
    printf "  ${GREEN}ok${NC}    sent the app login to %s on Slack (%s), as its own message\n" "$person" "$chan"
  else
    printf "  ${YELLOW}warn${NC}  app password NOT sent (%s) — it is in Secrets Manager and readable with 'engine env resolve FINCH_AGENT_APP_PASSWORD --show-value'.\n" \
      "$(printf '%s' "$resp" | jq -r '.error // "unknown"' 2>/dev/null)"
  fi
  return 0
}

_deliver_via_slack() {
  local user="$1" person="$2" keyfile="$3"
  local token; token="$(resolve_env_key SLACK_INTAKE_TOKEN 2>/dev/null || true)"
  if [ -z "$token" ]; then
    printf "  ${CYAN}note${NC}  no Slack token resolves — the key file was not sent, hand it over yourself.\n"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || return 0

  local chan resp
  _slack_dm_channel "$person" || {
    printf "        key NOT sent — the file is still on disk.\n"; return 0; }
  chan="$ENGINE_DM_CHANNEL"
  [ -n "$chan" ] || { printf "        key NOT sent — the file is still on disk.\n"; return 0; }

  # Slack's upload is three calls: reserve a URL, PUT the bytes, then share it into the
  # conversation. Sharing is what makes it visible; an uploaded-but-unshared file is
  # invisible to the recipient and easy to mistake for success.
  local size url fid
  size="$(wc -c < "$keyfile" | tr -d ' ')"
  resp="$(_slack_api "$token" "files.getUploadURLExternal?filename=$(basename "$keyfile")&length=${size}")"
  url="$(printf '%s' "$resp" | jq -r '.upload_url // empty' 2>/dev/null)"
  fid="$(printf '%s' "$resp" | jq -r '.file_id // empty' 2>/dev/null)"
  if [ -z "$url" ] || [ -z "$fid" ]; then
    printf "  ${YELLOW}warn${NC}  cannot upload (%s) — missing ${BOLD}files:write${NC}? Key NOT sent.\n" \
      "$(printf '%s' "$resp" | jq -r '.error // "unknown"' 2>/dev/null)"
    return 0
  fi
  curl -sS -X POST "$url" -F "file=@${keyfile}" >/dev/null 2>&1 || {
    printf "  ${YELLOW}warn${NC}  the upload PUT failed — key NOT sent.\n"; return 0; }

  local doc; doc="$(resolve_env_key FINCH_SETUP_DOC_URL 2>/dev/null || true)"
  local msg
  msg="Here is your Finch agent key for \`${user}\`.

*Do this inside a Finch repo checkout — not your home folder.* Open the repo in Claude Code, then type \`/do\` and let it start a session. Everything below reads its settings relative to that checkout, so running it from \`~\` puts your credentials somewhere the tools stop finding the moment you open a project.

Then, in that session, one command:
\`\`\`
engine env setup --aws-key ~/Downloads/$(basename "$keyfile")
\`\`\`
It checks the key works, installs it, deletes the file, then fetches everything else it unlocks — including your app password, which you will never need to type. It finishes by checking its own work and telling you what it found.

If anything says *no session anchor*, that is this exact thing: you are outside a session or outside the checkout. Type \`/do\` in the repo and run it again.${doc:+

Full guide: ${doc}}

Delete this message once you have installed it."

  resp="$(_slack_api "$token" "files.completeUploadExternal" -H 'Content-Type: application/json' \
          --data "$(jq -nc --arg id "$fid" --arg t "Finch agent key — ${user}" --arg c "$chan" --arg m "$msg" \
                    '{files:[{id:$id,title:$t}], channel_id:$c, initial_comment:$m}')")"
  if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null)" = "true" ]; then
    PROVISION_SLACK_OK=1
    printf "  ${GREEN}ok${NC}    sent the key to %s on Slack (%s)\n" "$person" "$chan"
    printf "        ${YELLOW}That credential now lives in Slack history.${NC} Ask them to delete the message once installed.\n"
  else
    printf "  ${YELLOW}warn${NC}  upload completed but sharing failed (%s) — key NOT delivered.\n" \
      "$(printf '%s' "$resp" | jq -r '.error // "unknown"' 2>/dev/null)"
  fi
  return 0
}

# ── _provision_app_row <agent-user> <clerk-id> <email> <given> <family> ───────
#
# The last step that makes an account usable. AWS gives it credentials and Clerk gives
# it an identity, but until a `user` row exists the application does not know the person
# — no row, no role, nothing works.
#
# ⚠️ This is the one place the engine writes to the APPLICATION database, and it does so
# with a credential it never hands to an agent (`provisioner` tier). The database is not
# reachable directly; it goes through the SSM tunnel.
#
# Idempotent by clerk_user_id, which is unique: re-running adopts the existing row rather
# than failing or duplicating.
_provision_app_row() {
  local user="$1" clerk_id="$2" email="$3" given="$4" family="$5"
  [ -n "$clerk_id" ] || { printf "  ${CYAN}note${NC}  no Clerk id, so no app row was created.\n"; return 0; }
  command -v psql >/dev/null 2>&1 || { printf "  ${YELLOW}warn${NC}  psql is not on PATH — app row NOT created.\n"; return 0; }

  local org secret_name port url local_url
  org="$(resolve_env_key FINCH_AGENT_HOME_ORG 2>/dev/null || true)"
  port="$(resolve_env_key FINCH_DB_TUNNEL_PORT 2>/dev/null || true)"; port="${port:-15432}"
  secret_name="$(manifest_rows 2>/dev/null | awk -F'\037' '$1=="FINCH_DB_RW_SECRET"{print ($11!=""?$11:$5); exit}')"
  if [ -z "$org" ] || [ -z "$secret_name" ]; then
    printf "  ${YELLOW}warn${NC}  the manifest does not declare the home org or the read-write DB secret — app row NOT created.\n"
    return 0
  fi

  url="$(env_fetch_aws_secret "$secret_name" "" "" "" 2>/dev/null)" || url=""
  [ -n "$url" ] || { printf "  ${YELLOW}warn${NC}  could not read %s — app row NOT created.\n" "$secret_name"; return 0; }
  # The host in the secret is the private RDS endpoint; reachable only through the tunnel.
  local_url="$(printf '%s' "$url" | sed -E "s#@[^/:]+(:[0-9]+)?/#@127.0.0.1:${port}/#")"
  url=""

  if ! psql "$local_url" -tAc 'select 1' >/dev/null 2>&1; then
    printf "  ${YELLOW}warn${NC}  the database is not reachable on 127.0.0.1:%s — is the SSM tunnel up?\n" "$port"
    printf "           Start it (scripts/staging-db-tunnel.sh) and re-run with --app-row-only. App row NOT created.\n"
    local_url=""; return 0
  fi

  local existing
  existing="$(psql "$local_url" -tAc "select role from \"user\" where clerk_user_id = '${clerk_id}'" 2>/dev/null | tr -d ' ')"
  if [ -n "$existing" ]; then
    printf "  ${CYAN}note${NC}  an app row already exists for %s (role=%s) — left untouched.\n" "$user" "$existing"
    PROVISION_APP_ROW_OK=1
    local_url=""; return 0
  fi

  # ON CONFLICT on the unique clerk_user_id: a concurrent run cannot duplicate the person.
  if psql "$local_url" -v ON_ERROR_STOP=1 -tAc \
      "insert into \"user\" (clerk_user_id, role, organization_id, email, first_name, last_name)
       values ('${clerk_id}', 'agent', '${org}', '${email}', '${given}', '${family}')
       on conflict (clerk_user_id) do nothing" >/dev/null 2>&1; then
    local got
    got="$(psql "$local_url" -tAc "select role from \"user\" where clerk_user_id = '${clerk_id}'" 2>/dev/null | tr -d ' ')"
    if [ "$got" = "agent" ]; then
      printf "  ${GREEN}ok${NC}    app row created — %s is role=agent in org %s\n" "$user" "$org"
      PROVISION_APP_ROW_OK=1
    else
      printf "  ${YELLOW}warn${NC}  the insert reported success but the row reads role=%s\n" "${got:-<missing>}"
    fi
  else
    printf "  ${RED}warn${NC}  the app row could not be created. The AWS and Clerk halves are done; this person still cannot use the app.\n" >&2
  fi
  local_url=""
  return 0
}

cmd_provision() {
  local person="" tier="" apply=0 account="" reconcile=0 out="" email="" want_clerk=1 clerk_only=0 want_slack=1 approw_only=0 want_gemini=1 gemini_only=0
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
      --no-slack) want_slack=0; shift ;;
      --no-gemini) want_gemini=0; shift ;;
      # Mirrors --clerk-only / --app-row-only: backfill just this half for someone who
      # already exists, without touching a key or a login that is already installed.
      --gemini-only) gemini_only=1; shift ;;
      --app-row-only) approw_only=1; shift ;;
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
  local db_secret="" region="" bucket="" prefix="" bastion_tag="" login_secret="" db_identifier=""
  local gemini_secret="" gemini_project=""; local -a shared_secrets=()
  local state_prefix="" events_prefix=""
  while IFS=$'\037' read -r key service required secret default dotfile how check arg src sname sfield sregion sprofile; do
    # ⚠️ A `provisioner` ROW IS NEVER GRANTED. These are credentials the person running
    # this command needs and the agent must never hold — the read-write database URL
    # above all. Skipping them here, before any key is examined, makes that structural:
    # a new provisioner-only row cannot reach a policy by being forgotten in the case
    # below, which is the only way it could have leaked.
    [ "$required" = "provisioner" ] && continue
    case "$key" in
      FINCH_DB_RO_SECRET) db_secret="${sname:-$default}" ;;
      FINCH_BASTION_TAG)  bastion_tag="$default" ;;
      FINCH_DB_IDENTIFIER) db_identifier="$default" ;;
      FINCH_AGENT_APP_*)  login_secret="$sname" ;;
      GEMINI_API_KEY)     gemini_secret="$sname" ;;
      GEMINI_PROJECT)     gemini_project="$default" ;;
      # SHARED secrets: one ARN everyone reads. Collected as a list rather than a case
      # per key, because this set grows every time a credential turns out to be one
      # nobody can self-serve — which is how SLACK_INTAKE_TOKEN got here.
      SLACK_INTAKE_TOKEN|LINEAR_API_KEY)
        [ "$src" = "aws-secret" ] && [ -n "$sname" ] && shared_secrets[${#shared_secrets[@]}]="$sname" ;;
      AWS_REGION)         region="$default" ;;
      PROVE_S3_BUCKET)        [ "$tier" = "member" ] && bucket="$default" ;;
      PROVE_S3_PREFIX)        [ "$tier" = "member" ] && prefix="$default" ;;
      PROVE_S3_STATE_PREFIX)  [ "$tier" = "member" ] && state_prefix="$default" ;;
      PROVE_S3_EVENTS_PREFIX) [ "$tier" = "member" ] && events_prefix="$default" ;;
    esac
  done < <(manifest_rows)
  region="${region:-us-east-2}"

  # The Gemini key on its own — for someone already provisioned before this half existed.
  # Returns before the IAM mint, which refuses once a profile exists and would otherwise
  # take the backfill down with it.
  if [ "$gemini_only" -eq 1 ]; then
    if [ -z "$gemini_secret" ]; then
      echo "env provision: no manifest row declares a Gemini secret path, so there is nothing to mint." >&2; return 1
    fi
    local gsec="${gemini_secret//<person>/$user}"
    if aws secretsmanager describe-secret --secret-id "$gsec" --region "${region:-us-east-2}" >/dev/null 2>&1; then
      printf "  ${GREEN}ok${NC}    %s already has a Gemini key at %s — left alone.\n" "$user" "$gsec"; return 0
    fi
    if [ "$apply" -ne 1 ]; then
      printf "dry-run: would mint a Gemini key for %s on %s and store it at %s.\n" "$user" "${gemini_project:-<no GEMINI_PROJECT row>}" "$gsec"; return 0
    fi
    command -v gcloud >/dev/null 2>&1 || { echo "env provision: gcloud is not on PATH." >&2; return 2; }
    [ -n "$gemini_project" ] || { echo "env provision: no GEMINI_PROJECT row in the manifest." >&2; return 2; }
    local gkey=""
    gkey="$(gcloud services api-keys create --project="$gemini_project" --display-name="$user" \
              --api-target=service=generativelanguage.googleapis.com \
              --format='value(response.keyString)' 2>/dev/null | tail -1)"
    [ -n "$gkey" ] || { echo "env provision: could not mint a key on $gemini_project — check gcloud auth and apikeys.keys.create." >&2; return 2; }
    if aws secretsmanager create-secret --name "$gsec" --region "${region:-us-east-2}" \
         --description "Gemini API key for ${user}. Per-person: attribution and revocation. Restricted to generativelanguage.googleapis.com. Quota and billing are per PROJECT (${gemini_project}), so this carries no spend ceiling of its own." \
         --secret-string "$gkey" >/dev/null 2>&1; then
      gkey=""
      printf "  ${GREEN}ok${NC}    minted a Gemini key for %s and stored it at %s\n" "$user" "$gsec"; return 0
    fi
    gkey=""
    echo "env provision: minted a key but could not store it — it exists on $gemini_project under display name $user and is unreachable. Delete it there." >&2; return 2
  fi

  # The app login on its own. Without this, the Clerk half is unreachable for anyone who
  # already has an AWS profile — the mint refuses early to avoid orphaning a key, and
  # that refusal would take the app login down with it.
  if [ "$approw_only" -eq 1 ]; then
    # For an account that already exists: the Clerk id is not returned again, so it is
    # looked up by the email the account was created under.
    [ -n "$email" ] || email="$(_agent_login_email "$user")"
    local tok cid given
    tok="$(resolve_env_key CLERK_SECRET_KEY 2>/dev/null || true)"
    if [ -z "$tok" ]; then echo "env provision --app-row-only: no CLERK_SECRET_KEY resolves, so the Clerk id cannot be looked up." >&2; return 2; fi
    # ⚠️ PERCENT-ENCODE THE `+`. In a query string a literal `+` decodes to a SPACE, so
    # `leonardo+agent@…` reaches the API as `leonardo agent@…` and matches nobody — the
    # account is found to be missing seconds after being created. Only this one character
    # matters here (the local part is otherwise an identifier), so encode it directly
    # rather than pulling in a general encoder.
    local email_q="${email//+/%2B}"
    cid="$(curl -sS "https://api.clerk.com/v1/users?email_address=${email_q}" -H "Authorization: Bearer $tok" 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null)"
    if [ -z "$cid" ]; then echo "env provision --app-row-only: no Clerk user found for $email." >&2; return 2; fi
    given="$(printf '%s' "${user%-agent}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    printf "${BOLD}=== app row for %s ===${NC}\n  clerk %s\n  email %s\n" "$user" "$cid" "$email"
    if [ "$apply" -eq 0 ]; then printf "${BOLD}dry-run:${NC} nothing was written. Re-run with --apply.\n"; return 0; fi
    printf "${BOLD}About to INSERT a row into the app database.${NC}\nType the account id to confirm: "
    local typed=""; IFS= read -r typed || typed=""; printf "\n"
    [ "$typed" = "$account" ] || { echo "env provision --app-row-only: requires a typed confirmation of the account id ($account). Nothing was written." >&2; return 1; }
    _provision_app_row "$user" "$cid" "$email" "$given" "Agent"
    return $?
  fi

  if [ "$clerk_only" -eq 1 ]; then
    [ -n "$email" ] || email="$(_agent_login_email "$user")"
    local target="${login_secret//<person>/$(_agent_login_local "$user")}"
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

  # TWO buckets, and the split is the whole design. `stmts` is what every agent of this
  # tier gets identically — it goes into ONE customer-managed policy they all share, so
  # the next grant stops competing for a per-user byte budget. `own_stmts` is what names a
  # PERSON: their login secret and their Gemini key, which cannot live in a shared
  # document. Measured, not assumed: ${aws:username} IS substituted inside a Secrets
  # Manager resource ARN, but it resolves to the DASHED IAM user name (yarik-agent) while
  # the login secret is PLUS-addressed (agent-login/yarik+agent-*), and IAM policy
  # variables carry no string transform. The only shared shape that reaches it is
  # agent-login/*, which hands every agent every other person's login and destroys the
  # attribution per-person accounts exist for. So the person-scoped half stays inline.
  local -a stmts=() own_stmts=() dropped=() underivable=()
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
      # TWO statements, deliberately. A Condition applies to EVERY resource in its
      # statement, and the SSM document is an AWS-managed public document carrying no
      # tags at all — so a single statement covering instance+document under a
      # resourceTag condition can never authorise the document, and StartSession is
      # denied naming the DOCUMENT arn. Measured: that is exactly what it did.
      # The tag condition stays on the INSTANCE, which is where the scoping matters;
      # a grant on the document widens nothing, because it names no target.
      stmts[${#stmts[@]}]="$(jq -nc --arg r "$arn" --arg tag "$bastion_tag" '
        {Sid:"TunnelToBastion",Effect:"Allow",Action:["ssm:StartSession"],Resource:[$r],
         Condition:{StringEquals:{"ssm:resourceTag/Name":$tag}}}')"
      stmts[${#stmts[@]}]="$(jq -nc \
        --arg doc "arn:aws:ssm:${region}::document/AWS-StartPortForwardingSessionToRemoteHost" '
        {Sid:"TunnelDocument",Effect:"Allow",Action:["ssm:StartSession"],Resource:[$doc]}')"
      stmts[${#stmts[@]}]="$(jq -nc '{Sid:"DiscoverBastionByTag",Effect:"Allow",Action:["ec2:DescribeInstances"],Resource:["*"]}')"
      # The tunnel turns DB_IDENTIFIER into an endpoint hostname and passes it to
      # start-session. That lookup is the ONLY thing this grant buys.
      if [ -n "$db_identifier" ]; then
        arn="arn:aws:rds:${region}:${account}:db:${db_identifier}"
        if _arn_allowed "$arn"; then
          stmts[${#stmts[@]}]="$(jq -nc --arg r "$arn" '{Sid:"ResolveDbEndpoint",Effect:"Allow",Action:["rds:DescribeDBInstances"],Resource:[$r]}')"
        else
          dropped[${#dropped[@]}]="$arn"
        fi
      else
        underivable[${#underivable[@]}]="rds:DescribeDBInstances — no manifest row declares the DB identifier (FINCH_DB_IDENTIFIER), so the endpoint lookup cannot be derived."
      fi
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
    # Same plus form the fetcher asks for. These two disagreeing is precisely the defect
    # that made the read impossible before: a grant on a path nothing ever requests.
    arn="arn:aws:secretsmanager:${region}:${account}:secret:${login_secret//<person>/$(_agent_login_local "$user")}-*"
    if _arn_allowed "$arn"; then
      own_stmts[${#own_stmts[@]}]="$(jq -nc --arg r "$arn" '{Sid:"ReadOwnAgentLogin",Effect:"Allow",Action:["secretsmanager:GetSecretValue"],Resource:[$r]}')"
    else
      dropped[${#dropped[@]}]="$arn"
    fi
  fi

  # The agent's OWN Gemini key. PER-PERSON, and scoped exactly like the login above —
  # that scoping is what turns "someone burned the quota" into "this person's agent did".
  # ⚠️ DASHED here, unlike agent-login: that path carries the plus form because it names a
  # LOGIN, and the fetcher only plus-converts a path containing `agent-login`. A grant on
  # a path the fetcher never requests is the exact defect this branch already paid for.
  if [ -n "$gemini_secret" ]; then
    arn="arn:aws:secretsmanager:${region}:${account}:secret:${gemini_secret//<person>/$user}-*"
    if _arn_allowed "$arn"; then
      own_stmts[${#own_stmts[@]}]="$(jq -nc --arg r "$arn" '{Sid:"ReadOwnGeminiKey",Effect:"Allow",Action:["secretsmanager:GetSecretValue"],Resource:[$r]}')"
    else
      dropped[${#dropped[@]}]="$arn"
    fi
  fi

  # SHARED secrets — the same ARN for everyone, deliberately. A Slack bot token is ONE
  # bot and a Linear read key carries no attribution, so per-person copies would be
  # theatre; rotation happens once, here, rather than in four dotfiles. Contrast the two
  # blocks above: per-person where the credential identifies someone, shared where it
  # does not. Both of these were typed by hand until today, which asked a new teammate
  # for credentials they had no way to obtain.
  if [ "${#shared_secrets[@]}" -gt 0 ]; then
    local -a shared_arns=()
    local sec
    for sec in "${shared_secrets[@]}"; do
      arn="arn:aws:secretsmanager:${region}:${account}:secret:${sec}-*"
      if _arn_allowed "$arn"; then shared_arns[${#shared_arns[@]}]="$arn"; else dropped[${#dropped[@]}]="$arn"; fi
    done
    if [ "${#shared_arns[@]}" -gt 0 ]; then
      stmts[${#stmts[@]}]="$(printf '%s\n' "${shared_arns[@]}" | jq -R . | jq -sc '{Sid:"ReadSharedTokens",Effect:"Allow",Action:["secretsmanager:GetSecretValue"],Resource:.}')"
    fi
  fi

  # Both documents go through the SAME merge (see _provision_policy_doc). The split
  # happens BEFORE the merge and cannot change what is allowed: merging unions Resources
  # within one Effect+Action group, so partitioning the statements first yields two groups
  # whose union is the same set of (action, resource) pairs.
  local policy="" managed_policy=""
  if [ "${#stmts[@]}" -gt 0 ]; then
    managed_policy="$(printf '%s\n' "${stmts[@]+"${stmts[@]}"}" | _provision_policy_doc)"
  fi
  if [ "${#own_stmts[@]}" -gt 0 ]; then
    policy="$(printf '%s\n' "${own_stmts[@]+"${own_stmts[@]}"}" | _provision_policy_doc)"
  fi

  # ⚠️ THE TIER IS IN THE MANAGED NAME AND NOT IN THE INLINE ONE, and the asymmetry is
  # deliberate. The shared document's CONTENT differs by tier — member publishes boards,
  # triage does not — so one name across both tiers would hand triage the publisher grant
  # the moment a member re-provisioned. The inline document is now tier-INVARIANT: two
  # person-scoped secrets, the same set at every tier. So the old rule that kept the tier
  # out of the inline name is not merely preserved, it has become impossible to break.
  # The downgrade hazard that rule was written against moves to the managed side, where it
  # is ENUMERABLE — list-attached-user-policies returns the exact attached set, so a
  # sibling tier left attached is detected rather than invisible. Reconcile reports it.
  local policy_name="engine-${DOMAIN}"
  local managed_name="engine-${DOMAIN}-${tier}"
  local managed_arn; managed_arn="$(_provision_managed_arn "$account" "$managed_name")"

  printf "${BOLD}=== provision %s (tier: %s, account: %s) ===${NC}\n" "$user" "$tier" "$account"
  printf "${CYAN}SHARED managed policy %s — the same document for every %s agent:${NC}\n" "$managed_name" "$tier"
  if [ -n "$managed_policy" ]; then
    printf '%s\n' "$managed_policy"
    _provision_report_size "$managed_policy" "$ENV_PROVISION_MANAGED_CAP" "managed policy"
  else
    printf "  ${YELLOW}empty${NC}    nothing shared is derivable — no managed policy would be written.\n"
  fi
  printf "${CYAN}PER-PERSON inline policy %s — only what names %s:${NC}\n" "$policy_name" "$user"
  if [ -n "$policy" ]; then
    printf '%s\n' "$policy"
    _provision_report_size "$policy" "$ENV_PROVISION_INLINE_CAP" "inline policy"
  else
    printf "  ${YELLOW}empty${NC}    no manifest row declares a person-scoped secret — no inline policy would be written.\n"
  fi
  local i=0
  while [ "$i" -lt "${#dropped[@]}" ]; do
    printf "  ${YELLOW}dropped${NC}  %s — outside the ARN allowlist in env.sh (a manifest edit cannot widen the grant)\n" "${dropped[$i]}"; i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "${#underivable[@]}" ]; do
    printf "  ${YELLOW}UNDERIVABLE${NC}  %s\n" "${underivable[$i]}"; i=$((i + 1))
  done
  printf "  ${CYAN}note${NC}  the minted profile gets NO ~/.aws/config entry — the ABSENCE of login_session is what makes an agent key never expire.\n"

  if [ "$reconcile" -eq 1 ]; then
    if [ "${#underivable[@]}" -gt 0 ]; then
      echo "env provision --reconcile: refusing while part of the policy is UNDERIVABLE from the manifest (see above) — reconciling to a partial derivation would REMOVE a grant that is merely underived." >&2
      return 2
    fi
    # ⚠️ SHARED FIRST, INLINE SECOND, ALWAYS. The inline document is about to SHRINK to the
    # two person-scoped secrets, and everything it sheds is only still granted because the
    # shared policy now carries it. Shrinking first would leave a live agent with no
    # tunnel and no database secret for as long as the shared half takes — and forever if
    # it fails. In this order a failure on the shared half stops before anything is
    # removed, which is why the exit code below is checked rather than accumulated blindly.
    local rc_m rc_i
    _provision_managed_sync "$user" "$managed_name" "$managed_arn" "$managed_policy" "$apply" "$account" "$DOMAIN"; rc_m=$?
    if [ "$rc_m" -eq 2 ] || { [ "$apply" -eq 1 ] && [ "$rc_m" -ne 0 ]; }; then
      echo "env provision --reconcile: the shared policy is not in place, so the inline policy was left alone — shrinking it now would REMOVE grants nothing else carries yet." >&2
      return "$rc_m"
    fi
    if [ -z "$policy" ]; then
      printf "  ${CYAN}note${NC}  no person-scoped secret is derivable, so there is no inline policy to reconcile.\n"
      return "$rc_m"
    fi
    _provision_reconcile "$user" "$policy_name" "$policy" "$apply" "$account" "$managed_name" "$managed_policy"; rc_i=$?
    [ "$rc_m" -gt "$rc_i" ] && return "$rc_m"
    return "$rc_i"
  fi

  if [ "$apply" -eq 0 ]; then
    printf "${BOLD}dry-run:${NC} nothing was created. Review the policy above, then re-run with --apply.\n"
    return 0
  fi

  if [ "${#underivable[@]}" -gt 0 ]; then
    echo "env provision: refusing --apply while part of the policy is UNDERIVABLE from the manifest (see above). Minting a partial policy would silently under-grant." >&2
    return 1
  fi
  # Refuse over-cap HERE, before an IAM user is created. IAM's own refusal arrives after
  # the user exists and names neither the document nor the number, which is how the last
  # cap failure cost an afternoon.
  if [ -z "$managed_policy" ] || [ -z "$policy" ]; then
    echo "env provision: refusing --apply — one of the two documents is empty (see above). Both halves are required: the shared policy carries the tier's grants, the inline one the person's own secrets." >&2
    return 1
  fi
  if ! _provision_report_size "$managed_policy" "$ENV_PROVISION_MANAGED_CAP" "managed policy" >/dev/null \
     || ! _provision_report_size "$policy" "$ENV_PROVISION_INLINE_CAP" "inline policy" >/dev/null; then
    echo "env provision: refusing --apply — a document is over its IAM size cap (see the size lines above). Nothing was created." >&2
    return 1
  fi
  # THE CONFIRMATION IS READ, NEVER FLAGGED. A `--yes`-shaped flag would make minting
  # reachable from any automated `Bash(engine *)` call, which is the same hole the seam
  # refusal above closes. A read gets EOF in that context and aborts on its own.
  printf "${BOLD}About to mint IAM user %s in account %s.${NC}\n" "$user" "$account"
  [ "$want_clerk" -eq 1 ] && printf "${BOLD}This ALSO creates an app login in the Clerk instance your CLERK_SECRET_KEY points at, and stores its password in Secrets Manager.${NC} Pass --no-clerk to skip that half.\n"
  # ⚠️ The app row is the half people do not expect, and the half that silently does not
  # happen. It needs YOUR OWN full access — an agent profile cannot write the database,
  # and a personal cloud session expires daily — plus the SSM tunnel already listening.
  # Saying so BEFORE the confirm is the point: discovering it afterwards leaves a person
  # holding a cloud account and an app login that the application does not recognise,
  # which is exactly the state an earlier run shipped someone in.
  if [ "$want_clerk" -eq 1 ]; then
    printf "${BOLD}It ALSO creates their app row at role=agent${NC} — without it the application authenticates the account and still does not know who it is.\n"
    printf "  That half needs YOUR OWN access, not an agent profile: be logged in, and have the DB tunnel up (scripts/staging-db-tunnel.sh).\n"
    if ! (exec 3<>/dev/tcp/127.0.0.1/${FINCH_DB_TUNNEL_PORT:-15432}) 2>/dev/null; then
      printf "  ${YELLOW}warn${NC}  nothing is listening on 127.0.0.1:${FINCH_DB_TUNNEL_PORT:-15432} — the app row WILL fail and you will have to re-run with --app-row-only.\n"
      printf "        Start the tunnel in another shell now, or continue and finish that half afterwards.\n"
    fi
    printf "  Setup guide: https://app.notion.com/p/3c0c52348d1381d2ac12c85b44b30d20\n"
  fi
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

  # SHARED FIRST. Most of what the agent needs now lives in the shared policy, so a
  # failure here means the inline half must not be written either — an agent holding only
  # its own two secrets is a worse state to debug than one with no grants at all, because
  # it authenticates and then fails on every real call.
  local rc_shared
  _provision_managed_sync "$user" "$managed_name" "$managed_arn" "$managed_policy" 1 "$account" "$DOMAIN" 1; rc_shared=$?
  if [ "$rc_shared" -ne 0 ]; then
    echo "env provision: the shared policy is not in place. The IAM user exists and is UNGRANTED; nothing else was created." >&2
    return 1
  fi

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
    echo "env provision: could not attach inline policy $policy_name to $user. The shared policy is attached, but the agent cannot read its own login or Gemini key." >&2
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
      printf "           That file is what they feed to:  engine env setup --aws-key <path>\n"
      printf "           It validates the key, installs it, and SHREDS the file. Delete your copy once they confirm.\n"
      if [ "$want_slack" -eq 1 ]; then
        _deliver_via_slack "$user" "$person" "$dfile"
      else
        printf "  ${CYAN}note${NC}  --no-slack: nothing was sent; hand the file over yourself.\n"
      fi
    else
      printf "  ${YELLOW}warn${NC}  no delivery file was written — the key is installed locally as [%s] but you have nothing to send.\n" "$user"
    fi
  fi
  skey=""

  if [ "$want_clerk" -eq 1 ]; then
    [ -n "$email" ] || email="$(_agent_login_email "$user")"
    _provision_clerk_account "$user" "$email" "${login_secret//<person>/$(_agent_login_local "$user")}" "$region"
    # The row that turns an identity into an account the application recognises.
    _provision_app_row "$user" "${PROVISION_CLERK_USER_ID:-}" "$email" \
      "$(printf '%s' "${user%-agent}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')" "Agent"
  else
    printf "  ${CYAN}note${NC}  --no-clerk: no app login was created, so the agent-login secret stays as it was.\n"
  fi

  # ⚠️ REPORT WHAT HAPPENED, NOT WHAT WAS ATTEMPTED. Every half below degrades rather
  # than aborting — deliberately, because losing a minted IAM key to a chat-API hiccup
  # would be the worst trade available. The cost of that choice is that a run can leave
  # an account that exists and cannot be used, so the summary has to say so. It once
  # printed "provisioned" while the app login, the app row and the delivery had all
  # silently no-opped on a mis-resolved credential path: three of four halves missing,
  # reported as success.
  # ── the agent's own Gemini key ───────────────────────────────────────────────
  # PER-PERSON so spend is attributable and one key can be revoked alone. Restricted to
  # generativelanguage.googleapis.com at creation, so a leak reaches nothing else on the
  # project. FAIL-SOFT like every other half: a missing gcloud must not cost a minted IAM
  # key. The key string is written straight to Secrets Manager and never printed, never
  # put in the delivery file — the holder fetches it with the grant they already have.
  PROVISION_GEMINI_OK=0
  if [ -n "$gemini_secret" ] && [ "$apply" -eq 1 ] && [ "$want_gemini" -eq 1 ]; then
    local gsec="${gemini_secret//<person>/$user}"
    if aws secretsmanager describe-secret --secret-id "$gsec" --region "$region" >/dev/null 2>&1; then
      # Idempotent, and for the same reason the app login is: re-minting would strand
      # whatever is already installed on their machine.
      printf "  ${GREEN}ok${NC}    gemini key already provisioned at %s — left alone\n" "$gsec"
      PROVISION_GEMINI_OK=1
    elif ! command -v gcloud >/dev/null 2>&1; then
      printf "  ${YELLOW}warn${NC}  gcloud is not on PATH — no Gemini key minted. Install it and re-run; nothing else is affected.\n"
    elif [ -z "$gemini_project" ]; then
      printf "  ${YELLOW}warn${NC}  no manifest row declares GEMINI_PROJECT, so the key cannot be minted. Add it and re-run.\n"
    else
      local gkey=""
      gkey="$(gcloud services api-keys create --project="$gemini_project" \
                --display-name="$user" \
                --api-target=service=generativelanguage.googleapis.com \
                --format='value(response.keyString)' 2>/dev/null | tail -1)"
      if [ -z "$gkey" ]; then
        printf "  ${YELLOW}warn${NC}  could not mint a Gemini key on project %s — check 'gcloud auth login' and that you hold apikeys.keys.create there.\n" "$gemini_project"
      elif aws secretsmanager create-secret --name "$gsec" --region "$region" \
             --description "Gemini API key for ${user}. Per-person: attribution and revocation. Restricted to generativelanguage.googleapis.com. Quota and billing are per PROJECT (${gemini_project}), so this does NOT carry its own spend ceiling." \
             --secret-string "$gkey" >/dev/null 2>&1; then
        printf "  ${GREEN}ok${NC}    minted a Gemini key on %s and stored it at %s\n" "$gemini_project" "$gsec"
        PROVISION_GEMINI_OK=1
      else
        printf "  ${RED}FAIL${NC}  minted a Gemini key but could NOT store it — it exists on %s under display name %s and is unreachable. Delete it there.\n" "$gemini_project" "$user"
      fi
      gkey=""
    fi
  elif [ -n "$gemini_secret" ]; then
    printf "  ${CYAN}note${NC}  dry-run: would mint a Gemini key on %s and store it at %s\n" "${gemini_project:-<no GEMINI_PROJECT row>}" "${gemini_secret//<person>/$user}"
  fi

  # ⚠️ THE FLAGS ARE COMPUTED BEFORE THEY ARE PRINTED, and that is the whole point.
  # They used to be set inside the `$( … )` that rendered each line — a SUBSHELL, so every
  # `_p_ok=0` was discarded on the way out and the verdict below read 1 no matter how many
  # halves had failed. That is exactly how a run printed "NO app row" and "done: usable"
  # in the same breath, which is the failure this summary exists to prevent. Same subshell
  # trap that made the MCP probe re-exec per row; it is worth suspecting `$( … )` whenever
  # a variable will not stay set.
  local _p_ok=1
  [ -n "$akid" ] || _p_ok=0
  if [ "$want_clerk" -eq 1 ]; then
    [ "${PROVISION_CLERK_OK:-0}" -eq 1 ] || _p_ok=0
    [ "${PROVISION_APP_ROW_OK:-0}" -eq 1 ] || _p_ok=0
  fi
  [ -z "${gemini_secret:-}" ] || [ "${PROVISION_GEMINI_OK:-0}" -eq 1 ] || _p_ok=0

  printf "\n${BOLD}=== %s ===${NC}\n" "$user"
  printf "  %s  cloud account + policy + key\n" "$([ -n "$akid" ] && printf "${GREEN}yes${NC}" || printf "${RED}NO ${NC}")"
  if [ "$want_clerk" -eq 1 ]; then
    printf "  %s  app login\n" "$([ "${PROVISION_CLERK_OK:-0}" -eq 1 ] && printf "${GREEN}yes${NC}" || printf "${RED}NO ${NC}")"
    printf "  %s  app row (role=agent) — without it the application does not know them\n" \
      "$([ "${PROVISION_APP_ROW_OK:-0}" -eq 1 ] && printf "${GREEN}yes${NC}" || printf "${RED}NO ${NC}")"
  fi
  if [ -n "${gemini_secret:-}" ]; then
    printf "  %s  own Gemini key\n" "$([ "${PROVISION_GEMINI_OK:-0}" -eq 1 ] && printf "${GREEN}yes${NC}" || printf "${RED}NO ${NC}")"
  fi
  if [ -n "${dfile:-}" ]; then
    printf "  %s  delivered on Slack%s\n" \
      "$([ "${PROVISION_SLACK_OK:-0}" -eq 1 ] && printf "${GREEN}yes${NC}" || printf "${YELLOW}no ${NC}")" \
      "$([ "${PROVISION_SLACK_OK:-0}" -eq 1 ] || printf " — the key file is on disk; hand it over yourself")"
  fi
  if [ "$_p_ok" -eq 1 ]; then
    printf "${BOLD}done:${NC} %s is usable at the %s tier. Have them run 'engine env setup --aws-key <path>', then 'engine env setup'.\n" "$user" "$tier"
  else
    printf "${YELLOW}PARTIAL:${NC} %s is NOT usable yet — the NO lines above did not happen.\n" "$user"
    printf "         Fix what they name and re-run; each half is idempotent, so nothing is duplicated.\n"
    return 1
  fi
  if [ -n "${PROVISION_CLERK_USER_ID:-}" ] && [ "${PROVISION_APP_ROW_OK:-0}" -ne 1 ]; then
    # ⚠️ NOT USABLE YET, and saying so here is the point: AWS and the identity provider
    # are done, the application still does not know this person. The row needs write
    # access to the app database, which nothing in this system provisions — the only DB
    # credential it hands out is read-only, deliberately.
    printf "\n${YELLOW}STILL REQUIRED — the app does not know %s yet.${NC}\n" "$user"
    printf "  An app 'user' row must exist before the account can do anything:\n"
    printf "    clerk_user_id   %s\n" "$PROVISION_CLERK_USER_ID"
    printf "    email           %s\n" "$email"
    printf "    role            agent\n"
    printf "    organization_id <required, NOT NULL — an agent redirects org per request, so this is its home org>\n"
    printf "  This needs DB WRITE access. It is not part of provisioning yet.\n"
  fi
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

  # Checked HERE, before anything is written. _agent_profile_verify returns 1 for a
  # missing `aws` exactly as it does for a rejected key, so without this guard a machine
  # with no CLI is told its key "did not authenticate" — sending the reader after a
  # credential that was fine all along. Nothing is written yet, so there is no profile
  # to clean up either.
  if ! command -v aws >/dev/null 2>&1 && [ -z "${ENV_STS_ARN+set}" ]; then
    echo "env setup --aws-key: the AWS CLI is not installed, so the key cannot be verified. Install it (brew install awscli) and re-run. Nothing was written; your delivered file was NOT removed." >&2
    return 1
  fi

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
  # An agent-login secret is named for the LOGIN it holds, not for the profile that
  # reads it — so the path carries the plus form even though the profile is dashed.
  case "$sname" in
    *agent-login*) who="$(_agent_login_local "$who")" ;;
  esac
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

# ── cmd_db_url ────────────────────────────────────────────────────────────────
#
# THE one way to get a usable staging DB connection string. Fetches the credential
# from Secrets Manager and re-points its host at the local tunnel, printing a URL you
# can hand straight to psql.
#
# Why this exists as a command rather than a recipe: the credential is deliberately
# never written to disk (FINCH_DB_RO_SECRET carries the secret's NAME, not its value),
# so every consumer had to call `aws secretsmanager get-secret-value` itself and then
# re-point the host with the same sed. That duplication is real — the identical
# incantation sits in the runbook, in the triage access directive, and in whatever the
# caller last wrote by hand. Worse, the raw aws call trips the permission classifier,
# which has already killed a background agent mid-run; `engine` does not.
#
# ⚠️ THE SECRET'S OWN HOST IS NOT THE TUNNEL. staging/finch/db-ro-url points at the
# PUBLIC analyst instance, which is IP-allowlisted and will hang for anyone not on the
# list. Re-pointing to 127.0.0.1 is what makes it the tunnel — that is the step callers
# kept getting wrong, not the fetch.
#
# Prints ONLY the URL on stdout, so it composes: psql "$(engine env db-url)".
cmd_db_url() {
  local role="ro" port="" show_host=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --owner) role="owner"; shift ;;
      --ro)    role="ro"; shift ;;
      --port)  port="${2:-}"; shift 2 ;;
      --port=*) port="${1#*=}"; shift ;;
      --analyst-host) show_host=1; shift ;;
      -h|--help) sed -n "$USAGE_LINES" "$0"; return 0 ;;
      *) echo "env db-url: unknown flag '$1'" >&2; return 1 ;;
    esac
  done

  local key sname
  if [ "$role" = "owner" ]; then key="FINCH_DB_RW_SECRET"; else key="FINCH_DB_RO_SECRET"; fi
  sname="$(manifest_secret_name "$key")"
  if [ -z "$sname" ]; then
    echo "env db-url: no manifest row declares $key, so there is no secret to fetch." >&2
    return 2
  fi

  local url; url="$(env_fetch_aws_secret "$sname")" || return $?
  [ -n "$url" ] || { echo "env db-url: $sname fetched empty." >&2; return 1; }
  # Some rows store a JSON blob, some a bare URL. Take .url/.password-free connection
  # string when it parses as JSON, else use it verbatim.
  case "$url" in
    \{*) url="$(printf '%s' "$url" | jq -r '.url // .connectionString // .dsn // empty' 2>/dev/null)" ;;
  esac
  [ -n "$url" ] || { echo "env db-url: $sname holds no connection string." >&2; return 1; }

  if [ "$show_host" -eq 1 ]; then printf '%s\n' "$url"; return 0; fi

  # The tunnel's local port, from the manifest, so a caller who overrode LOCAL_PORT is
  # not silently handed 15432.
  [ -n "$port" ] || port="${LOCAL_PORT:-$(manifest_secret_name FINCH_DB_TUNNEL_PORT)}"
  [ -n "$port" ] || port=15432
  printf '%s\n' "$(printf '%s' "$url" | sed "s|@[^/]*|@127.0.0.1:${port}|")"
  return 0
}

# manifest_secret_name KEY -> the Secrets Manager name that row points at, empty if none.
#
# Prefers the source's own `name` and falls back to `default`, mirroring what the policy
# builder does for the same rows (env.sh: `db_secret="${sname:-$default}"`) — the two must
# agree, or a grant would be minted for a path nothing ever requests.
#
# ⚠️ Field order is fixed by env_manifest_rows and `default` is the FIFTH field. Reading
# positionally is easy to get wrong; the full name list is spelled out deliberately.
manifest_secret_name() {
  local want="$1"
  local key service required secret default dotfile how check arg src sname sfield sregion sprofile
  while IFS=$'\037' read -r key service required secret default dotfile how check arg src sname sfield sregion sprofile; do
    if [ "$key" = "$want" ]; then printf '%s' "${sname:-$default}"; return 0; fi
  done < <(manifest_rows 2>/dev/null)
  return 1
}

cmd_setup() {
  env_anchor_prime   # resolve the anchor ONCE; every later subshell inherits it
  local dry=0 aws_key="" person="" domain_given=0 refresh=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) DOMAIN="${2:-}"; domain_given=1; shift 2 ;;
      --domain=*) DOMAIN="${1#*=}"; domain_given=1; shift ;;
      --aws-key) aws_key="${2:-}"; shift 2 ;;
      --aws-key=*) aws_key="${1#*=}"; shift ;;
      --person) person="${2:-}"; shift 2 ;;
      --person=*) person="${1#*=}"; shift ;;
      --non-interactive|--dry-run) dry=1; shift ;;
      # Re-fetch rows whose value has an authoritative upstream (aws-secret), even when
      # the dotfile already holds one. Never touches a `prompt` row — see the loop below.
      --refresh) refresh=1; shift ;;
      -h|--help) sed -n "$USAGE_LINES" "$0"; return 0 ;;
      *) echo "env setup: unknown flag '$1'" >&2; return 1 ;;
    esac
  done
  # INSTALL, THEN KEEP GOING. The key is precisely what unlocks the fetch, so stopping
  # here made "you are done" and "you are half done" look identical, and left the rest
  # behind a second command the recipient had to know to run. A failed install still
  # stops — there is nothing to fetch with.
  if [ -n "$aws_key" ]; then
    install_aws_key "$aws_key" "$person" || return $?
    printf "\n"
    printf "  ${CYAN}next${NC}  key installed — fetching everything else it unlocks…\n"
  fi

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
      # Built as an array, not `${dry:+…}`: that form expands on NON-EMPTINESS, and the
      # default `dry=0` is a non-empty string — so the walk passed --non-interactive
      # every time and never asked the new teammate anything. Quoting matters too; an
      # unquoted ${person:+…} splits a name containing a space.
      local -a walk_args=()
      [ "$dry" -eq 1 ] && walk_args[${#walk_args[@]}]="--non-interactive"
      if [ -n "$person" ]; then
        walk_args[${#walk_args[@]}]="--person"; walk_args[${#walk_args[@]}]="$person"
      fi
      cmd_setup --domain "$d" ${walk_args[@]+"${walk_args[@]}"}
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
    # Seed a non-secret manifest default FIRST, before the secret/aws-secret filter below
    # drops the row. AWS_REGION is the case that matters: non-secret, prompt-sourced, and
    # required by every Secrets Manager fetch this same loop is about to make. Seeding it
    # only in the doctor meant setup could not fetch anything unless doctor had already
    # run — an ordering nobody would guess from the command names.
    if [ "$secret" != "true" ] && [ "$check" = "file-key" ] && [ -n "$default" ] && [ -n "$dotfile" ] \
       && [ "$src" != "aws-secret" ]; then
      if ! resolve_env_key "$key" >/dev/null 2>&1; then
        if [ "$dry" -eq 1 ]; then
          printf "  ${CYAN}would-seed${NC}   %-22s = %s → %s\n" "$key" "$default" "$dotfile"
        else
          local _where
          if _where="$(seed_nonsecret_default "$key" "$default" "$dotfile")"; then
            printf "  ${GREEN}seed${NC}  %-22s = %s → %s\n" "$key" "$default" "$_where"
          else
            printf "  ${YELLOW}warn${NC}  %-22s could not seed default into %s\n" "$key" "$dotfile"
          fi
        fi
      fi
    fi
    [ "$secret" = "true" ] || [ "$src" = "aws-secret" ] || continue
    [ "$check" = "file-key" ] || continue   # only dotfile-backed rows are wizard-writable
    # --refresh re-fetches rows that have an AUTHORITATIVE UPSTREAM, even when the dotfile
    # already holds a value. For an `aws-secret` row the local copy is a CACHE, not a
    # source, and a stale cache is invisible: the doctor reports PASS because a value is
    # present, never because it is the right one. That is how a per-person key can be
    # provisioned, granted and never used — the machine keeps whatever was typed months
    # ago and nothing says so.
    #
    # ⚠️ It deliberately does NOT touch `prompt` rows. Those have no upstream to refresh
    # FROM, so re-writing one could only mean discarding a value a person went and
    # obtained. Refreshing a cache and clobbering a source are different acts.
    if key_present "$key" "$dotfile" "$check" "$arg"; then
      if [ "$refresh" -eq 1 ] && [ "$src" = "aws-secret" ]; then
        printf "  ${CYAN}refresh${NC}  %-22s (re-fetching from %s)\n" "$key" \
          "$(_resolve_person_secret_name "$sname" 2>/dev/null || printf '%s' "$sname")"
      else
        printf "  ${GREEN}have${NC}  %-22s (already set%s)\n" "$key" \
          "$([ "$src" = "aws-secret" ] && [ "$refresh" -ne 1 ] && printf " — pass --refresh to re-fetch")"
        continue
      fi
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
    printf "${BOLD}done:${NC} %d secret(s) written.\n" "$wrote"
    # CHECK ITS OWN WORK. "Now run the doctor" is a second thing to know, and the person
    # who most needs the check is the one least likely to run it. Advisory only: the
    # doctor's verdict is REPORTED, never folded into setup's exit code — setup succeeded
    # or failed on whether it wrote the secrets, and a red doctor usually means something
    # setup does not own (an unauthenticated MCP, a missing binary).
    if [ "${ENV_SETUP_NO_VERIFY:-0}" != "1" ]; then
      printf "\n${BOLD}=== checking it ===${NC}\n"
      cmd_doctor --domain "$DOMAIN" || true
    fi
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
    echo "$key: no session anchor — credentials resolve relative to the project ROOT. You must be inside a repo checkout (not your home folder) AND in an engine session: open the repo in Claude Code and type /do, or stand in that repo's sessions/ directory. (Raw equivalent: engine session activate <path>, from inside the checkout.)" >&2
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
  db-url)      shift; cmd_db_url "$@" ;;
  provision)   shift; cmd_provision "$@" ;;
  ""|-h|--help|help) sed -n "$USAGE_LINES" "$0" ;;
  *) echo "env: unknown subcommand '$1'" >&2; sed -n "$USAGE_LINES" "$0"; exit 1 ;;
esac
