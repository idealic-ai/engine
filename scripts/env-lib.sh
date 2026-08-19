#!/bin/bash
# env-lib.sh — the ONE dotfile-resolution rule shared by every engine credential loader.
#
# Sourced by slack-lib.sh, linear-lib.sh, ticket-search.sh and session.sh (and, through
# slack-lib.sh, by intake.sh), so a credential is looked for in the same places in the
# same order everywhere:
#
#   real env var
#     → any caller-preferred file (e.g. the manifest's preferred home)
#     → <anchor>/.env.local  →  <anchor>/.env
#
# <anchor> is the CURRENT SESSION's project root (env_anchor_dir), not $PWD — so the
# same credential resolves the same way from the repo root and from apps/api/src, and
# a write from a subdirectory lands where the reader will look. With NO session nothing
# resolves at all: the resolver returns ENV_NO_ANCHOR_RC, it never guesses.
#
# `.env.local` is the only file anything WRITES to and the first file read; `.env` stays
# in the chain as a read-only back-compat fallback. Nothing outside the anchored project
# is searched — a per-project credential comes from the project, never from a global file
# that would let one project's wave authenticate as another's.
#
# When a key resolves from ./.env.local while ./.env carries a DIFFERENT value, one line
# on stderr says so (never the value), so the precedence flip is visible, not silent.
#
# Dotfiles are UNTRUSTED: values are grepped out, never sourced.

# Resolve this file's own directory through any symlink chain — a test harness may
# link the lib into a fake HOME where the sibling skills/ tree does not exist.
_ENV_LIB_SRC="${BASH_SOURCE[0]:-$0}"
while [ -L "$_ENV_LIB_SRC" ]; do
  _ENV_LIB_DIR="$(cd -P "$(dirname "$_ENV_LIB_SRC")" && pwd)"
  _ENV_LIB_SRC="$(readlink "$_ENV_LIB_SRC")"
  case "$_ENV_LIB_SRC" in /*) ;; *) _ENV_LIB_SRC="$_ENV_LIB_DIR/$_ENV_LIB_SRC" ;; esac
done
_ENV_LIB_DIR="$(cd -P "$(dirname "$_ENV_LIB_SRC")" && pwd)"

# ── The credential manifest (per-domain JSON) ──────────────────────────────────
#
# Shape: { version, domain, credentials: [ { key, service, required, secret,
#          default, dotfile, how, check: {type[,server|name]}, source: {type,…} } ] }
#
# `jq` is a HARD prerequisite here, guarded explicitly. lib.sh already calls jq ~30
# times unguarded, so availability is an untested assumption of existing code — not a
# guarantee it provides. This is the engine's stated idiom (see lint-lib.sh).
env_require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  echo "env: jq is required to read a credential manifest — install it (brew install jq)" >&2
  return 1
}

# env_manifest_path [domain] → the manifest file for a domain. ENV_MANIFEST overrides.
env_manifest_path() {
  local domain="${1:-intake}"
  if [ -n "${ENV_MANIFEST:-}" ]; then printf '%s' "$ENV_MANIFEST"; return 0; fi
  # `core` is the ENGINE's own credential set — consumed by session.sh, gemini.sh,
  # slack-lib.sh, linear-lib.sh and ticket-search.sh, by zero skills. It lives beside
  # the scripts that read it (a sibling of this file), because filing it under skills/
  # would put it inside the tree of the thing it is defined as being independent of.
  if [ "$domain" = "core" ]; then printf '%s' "$_ENV_LIB_DIR/credentials.json"; return 0; fi
  printf '%s' "$_ENV_LIB_DIR/../skills/$domain/assets/credentials.json"
}

# env_manifest_rows [domain] → one record per line, fields separated by \037 (ASCII
# UNIT SEPARATOR), the character the encoding was invented for.
#
# US rather than @tsv or any printable delimiter: it needs no escaping, so a `how`
# string carrying quotes, backslashes, tabs or the old pipe character round-trips
# byte-exact, and it is NOT IFS whitespace so empty fields survive (`default` is
# routinely empty). Callers read with `IFS=$'\037' read -r …`.
#
# ⚠️ NOT \001: bash 3.2 (what macOS ships) DELETES a \001 in IFS instead of splitting
# on it — `IFS=$'\001' read -r p q < <(printf 'a\001b\n')` yields p=ab, q=empty.
#
# Field order (14): key service required secret default dotfile how check_type check_arg
#                   source_type source_name source_field source_region source_profile
#   secret     → the literal "true"/"false" (a shell string, not a JSON bool)
#   default    → "" when null
#   check_arg  → check.server (mcp) or check.name (binary); "" otherwise
env_manifest_rows() {
  local domain="${1:-intake}" mf
  env_require_jq || return 1
  mf="$(env_manifest_path "$domain")"
  [ -f "$mf" ] || { echo "env: manifest not found at $mf" >&2; return 1; }
  jq -r '
    .credentials[]
    | [ .key,
        (.service // ""),
        (if (.required // "") == "" then "optional" else .required end),
        (if .secret then "true" else "false" end),
        (.default // ""),
        (.dotfile // ""),
        (.how // ""),
        (if (.check.type // "") == "" then "file-key" else .check.type end),
        (.check.server // .check.name // ""),
        (.source.type // "prompt"),
        (.source.name // ""),
        (.source.field // ""),
        (.source.region // ""),
        (.source.profile // "") ]
    | join("\u001f")
  ' "$mf" || { echo "env: manifest at $mf is not valid JSON" >&2; return 1; }
}

# Extract a KEY=value from an env file WITHOUT sourcing it (dotfiles are untrusted).
# An optional `export ` prefix counts — dotfiles meant to be sourced use it. Matching
# lines are scanned in order and the FIRST NON-EMPTY one wins, so a blank `KEY=`
# placeholder above a real value (copy-the-template-then-append) does not mask it.
extract_env_key() {
  local file="$1" key="$2" line val
  [ -f "$file" ] || return 1
  while IFS= read -r line; do
    val="${line#*=}"
    val="$(printf '%s' "$val" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/')"
    [ -n "$val" ] && { printf '%s' "$val"; return 0; }
  done < <(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$file" 2>/dev/null)
  return 1
}

# ── The session anchor ────────────────────────────────────────────────────────
#
# Every engine invocation has a session; credentials resolve relative to THAT session's
# project root, so the answer does not change with which subdirectory you are standing
# in. `session.sh find` owns the lookup (its PID cache makes this cheap); the root is
# the nearest `.claude/` ancestor of the session dir, which is also what
# `resolve_sessions_dir` anchors to — so WORKSPACE nesting cannot pull the two apart.
#
# NO SESSION IS A `return`, NEVER AN `exit`. session.sh:875 calls resolve_env_key
# IN-PROCESS during `activate`; an exit-shaped throw there kills activation mid-flight.
ENV_NO_ANCHOR_RC=3

env_anchor_dir() {
  if [ -n "${_ENV_ANCHOR_CACHE+set}" ]; then
    [ -n "$_ENV_ANCHOR_CACHE" ] || return "$ENV_NO_ANCHOR_RC"
    printf '%s' "$_ENV_ANCHOR_CACHE"; return 0
  fi
  local sdir="" root="" d
  # Re-entry guard: if anything reached by `session.sh find` ever resolves a credential,
  # this returns "no anchor" instead of forking processes without bound.
  if [ -z "${_ENV_ANCHOR_RESOLVING:-}" ] && [ -x "$_ENV_LIB_DIR/session.sh" ]; then
    sdir="$(_ENV_ANCHOR_RESOLVING=1 "$_ENV_LIB_DIR/session.sh" find 2>/dev/null)" || sdir=""
  fi
  if [ -n "$sdir" ]; then
    # STRIP FIRST, THEN CLIMB — and in that order for a reason. `resolve_sessions_dir`
    # BUILDS the session path as  <root>[/<WORKSPACE>]/sessions/<name>, so inverting it
    # is: drop everything from the first /sessions/ segment (that lands on
    # <root>[/<WORKSPACE>]), then walk up to the nearest .claude marker (that climbs out
    # of the WORKSPACE subdir to <root>). Deriving the anchor by the exact inverse of how
    # the path was constructed is what keeps the two from drifting apart.
    #
    # ⚠️ NEITHER HALF IS CORRECT ALONE, and both failure modes are real:
    #   * climb-only is captured by ANY stray .claude in the chain — Projects/finch/
    #     sessions/.claude/ exists on this machine, and it made every credential in the
    #     repo-root .env read as absent while two independent read paths happily AGREED
    #     on the wrong directory;
    #   * strip-only stops at <root>/<WORKSPACE> under workspace nesting, where the
    #     dotfiles and the .claude marker live at <root>.
    # Stripping first also excludes the sessions/ subtree STRUCTURALLY — the climb never
    # visits it — rather than by a predicate that would have to stay in sync.
    case "$sdir" in
      */sessions/*) d="${sdir%%/sessions/*}" ;;
      *)            d="$sdir" ;;   # defensive: session.sh find always returns a path under sessions/
    esac
    root="$d"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
      if [ -d "$d/.claude" ]; then root="$d"; break; fi
      d="$(dirname "$d")"
    done
  fi
  _ENV_ANCHOR_CACHE="$root"
  [ -n "$root" ] || return "$ENV_NO_ANCHOR_RC"
  printf '%s' "$root"
}

# env_anchored_path REL -> REL resolved against the session anchor. An ABSOLUTE path
# passes through untouched (an explicit --env-file is a statement of intent, not a hint).
env_anchored_path() {
  local rel="$1" root
  [ -n "$rel" ] || return 1
  case "$rel" in /*) printf '%s' "$rel"; return 0 ;; esac
  root="$(env_anchor_dir)" || return "$ENV_NO_ANCHOR_RC"
  printf '%s/%s' "$root" "${rel#./}"
}

# env_key_files [preferred...] -> the dotfiles to search, one per line, most-preferred
# first, ANCHORED to the session's project root. Arguments sort ABOVE the defaults.
# Emits nothing and returns ENV_NO_ANCHOR_RC when there is no session.
# Dedup is exact-string on the resolved absolute path.
env_key_files() {
  local f root
  root="$(env_anchor_dir)" || return "$ENV_NO_ANCHOR_RC"
  {
    for f in "$@"; do
      [ -n "$f" ] || continue
      case "$f" in /*) printf '%s\n' "$f" ;; *) printf '%s/%s\n' "$root" "${f#./}" ;; esac
    done
    printf '%s/%s\n' "$root" ".env.local"
    printf '%s/%s\n' "$root" ".env"
  } | awk 'NF && !seen[$0]++'
}

# One stderr line when a key resolves from .env.local while the SIBLING .env — the one
# in the same directory, not whatever sits under $PWD — holds a DIFFERENT value for it.
# The VALUE is never printed, only the fact that the two files disagree.
notice_shadowed_env_key() {
  local key="$1" from="$2" val="$3" other dir
  [ "$(basename "$from")" = ".env.local" ] || return 0
  dir="$(dirname "$from")"
  other="$(extract_env_key "$dir/.env" "$key")" || return 0
  [ "$other" = "$val" ] && return 0
  printf '%s: using %s (a different value exists in %s)\n' "$key" "$from" "$dir/.env" >&2
}

# resolve_env_key KEY [preferred_file...] -> the value on stdout.
#   0 resolved | 1 nothing resolved | ENV_NO_ANCHOR_RC (3) no session anchor
# An empty value is NOT a resolution (mirrors extract_env_key) — presence-of-the-line
# is a different question, answered by env.sh's key_line_present.
resolve_env_key() {
  local key="$1"; shift
  local val="${!key:-}" f
  if [ -n "$val" ]; then printf '%s' "$val"; return 0; fi
  if ! env_anchor_dir >/dev/null 2>&1; then
    echo "env: no session anchor — credentials resolve relative to the current session's project root; run inside an engine session ($key was not looked up)" >&2
    return "$ENV_NO_ANCHOR_RC"
  fi
  while IFS= read -r f; do
    if val="$(extract_env_key "$f" "$key")" && [ -n "$val" ]; then
      notice_shadowed_env_key "$key" "$f" "$val"
      printf '%s' "$val"; return 0
    fi
  done < <(env_key_files "$@")
  return 1
}

# ── env_load_domain <domain> ──────────────────────────────────────────────────
#
# Resolves every env-var row a domain declares and assigns them into the CALLER's
# shell. This is a sourced FUNCTION, deliberately not a CLI verb:
#   * values move through shell variables, so NOTHING reaches stdout — no transcript,
#     hook-log or capture-pane exposure, for any domain;
#   * there is no per-key repetition at the call site (`env_load_domain prove`, done);
#   * status propagates normally, so `env_load_domain prove || return 1` works — a
#     command substitution would have swallowed it.
#
# Resolve-EVERYTHING-first, then assign: a failure leaves the caller's environment
# exactly as it was. Never a partial load.
#
# Only `file-key` / `env-present` rows are loaded — an mcp server or a binary probe is
# not an env var. A row that resolves nowhere falls back to the manifest's `default`,
# which is what collapses the duplicate source of truth for /prove's four defaults.
#
# `--env-file <path>` makes that ONE file authoritative: a real env var still wins, but
# nothing else is consulted and no session anchor is required. Same rule as
# `slack_token --env-file` — an explicit file is a statement of intent, never a hint —
# so a caller can pin an empty/absent file and be certain the operator's own dotfiles
# cannot leak in. It goes through the same extract_env_key; no second parser.
#
# Returns: 0 loaded · 1 a REQUIRED row is unset (or the manifest is unreadable)
#          2 a manifest key is not a valid env-var name · 3 no session anchor
env_load_domain() {
  local domain="" env_file="" explicit=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --env-file) env_file="${2:-}"; explicit=1; shift 2 ;;
      --env-file=*) env_file="${1#*=}"; explicit=1; shift ;;
      *) [ -n "$domain" ] && { echo "env_load_domain: unexpected argument '$1'" >&2; return 1; }
         domain="$1"; shift ;;
    esac
  done
  [ -n "$domain" ] || { echo "env_load_domain: a domain is required" >&2; return 1; }

  local rows
  rows="$(env_manifest_rows "$domain")" || return 1

  local key service required secret default dotfile how check arg src sname sfield sregion sprofile
  local val rc failed=0 n=0
  local -a load_keys=() load_vals=()

  while IFS=$'\037' read -r key service required secret default dotfile how check arg src sname sfield sregion sprofile; do
    case "$check" in file-key|env-present) ;; *) continue ;; esac
    # NO eval anywhere: the key is validated, then used with `export "$k=$v"`. A
    # malformed manifest key is refused outright rather than becoming code.
    printf '%s' "$key" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || {
      echo "env_load_domain: manifest key '$key' is not a valid env-var name (domain '$domain')" >&2
      return 2
    }
    if [ "$explicit" -eq 1 ]; then
      val="${!key:-}"
      [ -n "$val" ] || val="$(extract_env_key "$env_file" "$key" 2>/dev/null)" || val=""
    else
      val="$(resolve_env_key "$key" "$dotfile" 2>/dev/null)"; rc=$?
      if [ "$rc" -eq "$ENV_NO_ANCHOR_RC" ]; then
        echo "env_load_domain: no session anchor — cannot load domain '$domain'; run inside an engine session" >&2
        return "$ENV_NO_ANCHOR_RC"
      fi
    fi
    [ -n "$val" ] || val="$default"
    if [ -z "$val" ]; then
      if [ "$required" = "req" ]; then
        echo "env_load_domain: required credential $key is unset (domain '$domain') — $how" >&2
        failed=1
      fi
      continue
    fi
    load_keys[$n]="$key"; load_vals[$n]="$val"; n=$((n + 1))
  done <<< "$rows"

  [ "$failed" -eq 0 ] || return 1

  local i=0
  while [ "$i" -lt "$n" ]; do
    export "${load_keys[$i]}=${load_vals[$i]}"
    i=$((i + 1))
  done
  return 0
}

# ── env_fetch_aws_secret NAME [FIELD] [REGION] [PROFILE] ───────────────────────
#
# Fetches a secret's value from AWS Secrets Manager. Prints ONLY the value on stdout.
# Three outcomes get three distinct messages, because they need three different actions:
#   0  ok
#   4  AccessDenied — this account is not granted THIS secret (expected; policies are
#      scoped per person, so it means "ask for access", not "your setup is broken")
#   5  no/invalid credentials — the agent profile is missing or revoked
#   1  anything else
#
# ENV_AWS_SECRET_OUTPUT / ENV_AWS_SECRET_FAIL are TEST SEAMS so no test ever makes a
# real AWS call. Any active seam is announced loudly on stderr — a seam-influenced run
# must never be mistaken for a real one.
env_fetch_aws_secret() {
  local name="$1" field="${2:-}" region="${3:-}" profile="${4:-}" out rc err

  if [ -n "${ENV_AWS_SECRET_FAIL:-}" ]; then
    echo "env: ⚠️  TEST SEAM ACTIVE — ENV_AWS_SECRET_FAIL=$ENV_AWS_SECRET_FAIL (no AWS call was made)" >&2
    case "$ENV_AWS_SECRET_FAIL" in
      *AccessDenied*)
        echo "env: access denied fetching '$name' — this AWS account is not granted that secret. Ask for it to be added to your agent policy (the setup is otherwise fine)." >&2
        return 4 ;;
      *NoCredentials*|*ExpiredToken*|*InvalidClientTokenId*)
        echo "env: no usable AWS credentials for '$name' — the agent profile is missing or revoked. Install the delivered key with 'engine env setup --aws-key <path>'." >&2
        return 5 ;;
      *) echo "env: could not fetch '$name': $ENV_AWS_SECRET_FAIL" >&2; return 1 ;;
    esac
  fi

  if [ -n "${ENV_AWS_SECRET_OUTPUT+set}" ]; then
    echo "env: ⚠️  TEST SEAM ACTIVE — ENV_AWS_SECRET_OUTPUT is set (no AWS call was made)" >&2
    out="$ENV_AWS_SECRET_OUTPUT"
  else
    command -v aws >/dev/null 2>&1 || { echo "env: the aws CLI is required to fetch '$name'" >&2; return 1; }
    # An agent profile has NO ~/.aws/config block — that absence is what stops it
    # expiring — so it carries no region either, and the CLI refuses without one. Fall
    # back to the resolver rather than a hardcoded default, so the region stays a
    # manifest-owned value.
    [ -n "$region" ] || region="$(resolve_env_key AWS_REGION 2>/dev/null || true)"
    local args=(secretsmanager get-secret-value --secret-id "$name" --output json)
    [ -n "$region" ]  && args+=(--region "$region")
    [ -n "$profile" ] && args+=(--profile "$profile")
    err="$(mktemp)"
    out="$(aws "${args[@]}" 2>"$err")"; rc=$?
    if [ "$rc" -ne 0 ]; then
      if grep -qi 'AccessDenied\|not authorized' "$err"; then
        echo "env: access denied fetching '$name' — this AWS account is not granted that secret. Ask for it to be added to your agent policy (the setup is otherwise fine)." >&2
        rm -f "$err"; return 4
      fi
      if grep -qi 'Unable to locate credentials\|ExpiredToken\|InvalidClientTokenId\|could not be found' "$err"; then
        echo "env: no usable AWS credentials for '$name' — the agent profile is missing or revoked. Install the delivered key with 'engine env setup --aws-key <path>'." >&2
        rm -f "$err"; return 5
      fi
      echo "env: could not fetch '$name' (see AWS error above)" >&2
      sed 's/^/       /' "$err" >&2; rm -f "$err"; return 1
    fi
    rm -f "$err"
  fi

  env_require_jq || return 1
  local val
  if [ -n "$field" ]; then
    val="$(printf '%s' "$out" | jq -r --arg f "$field" '(.SecretString // "{}") | fromjson? // {} | .[$f] // empty' 2>/dev/null)"
  else
    val="$(printf '%s' "$out" | jq -r '.SecretString // empty' 2>/dev/null)"
  fi
  [ -n "$val" ] || { echo "env: '$name' returned no value${field:+ for field '$field'}" >&2; return 1; }
  printf '%s' "$val"
}

# ── env_infer_person [explicit] ────────────────────────────────────────────────
#
# Resolves the COMPANY identity an agent IAM principal is named after.
#   --person (explicit)  →  @finchclaims.com Google Drive  →  aws sts caller identity
#   →  fail loudly.
#
# 🚫 NEVER $USER, `git config user.email`, or gcloud. Measured on this machine: all
# three return `invizko` / `invizko@gmail.com` — the operator's PERSONAL identity, not
# their company one. Four of five candidate sources are wrong here, so a "sensible
# fallback" mints an IAM principal under the wrong name.
#
# The @finchclaims.com filter is LOAD-BEARING, not decoration: four Drives are mounted
# here and unfiltered the personal gmail sorts first and wins.
#
# Ambiguity is an ERROR, never a coin-flip — two company Drives, or a local part with
# anything outside [a-z0-9-] (firstname.lastname@), must demand --person rather than
# mangle a human name into an IAM principal.
env_infer_person() {
  local explicit="${1:-}"
  if [ -n "$explicit" ]; then printf '%s' "$explicit"; return 0; fi

  local root="${ENV_DRIVE_ROOT:-$HOME/Library/CloudStorage}" b lp found="" count=0
  if [ -d "$root" ]; then
    while IFS= read -r b; do
      case "$b" in
        GoogleDrive-*@finchclaims.com) ;;
        *) continue ;;
      esac
      lp="${b#GoogleDrive-}"; lp="${lp%@finchclaims.com}"
      [ "$lp" = "$found" ] && continue
      found="$lp"; count=$((count + 1))
    done < <(cd "$root" 2>/dev/null && ls -1 2>/dev/null | sort)
  fi

  if [ "$count" -gt 1 ]; then
    echo "env: more than one @finchclaims.com Google Drive is mounted — pass --person <name> rather than have one picked for you" >&2
    return 1
  fi
  if [ "$count" -eq 1 ]; then
    if printf '%s' "$found" | grep -qE '^[a-z0-9-]+$'; then printf '%s' "$found"; return 0; fi
    echo "env: the Drive local part '$found' is not a usable IAM principal name — pass --person <name> rather than have it mangled into one" >&2
    return 1
  fi

  # LAST resort. Deliberately not first: a brand-new teammate has no AWS account yet —
  # that is the entire point of onboarding — so sts cannot name them, but Drive can.
  local arn=""
  if [ -n "${ENV_STS_ARN+set}" ]; then
    arn="$ENV_STS_ARN"
  elif command -v aws >/dev/null 2>&1; then
    arn="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)"
  fi
  if [ -n "$arn" ]; then
    lp="${arn##*/}"
    if printf '%s' "$lp" | grep -qE '^[a-z0-9-]+$'; then printf '%s' "$lp"; return 0; fi
  fi

  echo "env: cannot determine who you are — no @finchclaims.com Google Drive and no AWS identity. Pass --person <name>. (\$USER, git email and gcloud are deliberately NOT consulted: they return your personal identity, not your company one.)" >&2
  return 1
}

# ── env_active_seams → the names of any TEST SEAM currently set ────────────────
# `provision` refuses outright when any is set: a seam makes a real IAM mutation run
# against faked inputs, and `Bash(engine *)` is blanket-allowed.
env_active_seams() {
  local s out=""
  for s in ENV_MANIFEST ENV_MCP_LIST_OUTPUT ENV_AWS_SECRET_OUTPUT ENV_AWS_SECRET_FAIL ENV_STS_ARN ENV_DRIVE_ROOT ENV_AWS_HOME; do
    eval "[ -n \"\${$s+set}\" ]" && out="$out $s"
  done
  printf '%s' "${out# }"
}
