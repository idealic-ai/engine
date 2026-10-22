#!/usr/bin/env bash
# The wave boundary — integration. Three parts, and the third one is SKIPPED on purpose.
#
# WHAT THIS COVERS
#   The loom now specifies how a wave's lanes are brought back together: the conductor merges each
#   lane's branch onto the session branch in landing order with --no-ff, runs the once-per-wave
#   suite against the assembled sha, and hands a conflict back to the later lander. See
#   `skills/loom/SKILL.md` § "The wave boundary — integration" and `§INV_LOOM_INTEGRATES_AT_THE_WAVE_BOUNDARY`.
#
# WHY A PART OF IT CANNOT RUN
#   The loom's live collision strategy is PREVENTION — a disjoint file partition with
#   first-claim-wins — so two lanes never touch one file and a merge conflict cannot arise. The
#   thing that makes conflicts possible is a tree per lane, and that is not built. So the mechanism
#   specified here has no triggering condition in this repository yet, and a paragraph saying so is
#   not enforcement.
#
#   Part A asserts the RULE IS STATED, and reddens if the specification is deleted or hollowed out.
#   Part B asserts the GIT MECHANICS the specification rests on, in a throwaway repository under
#     $TMPDIR — never this checkout, which carries several lanes' uncommitted work. These are the
#     claims the spec makes about git itself (--no-ff leaves a merge commit; an abort restores the
#     branch to its exact pre-merge sha; --diff-filter=U names the collision), and they are
#     measurable today, so they are measured rather than assumed.
#   Part C is the case against the rule for the part that cannot run: that a loom ACTUALLY
#     integrated a wave. It is skipped, per `§INV_A_KNOWN_DEFECT_SHIPS_AS_A_SKIPPED_CASE`.
#
# THE CONDITION THAT UN-SKIPS PART C  (it arms itself — nobody has to remember)
#   Any of:
#     * the "### The Setup dispositions" section of `skills/loom/SKILL.md` gains a bolded dial
#       LABEL this probe recognises (Execution shape · Worktree · Tree per lane · Tree shape ·
#       Lane isolation); or
#     * — the arm that does NOT depend on what the dial is called — that same section comes to
#       MENTION lanes having their own trees in any disposition's body text (worktree, tree per
#       lane, own tree, a tree for every/each lane). Read from the DISPOSITION BULLETS only, not
#       this section's prose, so the pointer paragraph that names this very file cannot arm it.
#       A dial that offers worktree-per-lane cannot
#       describe itself without saying so, which is why this arm is the robust one; or
#     * the environment sets LOOM_WORKTREE_PER_LANE=1.
#
#   WHY TWO ARMS, measured rather than assumed: the first draft of this file armed on the LABEL
#   alone, and that assumption was falsified in review. On a copy whose dispositions gained
#   `**Tree per lane**: [one shared tree | a worktree for every lane]` the suite came back
#   30 ok / 0 FAIL / 3 skipped, exit 0 — C1 still reading `skip` — while the identical mutation
#   spelled `**Execution shape**` armed it to exit 1. A probe bound to a name the future lane has
#   not chosen yet fails toward a FALSE ABSENCE: the case stays quietly skipped and reads as a
#   clean run. Case A22 keeps the meaning arm honest from the other side.
#   Once armed, Part C requires a real integrated wave: WAVE_LOG=<path to a loom log> whose
#   `## 🌊 Wave` block carries a closed `Integration` row and a `Suite` reading naming a sha.
#   ARMED WITH NO WAVE_LOG IS A FAILURE, not a skip — that red is the point: it says the mechanism
#   became reachable and nobody has yet shown it running.
#
#   NOTE ON THE ARMING PROBE: a bare `worktree` grep over SKILL.md FALSE-POSITIVES — the word
#   already appears in the /experiment bullet ("or run in an isolated worktree"). A stem that
#   sounds distinctive is not the same as one that is, and this failure direction is a false
#   PRESENCE, whose consequence is skipping work while believing it done. The probe is therefore
#   scoped to a bolded disposition label inside the Setup dispositions section, and case A0 proves
#   the naive stem would have lied.
#
# Run:  ~/.claude/engine/skills/loom/assets/__tests__/wave-integration.test.sh
# No network. No writes anywhere inside the engine checkout.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
loom="$(cd "$here/../.." && pwd)"
SKILL="$loom/SKILL.md"
TPL="$loom/assets/TEMPLATE_LOOM_LOG.md"
DIR="$loom/assets/LOOM_AGENT_DIRECTIONS.md"
GITIGNORE="$(cd "$loom/../.." && pwd)/.gitignore"

pass=0; fail=0; skipped=0
ok()   { pass=$((pass+1));    printf '  ok    %s\n' "$1"; }
no()   { fail=$((fail+1));    printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
skip() { skipped=$((skipped+1)); printf '  skip  %s\n        un-skips when: %s\n' "$1" "${2:-}"; }

# states() — assert a literal string is present in a file. Every absence claim in this file goes
# through here, and the file-reaches control (A-control) fires in the same run, so a zero reading
# is the probe working rather than the probe missing its target.
states() { grep -qF -- "$2" "$1"; }

printf '\n== Part A — the rule is stated (reddens if the specification is deleted) ==\n'

[ -f "$SKILL" ] || { no "A-control  SKILL.md is readable" "not found at $SKILL"; }
[ -f "$TPL" ]   || { no "A-control  log template is readable" "not found at $TPL"; }

# The control for every absence claim below: a stem that MUST be there, and one that must not.
if states "$SKILL" 'INV_LOOM_COMPOSED_WRITES' && ! states "$SKILL" 'INV_LOOM_NOSUCHRULE_CONTROL'; then
  ok "A-control  the probe reaches SKILL.md and discriminates (present stem found, planted absent stem not found)"
else
  no "A-control  the probe reaches SKILL.md and discriminates" "a present stem was missed or an absent stem was found — every other case in Part A is theatre until this passes"
fi

# A0 — the arming probe's own trap, measured rather than asserted.
naive_hits="$(grep -ocF 'worktree' "$SKILL" 2>/dev/null || echo 0)"
if [ "$naive_hits" -gt 0 ]; then
  ok "A0  the naive arming stem 'worktree' already matches SKILL.md ($naive_hits line(s)) — a false PRESENCE, which is why Part C's probe is scoped to a disposition label"
else
  no "A0  the naive arming stem 'worktree' already matches SKILL.md" "it matched nothing, so the premise behind the scoped probe has changed — re-derive the arming condition before trusting Part C's skip"
fi

a_case() { # name, file, literal
  if states "$2" "$3"; then ok "$1"; else no "$1" "missing from ${2##*/}: $3"; fi
}

a_case "A1  the wave boundary is a named section in the skill"            "$SKILL" '### The wave boundary — integration'
a_case "A2  the invariant is defined exactly once, with a pilcrow"        "$SKILL" '¶INV_LOOM_INTEGRATES_AT_THE_WAVE_BOUNDARY'
a_case "A3  the gate's subject tree is its own invariant"                 "$SKILL" '¶INV_LOOM_GATE_RUNS_ON_THE_INTEGRATED_TREE'
a_case "A4  the boundary is distinguished from the loop gate's unit"      "$SKILL" 'unit of progress'
a_case "A5  the base is the session branch, captured at Setup"            "$SKILL" 'sessionBranch'
a_case "A6  the order is landing order, first-landed first"               "$SKILL" 'landing order, first-landed first'
a_case "A7  the merge is --no-ff, and that is load-bearing"               "$SKILL" '`--no-ff`'
a_case "A8  a conflict aborts and never resolves"                         "$SKILL" 'never resolved, never `-X`'
a_case "A9  the conflicting lane resolves in its OWN tree"                "$SKILL" 'INTO its own branch'
a_case "A10 the conflict paths come from --diff-filter=U"                 "$SKILL" '--diff-filter=U'
a_case "A11 a partially integrated tree is forbidden as the subject"      "$SKILL" 'suite deferred'
a_case "A12 one PR for the assembled wave, whole-branch"                  "$SKILL" 'ONE PR FOR THE ASSEMBLED WAVE'
a_case "A13 partition and merge are mutually exclusive"                   "$SKILL" 'two answers to ONE question'
a_case "A14 the cold-lane case STOPS rather than inventing a fallback"    "$SKILL" 'no fallback has been chosen'
a_case "A15 the wave record gates Loom→Synthesis"                         "$SKILL" 'wavesIntegrated'
a_case "A16 the log template records the session branch at open"          "$TPL"   '**Session branch**'
a_case "A17 the log template records the execution shape"                 "$TPL"   '**Execution shape**'
a_case "A18 the wave block records the boundary reading"                  "$TPL"   '**Boundary**'
a_case "A19 the wave block records each lane's merge"                     "$TPL"   '**Integration**'
a_case "A20 the wave block names the sha the suite ran against"           "$TPL"   '**Integrated tree**'
a_case "A21 the shared-tree reading is an allowed, written outcome"       "$TPL"   'nothing to merge — shared tree'

# A22 — the meaning arm, honest from the other side. Part C's label arm knows a fixed list of dial
# names; a future rename it has not been taught reads as a false absence. This case asserts the
# thing the meaning arm looks FOR actually exists in a bolded disposition bullet, so a rename that
# silences the label arm cannot silence both at once without also reddening here.
if printf '%s' "$(awk '/^### The Setup dispositions/{f=1;next} /^### /{f=0} f' "$SKILL" 2>/dev/null)" \
   | grep -E '^\*[[:space:]]+\*\*' \
   | grep -qiE 'worktree|tree per lane|tree-per-lane|own tree|tree for every lane|tree for each lane'; then
  ok "A22 a bolded Setup disposition says in words that lanes hold their own trees — the arm that survives a dial rename"
else
  no "A22 a bolded Setup disposition says in words that lanes hold their own trees" "no disposition bullet carries the meaning, so Part C's label arm is the only thing holding the arming up — a rename would silence it and read as a clean skip"
fi

printf '\n== Part D — the dial half is stated (reddens if the batching dial or the global cap is deleted) ==\n'

if states "$DIR" 'threadId' && ! states "$DIR" 'INV_LOOM_NOSUCHRULE_CONTROL'; then
  ok "D-control the probe reaches the lane directions and discriminates (present stem found, planted absent stem not found)"
else
  no "D-control the probe reaches the lane directions and discriminates" "a present stem was missed or an absent stem was found — every D case touching that file is theatre until this passes"
fi

# D1 is scoped to the dispositions SECTION rather than the whole file. Measured: the unscoped form
# passed on a copy whose disposition bullet had been deleted, because the literal also appears in
# Setup's ask step and in the ledger field it names — a pattern matching what both states share.
if printf '%s' "$(awk '/^### The Setup dispositions/{f=1;next} /^### /{f=0} f' "$SKILL" 2>/dev/null)" \
   | grep -qF '*   **Execution shape**'; then
  ok "D1  the batching dial is a Setup disposition, named — inside the dispositions section, not merely somewhere in the file"
else
  no "D1  the batching dial is a Setup disposition, named" "no '**Execution shape**' bullet in § The Setup dispositions; the literal elsewhere in the file does not make it a dial anyone is asked"
fi

a_case "D2  the once-per-wave suite is its own invariant"                 "$SKILL" '¶INV_SUITE_ONCE_PER_WAVE'
a_case "D3  the global cap is its own invariant"                          "$SKILL" '¶INV_SLOT_CAP_IS_GLOBAL'
a_case "D4  the worktree default rests on a local measurement"            "$SKILL" '¶INV_LOOM_WORKTREE_DEFAULT_IS_MEASURED'
a_case "D5  the measured distribution is cited, not asserted"             "$SKILL" '105 interleaved order-rotated runs'
a_case "D6  the spread is stated, so no single timing reads as evidence"  "$SKILL" '10.7s–102.0s'
a_case "D7  reducing concurrency is recorded as falsified, not untried"   "$SKILL" '311.1s against a 40.4s baseline'
a_case "D8  an advertised figure is marked as not a measurement"          "$SKILL" 'inside the noise band'
a_case "D9  the slot count's home is named and sits in the engine tree"   "$SKILL" '~/.claude/engine/.loom-slots/'
a_case "D10 one writer per file is what makes the read lock-free"         "$SKILL" 'writes only its own file and reads every file'
a_case "D11 a stale slot row is reported rather than dropped"             "$SKILL" 'reported as stale and not counted'
a_case "D12 deriving the count is recorded as falsified here"             "$SKILL" 'find-sessions.sh active'
a_case "D13 the justifying measurement names its own method"              "$SKILL" 'read back through the workspace link'
a_case "D14 the partition is conditional on the dial, not standing"       "$SKILL" "computes **no** partition and brokers **no** claims"
a_case "D15 lanes are told to run targeted tests, not the suite"          "$DIR"   'you do not run the full suite'
a_case "D16 the lane partition section is marked conditional"             "$DIR"   '## File ownership — under one shared tree'
a_case "D17 a lane with its own tree is told to stay inside it"           "$DIR"   'stay in your own tree'

# D18 — measured rather than asserted: the slot directory must be ignored by git, or a loom's own
# bookkeeping lands in the untracked set of a checkout several sessions share. Controls in the same
# invocation, because `check-ignore` on a path that does not exist answers about the pattern only.
if [ -f "$GITIGNORE" ]; then
  # Paths are REPO-ROOT-RELATIVE and the probe runs from the repo root. `check-ignore` resolves a
  # relative path against its own cwd, so running it from skills/loom/ asks about
  # skills/loom/.project-fetch — a different question with the same shape of answer, which is how
  # the first draft of this case failed its own control.
  root="$(cd "$loom/../.." && pwd)"
  gi_ctl_in="$(git -C "$root" check-ignore -q 'control-probe.db' 2>/dev/null && echo 1 || echo 0)"
  gi_ctl_out="$(git -C "$root" check-ignore -q 'skills/loom/SKILL.md' 2>/dev/null && echo 1 || echo 0)"
  gi_hit="$(git -C "$root" check-ignore -q '.loom-slots/probe.slots' 2>/dev/null && echo 1 || echo 0)"
  if [ "$gi_ctl_in" = 1 ] && [ "$gi_ctl_out" = 0 ] && [ "$gi_hit" = 1 ]; then
    ok "D18 the slot directory's contents are gitignored (controls fired: a *.db path read ignored, a tracked file did not)"
  elif [ "$gi_ctl_in" != 1 ] || [ "$gi_ctl_out" != 0 ]; then
    no "D18 the slot directory's contents are gitignored" "the controls did not discriminate (known-ignored=$gi_ctl_in, tracked=$gi_ctl_out) — the reading on .loom-slots/ is void either way"
  else
    no "D18 the slot directory's contents are gitignored" "a file under .loom-slots/ is NOT ignored, so every loom's slot bookkeeping shows up in a shared checkout's untracked set"
  fi
else
  no "D18 the slot directory's contents are gitignored" "no .gitignore found at $GITIGNORE"
fi

printf '\n== Part B — the git mechanics the specification rests on (throwaway repo, never this checkout) ==\n'

tmp="$(mktemp -d "${TMPDIR:-/tmp}/loom-wave-integration.XXXXXX")" || { echo "cannot make a scratch dir"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
R="$tmp/repo"

g() { git -C "$R" "$@"; }

mkdir -p "$R"
git -c init.defaultBranch=session init -q "$R" >/dev/null 2>&1
g config user.email loom@example.invalid
g config user.name  "Loom Test"
g config commit.gpgsign false
printf 'alpha\nbeta\ngamma\n' > "$R/shared.txt"
g add shared.txt >/dev/null 2>&1
g commit -qm base >/dev/null 2>&1
base_sha="$(g rev-parse HEAD 2>/dev/null)"

if [ -n "${base_sha:-}" ]; then
  ok "B-control  a throwaway repo was created and committed to at $R (so a later zero reading is not a broken harness)"
else
  no "B-control  a throwaway repo was created and committed to" "git init/commit failed in $tmp — every case below is meaningless"
  printf '\n  %d ok, %d FAIL, %d skipped\n\n' "$pass" "$fail" "$skipped"; exit 1
fi

# Two lanes editing the SAME line — the collision the file partition exists to prevent, and the one
# a merge detects. laneA lands first, laneB second.
g checkout -q -b laneA session >/dev/null 2>&1
printf 'alpha\nLANE-A\ngamma\n' > "$R/shared.txt"; g commit -qam "laneA" >/dev/null 2>&1
g checkout -q -b laneB session >/dev/null 2>&1
printf 'alpha\nLANE-B\ngamma\n' > "$R/shared.txt"; g commit -qam "laneB" >/dev/null 2>&1
g checkout -q session >/dev/null 2>&1

# B1 — the first lane merges, --no-ff, and leaves a MERGE COMMIT. That commit is what engages
# /pr's own refusal to cherry-pick merge commits, which forces the whole-branch path and makes the
# declined per-lane PR structurally unavailable rather than merely remembered.
g merge --no-ff -q -m "integrate laneA" laneA >/dev/null 2>&1
m1_status=$?
sha_after_a="$(g rev-parse HEAD)"
parents_a="$(g rev-list --parents -n1 HEAD | wc -w | tr -d ' ')"   # 1 self + N parents
if [ "$m1_status" -eq 0 ] && [ "$parents_a" -eq 3 ]; then
  ok "B1  first lane merges --no-ff and leaves a merge commit (2 parents) — the commit /pr's merge-commit rule refuses to cherry-pick"
else
  no "B1  first lane merges --no-ff and leaves a merge commit" "merge status=$m1_status, self+parents=$parents_a (expected 0 and 3)"
fi

# B2 — without --no-ff a fast-forwardable merge leaves NO merge commit. This is the measurement
# that makes --no-ff load-bearing: the single-lane wave that fast-forwards re-opens /pr's
# cherry-pick fork, which is the shape the operator declined.
g checkout -q -b ff-base session >/dev/null 2>&1
g checkout -q -b ff-lane ff-base >/dev/null 2>&1
printf 'alpha\nLANE-A\ngamma\nff\n' > "$R/shared.txt"; g commit -qam "ff lane" >/dev/null 2>&1
g checkout -q ff-base >/dev/null 2>&1
g merge -q ff-lane >/dev/null 2>&1
parents_ff="$(g rev-list --parents -n1 HEAD | wc -w | tr -d ' ')"
if [ "$parents_ff" -eq 2 ]; then
  ok "B2  a fast-forwardable merge WITHOUT --no-ff leaves no merge commit (1 parent) — so --no-ff is load-bearing, not cosmetic"
else
  no "B2  a fast-forwardable merge without --no-ff leaves no merge commit" "self+parents=$parents_ff (expected 2)"
fi
g checkout -q session >/dev/null 2>&1

# B3 — the second lane CONFLICTS, and the conflicting paths are nameable in the exact form the
# hand-back carries.
g merge --no-ff -q -m "integrate laneB" laneB >/dev/null 2>&1
m2_status=$?
unmerged="$(g diff --name-only --diff-filter=U | tr '\n' ' ' | sed 's/ *$//')"
if [ "$m2_status" -ne 0 ] && [ "$unmerged" = "shared.txt" ]; then
  ok "B3  the later lander conflicts, and --diff-filter=U names the collision ('$unmerged') — the field the hand-back carries"
else
  no "B3  the later lander conflicts and --diff-filter=U names the collision" "merge status=$m2_status, unmerged='$unmerged' (expected non-zero and 'shared.txt')"
fi

# B4 — the abort restores the session branch to its EXACT pre-merge sha. Not the wave's starting
# sha: the branch legitimately moved when laneA landed, so the claim is "pre-merge", which is the
# only version of it that is true.
g merge --abort >/dev/null 2>&1
sha_now="$(g rev-parse HEAD)"
if [ "$sha_now" = "$sha_after_a" ] && [ "$sha_now" != "$base_sha" ]; then
  ok "B4  abort restores the session branch to its exact pre-merge sha (and that is NOT the wave's opening sha — laneA had legitimately moved it)"
else
  no "B4  abort restores the session branch to its exact pre-merge sha" "after abort=$sha_now, pre-merge=$sha_after_a, wave open=$base_sha"
fi

# B5 — the direction the spec mandates: the LANE merges the session branch into ITS OWN branch and
# resolves there, leaving shared ground untouched. The assertion is on the session branch's sha
# after the lane has resolved: it must not have moved.
g checkout -q laneB >/dev/null 2>&1
g merge --no-ff -q -m "take base" session >/dev/null 2>&1
printf 'alpha\nLANE-A and LANE-B\ngamma\n' > "$R/shared.txt"
g add shared.txt >/dev/null 2>&1
g commit -qm "resolve against the session branch" >/dev/null 2>&1
g checkout -q session >/dev/null 2>&1
sha_shared_after_lane_work="$(g rev-parse HEAD)"
if [ "$sha_shared_after_lane_work" = "$sha_after_a" ]; then
  ok "B5  the lane resolved in its own tree and the session branch did not move — shared ground is never the resolution surface"
else
  no "B5  the lane resolved in its own tree and the session branch did not move" "session branch moved to $sha_shared_after_lane_work from $sha_after_a"
fi

# B6 — and the conductor's re-attempt then succeeds, with a merge commit, so the wave assembles.
g merge --no-ff -q -m "integrate laneB (resolved)" laneB >/dev/null 2>&1
m3_status=$?
parents_b="$(g rev-list --parents -n1 HEAD | wc -w | tr -d ' ')"
body="$(cat "$R/shared.txt")"
if [ "$m3_status" -eq 0 ] && [ "$parents_b" -eq 3 ] && [ "$body" = "$(printf 'alpha\nLANE-A and LANE-B\ngamma')" ]; then
  ok "B6  the conductor's re-attempt lands, with a merge commit, carrying BOTH lanes' work — the assembled tree the suite judges"
else
  no "B6  the conductor's re-attempt lands carrying both lanes' work" "status=$m3_status, self+parents=$parents_b, body='$body'"
fi

printf '\n== Part C — the case against the rule: a loom ACTUALLY integrated a wave ==\n'

# The arming probe. Scoped to a bolded disposition label inside the Setup dispositions section,
# because the bare word `worktree` already matches elsewhere in the file (case A0 measures that).
armed=""
why=""
dispositions="$(awk '/^### The Setup dispositions/{f=1;next} /^### /{f=0} f' "$SKILL" 2>/dev/null)"
MEANING='worktree|tree per lane|tree-per-lane|own tree|tree for every lane|tree for each lane'
if [ "${LOOM_WORKTREE_PER_LANE:-0}" = "1" ]; then
  armed=1; why="LOOM_WORKTREE_PER_LANE=1"
elif printf '%s' "$dispositions" | grep -qE '^\*[[:space:]]+\*\*(Execution shape|Worktree|Tree per lane|Tree shape|Lane isolation)'; then
  armed=1; why="SKILL.md's Setup dispositions gained a dial this probe recognises by name"
elif printf '%s' "$dispositions" | grep -E '^\*[[:space:]]+\*\*' | grep -qiE "$MEANING"; then
  armed=1; why="SKILL.md's Setup dispositions now describe lanes holding their own trees (the arm that does not depend on what the dial is called)"
fi

# C-arm — the instrument disclosed, so a skip is never mistaken for a probe that failed to look.
# Both arm readings are printed every run, with the dispositions section's own size as the control
# that the section was located at all: a 0-line section would make both arms read "absent" for the
# trivial reason, which is the failure mode this line exists to expose.
disp_lines="$(printf '%s' "$dispositions" | grep -c . || true)"
label_hit="$(printf '%s' "$dispositions" | grep -cE '^\*[[:space:]]+\*\*(Execution shape|Worktree|Tree per lane|Tree shape|Lane isolation)' || true)"
mean_hit="$(printf '%s' "$dispositions" | grep -E '^\*[[:space:]]+\*\*' | grep -ciE "$MEANING" || true)"
if [ "${disp_lines:-0}" -gt 0 ]; then
  ok "C-arm  the Setup dispositions section was located ($disp_lines lines) — label arm=$label_hit, meaning arm=$mean_hit, env arm=${LOOM_WORKTREE_PER_LANE:-0}; armed=${armed:-no}"
else
  no "C-arm  the Setup dispositions section was located" "0 lines — both arms would read 'absent' for the trivial reason and Part C would skip without having looked at anything"
fi

if [ -z "$armed" ]; then
  skip "C1  a wave's lanes were merged in landing order onto the session branch" \
       "worktree-per-lane ships — SKILL.md § The Setup dispositions gains a dial named for it, OR simply mentions lanes holding their own trees (the arm that survives a dial this probe has not been taught to recognise), or LOOM_WORKTREE_PER_LANE=1. Lane branches do not exist under one shared tree, so there is nothing to merge."
  skip "C2  a conflicting lane was resumed and resolved its own conflict" \
       "the same condition. The live collision strategy is PREVENTION — a disjoint file partition with first-claim-wins — so no conflict has ever arisen here."
  skip "C3  the once-per-wave suite ran against the integrated sha, not a lane's tree" \
       "the same condition, plus a loom log to read: WAVE_LOG=<path>."
elif [ -z "${WAVE_LOG:-}" ]; then
  no "C1  a wave's lanes were merged in landing order onto the session branch" \
     "ARMED ($why) and no WAVE_LOG was supplied. The mechanism is now reachable and no run of it has been shown. Point WAVE_LOG at a loom log whose '## 🌊 Wave' block carries a closed Integration row."
  no "C2  a conflicting lane was resumed and resolved its own conflict" "ARMED ($why) and no WAVE_LOG was supplied."
  no "C3  the once-per-wave suite ran against the integrated sha" "ARMED ($why) and no WAVE_LOG was supplied."
else
  if [ ! -f "$WAVE_LOG" ]; then
    no "C-control WAVE_LOG is readable" "not a file: $WAVE_LOG"
  else
    wave="$(awk '/^## .. Wave/{f=1} f' "$WAVE_LOG" 2>/dev/null)"
    # The heading carries an emoji, so it is matched by a two-character wildcard rather than by a
    # range spanning the glyph — a `sed` range written across a multibyte character returns zero
    # lines and a diff built on it reads "identical" at exit 0.
    if [ -n "$wave" ]; then
      ok "C-control the log's wave block was located (a zero reading here would be the glyph, not the absence)"
    else
      no "C-control the log's wave block was located" "no '## <emoji> Wave' heading in $WAVE_LOG"
    fi
    if printf '%s' "$wave" | grep -qE 'Integration.*(merged [0-9a-f]{7,}|nothing to merge|conflict)'; then
      ok "C1  the wave's Integration row is closed with a disposition per lane"
    else
      no "C1  the wave's Integration row is closed with a disposition per lane" "no merged sha, shared-tree reading, or conflict disposition in the wave block"
    fi
    if printf '%s' "$wave" | grep -qE 'conflict.*(resumed|ESCALATED)'; then
      ok "C2  a conflicting lane was handed back (resumed) or escalated — never resolved by the conductor"
    else
      skip "C2  a conflicting lane was resumed and resolved its own conflict" "this wave had no conflict to hand back; a wave that does will exercise it"
    fi
    if printf '%s' "$wave" | grep -qE 'Suite.*((green|red) @ [0-9a-f]{7,}|deferred)'; then
      ok "C3  the suite's reading names the sha it ran against, or states the deferral"
    else
      no "C3  the suite's reading names the sha it ran against" "a Suite line with no sha is a green with no subject tree"
    fi
  fi
fi

printf '\n  %d ok, %d FAIL, %d skipped\n\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ] || exit 1
exit 0
