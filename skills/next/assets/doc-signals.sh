#!/bin/bash
# doc-signals.sh — /next's documentation-signal reading (NEXTDOCS). Finds documentation problems
# in the COMMITS since the last /next, routes each to the owning project's 🟦 Documentation
# channel, holds what has nowhere to go, and prints the `docs:` notice line.
#
# It POSTS NOTHING. Posting is /inbox-post's (skills/inbox-post/SKILL.md); this script only says
# what to post, what to hold and what an open comment already covers.
#
# A signal's file is always repo-keyed: `<repo-id>:<path>`, where repo-id is the basename of the
# repository's `origin` URL (worktrees of one repository share it), else of its top level.
#
# Subcommands (TSV = tab-separated, one row per line):
#
#   detect --repo DIR [--since REV] [--head REV] [--exclude GLOB]...
#       Reads the commits in REV..HEAD (--head names another end, for re-labelling a past range)
#       and nothing else: not the working tree, not untracked
#       files (another seat's half-written work is not this run's diff). Prints:
#         signal<TAB>kind<TAB>repo-id:path<TAB>subject
#       and, on stderr, `detect: range <rev>..<head>` (the head is the marker `apply` records).
#       REV defaults to the newest commit older than 24 hours. A REV that is not a commit, or not
#       an ancestor of HEAD, falls back to that default with a warning on stderr; it never fails.
#       An empty range (REV is HEAD) prints nothing and returns at once.
#       Docs are the *.md files committed at HEAD, read from the commit rather than the disk,
#       minus every --exclude glob (default: sessions/*,
#       */fixtures/*, fixtures/*, node_modules/*).
#       Exit 0 = no signal, 3 = signals found (a finding, not a failure), 2 = usage/git error.
#
#   plan --signals F --owners F --channels F [--open F] [--held F] [--sessions-root DIR]
#        [--max N] [--hold-kinds "K…"]
#       Pure: writes nothing. Routes every held row, then every new signal:
#         post<TAB>kind<TAB>file<TAB>project<TAB>channel<TAB>subject<TAB>new|held
#         hold<TAB>kind<TAB>file<TAB>project|-<TAB>reason<TAB>subject<TAB>new|held
#         dedup<TAB>kind<TAB>file<TAB>open-comment|held|repeat|marker-lost<TAB>subject<TAB>new|held
#       reasons: owner-unresolved · no-docs-channel · over-cap · detected-not-posted · marker-lost ·
#                posting-paused
#       Rows sharing a kind and file fold their subjects into the one row ("a; b; c"), so a post
#       names every finding. A held marker-lost row stays held: it is never re-posted.
#       The pause: marker-lost rows are read from --held and from every
#       <sessions-root>/*/NEXT_DOC_SIGNALS.tsv. Each one dedups its key, and while any of them is
#       not among the open keys, every postable row is held as posting-paused instead. It clears
#       when the lost comment's marker reads back (that row then leaves as dedup open-comment).
#       owners   = repo-id<TAB>prefix<TAB>project  (longest prefix within the same repo wins;
#                  project "-" claims a prefix for nobody, so its files stay owner-unresolved)
#       channels = project<TAB>channel             (the project's 🟦 Documentation channel)
#       open     = kind<TAB>repo-id:path           (the channel's open comments, from open-keys)
#       --max N (default 3): at most N post rows; the rest are held as over-cap.
#       --hold-kinds (default "redundancy"): kinds detected but held as detected-not-posted.
#       Exit 2 on a kind outside the vocabulary.
#
#   apply --plan F --held F [--posted F] [--lost F] [--since-repo DIR --since-sha SHA]
#       The one write, under a lock. MERGES into the held file: every earlier held row the plan
#       does not mention is kept; plan `hold` rows are written; a `post` row not in --posted
#       stays held as post-not-landed, or as marker-lost when it is in --lost; a posted or
#       deduped row leaves. Other repositories' since-markers are kept. Records the since-marker
#       for DIR (realpath of its top level). A missing plan, or a failed write, exits 2.
#       Run it after every accepted plain run and every `all` run, with 0 signals too.
#
#   since --held F --repo DIR [--sessions-root DIR]
#       Prints the recorded since-sha for DIR. With none in F, seeds from the newest marker for
#       DIR in any <sessions-root>/*/NEXT_DOC_SIGNALS.tsv, naming the file on stderr.
#
#   notice --mode all|plain|stopped --plan F [--posted F] [--lost F]
#       Prints the one `docs:` line: posted (all) or to post (plain) items, this run's holds with
#       their reasons, the owner-unresolved files, the over-cap items, and the carried holds as
#       counts. It leads with this run's --lost posts, then with the pause (the posting-paused
#       items) while a marker-lost row is held. `stopped` is for a run that ended before the step.
#
#   open-keys        reads comment bodies on stdin, prints kind<TAB>key for the last marker
#                    `doc-signal: <kind> <key>` on each line. Tolerates inline code, **bold**, a
#                    [text](url) link or <autolink> around the key, and markdown escapes
#                    (`my\_guide.md`). The key runs to the end of the line (a path may hold a
#                    space), ended earlier by a code span or a ", " / "; " list separator; a
#                    trailing [.,;:)>] is dropped; the kind is lowercased.
#   landed --open F KIND KEY   the read-back guard after each /inbox-post: exit 0 "landed" when
#                    KIND KEY is among the open keys read back from the channel, else exit 1
#                    "marker-lost". posted-file rows are written only for a landed key.
#   registry-channels REGISTRY.md   prints project<TAB>channel for each 🟦 row in the registry.
#   owners-from-doc --repo DIR [--repo-id ID] FILE
#       Derives owner rows from an "Ownership is fixed" line in the file the repository names:
#       each lane's paths, the lane → project list, and the sub-path overrides. Emits a path
#       only when it exists at DIR's HEAD; every item it skips is named on stderr. A lane that
#       maps to "none" emits its paths with project "-". Path-level override rows may be appended.
#       THE FORMAT IT PARSES (pinned; a reshape of the source must keep it, or this exits 2):
#         - **Ownership is fixed.**                         the anchor, a top-level bullet
#           - <Lane>[ (…)|, …]: <paths, comma/"and" list>   a lane's paths, up to the first ";"
#           - Which Linear project receives …               the lane → project list
#             - <Lane>: <Project|none>[ (…)]
#             - A sub-path inside a lane …                  the overrides, longest prefix winning
#               - `<path>`[ and `<path>`]: <Project>[ (…)]
#       Exit 2, with the reason on stderr, when the anchor or the list is missing or no row comes
#       out: an empty map is never returned at exit 0.
#
# Kind vocabulary (¶INV_NEXT_DOC_KINDS): undocumented-feature · stale-reference · redundancy ·
# contradiction · other. `detect` emits the first three; the last two are for a signal an agent
# raises by hand and routes through `plan` like any other.
set -uo pipefail

KINDS="undocumented-feature stale-reference redundancy contradiction other"
TAB=$'\t'
# The whole-corpus scans run under the fastest awk on the path: measured on the engine tree
# (473 docs), the scan took 1.7 s CPU under /usr/bin/awk and 0.3 s under mawk.
FAST_AWK=$(command -v mawk || command -v gawk || echo awk)

die() { echo "doc-signals: $*" >&2; exit 2; }
warn() { echo "doc-signals: $*" >&2; }

# canon <dir> → realpath of the repository top level (or of the dir when it is not a repo)
canon() {
  local top
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || top="$1"
  (cd "$top" 2>/dev/null && pwd -P) || printf '%s\n' "$top"
}

repo_id() {
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null)
  if [ -n "$url" ]; then url="${url%.git}"; url="${url%/}"; printf '%s\n' "${url##*[/:]}"
  else basename "$(canon "$1")"; fi
}

# not_feature_source <path> → 0 for files that are never a command, a flag source or a route:
# tests, confs, backups, type declarations, docs, and private helpers (`_name`)
not_feature_source() {
  case "${1##*/}" in _*) return 0 ;; esac    # a leading underscore marks a private helper
  case "$1" in
    *.md|*.test.*|*.spec.*|*/__tests__/*|__tests__/*|*/tests/*|tests/*|*/test/*|test/*|*.conf|*.bak*|*.d.ts) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------- detect
cmd_detect() {
  local repo="" since="" headrev="HEAD" excludes=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --since) since="${2:-}"; shift 2 ;;
      --head) headrev="${2:-}"; shift 2 ;;
      --exclude) excludes+=("${2:-}"); shift 2 ;;
      *) die "detect: unknown argument $1" ;;
    esac
  done
  [ -n "$repo" ] || die "detect: --repo is required"
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "detect: not a git repository: $repo"
  [ ${#excludes[@]} -gt 0 ] || excludes=("sessions/*" "*/fixtures/*" "fixtures/*" "node_modules/*")
  repo=$(canon "$repo")
  local rid head; rid=$(repo_id "$repo"); head=$(git -C "$repo" rev-parse --verify -q "$headrev^{commit}") || die "detect: cannot resolve --head $headrev"

  local fallback
  fallback=$(git -C "$repo" rev-list -n1 --before='24 hours ago' "$head" 2>/dev/null)
  [ -n "$fallback" ] || fallback=$(git -C "$repo" rev-list --max-parents=0 "$head" | tail -1)
  if [ -n "$since" ]; then
    if ! git -C "$repo" rev-parse --verify -q "$since^{commit}" >/dev/null; then
      warn "detect: since $since is not a commit here; falling back to the last 24 hours"; since=$fallback
    elif ! git -C "$repo" merge-base --is-ancestor "$since" "$head" 2>/dev/null; then
      warn "detect: since $since is not an ancestor of HEAD; falling back to the last 24 hours"; since=$fallback
    fi
  else
    since=$fallback
  fi
  since=$(git -C "$repo" rev-parse "$since^{commit}")
  echo "detect: range $since..$head" >&2
  [ "$since" = "$head" ] && return 0     # S6: nothing committed since the marker

  local work; work=$(mktemp -d "${TMPDIR:-/tmp}/doc-signals.XXXXXX")
  trap 'rm -rf "$work"' RETURN

  git -C "$repo" diff --name-status -M "$since" "$head" >"$work/changes" || die "detect: git diff failed"
  [ -s "$work/changes" ] || return 0
  git -C "$repo" ls-tree -r "$head" >"$work/tree"

  # Docs: *.md committed at HEAD, minus excluded globs, read from the commit (one archive) so a
  # half-written doc in the working tree neither suppresses nor raises a signal.
  # The archive is extracted lazily (mirror_docs), only when a query or an added line needs it.
  local f ex skip mirror="$work/mirror"
  mirror_docs() {
    [ -d "$mirror" ] && return 0
    mkdir -p "$mirror"
    git -C "$repo" archive --format=tar "$head" -- ':(glob)**/*.md' 2>/dev/null | tar -x -C "$mirror" 2>/dev/null
  }
  : >"$work/docs"
  while IFS= read -r f; do
    skip=0
    for ex in "${excludes[@]}"; do case "$f" in $ex) skip=1 ;; esac; done
    [ $skip -eq 0 ] && printf '%s\n' "$f" >>"$work/docs"
  done < <(awk -F'\t' '$2 ~ /\.md$/ {print $2}' "$work/tree")

  # is_command <path>: executable at HEAD and starts with a shebang. A sourced helper is mode
  # 100644 or has no shebang; tests, confs and backups are never commands.
  # The executable set is read once into one string; a lookup is an in-process case match, so
  # a range of hundreds of changed files spawns no process per file to ask "is it executable".
  local nl=$'\n' execs
  execs="$nl$(awk -F'\t' '{split($1, m, " ")} m[1] == "100755" {print $2}' "$work/tree")$nl"
  is_command() {
    not_feature_source "$1" && return 1
    case "$execs" in *"$nl$1$nl"*) ;; *) return 1 ;; esac
    [ "$(git -C "$repo" show "$head:$1" 2>/dev/null | head -c 2)" = "#!" ]
  }
  # Flags a script handles: case arms (`--x)`, `-h|--help)`, `"--x"|--y=*)`) and test
  # expressions (`[ "$1" = --x ]`, `[[ $a == --x ]]`).
  flags_of() {
    grep -E "^[[:space:]]*[\"']?-{1,2}[A-Za-z0-9][^)]*\)" 2>/dev/null | sed 's/).*//' | grep -oE -- '--[a-z][a-z0-9-]*'
  }
  flags_tested() {
    grep -oE '\$\{?[0-9A-Za-z_@]+\}?"?[[:space:]]*==?[[:space:]]*"?--[a-z][a-z0-9-]*' 2>/dev/null | grep -oE -- '--[a-z][a-z0-9-]*'
  }
  routes_of() {
    grep -oE "\.(get|post|put|patch|delete|all)\([[:space:]]*[\"'\`]/[^\"'\`]*" 2>/dev/null | grep -oE "/[^\"'\`]*\$"
  }
  bin_keys() {   # bin_keys <package.json content file> → one bin name per line
    python3 -I -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
b = d.get("bin")
if isinstance(b, str):
    print(d.get("name", "").split("/")[-1])
elif isinstance(b, dict):
    for k in b: print(k)
' "$1" 2>/dev/null
  }

  # Phase 1 — queries: id, want, mode, needle, own-prefix, file, subject.
  #   want=absent  → fires when NO doc outside own-prefix carries any needle of that id
  #   want=present → every doc carrying the needle is a signal (file = that doc)
  #   mode F fixed · W bounded both sides by a non-[A-Za-z0-9_-] · R bounded on the right only
  #   mode P a path: the whole path token around the hit must resolve to the needle, read as
  #     repo-relative, as relative to the doc's own directory (`./x`, `../x`), or as an absolute
  #     path ending in /<needle>. So `handbook/handbook/x` is not a mention of `handbook/x`.
  local status path newpath name dir q="$work/queries" out="$work/signals" id=0 tok pre post cur old
  : >"$q"; : >"$out"
  query() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$q"; }
  while IFS="$TAB" read -r status path newpath; do
    id=$((id + 1))
    cur="$path"; old="$path"
    case "$status" in R*) cur="$newpath" ;; esac
    case "$status" in
      A*)
        case "$path" in
          skills/*/SKILL.md|*/skills/*/SKILL.md)
            dir="${path%/SKILL.md}"; name="${dir##*/}"
            query "$id" absent R "/$name" "$dir/" "$path" "new skill /$name: no doc names /$name or skills/$name"
            query "$id" absent R "skills/$name" "$dir/" "$path" "new skill /$name: no doc names /$name or skills/$name" ;;
          *)
            if is_command "$path"; then
              name="${path##*/}"; name="${name%.*}"
              query "$id" absent W "$name" "" "$path" "new command $name with no doc mention"
            fi ;;
        esac ;;
      D*) query "$id" present P "$path" "" "-" "names removed path $path" ;;
      R*) query "$id" present P "$path" "" "-" "names $path, renamed to $newpath" ;;
    esac
    case "$status" in M*|R*) ;; *) continue ;; esac
    # A new flag: handled at HEAD and absent from the whole pre-image, so a moved, reflowed or
    # edited arm is not new. Only for commands; an added command is covered by its own signal.
    if is_command "$cur"; then
      pre=$(git -C "$repo" show "$since:$old" 2>/dev/null)
      post=$(git -C "$repo" show "$head:$cur" 2>/dev/null)
      while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        printf '%s\n' "$pre" | grep -qE -- "${tok}([^a-z0-9-]|\$)" && continue
        id=$((id + 1))
        query "$id" absent W "$tok" "" "$cur" "new flag $tok with no doc mention"
      done < <({ printf '%s\n' "$post" | flags_of; printf '%s\n' "$post" | flags_tested; } | sort -u)
    fi
    # TypeScript: a new route string in a changed source file.
    case "$cur" in *.ts|*.tsx|*.mts|*.js|*.mjs)
      not_feature_source "$cur" && continue
      pre=$(git -C "$repo" show "$since:$old" 2>/dev/null)
      post=$(git -C "$repo" show "$head:$cur" 2>/dev/null)
      while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        printf '%s\n' "$pre" | grep -qF -- "$tok" && continue
        id=$((id + 1))
        query "$id" absent R "$tok" "" "$cur" "new route $tok with no doc mention"
      done < <(printf '%s\n' "$post" | routes_of | sort -u) ;;
    esac
  done <"$work/changes"
  # TypeScript: a new bin in any changed or added package.json.
  while IFS="$TAB" read -r status path newpath; do
    case "$status" in R*) path="$newpath" ;; esac
    case "$path" in package.json|*/package.json) ;; *) continue ;; esac
    case "$path" in node_modules/*|*/node_modules/*) continue ;; esac
    git -C "$repo" show "$since:$path" >"$work/pkg.pre" 2>/dev/null || : >"$work/pkg.pre"
    git -C "$repo" show "$head:$path" >"$work/pkg.post" 2>/dev/null || continue
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      bin_keys "$work/pkg.pre" | grep -qxF -- "$tok" && continue
      id=$((id + 1))
      query "$id" absent W "$tok" "" "$path" "new bin $tok with no doc mention"
    done < <(bin_keys "$work/pkg.post" | sort -u)
  done < <(awk -F'\t' '$1 ~ /^[AMR]/' "$work/changes")

  # Phase 2 — one pass over every doc answers every query.
  : >"$work/hits"
  if [ -s "$q" ] && [ -s "$work/docs" ]; then
    mirror_docs
    (cd "$mirror" && tr '\n' '\0' <"$work/docs" | xargs -0 "$FAST_AWK" -F'\t' -v queries="$q" '
      function word(c) { return c ~ /[A-Za-z0-9_-]/ }
      function pathc(c) { return c ~ /[A-Za-z0-9_.\/~-]/ }
      function normp(p,   parts, n, i, out, k, st) {     # collapse . and .. segments
        n = split(p, parts, "/"); k = 0
        for (i = 1; i <= n; i++) {
          if (parts[i] == "" || parts[i] == ".") continue
          if (parts[i] == "..") { if (k > 0) k--; continue }
          st[++k] = parts[i]
        }
        out = ""; for (i = 1; i <= k; i++) out = out (i > 1 ? "/" : "") st[i]
        return out
      }
      # Search for the basename, then judge the whole path token around each hit, so a
      # doc-relative link (`./std.idea`) is found as well as a repo-relative one.
      function pathhit(line, needle, docdir,   i, off, rest, s0, e0, tok, base) {
        base = needle; sub(/^.*\//, "", base)
        rest = line; off = 0
        while ((i = index(rest, base)) > 0) {
          s0 = off + i; e0 = s0 + length(base) - 1
          while (s0 > 1 && pathc(substr(line, s0 - 1, 1))) s0--
          while (e0 < length(line) && pathc(substr(line, e0 + 1, 1))) e0++
          tok = substr(line, s0, e0 - s0 + 1); sub(/[.,:;]+$/, "", tok)
          if (tok ~ /^\.\.?\//) { if (normp(docdir "/" tok) == needle) return 1 }
          else if (tok ~ /^[~\/]/) { if (length(tok) > length(needle) && substr(tok, length(tok) - length(needle)) == "/" needle) return 1 }
          else if (tok == needle || normp(docdir "/" tok) == needle) return 1
          off += i; rest = substr(line, off + 1)
        }
        return 0
      }
      function has(line, needle, mode,   i, off, rest, before, after, dd) {
        if (mode == "F") return index(line, needle) > 0
        if (mode == "P") { dd = FILENAME; if (dd !~ /\//) dd = ""; else sub(/\/[^\/]*$/, "", dd); return pathhit(line, needle, dd) }
        rest = line; off = 0
        while ((i = index(rest, needle)) > 0) {
          before = (off + i > 1) ? substr(line, off + i - 1, 1) : ""
          after = substr(line, off + i + length(needle), 1)
          if (!word(after) && (mode == "R" || !word(before))) return 1
          off += i; rest = substr(line, off + 1)
        }
        return 0
      }
      BEGIN { while ((getline l < queries) > 0) { n++; split(l, a, "\t"); qid[n] = a[1]; qmode[n] = a[3]; qneedle[n] = a[4]; qown[n] = a[5] } }
      FNR == 1 { for (k in hit) delete hit[k] }
      {
        for (k = 1; k <= n; k++) {
          if ((k in hit) || (qown[k] != "" && index(FILENAME, qown[k]) == 1)) continue
          if (has($0, qneedle[k], qmode[k])) { hit[k] = 1; print qid[k] "\t" FILENAME }
        }
      }') >"$work/hits"
  fi

  # Phase 3 — hits become signals.
  awk -F'\t' -v OFS='\t' -v hits="$work/hits" -v rid="$rid" '
    BEGIN { while ((getline l < hits) > 0) { split(l, a, "\t"); found[a[1]] = 1; docs[a[1]] = docs[a[1]] "\t" a[2] } }
    $2 == "absent"  { if (!($1 in found)) want[$1] = rid ":" $6 "\t" $7; else want[$1] = "" }
    $2 == "present" && ($1 in found) {
      m = split(substr(docs[$1], 2), ds, "\t")
      for (i = 1; i <= m; i++) print "signal", "stale-reference", rid ":" ds[i], $7
    }
    END { for (k in want) if (want[k] != "") print "signal", "undocumented-feature", want[k] }' "$q" >>"$out"

  # Redundancy: a long line (>= 80 chars, whitespace-normalised) ADDED in the range that one or
  # two other docs already carry verbatim, reported once per unordered pair. A passage that 3+
  # other docs carry is a shared convention, not a redundancy this change introduced.
  : >"$work/added"
  git -C "$repo" diff -U0 "$since" "$head" -- '*.md' | awk -v OFS="$TAB" '
    /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); next }
    /^\+/ && f != "/dev/null" { print f, substr($0, 2) }' >"$work/added"
  if [ -s "$work/added" ] && [ -s "$work/docs" ]; then
    mirror_docs
    (cd "$mirror" && tr '\n' '\0' <"$work/docs" | xargs -0 "$FAST_AWK" -v added="$work/added" -v docs="$work/docs" -v rid="$rid" '
      # No tolower: mawk lowercases bytes and mangles UTF-8; matching stays case-sensitive.
      function norm(x) { gsub(/[[:space:]]+/, " ", x); sub(/^ /, "", x); sub(/ $/, "", x); return x }
      BEGIN {
        while ((getline d < docs) > 0) isdoc[d] = 1
        while ((getline l < added) > 0) {
          t = index(l, "\t"); f = substr(l, 1, t - 1); line = norm(substr(l, t + 1))
          if (!(f in isdoc) || length(line) < 80 || line ~ /^```/) continue
          # Not `owner[line] = (line in owner) ? … : f`: mawk creates the lvalue before it tests
          # membership, so that form always takes the first branch and prefixes an empty owner.
          if (line in owner) owner[line] = owner[line] SUBSEP f; else owner[line] = f
        }
      }
      {
        line = norm($0)
        if (!(line in owner)) next
        if ((line SUBSEP FILENAME) in carried) next
        carried[line SUBSEP FILENAME] = 1
        holders[line] = holders[line] SUBSEP FILENAME
      }
      END {
        for (line in holders) {
          h = split(substr(holders[line], 2), hs, SUBSEP)
          n = split(owner[line], fs, SUBSEP)
          for (i = 1; i <= n; i++) {
            others = 0
            for (j = 1; j <= h; j++) if (hs[j] != fs[i]) others++
            if (others == 0 || others > 2) continue
            for (j = 1; j <= h; j++) if (hs[j] != fs[i]) {
              a = fs[i]; b = hs[j]
              pair = (a < b) ? a SUBSEP b : b SUBSEP a
              if (pair in done) continue
              done[pair] = 1
              printf "signal\tredundancy\t%s:%s\trepeats a passage of %s\n", rid, a, b
            }
          }
        }
      }') >>"$out"
  fi

  sort -u "$out"
  [ -s "$out" ] && return 3 || return 0
}

# ---------------------------------------------------------------- plan
lost_rows() { awk -F"$TAB" '$1 == "held" && $5 == "marker-lost" {print $2 "\t" $3}' "$1"; }

cmd_plan() {
  local signals="" owners="" channels="" open="" held="" root="" max=3 holdkinds="redundancy"
  while [ $# -gt 0 ]; do
    case "$1" in
      --signals) signals="$2"; shift 2 ;;
      --sessions-root) root="$2"; shift 2 ;;
      --owners) owners="$2"; shift 2 ;;
      --channels) channels="$2"; shift 2 ;;
      --open) open="$2"; shift 2 ;;
      --held) held="$2"; shift 2 ;;
      --max) max="$2"; shift 2 ;;
      --hold-kinds) holdkinds="$2"; shift 2 ;;
      *) die "plan: unknown argument $1" ;;
    esac
  done
  [ -n "$signals" ] && [ -n "$owners" ] && [ -n "$channels" ] || die "plan: --signals, --owners and --channels are required"
  case "$max" in ''|*[!0-9]*) die "plan: --max takes a whole number" ;; esac
  local nul=/dev/null lostf f rc
  # Every marker-lost row any seat holds: this session's file and each one under the sessions root.
  lostf=$(mktemp "${TMPDIR:-/tmp}/doc-lost.XXXXXX") || die "plan: cannot make a temp file"
  {
    [ -n "$held" ] && [ -f "$held" ] && lost_rows "$held"
    if [ -n "$root" ] && [ -d "$root" ]; then
      for f in "$root"/*/NEXT_DOC_SIGNALS.tsv; do [ -f "$f" ] && lost_rows "$f"; done
    fi
  } >"$lostf"
  awk -F"$TAB" -v OFS="$TAB" -v kinds="$KINDS" -v holdkinds="$holdkinds" -v max="$max" -v lostf="$lostf" \
      -v owners="$owners" -v channels="$channels" -v open="${open:-$nul}" -v held="${held:-$nul}" -v sigs="$signals" '
    function owner(key,   c, r, path, k, best, bl, p) {
      c = index(key, ":"); r = substr(key, 1, c - 1); path = substr(key, c + 1)
      best = ""; bl = -1
      for (k in own) {
        split(k, p, SUBSEP)
        if (p[1] != r) continue
        if (index(path, p[2]) == 1 && length(p[2]) > bl) { best = own[k]; bl = length(p[2]) }
      }
      return best
    }
    # Rows are buffered so that a later row sharing a key (S3) folds its subject into the first
    # one: one post per file and kind, naming every finding, never a silent "deduped".
    function emit(t, kind, file, c4, c5, subject, source, key) {
      out[++no] = t; o2[no] = kind; o3[no] = file; o4[no] = c4; o5[no] = c5; o6[no] = subject; o7[no] = source
      rowof[key] = no
    }
    function route(kind, file, subject, source, reason,   key, proj, r) {
      if (!(kind in okkind)) { printf "doc-signals: plan: kind \"%s\" is not in the vocabulary\n", kind > "/dev/stderr"; bad = 1; return }
      key = kind SUBSEP file
      if (key in routed) {
        r = rowof[key]
        if (index("; " o6[r] "; ", "; " subject "; ") == 0) { o6[r] = o6[r] "; " subject; return }   # fold
        if (source == "new") emit("dedup", kind, file, (key in heldkey) ? "held" : "repeat", "", subject, source, key "\034d" no)
        return
      }
      routed[key] = 1
      if ((tolower(kind) SUBSEP tolower(file)) in opened) { emit("dedup", kind, file, "open-comment", "", subject, source, key); return }
      proj = owner(file)
      # A marker-lost row stays held: its comment exists but cannot be read back, so posting it
      # again is exactly the duplicate the read-back guard exists to stop.
      if (reason == "marker-lost") { emit("hold", kind, file, (proj == "" ? "-" : proj), "marker-lost", subject, source, key); return }
      # Another seat posted this key and its marker did not read back: that comment covers it.
      if ((tolower(kind) SUBSEP tolower(file)) in lost) { emit("dedup", kind, file, "marker-lost", "", subject, source, key); return }
      if (proj == "" || proj == "-") { emit("hold", kind, file, "-", "owner-unresolved", subject, source, key); return }
      if (!(proj in chan) || chan[proj] == "") { emit("hold", kind, file, proj, "no-docs-channel", subject, source, key); return }
      if (kind in holdk) { emit("hold", kind, file, proj, "detected-not-posted", subject, source, key); return }
      # While any seat holds a marker-lost row, /inbox-post is dropping markers: post nothing.
      if (paused) { emit("hold", kind, file, proj, "posting-paused", subject, source, key); return }
      if (posts >= max) { emit("hold", kind, file, proj, "over-cap", subject, source, key); return }
      posts++
      emit("post", kind, file, proj, chan[proj], subject, source, key)
    }
    BEGIN {
      n = split(kinds, ks, " "); for (i = 1; i <= n; i++) okkind[ks[i]] = 1
      n = split(holdkinds, ks, " "); for (i = 1; i <= n; i++) holdk[ks[i]] = 1
      while ((getline l < owners) > 0) {
        if (l ~ /^#/ || l == "") continue
        split(l, a, "\t"); if (a[3] == "") continue
        own[a[1] SUBSEP a[2]] = a[3]
      }
      while ((getline l < channels) > 0) { if (l ~ /^#/ || l == "") continue; split(l, a, "\t"); chan[a[1]] = a[2] }
      while ((getline l < open) > 0)     { if (l ~ /^#/ || l == "") continue; split(l, a, "\t"); opened[tolower(a[1]) SUBSEP tolower(a[2])] = 1 }
      # A lost key whose comment now reads back has cleared; any other one pauses posting.
      while ((getline l < lostf) > 0) {
        split(l, a, "\t"); k = tolower(a[1]) SUBSEP tolower(a[2])
        if (!(k in opened)) { lost[k] = 1; paused = 1 }
      }
      # held rows first: they were found earlier, and a held row whose channel now exists posts.
      while ((getline l < held) > 0) {
        if (l !~ /^held\t/) continue
        split(l, a, "\t"); heldkey[a[2] SUBSEP a[3]] = 1; route(a[2], a[3], a[6], "held", a[5])
      }
      while ((getline l < sigs) > 0) {
        if (l !~ /^signal\t/) continue
        split(l, a, "\t"); route(a[2], a[3], a[4], "new", "")
      }
      for (i = 1; i <= no; i++) {
        if (out[i] == "dedup") print out[i], o2[i], o3[i], o4[i], o6[i], o7[i]
        else print out[i], o2[i], o3[i], o4[i], o5[i], o6[i], o7[i]
      }
      exit bad ? 2 : 0
    }'
  rc=$?
  rm -f "$lostf"
  return $rc
}

# ---------------------------------------------------------------- apply
cmd_apply() {
  local plan="" held="" posted="" lost="" srepo="" ssha=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --plan) plan="$2"; shift 2 ;;
      --held) held="$2"; shift 2 ;;
      --posted) posted="$2"; shift 2 ;;
      --lost) lost="$2"; shift 2 ;;
      --since-repo) srepo="$2"; shift 2 ;;
      --since-sha) ssha="$2"; shift 2 ;;
      *) die "apply: unknown argument $1" ;;
    esac
  done
  [ -n "$plan" ] && [ -n "$held" ] || die "apply: --plan and --held are required"
  [ -f "$plan" ] || die "apply: no plan at $plan"
  [ -z "$posted" ] || [ -f "$posted" ] || die "apply: no posted file at $posted"
  [ -z "$lost" ] || [ -f "$lost" ] || die "apply: no lost file at $lost"
  [ -n "$srepo" ] && srepo=$(canon "$srepo")
  # N5: two /next runs sharing one session directory take turns. A lock older than 5 minutes was
  # left by a run killed past its trap (kill -9); apply takes well under a second.
  local lock="$held.lock" tries=0 tmp=""
  until mkdir "$lock" 2>/dev/null; do
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then
      warn "apply: breaking a stale lock $lock (older than 5 minutes)"; rmdir "$lock" 2>/dev/null; continue
    fi
    tries=$((tries + 1)); [ $tries -lt 100 ] || die "apply: $lock is held by another run"
    sleep 0.1
  done
  trap 'rm -f "$tmp"; rmdir "$lock" 2>/dev/null' EXIT
  trap 'rm -f "$tmp"; rmdir "$lock" 2>/dev/null; trap - EXIT; exit 143' INT TERM HUP
  local now rc nul=/dev/null
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  tmp=$(mktemp "${held}.XXXXXX") || { rmdir "$lock"; die "apply: cannot write next to $held"; }
  awk -F"$TAB" -v OFS="$TAB" -v now="$now" -v srepo="$srepo" -v ssha="$ssha" \
      -v oldheld="$([ -f "$held" ] && echo "$held" || echo $nul)" -v posted="${posted:-$nul}" -v lost="${lost:-$nul}" '
    BEGIN {
      print "# /next documentation signals — held until the owning project has a 🟦 Documentation channel."
      print "# Written only by skills/next/assets/doc-signals.sh apply. Row: held, kind, file, project, reason, subject, first-seen."
      print "# Marker: # since, repo (realpath), sha, utc."
      while ((getline l < posted) > 0) { split(l, a, "\t"); done[a[1] SUBSEP a[2]] = 1 }
      while ((getline l < lost) > 0)   { split(l, a, "\t"); gone[a[1] SUBSEP a[2]] = 1 }
    }
    {
      if ($1 == "hold" || $1 == "post" || $1 == "dedup") inplan[$2 SUBSEP $3] = 1
      plan[++np] = $0
    }
    END {
      while ((getline l < oldheld) > 0) {
        split(l, a, "\t")
        if (l ~ /^# since\t/) { if (a[2] != srepo || ssha == "") marker[a[2]] = l; continue }
        if (l !~ /^held\t/) continue
        key = a[2] SUBSEP a[3]
        first[key] = a[7]
        if (!(key in inplan) && !(key in done)) keep[++nk] = l     # S2: merge, never drop
      }
      for (r in marker) print marker[r]
      if (srepo != "" && ssha != "") print "# since", srepo, ssha, now
      for (i = 1; i <= nk; i++) print keep[i]
      for (i = 1; i <= np; i++) {
        split(plan[i], a, "\t")
        key = a[2] SUBSEP a[3]
        fs = (key in first && first[key] != "") ? first[key] : now
        if (a[1] == "hold") print "held", a[2], a[3], a[4], a[5], a[6], fs
        else if (a[1] == "post" && (key in gone)) print "held", a[2], a[3], a[4], "marker-lost", a[6], fs
        else if (a[1] == "post" && !(key in done)) print "held", a[2], a[3], a[4], "post-not-landed", a[6], fs
      }
    }' "$plan" >"$tmp"
  rc=$?
  if [ $rc -ne 0 ] || ! mv "$tmp" "$held"; then
    rm -f "$tmp"; rmdir "$lock" 2>/dev/null; trap - EXIT INT TERM HUP; die "apply: write failed (awk exit $rc); the held file is unchanged"
  fi
  rmdir "$lock" 2>/dev/null
  trap - EXIT INT TERM HUP
  return 0
}

cmd_since() {
  local held="" repo="" root=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --held) held="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      --sessions-root) root="$2"; shift 2 ;;
      *) die "since: unknown argument $1" ;;
    esac
  done
  [ -n "$repo" ] || die "since: --repo is required"
  repo=$(canon "$repo")
  local s="" best f
  [ -n "$held" ] && [ -f "$held" ] &&
    s=$(awk -F"$TAB" -v r="$repo" '$1 == "# since" && $2 == r {s = $3} END {if (s != "") print s}' "$held")
  if [ -z "$s" ] && [ -n "$root" ] && [ -d "$root" ]; then
    best=$(for f in "$root"/*/NEXT_DOC_SIGNALS.tsv; do
             [ -f "$f" ] || continue
             awk -F"$TAB" -v r="$repo" -v f="$f" '$1 == "# since" && $2 == r {print $4 "\t" $3 "\t" f}' "$f"
           done | sort | tail -1)
    if [ -n "$best" ]; then
      s=$(printf '%s\n' "$best" | cut -f2)
      warn "since: seeded from $(printf '%s\n' "$best" | cut -f3) (marker of $(printf '%s\n' "$best" | cut -f1))"
    fi
  fi
  [ -n "$s" ] && printf '%s\n' "$s"
  return 0
}

# ---------------------------------------------------------------- notice
cmd_notice() {
  local mode="" plan="" posted="" lost=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode) mode="$2"; shift 2 ;;
      --plan) plan="$2"; shift 2 ;;
      --posted) posted="$2"; shift 2 ;;
      --lost) lost="$2"; shift 2 ;;
      *) die "notice: unknown argument $1" ;;
    esac
  done
  case "$mode" in all|plain|stopped) ;; *) die "notice: --mode all|plain|stopped" ;; esac
  [ -f "$plan" ] || die "notice: no plan at $plan"
  local nul=/dev/null
  awk -F"$TAB" -v mode="$mode" -v posted="${posted:-$nul}" -v lost="${lost:-$nul}" '
    function add(arr, item) { return arr == "" ? item : arr "; " item }
    function list(n, s, cap,   parts, m, i, out) {      # at most cap items, then "+k more"
      if (n == 0) return ""
      m = split(s, parts, "; "); out = ""
      for (i = 1; i <= m && i <= cap; i++) out = add(out, parts[i])
      if (m > cap) out = out "; +" (m - cap) " more"
      return " (" out ")"
    }
    BEGIN {
      while ((getline l < posted) > 0) { split(l, a, "\t"); done[a[1] SUBSEP a[2]] = (a[5] == "" ? "posted" : a[5]) }
      while ((getline l < lost) > 0)   { split(l, a, "\t"); gone[a[1] SUBSEP a[2]] = (a[5] == "" ? "no link" : a[5]) }
    }
    $1 == "post" {
      key = $2 SUBSEP $3
      if (mode != "all") { np++; P = add(P, $2 " " $3 " → " $4 " " $5); next }
      if (key in done)      { np++; P = add(P, $2 " " $3 " → " $4 " " $5 " (" done[key] ")") }
      else if (key in gone) { nl++; L = add(L, $2 " " $3 " → " $4 " " $5 " (" gone[key] ")") }
      else                  { nh++; H = add(H, $2 " " $3 ": post-not-landed") }
      next
    }
    $1 == "hold" && $5 == "posting-paused"   { nz++; Z = add(Z, $2 " " $3); next }
    $1 == "hold" && $5 == "marker-lost"      { held_lost = 1 }
    $1 == "hold" && $5 == "owner-unresolved" { nu++; U = add(U, $3) }
    $1 == "hold" && $5 == "over-cap"         { nc++; C = add(C, $2 " " $3) }
    $1 == "hold" && $7 == "held" { carried[$5]++; ncar++; next }
    $1 == "hold" && $5 != "owner-unresolved" && $5 != "over-cap" { nh++; H = add(H, $2 " " $3 ": " $5 ($4 == "-" ? "" : " (" $4 ")")) }
    $1 == "dedup" { nd++ }
    END {
      verb = (mode == "all") ? "posted" : (mode == "plain") ? "will post" : "would post"
      head = (mode == "stopped") ? "docs: not posted — the run stopped before the docs step, nothing held, re-detected next run; " : "docs: "
      cs = ""; for (r in carried) cs = add(cs, carried[r] " " r)
      # The lost posts of this run lead the line; a pause carried from an earlier loss comes next.
      ml = nl ? "marker-lost — " nl list(nl, L, 5) ", posting paused until its marker reads back; " : ""
      if (nz || (held_lost && !nl)) ml = ml "posting paused — " nz list(nz, Z, 5) " while a marker-lost comment is held; "
      printf "%s%s%s — %d%s; held — %d%s; owner-unresolved — %d%s; over-cap — %d%s; carried — %d%s; deduped — %d\n", \
        head, ml, verb, np, list(np, P, 10), nh, list(nh, H, 5), nu, list(nu, U, 5), nc, list(nc, C, 5), ncar, (ncar ? " (" cs ")" : ""), nd
    }' "$plan"
}

cmd_open_keys() {
  # Normalise each line (drop **bold**, unwrap [text](url), unescape markdown escapes), then read
  # the last marker on it. The key runs to the end of the line, so a path may hold a space; an
  # inline-code span, a list separator (", " "; " " · " " | " " — "), and trailing [.,;:)>] end it.
  sed -E -e 's/\*\*//g' -e 's/\[([^]]*)\]\([^)]*\)/\1/g' -e 's/\\([][\\`*_{}()#+.!<>|-])/\1/g' |
    awk -v OFS='\t' '
      {
        low = tolower($0); p = 0
        while ((i = index(substr(low, p + 1), "doc-signal:")) > 0) p += i
        if (!p) next
        rest = substr($0, p + 11)
        if (!match(rest, /^[[:space:]]*[A-Za-z-]+[[:space:]]+/)) next
        kind = substr(rest, 1, RLENGTH); rest = substr(rest, RLENGTH + 1)
        gsub(/[[:space:]]/, "", kind)
        sub(/^`/, "", rest)
        if ((e = index(rest, "`")) > 0) rest = substr(rest, 1, e - 1)
        if (match(rest, /(, |; | · | \| | — )/)) rest = substr(rest, 1, RSTART - 1)
        sub(/^</, "", rest); sub(/[[:space:].,;:)>]+$/, "", rest)
        if (rest != "") print tolower(kind), rest
      }' | sort -u
}

# landed --open F KIND KEY — the read-back guard. Exit 0 and print "landed" when KIND KEY is among
# the open keys read back from the channel after a post; exit 1 and print "marker-lost" otherwise.
cmd_landed() {
  local open="" kind="" key=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --open) open="$2"; shift 2 ;;
      *) if [ -z "$kind" ]; then kind="$1"; else key="$1"; fi; shift ;;
    esac
  done
  [ -n "$open" ] && [ -f "$open" ] && [ -n "$kind" ] && [ -n "$key" ] || die "landed: --open FILE KIND KEY"
  if awk -F'\t' -v k="$(printf '%s' "$kind" | tr 'A-Z' 'a-z')" -v f="$(printf '%s' "$key" | tr 'A-Z' 'a-z')" \
       'tolower($1) == k && tolower($2) == f {hit = 1} END {exit hit ? 0 : 1}' "$open"; then
    echo landed; return 0
  fi
  echo marker-lost; return 1
}

cmd_registry_channels() {
  local reg="${1:-}"; [ -f "$reg" ] || die "registry-channels: no registry at $reg"
  awk '
    /^## / { proj = substr($0, 4); next }
    /🟦/ && proj != "" && match($0, /[A-Z]+-[0-9]+/) { printf "%s\t%s\n", proj, substr($0, RSTART, RLENGTH) }' "$reg"
}

# ---------------------------------------------------------------- owners-from-doc
cmd_owners_from_doc() {
  local repo="" rid="" file="" rev=HEAD emit=project
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) repo="$2"; shift 2 ;;
      --repo-id) rid="$2"; shift 2 ;;
      --rev) rev="${2:-}"; shift 2 ;;
      --emit) emit="${2:-}"; shift 2 ;;
      *) file="$1"; shift ;;
    esac
  done
  [ -n "$repo" ] && [ -n "$file" ] && [ -f "$file" ] && [ -n "$rev" ] || die "owners-from-doc: --repo DIR [--repo-id ID] [--rev REV] [--emit project|lane] FILE"
  case "$emit" in project|lane) ;; *) die "owners-from-doc: --emit takes project or lane" ;; esac
  [ -n "$rid" ] || rid=$(repo_id "$repo")
  local tree; tree=$(mktemp "${TMPDIR:-/tmp}/doc-owners.XXXXXX")
  git -C "$repo" ls-tree -r --name-only "$rev" >"$tree" || { rm -f "$tree"; die "owners-from-doc: cannot list $repo at $rev"; }
  "$FAST_AWK" -v rid="$rid" -v tree="$tree" -v mode="$emit" -v rev="$rev" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    # kind_of <path> → "file", "dir" or "" (a trailing * is a name-prefix glob: "glob")
    function kind_of(p,   q, t) {
      if (p ~ /\*$/) { q = substr(p, 1, length(p) - 1); for (t in files) if (index(t, q) == 1) return "glob"; return "" }
      if (p in files) return "file"
      q = (p ~ /\/$/) ? p : p "/"
      for (t in files) if (index(t, q) == 1) return "dir"
      return ""
    }
    # elsewhere <p> → 1 when p is not a path at REV but is the tail of one ("main.ts" for
    # world-runner/src/ideas-app/server/main.ts): the doc names a real file by a partial path.
    function elsewhere(p,   t, q) {
      q = "/" p; sub(/\/$/, "", q)
      for (t in files) if (length(t) > length(q) && substr(t, length(t) - length(q) + 1) == q) return 1
      for (t in files) if (index(t, q "/")) return 1
      return 0
    }
    function emit(lane, p, kind,   k, bt) {
      p = trim(p); bt = (p ~ /`/); gsub(/`/, "", p); sub(/^\.\//, "", p); sub(/[[:space:]]*(—|-|\.)$/, "", p); p = trim(p)
      if (p == "") return
      if (p ~ /[[:space:]]/) { skipped[++ns] = lane ": " p " (prose, not a path)"; slane[ns] = lane; return }
      k = kind_of(p)
      if (k == "" && kind == "unread") return      # a guard on a path that is not there guards nothing
      if (k == "") { skipped[++ns] = lane ": " p " (not at " rev ")"; slane[ns] = lane; sabs[ns] = bt && elsewhere(p); return }
      if (k == "dir" && p !~ /\/$/) p = p "/"
      if (kind == "shared") { if (!(p in shared)) { shared[p] = 1; sh[++nsh] = p }; return }
      if (kind == "unread") { if (!(p in ur)) { ur[p] = lane; urt[p] = utext; urp[++nur] = p }; return }
      if (kind == "override") over[p] = lane; else if (!((lane SUBSEP p) in seen)) { seen[lane SUBSEP p] = 1; lp[++nl] = lane; pp[nl] = p }
    }
    # item <lane> <text>: a backticked path inside it wins; otherwise the bare text, if it is one word
    function item(lane, t,   rest) {
      if (t ~ /`[^`]+`/) {
        rest = t
        while (match(rest, /`[^`]+`/)) { emit(lane, substr(rest, RSTART, RLENGTH), "lane"); rest = substr(rest, RSTART + RLENGTH) }
        return
      }
      sub(/ except .*$/, "", t); sub(/^the /, "", t)
      emit(lane, t, "lane")
    }
    # lane_end: --emit lane. Rows "<path>\t<seat>" for every lane whose key names a seat, then
    # "<path>\tshared" for each shared-ground path. A lane is a key that names a seat, or one the
    # lane → project list names (which then must name a seat). Refusals (xrc 2): no anchor; a
    # listed lane with no seat; a backticked lane item that is not a path at REV but is the tail of
    # one (the doc names a real file by a partial path, so that file would fall to a shorter
    # prefix owner unseen); no row. Any other miss (a bare word, `.idea`, `--check`, a file not
    # landed yet) is a name, not a path, and is only named on stderr.
    function lane_end(   i, l, p) {
      if (!anchor) { print "owners-from-doc: no \"- **Ownership is fixed.**\" line in this file" > "/dev/stderr"; xrc = 2; return }
      for (l in project) if (!(l in seatof)) { print "owners-from-doc: lane \"" l "\" names no seat (a fleet name as its key, or a backticked one in its parenthetical); the seat map is unread" > "/dev/stderr"; xrc = 2 }
      for (i = 1; i <= ns; i++) if (sabs[i] && slane[i] in seatof) { print "owners-from-doc: lane " skipped[i] "; the seat map is unread" > "/dev/stderr"; xrc = 2 }
      if (xrc) return
      for (i = 1; i <= nl; i++) {
        l = lp[i]; p = pp[i]
        if (!(l in seatof)) continue
        if ((p SUBSEP seatof[l]) in out) continue
        out[p SUBSEP seatof[l]] = 1; rows++; has[seatof[l]] = 1; rowseat[p] = seatof[l]
        print p "\t" seatof[l]
      }
      for (i = 1; i <= nsh; i++) { print sh[i] "\tshared"; rows++ }
      # A guard is dropped when a lane row gives the same path and the guarding sentence names
      # that row seat: the sentence agrees with the lane (the theme sentence naming app:writer
      # beside app:writer own design/cli-theme/ row).
      for (i = 1; i <= nur; i++) {
        p = urp[i]
        if ((p in rowseat) && index(urt[p], rowseat[p])) continue
        print p "\tunread\t" ur[p]
      }
      # A lane the line names that yields no path: a path of its may map to no seat, and the
      # refusal then names it rather than saying the path has no owner.
      for (l in seatof) { print "# lane " seatof[l]; if (!(seatof[l] in has)) print "# uncovered " seatof[l] }
      if (!rows) { print "owners-from-doc: the Ownership line yielded no row; the seat map is unread" > "/dev/stderr"; xrc = 2 }
    }
    # unread <label> <text>: every backticked path in text is named by a sentence the parser cannot
    # assign; --emit lane prints it as a guard row "<path>\tunread\t<label>", which go-request refuses.
    function unread(label, t,   all) {
      all = t
      while (match(t, /`[^`]+`/)) { utext = all; emit(label, substr(t, RSTART, RLENGTH), "unread"); t = substr(t, RSTART + RLENGTH) }
    }
    BEGIN { while ((getline t < tree) > 0) files[t] = 1 }
    /^- \*\*Ownership is fixed\.\*\*/ { inown = 1; anchor = 1; next }
    inown && /^- / { inown = 0 }
    !inown { next }
    /^    - A sub-path inside a (lane|seat)/ { inover = 1; next }
    inover && /^      - / {
      line = substr($0, 9); c = index(line, ": "); paths = substr(line, 1, c - 1); proj = trim(substr(line, c + 2))
      sub(/ \(.*$/, "", proj); sub(/\.$/, "", proj)
      gsub(/ and /, ",", paths); m = split(paths, ps, ",")
      for (i = 1; i <= m; i++) emit(proj, ps[i], "override")
      next
    }
    /^  - Which Linear project receives/ { inproj = 1; listed = 1; next }
    inproj && /^    - / {
      line = substr($0, 7); c = index(line, ": "); if (c == 0) next
      lane = substr(line, 1, c - 1); proj = trim(substr(line, c + 2))
      sub(/ \(.*$/, "", proj); sub(/\.$/, "", proj)
      project[lane] = proj
      next
    }
    # cut_semi <s> → s up to its first ";" outside parentheses
    function cut_semi(s,   i, ch, d) {
      for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (ch == "(") d++; else if (ch == ")" && d > 0) d--; else if (ch == ";" && d == 0) return substr(s, 1, i - 1)
      }
      return s
    }
    /^  - / {
      inproj = 0; inover = 0
      line = substr($0, 5)
      # Shared ground: the backticked paths of a bullet that says it lists shared ground, up to
      # its first ": " (what follows is a rule about the paths, not more of them).
      if (line ~ /^Shared ground/ || line ~ /is shared ground/) {
        t = line; c = index(t, ": "); if (c) t = substr(t, 1, c - 1)
        # "the Dockerfiles at the `app/` root" names files at a root, not the tree: skipped, so app/
        # is not made shared (those files then map to no seat, and a request on one refuses).
        while (match(t, /`[^`]+`/)) {
          if (substr(t, RSTART + RLENGTH, 5) != " root") emit("shared", substr(t, RSTART, RLENGTH), "shared")
          t = substr(t, RSTART + RLENGTH)
        }
        next
      }
      label = substr(line, 1, 48); gsub(/\t/, " ", label)
      c = index(line, ": "); if (c == 0) { unread(label, line); next }
      raw = substr(line, 1, c - 1)
      lane = raw; sub(/ \(.*$/, "", lane); sub(/,.*$/, "", lane)
      # The seat a lane key names: the key itself when it is a fleet name (window:label), else a
      # backticked fleet name in its parenthetical ("Runner (the `idealic:runner` seat)").
      if (lane ~ /^[a-z0-9][a-z0-9._-]*:[a-z0-9][a-z0-9._-]*$/) seatof[lane] = lane
      else if (match(raw, /\([^)]*`[a-z0-9][a-z0-9._-]*:[a-z0-9][a-z0-9._-]*`[^)]*\)/)) {
        t = substr(raw, RSTART, RLENGTH); match(t, /`[^`]+`/); seatof[lane] = substr(t, RSTART + 1, RLENGTH - 2)
      }
      # A bullet whose key names no seat is a rule, not a lane: its paths are guarded.
      if (!(lane in seatof)) unread(label, line)
      full = substr(line, c + 2); body = cut_semi(full); rest = (length(body) < length(full)) ? substr(full, length(body) + 2) : ""
      # Each later ";" segment that starts with a backticked path (or "and `…`") continues the
      # list ("`ui/`, …; `morph/`; and `tui/`"); any other segment is a rule whose paths are guarded.
      while (rest != "") {
        seg = cut_semi(rest); rest = (length(seg) < length(rest)) ? substr(rest, length(seg) + 2) : ""
        t = trim(seg); sub(/^and /, "", t)
        if (t ~ /^`/) body = body ", " t; else unread(lane, seg)
      }
      # drop parenthetical prose, but keep a path a parenthetical names; a dropped parenthetical
      # that names paths guards them
      while (match(body, /\([^()]*\)/)) {
        ps0 = RSTART; pl0 = RLENGTH; par = substr(body, ps0 + 1, pl0 - 2)
        if (par ~ /^`[^`]*`$/) emit(lane, par, "lane"); else unread(lane, par)
        body = substr(body, 1, ps0 - 1) substr(body, ps0 + pl0)
      }
      gsub(/ and /, ",", body); m = split(body, ps, ",")
      for (i = 1; i <= m; i++) item(lane, ps[i])
    }
    END {
      if (mode == "lane") { lane_end(); exit xrc }
      # Only lanes the lane → project list names are lanes; other bullets in the line are rules.
      for (i = 1; i <= nl; i++) {
        l = lp[i]; p = pp[i]
        if (!(l in project)) continue
        if (p in over) continue                  # a sub-path override beats the lane row
        if (p in printed) continue
        printed[p] = 1; rows++
        # A lane that maps to none still claims its paths, as "-": that blocks a shorter prefix
        # (resource-* → Platform) from routing the file of a none lane (resource-kernel/) elsewhere.
        print rid "\t" p "\t" (project[l] == "none" ? "-" : project[l])
      }
      for (p in over) { print rid "\t" p "\t" over[p]; rows++ }
      for (i = 1; i <= ns; i++) if (slane[i] in project || slane[i] ~ /^Product: /) print "owners-from-doc: skipped " skipped[i] > "/dev/stderr"
      # Never an empty map at exit 0: a missing anchor, a missing lane → project list, or no row
      # at all is a map that could not be built, and the caller must report it as unread.
      if (!anchor) { print "owners-from-doc: no \"- **Ownership is fixed.**\" line in this file" > "/dev/stderr"; exit 2 }
      if (!listed) { print "owners-from-doc: the Ownership line has no lane → project list (\"  - Which Linear project receives …\"); the map is unread" > "/dev/stderr"; exit 2 }
      if (!rows)   { print "owners-from-doc: the Ownership line yielded no row; the map is unread" > "/dev/stderr"; exit 2 }
    }' "$file" | sort -u
  local rc=$?
  rm -f "$tree"
  return $rc
}

sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  detect) cmd_detect "$@" ;;
  plan) cmd_plan "$@" ;;
  apply) cmd_apply "$@" ;;
  since) cmd_since "$@" ;;
  notice) cmd_notice "$@" ;;
  open-keys) cmd_open_keys ;;
  landed) cmd_landed "$@" ;;
  registry-channels) cmd_registry_channels "$@" ;;
  owners-from-doc) cmd_owners_from_doc "$@" ;;
  *) die "usage: doc-signals.sh detect|plan|apply|since|notice|open-keys|landed|registry-channels|owners-from-doc …" ;;
esac
