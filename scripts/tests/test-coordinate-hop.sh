#!/bin/bash
# test-coordinate-hop.sh — Tests for skills/coordinate/scripts/hop.sh, its configs and the
# protocol text that depends on them. All against fixtures (no live tmux, no live fleet).
#
#   target   — the live @pane_parent decides; FLEET_PARENT only cross-checks; broken config,
#              missing identity and a wrong edge fail loudly; a dead rung is skipped one level
#              up via the chain record (exit 3, target still printed).
#   may-rule — required --class/--floor/--raised-by/--config; uppercase classes only; own
#              fork, floor, reserved E–H and the installed grant v1 (A–D).
#   ask-id / rowed — dedupe a blocked worker that await-next re-emits.
#   configs  — grant v1 installed; the 4 git clauses verbatim; no timer keys; the preset's
#              keys each have a reader.
#
# Plant a defect: HOP_SH=<mutated copy> bash test-coordinate-hop.sh — it must go red.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SKILL_DIR="${COORD_SKILL_DIR:-$HOME/.claude/engine/skills/coordinate}"
HOP_SH="${HOP_SH:-$SKILL_DIR/scripts/hop.sh}"
PROPOSAL="$HOME/Projects/kit/sessions/2026_10_14_LAND_TREE_BRANCHES/builds/AUTHORITY_GRANT_PROPOSAL.md"

# assert_has — like assert_contains, but with no pipe. test-helpers' assert_has runs
# `echo "$big" | grep -q`; under `set -o pipefail` grep -q exits on the first match, echo takes
# SIGPIPE, and the pipeline reports 141 — a FAIL on a string that is present. Measured: 3 of 9
# planted runs failed text assertions on untouched files that way.
assert_has() {
  local pattern="$1" actual="$2" msg="$3"
  if grep -qF -- "$pattern" <<<"$actual"; then pass "$msg"; else fail "$msg" "contains '$pattern'" "(${#actual} chars)"; fi
}

FIX=""

setup() {
  FIX="$(mktemp -d)"
  cat > "$FIX/live.txt" <<'EOF'
manager:director %114 -
manager:idealic %121 manager:director
manager:domain %134 manager:director
idealic:kernel %3 manager:idealic
domain:orphan %40 manager:ghost
loop:self %50 loop:self
odd:seat %51 operator
EOF
  # The chain recorded at Setup still knows the dead rung's own parent.
  printf 'manager:ghost %%99 manager:director\n' > "$FIX/chain.txt"
  printf '{"grant":{"classes":[]}}\n' > "$FIX/empty-grant.json"
  printf '{"grant":{"classes":["A","H","E","e"]}}\n' > "$FIX/marked-grant.json"
  printf '{"grant":' > "$FIX/broken.json"
  printf '{"hop":{"parentFrom":"FLEET_PANE"},"grant":{"classes":[]}}\n' > "$FIX/parentfrom.json"
}

teardown() { rm -rf "$FIX"; }

# Run hop.sh with a clean fleet env; leading NAME=VALUE words are extra env.
hop() { env -u FLEET_PARENT -u FLEET_PANE -u HOP_CHAIN_FILE -u TMUX_PANE HOP_LIVE_PANES="$FIX/live.txt" "$@"; }

# run_hop <env and args…> → "rc|stdout" (stderr dropped)
run_hop() {
  local out rc
  out=$(hop "$@" 2>/dev/null); rc=$?
  echo "$rc|$out"
}

test_hop_script_exists() {
  assert_file_exists "$HOP_SH" "hop.sh exists (so the empty-stdout checks below are not vacuous)"
}

# ---------------------------------------------------------------- target: the edge

test_target_top_seat_goes_to_operator() {
  assert_eq "0|operator" "$(run_hop FLEET_PANE=manager:director bash "$HOP_SH" target)" \
    "target: a seat with no live @pane_parent → operator"
}

test_target_live_parent_with_matching_env() {
  assert_eq "0|manager:director %114" \
    "$(run_hop FLEET_PANE=manager:idealic FLEET_PARENT=manager:director bash "$HOP_SH" target)" \
    "target: live parent, FLEET_PARENT agrees → the parent's pane"
}

test_target_unset_env_on_parented_seat_refuses() {
  local err
  assert_eq "5|" "$(run_hop FLEET_PANE=manager:idealic bash "$HOP_SH" target)" \
    "target: FLEET_PARENT unset but live @pane_parent set → exit 5, no target (M1)"
  err=$(hop FLEET_PANE=manager:idealic bash "$HOP_SH" target 2>&1 >/dev/null)
  assert_has "refusing to fall back" "$err" "target: says why it refused"
}

test_target_env_disagreeing_with_live_refuses() {
  assert_eq "5|" "$(run_hop FLEET_PANE=manager:idealic FLEET_PARENT=manager:domain bash "$HOP_SH" target)" \
    "target: FLEET_PARENT disagrees with the live edge → exit 5"
}

test_target_parent_is_self_or_operator_refuses() {
  assert_eq "5|" "$(run_hop FLEET_PANE=loop:self FLEET_PARENT=loop:self bash "$HOP_SH" target)" \
    "target: a parent equal to this seat → exit 5"
  assert_eq "5|" "$(run_hop FLEET_PANE=odd:seat FLEET_PARENT=operator bash "$HOP_SH" target)" \
    "target: a parent literally named operator → exit 5"
}

test_target_without_identity_refuses() {
  assert_eq "2|" "$(run_hop FLEET_PARENT=manager:director bash "$HOP_SH" target)" \
    "target: no FLEET_PANE and no --self → exit 2, never operator"
}

test_target_seat_not_in_tree_refuses() {
  assert_eq "5|" "$(run_hop FLEET_PANE=nowhere:seat bash "$HOP_SH" target)" \
    "target: this seat not in the live tree → exit 5"
}

# ---------------------------------------------------------------- target: config (M1)

test_target_broken_config_fails_loudly() {
  assert_eq "2|" "$(run_hop FLEET_PANE=manager:idealic FLEET_PARENT=manager:director bash "$HOP_SH" target --config "$FIX/broken.json")" \
    "target: unparseable config → exit 2, no target"
  assert_eq "2|" "$(run_hop FLEET_PANE=manager:idealic FLEET_PARENT=manager:director bash "$HOP_SH" target --config "$FIX/nope.json")" \
    "target: missing config → exit 2, no target"
}

test_target_parentfrom_cannot_redirect() {
  assert_eq "2|" "$(run_hop FLEET_PANE=manager:idealic FLEET_PARENT=manager:director bash "$HOP_SH" target --config "$FIX/parentfrom.json")" \
    "target: hop.parentFrom other than FLEET_PARENT → exit 2"
}

test_target_with_shipped_configs() {
  local f
  for f in coordinate.config.example.json coordinate.manager.config.json; do
    assert_eq "0|manager:director %114" \
      "$(run_hop FLEET_PANE=manager:idealic FLEET_PARENT=manager:director bash "$HOP_SH" target --config "$SKILL_DIR/assets/$f")" \
      "target: $f resolves the parent"
  done
}

# ---------------------------------------------------------------- target: dead rungs (M2)

test_target_dead_parent_skips_up_via_chain() {
  local err
  assert_eq "3|manager:director %114" \
    "$(run_hop FLEET_PANE=domain:orphan FLEET_PARENT=manager:ghost bash "$HOP_SH" target --chain-file "$FIX/chain.txt")" \
    "target: dead parent → its recorded parent, exit 3"
  err=$(hop FLEET_PANE=domain:orphan FLEET_PARENT=manager:ghost bash "$HOP_SH" target --chain-file "$FIX/chain.txt" 2>&1 >/dev/null)
  assert_has "no live pane" "$err" "target: the skipped rung is named on stderr"
}

test_target_dead_top_goes_to_operator_with_reason() {
  local err
  assert_eq "3|operator" "$(run_hop FLEET_PANE=domain:orphan FLEET_PARENT=manager:ghost bash "$HOP_SH" target)" \
    "target: dead parent with no chain record → operator, exit 3"
  err=$(hop FLEET_PANE=domain:orphan FLEET_PARENT=manager:ghost bash "$HOP_SH" target 2>&1 >/dev/null)
  assert_has "dead top" "$err" "target: the reason is on stderr"
}

test_target_unreadable_tree_fails_loudly() {
  assert_eq "4|" "$(run_hop FLEET_PANE=manager:idealic FLEET_PARENT=manager:director HOP_LIVE_PANES="$FIX/missing.txt" bash "$HOP_SH" target)" \
    "target: unreadable live tree → exit 4, no target"
}

# A seat renamed after launch: run.sh cached FLEET_PANE=domain:domain, the live label reads
# domain:stats. The live label must win, with a stale warning. tmux is a PATH stub here (the
# hop() seam sets HOP_LIVE_PANES, which turns the live-label read off), so no server is touched.
live_label_hop() { # live_label_hop <env and args…> — hop.sh against the stub tmux, pane %60
  mkdir -p "$FIX/bin"
  cat > "$FIX/bin/tmux" <<EOF
#!/bin/bash
case "\$1" in
  display) [ "\$4" = "%60" ] && echo "domain:stats" ;;
  list-panes) cat "$FIX/live.txt"; echo "domain:stats %60 manager:domain" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FIX/bin/tmux"
  env -u FLEET_PARENT -u FLEET_PANE -u HOP_CHAIN_FILE -u HOP_LIVE_PANES -u HOP_TMUX_SOCKET \
    PATH="$FIX/bin:$PATH" TMUX_PANE=%60 "$@"
}

test_target_live_label_beats_a_stale_fleet_pane() {
  local out rc err
  out=$(live_label_hop FLEET_PANE=domain:domain FLEET_PARENT=manager:domain bash "$HOP_SH" target 2>/dev/null); rc=$?
  assert_eq "0|manager:domain %134" "$rc|$out" "target: stale FLEET_PANE, live label domain:stats → its live parent"
  err=$(live_label_hop FLEET_PANE=domain:domain FLEET_PARENT=manager:domain bash "$HOP_SH" target 2>&1 >/dev/null)
  assert_has "FLEET_PANE 'domain:domain' is stale; using the live pane label 'domain:stats'" "$err" \
    "target: a stale FLEET_PANE is named on stderr"
  err=$(live_label_hop FLEET_PANE=domain:stats FLEET_PARENT=manager:domain bash "$HOP_SH" target 2>&1 >/dev/null)
  assert_eq "" "$err" "target: a FLEET_PANE that matches the live label warns nothing"
}

test_target_of_walks_one_level_up() {
  assert_eq "0|manager:director %114" "$(run_hop bash "$HOP_SH" target --of manager:idealic)" "target --of manager:idealic → director"
  assert_eq "0|operator" "$(run_hop bash "$HOP_SH" target --of manager:director)" "target --of the director → operator"
  assert_eq "3|manager:director %114" "$(run_hop bash "$HOP_SH" target --of manager:ghost --chain-file "$FIX/chain.txt")" \
    "target --of a dead seat → its recorded parent, exit 3"
  assert_eq "3|operator" "$(run_hop bash "$HOP_SH" target --of manager:nobody)" \
    "target --of an unknown seat → operator, exit 3"
}

test_chain_records_ancestry() {
  local out
  out=$(hop FLEET_PANE=idealic:kernel bash "$HOP_SH" chain 2>/dev/null)
  assert_eq "idealic:kernel %3 manager:idealic
manager:idealic %121 manager:director
manager:director %114 -" "$out" "chain: kernel → idealic → director → top"
}

# ---------------------------------------------------------------- may-rule

may() { # may <args…> → "rc|stdout lines joined by ' / '"
  local out rc
  out=$(hop FLEET_PANE=manager:idealic bash "$HOP_SH" may-rule "$@" 2>/dev/null); rc=$?
  echo "$rc|$(printf '%s' "$out" | awk 'NR>1{printf " / "} {printf "%s", $0}')"
}
v1() { echo "$SKILL_DIR/assets/coordinate.manager.config.json"; }

test_may_rule_requires_every_argument() {
  local c; c=$(v1)
  assert_eq "2|" "$(may --floor none --raised-by idealic:kernel --config "$c")" "may-rule: no --class → exit 2"
  assert_eq "2|" "$(may --class A --raised-by idealic:kernel --config "$c")" "may-rule: no --floor → exit 2 (M5)"
  assert_eq "2|" "$(may --class A --floor none --config "$c")" "may-rule: no --raised-by → exit 2 (S1)"
  assert_eq "2|" "$(may --class A --floor none --raised-by idealic:kernel)" "may-rule: no --config → exit 2"
  assert_eq "2|" "$(may --class A --floor none --raised-by idealic:kernel --config "$FIX/broken.json")" "may-rule: broken config → exit 2"
}

test_may_rule_refuses_lowercase_and_unknown_classes() {
  assert_eq "2|" "$(may --class e --floor none --raised-by idealic:kernel --config "$FIX/marked-grant.json")" \
    "may-rule: lowercase e → exit 2, even when the config lists 'e'"
  assert_eq "2|" "$(may --class Z --floor none --raised-by idealic:kernel --config "$(v1)")" "may-rule: class Z → exit 2"
  assert_eq "2|" "$(may --class A --floor made-up --raised-by idealic:kernel --config "$(v1)")" "may-rule: unknown floor item → exit 2"
}

test_may_rule_grant_v1() {
  local c k; c=$(v1)
  for k in A B C D; do
    assert_eq "0|rule" "$(may --class "$k" --floor none --raised-by idealic:kernel --config "$c")" "may-rule v1: $k is delegated"
  done
  assert_eq "0|rule" "$(may --class orientation --floor none --raised-by idealic:kernel --config "$c")" "may-rule v1: orientation is the seat's"
  assert_eq "1|pass-up: class A is not in the installed grant" \
    "$(may --class A --floor none --raised-by idealic:kernel --config "$FIX/empty-grant.json")" "may-rule: A with an empty grant passes up"
}

test_may_rule_reserved_classes_carry_the_mark() {
  local k
  for k in E F G; do
    assert_eq "1|pass-up: reserved class $k — never a manager's ruling, recommendation attached / reserved-for: operator" \
      "$(may --class "$k" --floor none --raised-by idealic:kernel --config "$FIX/marked-grant.json")" \
      "may-rule: $k passes up marked reserved-for operator, even when the config lists it"
  done
  assert_eq "1|pass-up: class H is reserved until the operator marks it / reserved-for: operator" \
    "$(may --class H --floor none --raised-by idealic:kernel --config "$(v1)")" "may-rule v1: H stays reserved, marked"
  assert_eq "0|rule" "$(may --class H --floor none --raised-by idealic:kernel --config "$FIX/marked-grant.json")" \
    "may-rule: H once marked may be ruled"
}

test_may_rule_floor_beats_every_class() {
  local f k
  for f in cyclic-deadlock build-fails-after-retries blocking-critique thread-loopback; do
    for k in orientation A; do
      assert_eq "1|pass-up: IDE-135 floor ($f) — the operator's, recommendation attached / reserved-for: operator" \
        "$(may --class "$k" --floor "$f" --raised-by idealic:kernel --config "$(v1)")" "may-rule: floor $f with class $k passes up, marked"
    done
  done
}

test_may_rule_forwards_an_ask_marked_for_the_operator() {
  assert_eq "1|pass-up: marked reserved-for operator upstream — forward only, never rule / reserved-for: operator" \
    "$(may --class orientation --floor none --raised-by idealic:kernel --reserved-for operator --config "$(v1)")" \
    "may-rule: an incoming reserved-for: operator ask is forwarded, never ruled (M4)"
}

test_may_rule_never_answers_its_own() {
  local c out rc; c=$(v1)
  assert_eq "1|pass-up: own fork — manager:idealic raised this question itself" \
    "$(may --class orientation --floor none --raised-by manager:idealic --config "$c")" "may-rule: own fork by label passes up"
  assert_eq "1|pass-up: own fork — manager:idealic raised this question itself" \
    "$(may --class A --floor none --raised-by %121 --config "$c")" "may-rule: own fork by pane id passes up (S1)"
  out=$(hop bash "$HOP_SH" may-rule --class A --floor none --raised-by manager:idealic --config "$c" 2>/dev/null); rc=$?
  assert_eq "2|" "$rc|$out" "may-rule: no identity for this seat → exit 2, not a ruling (S1)"
}

test_own_fork_on_floor_or_reserved_still_carries_the_mark() {
  # R1: the mark is decided before own-fork.
  local c; c=$(v1)
  assert_eq "1|pass-up: IDE-135 floor (cyclic-deadlock) — the operator's, recommendation attached (and own fork — manager:idealic raised it) / reserved-for: operator" \
    "$(may --class orientation --floor cyclic-deadlock --raised-by manager:idealic --config "$c")" \
    "may-rule: own fork on a floor item → marked reserved-for operator (R1)"
  assert_eq "1|pass-up: reserved class E — never a manager's ruling, recommendation attached (and own fork — manager:idealic raised it) / reserved-for: operator" \
    "$(may --class E --floor none --raised-by manager:idealic --config "$c")" \
    "may-rule: own fork on class E → marked reserved-for operator (R1)"
}

# ---------------------------------------------------------------- inbox (R2)

make_asks() { # make_asks <root>
  mkdir -p "$1/manager:idealic" "$1/manager:domain" "$1/idealic:kernel"
  printf -- '---\nid: q1\nto: manager:director\nfrom: manager:idealic\nstatus: open\nrevision: 1\nreserved-for: operator\n---\n## Choose one: Push the branch?\n- [ ] [YES] Yes\n- [ ] [NO] No\n' > "$1/manager:idealic/q1.md"
  printf -- '---\nid: q2\nto: manager:director\nfrom: manager:domain\nstatus: open\nrevision: 1\n---\n## Choose one: Which dir?\n- [ ] [AAA] a\n- [ ] [BBB] b\n' > "$1/manager:domain/q2.md"
  printf -- '---\nid: q3\nto: manager:director\nfrom: manager:domain\nstatus: answered\nrevision: 1\n---\n## Choose one: Old?\n- [ ] [AAA] a\n' > "$1/manager:domain/q3.md"
  printf -- '---\nid: q4\nto: manager:idealic\nfrom: idealic:kernel\nstatus: open\nrevision: 1\n---\n## Choose one: Mine?\n- [ ] [AAA] a\n' > "$1/idealic:kernel/q4.md"
}

inbox_ids() { awk -F'\t' '{print $1 "|" $3}' | sort | paste -sd' ' -; }

test_inbox_fallback_reads_headers() {
  make_asks "$FIX/asks"
  assert_eq "manager:domain/q2|- manager:idealic/q1|reserved-for:operator" \
    "$(hop FLEET_PANE=manager:director HOP_ASK_CLI=none ASK_ROOT="$FIX/asks" bash "$HOP_SH" inbox 2>/dev/null | inbox_ids)" \
    "inbox (headers): the director sees its two open asks, with the mark; not the answered one, not idealic's"
  assert_eq "idealic:kernel/q4|-" \
    "$(hop FLEET_PANE=manager:idealic HOP_ASK_CLI=none ASK_ROOT="$FIX/asks" bash "$HOP_SH" inbox 2>/dev/null | inbox_ids)" \
    "inbox (headers): idealic sees only the ask addressed to it"
}

test_inbox_via_ask_cli() {
  make_asks "$FIX/asks"
  if ! ASK_ROOT="$FIX/asks" engine ask list --status open --to manager:director >/dev/null 2>&1; then
    skip "inbox via the ask CLI" "engine ask list unavailable"; return
  fi
  assert_eq "manager:domain/q2|- manager:idealic/q1|reserved-for:operator" \
    "$(hop FLEET_PANE=manager:director ASK_ROOT="$FIX/asks" bash "$HOP_SH" inbox 2>/dev/null | inbox_ids)" \
    "inbox (engine ask list --to): the director receives idealic's pass-up (acceptance 1, receiving half)"
}

test_inbox_without_any_source_fails_loudly() {
  assert_eq "2|" "$(run_hop FLEET_PANE=manager:director HOP_ASK_CLI=none ASK_ROOT="$FIX/no-such" bash "$HOP_SH" inbox)" \
    "inbox: no CLI and no ask root → exit 2"
}

# ---------------------------------------------------------------- panes (M3 residual)

test_panes_excludes_passed_up_and_unanswered() {
  cat > "$FIX/reg.md" <<'EOF'
## 🪜 Escalations (live)
| direction | seat (from-name · pane id) | the topic | member links | sent | ack | disposition |
|-----------|----------------------------|-----------|--------------|------|-----|-------------|
| received | idealic:kernel · %3 | Push? | ask:hop-3-aaaa | 22:10 · delivered | open | passed up |
| sent | manager:director · %114 | Push? | ask:hop-3-aaaa · /a.md | 22:11 · delivered | open — waiting | passed up |
| received | idealic:ops · %22 | Q2 | ask:hop-22-bbbb | 22:12 · delivered | taken | passed up |
| sent | manager:director · %114 | Q2 | ask:hop-22-bbbb | 22:12 · delivered | taken — answer A | passed up |
| received | idealic:ui · %23 | Q3 | ask:hop-23-cccc | 22:13 | open | answered |
| `received` | `idealic:exchange` · `%19` | Template-format row | `ask:hop-19-eeee` | 22:14 · delivered | open | `passed up` |
| `sent` | `manager:director` · `%114` | Template-format row | `ask:hop-19-eeee` · /e.md | 22:14 · delivered | open — waiting | passed up |
| received | idealic:realm · %20 | reserved-for: operator Floor item | ask:hop-20-ffff | 22:15 · delivered | open | passed up |
| sent | manager:director · %114 | reserved-for: operator Floor item | ask:hop-20-ffff | 22:15 · delivered | declined — not the operator's answer | passed up |

## 👁️ Observation
| received | idealic:runner · %21 | x | ask:hop-21-dddd | - | open | passed up |
EOF
  assert_eq "0|runner,ops,ui" \
    "$(run_hop bash "$HOP_SH" panes --log "$FIX/reg.md" --manages kernel,exchange,realm,runner,ops,ui)" \
    "panes: kernel held; exchange held from a template-format row (RR1); realm held after a non-operator decline (RR2); ops (taken) comes back; ui (ruled) stays; rows outside the register ignored"
  assert_eq "0|ops" "$(run_hop bash "$HOP_SH" panes --log "$FIX/reg.md" --manages kernel,ops,%19,%20)" \
    "panes: held panes are matched by pane id too (%19 template-format, %20 declined); only ops (taken) is swept"
  assert_eq "0|-" "$(run_hop bash "$HOP_SH" panes --log "$FIX/reg.md" --manages kernel)" \
    "panes: every pane held → '-' (an empty --panes would mean all of FLEET_MANAGES)"
  assert_eq "0|kernel,ops" "$(run_hop bash "$HOP_SH" panes --log "$FIX/none.md" --manages kernel,ops)" \
    "panes: no log yet → every managed pane"
  assert_eq "2|" "$(run_hop bash "$HOP_SH" panes --log "$FIX/reg.md")" "panes: no managed panes → exit 2"
}

# ---------------------------------------------------------------- dedupe (M3)

test_ask_id_is_stable_for_a_reemitted_question() {
  local a b c
  a=$(bash "$HOP_SH" ask-id --pane %3 --question "Push the branch?")
  b=$(bash "$HOP_SH" ask-id --pane %3 --question "  Push   the branch? ")
  c=$(bash "$HOP_SH" ask-id --pane %3 --question "Delete the branch?")
  assert_not_empty "$a" "ask-id: prints an id"
  assert_eq "$a" "$b" "ask-id: the same question re-emitted (whitespace aside) → the same id"
  assert_neq "$a" "$c" "ask-id: a different question → a different id"
}

test_rowed_finds_an_existing_row() {
  local id rc
  id=$(bash "$HOP_SH" ask-id --pane %3 --question "Push the branch?")
  cat > "$FIX/log.md" <<EOF
## 🪜 Escalations (live)
| direction | seat (from-name · pane id) | the topic | member links | sent | ack | disposition |
|-----------|----------------------------|-----------|--------------|------|-----|-------------|
| received | idealic:kernel · %3 | Push the branch? | ask:$id | 22:10 · delivered | open — passed up | passed up |

## 👁️ Observation
| other table | ask:hop-0-ffffffffff |
EOF
  bash "$HOP_SH" rowed --log "$FIX/log.md" --id "$id"; rc=$?
  assert_eq "0" "$rc" "rowed: a re-emitted question already in the register → 0 (skip; no duplicate row or /ask)"
  bash "$HOP_SH" rowed --log "$FIX/log.md" --id "hop-3-0000000000"; rc=$?
  assert_eq "1" "$rc" "rowed: a new question → 1 (write the row)"
  bash "$HOP_SH" rowed --log "$FIX/log.md" --id "hop-0-ffffffffff"; rc=$?
  assert_eq "1" "$rc" "rowed: an id outside the register does not count"
}

test_no_clock_subcommand() {
  local rc
  bash "$HOP_SH" due --asked-at 1 --now 100000 >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "hop.sh has no 'due' clock (M3/M6: re-ping is manual)"
}

# ---------------------------------------------------------------- configs: grant v1

test_configs_install_grant_v1() {
  local f p
  for f in coordinate.manager.config.json; do
    p="$SKILL_DIR/assets/$f"
    assert_ok "$f parses" jq -e . "$p"
    assert_eq '["A","B","C","D"]' "$(jq -c '.grant.classes' "$p")" "$f: grant v1 delegates A–D"
    assert_eq '["E","F","G","H"]' "$(jq -c '.grant.reserved' "$p")" "$f: E–H reserved"
    assert_eq "4" "$(jq '[.grant.clauses[] | select(.condition and .reversal)] | length' "$p")" "$f: each of A–D has a condition and a reversal"
    assert_eq "false" "$(jq '.alwaysEscalate | index("git operations") != null' "$p")" "$f: blanket 'git operations' is gone"
    assert_eq "null" "$(jq -c '.hop.repingAfterMinutes // .hop.passUpAfterMinutes // .hop.parentFrom' "$p")" "$f: no timer keys, no parentFrom"
  done
}

test_example_config_carries_no_grant() {
  # R7 (director ruling): the grant applies in Manager mode only.
  local p="$SKILL_DIR/assets/coordinate.config.example.json"
  assert_ok "example config parses" jq -e . "$p"
  assert_eq "[]" "$(jq -c '.grant.classes' "$p")" "example: grant is empty (manager mode only)"
  assert_eq '["git operations","file deletion","database changes","security decisions","architecture changes","PR creation","deployment","dependency changes"]' \
    "$(jq -c '.alwaysEscalate' "$p")" "example: alwaysEscalate is the pre-install list, git blanket first"
  assert_eq "null" "$(jq -c '.hop.repingAfterMinutes // .hop.passUpAfterMinutes // .hop.parentFrom' "$p")" "example: no timer keys, no parentFrom"
  assert_eq "1|pass-up: class B is not in the installed grant" \
    "$(may --class B --floor none --raised-by idealic:kernel --config "$p")" "example config: a class-B question passes up"
}

test_manager_backstops_and_log_lines_are_verbatim() {
  # R6 (director ruling): F, G, H backstops and the C/D alwaysLog lines, from the proposal.
  if [ ! -r "$PROPOSAL" ]; then skip "backstops verbatim" "proposal not readable"; return; fi
  local p="$SKILL_DIR/assets/coordinate.manager.config.json" line ln
  for ln in 121 122 126; do
    line=$(sed -n "${ln}p" "$PROPOSAL" | sed -E 's/^ *"(.*)",?$/\1/')
    assert_eq "true" "$(jq --arg l "$line" '.alwaysEscalate | index($l) != null' "$p")" "manager alwaysEscalate has proposal line $ln: $line"
  done
  for ln in 130 131; do
    line=$(sed -n "${ln}p" "$PROPOSAL" | sed -E 's/^ *"(.*)",?$/\1/')
    assert_eq "true" "$(jq --arg l "$line" '.alwaysLog | index($l) != null' "$p")" "manager alwaysLog has proposal line $ln: $line"
  done
}

test_git_clauses_are_verbatim_from_the_proposal() {
  if [ ! -r "$PROPOSAL" ]; then skip "git clauses verbatim" "proposal not readable"; return; fi
  local want got f
  want=$(sed -n '/"alwaysEscalate": \[/,/\]/p' "$PROPOSAL" | sed -nE 's/^ *"(.*)",?$/\1/p' | head -4)
  for f in coordinate.manager.config.json; do
    got=$(jq -r '.alwaysEscalate[0:4][]' "$SKILL_DIR/assets/$f")
    assert_eq "$want" "$got" "$f: the 4 git clauses match the proposal byte for byte"
  done
}

test_manager_preset_values_each_have_a_reader() {
  local p="$SKILL_DIR/assets/coordinate.manager.config.json" k mode="$SKILL_DIR/modes/manager.md"
  assert_eq "0.5" "$(jq -r '.confidenceThreshold' "$p")" "preset: threshold 0.5 (C1)"
  assert_eq "1" "$(jq -r '.slotCap' "$p")" "preset: slot cap 1 (C1)"
  for k in peerInstructions slotCap autoContinue declaredVsLiveCheck interruption autonomy; do
    assert_gt "$(grep -c "\`$k\`" "$mode")" 0 "preset key $k is read by modes/manager.md"
  done
}

test_manager_mode_is_registered() {
  assert_eq "modes/manager.md" "$(jq -r '.modes.manager.file' "$SKILL_DIR/manifest.json")" "manifest lists the manager mode"
}

# ---------------------------------------------------------------- protocol text

test_register_reuses_seat_handovers_row_shape() {
  local loom="$HOME/.claude/engine/skills/loom/assets/TEMPLATE_LOOM_LOG.md"
  local mine="$SKILL_DIR/assets/TEMPLATE_COORDINATE_LOG.md" theirs ours
  theirs=$(awk '/^## 📨 Seat handovers/{f=1} f && /^\| direction/{print; exit}' "$loom")
  ours=$(awk '/^## 🪜 Escalations/{f=1} f && /^\| direction/{print; exit}' "$mine")
  assert_not_empty "$theirs" "loom template still has the Seat handovers header"
  assert_eq "$theirs disposition |" "$ours" "Escalations header = Seat handovers header + disposition"
}

test_skill_text_matches_the_script() {
  local s="$SKILL_DIR/SKILL.md" step5
  step5=$(awk '/^#### Step 5/{f=1} /^### ESC Interrupt/{f=0} f' "$s")
  assert_has "hop.sh target" "$step5" "Step 5 resolves the target with hop.sh"
  assert_has "exit 3" "$step5" "Step 5 handles exit 3"
  assert_has "reserved-for: operator" "$step5" "Step 5 carries the reserved-for mark"
  assert_eq "0" "$(grep -c 'hop.sh due' "$s")" "SKILL.md no longer calls a clock"
  assert_eq "0" "$(grep -c 'repingAfterMinutes\|passUpAfterMinutes' "$s")" "SKILL.md names no timer keys"
  assert_has "hop.sh rowed" "$(cat "$s")" "SKILL.md dedupes with hop.sh rowed"
  assert_has "**Orientation**" "$(cat "$s")" "SKILL.md defines orientation"
  local step1
  step1=$(awk '/^#### Step 1/{f=1} /^#### Step 2/{f=0} f' "$s")
  assert_has "hop.sh panes" "$step1" "Step 1 sweeps only panes not held by a pass-up (M3 residual)"
  assert_has "hop.sh inbox" "$step1" "the top of each iteration reads asks addressed to this seat (R2)"
  assert_has "Check its exit" "$(sed -n '/Parent Resolution/,/Pane Discovery/p' "$s")" "Setup checks chain's exit (R9)"
  assert_eq "0" "$(sed -n '/Core Invariants/,/^---/p' "$s" | grep -cF 'No custom protocols or file-based handshakes.')" \
    "SKILL.md's transcript invariant states its exception (S3)"
}

run_discovered_tests
