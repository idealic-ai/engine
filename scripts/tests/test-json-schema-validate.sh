#!/usr/bin/env bash
# Tests for tools/json-schema-validate
set -euo pipefail

# --- Sandbox Setup ---
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

TOOL_DIR="$HOME/.claude/engine/tools/json-schema-validate"
VALIDATE="$TOOL_DIR/validate.sh"

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_contains() {
  local desc="$1" pattern="$2" stderr_file="$3"
  if grep -q "$pattern" "$stderr_file" 2>/dev/null; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (stderr missing: $pattern)"
    echo "    stderr was: $(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
  fi
}

# --- Test Schemas ---
SCHEMA_OBJ="$TMPDIR_BASE/schema-obj.json"
cat > "$SCHEMA_OBJ" <<'SCHEMA'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "name": { "type": "string", "description": "A name" },
    "count": { "type": "number", "description": "A count" },
    "active": { "type": "boolean", "description": "Is active" }
  },
  "required": ["name", "count"],
  "additionalProperties": false
}
SCHEMA

# --- Tests ---

echo "=== Unit Tests: json-schema-validate ==="

# 1. Valid instance
echo ""
echo "--- valid instance ---"
INST="$TMPDIR_BASE/valid.json"
echo '{"name": "test", "count": 42}' > "$INST"
STDERR="$TMPDIR_BASE/stderr1"
"$VALIDATE" "$SCHEMA_OBJ" "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "accepts valid JSON" 0 "$EC"

# 2. Valid instance with optional field
echo ""
echo "--- valid instance with optional boolean ---"
INST="$TMPDIR_BASE/valid-opt.json"
echo '{"name": "test", "count": 42, "active": true}' > "$INST"
STDERR="$TMPDIR_BASE/stderr2"
"$VALIDATE" "$SCHEMA_OBJ" "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "accepts valid JSON with optional field" 0 "$EC"

# 3. Wrong type — string where number expected
echo ""
echo "--- wrong type (string for number) ---"
INST="$TMPDIR_BASE/wrong-type.json"
echo '{"name": "test", "count": "not-a-number"}' > "$INST"
STDERR="$TMPDIR_BASE/stderr3"
"$VALIDATE" "$SCHEMA_OBJ" "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "rejects wrong type" 1 "$EC"
assert_stderr_contains "error mentions /count" "count" "$STDERR"

# 4. Missing required field
echo ""
echo "--- missing required field ---"
INST="$TMPDIR_BASE/missing-req.json"
echo '{"name": "test"}' > "$INST"
STDERR="$TMPDIR_BASE/stderr4"
"$VALIDATE" "$SCHEMA_OBJ" "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "rejects missing required" 1 "$EC"
assert_stderr_contains "error mentions required property" "required" "$STDERR"

# 5. Additional properties rejected
echo ""
echo "--- additional properties ---"
INST="$TMPDIR_BASE/extra-prop.json"
echo '{"name": "test", "count": 42, "extra": "bad"}' > "$INST"
STDERR="$TMPDIR_BASE/stderr5"
"$VALIDATE" "$SCHEMA_OBJ" "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "rejects additional properties" 1 "$EC"
assert_stderr_contains "error mentions additionalProperties" "additional" "$STDERR"

# 6. Wrong type — boolean where string expected
echo ""
echo "--- wrong type (boolean for string) ---"
INST="$TMPDIR_BASE/wrong-bool.json"
echo '{"name": true, "count": 42}' > "$INST"
STDERR="$TMPDIR_BASE/stderr6"
"$VALIDATE" "$SCHEMA_OBJ" "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "rejects boolean where string expected" 1 "$EC"
assert_stderr_contains "error mentions /name" "name" "$STDERR"

# 7. Schema from stdin
echo ""
echo "--- schema from stdin ---"
INST="$TMPDIR_BASE/stdin-valid.json"
echo '{"x": true}' > "$INST"
STDERR="$TMPDIR_BASE/stderr7"
echo '{"type":"object","properties":{"x":{"type":"boolean"}},"required":["x"]}' | \
  "$VALIDATE" --schema-stdin "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "validates with schema from stdin" 0 "$EC"

# 8. Schema from stdin — invalid instance
echo ""
echo "--- schema from stdin (invalid) ---"
INST="$TMPDIR_BASE/stdin-invalid.json"
echo '{"x": "not-bool"}' > "$INST"
STDERR="$TMPDIR_BASE/stderr8"
echo '{"type":"object","properties":{"x":{"type":"boolean"}},"required":["x"]}' | \
  "$VALIDATE" --schema-stdin "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "rejects invalid with schema from stdin" 1 "$EC"

# 9. Empty object against schema requiring fields
echo ""
echo "--- empty object against required fields ---"
INST="$TMPDIR_BASE/empty.json"
echo '{}' > "$INST"
STDERR="$TMPDIR_BASE/stderr9"
"$VALIDATE" "$SCHEMA_OBJ" "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "rejects empty object" 1 "$EC"

# 10. Nested object validation
echo ""
echo "--- nested object ---"
SCHEMA_NESTED="$TMPDIR_BASE/schema-nested.json"
cat > "$SCHEMA_NESTED" <<'SCHEMA'
{
  "type": "object",
  "properties": {
    "proof": {
      "type": "object",
      "properties": {
        "filed": { "type": "boolean" }
      },
      "required": ["filed"]
    }
  },
  "required": ["proof"]
}
SCHEMA
INST="$TMPDIR_BASE/nested-valid.json"
echo '{"proof": {"filed": true}}' > "$INST"
STDERR="$TMPDIR_BASE/stderr10"
"$VALIDATE" "$SCHEMA_NESTED" "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "accepts valid nested object" 0 "$EC"

INST="$TMPDIR_BASE/nested-invalid.json"
echo '{"proof": {"filed": "yes"}}' > "$INST"
STDERR="$TMPDIR_BASE/stderr10b"
"$VALIDATE" "$SCHEMA_NESTED" "$INST" 2>"$STDERR" && EC=0 || EC=$?
assert_exit "rejects wrong type in nested object" 1 "$EC"

# --- Integration Tests: CMD proof schema extraction + validation ---
echo ""
echo "=== Integration Tests: CMD proof schema + session.sh ==="

# 11. Validate a converted CMD proof schema from disk
echo ""
echo "--- CMD proof schema from disk ---"
CMD_FILE="$HOME/.claude/engine/.directives/commands/CMD_INTERROGATE.md"
if [ -f "$CMD_FILE" ]; then
  SCHEMA_FROM_CMD=$(awk '/## PROOF FOR/,0{if(/```json/){f=1;next}if(/```/){f=0;next}if(f)print}' "$CMD_FILE")
  echo "$SCHEMA_FROM_CMD" > "$TMPDIR_BASE/cmd-schema.json"
  INST="$TMPDIR_BASE/cmd-valid.json"
  echo '{"depth_chosen": "Short", "rounds_completed": 3}' > "$INST"
  STDERR="$TMPDIR_BASE/stderr11"
  "$VALIDATE" "$TMPDIR_BASE/cmd-schema.json" "$INST" 2>"$STDERR" && EC=0 || EC=$?
  assert_exit "CMD_INTERROGATE schema accepts valid proof" 0 "$EC"

  INST="$TMPDIR_BASE/cmd-invalid.json"
  echo '{"depth_chosen": 42, "rounds_completed": "not-a-number"}' > "$INST"
  STDERR="$TMPDIR_BASE/stderr11b"
  "$VALIDATE" "$TMPDIR_BASE/cmd-schema.json" "$INST" 2>"$STDERR" && EC=0 || EC=$?
  assert_exit "CMD_INTERROGATE schema rejects wrong types" 1 "$EC"
else
  echo "  (skipped — CMD_INTERROGATE.md not found)"
fi

# 12. Validate §CMD_PARSE_PARAMETERS schema from disk
echo ""
echo "--- session params schema from disk ---"
PARAMS_CMD="$HOME/.claude/engine/.directives/commands/CMD_PARSE_PARAMETERS.md"
if [ -f "$PARAMS_CMD" ]; then
  PARAMS_SCHEMA=$(awk '/```json/{f=1;next}/```/{if(f){f=0;exit}}f' "$PARAMS_CMD")
  echo "$PARAMS_SCHEMA" > "$TMPDIR_BASE/params-schema.json"
  INST="$TMPDIR_BASE/params-valid.json"
  cat > "$INST" <<'INST_EOF'
{
  "taskSummary": "test",
  "scope": "test scope",
  "directoriesOfInterest": ["src/"],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": "none"
}
INST_EOF
  STDERR="$TMPDIR_BASE/stderr12"
  "$VALIDATE" "$TMPDIR_BASE/params-schema.json" "$INST" 2>"$STDERR" && EC=0 || EC=$?
  assert_exit "params schema accepts valid session params" 0 "$EC"

  INST="$TMPDIR_BASE/params-missing.json"
  echo '{"taskSummary": "test"}' > "$INST"
  STDERR="$TMPDIR_BASE/stderr12b"
  "$VALIDATE" "$TMPDIR_BASE/params-schema.json" "$INST" 2>"$STDERR" && EC=0 || EC=$?
  assert_exit "params schema rejects missing required fields" 1 "$EC"

  INST="$TMPDIR_BASE/params-wrongtype.json"
  echo '{"taskSummary": "test", "scope": "s", "directoriesOfInterest": "not-array", "contextPaths": [], "requestFiles": [], "extraInfo": ""}' > "$INST"
  STDERR="$TMPDIR_BASE/stderr12c"
  "$VALIDATE" "$TMPDIR_BASE/params-schema.json" "$INST" 2>"$STDERR" && EC=0 || EC=$?
  assert_exit "params schema rejects wrong type (string for array)" 1 "$EC"
else
  echo "  (skipped — CMD_PARSE_PARAMETERS.md not found)"
fi

# 13. Nullable fields (template paths accept null)
echo ""
echo "--- nullable fields ---"
if [ -f "$PARAMS_CMD" ]; then
  INST="$TMPDIR_BASE/params-null.json"
  cat > "$INST" <<'INST_EOF'
{
  "taskSummary": "test",
  "scope": "test",
  "directoriesOfInterest": [],
  "contextPaths": [],
  "requestFiles": [],
  "extraInfo": null,
  "planTemplate": null,
  "logTemplate": null
}
INST_EOF
  STDERR="$TMPDIR_BASE/stderr13"
  "$VALIDATE" "$TMPDIR_BASE/params-schema.json" "$INST" 2>"$STDERR" && EC=0 || EC=$?
  assert_exit "params schema accepts null for nullable fields" 0 "$EC"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
