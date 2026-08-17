#!/bin/bash
# env-lib.sh — the ONE dotfile-resolution rule shared by every engine credential loader.
#
# Sourced by slack-lib.sh, linear-lib.sh, ticket-search.sh and session.sh (and, through
# slack-lib.sh, by intake.sh), so a credential is looked for in the same places in the
# same order everywhere:
#
#   real env var
#     → any caller-preferred file (e.g. the manifest's preferred home)
#     → ./.env.local  →  ./.env
#
# `.env.local` is the only file anything WRITES to and the first file read; `.env` stays
# in the chain as a read-only back-compat fallback. Nothing outside the working directory
# is searched — a per-project credential comes from the project, never from a global file
# that would let one project's wave authenticate as another's.
#
# When a key resolves from ./.env.local while ./.env carries a DIFFERENT value, one line
# on stderr says so (never the value), so the precedence flip is visible, not silent.
#
# Dotfiles are UNTRUSTED: values are grepped out, never sourced.

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

# env_key_files [preferred...] → the dotfiles to search, one per line, most-preferred
# first. Arguments sort ABOVE the defaults. Dedup is EXACT-STRING: `.env.local` and
# `./.env.local` are different strings, so both survive and that file is grepped twice
# (wasteful, never wrong — the same value resolves either way).
env_key_files() {
  local f
  {
    for f in "$@"; do [ -n "$f" ] && printf '%s\n' "$f"; done
    printf '%s\n' "./.env.local" "./.env"
  } | awk 'NF && !seen[$0]++'
}

# One stderr line when a key resolves from .env.local while ./.env holds a DIFFERENT
# value for it. The VALUE is never printed — only the fact that the files disagree.
notice_shadowed_env_key() {
  local key="$1" from="$2" val="$3" other
  [ "${from#./}" = ".env.local" ] || return 0
  other="$(extract_env_key "./.env" "$key")" || return 0
  [ "$other" = "$val" ] && return 0
  printf '%s: using ./.env.local (a different value exists in ./.env)\n' "$key" >&2
}

# resolve_env_key KEY [preferred_file...] → the value on stdout; 1 if nothing resolved.
# An empty value is NOT a resolution (mirrors extract_env_key) — presence-of-the-line
# is a different question, answered by intake.sh's key_line_present.
resolve_env_key() {
  local key="$1"; shift
  local val="${!key:-}" f
  if [ -n "$val" ]; then printf '%s' "$val"; return 0; fi
  while IFS= read -r f; do
    if val="$(extract_env_key "$f" "$key")" && [ -n "$val" ]; then
      notice_shadowed_env_key "$key" "$f" "$val"
      printf '%s' "$val"; return 0
    fi
  done < <(env_key_files "$@")
  return 1
}
