#!/bin/bash
# receipt.sh — record and find receipts (a command run against an exact state, with its
# result) and gos (approvals keyed by patch-id), stored per repo in git notes.
#
# Usage:
#   engine receipt run [--seat S] [--summary S] -- <cmd...>
#   engine receipt find (--tree <t> | --commit <c> | --patch <id> | --here) [--all] [--json]
#   engine receipt go <patch-id> --form <form> [--paths a,b] --owner <O>
#                     [--seat S] [--commit <sha>] [--note TEXT] [--withdraw]
#   engine receipt check <rev-range> [--against <branch>]... [--form <form>]
#                        [--owner <O>=<path,path>]...
#   engine receipt id <sha> --form <form> [--paths a,b]
#   engine receipt sync [--remote R] [--no-push]
#
# Storage: notes on refs/notes/receipts. A key K of kind T is the object
# `printf 'receipt-key:T:K' | git hash-object -w --stdin`, so a tree hash, commit or patch-id
# is a direct lookup and the record survives rebases (it hangs on the id, not on a sha).
# Every write appends one JSON line; nothing is ever rewritten. Notes live in the common git
# dir, so every worktree of the repo reads them at once. Notes do not travel with a plain
# push; `sync` fetches the remote's notes, merges them (cat_sort_uniq: JSON lines are kept,
# duplicates dropped) and pushes the union back. It also adds a fetch refspec so a plain
# fetch brings the remote's notes into refs/notes/receipts-remote/<R>. It adds no push
# refspec, because a configured push refspec replaces what a bare `git push` pushes.
#
# Forms of a patch-id: whole | whole+text | path | path+text. "path" forms are computed as
# `git show [--text] <sha> -- <paths> | git patch-id --stable`; "whole" forms omit the paths.
# A go satisfies a check only in the form and paths it was given for.
#
# Exit codes: run passes the command's code through; find 0 when something is listed, 1 when
# nothing is; check 0 when every go is present and every merge is clean, 1 otherwise;
# 2 on usage errors.

set -uo pipefail

NOTES_REF="refs/notes/receipts"
TMP_REF_PREFIX="refs/notes/receipts-tmp"
RECEIPT_RETRIES="${RECEIPT_RETRIES:-60}"
FORMS="whole whole+text path path+text"

die() { echo "receipt: $*" >&2; exit 2; }

usage() { sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'; }

require_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
}

now_epoch() { date -u +%s; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }

key_object() {
  printf 'receipt-key:%s:%s' "$1" "$2" | git hash-object -w --stdin
}

repo_id() {
  local url
  url=$(git config --get remote.origin.url 2>/dev/null || true)
  if [ -n "$url" ]; then echo "$url"; return; fi
  (cd "$(git rev-parse --git-common-dir)" && pwd -P)
}

# The single seam for ownership: the owner of one path. With no declared map every path is
# "undeclared", and check requires a go for an undeclared path exactly as for an owned one.
# It fails closed: no answer this function gives ever makes a path free of a go.
owner_of_path() {
  echo "undeclared"
}

normalize_form() {
  case "$1" in
    whole|whole+text|path|path+text) echo "$1" ;;
    path-scoped) echo "path" ;;
    path-scoped+text) echo "path+text" ;;
    *) return 1 ;;
  esac
}

# Comma list -> sorted unique JSON array.
paths_json() {
  printf '%s' "$1" | tr ',' '\n' | sed '/^$/d' | sort -u | jq -R . | jq -sc .
}

# patch_id <sha> <form> <paths-json>; prints the id, or nothing for an empty diff.
patch_id() {
  local sha="$1" form="$2" pj="$3" textflag=() paths=()
  case "$form" in *+text) textflag=(--text) ;; esac
  case "$form" in
    path|path+text)
      while IFS= read -r p; do paths+=("$p"); done < <(jq -r '.[]' <<<"$pj")
      [ "${#paths[@]}" -gt 0 ] || return 0
      git show ${textflag[@]+"${textflag[@]}"} --no-color "$sha" -- "${paths[@]}" | git patch-id --stable | awk '{print $1}'
      ;;
    *)
      git show ${textflag[@]+"${textflag[@]}"} --no-color "$sha" | git patch-id --stable | awk '{print $1}'
      ;;
  esac
}

patch_cmd() {
  local sha="$1" form="$2" pj="$3" t="" p
  case "$form" in *+text) t=" --text" ;; esac
  case "$form" in
    path|path+text)
      p=$(jq -r 'map(@sh) | join(" ")' <<<"$pj")
      echo "git show${t} $sha -- $p | git patch-id --stable" ;;
    *) echo "git show${t} $sha | git patch-id --stable" ;;
  esac
}

# Tree hash of the working state. Clean: HEAD's tree. Dirty: a snapshot written through a
# private copy of the index, so the real index is never touched.
# Prints "<tree> <dirty:true|false>".
current_state() {
  local top st tmpd idx tree
  top=$(git rev-parse --show-toplevel)
  st=$(git -C "$top" status --porcelain=v1 --untracked-files=normal 2>/dev/null)
  if [ -z "$st" ] && git rev-parse -q --verify HEAD >/dev/null; then
    echo "$(git rev-parse 'HEAD^{tree}') false"
    return
  fi
  tmpd=$(mktemp -d)
  idx="$tmpd/index"
  cp "$(git rev-parse --path-format=absolute --git-path index)" "$idx" 2>/dev/null || true
  GIT_INDEX_FILE="$idx" git -C "$top" add -A -- . >/dev/null 2>&1
  tree=$(GIT_INDEX_FILE="$idx" git -C "$top" write-tree)
  rm -rf "$tmpd"
  if [ -z "$st" ]; then echo "$tree false"; else echo "$tree true"; fi
}

# write_notes <file>: each line "<object>\t<json>". All lines land in ONE compare-and-swap
# of refs/notes/receipts, retried until no other writer moved the ref in between.
write_notes() {
  local file="$1" attempt=0 old tmp new ok obj json
  while [ "$attempt" -lt "$RECEIPT_RETRIES" ]; do
    attempt=$((attempt + 1))
    old=$(git rev-parse -q --verify "$NOTES_REF" 2>/dev/null || true)
    tmp="$TMP_REF_PREFIX/$$-$RANDOM-$attempt"
    if [ -n "$old" ]; then git update-ref "$tmp" "$old" || continue; fi
    ok=1
    while IFS=$'\t' read -r obj json; do
      [ -n "$obj" ] || continue
      git notes --ref="$tmp" append -m "$json" "$obj" >/dev/null 2>&1 || { ok=0; break; }
    done < "$file"
    new=$(git rev-parse -q --verify "$tmp" 2>/dev/null || true)
    if [ "$ok" = 1 ] && [ -n "$new" ] \
      && git update-ref -m "receipt append" "$NOTES_REF" "$new" "${old:-}" 2>/dev/null; then
      git update-ref -d "$tmp" >/dev/null 2>&1
      return 0
    fi
    git update-ref -d "$tmp" >/dev/null 2>&1
    sleep "0.0$((RANDOM % 9 + 1))"
  done
  echo "receipt: could not write notes after $RECEIPT_RETRIES attempts" >&2
  return 1
}

read_notes() {
  local obj
  obj=$(key_object "$1" "$2")
  git notes --ref="$NOTES_REF" show "$obj" 2>/dev/null | sed '/^[[:space:]]*$/d'
}

# ---------------------------------------------------------------- run
cmd_run() {
  local seat="${FLEET_PANE:-unknown}" summary=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --seat) seat="${2:?--seat needs a value}"; shift 2 ;;
      --summary) summary="${2:?--summary needs a value}"; shift 2 ;;
      --) shift; break ;;
      *) die "run: unexpected '$1' (put the command after --)" ;;
    esac
  done
  [ $# -gt 0 ] || die "run: no command given after --"
  require_repo

  local commit tree dirty state out code tree_after changed=false
  commit=$(git rev-parse -q --verify HEAD 2>/dev/null || echo "")
  state=$(current_state); tree=${state% *}; dirty=${state#* }
  out=$(mktemp)
  "$@" 2>&1 | tee "$out"
  code=${PIPESTATUS[0]}
  state=$(current_state); tree_after=${state% *}
  [ "$tree_after" = "$tree" ] || changed=true
  if [ -z "$summary" ]; then
    summary=$(sed '/^[[:space:]]*$/d' "$out" | tail -n 1 | cut -c1-240)
  fi
  rm -f "$out"

  local argv cmdstr epoch iso rec notes
  argv=$(jq -nc '$ARGS.positional' --args -- "$@")
  cmdstr=$(printf '%q ' "$@"); cmdstr=${cmdstr% }
  epoch=$(now_epoch); iso=$(now_iso)
  notes=$(mktemp)
  for kk in tree commit; do
    local kv="$tree"; [ "$kk" = commit ] && kv="$commit"
    [ -n "$kv" ] || continue
    rec=$(jq -nc --arg kk "$kk" --arg kv "$kv" --arg repo "$(repo_id)" --arg commit "$commit" \
      --arg tree "$tree" --argjson dirty "$dirty" --argjson changed "$changed" \
      --arg tree_after "$tree_after" --arg seat "$seat" --argjson epoch "$epoch" \
      --arg iso "$iso" --argjson ms "$(now_ms)" --argjson argv "$argv" --arg cmd "$cmdstr" --argjson exit "$code" \
      --arg summary "$summary" \
      '{v:1, kind:"run", key_kind:$kk, key:$kv, repo:$repo, commit:$commit, tree:$tree,
        dirty:$dirty, changed_during_run:$changed, tree_after:$tree_after, seat:$seat,
        time:$epoch, time_ms:$ms, time_iso:$iso, argv:$argv, cmd:$cmd, exit:$exit, summary:$summary}')
    printf '%s\t%s\n' "$(key_object "$kk" "$kv")" "$rec" >> "$notes"
  done
  write_notes "$notes" || { rm -f "$notes"; exit "$code"; }
  rm -f "$notes"
  local mark=""
  [ "$dirty" = true ] && mark=" dirty"
  [ "$changed" = true ] && mark="$mark changed-during-run"
  echo "receipt: tree:$tree commit:${commit:-none} exit=$code${mark}" >&2
  return "$code"
}

# ---------------------------------------------------------------- find
cmd_find() {
  local kk="" kv="" all=false json=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --tree) kk=tree; kv="${2:?}"; shift 2 ;;
      --commit) kk=commit; kv="${2:?}"; shift 2 ;;
      --patch) kk=patch; kv="${2:?}"; shift 2 ;;
      --here) kk=here; shift ;;
      --all) all=true; shift ;;
      --json) json=true; shift ;;
      *) die "find: unexpected '$1'" ;;
    esac
  done
  [ -n "$kk" ] || die "find: give --tree, --commit, --patch or --here"
  require_repo
  if [ "$kk" = here ]; then
    local st; st=$(current_state); kk=tree; kv=${st% *}
    [ "${st#* }" = true ] && echo "receipt: working tree is dirty (snapshot tree $kv); dirty receipts are never reusable" >&2
  elif [ "$kk" = commit ] || [ "$kk" = tree ]; then
    kv=$(git rev-parse -q --verify "$kv^{object}" 2>/dev/null || echo "$kv")
  fi

  local lines; lines=$(read_notes "$kk" "$kv")
  local sel
  sel=$(printf '%s\n' "$lines" | sed '/^$/d' | jq -sc 'sort_by(.time_ms // (.time * 1000))[]' | jq -c --argjson all "$all" \
    'select($all or (.kind != "run") or ((.dirty|not) and ((.changed_during_run // false)|not)))')
  local incons
  incons=$(printf '%s\n' "$lines" | sed '/^$/d' | jq -sr \
    '[.[] | select(.kind=="run" and (.dirty|not) and ((.changed_during_run // false)|not))]
     | group_by(.cmd)[] | select((map(.exit)|unique|length) > 1)
     | "inconsistent: \(.[0].cmd) exited \(map(.exit)|unique|map(tostring)|join(" and ")) on this key"')
  if [ -z "$sel" ]; then
    echo "receipt: no ${all:+}receipts for $kk:$kv" >&2
    [ -n "$incons" ] && echo "$incons"
    return 1
  fi
  if [ "$json" = true ]; then
    printf '%s\n' "$sel"
  else
    printf '%s\n' "$sel" | jq -r '
      if .kind=="run" then
        "\(.time_iso) run  exit=\(.exit) seat=\(.seat) commit=\(.commit[0:12])\(if .dirty then " DIRTY" else "" end)\(if (.changed_during_run // false) then " CHANGED" else "" end)  \(.cmd)  -- \(.summary)"
      else
        "\(.time_iso) go\(if .withdrawn then "-withdrawn" else "" end)  owner=\(.owner) form=\(.form) paths=\(.paths|join(",")) giver=\(.giver)  \(.patch_id[0:12])\(if .verify != "" then "  verify: \(.verify)" else "" end)"
      end'
  fi
  [ -n "$incons" ] && echo "$incons"
  return 0
}

# ---------------------------------------------------------------- go
cmd_go() {
  local pid="${1:-}"; [ -n "$pid" ] && shift
  [[ "$pid" =~ ^[0-9a-f]{40}$ ]] || die "go: first argument must be a full 40-hex patch-id"
  local form="" paths="" owner="" seat="${FLEET_PANE:-unknown}" commit="" note="" withdraw=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --form) form=$(normalize_form "${2:-}") || die "go: --form must be one of: $FORMS"; shift 2 ;;
      --paths) paths="${2:?}"; shift 2 ;;
      --owner) owner="${2:?}"; shift 2 ;;
      --seat) seat="${2:?}"; shift 2 ;;
      --commit) commit="${2:?}"; shift 2 ;;
      --note) note="${2:?}"; shift 2 ;;
      --withdraw) withdraw=true; shift ;;
      *) die "go: unexpected '$1'" ;;
    esac
  done
  [ -n "$form" ] || die "go: --form is required ($FORMS)"
  [ -n "$owner" ] || die "go: --owner is required"
  case "$form" in
    path*) [ -n "$paths" ] || die "go: form $form needs --paths" ;;
    whole*) [ -z "$paths" ] || die "go: form $form covers the whole commit; drop --paths" ;;
  esac
  require_repo
  local pj; pj=$(paths_json "$paths")
  local verify=""
  if [ -n "$commit" ]; then
    commit=$(git rev-parse -q --verify "$commit^{commit}") || die "go: unknown commit '$commit'"
    local got; got=$(patch_id "$commit" "$form" "$pj")
    [ "$got" = "$pid" ] || die "go: $commit gives ${got:-an empty diff} in form $form, not $pid"
    verify=$(patch_cmd "$commit" "$form" "$pj")
  fi
  local rec notes
  rec=$(jq -nc --arg pid "$pid" --arg form "$form" --argjson paths "$pj" --arg owner "$owner" \
    --arg giver "$seat" --arg commit "$commit" --arg note "$note" --argjson wd "$withdraw" \
    --arg repo "$(repo_id)" --argjson epoch "$(now_epoch)" --arg iso "$(now_iso)" \
    --argjson ms "$(now_ms)" --arg verify "$verify" \
    '{v:1, kind:"go", key_kind:"patch", key:$pid, patch_id:$pid, form:$form, paths:$paths,
      owner:$owner, giver:$giver, commit:$commit, verify:$verify, note:$note,
      withdrawn:$wd, repo:$repo, time:$epoch, time_ms:$ms, time_iso:$iso}')
  notes=$(mktemp)
  printf '%s\t%s\n' "$(key_object patch "$pid")" "$rec" >> "$notes"
  printf '%s\t%s\n' "$(key_object index go)" "$rec" >> "$notes"
  write_notes "$notes" || { rm -f "$notes"; exit 1; }
  rm -f "$notes"
  echo "receipt: go${withdraw:+} patch:$pid form=$form owner=$owner$( [ "$withdraw" = true ] && echo ' WITHDRAWN')" >&2
}

# ---------------------------------------------------------------- id
cmd_id() {
  local sha="${1:-}"; [ -n "$sha" ] && shift || die "id: give a commit"
  local form="path+text" paths=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --form) form=$(normalize_form "${2:-}") || die "id: bad --form"; shift 2 ;;
      --paths) paths="${2:?}"; shift 2 ;;
      *) die "id: unexpected '$1'" ;;
    esac
  done
  require_repo
  local id; id=$(patch_id "$sha" "$form" "$(paths_json "$paths")")
  if [ -z "$id" ]; then echo "empty"; return 1; fi
  echo "$id"
}

# ---------------------------------------------------------------- check
# covers <go-paths-json> <path>: is path equal to or under one of the go's paths?
covers() {
  jq -e --arg p "$2" 'any(.[]; (sub("/+$";"")) as $q | $p == $q or ($p | startswith($q + "/")))' \
    <<<"$1" >/dev/null
}

cmd_check() {
  local range="" form="path+text" against=() owners=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --against) against+=("${2:?}"); shift 2 ;;
      --form) form=$(normalize_form "${2:-}") || die "check: --form must be one of: $FORMS"; shift 2 ;;
      --owner) owners+=("${2:?}"); shift 2 ;;
      -*) die "check: unexpected '$1'" ;;
      *) [ -z "$range" ] || die "check: one rev-range only"; range="$1"; shift ;;
    esac
  done
  [ -n "$range" ] || die "check: give a rev-range such as origin/dev..HEAD"
  require_repo
  local o; for o in "${owners[@]+"${owners[@]}"}"; do
    case "$o" in *=*) ;; *) die "check: --owner takes NAME=path,path" ;; esac
  done

  local commits; commits=$(git rev-list --reverse --no-merges "$range") || die "check: bad range '$range'"
  # Ordered by time, not line order: a notes merge (cat_sort_uniq) sorts the lines.
  local index; index=$(read_notes index go | jq -sc '
    sort_by(.time_ms // (.time * 1000)) | group_by([.patch_id, .form, (.paths|join(",")), .owner])
    | map(last) | map(select(.withdrawn|not))')
  local fail=0 c

  for c in $commits; do
    local subject touched
    subject=$(git log -1 --format=%s "$c")
    touched=$(git diff-tree --root --no-commit-id --name-only -r "$c")
    echo "commit ${c:0:12} $subject"

    # Gos that apply: the commit's id, recomputed in each recorded go's own form and paths.
    local applicable="[]" n i g gf gp gid
    n=$(jq 'length' <<<"$index")
    i=0
    while [ "$i" -lt "$n" ]; do
      g=$(jq -c ".[$i]" <<<"$index"); i=$((i + 1))
      gf=$(jq -r .form <<<"$g"); gp=$(jq -c .paths <<<"$g")
      gid=$(patch_id "$c" "$gf" "$gp")
      [ -n "$gid" ] && [ "$gid" = "$(jq -r .patch_id <<<"$g")" ] || continue
      applicable=$(jq -c --argjson g "$g" '. + [$g]' <<<"$applicable")
      echo "  go     owner=$(jq -r .owner <<<"$g") form=$gf paths=$(jq -r '.paths|join(",")' <<<"$g") id=${gid:0:12} by $(jq -r .giver <<<"$g") at $(jq -r .time_iso <<<"$g")"
    done

    # Requirements: explicit --owner specs, else one per owner from the ownership seam.
    local reqs=() spec p
    if [ "${#owners[@]}" -gt 0 ]; then
      reqs=("${owners[@]}")
    else
      local grouped=""
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        grouped+="$(owner_of_path "$p")"$'\t'"$p"$'\n'
      done <<<"$touched"
      while IFS= read -r spec; do [ -n "$spec" ] && reqs+=("$spec"); done < <(
        printf '%s' "$grouped" | awk -F'\t' '{a[$1]=a[$1] (a[$1]==""?"":",") $2} END {for (k in a) print k "=" a[k]}' | sort)
    fi

    for spec in "${reqs[@]+"${reqs[@]}"}"; do
      local who="${spec%%=*}" rpaths="${spec#*=}" rpj rid
      rpj=$(paths_json "$rpaths")
      case "$form" in
        whole*) rid=$(patch_id "$c" "$form" "[]") ;;
        *) rid=$(patch_id "$c" "$form" "$rpj") ;;
      esac
      local label="  need   owner=$who form=$form"
      case "$form" in path*) label="$label paths=$rpaths" ;; esac
      if [ -z "$rid" ]; then
        echo "$label: EMPTY (no diff under these paths; not an id, no go needed)"
        continue
      fi
      local mine
      mine=$(jq -c --arg w "$who" 'map(select($w == "undeclared" or .owner == $w))' <<<"$applicable")
      local sameform; sameform=$(jq -c --arg f "$form" 'map(select(.form == $f))' <<<"$mine")
      local ok=1 missing=""
      case "$form" in
        whole*) [ "$(jq length <<<"$sameform")" -gt 0 ] || ok=0 ;;
        *)
          while IFS= read -r p; do
            [ -n "$p" ] || continue
            if ! covers "$(jq -c '[.[].paths[]]' <<<"$sameform")" "$p"; then ok=0; missing+="$p,"; fi
          done < <(jq -r '.[]' <<<"$rpj")
          ;;
      esac
      if [ "$ok" = 1 ]; then
        echo "$label id=${rid:0:12}: OK"
        continue
      fi
      fail=1
      local other; other=$(jq -r --arg f "$form" '[.[] | select(.form != $f) | .form] | unique | join(",")' <<<"$mine")
      if [ -n "$other" ]; then
        echo "$label id=${rid:0:12}: FORM-MISMATCH (a go exists in form $other, not $form; it does not count)"
      else
        echo "$label id=${rid:0:12}: MISSING${missing:+ (uncovered: ${missing%,})}"
      fi
    done
  done

  local head base b mt
  head="${range##*..}"; [ -n "$head" ] || head=HEAD
  base="${range%%..*}"; [ "$base" = "$range" ] && base=""
  for b in ${base:+"$base"} "${against[@]+"${against[@]}"}"; do
    if mt=$(git merge-tree --write-tree --name-only "$b" "$head" 2>&1); then
      echo "merge-tree $head onto $b: clean"
    else
      fail=1
      echo "merge-tree $head onto $b: CONFLICT"
      printf '%s\n' "$mt" | sed -n '2,/^$/p' | sed '/^$/d' | sed 's/^/  /'
    fi
  done
  [ "$fail" = 0 ] && echo "check: ready (nothing was pushed)" || echo "check: NOT ready"
  return "$fail"
}

# ---------------------------------------------------------------- sync
cmd_sync() {
  local remote=origin push=true
  while [ $# -gt 0 ]; do
    case "$1" in
      --remote) remote="${2:?}"; shift 2 ;;
      --no-push) push=false; shift ;;
      *) die "sync: unexpected '$1'" ;;
    esac
  done
  require_repo
  git remote get-url "$remote" >/dev/null 2>&1 || die "sync: no remote '$remote'"
  local track="refs/notes/receipts-remote/$remote"
  local spec="+$NOTES_REF:$track"
  git config --get-all "remote.$remote.fetch" | grep -qxF "$spec" \
    || git config --add "remote.$remote.fetch" "$spec"

  local attempt=0
  while [ "$attempt" -lt 10 ]; do
    attempt=$((attempt + 1))
    git fetch -q "$remote" "$spec" 2>/dev/null || git update-ref -d "$track" 2>/dev/null
    if git rev-parse -q --verify "$track" >/dev/null; then
      merge_remote_notes "$track" || return 1
    fi
    [ "$push" = true ] || { echo "receipt: fetched and merged notes from $remote" >&2; return 0; }
    git rev-parse -q --verify "$NOTES_REF" >/dev/null || { echo "receipt: no notes to push" >&2; return 0; }
    if git push -q "$remote" "$NOTES_REF:$NOTES_REF" 2>/dev/null; then
      echo "receipt: notes synced with $remote" >&2
      return 0
    fi
    sleep "0.$((RANDOM % 5 + 1))"
  done
  echo "receipt: sync with $remote did not settle after $attempt attempts" >&2
  return 1
}

# Merge a fetched notes ref into ours on a temp ref, then compare-and-swap it in.
merge_remote_notes() {
  local theirs="$1" attempt=0 old tmp new
  while [ "$attempt" -lt "$RECEIPT_RETRIES" ]; do
    attempt=$((attempt + 1))
    old=$(git rev-parse -q --verify "$NOTES_REF" 2>/dev/null || true)
    if [ -z "$old" ]; then
      git update-ref "$NOTES_REF" "$(git rev-parse "$theirs")" "" 2>/dev/null && return 0
      continue
    fi
    tmp="$TMP_REF_PREFIX/$$-$RANDOM-merge-$attempt"
    git update-ref "$tmp" "$old" || continue
    if ! git notes --ref="$tmp" merge -q -s cat_sort_uniq "$theirs" >/dev/null 2>&1; then
      git update-ref -d "$tmp" >/dev/null 2>&1
      echo "receipt: notes merge from $theirs failed" >&2
      return 1
    fi
    new=$(git rev-parse "$tmp")
    git update-ref -d "$tmp" >/dev/null 2>&1
    [ "$new" = "$old" ] && return 0
    git update-ref -m "receipt merge" "$NOTES_REF" "$new" "$old" 2>/dev/null && return 0
  done
  return 1
}

main() {
  local sub="${1:-}"; [ -n "$sub" ] && shift
  case "$sub" in
    run) cmd_run "$@" ;;
    find) cmd_find "$@" ;;
    go) cmd_go "$@" ;;
    check) cmd_check "$@" ;;
    id) cmd_id "$@" ;;
    sync) cmd_sync "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "unknown subcommand '$sub'" ;;
  esac
}

main "$@"
