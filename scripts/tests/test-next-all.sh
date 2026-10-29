#!/bin/bash
# test-next-all.sh — IDE-236: `/next all` runs the whole sequence and asks nothing; a plain
# `/next` keeps the shipped consent (IDE-154) exactly.
#
# Two kinds of arm:
#   * BEHAVIOUR — skills/next/assets/consent-mode.sh is the one place the waiver is decided.
#     The skill tells the agent to hand it the operator's literal argument text on STDIN through
#     a quoted heredoc (never on a shell line), so ¶INV_NEXT_ALL_IS_THE_WORD_ONLY ("only an exact
#     `/next all`, nothing after it, waives") is executable here, byte for byte.
#   * TEXT CONTRACT — the amended invariants, the description, the notice, the stop rules and the
#     waiver citations in skills/next/SKILL.md, plus a drift sensor on the composed skills' own
#     args lines.
#
# PLANTED-DEFECT CONTROLS: each copies the resolver, plants a defect into the copy, and asserts
# the plain-run arm reports failures against it. A plain-run arm that cannot go red proves
# nothing. Control 1 plants "plain /next waives"; control 2 plants punctuation tolerance
# (`all,` `all.` `all!` waive).
#
# DECLARED BOUNDARY (¶INV_A_NEGATIVE_ONLY_CHECK_SAYS_SO): the text arms read the skill file and
# the composed skills' `args:` lines; they do not run a live /next, /snapshot or /groom. That an
# agent following the prose actually skips its AskUserQuestion, or actually feeds the heredoc,
# is not checked here.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$ENGINE_DIR/skills/next/SKILL.md"
RESOLVER="$ENGINE_DIR/skills/next/assets/consent-mode.sh"

# The whole plain block, minus the reason= line (which names why the input was plain).
PLAIN_BLOCK='mode=plain
consent=asked
step.resume=in-consent
step.decide=own-confirm
step.snapshot=own-confirm
step.groom=own-confirm
step.sweep=own-confirm
step.inbox-next=not-reached-unless-asked
step.weave=loom-setting
halt.snapshot=declined
notice=none'

# feed <resolver> <exact stdin bytes> → the resolver's output, reason= line dropped
feed() {
  printf '%s' "$2" | bash "$1" 2>/dev/null | grep -v '^reason='
}

# kvin <resolver> <key> <exact stdin bytes> → the value printed for key
kvin() {
  printf '%s' "$3" | bash "$1" 2>/dev/null | sed -n "s/^$2=//p" | head -1
}

# Every input that is not exactly `all` (bare, or with the one newline a heredoc adds).
# ANSI-C quoting, so each entry is the exact byte string an operator could have typed.
PLAIN_INPUTS=(
  "" $'\n' "do everything" "the full run" "run everything" "myproject" "myproject all"
  "--session /tmp/all" "overall" "--all" "ALL" "All" "all-hands" "--minutes 30"
  "show me all blocking" "show me all" "a b all" "x y z all"
  "all," "all." "all!" "all?" "all*" "all;" "all # keep it safe" "all but don't commit"
  "all myproject" "all myproject --minutes 30" "all " $'all\n\n' $'all\r\n' $'all\t'
  " all" $'\tall' $'\nall' "  all"
  "'all'" '"all"' 'al\l' "\$(echo all)" "\`echo all\`" "-- all" "not all" '"" all'
)

# The plain-run arm, parameterised by resolver so the controls can point it at a planted copy.
# Each input is fed bare and with a trailing newline (the heredoc form), and the WHOLE output is
# compared to the plain block, so every step.* line is asserted. Echoes the failure count.
plain_failures() {
  local r="$1" n=0 a
  for a in "${PLAIN_INPUTS[@]}"; do
    [ "$(feed "$r" "$a")" = "$PLAIN_BLOCK" ] || n=$((n+1))
    [ "$(feed "$r" "$a"$'\n')" = "$PLAIN_BLOCK" ] || n=$((n+1))
  done
  echo "$n"
}

# skill_has <fixed string> <msg> — the skill file carries the string verbatim.
skill_has() {
  if grep -qF -- "$1" "$SKILL"; then pass "$2"; else fail "$2" "SKILL.md contains '$1'" "absent"; fi
}

# skill_lacks <fixed string> <msg>
skill_lacks() {
  if grep -qF -- "$1" "$SKILL"; then fail "$2" "SKILL.md lacks '$1'" "present"; else pass "$2"; fi
}

# section <start-regex> <end-regex> → the SKILL.md lines from the first start match up to (not
# including) the next end match.
section() {
  awk -v s="$1" -v e="$2" '$0 ~ s {on=1; print; next} on && $0 ~ e {exit} on {print}' "$SKILL"
}

# has_fixed <fixed string> <text> <msg> — a fixed-string match (no regex fallback, unlike
# assert_contains), so "plain run" cannot be satisfied by "explains".
has_fixed() {
  if printf '%s\n' "$2" | grep -qF -- "$1"; then pass "$3"; else fail "$3" "contains '$1'" "absent"; fi
}

# inv_line <name> → the invariant's bullet line in § Constraints
inv_line() {
  grep -m1 "^\*   \*\*\`¶$1\`\*\*" "$SKILL"
}

# ------------------------------------------------------------
test_resolver_exists() {
  assert_file_exists "$RESOLVER" "the waiver resolver skills/next/assets/consent-mode.sh exists"
}

# BEHAVIOUR — plain /next asks, for every input that is not exactly `all`.
test_plain_asks_for_every_other_input() {
  local n; n=$(plain_failures "$RESOLVER")
  assert_eq "0" "$n" "plain /next (${#PLAIN_INPUTS[@]} inputs x bare/heredoc: free text after all, quoting, punctuation, leading whitespace, all not sole) prints the whole plain block"
}

# BEHAVIOUR — the exact `all`, as the quoted heredoc delivers it, waives /next's own consent.
test_all_waives_consent() {
  local out
  out=$(bash "$RESOLVER" 2>/dev/null <<'NEXT_ARGS'
all
NEXT_ARGS
)
  assert_contains "consent=waived" "$out" "quoted heredoc 'all' → consent=waived"
  assert_eq "all" "$(kvin "$RESOLVER" mode "all")" "stdin 'all' (no newline) → mode=all"
  assert_eq "waived" "$(kvin "$RESOLVER" consent $'all\n')" "stdin 'all\\n' → consent=waived"
}

# BEHAVIOUR — the shell-quoted forms ride the heredoc verbatim and do not waive.
test_heredoc_keeps_quoting() {
  local out
  out=$(bash "$RESOLVER" 2>/dev/null <<'NEXT_ARGS'
'all'
NEXT_ARGS
)
  assert_contains "consent=asked" "$out" "quoted heredoc \"'all'\" → consent=asked (quotes are not stripped)"
  out=$(bash "$RESOLVER" 2>/dev/null <<'NEXT_ARGS'
all; echo pwned
NEXT_ARGS
)
  assert_contains "consent=asked" "$out" "quoted heredoc 'all; echo pwned' → consent=asked"
  assert_not_contains "pwned" "$out" "quoted heredoc: nothing after ';' executes"
}

# BEHAVIOUR — arguments on the command line never waive; the input is stdin only.
test_argv_never_waives() {
  assert_eq "asked" "$(bash "$RESOLVER" all </dev/null 2>/dev/null | sed -n 's/^consent=//p')" "argv 'all' → consent=asked"
  assert_eq "asked" "$(printf 'all' | bash "$RESOLVER" all 2>/dev/null | sed -n 's/^consent=//p')" "argv 'all' plus stdin 'all' → consent=asked"
  assert_eq "argv" "$(bash "$RESOLVER" all </dev/null 2>/dev/null | sed -n 's/^reason=//p')" "argv → reason=argv"
}

# BEHAVIOUR — NUL bytes are not dropped into a match.
test_nul_bytes_ask() {
  assert_eq "asked" "$(printf 'al\0l' | bash "$RESOLVER" 2>/dev/null | sed -n 's/^consent=//p')" "stdin 'al<NUL>l' → consent=asked"
  assert_eq "asked" "$(printf 'all\0' | bash "$RESOLVER" 2>/dev/null | sed -n 's/^consent=//p')" "stdin 'all<NUL>' → consent=asked"
}

# BEHAVIOUR — each composed step's invocation form under `all`.
test_all_step_forms() {
  assert_eq "--yes"        "$(kvin "$RESOLVER" step.snapshot all)"   "all: /snapshot runs in its waiver form --yes"
  assert_eq "waiver-owed"  "$(kvin "$RESOLVER" step.groom all)"      "all: /groom has no waiver → named owed, never skipped"
  assert_eq "decisions-asked+confirms-owed" "$(kvin "$RESOLVER" step.decide all)" "all: /decide's decisions are asked; its confirms are waiver-owed"
  assert_eq "dispatch"     "$(kvin "$RESOLVER" step.resume all)"     "all: a lane resume is /next's own dispatch, run unasked"
  assert_eq "not-reached"  "$(kvin "$RESOLVER" step.inbox-next all)" "all: the single pick is not reached"
  assert_eq "nothing-to-waive" "$(kvin "$RESOLVER" step.sweep all)"  "all: /sweep holds no confirm of its own"
  assert_eq "loom-setting" "$(kvin "$RESOLVER" step.weave all)"      "all: the weave /groom dispatches into is governed by its loom's setting"
  assert_eq "commit-not-done" "$(kvin "$RESOLVER" halt.snapshot all)" "all: any /snapshot --yes commit outcome but done (skipped, failed, aborted) ends the run"
}

# BEHAVIOUR — the notice template has every slot, including the stop and the declined actions.
test_all_notice_template() {
  local t; t=$(kvin "$RESOLVER" notice all)
  has_fixed "all: ran unconfirmed —" "$t" "notice: opens 'all: ran unconfirmed —'"
  has_fixed "resumed unasked —" "$t" "notice: slot for the unasked resume"
  has_fixed "snapshot declined —" "$t" "notice: slot for /snapshot's declined actions"
  has_fixed "posted anyway —" "$t" "notice: slot for what /snapshot posted anyway"
  has_fixed "commit failed" "$t" "notice: names a failed commit (e.g. branch creation on main)"
  has_fixed "waiver owed —" "$t" "notice: slot for owed waivers"
  has_fixed "the weave" "$t" "notice: the weave is named among the owed"
  has_fixed "/decide's confirms" "$t" "notice: /decide's confirms are named owed"
  has_fixed "still asked (decisions) —" "$t" "notice: slot for the decisions still asked"
  has_fixed "stopped at —" "$t" "notice: slot for where the run stopped"
}

# BEHAVIOUR — plain keeps every step under its own confirm and the one consent (no stdin).
test_plain_step_forms() {
  assert_eq "$PLAIN_BLOCK" "$(bash "$RESOLVER" </dev/null 2>/dev/null | grep -v '^reason=')" "plain (empty stdin): the whole plain block, incl. step.sweep and step.inbox-next"
  assert_eq "own-confirm" "$(kvin "$RESOLVER" step.sweep "")" "plain: /sweep keeps its own confirm"
  assert_eq "not-reached-unless-asked" "$(kvin "$RESOLVER" step.inbox-next "")" "plain: the single pick is reached only from an ask for one item"
}

# plant <sed-expr> → path of a planted copy of the resolver, or empty when sed matched nothing
plant() {
  local tmp; tmp=$(mktemp)
  sed "$1" "$RESOLVER" > "$tmp"
  if cmp -s "$RESOLVER" "$tmp"; then rm -f "$tmp"; echo ""; else echo "$tmp"; fi
}

# CONTROL 1 — plant "plain /next waives" into a copy of the resolver; the plain arm must go red.
test_control_plain_waive_goes_red() {
  local tmp n
  tmp=$(plant 's/^MODE=plain$/MODE=all/')
  if [ -z "$tmp" ]; then
    fail "control 1: the defect plants (resolver carries a MODE=plain default line)" "a changed copy" "sed matched nothing"; return
  fi
  n=$(plain_failures "$tmp"); rm -f "$tmp"
  assert_gt "$n" "0" "control 1: with 'plain waives' planted, the plain-run arm reports failures ($n)"
}

# CONTROL 2 — plant punctuation tolerance (`all,` `all.` `all!` waive); the plain arm must go red.
test_control_punctuation_goes_red() {
  local tmp n
  tmp=$(plant 's/^  616c6c|616c6c0a)/  616c6c|616c6c0a|616c6c2c|616c6c2e|616c6c21)/')
  if [ -z "$tmp" ]; then
    fail "control 2: the defect plants (resolver carries the exact-bytes case arm)" "a changed copy" "sed matched nothing"; return
  fi
  n=$(plain_failures "$tmp"); rm -f "$tmp"
  assert_gt "$n" "0" "control 2: with punctuation tolerance planted, the plain-run arm reports failures ($n)"
}

# TEXT — the waiver flag cited for /snapshot is one /snapshot defines; /groom and /decide have none.
test_waiver_citations_resolve() {
  if grep -E '^args:' "$ENGINE_DIR/skills/snapshot/SKILL.md" | grep -q -- '--yes'; then
    pass "/snapshot's args line defines --yes (the waiver /next all passes)"
  else
    fail "/snapshot's args line defines --yes" "--yes in args:" "absent"
  fi
  local g d
  g=$(grep -E '^args:' "$ENGINE_DIR/skills/groom/SKILL.md" | grep -oE -- '--(yes|silent|no-confirm)' || true)
  assert_empty "$g" "drift sensor: /groom still has no waiver flag (if this fails, wire it in consent-mode.sh and drop 'waiver-owed')"
  d=$(grep -E '^args:' "$ENGINE_DIR/skills/decide/SKILL.md" | grep -oE -- '--(yes|silent|no-confirm)' || true)
  assert_empty "$d" "drift sensor: /decide still has no waiver flag (if this fails, wire it and drop 'confirms-owed')"
}

# TEXT — the description: plain-scoped confirm sentence, the exact-word rule, no bare "all" trigger.
test_description_amended() {
  local d; d=$(grep -m1 '^description:' "$SKILL")
  assert_not_contains "which \`all\` never bypasses" "$d" "description drops 'which \`all\` never bypasses'"
  has_fixed "\`/next all\` waives" "$d" "description states that \`/next all\` waives"
  has_fixed "plain \`/next\`" "$d" "description states a plain \`/next\` still asks"
  has_fixed "in a plain run each step's write still passes its own skill's confirm" "$d" "description scopes the per-step confirm to the plain run"
  assert_not_contains '\"next all\", \"all\",' "$d" "description drops the bare \"all\" trigger"
  has_fixed "nothing after it" "$d" "description says only an exact \`/next all\` with nothing after it waives"
}

# TEXT — both IDE-154 invariants carry the `all` exception, quoting the operator, plain kept.
test_invariants_carry_exception() {
  local inv line
  for inv in INV_NEXT_PROPOSES_NEVER_DECIDES INV_NEXT_ONE_CONSENT_PER_RUN; do
    line=$(inv_line "$inv")
    has_fixed "IDE-236" "$line" "¶$inv names IDE-236"
    has_fixed "Waive every confirm" "$line" "¶$inv quotes the operator's ruling"
    has_fixed "plain run" "$line" "¶$inv keeps the plain run as written"
  done
}

# TEXT — M3: every unconditional plain-run sentence is scoped.
test_plain_sentences_scoped() {
  local line
  line=$(inv_line INV_NEXT_MAXIMAL_BY_DEFAULT)
  has_fixed "In a plain run, writing anything before the one question is answered is forbidden" "$line" "¶INV_NEXT_MAXIMAL_BY_DEFAULT scopes 'writing anything before the question' to the plain run"
  line=$(inv_line INV_NEXT_ESCALATES_WHAT_IT_CANNOT_ROUTE)
  has_fixed "in a plain run" "$line" "¶INV_NEXT_ESCALATES_WHAT_IT_CANNOT_ROUTE scopes the promotion to the plain run"
  has_fixed "\`all\`" "$line" "¶INV_NEXT_ESCALATES_WHAT_IT_CANNOT_ROUTE says what \`all\` does instead"
  line=$(inv_line INV_NEXT_MINTS_NO_LANES)
  has_fixed "\`all\`" "$line" "¶INV_NEXT_MINTS_NO_LANES says which resumes an \`all\` run may dispatch"
  line=$(inv_line INV_NEXT_ONE_CONSENT_PER_RUN)
  has_fixed "in a plain run a step whose skill holds no confirm" "$line" "¶INV_NEXT_ONE_CONSENT_PER_RUN scopes the own-question rule to the plain run"
  skill_has "**In a plain run, a step whose routed skill holds NO confirm of its own may not ride a sequence accept**" "step 5 scopes the no-confirm own-question rule to the plain run"
  skill_has "and, in a plain run, every write still passes its own skill's confirm" "step 6 scopes 'every write passes its own confirm' to the plain run"
}

# TEXT — M1: the word-only invariant names the exact rule and the heredoc.
test_word_only_invariant() {
  local line; line=$(inv_line INV_NEXT_ALL_IS_THE_WORD_ONLY)
  has_fixed "exact \`/next all\`" "$line" "¶INV_NEXT_ALL_IS_THE_WORD_ONLY names the exact \`/next all\`"
  has_fixed "nothing after it" "$line" "¶INV_NEXT_ALL_IS_THE_WORD_ONLY: nothing after it"
  has_fixed "quoted heredoc" "$line" "¶INV_NEXT_ALL_IS_THE_WORD_ONLY: the text reaches the resolver on a quoted heredoc"
  has_fixed "leading whitespace" "$line" "¶INV_NEXT_ALL_IS_THE_WORD_ONLY: leading whitespace asks"
  skill_has "<<'NEXT_ARGS'" "SKILL.md gives the quoted-heredoc invocation"
  skill_has "assets/consent-mode.sh" "SKILL.md tells the agent to run the resolver"
}

# TEXT — M2 + S7: a skipped commit or an aborted /snapshot --yes ends an `all` run.
test_snapshot_halt_ends_all_run() {
  local s6; s6=$(section '^### 6\. ' '^### 7\. ')
  has_fixed "a checkpoint whose commit was skipped, or that aborted, ends the sequence" "$s6" "step 6: a skipped commit or an aborted /snapshot --yes ends an \`all\` run"
  has_fixed "a failed commit included" "$s6" "step 6: a failed commit also ends an \`all\` run (NS2)"
  skill_has "aborts on a low-confidence or ambiguous target ticket, and that abort ends the run" "§ /next all states /snapshot --yes aborts on a low-confidence ticket and that ends the run"
}

# TEXT — S3: the notice is required in step 7 and on every stop path in step 6.
test_notice_on_every_exit() {
  local s7 s6
  s7=$(section '^### 7\. ' '^## Constraints')
  has_fixed "all: ran unconfirmed —" "$s7" "step 7 requires the notice line"
  has_fixed "on every exit of an \`all\` run" "$s7" "step 7 requires the notice on every exit, a stop included"
  s6=$(section '^### 6\. ' '^### 7\. ')
  has_fixed "print the \`all:\` notice" "$s6" "step 6's stop paths require the notice"
}

# TEXT — S4/S5/S6: /decide owed, floor scoped to what /next detects, the loom's five kept items.
test_conflict_and_floor() {
  skill_has "waiver-owed to \`/decide\`'s owner" "/decide's confirms are named owed, not unwaivable"
  skill_lacks "step.decide=not-waivable" "the old 'not-waivable' step form is gone"
  skill_has "inside the weave \`/groom\` dispatches into" "the floor says the loom's floor items fire inside the weave"
  skill_has "scrutiny card" "the conflict names the scrutiny card"
  skill_has "wave boundary's merge" "the conflict names the wave boundary's merge"
  skill_has "hard escalation floor" "the conflict names the hard escalation floor"
  skill_has "a composed skill's own confirm" "the conflict names a composed skill's own confirm"
  skill_has "\`all\` stops at the weave" "the conflict says \`all\` stops at the weave /groom dispatches into"
}

# TEXT — M4 + S1: hook (a) reads unread answers by readAt, folds with engine ask read, and
# reports a missing store or an empty seat as unreadable.
test_ask_hook_wired() {
  skill_has "engine ask list --status open --to" "reads open asks addressed to the seat"
  skill_has "engine ask list --status all --seat" "reads every ask of the seat, declined included"
  skill_has "header.readAt" "unread is read by readAt"
  skill_has "engine ask read" "the fold stamps the answer with engine ask read"
  skill_lacks "engine ask list --status answered --seat" "the delivery-based answered-only reading is gone"
  skill_has "cannot read asks" "a missing store or empty seat is reported as cannot read asks"
  skill_has '[ -n "${FLEET_PANE:-}" ]' "an empty FLEET_PANE is unreadable, never all seats"
  skill_has '[ -d "$(engine ask path)" ]' "a missing ASK_ROOT is unreadable, never no asks"
}

# BEHAVIOUR — NS1 (§PTF_BLOCKING_CAT_ON_STDIN): stdin held open never blocks the resolver.
test_held_open_stdin_does_not_block() {
  local TIMEFORMAT=%R t out
  t=$( { time bash "$RESOLVER" < <(sleep 5) > "${TMPDIR:-/tmp}/next-all-held.$$" 2>/dev/null; } 2>&1 )
  out=$(cat "${TMPDIR:-/tmp}/next-all-held.$$"); rm -f "${TMPDIR:-/tmp}/next-all-held.$$"
  if awk -v t="$t" 'BEGIN { exit !(t < 2) }'; then
    pass "stdin held open (< <(sleep 5)) returns in under 2 s (${t}s)"
  else
    fail "stdin held open (< <(sleep 5)) returns in under 2 s" "< 2" "${t}s"
  fi
  assert_contains "consent=asked" "$out" "stdin held open → consent=asked"
  assert_contains "reason=stdin-held-open" "$out" "stdin held open → reason=stdin-held-open"
  assert_eq "no-stdin" "$(bash "$RESOLVER" </dev/null 2>/dev/null | sed -n 's/^reason=//p')" "stdin neither file nor pipe (/dev/null) → reason=no-stdin, no read"
}

# TEXT — NS3/Q1: the call the agent copies, inside § /next all's code block, is QUOTED.
test_skill_code_block_heredoc_quoted() {
  local blk
  blk=$(section '^## `/next all`' '^## Algorithm' | awk '/^```/ {f=!f; next} f')
  has_fixed "consent-mode.sh <<'NEXT_ARGS'" "$blk" "§ /next all's code block calls the resolver with the quoted <<'NEXT_ARGS'"
}

# TEXT — NS3/Q2: § /next all itself keeps the halt wording (not only step 6).
test_all_section_keeps_halt() {
  local sec
  sec=$(section '^## `/next all`' '^## Algorithm')
  has_fixed "goes on neither to \`/groom\` nor to any new work" "$sec" "§ /next all: a checkpoint that did not land goes on neither to /groom nor to new work"
  has_fixed "**failed**" "$sec" "§ /next all names a failed commit as a halt (NS2)"
  assert_not_contains "goes on to \`/groom\`" "$sec" "§ /next all never says the run goes on to /groom after a checkpoint that did not land"
}

# TEXT — the per-id fold is kept; the bulk --unread form drops unstamped answers.
test_ask_fold_per_id() {
  skill_has "Fold **one id at a time**, never with \`engine ask read --unread\`" "rung 2 folds one id at a time, never with read --unread"
}

run_discovered_tests
