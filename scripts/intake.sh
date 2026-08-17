#!/bin/bash
# intake.sh — engine intake <doctor|setup|env-example>: operator credential scaffolding.
#
# One credential manifest (skills/intake/assets/CREDENTIALS.manifest) is the single
# source of truth; this command reads it to (a) VERIFY the operator's setup (doctor),
# (b) WALK the operator through the secret ones (setup), and (c) GENERATE the committed
# `.env.example` (env-example). All three derive from the manifest so the anti-drift
# tool does not itself drift.
#
# Usage:
#   engine intake doctor [--env-example <path>]   Red/green preflight of every credential.
#                                                 Exits non-zero iff a REQUIRED cred is missing
#                                                 (so a caller can gate). Reads no API secrets;
#                                                 the only network touch is the timed
#                                                 `claude mcp list` MCP-reachability probe.
#                                                 Seeds missing non-secret defaults into their
#                                                 dotfile. --env-example asserts a committed
#                                                 .env.example agrees with the manifest.
#   engine intake setup [--non-interactive]       Wizard: prompt for each missing SECRET row,
#                                                 write it to its gitignored dotfile.
#                                                 --non-interactive (alias --dry-run) echoes
#                                                 what it WOULD write, writes nothing.
#   engine intake env-example                     Print the manifest-derived `.env.example` to
#                                                 stdout (secret NAMES with empty values, non-
#                                                 secret defaults filled). Redirect to a file.
#
# `.env.local` is the one file an operator needs for the keys the manifest homes there,
# and the ONLY file a secret is ever written to. A key is READ from `.env.local` first and
# `.env` second (env-lib.sh owns the rule), so setups that keep keys in `.env` keep
# working. Rows the manifest pins to `.env` must stay there — their reader is out-of-band.
#
# Test seams:
#   INTAKE_MANIFEST         override the manifest path (default: the assets copy).
#   INTAKE_MCP_LIST_OUTPUT  when SET (even empty), used verbatim instead of `claude mcp list`
#                           (empty string = "command unavailable" → degrade to WARN).
#   (resolution is project-scoped: no global engine-home dotfile is ever consulted.)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# extract_env_key / resolve_env_key — grep a KEY=value out of a dotfile WITHOUT sourcing it.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/slack-lib.sh"

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

# --- Manifest ---
manifest_path() {
  if [ -n "${INTAKE_MANIFEST:-}" ]; then printf '%s' "$INTAKE_MANIFEST"; return 0; fi
  printf '%s' "$SCRIPT_DIR/../skills/intake/assets/CREDENTIALS.manifest"
}

# Emit manifest records (comments + blank lines stripped) on stdout.
manifest_rows() {
  local mf; mf="$(manifest_path)"
  [ -f "$mf" ] || { echo "intake: manifest not found at $mf" >&2; return 1; }
  grep -vE '^[[:space:]]*(#|$)' "$mf" | tr -d '\r'
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
writable_dotfiles() {
  local preferred="$1"
  { [ -n "$preferred" ] && printf '%s\n' "$preferred"
    printf '%s\n' "./.env.local"; } | awk 'NF && !seen[$0]++'
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
# key_present KEY DOTFILE CHECK → 0 present, 1 missing, 2 cannot-verify (mcp cmd absent).
key_present() {
  local key="$1" dotfile="$2" check="$3"
  case "$check" in
    file-key)
      # The manifest's dotfile is the PREFERRED home, not the only one searched:
      # resolve_env_key falls through to .env.local / .env / the engine-home pair.
      resolve_env_key "$key" "$dotfile" >/dev/null 2>&1 && return 0
      return 1 ;;
    env-present)
      [ -n "${!key:-}" ] && return 0
      return 1 ;;
    binary:*)
      command -v "${check#binary:}" >/dev/null 2>&1 && return 0
      return 1 ;;
    mcp:*)
      local out server_line; out="$(mcp_list_output)"
      [ -z "$out" ] && return 2
      server_line="$(printf '%s' "$out" | grep -E "^[[:space:]]*${check#mcp:}:" | head -1)"
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

# `claude mcp list` output, honoring the INTAKE_MCP_LIST_OUTPUT test seam.
mcp_list_output() {
  if [ -n "${INTAKE_MCP_LIST_OUTPUT+set}" ]; then printf '%s' "$INTAKE_MCP_LIST_OUTPUT"; return 0; fi
  command -v claude >/dev/null 2>&1 || return 0
  # `claude mcp list` probes each server over the network; bound it so a hung
  # endpoint can't stall the doctor. On timeout it prints nothing → cannot-verify WARN.
  local t=""
  if command -v timeout >/dev/null 2>&1; then t="timeout 15"
  elif command -v gtimeout >/dev/null 2>&1; then t="gtimeout 15"; fi
  $t claude mcp list 2>/dev/null || true
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
# (engine intake env-example). Do not hand-edit; regenerate after a manifest change.
#
# Each `--- <file> ---` group below names the file its keys belong in. They are NOT
# interchangeable, so copy each group into the file it names:
#   .env.local  — read from .env.local first and .env second (so an existing .env setup
#                 keeps working, and a key in both files resolves to the .env.local one),
#                 and the only file `engine intake doctor|setup` ever writes.
#   .env        — the home for those keys, and PROVE_S3_* are REQUIRED there: their
#                 reader (skills/prove/assets/_prove-s3-env.sh) never opens .env.local.
# Secrets carry an empty value here (never a real token). Non-secret defaults are filled.
#
# NOT dotfile keys (documented, set up out-of-band):
#   linear-server (MCP)  — interactive OAuth in Claude Code; all /intake writes are MCP-only
#   notion (MCP)         — interactive OAuth; project-creation / KB steps only
#   aws, session-manager-plugin — binaries; install AWS CLI v2 + the SSM plugin
#   AWS_PROFILE          — set via `aws sso login --profile <name>`, exported in your shell
#   FINCH_DB_RO_SECRET   — Secrets Manager name staging/finch/db-ro-url, fetched at runtime
#   PostHog              — unwired; handled manually via the PostHog UI
HDR
  local key service required secret default dotfile how check row
  local last_dotfile=""
  while IFS= read -r row; do
    check="${row##*|}"; IFS='|' read -r key service required secret default dotfile how <<< "${row%|*}"
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
  local key service required secret default dotfile how check row
  while IFS= read -r row; do
    check="${row##*|}"; IFS='|' read -r key service required secret default dotfile how <<< "${row%|*}"
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
  local env_example=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --env-example) env_example="${2:-}"; shift 2 ;;
      --env-example=*) env_example="${1#*=}"; shift ;;
      -h|--help) sed -n '11,36p' "$0"; return 0 ;;
      *) echo "intake doctor: unknown flag '$1'" >&2; return 1 ;;
    esac
  done

  printf "${BOLD}=== intake credentials ===${NC}\n"
  local key service required secret default dotfile how check rc row
  while IFS= read -r row; do
    check="${row##*|}"; IFS='|' read -r key service required secret default dotfile how <<< "${row%|*}"
    key_present "$key" "$dotfile" "$check"; rc=$?
    if [ "$rc" -eq 0 ]; then
      case "$check" in
        note) note "$key" "$how" ;;
        *)    pass "$key" "$service" ;;
      esac
      continue
    fi
    if [ "$rc" -eq 2 ]; then
      warn "$key" "cannot verify (claude mcp list unavailable) — $how"
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
        printf '%s=%s\n' "$key" "$default" >> "$dotfile" && seed "$key" "seeded default '$default' → $dotfile" \
          || warn "$key" "could not seed default into $dotfile — $how"
      fi
      continue
    fi
    report_miss "$required" "$key" "$how"
  done < <(manifest_rows)

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
      warn ".env.example" "DRIFT from manifest — regenerate with 'engine intake env-example > $env_example'"
      diff <(printf '%s\n' "$expected") <(printf '%s\n' "$committed") | sed 's/^/        /'
    fi
  fi

  # --- Summary ---
  printf "${BOLD}===${NC} "
  printf "${GREEN}%d PASS${NC} | ${YELLOW}%d WARN${NC} | " "$PASSES" "$WARNS"
  if [ "$FAILS" -gt 0 ]; then printf "${RED}%d FAIL${NC}\n" "$FAILS"; else printf "${GREEN}%d FAIL${NC}\n" "$FAILS"; fi

  # The structural gap this scaffolding cannot close: Linear/Notion MCP writes need
  # interactive OAuth, so a headless / cron wave can READ a project but never record the
  # outcome (save_comment / save_status_update are MCP-only). Surface it every run.
  printf "${CYAN}note:${NC} MCP writes (Linear, Notion) require an interactive OAuth session — headless/cron waves cannot post comments, status updates, or documents.\n"

  [ "$FAILS" -eq 0 ]
}

# --- setup ---
cmd_setup() {
  local dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --non-interactive|--dry-run) dry=1; shift ;;
      -h|--help) sed -n '11,36p' "$0"; return 0 ;;
      *) echo "intake setup: unknown flag '$1'" >&2; return 1 ;;
    esac
  done

  printf "${BOLD}intake setup${NC} — writes missing SECRET credentials to their gitignored dotfile.\n"
  [ "$dry" -eq 1 ] && printf "${YELLOW}(dry-run: nothing will be written)${NC}\n"
  printf "\n"

  # The manifest is read on fd 3 so the loop body's interactive `read -rs val`
  # reads the operator's input from stdin — not the next manifest row.
  local key service required secret default dotfile how check wrote=0 row
  while IFS= read -r row <&3; do
    check="${row##*|}"; IFS='|' read -r key service required secret default dotfile how <<< "${row%|*}"
    [ "$secret" = "true" ] || continue
    [ "$check" = "file-key" ] || continue   # only dotfile-backed secrets are wizard-writable
    if key_present "$key" "$dotfile" "$check"; then
      printf "  ${GREEN}have${NC}  %-22s (already set)\n" "$key"
      continue
    fi
    if [ "$dry" -eq 1 ]; then
      printf "  ${CYAN}would-write${NC}  %-22s → %s\n" "$key" "$dotfile"
      printf "        how: %s\n" "$how"
      wrote=$((wrote + 1))
      continue
    fi
    printf "  ${YELLOW}missing${NC}  %-22s\n        how: %s\n" "$key" "$how"
    printf "        enter value for %s (blank to skip): " "$key"
    local val=""
    read -rs val; printf "\n"
    [ -n "$val" ] || { printf "        skipped.\n"; continue; }
    # Quote on write so extract_env_key round-trips the value exactly (its read
    # strips one quote layer AFTER trimming, so surrounding/internal spaces survive).
    local quoted="\"$val\"" target
    if target="$(locate_key_line "$key" "$dotfile")"; then
      # A KEY= line already exists (present-but-empty, else key_present passed and we
      # never reached here) — fill it WHERE IT IS rather than appending a duplicate.
      fill_env_key "$target" "$key" "$quoted" && { printf "        wrote %s → %s (filled in place)\n" "$key" "$target"; wrote=$((wrote + 1)); } \
        || printf "        ${RED}failed${NC} to write %s\n" "$key"
    else
      printf '%s=%s\n' "$key" "$quoted" >> "$dotfile" && { printf "        wrote %s → %s\n" "$key" "$dotfile"; wrote=$((wrote + 1)); } \
        || printf "        ${RED}failed${NC} to write %s\n" "$key"
    fi
  done 3< <(manifest_rows)

  printf "\n"
  if [ "$dry" -eq 1 ]; then
    printf "${BOLD}dry-run:${NC} %d secret(s) would be prompted. Run without --non-interactive to write them.\n" "$wrote"
  else
    printf "${BOLD}done:${NC} %d secret(s) written. Run 'engine intake doctor' to verify.\n" "$wrote"
  fi
}

# --- Dispatch ---
case "${1:-}" in
  doctor)      shift; cmd_doctor "$@" ;;
  setup)       shift; cmd_setup "$@" ;;
  env-example) shift; gen_env_example ;;
  ""|-h|--help|help) sed -n '11,36p' "$0" ;;
  *) echo "intake: unknown subcommand '$1'" >&2; sed -n '11,36p' "$0"; exit 1 ;;
esac
