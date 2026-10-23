#!/bin/bash
# tests/test-brief-capability.sh — Tests for pre-tool-use-brief-capability.sh hook
#
# The hook enforces ¶INV_BRIEF_MATCHES_THE_AGENT: a dispatch whose brief mandates a file
# write to an agent type with no Write/Edit tool is REFUSED before the agent starts.
#
# Test groups:
#   N1-N6  non-dispatch tools and write-capable agent types pass untouched
#   A1-A4  an Explore/Plan brief that demands nothing of a file passes (the other-way control:
#          the guard does not refuse every read-only dispatch)
#   R1-R13 the refusal — a mandated write to a write-incapable type is denied, and the
#          refusal names the mandated action AND the missing capability
#   G1-G4  negation and hedging do not count as a demand (false-positive guards)
#   F1-F8  field-realistic read-only briefs pass, a real file demand does not, and the quoted
#          line survives multibyte truncation as valid JSON
#
# The hook under test is resolved from THIS FILE's tree, not from $HOME, so the test
# exercises the worktree it lives in rather than whatever is installed.
#
# Run: bash scripts/tests/test-brief-capability.sh

set -uo pipefail
source "$(dirname "$0")/test-helpers.sh"

ENGINE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ENGINE_ROOT/hooks/pre-tool-use-brief-capability.sh"

# run_hook TOOL_NAME SUBAGENT_TYPE PROMPT
# An empty SUBAGENT_TYPE omits the key entirely (the default-agent dispatch shape).
run_hook() {
  local tool_name="$1" subagent_type="$2" prompt="$3"
  jq -n --arg t "$tool_name" --arg s "$subagent_type" --arg p "$prompt" \
    '{tool_name:$t, tool_input:({prompt:$p} + (if $s == "" then {} else {subagent_type:$s} end))}' \
    | "$HOOK" 2>/dev/null
}

echo "======================================"
echo "Brief-Matches-The-Agent Hook Tests"
echo "======================================"
echo ""

if [ ! -x "$HOOK" ]; then
  fail "hook exists and is executable" "$HOOK executable" "missing or not executable"
fi

# A brief that unambiguously mandates a file write — the shape of the measured instance.
WRITE_BRIEF='[SWEEPFILES] You are thread SWEEPFILES in a /loom weave.

## Your deliverable
Write your findings to `builds/sweep-files.md` as you establish them.

## Your last act
Hand back with the path.'

READ_BRIEF='[SCOPE] You are thread SCOPE in a /loom weave.

Establish which modules own the dispatch path. Read the sources you need.
Report your findings in your hand-back — ranked, with a path and a line number each.
Do not summarise anything you have not read.'

# --- N. Non-dispatch tools and write-capable types pass ---
echo "--- N. Pass-through ---"

OUT=$(run_hook "Bash" "" "write your findings to builds/x.md")
assert_contains '"allow"' "$OUT" "N1: Bash is not a dispatch tool"

OUT=$(run_hook "Write" "" "anything")
assert_contains '"allow"' "$OUT" "N2: Write is not a dispatch tool"

OUT=$(run_hook "Agent" "builder" "$WRITE_BRIEF")
assert_contains '"allow"' "$OUT" "N3: builder can write — mandated write allowed"

OUT=$(run_hook "Agent" "general-purpose" "$WRITE_BRIEF")
assert_contains '"allow"' "$OUT" "N4: general-purpose can write — mandated write allowed"

OUT=$(run_hook "Agent" "" "$WRITE_BRIEF")
assert_contains '"allow"' "$OUT" "N5: no subagent_type (default agent) — allowed"

OUT=$(run_hook "Agent" "fork" "$WRITE_BRIEF")
assert_contains '"allow"' "$OUT" "N6: fork inherits the parent's tools — allowed"

echo ""

# --- A. Read-only types with no file demand pass (the other-way control) ---
echo "--- A. Read-only dispatch with no file demand ---"

OUT=$(run_hook "Agent" "Explore" "$READ_BRIEF")
assert_contains '"allow"' "$OUT" "A1: Explore + prose-only report brief allowed"

OUT=$(run_hook "Agent" "Plan" "$READ_BRIEF")
assert_contains '"allow"' "$OUT" "A2: Plan + prose-only report brief allowed"

OUT=$(run_hook "Agent" "Explore" "Read builds/sweep-findings.md and tell me what it claims.")
assert_contains '"allow"' "$OUT" "A3: Explore + read-a-path brief allowed"

OUT=$(run_hook "Agent" "Explore" "Return the answer in your hand-back. No file is involved.")
assert_contains '"allow"' "$OUT" "A4: Explore + no path at all allowed"

echo ""

# --- R. The refusal ---
echo "--- R. Refusal: brief mandates a write the agent cannot perform ---"

OUT=$(run_hook "Agent" "Explore" "$WRITE_BRIEF")
assert_contains '"deny"' "$OUT" "R1: Explore + mandated write is REFUSED"
assert_contains 'builds/sweep-files.md' "$OUT" "R2: refusal names the mandated action (the path)"
assert_contains 'Write' "$OUT" "R3: refusal names the missing capability"
assert_contains 'Explore' "$OUT" "R4: refusal names the agent type"
assert_contains 'brief-capability' "$OUT" "R5: refusal names the guard"

OUT=$(run_hook "Task" "Explore" "$WRITE_BRIEF")
assert_contains '"deny"' "$OUT" "R6: the Task tool name is also a dispatch"

OUT=$(run_hook "Agent" "Plan" "$WRITE_BRIEF")
assert_contains '"deny"' "$OUT" "R7: Plan also lacks Write"

OUT=$(run_hook "Agent" "explore" "$WRITE_BRIEF")
assert_contains '"deny"' "$OUT" "R8: agent type match is case-insensitive"

OUT=$(run_hook "Agent" "Explore" 'Append your notes to the shared log with `engine log sessions/x/LOG.md`.')
assert_contains '"deny"' "$OUT" "R9: an engine log instruction is a mandated write"

OUT=$(run_hook "Agent" "Explore" 'Use the Write tool to land the report.')
assert_contains '"deny"' "$OUT" "R10: naming the Write tool is a mandated write"

OUT=$(run_hook "Agent" "Explore" 'Emit the table with `cat > /tmp/out.txt <<EOF`.')
assert_contains '"deny"' "$OUT" "R11: a shell redirect instruction is a mandated write"

OUT=$(run_hook "Agent" "Explore" 'Your deliverable file is `builds/IDE165.md` — fill it as you go.')
assert_contains '"deny"' "$OUT" "R12: a named deliverable file is a mandated write"
assert_contains 'builds/IDE165.md' "$OUT" "R13: refusal names that path"

echo ""

# --- G. Negation and hedging are not demands ---
echo "--- G. False-positive guards ---"

OUT=$(run_hook "Agent" "Explore" 'You are read-only. Do NOT write to builds/sweep-files.md.')
assert_contains '"allow"' "$OUT" "G1: an explicit prohibition is not a demand"

OUT=$(run_hook "Agent" "Explore" 'You cannot write to notes.md, so hand the content back instead.')
assert_contains '"allow"' "$OUT" "G2: 'cannot write' is not a demand"

OUT=$(run_hook "Agent" "Explore" 'Never create a report.md — findings go in the hand-back.')
assert_contains '"allow"' "$OUT" "G3: 'never create' is not a demand"

OUT=$(run_hook "Agent" "Explore" 'You may optionally save a copy to /tmp/scratch.md if it helps.')
assert_contains '"allow"' "$OUT" "G4: an optional write is not a mandate"

echo ""

# --- F. Field-realistic read-only briefs must pass ---
# The precision claim is only worth what these cost: four briefs of the shape a conductor
# actually hands an Explore lane, none of which demands a file.
echo "--- F. Field-realistic read-only briefs ---"

OUT=$(run_hook "Agent" "Explore" 'Read scripts/lib.sh and tell me what hook_deny writes to stdout.')
assert_contains '"allow"' "$OUT" "F1: a write verb AFTER the path is a reading, not a demand"

OUT=$(run_hook "Agent" "Explore" 'Sweep skills/ for dispatch instructions. Rank them in your hand-back with path:line.')
assert_contains '"allow"' "$OUT" "F2: sweep-and-report-back allowed"

OUT=$(run_hook "Agent" "Explore" 'Open guards.json and summarise which rules can block. Do not edit it.')
assert_contains '"allow"' "$OUT" "F3: read a file under an explicit prohibition allowed"

OUT=$(run_hook "Agent" "Explore" 'Quote the matching lines from .directives/INVARIANTS.md in your reply.')
assert_contains '"allow"' "$OUT" "F4: quote-back-in-your-reply allowed"

OUT=$(run_hook "Agent" "Explore" 'Write the ranked list into builds/scope.md as you establish each row.')
assert_contains '"deny"' "$OUT" "F5: and the same lane with a real file demand is still refused"

# A real brief is full of multibyte characters. A byte-wise truncation of the quoted line
# splits one in half and the refusal comes out mojibake, so the quote is sliced by codepoint.
LONG_TAIL=$(printf 'é%.0s' $(seq 1 300))
OUT=$(run_hook "Agent" "Explore" "Write your findings to builds/x.md — the ⛔ deliverable for Zoë, naïve café $LONG_TAIL")
assert_contains '"deny"' "$OUT" "F6: a multibyte brief is still refused"
printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 \
  && pass "F7: the refusal is valid JSON after truncating a multibyte line" \
  || fail "F7: the refusal is valid JSON after truncating a multibyte line" "parseable JSON" "$OUT"
assert_contains 'café' "$OUT" "F8: multibyte characters survive the quote intact"

echo ""
exit_with_results
