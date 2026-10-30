#!/bin/bash
# test-next-docs.sh — NEXTDOCS: /next reads documentation signals from the COMMITS since the last
# /next, routes each to the owning project's 🟦 Documentation channel, holds what has nowhere to
# go, caps what it posts, and names what it posted in the `docs:` notice line.
#
# BEHAVIOUR arms (test_b_*) drive skills/next/assets/doc-signals.sh over fixture git histories
# built in a temp dir, and read its exit code directly (never through a pipe). Gate arms:
#   1 a new skill with no doc mention fires          4 dedup suppresses a repeat (every marker shape)
#   2 a doc naming a removed path fires              5 a missing channel goes to the held file
#   3 an unrelated change does not fire              6 `all` lists posted items in the notice
# Fix-round-1 arms: 10 R1 commits only · 11 cap · 12 D1 repo-scoped owners · 13-16 S5 marker ·
# 17 S1/S2 apply · 18 TypeScript bin and route · 19 owners-from-doc.
# Fix-round-3 arms: 27 the marker-lost pause across seats · 28 a key with a space · 29 the apply lock.
#
# PLANTED-DEFECT CONTROLS (test_control_*): each plants one defect into a copy of the script and
# asserts the matching arm reports failures against it. An arm that cannot go red proves nothing.
# DOC_SIGNALS=<path> points every arm at another copy (how builds/nextdocs_TEST_PLANTED.txt was
# produced: TEST_FILTER=test_b_<n>_ DOC_SIGNALS=<planted copy>).
#
# DECLARED BOUNDARY (¶INV_A_NEGATIVE_ONLY_CHECK_SAYS_SO): no Linear call is made. The channel map,
# the owner map and the open-comment keys are fixture files; that an agent builds them from
# Linear and the Ownership line, and posts through /inbox-post (which must keep the marker line
# and must not reclassify the channel — owed to its owner), is not checked here.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$ENGINE_DIR/skills/next/SKILL.md"
REAL_DS="$ENGINE_DIR/skills/next/assets/doc-signals.sh"
DS="${DOC_SIGNALS:-$REAL_DS}"
T=$'\t'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-next-docs.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# fixture <dir> → a repo (origin …/fixture.git, so its repo-id is "fixture") with a README, a guide
# naming skills/old/SKILL.md, an old skill and an executable script handling --old; prints the
# base sha.
fixture() {
  local r="$1"
  mkdir -p "$r/skills/old" "$r/docs" "$r/scripts"
  (
    cd "$r" || exit 1
    git init -q . && git config user.email t@t && git config user.name t
    git remote add origin git@example.com:org/fixture.git
    printf '# Project\n\nUse /old to do old things. The tool takes --documented.\n' >README.md
    printf '# Guide\n\nThe old skill lives at skills/old/SKILL.md and is retired soon.\n' >docs/guide.md
    printf '# old\n' >skills/old/SKILL.md
    printf '#!/bin/bash\ncase "$1" in\n  --old) echo old ;;\n  --documented) echo d ;;\nesac\n' >scripts/tool.sh
    chmod +x scripts/tool.sh
    printf 'notes\n' >notes.txt
    git add -A && git commit -q -m base
  ) >/dev/null 2>&1
  git -C "$r" rev-parse HEAD
}

commit_all() { (cd "$1" && git add -A && git commit -q -m "$2") >/dev/null 2>&1; }
newdir() { local d="$WORK/$1.$RANDOM"; mkdir -p "$d"; echo "$d"; }

# ---------------------------------------------------------------- arms (parameterised by script)

arm_new_skill() {
  local ds="$1" r="$WORK/new-skill.$RANDOM" base out rc
  base=$(fixture "$r")
  mkdir -p "$r/skills/shiny" "$r/skills/documented"
  printf '# shiny\n\nDoes shiny things.\n' >"$r/skills/shiny/SKILL.md"
  printf '# documented\n' >"$r/skills/documented/SKILL.md"
  printf '\nSee /documented for more.\n' >>"$r/README.md"
  commit_all "$r" "add shiny"
  out=$(bash "$ds" detect --repo "$r" --since "$base" 2>/dev/null); rc=$?
  assert_eq "3" "$rc" "1 new skill, no doc mention: detect exits 3 (signals found)"
  assert_contains "signal${T}undocumented-feature${T}fixture:skills/shiny/SKILL.md" "$out" "1 new skill, no doc mention: undocumented-feature on fixture:skills/shiny/SKILL.md (repo-keyed)"
  assert_not_contains "skills/documented" "$out" "1 a new skill a doc names (/documented) does not fire"
}

arm_removed_path() {
  local ds="$1" r="$WORK/removed.$RANDOM" base out rc
  base=$(fixture "$r")
  (cd "$r" && git rm -q skills/old/SKILL.md && git commit -q -m "drop old") >/dev/null 2>&1
  out=$(bash "$ds" detect --repo "$r" --since "$base" 2>/dev/null); rc=$?
  assert_eq "3" "$rc" "2 doc names a removed path: detect exits 3"
  assert_contains "signal${T}stale-reference${T}fixture:docs/guide.md${T}names removed path skills/old/SKILL.md" "$out" "2 doc names a removed path: stale-reference on fixture:docs/guide.md"
  # Path tokens: a longer path that merely ends in the old one is not a mention of it; a doc-relative
  # link and an absolute path ending in it are.
  local r2="$WORK/paths.$RANDOM"
  base=$(fixture "$r2")
  mkdir -p "$r2/hb/hb" "$r2/notes"
  printf 'x\n' >"$r2/hb/std.idea"
  printf '# a\n\nSee [std](./std.idea).\n' >"$r2/hb/README.md"
  printf '# b\n\nGenerated: `hb/hb/std.idea` is the page.\n' >"$r2/notes/gen.md"
  printf '# c\n\nRead ~/src/fixture/hb/std.idea first.\n' >"$r2/notes/abs.md"
  commit_all "$r2" "pages"; base=$(git -C "$r2" rev-parse HEAD)
  (cd "$r2" && git mv hb/std.idea hb/hb/std.idea && git commit -q -m move) >/dev/null 2>&1
  out=$(bash "$ds" detect --repo "$r2" --since "$base" 2>/dev/null)
  assert_contains "stale-reference${T}fixture:hb/README.md${T}names hb/std.idea" "$out" "2 a doc-relative ./std.idea link to the moved path fires"
  assert_contains "stale-reference${T}fixture:notes/abs.md${T}names hb/std.idea" "$out" "2 an absolute path ending in the moved path fires"
  assert_not_contains "fixture:notes/gen.md" "$out" "2 hb/hb/std.idea (the NEW path) is not a mention of hb/std.idea"
}

arm_unrelated() {
  local ds="$1" r="$WORK/unrelated.$RANDOM" base out rc
  base=$(fixture "$r")
  printf 'more notes\n' >>"$r/notes.txt"
  # R2: the --old arm is reflowed and moved, not new.
  printf '#!/bin/bash\n# tool\ncase "$1" in\n  --documented) echo d ;;\n  "--old"|-o)\n    echo old ;;\nesac\n' >"$r/scripts/tool.sh"
  # R4: a test, a conf and a sourced helper are never commands.
  printf '#!/bin/bash\necho t\n' >"$r/scripts/run.test.sh"; chmod +x "$r/scripts/run.test.sh"
  printf 'key=1\n' >"$r/scripts/new.conf"
  printf '#!/bin/bash\nhelper() { :; }\n' >"$r/scripts/helper.sh"      # mode 100644: sourced
  commit_all "$r" "unrelated"
  out=$(bash "$ds" detect --repo "$r" --since "$base" 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "3 unrelated change (reflowed arm, test, conf, sourced helper): detect exits 0"
  assert_empty "$out" "3 unrelated change: detect prints no signal"
}

arm_dedup() {
  local ds="$1" d out rc keys
  d=$(newdir dedup)
  printf 'signal\tstale-reference\tfixture:docs/guide.md\tnames removed path x\nsignal\tstale-reference\tfixture:docs/guide.md\tnames removed path x\n' >"$d/sig"
  printf 'fixture\tdocs/\tProduct: Stats\n' >"$d/owners"
  printf 'Product: Stats\tIDE-251\n' >"$d/chan"
  printf 'Found during /next.\n\ndoc-signal: stale-reference fixture:docs/guide.md\n' | bash "$ds" open-keys >"$d/open"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/owners" --channels "$d/chan" --open "$d/open" 2>&1); rc=$?
  assert_eq "0" "$rc" "4 dedup: plan exits 0"
  assert_contains "dedup${T}stale-reference${T}fixture:docs/guide.md${T}open-comment" "$out" "4 dedup: an open comment with the same file + kind suppresses the signal"
  assert_not_contains "post${T}" "$out" "4 dedup: nothing is posted when an open comment covers it"
  : >"$d/open-empty"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/owners" --channels "$d/chan" --open "$d/open-empty" 2>&1)
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c "^post${T}")" "4 dedup: a repeat within one run posts once"
  assert_contains "dedup${T}stale-reference${T}fixture:docs/guide.md${T}repeat" "$out" "4 dedup: the repeat is named"
  # Every marker shape a comment body can carry it in.
  keys=$(printf '%s\n' \
    'plain: doc-signal: other kit:a.md' \
    'code: `doc-signal: other kit:b.md`' \
    '**doc-signal:** other kit:c.md' \
    'doc-signal: other [kit:d.md](https://example/d)' \
    'doc-signal: other kit:my\_guide.md' | bash "$ds" open-keys)
  local k
  for k in kit:a.md kit:b.md kit:c.md kit:d.md kit:my_guide.md; do
    assert_contains "other${T}${k}" "$keys" "4 open-keys reads the marker for $k"
  done
  # S2 (round 2): trailing punctuation and case.
  keys=$(printf '%s\n' \
    'It ends a sentence: doc-signal: stale-reference kit:docs/e.md.' \
    '**Refs**: IDE-1, doc-signal: stale-reference kit:skills/x/SKILL.md,' \
    'Doc-Signal: Stale-Reference kit:docs/F.md' | bash "$ds" open-keys)
  assert_contains "stale-reference${T}kit:docs/e.md" "$keys" "4 S2 a marker ending a sentence loses its trailing period"
  assert_not_contains "kit:docs/e.md." "$keys" "4 S2 no key keeps a trailing period"
  assert_contains "stale-reference${T}kit:skills/x/SKILL.md" "$keys" "4 S2 a marker in a Refs comma list loses its trailing comma"
  assert_not_contains "SKILL.md," "$keys" "4 S2 no key keeps a trailing comma"
  assert_contains "stale-reference${T}kit:docs/F.md" "$keys" "4 S2 the marker and its kind are read case-insensitively"
  printf 'signal\tstale-reference\tkit:docs/f.md\tx\n' >"$d/sig3"; printf 'kit\t\tP\n' >"$d/own3"; printf 'P\tC-1\n' >"$d/chan3"
  printf '%s\n' "$keys" >"$d/open3"
  out=$(bash "$ds" plan --signals "$d/sig3" --owners "$d/own3" --channels "$d/chan3" --open "$d/open3" 2>&1)
  assert_contains "dedup${T}stale-reference${T}kit:docs/f.md${T}open-comment" "$out" "4 S2 an open key differing only in case still dedups"
  # Keys carry the repo: the same path in another repository is not deduped.
  printf 'signal\tstale-reference\tkit:README.md\tx\nsignal\tstale-reference\tengine:README.md\tx\n' >"$d/sig2"
  printf 'kit\t\tP\nengine\t\tP\n' >"$d/own2"; printf 'P\tC-1\n' >"$d/chan2"
  printf 'stale-reference\tkit:README.md\n' >"$d/open2"
  out=$(bash "$ds" plan --signals "$d/sig2" --owners "$d/own2" --channels "$d/chan2" --open "$d/open2" 2>&1)
  assert_contains "post${T}stale-reference${T}engine:README.md" "$out" "4 the same path in another repo is its own key"
}

arm_missing_channel() {
  local ds="$1" d out rc
  d=$(newdir held)
  printf 'signal\tundocumented-feature\tkit:skills/shiny/SKILL.md\tnew skill /shiny\nsignal\tstale-reference\tkit:loose/a.md\tnames b.md\n' >"$d/sig"
  printf 'kit\tskills/\tKit\n' >"$d/owners"
  printf 'Product: Stats\tIDE-251\n' >"$d/chan"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/owners" --channels "$d/chan" 2>&1); rc=$?
  assert_eq "0" "$rc" "5 missing channel: plan exits 0"
  assert_contains "hold${T}undocumented-feature${T}kit:skills/shiny/SKILL.md${T}Kit${T}no-docs-channel" "$out" "5 missing channel: a project with no 🟦 channel holds"
  assert_contains "hold${T}stale-reference${T}kit:loose/a.md${T}-${T}owner-unresolved" "$out" "5 missing channel: an unresolved owner holds, never guessed"
  printf '%s\n' "$out" >"$d/plan"
  bash "$ds" apply --plan "$d/plan" --held "$d/HELD.tsv" --since-repo "$d" --since-sha abc123; rc=$?
  assert_eq "0" "$rc" "5 missing channel: apply exits 0"
  assert_contains "held${T}undocumented-feature${T}kit:skills/shiny/SKILL.md${T}Kit${T}no-docs-channel" "$(cat "$d/HELD.tsv" 2>/dev/null)" "5 missing channel: the signal is in the held file"
  assert_eq "abc123" "$(bash "$ds" since --held "$d/HELD.tsv" --repo "$d")" "5 missing channel: the since-marker is recorded"
  # The channel appears: the held row is re-read and posts; nothing new was detected.
  printf 'Kit\tIDE-999\n' >>"$d/chan"; : >"$d/none"
  out=$(bash "$ds" plan --signals "$d/none" --owners "$d/owners" --channels "$d/chan" --held "$d/HELD.tsv" 2>&1)
  assert_contains "post${T}undocumented-feature${T}kit:skills/shiny/SKILL.md${T}Kit${T}IDE-999" "$out" "5 missing channel: once the channel exists the held signal posts"
  printf '%s\n' "$out" >"$d/plan2"
  printf 'undocumented-feature\tkit:skills/shiny/SKILL.md\tKit\tIDE-999\thttps://example/c1\n' >"$d/posted"
  bash "$ds" apply --plan "$d/plan2" --held "$d/HELD.tsv" --posted "$d/posted"
  assert_not_contains "kit:skills/shiny/SKILL.md" "$(cat "$d/HELD.tsv")" "5 missing channel: a posted signal leaves the held file"
  assert_eq "abc123" "$(bash "$ds" since --held "$d/HELD.tsv" --repo "$d")" "5 missing channel: an apply without a marker keeps the old one"
}

arm_all_notice() {
  local ds="$1" d out rc
  d=$(newdir notice)
  printf '%s\n' \
    "post${T}stale-reference${T}kit:docs/guide.md${T}Product: Stats${T}IDE-251${T}names removed path x${T}new" \
    "hold${T}redundancy${T}kit:a.md${T}Kit${T}no-docs-channel${T}repeats b${T}new" \
    "hold${T}stale-reference${T}kit:loose.md${T}-${T}owner-unresolved${T}names x${T}new" \
    "hold${T}stale-reference${T}kit:late.md${T}Product: Stats${T}over-cap${T}names y${T}new" \
    "hold${T}other${T}kit:old.md${T}Kit${T}no-docs-channel${T}z${T}held" \
    "dedup${T}other${T}kit:z.md${T}open-comment${T}z${T}new" >"$d/plan"
  printf 'stale-reference\tkit:docs/guide.md\tProduct: Stats\tIDE-251\thttps://linear.app/x/IDE-251#comment-1\n' >"$d/posted"
  out=$(bash "$ds" notice --mode all --plan "$d/plan" --posted "$d/posted" 2>&1); rc=$?
  assert_eq "0" "$rc" "6 all notice: notice exits 0"
  assert_contains "docs: posted — 1 (stale-reference kit:docs/guide.md → Product: Stats IDE-251 (https://linear.app/x/IDE-251#comment-1))" "$out" "6 all notice: the posted item is listed with its link"
  assert_contains "held — 1 (redundancy kit:a.md: no-docs-channel (Kit))" "$out" "6 all notice: this run's held item is listed with its reason"
  assert_contains "owner-unresolved — 1 (kit:loose.md)" "$out" "6 all notice: unresolved owners are named in the notice"
  assert_contains "over-cap — 1 (stale-reference kit:late.md)" "$out" "6 all notice: over-cap items are named"
  assert_contains "carried — 1 (1 no-docs-channel)" "$out" "6 all notice: carried holds are counted, not reprinted (N6)"
  assert_contains "deduped — 1" "$out" "6 all notice: the dedup count is said"
  out=$(bash "$ds" notice --mode plain --plan "$d/plan" 2>&1)
  assert_contains "docs: will post — 1 (stale-reference kit:docs/guide.md → Product: Stats IDE-251)" "$out" "6 plain notice: the consent body names what will post"
  out=$(bash "$ds" notice --mode stopped --plan "$d/plan" 2>&1)
  assert_contains "docs: not posted — the run stopped before the docs step" "$out" "6 stopped notice: a stopped run says nothing posted"
}

arm_redundancy() {
  local ds="$1" r="$WORK/redund.$RANDOM" base out rc d
  base=$(fixture "$r")
  local para='The release train leaves every Thursday at noon and anything not merged by then waits a full week.'
  printf '# Release\n\n%s\n' "$para" >"$r/docs/release.md"
  printf '\n%s\n' "$para" >>"$r/README.md"
  commit_all "$r" "two docs gain one passage"
  out=$(bash "$ds" detect --repo "$r" --since "$base" 2>/dev/null); rc=$?
  assert_eq "3" "$rc" "9 redundancy: detect exits 3"
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c "${T}redundancy${T}")" "9 redundancy: one signal per unordered pair (README.md ↔ docs/release.md)"
  assert_not_contains "redundancy${T}fixture:${T}" "$out" "9 no redundancy row has an empty path (the mawk lvalue-order trap)"
  d=$(newdir redund-plan)
  printf '%s\n' "$out" | grep "${T}redundancy${T}" >"$d/sig"
  printf 'fixture\t\tP\n' >"$d/own"; printf 'P\tC-1\n' >"$d/chan"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/own" --channels "$d/chan" 2>&1)
  assert_contains "hold${T}redundancy${T}" "$out" "9 redundancy is detected, not posted"
  assert_contains "${T}detected-not-posted${T}" "$out" "9 its hold reason is detected-not-posted"
  assert_not_contains "post${T}redundancy" "$out" "9 no redundancy row posts by default"
}

arm_flags() {
  local ds="$1" r="$WORK/flags.$RANDOM" base out rc
  base=$(fixture "$r")
  printf '#!/bin/bash\ncase "$1" in\n  --old) echo old ;;\n  --documented) echo d ;;\n  -h|--help) echo h ;;\nesac\nif [ "$1" = --rename ]; then echo r; fi\nif [ "$1" = --live ]; then echo l; fi\n' >"$r/scripts/tool.sh"
  printf '\nThe --live-foo mode is unrelated. See also --help.\n' >>"$r/docs/guide.md"
  commit_all "$r" "flags"
  out=$(bash "$ds" detect --repo "$r" --since "$base" 2>/dev/null); rc=$?
  assert_eq "3" "$rc" "20 flags: detect exits 3"
  assert_contains "fixture:scripts/tool.sh${T}new flag --rename" "$out" "20 a flag tested by [ \"\$1\" = --rename ] fires"
  assert_contains "fixture:scripts/tool.sh${T}new flag --live " "$out" "20 --live fires: a doc naming --live-foo is not a mention of --live (N3)"
  assert_not_contains "new flag --help" "$out" "20 --help (in -h|--help) is mentioned in a doc, so it does not fire"
  assert_not_contains "new flag --old" "$out" "20 --old was in the pre-image, so it is not new"
}

arm_commits_only() {
  local ds="$1" r="$WORK/commits.$RANDOM" base out rc
  base=$(fixture "$r")
  printf 'x\n' >>"$r/notes.txt"; commit_all "$r" "a commit so the range is not empty"
  # Uncommitted and untracked work is another seat's half-written state, not this run's diff.
  rm -f "$r/skills/old/SKILL.md"
  mkdir -p "$r/skills/wip"; printf '# wip\n' >"$r/skills/wip/SKILL.md"
  printf '#!/bin/bash\n' >"$r/scripts/wip.sh"; chmod +x "$r/scripts/wip.sh"
  out=$(bash "$ds" detect --repo "$r" --since "$base" 2>/dev/null); rc=$?
  assert_eq "0" "$rc" "10 R1: uncommitted deletes and untracked files do not fire (exit 0)"
  assert_empty "$out" "10 R1: detect prints no signal for work that is not committed"
}

arm_cap() {
  local ds="$1" d out i
  d=$(newdir cap)
  : >"$d/sig"; for i in 1 2 3 4 5; do printf 'signal\tstale-reference\tkit:d%s.md\tx\n' "$i" >>"$d/sig"; done
  printf 'kit\t\tP\n' >"$d/own"; printf 'P\tC-1\n' >"$d/chan"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/own" --channels "$d/chan" 2>&1)
  assert_eq "3" "$(printf '%s\n' "$out" | grep -c "^post${T}")" "11 cap: at most 3 post by default"
  assert_eq "2" "$(printf '%s\n' "$out" | grep -c "${T}over-cap${T}")" "11 cap: the rest are held as over-cap, not dropped"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/own" --channels "$d/chan" --max 1 2>&1)
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c "^post${T}")" "11 cap: --max 1 posts one"
}

arm_owners_repo() {
  local ds="$1" d out
  d=$(newdir owners)
  printf 'signal\tother\tb:docs/x.md\tx\nsignal\tother\ta:docs/sub/y.md\ty\nsignal\tother\ta:resource-kernel/z.md\tz\n' >"$d/sig"
  printf 'a\tdocs/\tP1\nb\tdocs/\tP2\na\tdocs/sub/\tP3\na\tresource-\tP4\na\tresource-kernel/\t-\n' >"$d/own"
  printf 'P1\tC-1\nP2\tC-2\nP3\tC-3\nP4\tC-4\n' >"$d/chan"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/own" --channels "$d/chan" --max 9 2>&1)
  assert_contains "post${T}other${T}b:docs/x.md${T}P2" "$out" "12 D1: an owner row applies only within its own repo"
  assert_contains "post${T}other${T}a:docs/sub/y.md${T}P3" "$out" "12 D1: the longest prefix within the repo wins"
  assert_contains "hold${T}other${T}a:resource-kernel/z.md${T}-${T}owner-unresolved" "$out" "12 D1: a '-' row (a lane mapping to none) blocks the shorter prefix"
}

arm_marker_realpath() {
  local ds="$1" d
  d=$(newdir realpath)
  mkdir -p "$d/real"; ln -s "$d/real" "$d/link"
  : >"$d/plan"
  bash "$ds" apply --plan "$d/plan" --held "$d/H.tsv" --since-repo "$d/link" --since-sha s1
  assert_eq "0" "$?" "13/14 S5: apply with an empty plan (0 signals) exits 0"
  assert_eq "s1" "$(bash "$ds" since --held "$d/H.tsv" --repo "$d/real")" "13 S5: a marker recorded via a symlink is found via the real path"
  assert_eq "s1" "$(bash "$ds" since --held "$d/H.tsv" --repo "$d/link")" "13 S5: and via the symlink"
}

arm_marker_zero() {
  local ds="$1" d
  d=$(newdir zero)
  : >"$d/plan"
  bash "$ds" apply --plan "$d/plan" --held "$d/H.tsv" --since-repo "$d" --since-sha zz9 >/dev/null 2>&1
  assert_eq "zz9" "$(bash "$ds" since --held "$d/H.tsv" --repo "$d" 2>/dev/null)" "14 S5: an accepted run with 0 signals still advances the marker"
}

arm_marker_seed() {
  local ds="$1" d out err
  d=$(newdir seed)
  mkdir -p "$d/sessions/old" "$d/sessions/newer" "$d/sessions/current" "$d/repo"
  printf '# since\t%s\tOLDSHA\t2026-10-01T00:00:00Z\n' "$(cd "$d/repo" && pwd -P)" >"$d/sessions/old/NEXT_DOC_SIGNALS.tsv"
  printf '# since\t%s\tNEWSHA\t2026-10-28T00:00:00Z\n' "$(cd "$d/repo" && pwd -P)" >"$d/sessions/newer/NEXT_DOC_SIGNALS.tsv"
  out=$(bash "$ds" since --held "$d/sessions/current/NEXT_DOC_SIGNALS.tsv" --repo "$d/repo" --sessions-root "$d/sessions" 2>"$d/err")
  assert_eq "NEWSHA" "$out" "15 S5: a new session seeds from the newest marker in any session"
  assert_contains "seeded from $d/sessions/newer/NEXT_DOC_SIGNALS.tsv" "$(cat "$d/err")" "15 S5: it says where it found the marker"
}

arm_marker_unreachable() {
  local ds="$1" r="$WORK/unreach.$RANDOM" base out rc side
  base=$(fixture "$r")
  (cd "$r" && git checkout -q -b side && printf 's\n' >side.txt && git add -A && git commit -q -m side && git checkout -q -) >/dev/null 2>&1
  side=$(git -C "$r" rev-parse side)
  printf 'x\n' >>"$r/notes.txt"; commit_all "$r" "main moves"
  bash "$ds" detect --repo "$r" --since deadbeefdeadbeefdeadbeefdeadbeefdeadbeef >/dev/null 2>"$WORK/unreach.err"; rc=$?
  assert_neq "2" "$rc" "16 S5: an unknown since-sha does not fail detect"
  assert_contains "falling back to the last 24 hours" "$(cat "$WORK/unreach.err")" "16 S5: it warns and falls back"
  bash "$ds" detect --repo "$r" --since "$side" >/dev/null 2>"$WORK/unreach.err"; rc=$?
  assert_neq "2" "$rc" "16 S5: a since-sha that is not an ancestor of HEAD does not fail detect"
  assert_contains "not an ancestor of HEAD" "$(cat "$WORK/unreach.err")" "16 S5: it names why it fell back"
}

arm_apply_guards() {
  local ds="$1" d rc
  d=$(newdir apply)
  printf 'held\tother\tkit:old.md\tKit\tno-docs-channel\tz\t2026-10-01T00:00:00Z\n' >"$d/H.tsv"
  bash "$ds" apply --plan "$d/missing" --held "$d/H.tsv" --since-repo "$d" --since-sha s >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "17 S1: apply with a missing plan exits non-zero (2)"
  assert_contains "kit:old.md" "$(cat "$d/H.tsv")" "17 S1: and leaves the held file as it was"
  printf 'hold\tother\tkit:new.md\t-\towner-unresolved\tn\tnew\n' >"$d/plan"     # built without --held
  bash "$ds" apply --plan "$d/plan" --held "$d/H.tsv" >/dev/null 2>&1
  assert_contains "held${T}other${T}kit:old.md" "$(cat "$d/H.tsv")" "17 S2: an earlier held row the plan does not mention is kept (merge)"
  assert_contains "held${T}other${T}kit:new.md" "$(cat "$d/H.tsv")" "17 S2: the plan's hold row is added"
  assert_contains "2026-10-01T00:00:00Z" "$(cat "$d/H.tsv")" "17 S2: the kept row keeps its first-seen time"
}

arm_typescript() {
  local ds="$1" r="$WORK/ts.$RANDOM" base out rc
  base=$(fixture "$r")
  mkdir -p "$r/pkg/src"
  printf '{"name":"@x/pkg","bin":{"oldtool":"./bin/old.js"}}\n' >"$r/pkg/package.json"
  printf 'app.get("/api/old", h)\n' >"$r/pkg/src/server.ts"
  commit_all "$r" "ts base"; base=$(git -C "$r" rev-parse HEAD)
  printf '{"name":"@x/pkg","bin":{"oldtool":"./bin/old.js","newtool":"./bin/new.js"}}\n' >"$r/pkg/package.json"
  printf 'app.get("/api/old", h)\napp.post("/api/fresh", h)\n' >"$r/pkg/src/server.ts"
  printf 'app.get("/api/testonly", h)\n' >"$r/pkg/src/server.test.ts"
  commit_all "$r" "ts feature"
  out=$(bash "$ds" detect --repo "$r" --since "$base" 2>/dev/null); rc=$?
  assert_eq "3" "$rc" "18 TS: detect exits 3"
  assert_contains "fixture:pkg/package.json${T}new bin newtool" "$out" "18 TS: a new package.json bin fires"
  assert_not_contains "new bin oldtool" "$out" "18 TS: a bin already in the pre-image does not"
  assert_contains "fixture:pkg/src/server.ts${T}new route /api/fresh" "$out" "18 TS: a new route fires"
  assert_not_contains "/api/old" "$out" "18 TS: an existing route does not"
  assert_not_contains "/api/testonly" "$out" "18 TS: a route in a test file does not"
}

arm_owners_from_doc() {
  local ds="$1" r="$WORK/own.$RANDOM" out
  fixture "$r" >/dev/null
  mkdir -p "$r/resource-db" "$r/resource-kernel/docs" "$r/ideas-stats" "$r/ui"
  for f in resource-db/a resource-kernel/a resource-kernel/docs/WORLD_BASE.md ideas-stats/a ui/a; do printf 'x\n' >"$r/$f"; done
  commit_all "$r" "tree"
  cat >"$r/OWN.md" <<'EOF'
- **Ownership is fixed.**
  - Platform: resource-* except resource-kernel, `ideas-stats/` and `gone/`.
  - Kernel: resource-kernel; before a change lands, Kernel asks.
  - UI (the `idealic:ui` seat): `ui/`, meaning its library source.
  - Shared ground (`.github/`) is not assigned by this line; the lanes agree.
  - Which Linear project receives a lane's documentation signals, read by `/next`.
    - Platform: Product: Resources & Platform (inferred).
    - Kernel: none.
    - UI: Product: UI & Design (inferred).
    - A sub-path inside a lane's area that belongs to a different project, the longest prefix winning:
      - `ideas-stats/`: Product: Stats (inferred).
      - `resource-kernel/docs/WORLD_BASE.md`: Product: Worlds & Branches (inferred).
- **Next principle.**
EOF
  out=$(bash "$ds" owners-from-doc --repo "$r" --repo-id kit "$r/OWN.md" 2>"$WORK/own.err")
  assert_contains "kit${T}resource-*${T}Product: Resources & Platform" "$out" "19 owners-from-doc: a lane's glob path maps to its project"
  assert_contains "kit${T}resource-kernel/${T}-" "$out" "19 owners-from-doc: a lane mapping to none claims its path as '-'"
  assert_contains "kit${T}ideas-stats/${T}Product: Stats" "$out" "19 owners-from-doc: a sub-path override wins over the lane"
  assert_not_contains "ideas-stats/${T}Product: Resources" "$out" "19 owners-from-doc: the overridden lane row is not emitted"
  assert_contains "kit${T}resource-kernel/docs/WORLD_BASE.md${T}Product: Worlds & Branches" "$out" "19 owners-from-doc: a file-level override"
  assert_contains "kit${T}ui/${T}Product: UI & Design" "$out" "19 owners-from-doc: a lane named with a parenthetical"
  assert_not_contains ".github" "$out" "19 owners-from-doc: shared ground is not assigned"
  assert_contains "gone/ (not at HEAD)" "$(cat "$WORK/own.err")" "19 owners-from-doc: a path absent at HEAD is skipped and named"
}

# 30: the round-5/6 changes to project mode (IDE-350): the override header's "inside a seat's area"
# form, a ";" segment that starts with a backtick continuing the list, the paren-aware ";" cut, an
# empty-key list entry, --rev, the seat-keyed skip report under --verbose only, and a sentence
# after ". " inside a lane bullet read as a rule, not more of the list.
arm_owners_project_r6() {
  local ds="$1" r="$WORK/own6.$RANDOM" out err
  fixture "$r" >/dev/null
  mkdir -p "$r/world-runner/src/merge" "$r/ui/examples" "$r/morph" "$r/tui" "$r/gone6" "$r/kern" "$r/sec"
  for f in world-runner/a world-runner/src/merge/m ui/a ui/examples/e morph/a tui/a gone6/a kern/a sec/a; do printf 'x\n' >"$r/$f"; done
  commit_all "$r" "tree"
  local old; old=$(git -C "$r" rev-parse HEAD)
  (cd "$r" && git rm -rq gone6 && git commit -qm gone) >/dev/null 2>&1
  cat >"$r/OWN6.md" <<'EOF'
- **Ownership is fixed.**
  - domain:language: world-runner and `missing6/`.
  - core:ui: `ui/` (its library; and its themes); `ui/examples/`; and `morph/`; its reviews of `tui/` go to core:ui.
  - core:kernel: `kern/`. domain:security owns `sec/`.
  - core:old: `gone6/`.
  - Which Linear project receives a seat's documentation signals, read by `/next`.
    - domain:language: Product: Idea.
    - core:ui: Product: UI & Design.
    - core:kernel: Product: Resources & Platform.
    - core:old: Product: Old.
    - an entry with no key
    - A sub-path inside a seat's area that belongs to a different project, the longest prefix winning:
      - `world-runner/src/merge/`: Product: Worlds & Branches (inferred).
- **Next principle.**
EOF
  out=$(bash "$ds" owners-from-doc --repo "$r" --repo-id kit "$r/OWN6.md" 2>"$WORK/own6.err"); rc=$?
  err=$(cat "$WORK/own6.err")
  assert_eq "0" "$rc" "30 owners-from-doc: a seat-keyed line parses"
  assert_contains "kit${T}world-runner/src/merge/${T}Product: Worlds & Branches" "$out" "30 override header: 'A sub-path inside a seat's area' is read as the override list"
  assert_contains "kit${T}ui/examples/${T}Product: UI & Design" "$out" "30 ';' continuation: a segment that starts with a backtick continues the lane's list"
  assert_contains "kit${T}morph/${T}Product: UI & Design" "$out" "30 ';' continuation: 'and \`morph/\`' too"
  assert_not_contains "kit${T}tui/" "$out" "30 ';' continuation: a segment that starts with a word is a rule, not the list"
  assert_contains "kit${T}ui/${T}Product: UI & Design" "$out" "30 paren-aware cut: a ';' inside parentheses does not end the list"
  assert_not_contains "sec/" "$out" "30 N1: a sentence after '. ' (a seat name next) is a rule, not more of core:kernel's list"
  assert_contains "kit${T}kern/${T}Product: Resources & Platform" "$out" "30 N1: the list before it stands"
  assert_not_contains "no key" "$out$err" "30 an empty-key list entry is skipped"
  assert_not_contains "skipped" "$err" "30 skip report: a seat-keyed lane's skips are quiet by default"
  err=$(bash "$ds" owners-from-doc --repo "$r" --repo-id kit --verbose "$r/OWN6.md" 2>&1 >/dev/null)
  assert_contains "skipped domain:language: missing6/ (not at HEAD)" "$err" "30 skip report: named with --verbose"
  out=$(bash "$ds" owners-from-doc --repo "$r" --repo-id kit "$r/OWN6.md" 2>/dev/null)
  assert_not_contains "gone6/" "$out" "30 --rev: at HEAD a removed path is not emitted"
  out=$(bash "$ds" owners-from-doc --repo "$r" --repo-id kit --rev "$old" "$r/OWN6.md" 2>/dev/null)
  assert_contains "kit${T}gone6/${T}Product: Old" "$out" "30 --rev: at an older rev its tree is read"
  out=$(bash "$ds" owners-from-doc --repo "$r" --repo-id kit --emit lane "$r/OWN6.md" 2>/dev/null)
  assert_contains "kern/${T}core:kernel" "$out" "30 --emit lane: '<path> <seat>' rows"
  assert_contains "sec/${T}unread${T}-${T}domain:security owns" "$out" "30 --emit lane: the sentence's path is a guard naming the lane seats it names (none here: domain:security is no lane) and the sentence"
}

arm_fold() {
  local ds="$1" d out
  d=$(newdir fold)
  printf 'signal\tundocumented-feature\tkit:scripts/m.sh\tnew flag --live\nsignal\tundocumented-feature\tkit:scripts/m.sh\tnew flag --roots\nsignal\tundocumented-feature\tkit:scripts/m.sh\tnew flag --rename\n' >"$d/sig"
  printf 'kit\t\tP\n' >"$d/own"; printf 'P\tC-1\n' >"$d/chan"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/own" --channels "$d/chan" 2>&1)
  assert_eq "1" "$(printf '%s\n' "$out" | grep -c "^post${T}")" "22 S3 three findings on one file and kind make one post"
  assert_contains "new flag --live; new flag --roots; new flag --rename" "$out" "22 S3 the one post names every finding"
  assert_not_contains "dedup${T}" "$out" "22 S3 no finding is hidden as deduped"
}

arm_readback() {
  local ds="$1" d out rc
  d=$(newdir readback)
  printf 'Posted.\n\n`doc-signal: stale-reference kit:docs/a.md`\n' | bash "$ds" open-keys >"$d/open-after"
  bash "$ds" landed --open "$d/open-after" stale-reference kit:docs/a.md >"$d/out1"; rc=$?
  assert_eq "0" "$rc" "23 M1 landed: a key read back from the channel exits 0"
  assert_eq "landed" "$(cat "$d/out1")" "23 M1 landed prints landed"
  bash "$ds" landed --open "$d/open-after" stale-reference kit:docs/b.md >"$d/out2"; rc=$?
  assert_eq "1" "$rc" "23 M1 a key that does not read back exits 1"
  assert_eq "marker-lost" "$(cat "$d/out2")" "23 M1 and prints marker-lost"
  # The run stops posting after the miss: b is lost, c never posted.
  printf '%s\n' \
    "post${T}stale-reference${T}kit:docs/a.md${T}P${T}C-1${T}x${T}new" \
    "post${T}stale-reference${T}kit:docs/b.md${T}P${T}C-1${T}y${T}new" \
    "post${T}stale-reference${T}kit:docs/c.md${T}P${T}C-1${T}z${T}new" >"$d/plan"
  printf 'stale-reference\tkit:docs/a.md\tP\tC-1\thttps://x/1\n' >"$d/posted"
  printf 'stale-reference\tkit:docs/b.md\tP\tC-1\thttps://x/2\n' >"$d/lost"
  out=$(bash "$ds" notice --mode all --plan "$d/plan" --posted "$d/posted" --lost "$d/lost" 2>&1)
  assert_contains "docs: marker-lost — 1 (stale-reference kit:docs/b.md → P C-1 (https://x/2)), posting paused until its marker reads back;" "$out" "23 M1 the docs: line names marker-lost first"
  assert_contains "held — 1 (stale-reference kit:docs/c.md: post-not-landed)" "$out" "23 M1 the rest are post-not-landed"
  bash "$ds" apply --plan "$d/plan" --held "$d/H.tsv" --posted "$d/posted" --lost "$d/lost" >/dev/null 2>&1
  assert_contains "held${T}stale-reference${T}kit:docs/b.md${T}P${T}marker-lost" "$(cat "$d/H.tsv")" "23 M1 the lost row is held as marker-lost"
  assert_contains "held${T}stale-reference${T}kit:docs/c.md${T}P${T}post-not-landed" "$(cat "$d/H.tsv")" "23 M1 the unposted row is held as post-not-landed"
  : >"$d/none"
  out=$(bash "$ds" plan --signals "$d/none" --owners <(printf 'kit\t\tP\n') --channels <(printf 'P\tC-1\n') --held "$d/H.tsv" 2>&1)
  assert_contains "hold${T}stale-reference${T}kit:docs/b.md${T}P${T}marker-lost" "$out" "23 M1 a marker-lost row is never re-posted by a later run"
  assert_not_contains "post${T}" "$out" "23 MUST-1a while a marker-lost row is held, nothing posts on a later run"
  assert_contains "hold${T}stale-reference${T}kit:docs/c.md${T}P${T}posting-paused" "$out" "23 MUST-1a the post-not-landed row is held as posting-paused"
  # SHOULD-1: the next run's line carries the lost row; it does not claim this run stopped.
  printf '%s\n' "$out" >"$d/plan-next"
  out=$(bash "$ds" notice --mode all --plan "$d/plan-next" --posted "$d/none" --lost "$d/none" 2>&1)
  assert_not_contains "marker-lost — " "$out" "23 S1 a carried marker-lost row does not lead the line as this run's loss"
  assert_not_contains "posting stopped for this run" "$out" "23 S1 nor claim posting stopped for this run"
  assert_contains "carried — 1 (1 marker-lost)" "$out" "23 S1 it is counted under carried"
  assert_contains "docs: posting paused — 1 (stale-reference kit:docs/c.md) while a marker-lost comment is held;" "$out" "23 S1 the pause and what it held back lead the line"
  # SHOULD-5: the way out. The lost comment reads back later: the row leaves as deduped and the pause lifts.
  printf 'stale-reference\tkit:docs/b.md\n' >"$d/open-b"
  out=$(bash "$ds" plan --signals "$d/none" --owners <(printf 'kit\t\tP\n') --channels <(printf 'P\tC-1\n') --held "$d/H.tsv" --open "$d/open-b" 2>&1)
  assert_contains "dedup${T}stale-reference${T}kit:docs/b.md${T}open-comment" "$out" "23 S5 a marker-lost row whose comment reads back leaves as dedup open-comment"
  assert_contains "post${T}stale-reference${T}kit:docs/c.md" "$out" "23 S5 and the pause lifts: the held row posts"
  # NIT-1: landed compares without regard to case.
  bash "$ds" landed --open "$d/open-after" Stale-Reference KIT:docs/A.md >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "23 N1 landed matches kind and key case-insensitively"
  printf 'Stale-Reference\tKIT:docs/A.md\n' >"$d/open-case"
  bash "$ds" landed --open "$d/open-case" stale-reference kit:docs/a.md >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "23 N1 and a read-back key in another case lands too"
}

# MUST-1(b): the pause and the dedup span every session's held file under the sessions root.
arm_pause() {
  local ds="$1" d out
  d=$(newdir pause)
  mkdir -p "$d/root/A" "$d/root/B"
  printf 'held\tstale-reference\tkit:docs/a.md\tP\tmarker-lost\tx\t2026-10-29T00:00:00Z\n' >"$d/root/A/NEXT_DOC_SIGNALS.tsv"
  printf 'signal\tstale-reference\tkit:docs/a.md\tx\nsignal\tstale-reference\tkit:docs/q.md\tq\n' >"$d/sig"
  printf 'kit\t\tP\n' >"$d/own"; printf 'P\tC-1\n' >"$d/chan"; : >"$d/open"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/own" --channels "$d/chan" --open "$d/open" \
          --held "$d/root/B/NEXT_DOC_SIGNALS.tsv" --sessions-root "$d/root" 2>&1)
  assert_not_contains "post${T}" "$out" "27 MUST-1b seat B posts nothing while seat A holds a marker-lost row"
  assert_contains "dedup${T}stale-reference${T}kit:docs/a.md${T}marker-lost" "$out" "27 MUST-1b seat B dedups the key seat A lost"
  assert_contains "hold${T}stale-reference${T}kit:docs/q.md${T}P${T}posting-paused" "$out" "27 MUST-1b and holds its new item as posting-paused"
  printf '%s\n' "$out" >"$d/plan"
  bash "$ds" apply --plan "$d/plan" --held "$d/root/B/NEXT_DOC_SIGNALS.tsv" >/dev/null 2>&1
  assert_contains "held${T}stale-reference${T}kit:docs/q.md${T}P${T}posting-paused" "$(cat "$d/root/B/NEXT_DOC_SIGNALS.tsv")" "27 MUST-1b the paused item is held, not dropped"
  assert_not_contains "kit:docs/a.md" "$(cat "$d/root/B/NEXT_DOC_SIGNALS.tsv")" "27 MUST-1b the lost key is not held twice"
  # Seat A's own next run, with no sessions root: its own held file pauses it.
  out=$(bash "$ds" plan --signals <(printf 'signal\tstale-reference\tkit:docs/y.md\ty\n') --owners "$d/own" --channels "$d/chan" \
          --held "$d/root/A/NEXT_DOC_SIGNALS.tsv" 2>&1)
  assert_contains "hold${T}stale-reference${T}kit:docs/y.md${T}P${T}posting-paused" "$out" "27 MUST-1a seat A's next new item is paused, not posted"
  # A's comment reads back: B's paused item posts and the key dedups as an open comment.
  printf 'stale-reference\tkit:docs/a.md\n' >"$d/open"
  out=$(bash "$ds" plan --signals "$d/sig" --owners "$d/own" --channels "$d/chan" --open "$d/open" \
          --held "$d/root/B/NEXT_DOC_SIGNALS.tsv" --sessions-root "$d/root" 2>&1)
  assert_contains "post${T}stale-reference${T}kit:docs/q.md" "$out" "27 MUST-1b the pause lifts once the lost marker reads back"
  assert_contains "dedup${T}stale-reference${T}kit:docs/a.md${T}open-comment" "$out" "27 MUST-1b and the key dedups as an open comment"
}

# SHOULD-4: a path with a space keeps its whole key; separators and code spans still end it.
arm_space_key() {
  local ds="$1" d keys rc
  d=$(newdir spacekey)
  keys=$(printf '%s\n' \
    'doc-signal: stale-reference sprepo:docs/my guide.md' \
    'Posted: `doc-signal: other kit:b.md` thanks' \
    '**Refs**: IDE-1, doc-signal: stale-reference kit:x.md, IDE-12' \
    'doc-signal: other <kit:docs/auto.md>' | bash "$ds" open-keys)
  printf '%s\n' "$keys" >"$d/open"
  assert_contains "stale-reference${T}sprepo:docs/my guide.md" "$keys" "28 S4 a key with a space is read whole"
  bash "$ds" landed --open "$d/open" stale-reference "sprepo:docs/my guide.md" >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "28 S4 and it lands"
  assert_contains "other${T}kit:b.md" "$keys" "28 S4 a code span still ends the key"
  assert_not_contains "thanks" "$keys" "28 S4 prose after the code span is not part of the key"
  assert_contains "stale-reference${T}kit:x.md" "$keys" "28 S4 a comma list still ends the key"
  assert_not_contains "IDE-12" "$keys" "28 S4 the next list item is not part of the key"
  assert_contains "other${T}kit:docs/auto.md" "$keys" "28 S4 an <autolink> loses its brackets"
}

# SHOULD-6: a killed apply releases its lock; a lock left by a hard kill is broken once stale.
arm_apply_lock() {
  local ds="$1" d rc
  d=$(newdir applylock)
  mkdir -p "$d/fake"; : >"$d/plan"
  printf '#!/bin/sh\nkill -TERM $PPID\nsleep 1\nexit 1\n' >"$d/fake/awk"; chmod +x "$d/fake/awk"
  PATH="$d/fake:$PATH" bash "$ds" apply --plan "$d/plan" --held "$d/H.tsv" >/dev/null 2>&1
  if [ -d "$d/H.tsv.lock" ]; then fail "29 S6 a TERM during apply releases the lock" "no $d/H.tsv.lock" "lock left behind"; rmdir "$d/H.tsv.lock"
  else pass "29 S6 a TERM during apply releases the lock"; fi
  assert_eq "" "$(ls "$d" | grep '^H.tsv\.' || true)" "29 S6 and leaves no temp file"
  mkdir "$d/H.tsv.lock"; touch -t 202001010000 "$d/H.tsv.lock"
  bash "$ds" apply --plan "$d/plan" --held "$d/H.tsv" >/dev/null 2>"$d/err"; rc=$?
  assert_eq "0" "$rc" "29 S6 a stale lock (older than the limit) is broken and apply runs"
  assert_contains "stale" "$(cat "$d/err")" "29 S6 and it warns that it broke one"
}

arm_owners_unread() {
  local ds="$1" r="$WORK/unread.$RANDOM" rc
  fixture "$r" >/dev/null
  printf -- '- **Ownership is fixed.**\n  - Platform: `docs/`.\n- **Next.**\n' >"$r/NOLIST.md"
  bash "$ds" owners-from-doc --repo "$r" --repo-id kit "$r/NOLIST.md" >"$WORK/unread.out" 2>"$WORK/unread.err"; rc=$?
  assert_eq "2" "$rc" "24 S1 the anchor without a lane → project list exits 2"
  assert_empty "$(cat "$WORK/unread.out")" "24 S1 and emits no rows"
  assert_contains "no lane → project list" "$(cat "$WORK/unread.err")" "24 S1 and says why"
  printf '# nothing\n' >"$r/NOANCHOR.md"
  bash "$ds" owners-from-doc --repo "$r" --repo-id kit "$r/NOANCHOR.md" >/dev/null 2>"$WORK/unread.err2"; rc=$?
  assert_eq "2" "$rc" "24 S1 a file with no Ownership anchor exits 2"
  assert_contains "no \"- **Ownership is fixed.**\" line" "$(cat "$WORK/unread.err2")" "24 N2 and names the missing anchor"
}

arm_docs_from_commit() {
  local ds="$1" r="$WORK/g3.$RANDOM" base out rc
  base=$(fixture "$r")
  mkdir -p "$r/skills/shiny"; printf '# shiny\n' >"$r/skills/shiny/SKILL.md"
  commit_all "$r" "add shiny"
  printf '\nHalf-written: see /shiny.\n' >>"$r/README.md"      # uncommitted mention
  out=$(bash "$ds" detect --repo "$r" --since "$base" 2>/dev/null); rc=$?
  assert_eq "3" "$rc" "25 g3 an uncommitted doc mention does not suppress the signal (exit 3)"
  assert_contains "fixture:skills/shiny/SKILL.md" "$out" "25 g3 docs are read from the commit, not the disk"
}

arm_other_markers() {
  local ds="$1" d
  d=$(newdir g6)
  mkdir -p "$d/kit" "$d/engine"; : >"$d/plan"
  bash "$ds" apply --plan "$d/plan" --held "$d/H.tsv" --since-repo "$d/kit" --since-sha KITSHA >/dev/null 2>&1
  bash "$ds" apply --plan "$d/plan" --held "$d/H.tsv" --since-repo "$d/engine" --since-sha ENGSHA >/dev/null 2>&1
  assert_eq "KITSHA" "$(bash "$ds" since --held "$d/H.tsv" --repo "$d/kit" 2>/dev/null)" "26 g6 an apply for one repo keeps the other repo's marker"
  assert_eq "ENGSHA" "$(bash "$ds" since --held "$d/H.tsv" --repo "$d/engine" 2>/dev/null)" "26 g6 and records its own"
}

# ---------------------------------------------------------------- behaviour

test_b_1_new_skill_fires()         { arm_new_skill "$DS"; }
test_b_2_removed_path_fires()      { arm_removed_path "$DS"; }
test_b_3_unrelated_does_not_fire() { arm_unrelated "$DS"; }
test_b_4_dedup_suppresses()        { arm_dedup "$DS"; }
test_b_5_missing_channel_holds()   { arm_missing_channel "$DS"; }
test_b_6_all_lists_posted()        { arm_all_notice "$DS"; }

test_b_7_unknown_kind_refused() {
  local d; d=$(newdir kind)
  printf 'signal\ttypo\tkit:a.md\tx\n' >"$d/sig"; : >"$d/o"; : >"$d/c"
  bash "$DS" plan --signals "$d/sig" --owners "$d/o" --channels "$d/c" >/dev/null 2>&1
  assert_eq "2" "$?" "7 a kind outside the vocabulary: plan exits 2"
}

test_b_8_registry_channels() {
  local d; d=$(newdir reg)
  printf '## Product: Stats\n- 🔴 Observed problems — [IDE-249](u)\n- 🟦 Documentation — [IDE-251](u)\n\n## Product: Idea\n- 🟦 Documentation — [docs](https://linear.app/x/issue/IDE-287/documentation)\n\n## Product: Example\n- 🔴 Observed — [ENG-1](u)\n' >"$d/R.md"
  assert_eq "Product: Stats${T}IDE-251
Product: Idea${T}IDE-287" "$(bash "$DS" registry-channels "$d/R.md")" "8 registry-channels: only 🟦 rows, keyed by project, key read from text or URL"
}

test_b_9_redundancy_once_and_held()  { arm_redundancy "$DS"; }
test_b_10_commits_only()             { arm_commits_only "$DS"; }
test_b_11_cap()                      { arm_cap "$DS"; }
test_b_12_owners_repo_scoped()       { arm_owners_repo "$DS"; }
test_b_13_marker_realpath()          { arm_marker_realpath "$DS"; }
test_b_14_marker_zero_signals()      { arm_marker_zero "$DS"; }
test_b_15_marker_seed()              { arm_marker_seed "$DS"; }
test_b_16_marker_unreachable()       { arm_marker_unreachable "$DS"; }
test_b_17_apply_guards()             { arm_apply_guards "$DS"; }
test_b_18_typescript()               { arm_typescript "$DS"; }
test_b_19_owners_from_doc()          { arm_owners_from_doc "$DS"; }
test_b_20_flags()                    { arm_flags "$DS"; }

test_b_22_fold_subjects()   { arm_fold "$DS"; }
test_b_23_readback_guard()  { arm_readback "$DS"; }
test_b_24_owners_unread()   { arm_owners_unread "$DS"; }
test_b_25_docs_from_commit(){ arm_docs_from_commit "$DS"; }
test_b_26_other_markers()   { arm_other_markers "$DS"; }
test_b_27_pause_across_seats(){ arm_pause "$DS"; }
test_b_28_space_key()        { arm_space_key "$DS"; }
test_b_29_apply_lock()       { arm_apply_lock "$DS"; }
test_b_30_owners_project_r6() { arm_owners_project_r6 "$DS"; }

test_b_21_empty_range() {
  local r="$WORK/empty.$RANDOM" out rc
  fixture "$r" >/dev/null
  out=$(bash "$DS" detect --repo "$r" --since HEAD 2>"$WORK/empty.err"); rc=$?
  assert_eq "0" "$rc" "21 S6: an empty range (since = HEAD) exits 0"
  assert_empty "$out" "21 S6: and prints nothing"
}

# ---------------------------------------------------------------- planted controls

# plant <sed-expr> → path of a planted copy, or empty when sed matched nothing
plant() {
  local tmp; tmp=$(mktemp "$WORK/planted.XXXXXX")
  sed "$1" "$REAL_DS" >"$tmp"
  if cmp -s "$REAL_DS" "$tmp"; then rm -f "$tmp"; echo ""; else echo "$tmp"; fi
}

# control <label> <arm> <sed-expr>
control() {
  local label="$1" arm="$2" tmp n
  tmp=$(plant "$3")
  if [ -z "$tmp" ]; then fail "control $label: the defect plants" "a changed copy" "sed matched nothing"; return; fi
  n=$( TESTS_FAILED=0; "$arm" "$tmp" >/dev/null 2>&1; echo "$TESTS_FAILED" )
  assert_gt "$n" "0" "control $label: planted, its arm reports failures ($n)"
}

# One plant per behaviour. The label names the defect; the arm is the one that must go red.
PLANT_1='s|^          skills/\*/SKILL.md\|\*/skills/\*/SKILL.md)$|          skills/*/SKILL.mdx\|*/skills/*/SKILL.mdx)|'
PLANT_2='s|^      D\*) query|      Dx*) query|'
PLANT_P='s|if (mode == "P") {|if (0) {|;s|present P "\$path"|present R "$path"|g'
PLANT_3='s|printf .%s\\n. "\$pre" \| grep -qE -- "\${tok}(\[^a-z0-9-\]\|\\\$)" \&\& continue|:|'
PLANT_4='s|if ((tolower(kind) SUBSEP tolower(file)) in opened) {|if (0) {|'
PLANT_5='s|emit("hold", kind, file, proj, "no-docs-channel", subject, source, key); return|emit("post", kind, file, proj, "-", subject, source, key); return|'
PLANT_6='s|head, ml, verb, np, list(np, P, 10)|head, ml, verb, np, ""|'
PLANT_R1='s|git -C "\$repo" diff --name-status -M "\$since" "\$head" >|git -C "$repo" diff --name-status -M "$since" >|'
PLANT_R3A='s|pair = (a < b) ? a SUBSEP b : b SUBSEP a|pair = a SUBSEP b|'
PLANT_R3B='s|max=3 holdkinds="redundancy"|max=3 holdkinds=""|'
PLANT_R4A='s|\*.md\|\*.test.\*\|\*.spec.\*\||*.md\||'
PLANT_R4B='s|m\[1\] == "100755" {print \$2}|{print $2}|'
PLANT_CAP='s|if (posts >= max) {|if (0) {|'
PLANT_KEYS='s|^  sed -E -e .s/\\\*\\\*//g. -e .s/\\\[(\[^\]\]\*)\\\]\\(\[^)\]\*\\)/\\1/g. -e .*$|  cat \||'
PLANT_REPO='s|want\[\$1\] = rid ":" \$6|want[$1] = $6|'
PLANT_D1='s|if (p\[1\] != r) continue|;|'
PLANT_UNRES='s|nu, list(nu, U, 5)|nu, ""|'
PLANT_S1='s|\[ -f "\$plan" \] \|\| die "apply: no plan at \$plan"|:|;s|if \[ \$rc -ne 0 \] \|\| ! mv|if ! mv|'
PLANT_S2='s|if (!(key in inplan) \&\& !(key in done)) keep\[++nk\] = l|if (0) keep[++nk] = l|'
PLANT_REAL='s|^  (cd "\$top" 2>/dev/null \&\& pwd -P) \|\| printf|  printf|'
PLANT_ZERO='s|\[ -f "\$plan" \] \|\| die "apply: no plan at \$plan"|[ -s "$plan" ] \|\| die "apply: no plan at $plan"|'
PLANT_SEED='s|done \| sort \| tail -1)|done \| sort \| head -1)|'
PLANT_UNREACH='s|warn "detect: since \$since is not a commit here; falling back to the last 24 hours"; since=\$fallback|die "detect: since $since is not a commit"|'
PLANT_TS='s|bin_keys "\$work/pkg.pre" \| grep -qxF -- "\$tok" \&\& continue|:|'
PLANT_OWN='s|if (p in over) continue  |;  |'
PLANT_M1='s|^  echo marker-lost; return 1|  echo landed; return 0|'
PLANT_LOSTSTICKY='s|if (reason == "marker-lost") {|if (0) {|'
PLANT_OSHAPE='s|sub(/\[\[:space:\].,;:)>\]+\$/, "", rest)|sub(/[[:space:]]+$/, "", rest)|'
PLANT_OCASE='s|opened\[tolower(a\[1\]) SUBSEP tolower(a\[2\])\] = 1|opened[a[1] SUBSEP a[2]] = 1|'
PLANT_FOLD='s|{ o6\[r\] = o6\[r\] "; " subject; return }|{ }|'
PLANT_NOLIST='s|  if (!listed) {|  if (0) {|;s|      if (!rows)   {|      if (0) {|'
PLANT_G3='s#git -C "\$repo" archive --format=tar "\$head" -- .:(glob)\*\*/\*.md. 2>/dev/null | tar -x -C "\$mirror" 2>/dev/null#cp -R "$repo/." "$mirror/"#'
PLANT_G6='s|if (a\[2\] != srepo \|\| ssha == "") marker|if (ssha == "") marker|'
PLANT_PAUSE='s|if (paused) {|if (0) {|'
PLANT_LOSTROOT='s|if \[ -n "\$root" \] \&\& \[ -d "\$root" \]; then|if false; then|'
PLANT_LOSTFIRST='s|if ((tolower(kind) SUBSEP tolower(file)) in opened) {|if (reason != "marker-lost" \&\& ((tolower(kind) SUBSEP tolower(file)) in opened)) {|'
PLANT_CARRIED='s|\$1 == "hold" \&\& \$5 == "marker-lost"      { held_lost = 1 }|$1 == "hold" \&\& $5 == "marker-lost" { nl++; L = add(L, $2 " " $3); next }|'
PLANT_SPACE='s|sub(/^</, "", rest);|sub(/^</, "", rest); sub(/ .*$/, "", rest);|'
PLANT_TRAP='s|^  trap .rm -f "\$tmp"; rmdir "\$lock" 2>/dev/null. EXIT$|  :|;s|^  trap .rm -f "\$tmp"; rmdir "\$lock" 2>/dev/null; trap - EXIT; exit 143. INT TERM HUP$|  :|'
PLANT_STALE='s|if \[ -n "\$(find "\$lock" -maxdepth 0 -mmin +5 2>/dev/null)" \]; then|if false; then|'
PLANT_LANDEDCASE='s|tolower(\$1) == k \&\& tolower(\$2) == f {hit = 1}|$1 == k \&\& $2 == f {hit = 1}|'
PLANT_NOANCHOR='s|      if (!anchor) {|      if (0) {|'
PLANT_FLAGS='s|grep -oE .\\\$\\{?\[0-9A-Za-z_@\]+\\}?"?\[\[:space:\]\]\*==?\[\[:space:\]\]\*"?--\[a-z\]\[a-z0-9-\]\*. 2>/dev/null|true|'

test_control_1_new_skill()       { control "1 (skill branch never matches)"            arm_new_skill          "$PLANT_1"; }
test_control_2_removed_path()    { control "2 (deletions ignored)"                     arm_removed_path       "$PLANT_2"; }
test_control_3_preimage()        { control "3 = P3 (pre-image ignored: a reflowed arm reads as new)" arm_unrelated "$PLANT_3"; }
test_control_4_dedup()           { control "4 (open comments ignored)"                 arm_dedup              "$PLANT_4"; }
test_control_5_missing_channel() { control "5 (no channel posts anyway)"               arm_missing_channel    "$PLANT_5"; }
test_control_6_all_notice()      { control "6 (all notice drops the posted list)"      arm_all_notice         "$PLANT_6"; }
test_control_p_path_tokens()     { control "P (path needle matched as a bare suffix)"  arm_removed_path      "$PLANT_P"; }
test_control_r1_commits_only()   { control "R1 (the working tree counts)"             arm_commits_only       "$PLANT_R1"; }
test_control_r3a_pair_once()     { control "R3a (a pair is reported both ways)"        arm_redundancy         "$PLANT_R3A"; }
test_control_r3b_held_back()     { control "R3b (redundancy posts)"                    arm_redundancy         "$PLANT_R3B"; }
test_control_r4a_tests()         { control "R4a (a *.test.* file is a command)"        arm_unrelated          "$PLANT_R4A"; }
test_control_r4b_helpers()       { control "R4b (a sourced 100644 helper is a command)" arm_unrelated         "$PLANT_R4B"; }
test_control_cap()               { control "cap (no --max)"                            arm_cap                "$PLANT_CAP"; }
test_control_keys()              { control "open-keys (no markdown normalising)"       arm_dedup              "$PLANT_KEYS"; }
test_control_repo_key()          { control "repo key (detect drops the repo-id)"       arm_new_skill          "$PLANT_REPO"; }
test_control_d1()                { control "D1 (owner rows ignore the repo)"           arm_owners_repo        "$PLANT_D1"; }
test_control_unresolved()        { control "unresolved owners not in the notice"       arm_all_notice         "$PLANT_UNRES"; }
test_control_s1()                { control "S1 (apply on a missing plan exits 0)"      arm_apply_guards       "$PLANT_S1"; }
test_control_s2()                { control "S2 (apply replaces, dropping held rows)"   arm_apply_guards       "$PLANT_S2"; }
test_control_s5_realpath()       { control "S5 realpath (repo key not canonical)"      arm_marker_realpath    "$PLANT_REAL"; }
test_control_s5_zero()           { control "S5 zero (an empty plan cannot apply)"      arm_marker_zero        "$PLANT_ZERO"; }
test_control_s5_seed()           { control "S5 seed (the oldest marker seeds)"         arm_marker_seed        "$PLANT_SEED"; }
test_control_s5_unreachable()    { control "S5 unreachable (an unknown sha fails)"     arm_marker_unreachable "$PLANT_UNREACH"; }
test_control_ts()                { control "TS (pre-image bins ignored)"               arm_typescript         "$PLANT_TS"; }
test_control_owners_doc()        { control "owners-from-doc (override does not win)"   arm_owners_from_doc    "$PLANT_OWN"; }
test_control_m1_readback()       { control "M1 (a key that does not read back counts as landed)" arm_readback "$PLANT_M1"; }
test_control_m1_sticky()         { control "M1 sticky (a marker-lost row is re-posted)" arm_readback "$PLANT_LOSTSTICKY"; }
test_control_s2_trailing()       { control "S2 (open-keys keeps trailing punctuation)" arm_dedup "$PLANT_OSHAPE"; }
test_control_s2_case()           { control "S2 case (open keys compared case-sensitively)" arm_dedup "$PLANT_OCASE"; }
test_control_s3_fold()           { control "S3 (rows sharing a key do not fold)" arm_fold "$PLANT_FOLD"; }
test_control_s1_unread()         { control "S1 (no lane list still exits 0)" arm_owners_unread "$PLANT_NOLIST"; }
test_control_g3_disk()           { control "g3 (docs read from the disk)" arm_docs_from_commit "$PLANT_G3"; }
test_control_g6_markers()        { control "g6 (apply drops other repos markers)" arm_other_markers "$PLANT_G6"; }
test_control_must1_pause()       { control "MUST-1a (a held marker-lost row does not pause posting)" arm_pause "$PLANT_PAUSE"; }
test_control_must1_pause_run()   { control "MUST-1a (pause, the readback arm)" arm_readback "$PLANT_PAUSE"; }
test_control_must1_root()        { control "MUST-1b (other sessions' held files not read)" arm_pause "$PLANT_LOSTROOT"; }
test_control_s5_lost_first()     { control "S5 (marker-lost checked before the open dedup)" arm_readback "$PLANT_LOSTFIRST"; }
test_control_s1_carried()        { control "S1 (a carried marker-lost row leads as this run's loss)" arm_readback "$PLANT_CARRIED"; }
test_control_s4_space()          { control "S4 (a key ends at the first space)" arm_space_key "$PLANT_SPACE"; }
test_control_s6_trap()           { control "S6 (no EXIT/INT/TERM trap releases the lock)" arm_apply_lock "$PLANT_TRAP"; }
test_control_s6_stale()          { control "S6 (a stale lock is never broken)" arm_apply_lock "$PLANT_STALE"; }
test_control_n1_landed_case()    { control "N1 (landed compares case-sensitively)" arm_readback "$PLANT_LANDEDCASE"; }
test_control_n2_noanchor()       { control "N2 (the anchor exit removed)" arm_owners_unread "$PLANT_NOANCHOR"; }
test_control_flags()             { control "flags (test expressions not read)"         arm_flags              "$PLANT_FLAGS"; }

# ---------------------------------------------------------------- text contract

# grep the file itself: assert_contains pipes the haystack through `echo | grep -q`, and under
# pipefail a 60 KB haystack makes that flaky (grep -q exits early, echo takes SIGPIPE).
skill_has() {
  if grep -qF -- "$1" "$SKILL"; then pass "$2"; else fail "$2" "contains '$1'" "absent from $SKILL"; fi
}

test_t_skill_wiring() {
  skill_has "assets/doc-signals.sh" "SKILL cites the detector"
  skill_has "NEXT_DOC_SIGNALS.tsv" "SKILL names the held file"
  skill_has "¶INV_NEXT_DOC_SIGNALS_ROUTE_OR_HOLD" "SKILL carries the routing invariant"
  skill_has "undocumented-feature · stale-reference · redundancy · contradiction · other" "SKILL states the kind vocabulary"
  skill_has "docs: posted —" "SKILL names the docs: notice line for all"
  skill_has "Exception — the held documentation signals" "¶INV_NEXT_INVENTS_NO_STORE carries the held-file exception"
  skill_has "the since-marker sits inside this exception" "the exception names the since-marker (Q1 ruling)"
  skill_has "/inbox-post" "SKILL routes posting through /inbox-post"
  skill_has "doc owners" "SKILL names the owner map 'doc owners' (D2)"
  skill_has "detected, not posted" "SKILL holds redundancy back (R3)"
  skill_has "--max" "SKILL names the per-run cap"
  skill_has "doc-signals.sh landed" "SKILL names the read-back guard (M1)"
  skill_has "marker-lost" "SKILL names marker-lost on the docs: line (M1)"
  skill_has "plan … --sessions-root" "MUST-1b the plan invocation reads every session's held file"
  skill_has "posting-paused" "MUST-1a SKILL names the posting-paused hold"
  skill_has "Run the guard only when \`/inbox-post\` reports that it created a comment" "S3 a declined or failed post is not read back as marker-lost"
  skill_has "A declined or failed \`/inbox-post\` in the docs step does not end the sequence" "S3 SKILL says which rule wins for the docs step"
  skill_has "every 🟦 channel a row routes to" "N7 open comments come from every channel a row routes to"
  local bad
  bad=$(grep -F -- "notice --mode all" "$SKILL" | grep -vF -- "--lost" || true)
  if [ -z "$bad" ]; then pass "S2 every notice --mode all invocation passes --lost"
  else fail "S2 every notice --mode all invocation passes --lost" "--lost on each line" "$(printf '%s' "$bad" | cut -c1-120)"; fi
  if grep -qF "LIVE_MARKET_DIRECT" "$SKILL" || grep -qF "sessions/2026_10_28" "$SKILL"; then
    fail "N1 SKILL names no kit path" "no LIVE_MARKET_DIRECT, no kit session path" "found"
  else pass "N1 SKILL names no kit path"; fi
}

run_discovered_tests
