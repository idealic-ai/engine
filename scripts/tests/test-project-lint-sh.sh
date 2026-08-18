#!/bin/bash
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FXDIR="$SRC_DIR/tests/fixtures/project-lint"
SCHEMA="$HOME/.claude/engine/skills/intake/assets/project-schema.json"

# lint-lib.sh is pure logic (no network, no $HOME resolution), so it is sourced directly
# rather than through a fake home.
# shellcheck source=/dev/null
. "$SRC_DIR/lint-lib.sh"

setup() {
  TMP_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TMP_DIR"
}

# ---- Case 1 — undeclared heading warns and derives its destination ----

test_projectlint_undeclared_heading_derives_destination() {
  local out rc
  out=$(lint_container "$SCHEMA" description "$FXDIR/desc-ticketing-only.md" 2>&1); rc=$?
  assert_eq "0" "$rc" "lint_container succeeds on a strayed description"
  assert_eq "1" "$(echo "$out" | jq 'length')" "exactly one finding"
  assert_eq "undeclared-heading" "$(echo "$out" | jq -r '.[0].rule')" "rule=undeclared-heading"
  assert_eq "Ticketing Strategy" "$(echo "$out" | jq -r '.[0].heading')" "the stray heading is named"
  assert_eq "handbook" "$(echo "$out" | jq -r '.[0].belongsIn')" "belongsIn DERIVED from the handbook container"
  assert_eq "warn" "$(echo "$out" | jq -r '.[0].severity')" "advisory by default"
  assert_eq "0" "$(lint_exit_code "$out")" "warnings alone exit 0"
}

# ---- Case 2 — the same input under --strict fails ----

test_projectlint_strict_promotes_undeclared_to_fail() {
  local out
  out=$(lint_container "$SCHEMA" description "$FXDIR/desc-ticketing-only.md" --strict)
  assert_eq "1" "$(echo "$out" | jq 'length')" "same single finding under --strict"
  assert_eq "undeclared-heading" "$(echo "$out" | jq -r '.[0].rule')" "identical rule under --strict"
  assert_eq "handbook" "$(echo "$out" | jq -r '.[0].belongsIn')" "identical derivation under --strict"
  assert_eq "fail" "$(echo "$out" | jq -r '.[0].severity')" "--strict promotes warn to fail"
  assert_eq "1" "$(lint_exit_code "$out")" "a failure exits 1"
}

# ---- Case 3 — missing 📘 pointer fails unconditionally ----

test_projectlint_missing_pointer_fails_without_strict() {
  local out
  out=$(lint_container "$SCHEMA" description "$FXDIR/desc-no-pointer.md")
  assert_eq "fail" "$(echo "$out" | jq -r '.[] | select(.id=="pointer") | .severity')" "pointer absence is a FAIL"
  assert_eq "missing-required" "$(echo "$out" | jq -r '.[] | select(.id=="pointer") | .rule')" "rule=missing-required"
  assert_eq "1" "$(lint_exit_code "$out")" "exit 1 even without --strict"
}

# ---- Case 4 — the four historical offenders, and the honest split between them ----
#
# Two of the four were RENAMED, not just moved: `Other intake inboxes` -> `The intake projects`
# and `Operators & cadence` -> `Cadence and the pass heartbeat`. Different words, so no container
# names them and nothing derives a destination. Normalization (case-fold + whitespace-collapse)
# recovers `Data Handling` -> `Data handling` for free; recovering the other two would take a
# stored alias, i.e. curation, which this schema refuses. So: 2 derived, 2 unresolved.
#
# The second sharp edge, worth stating because it is invisible otherwise: on the `description`
# container the two unresolved offenders are ABSORBED by the freeform `prose` section, which makes
# them indistinguishable from the project's own domain prose. In default mode they are SILENT.
# Only --strict surfaces them, and only as a non-blocking warn.

test_projectlint_four_historical_offenders() {
  local out headings
  out=$(lint_container "$SCHEMA" description "$FXDIR/desc-intake-precleanup.md")
  assert_eq "2" "$(echo "$out" | jq 'length')" \
    "default mode reports only the 2 offenders a sibling container still names"
  assert_eq "true" "$(echo "$out" | jq '[.[] | select(.rule=="undeclared-heading") | .belongsIn] | all(. == "handbook")')" \
    "both derive belongsIn=handbook — from the schema's own section lists, not a table"
  headings=$(echo "$out" | jq -r '[.[] | select(.rule=="undeclared-heading") | .heading] | sort | join(",")')
  assert_eq "Data Handling,Ticketing Strategy" "$headings" \
    "Data Handling resolves by NORMALIZATION alone (schema says `Data handling`)"
}

# All four offenders under --strict: 2 derived + 2 unresolved. The renamed pair reports the truth
# about this schema ("not named by any container") rather than a maintained guess about history.
test_projectlint_all_four_offenders_surface_under_strict() {
  local out offenders
  out=$(lint_container "$SCHEMA" description "$FXDIR/desc-intake-precleanup.md" --strict)
  offenders='["Ticketing Strategy","Data Handling","Other intake inboxes","Operators & cadence"]'
  assert_eq "4" "$(echo "$out" | jq --argjson o "$offenders" '[.[] | select(.heading as $h | $o | index($h))] | length')" \
    "all 4 historical offenders surface under --strict"
  assert_eq "2" "$(echo "$out" | jq --argjson o "$offenders" \
    '[.[] | select(.heading as $h | $o | index($h)) | select(.belongsIn == "handbook")] | length')" \
    "2 are DERIVED to the handbook"
  assert_eq "2" "$(echo "$out" | jq --argjson o "$offenders" \
    '[.[] | select(.heading as $h | $o | index($h)) | select(.belongsIn == null)] | length')" \
    "2 are unresolved — renamed sections no container names any more"
  assert_eq "true" "$(echo "$out" | jq --argjson o "$offenders" \
    '[.[] | select(.heading as $h | $o | index($h)) | select(.belongsIn == null) | .severity] | all(. == "warn")')" \
    "an unresolved offender never blocks — it is indistinguishable from the project's own prose"
}

# The design constraint itself, asserted: no curated bad-heading -> destination table, and no
# alias list either. Normalization is a rule and stays; aliasing is curation and is banned.
test_projectlint_schema_carries_no_curated_destination_map() {
  local keys
  keys=$(jq -r '[paths | map(tostring) | join(".")] | join(" ")' "$SCHEMA")
  assert_not_contains "canonicalize" "$keys" "no canonicalize map in the schema"
  assert_not_contains "movedTo" "$keys" "no movedTo map in the schema"
  assert_not_contains "knownBad" "$keys" "no known-bad-heading list in the schema"
  assert_not_contains "destination" "$keys" "no destination map in the schema"
  assert_eq "0" "$(jq '[paths | select(.[-1] == "aka")] | length' "$SCHEMA")" \
    "no aka/alias entries anywhere — zero curated entries is absolute"
  assert_eq "0" "$(grep -c '\.aka' "$SRC_DIR/lint-lib.sh")" \
    "lint-lib.sh reads no alias field either"
}

# ---- Case 5 — a clean description passes silently ----

test_projectlint_clean_description_is_silent() {
  local out
  out=$(lint_container "$SCHEMA" description "$FXDIR/desc-intake-clean.md")
  assert_eq "0" "$(echo "$out" | jq 'length')" "the real live description produces ZERO findings"
  assert_eq "0" "$(lint_exit_code "$out")" "clean exits 0"
}

# The wave's pre-write gate runs --strict against text like this. If --strict failed on the
# project's own prose headings, the gate would refuse the description that is already live and
# correct — so freeform absorption surfaces as a non-blocking warn, never a fail.
test_projectlint_strict_never_blocks_the_live_clean_description() {
  local out
  out=$(lint_container "$SCHEMA" description "$FXDIR/desc-intake-clean.md" --strict)
  assert_eq "false" "$(echo "$out" | jq 'any(.[]; .severity=="fail")')" "--strict raises no failure on the live description"
  assert_eq "0" "$(lint_exit_code "$out")" "the pre-write gate would let this description through"
  assert_eq "2" "$(echo "$out" | jq '[.[] | select(.rule=="unknown-heading" and .severity=="warn")] | length')" \
    "its two prose headings are surfaced to the wave, not suppressed"
}

# The same guard one tier down — with the one deliberate exception the schema now encodes.
#
# The schema's handbook order was reconciled to the MAJORITY of the five live copies, not to this
# fixture: `Data handling` sits at position 6, ahead of `Why it works this way`. This fixture IS
# the Intake System handbook, i.e. the 1-of-5 outlier the ordering disagreement was found on, so
# it reports exactly one `section-order` warn, and that warn is the finding rather than a linter
# bug. Asserting the exact count (not merely "no failures") is what stops a regression from
# hiding behind an outlier everybody already expects.
test_projectlint_clean_handbook_reports_only_the_known_order_outlier() {
  local out
  out=$(lint_container "$SCHEMA" handbook "$FXDIR/handbook-intake.md")
  assert_eq "1" "$(echo "$out" | jq 'length')" "exactly one finding on the outlier handbook"
  assert_eq "section-order" "$(echo "$out" | jq -r '.[0].rule')" "and it is the ordering nit"
  assert_eq "data" "$(echo "$out" | jq -r '.[0].id')" "on Data handling, the section the schema moved"
  assert_eq "0" "$(lint_exit_code "$out")" "an ordering nit never blocks"
}

# ---- Case 6 — out-of-order sections warn, don't fail ----

test_projectlint_out_of_order_warns_not_fails() {
  local out
  out=$(lint_container "$SCHEMA" description "$FXDIR/desc-out-of-order.md")
  assert_eq "true" "$(echo "$out" | jq 'any(.[]; .rule=="section-order")')" "order violation reported"
  assert_eq "warn" "$(echo "$out" | jq -r '.[] | select(.rule=="section-order") | .severity' | head -1)" \
    "order is advisory"
  assert_eq "0" "$(lint_exit_code "$out")" "order alone exits 0"
}

# ---- Case 7 — peerCompare: same ----

test_projectlint_peer_same_flags_identical_body() {
  local out
  out=$(lint_peers "$SCHEMA" description \
    "p1:$FXDIR/peers-same/p1.md" "p2:$FXDIR/peers-same/p2.md" "p3:$FXDIR/peers-same/p3.md" \
    "p4:$FXDIR/peers-same/p4.md" "p5:$FXDIR/peers-same/p5.md")
  assert_eq "true" "$(echo "$out" | jq 'any(.[]; .rule=="shared-text" and .id=="steer")')" \
    "an identical Directions body across 5 products is flagged"
  assert_eq "false" "$(echo "$out" | jq 'any(.[]; .id=="pointer")')" "allowlisted pointer is not flagged"
  assert_eq "false" "$(echo "$out" | jq 'any(.[]; .id=="people")')" "allowlisted Stakeholders is not flagged"
  assert_eq "0" "$(lint_exit_code "$out")" "peer findings are advisory"
}

# ---- Case 8 — peerCompare: differ ----

test_projectlint_peer_differ_flags_missing_shared_section() {
  local out
  out=$(lint_peers "$SCHEMA" handbook \
    "h1:$FXDIR/peers-differ/h1.md" "h2:$FXDIR/peers-differ/h2.md" "h3:$FXDIR/peers-differ/h3.md" \
    "h4:$FXDIR/peers-differ/h4.md" "h5:$FXDIR/peers-differ/h5.md")
  assert_eq "true" "$(echo "$out" | jq 'any(.[]; .rule=="missing-peer-section" and .id=="data" and .target=="h5")')" \
    "the handbook missing a shared section is named"
  assert_eq "false" "$(echo "$out" | jq 'any(.[]; .id=="recipe")')" \
    "perProject recipe differing across peers is NOT flagged"
  assert_eq "false" "$(echo "$out" | jq 'any(.[]; .id=="ticketing")')" \
    "perProject Ticketing Strategy differing across peers is NOT flagged"
}

# A heading declared twice must not silently disable the peer rules for that section across the
# WHOLE population. `$bodies` collects every occurrence, and the "present on every peer" guard
# compares that count to the peer count — so one peer carrying the heading twice inflates the
# count and the check no-ops. An operator pasting a section instead of replacing it is all it
# takes. Bodies are deduped to the first occurrence per peer, and the duplicate is reported.
test_projectlint_a_duplicated_heading_does_not_disable_peer_comparison() {
  local out
  out=$(lint_peers "$SCHEMA" handbook \
    "h1:$FXDIR/peers-dup/h1.md" "h2:$FXDIR/peers-dup/h2.md" "h3:$FXDIR/peers-dup/h3.md")
  assert_eq "true" "$(echo "$out" | jq 'any(.[]; .rule=="peer-text-differs" and .id=="data")')" \
    "divergent Data handling is still reported when one peer declares the heading twice"
  assert_eq "h1, h2, h3" "$(echo "$out" | jq -r '.[] | select(.rule=="peer-text-differs") | .target')" \
    "and the peer list is not inflated by the duplicate"
}

test_projectlint_duplicate_heading_is_a_finding_of_its_own() {
  local out
  out=$(lint_container "$SCHEMA" handbook "$FXDIR/peers-dup/h1.md")
  assert_eq "true" "$(echo "$out" | jq 'any(.[]; .rule=="duplicate-heading")')" \
    "the duplication is reported, not left to be inferred from an ordering nit"
  assert_eq "Data handling" "$(echo "$out" | jq -r '.[] | select(.rule=="duplicate-heading") | .heading')" \
    "and the offending heading is named"
  assert_eq "warn" "$(echo "$out" | jq -r '.[] | select(.rule=="duplicate-heading") | .severity')" \
    "advisory — a duplicate is a conformance fact, not a blocking one"
  assert_contains "appears 2 times" \
    "$(echo "$out" | jq -r '.[] | select(.rule=="duplicate-heading") | .message')" \
    "the message states how many times"
}

# jq `inside` is SUBSTRING containment, not element equality: `["Product: Claims"] |
# inside(["Product: Claims & Policies"])` is true. Both peer-membership tests used it, so a peer
# whose name is a prefix of another peer's silently counted as present, and the finding vanished.
# It fails in the under-reporting direction, which is the class this tool exists to prevent.
test_projectlint_peer_membership_is_equality_not_substring() {
  local out
  out=$(lint_peers "$SCHEMA" handbook \
    "Product: Claims & Policies:$FXDIR/peers-substring/full.md" \
    "Beta:$FXDIR/peers-substring/full2.md" \
    "Product: Claims:$FXDIR/peers-substring/short.md")
  assert_eq "true" "$(echo "$out" | jq 'any(.[]; .rule=="missing-peer-section" and .id=="data")')" \
    "the missing section is reported even though one peer name is a prefix of another"
  assert_eq "Product: Claims" "$(echo "$out" | jq -r '.[] | select(.rule=="missing-peer-section") | .target')" \
    "and the right peer is named"
}

# The headline duplication class: five descriptions each carrying a byte-identical section that
# NO container declares. Comparing only schema-declared sections inverts the rule it implements —
# it fires only where the schema already knows the answer, and `freeform` absorbs everything else.
# This is the exact historical incident (`cadence + pass-heartbeat` shipped to five descriptions).
test_projectlint_peer_same_flags_an_undeclared_shared_section() {
  local out
  out=$(lint_peers "$SCHEMA" description \
    "p1:$FXDIR/peers-undeclared/p1.md" "p2:$FXDIR/peers-undeclared/p2.md" \
    "p3:$FXDIR/peers-undeclared/p3.md" "p4:$FXDIR/peers-undeclared/p4.md" \
    "p5:$FXDIR/peers-undeclared/p5.md")
  assert_eq "1" "$(echo "$out" | jq '[.[] | select(.rule=="shared-text")] | length')" "one shared-text finding"
  assert_eq "Operators & cadence" "$(echo "$out" | jq -r '.[0].heading')" \
    "the undeclared heading is named — no container declares it, and it is still compared"
  assert_eq "null" "$(echo "$out" | jq -r '.[0].id')" "with a null id, because the schema has no name for it"
  assert_contains "byte-identical across 5 peers" "$(echo "$out" | jq -r '.[0].message')" \
    "and the message states the evidence"
}

# Widening the comparison must not cost the two exemptions the schema declares. Asserted against
# the same fixtures the narrower rule used, so a regression here is unambiguous.
test_projectlint_widened_peer_comparison_keeps_the_schema_exemptions() {
  local same differ
  same=$(lint_peers "$SCHEMA" description \
    "p1:$FXDIR/peers-same/p1.md" "p2:$FXDIR/peers-same/p2.md" "p3:$FXDIR/peers-same/p3.md" \
    "p4:$FXDIR/peers-same/p4.md" "p5:$FXDIR/peers-same/p5.md")
  assert_eq "false" "$(echo "$same" | jq 'any(.[]; .id=="people")')" \
    "sharedTextAllowlist still exempts Stakeholders under the widened comparison"
  differ=$(lint_peers "$SCHEMA" handbook \
    "h1:$FXDIR/peers-differ/h1.md" "h2:$FXDIR/peers-differ/h2.md" "h3:$FXDIR/peers-differ/h3.md" \
    "h4:$FXDIR/peers-differ/h4.md" "h5:$FXDIR/peers-differ/h5.md")
  assert_eq "false" "$(echo "$differ" | jq 'any(.[]; .id=="recipe" or .id=="ticketing")')" \
    "perProject sections are still exempt under the widened comparison"
}

# ---- Case 9 — a heading no container names suggests nothing ----

test_projectlint_unknown_heading_suggests_nothing() {
  local out
  out=$(lint_container "$SCHEMA" channel "$FXDIR/channel-unknown.md")
  assert_eq "unknown-heading" "$(echo "$out" | jq -r '.[0].rule')" "rule=unknown-heading"
  assert_eq "Escalation Protocol" "$(echo "$out" | jq -r '.[0].heading')" "the heading is echoed back"
  assert_eq "null" "$(echo "$out" | jq -r '.[0].belongsIn')" "belongsIn is null — no guess"
  assert_contains "not named by any container" "$(echo "$out" | jq -r '.[0].message')" \
    "states the fact, offers no opinion"
}

# The derived lookup subsumes the channel-tier machinery list — no `forbidden` array needed.
test_projectlint_channel_machinery_derives_to_handbook() {
  local out
  out=$(lint_container "$SCHEMA" channel "$FXDIR/channel-machinery.md")
  assert_eq "handbook" "$(echo "$out" | jq -r '.[] | select(.heading=="📋 Report template") | .belongsIn')" \
    "report template derives to the handbook"
  # `Other intake inboxes` was RENAMED to `The intake projects`; with no alias list, no container
  # names it any more. The channel container is closed (no freeform), so it is still REPORTED —
  # just without a destination. That is the honest answer, and the cost of zero curated entries.
  assert_eq "null" "$(echo "$out" | jq -r '.[] | select(.heading=="Other intake inboxes") | .belongsIn')" \
    "the renamed inboxes list is reported, but nothing is guessed about where it went"
  assert_eq "unknown-heading" "$(echo "$out" | jq -r '.[] | select(.heading=="Other intake inboxes") | .rule')" \
    "reported as unknown-heading, not silently dropped"
  assert_eq "false" "$(echo "$out" | jq 'any(.[]; .heading=="Directions")')" \
    "a channel's own Directions is not flagged as description machinery"
}

# ---- Exit contract (pure part; the CLI wiring is Chunk C) ----

test_projectlint_exit_code_contract() {
  assert_eq "0" "$(lint_exit_code '[]')" "no findings -> 0"
  assert_eq "0" "$(lint_exit_code '[{"severity":"warn"}]')" "warnings only -> 0"
  assert_eq "1" "$(lint_exit_code '[{"severity":"warn"},{"severity":"fail"}]')" "any failure -> 1"
  assert_eq "2" "$(lint_exit_code '[]' 1)" "unreachable target -> 2"
  assert_eq "2" "$(lint_exit_code '[{"severity":"fail"}]' 1)" "partial coverage outranks failures -> 2"
}

# `jq -e` exits non-zero for "no failures" AND for empty input AND for a parse error, so testing
# only for failures reads a WIPED accumulator as a clean bill of health. Every accumulation step
# rebuilds this string through jq; one failing step and every finding collected so far is gone.
# Failure-open inside the one function whose job is to be failure-closed.
test_projectlint_exit_code_refuses_an_unusable_findings_string() {
  assert_eq "2" "$(lint_exit_code '')" "an empty findings string is could-not-run, not clean"
  assert_eq "2" "$(lint_exit_code 'not json')" "a malformed findings string is could-not-run, not clean"
  assert_eq "2" "$(lint_exit_code 'null')" "null is not a findings array"
  assert_eq "2" "$(lint_exit_code '{"severity":"fail"}')" "a bare object is not a findings array"
  assert_eq "0" "$(lint_exit_code '[]')" "and a genuinely empty array is still clean"
  assert_eq "0" "$(lint_exit_code)" "an omitted argument still defaults to clean"
  # The same reasoning one argument over: `jq 'length'` on a broken envelope prints nothing, and
  # an unreadable unreachable count must not be read as "nothing was unreachable".
  assert_eq "2" "$(lint_exit_code '[]' '')" "an unreadable unreachable count is could-not-run"
  assert_eq "2" "$(lint_exit_code '[]' 'x')" "a non-numeric unreachable count is could-not-run"
}

# Bash 3.2 + set -u: the happy path is exactly when the findings array is empty.
test_projectlint_empty_findings_under_set_u() {
  local out rc
  out=$(set -u; lint_container "$SCHEMA" description "$FXDIR/desc-intake-clean.md" 2>&1); rc=$?
  assert_eq "0" "$rc" "empty-findings path survives set -u (PTF_BASH32_COMPATIBILITY)"
  assert_eq "[]" "$(echo "$out" | jq -c '.')" "emits a valid empty JSON array, not empty output"
}

# Fail loudly, not with a raw jq stack — Chunk C's CLI surfaces these straight to the user.
test_projectlint_bad_inputs_fail_cleanly() {
  local out rc
  out=$(lint_container "$SCHEMA" nope "$FXDIR/desc-no-pointer.md" 2>&1); rc=$?
  assert_eq "1" "$rc" "unknown container exits 1"
  assert_contains "unknown container" "$out" "names the problem, not a jq trace"
  out=$(lint_container "$SCHEMA" description "$TMP_DIR/nope.md" 2>&1); rc=$?
  assert_eq "1" "$rc" "missing input file exits 1"
  assert_contains "no such file" "$out" "names the missing file"
}

# ============================================================================
# CLI surface — cmd_lint, the renderers, and the exit contract (Cases 10–12).
# These drive `project.sh lint` end to end; the Linear reads are replaced by the
# LINEAR_FIXTURE seam, in the documented call order (project → documents → channels).
# ============================================================================

GQLDIR="$FXDIR/graphql"

# A one-project scope pointing at a handbookSlug the documents fixture does NOT contain, so the
# handbook lands in `unreachable` while the description and channel still produce real findings.
_lint_fixture_schema() {
  jq '.scope.projects = [{name: "00000000-0000-4000-8000-000000000001", handbookSlug: "ffffffffffff"}]' \
    "$SCHEMA" > "$TMP_DIR/schema.json"
  printf '%s' "$TMP_DIR/schema.json"
}

# ---- Case 10 — an unreachable target exits 2, even alongside real findings ----

test_projectlint_cli_partial_coverage_exits_2() {
  local schema out rc
  schema=$(_lint_fixture_schema)
  out=$(PROJECT_LINT_REGISTRY=/nonexistent \
        LINEAR_FIXTURE="$GQLDIR/project.json:$GQLDIR/documents-nomatch.json:$GQLDIR/channels-nopointer.json" \
        "$SRC_DIR/project.sh" lint --all --schema "$schema" --json 2>&1); rc=$?
  assert_eq "2" "$rc" "partial coverage exits 2"
  assert_eq "true" "$(echo "$out" | jq 'any(.unreachable[]; .container=="handbook")')" \
    "the unreadable handbook is listed, not silently absent"
  # The point of the case: real findings were produced too, INCLUDING a fail. 2 still outranks 1.
  assert_eq "true" "$(echo "$out" | jq 'any(.findings[]; .severity=="fail")')" "a real failure was also found"
  assert_eq "true" "$(echo "$out" | jq 'any(.findings[]; .rule=="undeclared-heading" and .belongsIn=="handbook")')" \
    "and a real derived warning"
  assert_eq "2" "$(echo "$out" | jq '.exitCode')" "the envelope reports 2, not 1 — an incomplete run is never a bill of health"
}

# The scope <-> registry check is soft by design (a disagreement is a warn), but SILENTLY soft is
# the class exit 2 exists for: an absent registry returned `[]` and was recorded nowhere, so
# relocating the file made the whole check evaporate into a green run. `--all` is the only mode
# that runs it, and it is the mode with no human watching a diff.
test_projectlint_cli_missing_registry_is_could_not_run_not_clean() {
  local schema out rc
  schema=$(_lint_fixture_schema)
  out=$(PROJECT_LINT_REGISTRY=/nonexistent \
        LINEAR_FIXTURE="$GQLDIR/project.json:$GQLDIR/documents-nomatch.json:$GQLDIR/channels-nopointer.json" \
        "$SRC_DIR/project.sh" lint --all --schema "$schema" --json 2>&1); rc=$?
  assert_eq "2" "$rc" "a check that could not run exits 2"
  assert_eq "true" "$(echo "$out" | jq 'any(.unreachable[]; .container=="scope")')" \
    "the skipped drift check is recorded in unreachable"
  assert_contains "registry not found" \
    "$(echo "$out" | jq -r '.unreachable[] | select(.container=="scope") | .reason')" \
    "with a reason naming the missing file"
  assert_eq "0" "$(echo "$out" | jq '[.findings[] | select(.rule=="scope-registry-drift")] | length')" \
    "and it contributes no findings — it did not run"
}

test_projectlint_cli_human_renderer_names_what_it_could_not_check() {
  local schema out
  schema=$(_lint_fixture_schema)
  out=$(PROJECT_LINT_REGISTRY=/nonexistent \
        LINEAR_FIXTURE="$GQLDIR/project.json:$GQLDIR/documents-nomatch.json:$GQLDIR/channels-nopointer.json" \
        "$SRC_DIR/project.sh" lint --all --schema "$schema" 2>&1)
  assert_contains "FAIL" "$out" "failures are rendered as FAIL"
  assert_contains "WARN" "$out" "warnings are rendered as WARN"
  assert_contains "Could not check (2)" "$out" "the unreachable list is rendered, with its count"
  assert_contains "no document with slugId ffffffffffff" "$out" "and its reason"
  assert_contains "unreachable" "$out" "the summary line carries the unreachable count"
}

# ---- `--all` across TWO projects — the peer axis, driven through the CLI ----
#
# Every other peer test calls `lint_peers` directly with colon-free labels (`p1`…`p5`). That is
# structurally the same fixture-reality gap that hid the original last-colon split bug, one layer
# up: the accumulation into `$tmp/peers-<c>.txt`, `peer_count`, and the `<label>:<path>` round trip
# through real Linear project names were exercised by nothing. Both fixture names carry a colon.
#
# 8 GraphQL responses, in the order cmd_lint issues them: per project, resolve-by-name → project →
# documents → channels. A ninth call would exhaust the list and fail loudly.
ALLDIR="$GQLDIR/all"
_lint_all_fixtures() {
  printf '%s' "$ALLDIR/alpha-resolve.json:$ALLDIR/alpha-project.json:$ALLDIR/alpha-documents.json:$ALLDIR/alpha-channels.json:$ALLDIR/beta-resolve.json:$ALLDIR/beta-project.json:$ALLDIR/beta-documents.json:$ALLDIR/beta-channels.json"
}

# A two-project scope whose names both contain a colon. Derived from the shipped schema so the
# container rules under test stay in step with the real ones; only `scope` is replaced.
_lint_all_schema() {
  jq '.scope.projects = [{name: "Product: Alpha", handbookSlug: "aaa000000001"},
                         {name: "Product: Beta",  handbookSlug: "bbb000000002"}]' \
    "$SCHEMA" > "$TMP_DIR/all-schema.json"
  printf '%s' "$TMP_DIR/all-schema.json"
}

_lint_run_all() {
  PROJECT_LINT_REGISTRY="$FXDIR/registry-2proj.md" LINEAR_FIXTURE="$(_lint_all_fixtures)" \
    "$SRC_DIR/project.sh" lint --all --schema "$1" --json 2>&1
}

test_projectlint_cli_all_two_projects_compares_peers() {
  local out rc
  out=$(_lint_run_all "$(_lint_all_schema)"); rc=$?
  assert_eq "0" "$rc" "a warning-only --all run exits 0"
  assert_eq "0" "$(echo "$out" | jq '.unreachable | length')" "nothing unreachable — every container read"
  assert_eq "6" "$(echo "$out" | jq '.checked | length')" "2 projects x (description + handbook + channel)"
  assert_eq "true" "$(echo "$out" | jq '.peerCompared')" "the peer comparison ran"
  assert_eq "2" "$(echo "$out" | jq '.peerCount')" "across both projects"
  assert_eq "null" "$(echo "$out" | jq '.peerSkipped')" "so no skip reason is emitted"
}

# The colon split, asserted where it actually runs. `<label>:<path>` is split at the LAST colon;
# splitting at the first would label these peers `Product` and `Product`.
test_projectlint_cli_all_keeps_colon_bearing_project_names_whole() {
  local out
  out=$(_lint_run_all "$(_lint_all_schema)")
  assert_eq "true" "$(echo "$out" | jq 'any(.checked[]; .target=="Product: Alpha")')" \
    "the description target is the whole project name"
  assert_eq "true" "$(echo "$out" | jq 'any(.checked[]; .target=="Product: Beta · Inbox Handbook")')" \
    "and non-description targets are qualified by the whole project name"
  assert_eq "Product: Alpha, Product: Beta" \
    "$(echo "$out" | jq -r '.findings[] | select(.rule=="shared-text" and .id=="steer") | .target')" \
    "the peer finding names both peers, uncut"
}

# F7 end to end: the undeclared section is invisible to every container lint (freeform absorbs it)
# and is caught only by the peer axis. Both halves are asserted, because the first is what makes
# the second the ONLY thing standing between five descriptions and silent re-bloat.
test_projectlint_cli_all_flags_an_undeclared_section_shared_across_projects() {
  local out
  out=$(_lint_run_all "$(_lint_all_schema)")
  assert_eq "true" \
    "$(echo "$out" | jq 'any(.findings[]; .rule=="shared-text" and .heading=="Operators & cadence")')" \
    "an identical section no container declares is flagged across projects"
  assert_eq "null" \
    "$(echo "$out" | jq -r '.findings[] | select(.heading=="Operators & cadence") | .id')" \
    "with no schema id, because the schema does not name it"
  assert_eq "0" \
    "$(echo "$out" | jq '[.findings[] | select(.container=="description" and .rule!="shared-text")] | length')" \
    "and no container-level rule saw it at all — freeform absorbed it silently"
}

# A peer comparison that DIED must never render as one that ran clean. Forced by a schema whose
# `sharedTextAllowlist` is a number: it fails the peer jq and nothing else, which is what makes
# this test about the peer accumulation path specifically rather than about a broken schema.
test_projectlint_cli_all_failed_peer_comparison_is_never_reported_as_clean() {
  local schema out rc
  schema="$TMP_DIR/all-badpeers.json"
  jq '.scope.projects = [{name: "Product: Alpha", handbookSlug: "aaa000000001"},
                         {name: "Product: Beta",  handbookSlug: "bbb000000002"}]
      | .containers.description.sharedTextAllowlist = 123
      | .containers.handbook.sharedTextAllowlist = 123' "$SCHEMA" > "$schema"
  out=$(_lint_run_all "$schema"); rc=$?
  assert_eq "2" "$rc" "a comparison that could not run exits 2"
  assert_eq "false" "$(echo "$out" | jq '.peerCompared')" "peerCompared stays false"
  assert_eq "0" "$(echo "$out" | jq '.peerCount')" "and no peer count is claimed"
  assert_eq "true" "$(echo "$out" | jq 'any(.unreachable[]; .container=="peer:description")')" \
    "the failed description comparison is recorded in unreachable"
  assert_eq "true" "$(echo "$out" | jq 'any(.unreachable[]; .container=="peer:handbook")')" \
    "and so is the handbook one"
  assert_contains "every peer comparison failed" "$(echo "$out" | jq -r '.peerSkipped')" \
    "the skip reason says the comparison failed, not that there were too few peers"
}

test_projectlint_cli_all_failed_peer_comparison_is_not_rendered_as_ran_across() {
  local schema out
  schema="$TMP_DIR/all-badpeers2.json"
  jq '.scope.projects = [{name: "Product: Alpha", handbookSlug: "aaa000000001"},
                         {name: "Product: Beta",  handbookSlug: "bbb000000002"}]
      | .containers.description.sharedTextAllowlist = 123
      | .containers.handbook.sharedTextAllowlist = 123' "$SCHEMA" > "$schema"
  out=$(PROJECT_LINT_REGISTRY="$FXDIR/registry-2proj.md" LINEAR_FIXTURE="$(_lint_all_fixtures)" \
        "$SRC_DIR/project.sh" lint --all --schema "$schema" 2>&1)
  assert_not_contains "ran across" "$out" "a comparison that failed is never rendered as one that ran"
  assert_contains "Peer comparison: SKIPPED" "$out" "it is rendered as skipped"
  assert_contains "Could not check" "$out" "and it appears in the could-not-check list"
}

# ---- Case 11 — --stdin skips peer comparison rather than reporting it clean ----

test_projectlint_cli_stdin_skips_peer_comparison() {
  local out rc
  out=$(printf 'Lead.\n\nProse one.\nProse two.\n\n## Ticketing Strategy\n\nx\n\n> 📘 [**How this project'"'"'s inbox works**](<https://x>) — y.\n' \
        | "$SRC_DIR/project.sh" lint --stdin --container description --json 2>&1); rc=$?
  assert_eq "0" "$rc" "a warning-only stdin lint exits 0"
  assert_eq "false" "$(echo "$out" | jq '.peerCompared')" "peer comparison did NOT run"
  assert_eq "false" "$(echo "$out" | jq '.peerSkipped == null')" "and the reason is stated, not left null"
  assert_contains "no peers" "$(echo "$out" | jq -r '.peerSkipped')" "the reason names the absence of peers"
  assert_eq "0" "$(echo "$out" | jq '.peerCount')" "zero peers compared"
  assert_eq "true" "$(echo "$out" | jq 'any(.findings[]; .rule=="undeclared-heading")')" \
    "the container rules still ran"
}

test_projectlint_cli_stdin_never_prints_a_clean_peer_result() {
  local out
  out=$(printf 'Lead.\n\nProse one.\nProse two.\n\n> 📘 [**x**](<https://x>) — y.\n' \
        | "$SRC_DIR/project.sh" lint --stdin --container description 2>&1)
  assert_contains "Peer comparison: SKIPPED" "$out" "a comparison that never ran is reported as skipped"
  assert_not_contains "ran across" "$out" "and never as a clean comparison"
}

# ---- The exit contract at the CLI boundary ----

test_projectlint_cli_exit_contract() {
  local rc
  printf 'Lead.\n\nProse one.\nProse two.\n\n> 📘 [**x**](<https://x>) — y.\n' \
    | "$SRC_DIR/project.sh" lint --stdin --container description >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "clean -> 0"
  printf 'Lead.\n\nProse one.\nProse two.\n\n## Ticketing Strategy\n\nx\n\n> 📘 [**x**](<https://x>) — y.\n' \
    | "$SRC_DIR/project.sh" lint --stdin --container description --strict >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "a failure -> 1"
  printf 'Lead only.\n' | "$SRC_DIR/project.sh" lint --stdin --container description >/dev/null 2>&1; rc=$?
  assert_eq "1" "$rc" "a missing required section -> 1"
  "$SRC_DIR/project.sh" lint >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "could-not-run (no mode selected) -> 2"
  "$SRC_DIR/project.sh" lint --stdin >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "could-not-run (--stdin without --container) -> 2"
  "$SRC_DIR/project.sh" lint --all --schema "$TMP_DIR/absent.json" >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "could-not-run (no such schema) -> 2"
  "$SRC_DIR/project.sh" lint --bogus-flag >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "could-not-run (unknown flag) -> 2"
}

# `lint` must be dispatched by the engine command, never by a script path (¶INV_ENGINE_COMMAND_DISPATCH).
test_projectlint_cli_is_dispatched() {
  assert_contains "lint)" "$(grep -A6 '^# ---- Dispatch ----' "$SRC_DIR/project.sh")" \
    "project.sh dispatches the lint subcommand"
  assert_contains "engine project lint" "$("$SRC_DIR/project.sh" --help 2>&1)" \
    "and advertises it in usage"
}

# ---- schema.scope <-> INBOX_REGISTRY.md agreement ----
# Two hand-maintained copies of the same five names is the duplication class this command exists
# to catch. They stay separate (rule vs navigation cache) but they are compared.

# Driven through the public CLI: an unresolvable fixture makes every project unreachable, so the
# run reaches the drift check with no network and no key.
_lint_scope_drift_findings() {
  LINEAR_FIXTURE="$TMP_DIR/no-such-fixture.json" "$SRC_DIR/project.sh" lint --all --schema "$1" --json 2>/dev/null \
    | jq '[.findings[] | select(.rule=="scope-registry-drift")]'
}

test_projectlint_scope_and_registry_agree_today() {
  local drift
  drift=$(_lint_scope_drift_findings "$SCHEMA")
  assert_eq "0" "$(echo "$drift" | jq 'length')" \
    "the shipped schema.scope and INBOX_REGISTRY.md name the same projects and the same handbook slugs"
}

test_projectlint_scope_drift_is_detected_when_it_exists() {
  local schema drift
  schema="$TMP_DIR/drifted.json"
  jq '.scope.projects += [{name: "Product: Ghost", handbookSlug: "deadbeefcafe"}]' "$SCHEMA" > "$schema"
  drift=$(_lint_scope_drift_findings "$schema")
  assert_eq "true" "$(echo "$drift" | jq 'any(.[]; .target=="Product: Ghost")')" \
    "a project the registry does not know is flagged"
  assert_eq "2" "$(echo "$drift" | jq '[.[] | select(.target=="Product: Ghost")] | length')" \
    "both the missing `## ` section AND the unknown handbookSlug are reported"
  assert_eq "warn" "$(echo "$drift" | jq -r '.[0].severity')" \
    "drift is advisory — the two files stay separate on purpose (rule vs navigation cache)"
}

test_projectlint_scope_drift_does_not_leak_into_other_modes() {
  local out
  out=$(printf 'Lead.\n\nProse one.\nProse two.\n\n> 📘 [**x**](<https://x>) — y.\n' \
        | "$SRC_DIR/project.sh" lint --stdin --container description --json 2>&1)
  assert_eq "0" "$(echo "$out" | jq '[.findings[] | select(.rule=="scope-registry-drift")] | length')" \
    "--stdin lints the text it was handed, nothing else"
}

# ---- Case 12 (opt-in, live) — the GraphQL selections still return the expected shape ----
# LINT_LIVE=1 only. This is the liveness check that keeps the suite from being shape-only.

test_projectlint_live_shape() {
  if [ "${LINT_LIVE:-}" != "1" ]; then
    assert_eq "skip" "skip" "Case 12 skipped (set LINT_LIVE=1 to run against live Linear)"
    return 0
  fi
  # LINEAR_API_KEY must be EXPORTED, not left in a repo .env: _load_key's .env lookup is relative
  # to the CWD, and the runner's CWD is the scripts dir. Refusing here beats a confusing red.
  if [ -z "${LINEAR_API_KEY:-}" ]; then
    assert_eq "skip" "skip" "Case 12 needs LINEAR_API_KEY exported (a repo .env is not on the runner's CWD)"
    return 0
  fi
  local out
  out=$("$SRC_DIR/project.sh" lint "Product: Intake System" --json 2>&1)
  assert_eq "true" "$(echo "$out" | jq 'any(.checked[]; .container=="description")')" "description read live"
  assert_eq "true" "$(echo "$out" | jq 'any(.checked[]; .container=="handbook")')" "handbook resolved by slugId live"
  assert_eq "true" "$(echo "$out" | jq 'any(.checked[]; .container=="channel")')" "channel tickets read live"
  assert_eq "0" "$(echo "$out" | jq '.unreachable | length')" "nothing unreachable on a healthy project"
  assert_eq "false" "$(echo "$out" | jq 'any(.findings[]; .rule=="missing-required" and .id=="pointer")')" \
    "the 📘 pointer rule does not fire on live, correct content"
}

run_discovered_tests
