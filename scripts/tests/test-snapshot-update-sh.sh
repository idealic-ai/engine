#!/bin/bash
# tests/test-snapshot-update-sh.sh — Tests for skills/snapshot/assets/wave-update.mjs
# Run: bash ~/.claude/engine/scripts/tests/run-all.sh test-snapshot-update-sh.sh
#
# /snapshot's wave-end updates (Linear PROJECT status updates per touched project, and a
# manager's INITIATIVE roll-up) are decided by one renderer so the rules are checkable
# without posting anything. What is worth asserting is the rules that fail silently:
#   - the health rule, and above all that an underivable health DECLINES instead of guessing;
#   - one update per project per wave: a retry or a second lane EDITS the wave's update in
#     place, and a foreign update in the window (an /intake post) blocks a second post;
#   - an initiative roll-up is built only from posted project updates — zero in, zero out;
#   - a manager's health override is VISIBLE in the edited body, not only in the health field.
# Nothing here touches Linear: the renderer is pure stdin -> stdout.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

WU="$HOME/.claude/engine/skills/snapshot/assets/wave-update.mjs"

run_wu() { node "$WU" "$1" 2>/dev/null; }
jqr() { printf '%s' "$1" | jq -r "$2"; }

LANE_GREEN='{"ticket":"IDE-201","title":"Snapshot posts wave updates","stateFrom":"In Progress","stateTo":"In Review",
  "tldr":"Wave updates render and post behind the batch confirm.","gates":"green","direction":"aligned","blocked":false,"mustFixOpen":0}'

# health of a signal set: clean defaults (blocked no, 0 MUST-FIX) merged under the given JSON.
hl() { jq -cn --argjson o "$1" '{gates:"green",direction:"aligned",blocked:"no",mustFixOpen:0} + $o' | run_wu health | jq -r .health; }

# SU-01 — the health rule, one row per outcome, in the template's own vocabulary.
test_health_rule() {
  assert_eq "onTrack"  "$(hl '{}')" "SU-01: green+aligned is onTrack"
  assert_eq "onTrack"  "$(hl '{"gates":"none"}')" "SU-01b: no runnable gate + aligned is onTrack"
  assert_eq "atRisk"   "$(hl '{"gates":"unrun"}')" "SU-01c: unrun gates are atRisk"
  assert_eq "atRisk"   "$(hl '{"direction":"rescoped"}')" "SU-01d: re-scoped is atRisk"
  assert_eq "atRisk"   "$(hl '{"mustFixOpen":2}')" "SU-01e: an open MUST-FIX is atRisk"
  assert_eq "atRisk"   "$(hl '{"mustFixOpen":"2"}')" "SU-01e2: a MUST-FIX count written as text is read"
  assert_eq "offTrack" "$(hl '{"gates":"red"}')" "SU-01f: red gates are offTrack"
  assert_eq "offTrack" "$(hl '{"direction":"drifted"}')" "SU-01g: drift is offTrack"
  assert_eq "offTrack" "$(hl '{"blocked":"yes"}')" "SU-01h: blocked 'yes' (the template's word) is offTrack"
  assert_eq "offTrack" "$(hl '{"blocked":true}')" "SU-01i: blocked true is offTrack"
}

# SU-02 — underivable is a first-class answer, never a default to onTrack.
test_health_underivable() {
  local out
  out=$(echo '{"gates":"green"}' | run_wu health)
  assert_eq "underivable" "$(jqr "$out" .health)" "SU-02: missing direction is underivable"
  assert_contains "direction" "$(jqr "$out" .reason)" "SU-02b: the reason names the missing signal"
  out=$(echo '{"direction":"aligned","gates":"purple"}' | run_wu health)
  assert_eq "underivable" "$(jqr "$out" .health)" "SU-02c: an unknown gate value is underivable, not guessed"
  # an unknown signal declines even when another signal alone would decide offTrack
  out=$(echo '{"direction":"unknown","gates":"red","blocked":"no","mustFixOpen":0}' | run_wu health)
  assert_eq "underivable" "$(jqr "$out" .health)" "SU-02d: direction 'unknown' declines even beside red gates"
  # M1 — blocked and the MUST-FIX count are required too; the critique's P1-P3 came out onTrack.
  assert_eq "underivable" "$(hl '{"mustFixOpen":"unknown"}')" "SU-02e: MUST-FIX 'unknown' is underivable (P1)"
  assert_eq "underivable" "$(hl '{"blocked":"unknown"}')" "SU-02f: blocked 'unknown' is underivable (P3)"
  assert_eq "underivable" "$(echo '{"gates":"green","direction":"aligned","blocked":"no"}' | run_wu health | jq -r .health)" "SU-02g: a missing MUST-FIX count is underivable"
  assert_eq "underivable" "$(echo '{"gates":"green","direction":"aligned","mustFixOpen":0}' | run_wu health | jq -r .health)" "SU-02h: a missing blocked is underivable"
  assert_eq "underivable" "$(hl '{"mustFixOpen":-1}')" "SU-02i: a negative count is underivable"
}

# SU-03 — no update yet this wave: create, with the marker as the last line.
test_project_create() {
  local out
  out=$(printf '{"wave":"DIRECTOR/w3","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project)
  assert_eq "create" "$(jqr "$out" .action)" "SU-03: no existing update -> create"
  assert_eq "onTrack" "$(jqr "$out" .health)" "SU-03b: health derived from the lane"
  assert_eq "derived" "$(jqr "$out" .healthSource)" "SU-03c: health source is stated"
  assert_contains "### IDE-201" "$(jqr "$out" .body)" "SU-03d: the lane is a section keyed by its ticket"
  assert_eq "— wave DIRECTOR/w3" "$(jqr "$out" '.body | split("\n") | last')" "SU-03e: wave marker is the body's last line"
}

# SU-03f — a local path in lane text declines (a cold reader cannot open it); control: without it, create.
test_project_local_path_declines() {
  local lane out
  lane=$(jq -c '.tldr = "See /Users/x/sessions/a_BUILD.md for the details."' <<<"$LANE_GREEN")
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[]}' "$lane" | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-03f: a lane carrying /Users/... declines"
  assert_contains "local file path" "$(jqr "$out" .reason)" "SU-03g: and says why"
  lane=$(jq -c '.tldr = "See ~/.claude/x for the details."' <<<"$LANE_GREEN")
  assert_eq "decline" "$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[]}' "$lane" | run_wu project | jq -r .action)" "SU-03h: a ~/ path declines too"
}

# SU-04 — a retry of the same lane edits the wave's update in place, and does not duplicate the section.
test_project_retry_edits() {
  local first second
  first=$(printf '{"wave":"DIRECTOR/w3","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project)
  local body; body=$(jqr "$first" .body)
  second=$(jq -n --arg b "$body" --argjson lane "$LANE_GREEN" \
    '{wave:"DIRECTOR/w3",project:"Engine",lane:$lane,existing:[{id:"su-1",body:$b,health:"onTrack"}]}' | run_wu project)
  assert_eq "edit" "$(jqr "$second" .action)" "SU-04: a retry edits"
  assert_eq "su-1" "$(jqr "$second" .id)" "SU-04b: it edits the wave's own update id"
  assert_eq "1" "$(jqr "$second" '[.body | split("\n")[] | select(startswith("### IDE-201"))] | length')" "SU-04c: the lane section is replaced, not appended twice"
}

# SU-05 — a second lane on the same project merges; project health is the worst lane.
test_project_second_lane_merges() {
  local first body lane2 out
  first=$(printf '{"wave":"DIRECTOR/w3","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project)
  body=$(jqr "$first" .body)
  lane2='{"ticket":"IDE-202","title":"Roll-up","stateFrom":"Todo","stateTo":"In Progress","tldr":"Half done.","gates":"unrun","direction":"aligned","blocked":"no","mustFixOpen":0}'
  out=$(jq -n --arg b "$body" --argjson lane "$lane2" \
    '{wave:"DIRECTOR/w3",project:"Engine",lane:$lane,existing:[{id:"su-1",body:$b,health:"onTrack"}]}' | run_wu project)
  assert_eq "edit" "$(jqr "$out" .action)" "SU-05: second lane edits the same update"
  assert_contains "### IDE-201" "$(jqr "$out" .body)" "SU-05b: the first lane survives"
  assert_contains "### IDE-202" "$(jqr "$out" .body)" "SU-05c: the second lane is added"
  assert_eq "atRisk" "$(jqr "$out" .health)" "SU-05d: project health is the worst lane"
}

# SU-06 — a foreign update in the window (no marker, e.g. /intake's) blocks a second post.
test_project_foreign_declines() {
  local out
  out=$(printf '{"wave":"DIRECTOR/w3","project":"Engine","lane":%s,"existing":[{"id":"x","body":"Intake pass: 4 filed","health":"onTrack"}]}' "$LANE_GREEN" | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-06: a foreign update this wave declines"
  assert_contains "no wave start given" "$(jqr "$out" .reason)" "SU-06b: with no start, the reason names the missing start"
  out=$(printf '{"wave":"DIRECTOR/w3","project":"Engine","since":"2026-10-28T12:00:00Z","lane":%s,"existing":[{"id":"x","body":"Intake pass: 4 filed","health":"onTrack","createdAt":"2026-10-28T13:00:00Z"}]}' "$LANE_GREEN" | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-06d: an unmarked update after the wave start declines"
  assert_contains "since this wave began" "$(jqr "$out" .reason)" "SU-06e: and the reason says it is inside this wave"
  out=$(printf '{"wave":"DIRECTOR/w3","project":"Engine","since":"2026-10-28T12:00:00Z","lane":%s,"existing":[{"id":"x","body":"Intake pass: 4 filed","health":"onTrack","createdAt":"2026-10-28T09:00:00Z"}]}' "$LANE_GREEN" | run_wu project)
  assert_eq "create" "$(jqr "$out" .action)" "SU-06f: an unmarked update before the wave start is outside it"
}

# SU-06c — M3: the second wave of a day is not blocked by the first (critique P10, no start given).
test_project_other_wave_ignored() {
  local w3 out
  w3=$(printf '{"wave":"DIRECTOR/w3","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project | jq -r .body)
  out=$(jq -n --arg b "$w3" --argjson lane "$LANE_GREEN" '{wave:"DIRECTOR/w4",project:"Engine",lane:$lane,existing:[{id:"w3u",body:$b,health:"onTrack"}]}' | run_wu project)
  assert_eq "create" "$(jqr "$out" .action)" "SU-06c: wave w4 creates beside w3's update"
  assert_eq "w3u" "$(jqr "$out" '.ignoredOtherWaves | join(",")')" "SU-06g: and reports the other wave's update it ignored"
}

# SU-07 — two of ours with no readable order: decline, and hand back exactly both ids.
test_project_double_declines() {
  local b out
  b=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project | jq -r .body)
  out=$(jq -n --arg b "$b" --argjson lane "$LANE_GREEN" '{wave:"W",project:"Engine",lane:$lane,existing:[{id:"a",body:$b},{id:"b",body:$b}]}' | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-07: two updates with no createdAt decline"
  assert_eq "a,b" "$(jqr "$out" '.ids | join(",")')" "SU-07b: exactly both ids are handed back"
}

# SU-15 — S4: a concurrent double create. The later lane edits the earliest, merges both, and
# retires only its own duplicate; another lane's duplicate is reported, not retired.
test_project_concurrent_double() {
  local ba bb lane2 out
  ba=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project | jq -r .body)
  lane2='{"ticket":"IDE-202","title":"Roll-up","stateFrom":"Todo","stateTo":"In Progress","tldr":"Half.","gates":"unrun","direction":"aligned","blocked":"no","mustFixOpen":0}'
  bb=$(jq -n --argjson lane "$lane2" '{wave:"W",project:"Engine",lane:$lane,existing:[]}' | run_wu project | jq -r .body)
  out=$(jq -n --arg a "$ba" --arg b "$bb" --argjson lane "$lane2" '{wave:"W",project:"Engine",lane:$lane,selfId:"b",
    existing:[{id:"b",body:$b,createdAt:"2026-10-28T10:00:02Z"},{id:"a",body:$a,createdAt:"2026-10-28T10:00:01Z"}]}' | run_wu project)
  assert_eq "edit" "$(jqr "$out" .action)" "SU-15: the later lane edits"
  assert_eq "a" "$(jqr "$out" .id)" "SU-15b: the earliest update is canonical"
  assert_eq "b" "$(jqr "$out" '.retire | join(",")')" "SU-15c: it retires only its own duplicate"
  assert_contains "### IDE-201" "$(jqr "$out" .body)" "SU-15d: the other lane's section is kept"
  assert_contains "### IDE-202" "$(jqr "$out" .body)" "SU-15e: its own section is merged in"
  out=$(jq -n --arg a "$ba" --arg b "$bb" --argjson lane "$lane2" '{wave:"W",project:"Engine",lane:$lane,selfId:"zz",
    existing:[{id:"b",body:$b,createdAt:"2026-10-28T10:00:02Z"},{id:"a",body:$a,createdAt:"2026-10-28T10:00:01Z"}]}' | run_wu project)
  assert_eq "" "$(jqr "$out" '(.retire // []) | join(",")')" "SU-15f: someone else's duplicate is not retired"
  assert_eq "b" "$(jqr "$out" '.duplicates | join(",")')" "SU-15g: it is reported instead"
}

# SU-08 — underivable health declines the lane; a chosen health (from the confirm) posts.
test_project_underivable() {
  local lane out
  lane='{"ticket":"IDE-203","title":"T","tldr":"x","gates":"green"}'
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[]}' "$lane" | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-08: underivable health declines"
  assert_contains "health" "$(jqr "$out" .reason)" "SU-08b: the reason names health"
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[],"health":"atRisk"}' "$lane" | run_wu project)
  assert_eq "create" "$(jqr "$out" .action)" "SU-08c: a health chosen at the confirm posts"
  assert_eq "chosen" "$(jqr "$out" .healthSource)" "SU-08d: and says it was chosen, not derived"
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[],"health":"great"}' "$lane" | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-08e: an invalid chosen health declines"
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[],"health":"atRisk","unattended":true}' "$lane" | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-08f: S6 — an unattended run refuses a chosen health"
  assert_contains "unattended" "$(jqr "$out" .reason)" "SU-08g: and says so"
}

ROLL_UPDATES='[
 {"id":"p1","project":"Engine","url":"https://linear.test/u/p1","health":"onTrack","body":"### IDE-201 · Snapshot posts wave updates\nIn Progress → In Review\nWave updates post.\nHealth: onTrack\n\n— wave W"},
 {"id":"p2","project":"Docs","url":"https://linear.test/u/p2","health":"atRisk","body":"### IDE-300 · Docs\nTodo → In Progress\nHalf.\nHealth: atRisk\n\n— wave W"},
 {"id":"p3","project":"Other","url":"https://linear.test/u/p3","health":"offTrack","body":"old\n— wave W0"}
]'

# SU-09 — the roll-up is built from posted wave updates only, and traces to each.
test_rollup_traces() {
  local out
  out=$(jq -n --argjson u "$ROLL_UPDATES" '{wave:"W",initiative:"idealic",manager:"idealic",updates:$u,existing:[]}' | run_wu rollup)
  assert_eq "create" "$(jqr "$out" .action)" "SU-09: a roll-up with inputs creates"
  assert_contains "https://linear.test/u/p1" "$(jqr "$out" .body)" "SU-09b: traces to the first project update"
  assert_contains "https://linear.test/u/p2" "$(jqr "$out" .body)" "SU-09c: traces to the second"
  assert_not_contains "p3" "$(jqr "$out" .body)" "SU-09d: another wave's update is excluded"
  assert_eq "atRisk" "$(jqr "$out" .health)" "SU-09e: initiative health is the worst included project"
  assert_eq "2" "$(jqr "$out" '.sources | length')" "SU-09f: sources list the two update ids"
}

# SU-10 — zero posted updates: no roll-up at all (no hand-written padding).
test_rollup_empty_declines() {
  local out
  out=$(jq -n '{wave:"W",initiative:"idealic",manager:"idealic",updates:[],existing:[]}' | run_wu rollup)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-10: zero updates -> decline"
  assert_eq "" "$(jqr "$out" '.body // ""')" "SU-10b: and no body is drafted"
}

# SU-11 — a manager override is visible in the worker's update body and drives the roll-up.
test_rollup_override_visible() {
  local out
  out=$(jq -n --argjson u "$ROLL_UPDATES" \
    '{wave:"W",initiative:"idealic",manager:"idealic",updates:$u,existing:[],overrides:{"Engine":{health:"offTrack",reason:"the merge gate is red on main"}}}' | run_wu rollup)
  assert_eq "p1" "$(jqr "$out" '.edits[0].id')" "SU-11: the override edits the worker update by id"
  assert_eq "offTrack" "$(jqr "$out" '.edits[0].health')" "SU-11b: with the new health"
  assert_contains "idealic manager" "$(jqr "$out" '.edits[0].body')" "SU-11c: the body names who overrode"
  assert_contains "was onTrack" "$(jqr "$out" '.edits[0].body')" "SU-11d: and what it was"
  assert_contains "merge gate is red" "$(jqr "$out" '.edits[0].body')" "SU-11e: and why"
  assert_eq "— wave W" "$(jqr "$out" '.edits[0].body | split("\n") | last')" "SU-11f: the marker stays last"
  assert_eq "offTrack" "$(jqr "$out" .health)" "SU-11g: the roll-up uses the overridden health"
  out=$(jq -n --argjson u "$ROLL_UPDATES" \
    '{wave:"W",initiative:"idealic",manager:"idealic",updates:$u,existing:[],overrides:{"Engine":{health:"offTrack"}}}' | run_wu rollup)
  assert_eq "0" "$(jqr "$out" '.edits | length')" "SU-11h: an override without a reason is declined"
  assert_not_empty "$(jqr "$out" '.declined[0] // empty')" "SU-11i: and the decline is reported"
}

# SU-12 — a roll-up retry edits the wave's initiative update in place.
test_rollup_retry_edits() {
  local out
  out=$(jq -n --argjson u "$ROLL_UPDATES" '{wave:"W",initiative:"idealic",manager:"idealic",updates:$u,existing:[{id:"i1",body:"x\n— wave W"}]}' | run_wu rollup)
  assert_eq "edit" "$(jqr "$out" .action)" "SU-12: roll-up retry edits"
  assert_eq "i1" "$(jqr "$out" .id)" "SU-12b: the existing initiative update id"
}

# SU-14 — on a real rendered body, the override also rewrites the lead line's health, so the
# edited update never states two healths. (Found in the dry run: the lead kept "health onTrack".)
test_override_lead_line() {
  local first body out lead
  first=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project)
  body=$(jqr "$first" .body)
  assert_contains "health onTrack" "$(printf '%s' "$body" | head -1)" "SU-14 control: the rendered lead states onTrack"
  out=$(jq -n --arg b "$body" '{wave:"W",initiative:"i",manager:"app",existing:[],
    updates:[{id:"p1",project:"Engine",url:"u",health:"onTrack",body:$b}],
    overrides:{"Engine":{health:"atRisk",reason:"review found a gap"}}}' | run_wu rollup)
  lead=$(jqr "$out" '.edits[0].body | split("\n") | first')
  assert_not_contains "health onTrack" "$lead" "SU-14b: the old health is gone from the lead"
  assert_contains "health atRisk, set by the app manager" "$lead" "SU-14c: the lead states the override"
}

LANE_B='{"ticket":"IDE-202","title":"Roll-up","stateFrom":"Todo","stateTo":"In Progress","tldr":"Half.","gates":"unrun","direction":"aligned","blocked":"no","mustFixOpen":0}'

# Build the critique's M2 scene: lanes A then B post, then the manager overrides to offTrack.
# Prints the overridden worker body.
overridden_body() {
  local a ab
  a=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project | jq -r .body)
  ab=$(jq -n --arg b "$a" --argjson lane "$LANE_B" '{wave:"W",project:"Engine",lane:$lane,existing:[{id:"u1",body:$b}]}' | run_wu project | jq -r .body)
  jq -n --arg b "$ab" '{wave:"W",initiative:"i",manager:"idealic",existing:[],
    updates:[{id:"u1",project:"Engine",url:"u",health:"atRisk",body:$b}],
    overrides:{"Engine":{health:"offTrack",reason:"the wave gate is red"}}}' | run_wu rollup | jq -r '.edits[0].body'
}

# SU-16 — M2: a worker re-post after an override keeps it, in the field AND the body, whichever lane re-posts.
test_repost_keeps_override() {
  local ov out lead
  ov=$(overridden_body)
  assert_contains "Health set to offTrack" "$ov" "SU-16 control: the scene carries an override"
  # lane B — the last section, the case that erased the note
  out=$(jq -n --arg b "$ov" --argjson lane "$LANE_B" '{wave:"W",project:"Engine",lane:$lane,existing:[{id:"u1",body:$b,health:"offTrack"}]}' | run_wu project)
  assert_eq "offTrack" "$(jqr "$out" .health)" "SU-16b: lane B re-post keeps the override health"
  assert_contains "Health set to offTrack by the idealic manager" "$(jqr "$out" .body)" "SU-16c: lane B re-post keeps the note"
  assert_eq "true" "$(jqr "$out" .overrideStands)" "SU-16d: and says the override stands"
  assert_eq "atRisk" "$(jqr "$out" .lanesWorst)" "SU-16e: while still reporting what the lanes say"
  # lane A
  out=$(jq -n --arg b "$ov" --argjson lane "$LANE_GREEN" '{wave:"W",project:"Engine",lane:$lane,existing:[{id:"u1",body:$b,health:"offTrack"}]}' | run_wu project)
  lead=$(jqr "$out" '.body | split("\n") | first')
  assert_eq "offTrack" "$(jqr "$out" .health)" "SU-16f: lane A re-post keeps the override health"
  assert_contains "health offTrack, set by the idealic manager" "$lead" "SU-16g: and the lead agrees with the field"
  assert_eq "1" "$(jqr "$out" '[.body | split("\n")[] | select(startswith("**Health set to"))] | length')" "SU-16h: the note is carried once, not duplicated"
}

# SU-17 — S1: an override naming a project with no wave update is reported, not silently dropped.
test_rollup_unmatched_override() {
  local out
  out=$(jq -n --argjson u "$ROLL_UPDATES" '{wave:"W",initiative:"i",manager:"m",updates:$u,existing:[],
    overrides:{"engine":{health:"offTrack",reason:"r"},"Engine":{health:"offTrack",reason:"r"}}}' | run_wu rollup)
  assert_eq "1" "$(jqr "$out" '.edits | length')" "SU-17: the matching override applies"
  assert_contains "engine: no wave W update" "$(jqr "$out" '.declined | join("|")')" "SU-17b: the wrong-case key is reported"
  out=$(jq -n '{wave:"W",initiative:"i",manager:"m",updates:[],existing:[],overrides:{"Docs":{health:"atRisk",reason:"r"}}}' | run_wu rollup)
  assert_contains "Docs" "$(jqr "$out" '.declined | join("|")')" "SU-17c: reported even when the roll-up itself declines"
}

# SU-18 — S2: a missing or unreadable health refuses instead of seeding onTrack.
test_no_onTrack_seed() {
  local out
  out=$(jq -n --argjson u "$ROLL_UPDATES" '{wave:"W",initiative:"i",manager:"m",updates:($u|map(del(.health))),existing:[]}' | run_wu rollup)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-18: roll-up updates with no health decline (P7)"
  out=$(jq -n --argjson u "$ROLL_UPDATES" '{wave:"W",initiative:"i",manager:"m",updates:($u|map(del(.url))),existing:[]}' | run_wu rollup)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-18b: roll-up updates with no url decline (no dead links)"
  # P12: another lane's section collapsed so its Health line is unreadable
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[{"id":"u1","health":"offTrack","body":"### IDE-9 · X Todo → Done Health: offTrack — red\\n\\n— wave W"}]}' "$LANE_GREEN" | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-18c: an existing lane with no readable health refuses (P12)"
  # S7-adjacent: someone else's words under our marker are never discarded
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[{"id":"h","body":"Ops note from Alice: release frozen.\\n— wave W"}]}' "$LANE_GREEN" | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-18d: stray text under the marker refuses rather than being dropped (P9)"
}

# SU-19 — S3: a second override keeps the lead consistent; notes stack, the last sets the health.
test_second_override() {
  local ov out lead
  ov=$(overridden_body)
  out=$(jq -n --arg b "$ov" '{wave:"W",initiative:"i",manager:"app",existing:[],
    updates:[{id:"u1",project:"Engine",url:"u",health:"offTrack",body:$b}],
    overrides:{"Engine":{health:"onTrack",reason:"gate fixed"}}}' | run_wu rollup)
  lead=$(jqr "$out" '.edits[0].body | split("\n") | first')
  assert_contains "health onTrack, set by the app manager" "$lead" "SU-19: the lead states the latest override (P8)"
  assert_not_contains "offTrack" "$lead" "SU-19b: and not the earlier one"
  assert_eq "2" "$(jqr "$out" '[.edits[0].body | split("\n")[] | select(startswith("**Health set to"))] | length')" "SU-19c: both rulings stay visible (they stack)"
  assert_eq "onTrack" "$(jqr "$out" '.edits[0].health')" "SU-19d: the field is the latest ruling"
}

# SU-20 — S5: what would post differs from what was confirmed -> reconfirm, or decline unattended.
test_confirmed_drift() {
  local out
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[],"confirmed":{"action":"create","health":"onTrack"}}' "$LANE_GREEN" | run_wu project)
  assert_eq "create" "$(jqr "$out" .action)" "SU-20 control: no drift posts as confirmed"
  assert_eq "null" "$(jqr "$out" .reconfirm)" "SU-20b: and asks nothing"
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[],"confirmed":{"action":"create","health":"atRisk"}}' "$LANE_GREEN" | run_wu project)
  assert_eq "true" "$(jqr "$out" .reconfirm)" "SU-20c: a changed health re-asks"
  assert_eq "health" "$(jqr "$out" '.drift | join(",")')" "SU-20d: naming what changed"
  out=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[],"unattended":true,"confirmed":{"action":"create","health":"atRisk"}}' "$LANE_GREEN" | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-20e: unattended, a drift declines"
  out=$(jq -n --argjson u "$ROLL_UPDATES" '{wave:"W",initiative:"i",manager:"m",updates:$u,existing:[],unattended:true,confirmed:{action:"create",health:"onTrack"}}' | run_wu rollup)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-20f: the roll-up applies the same rule"
}

# Build the RR-M1 scene: lanes A (onTrack) and B (atRisk), then the manager rules onTrack.
lapse_scene() {
  local a ab
  a=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project | jq -r .body)
  ab=$(jq -n --arg b "$a" --argjson lane "$LANE_B" '{wave:"W",project:"Engine",lane:$lane,existing:[{id:"u1",body:$b}]}' | run_wu project | jq -r .body)
  jq -n --arg b "$ab" '{wave:"W",initiative:"i",manager:"idealic",existing:[],
    updates:[{id:"u1",project:"Engine",url:"u",health:"atRisk",body:$b}],
    overrides:{"Engine":{health:"onTrack",reason:"the unrun gate is docs-only"}}}' | run_wu rollup | jq -r '.edits[0].body'
}

# SU-21 — RR-M1 (probe N-A): an override holds only while the lanes are no worse than what the
# manager ruled on. A lane going red lapses it: the worse health posts and the body says why.
test_override_lapses_when_lanes_worsen() {
  local ov red out lead
  ov=$(lapse_scene)
  assert_contains "(was atRisk)" "$ov" "SU-21 control: the ruling recorded the lanes' atRisk"
  # control: lane B re-posts still atRisk — the override stands
  out=$(jq -n --arg b "$ov" --argjson lane "$LANE_B" '{wave:"W",project:"Engine",lane:$lane,existing:[{id:"u1",body:$b,health:"onTrack"}]}' | run_wu project)
  assert_eq "onTrack" "$(jqr "$out" .health)" "SU-21b: no worse than the ruling, the override stands"
  assert_eq "true" "$(jqr "$out" .overrideStands)" "SU-21c: and says so"
  # lane B re-posts with red gates
  red=$(jq -c '.gates = "red"' <<<"$LANE_B")
  out=$(jq -n --arg b "$ov" --argjson lane "$red" '{wave:"W",project:"Engine",lane:$lane,existing:[{id:"u1",body:$b,health:"onTrack"}]}' | run_wu project)
  lead=$(jqr "$out" '.body | split("\n") | first')
  assert_eq "offTrack" "$(jqr "$out" .health)" "SU-21d: a lane worse than the ruling posts its own health (N-A)"
  assert_eq "false" "$(jqr "$out" .overrideStands)" "SU-21e: the override no longer stands"
  assert_not_contains "set by the idealic manager" "$lead" "SU-21f: the lead no longer credits the manager"
  assert_contains "Override lapsed" "$(jqr "$out" .body)" "SU-21g: the body says the override lapsed"
  assert_contains "worse than the atRisk the idealic manager ruled on" "$(jqr "$out" .body)" "SU-21h: and why"
  assert_contains "Health set to onTrack by the idealic manager" "$(jqr "$out" .body)" "SU-21i: the ruling itself stays visible"
  # the lapsed body is still the renderer's own: a later lane can edit it
  out=$(jq -n --arg b "$(jqr "$out" .body)" --argjson lane "$LANE_GREEN" '{wave:"W",project:"Engine",lane:$lane,existing:[{id:"u1",body:$b,health:"offTrack"}]}' | run_wu project)
  assert_eq "edit" "$(jqr "$out" .action)" "SU-21j: a lapsed body still parses for the next lane"
  assert_eq "1" "$(jqr "$out" '[.body | split("\n")[] | select(startswith("**Override lapsed"))] | length')" "SU-21k: the lapse line is regenerated, not stacked"
}

# SU-22 — RR-S1: under --yes, the S4 duplicate repair is a repair of this run's own create, so the
# drift against the confirmed "create" does not decline it. It still retires only selfId.
test_repair_not_declined_unattended() {
  local ba bb out
  ba=$(printf '{"wave":"W","project":"Engine","lane":%s,"existing":[]}' "$LANE_GREEN" | run_wu project | jq -r .body)
  bb=$(jq -n --argjson lane "$LANE_B" '{wave:"W",project:"Engine",lane:$lane,existing:[]}' | run_wu project | jq -r .body)
  out=$(jq -n --arg a "$ba" --arg b "$bb" --argjson lane "$LANE_B" '{wave:"W",project:"Engine",lane:$lane,selfId:"b",unattended:true,
    confirmed:{action:"create",health:"atRisk"},
    existing:[{id:"b",body:$b,createdAt:"2026-10-28T10:00:02Z"},{id:"a",body:$a,createdAt:"2026-10-28T10:00:01Z"}]}' | run_wu project)
  assert_eq "edit" "$(jqr "$out" .action)" "SU-22: the unattended repair proceeds (R1)"
  assert_eq "a" "$(jqr "$out" .id)" "SU-22b: on the earliest update"
  assert_eq "b" "$(jqr "$out" '.retire | join(",")')" "SU-22c: retiring only its own duplicate"
  assert_eq "true" "$(jqr "$out" .repair)" "SU-22d: and marks itself a repair"
  # control: the same drift without a duplicate to repair still declines unattended
  out=$(jq -n --arg a "$ba" --argjson lane "$LANE_B" '{wave:"W",project:"Engine",lane:$lane,unattended:true,
    confirmed:{action:"create",health:"atRisk"},existing:[{id:"a",body:$a}]}' | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-22e: a non-repair drift still declines unattended"
  # control: another lane's duplicate is not a repair of ours — drift still declines
  out=$(jq -n --arg a "$ba" --arg b "$bb" --argjson lane "$LANE_B" '{wave:"W",project:"Engine",lane:$lane,selfId:"zz",unattended:true,
    confirmed:{action:"create",health:"atRisk"},
    existing:[{id:"b",body:$b,createdAt:"2026-10-28T10:00:02Z"},{id:"a",body:$a,createdAt:"2026-10-28T10:00:01Z"}]}' | run_wu project)
  assert_eq "decline" "$(jqr "$out" .action)" "SU-22f: with no own duplicate to retire, drift still declines"
}

# SU-13 — bad input exits 1; decisions (incl. decline) exit 0.
test_exit_codes() {
  local rc
  echo 'not json' | node "$WU" project >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "SU-13: non-JSON exits 1"
  echo '{}' | node "$WU" sideways >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "SU-13b: unknown mode exits 1"
  echo '{"project":"Engine"}' | node "$WU" project >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "SU-13c: project without wave exits 1"
  jq -n '{wave:"W",initiative:"i",manager:"m",updates:[],existing:[]}' | node "$WU" rollup >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "SU-13d: a decline is a decision, exit 0"
}

run_discovered_tests
