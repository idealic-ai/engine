#!/bin/bash
# tests/test-intake-sh.sh — Tests for intake.sh (manifest parse, doctor red-green,
# .env.example generation + manifest agreement, setup dry-run).
# Run: bash ~/.claude/engine/scripts/tests/test-intake-sh.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

INTAKE_SH="$HOME/.claude/engine/scripts/intake.sh"
MANIFEST="$HOME/.claude/engine/skills/intake/assets/CREDENTIALS.manifest"

WORK=$(mktemp -d)
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && /bin/rm -rf "$WORK"; }
trap cleanup EXIT

strip() { sed 's/\x1b\[[0-9;]*m//g'; }

# A fully-Connected mcp-list stub so MCP req rows pass unless a test overrides it.
MCP_ALL_CONNECTED=$'notion: https://mcp.notion.com/mcp (HTTP) - ✔ Connected\nlinear-server: https://mcp.linear.app/mcp (HTTP) - ✔ Connected'

# ── 1. Manifest exists and parses (pipe-delimited, 8 fields, no bad rows) ──
echo "Test 1: manifest parse"
if [ -f "$MANIFEST" ]; then
  pass "manifest file exists"
else
  fail "manifest file exists" "$MANIFEST" "missing"
fi
BAD=$(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" | awk -F'|' 'NF!=8 {print NR": "NF" fields"}')
if [ -z "$BAD" ]; then
  pass "every manifest row has exactly 8 pipe-delimited fields"
else
  fail "every manifest row has 8 fields" "8 fields each" "$BAD"
fi
# The two REQUIRED rows the plan mandates.
if grep -qE '^SLACK_INTAKE_TOKEN\|.*\|req\|true\|' "$MANIFEST"; then
  pass "SLACK_INTAKE_TOKEN is req + secret"
else
  fail "SLACK_INTAKE_TOKEN is req + secret" "req|true" "not found"
fi
if grep -qE '^linear-server\|.*\|req\|.*\|mcp:linear-server$' "$MANIFEST"; then
  pass "linear-server is a req mcp check"
else
  fail "linear-server is a req mcp check" "req … mcp:linear-server" "not found"
fi

# ── 2. env-example generation ──
echo "Test 2: env-example generation"
GEN=$("$INTAKE_SH" env-example)
if printf '%s' "$GEN" | grep -qE '^SLACK_INTAKE_TOKEN=$'; then
  pass "secret row emitted with EMPTY value"
else
  fail "secret row emitted empty" "SLACK_INTAKE_TOKEN=" "$(printf '%s' "$GEN" | grep SLACK_INTAKE_TOKEN)"
fi
if printf '%s' "$GEN" | grep -qE '^AWS_REGION=us-east-2$'; then
  pass "non-secret default filled (AWS_REGION=us-east-2)"
else
  fail "non-secret default filled" "AWS_REGION=us-east-2" "$(printf '%s' "$GEN" | grep AWS_REGION)"
fi
# MCP / binary / note rows are NOT dotfile keys → never emitted as KEY= lines.
for nonkey in linear-server BIN_AWS POSTHOG FINCH_DB_RO_SECRET; do
  if printf '%s' "$GEN" | grep -qE "^${nonkey}="; then
    fail "non-env row '$nonkey' excluded from env-example" "no ${nonkey}= line" "present"
  else
    pass "non-env row '$nonkey' excluded from env-example"
  fi
done
# No real secret VALUE ever appears in the generated template.
if printf '%s' "$GEN" | grep -qE '=(xoxb-|lin_api_)'; then
  fail "no secret values in env-example" "empty secret lines" "a token-shaped value leaked"
else
  pass "no secret values in env-example (names only)"
fi

# ── 3. env-example ↔ manifest agreement check ──
echo "Test 3: agreement check"
GENFILE="$WORK/env.example"
"$INTAKE_SH" env-example > "$GENFILE"
OUT=$(cd "$WORK" && INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" \
  "$INTAKE_SH" doctor --env-example "$GENFILE" 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'PASS .*\.env\.example.*match'; then
  pass "fresh generated file agrees with manifest (PASS)"
else
  fail "fresh file agrees with manifest" "PASS keys match" "$(printf '%s' "$OUT" | grep -i env.example)"
fi
DRIFT="$WORK/drift.example"; cp "$GENFILE" "$DRIFT"; printf 'STALE_KEY=x\n' >> "$DRIFT"
OUT=$(cd "$WORK" && INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" \
  "$INTAKE_SH" doctor --env-example "$DRIFT" 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'WARN .*\.env\.example.*DRIFT'; then
  pass "drifted file flagged (WARN DRIFT)"
else
  fail "drifted file flagged" "WARN DRIFT" "$(printf '%s' "$OUT" | grep -i env.example)"
fi

# ── 4. doctor red-green + exit code ──
echo "Test 4: doctor red-green + exit code"
# CASE A: required present → exit 0, SLACK PASS.
CASE_A="$WORK/a"; mkdir -p "$CASE_A"; printf 'SLACK_INTAKE_TOKEN=xoxb-test\n' > "$CASE_A/.env.local"
OUT=$(cd "$CASE_A" && INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor 2>&1 | strip)
CODE=$(cd "$CASE_A" && INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$OUT" | grep -qE 'PASS +SLACK_INTAKE_TOKEN'; then
  pass "CASE A: SLACK_INTAKE_TOKEN renders PASS when present"
else
  fail "CASE A: SLACK PASS" "PASS SLACK_INTAKE_TOKEN" "$(printf '%s' "$OUT" | grep SLACK_INTAKE_TOKEN)"
fi
if [ "$CODE" -eq 0 ]; then
  pass "CASE A: exit 0 when all required present"
else
  fail "CASE A: exit 0" "0" "$CODE"
fi
# Seeding: a non-secret default was written into .env.
if grep -qE '^AWS_REGION=us-east-2$' "$CASE_A/.env"; then
  pass "CASE A: non-secret default seeded into .env"
else
  fail "CASE A: default seeded" "AWS_REGION=us-east-2 in .env" "$(cat "$CASE_A/.env" 2>/dev/null)"
fi

# CASE B: SLACK missing → FAIL + exit 1 (a REQUIRED miss gates the caller).
CASE_B="$WORK/b"; mkdir -p "$CASE_B"
OUT=$(cd "$CASE_B" && INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor 2>&1 | strip)
CODE=$(cd "$CASE_B" && INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$OUT" | grep -qE 'FAIL +SLACK_INTAKE_TOKEN'; then
  pass "CASE B: missing SLACK renders FAIL"
else
  fail "CASE B: SLACK FAIL" "FAIL SLACK_INTAKE_TOKEN" "$(printf '%s' "$OUT" | grep SLACK_INTAKE_TOKEN)"
fi
if [ "$CODE" -eq 1 ]; then
  pass "CASE B: exit 1 when a REQUIRED cred is missing"
else
  fail "CASE B: exit 1" "1" "$CODE"
fi

# CASE C: MCP list unavailable (empty seam) → req linear degrades to WARN, not a false FAIL.
CASE_C="$WORK/c"; mkdir -p "$CASE_C"; printf 'SLACK_INTAKE_TOKEN=xoxb-test\n' > "$CASE_C/.env.local"
OUT=$(cd "$CASE_C" && INTAKE_MCP_LIST_OUTPUT="" "$INTAKE_SH" doctor 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'WARN +linear-server .*cannot verify'; then
  pass "CASE C: unverifiable MCP degrades to WARN (not a false FAIL)"
else
  fail "CASE C: MCP degrade" "WARN linear-server cannot verify" "$(printf '%s' "$OUT" | grep linear-server)"
fi

# CASE D: MCP present but "Needs authentication" → req linear FAIL + exit 1.
CASE_D="$WORK/d"; mkdir -p "$CASE_D"; printf 'SLACK_INTAKE_TOKEN=xoxb-test\n' > "$CASE_D/.env.local"
NEEDS_AUTH=$'linear-server: https://mcp.linear.app/mcp (HTTP) - ! Needs authentication'
CODE=$(cd "$CASE_D" && INTAKE_MCP_LIST_OUTPUT="$NEEDS_AUTH" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_D" && INTAKE_MCP_LIST_OUTPUT="$NEEDS_AUTH" "$INTAKE_SH" doctor 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'FAIL +linear-server' && [ "$CODE" -eq 1 ]; then
  pass "CASE D: unconnected required MCP → FAIL + exit 1"
else
  fail "CASE D: MCP not connected fails" "FAIL linear-server + exit 1" "code=$CODE $(printf '%s' "$OUT" | grep linear-server)"
fi

# The headless MCP-write gap note is always surfaced.
if printf '%s' "$OUT" | grep -qiE 'MCP writes .*interactive OAuth'; then
  pass "doctor surfaces the headless MCP-write gap note"
else
  fail "MCP-write gap note" "interactive OAuth note" "absent"
fi

# ── 5. setup dry-run ──
echo "Test 5: setup --non-interactive dry-run"
CASE_S="$WORK/s"; mkdir -p "$CASE_S"
OUT=$(cd "$CASE_S" && "$INTAKE_SH" setup --non-interactive 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'would-write +SLACK_INTAKE_TOKEN' && printf '%s' "$OUT" | grep -qE 'would-write +LINEAR_API_KEY'; then
  pass "dry-run lists both secret rows as would-write"
else
  fail "dry-run lists secrets" "would-write SLACK + LINEAR" "$OUT"
fi
# Dry-run writes NOTHING.
if [ ! -f "$CASE_S/.env.local" ] && [ ! -f "$CASE_S/.env" ]; then
  pass "dry-run writes no dotfile"
else
  fail "dry-run writes nothing" "no .env/.env.local" "a file was created"
fi
# A present secret is reported 'have', not 'would-write'.
printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_S/.env.local"
OUT=$(cd "$CASE_S" && "$INTAKE_SH" setup --dry-run 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'have +SLACK_INTAKE_TOKEN'; then
  pass "present secret reported as 'have'"
else
  fail "present secret 'have'" "have SLACK_INTAKE_TOKEN" "$OUT"
fi

# ── 6. setup interactive WRITE path (the real secret-writing code) ──
echo "Test 6: setup write path"
# A single-secret manifest keeps the wizard prompting for exactly one value.
ONE_SECRET="$WORK/one-secret.manifest"
printf 'SLACK_INTAKE_TOKEN|Slack|req|true||.env.local|paste the xoxb- token|file-key\n' > "$ONE_SECRET"
CASE_W="$WORK/w"; mkdir -p "$CASE_W"
OUT=$(cd "$CASE_W" && INTAKE_MANIFEST="$ONE_SECRET" "$INTAKE_SH" setup <<<'my secret val' 2>&1 | strip)
# Exactly one KEY line, quoted, and round-trips through the read path.
LINES=$(grep -c '^SLACK_INTAKE_TOKEN=' "$CASE_W/.env.local" 2>/dev/null || echo 0)
if [ "$LINES" -eq 1 ]; then
  pass "setup writes exactly one KEY= line"
else
  fail "setup writes one line" "1" "$LINES: $(cat "$CASE_W/.env.local" 2>/dev/null)"
fi
if grep -qE '^SLACK_INTAKE_TOKEN="my secret val"$' "$CASE_W/.env.local"; then
  pass "setup quotes the written secret"
else
  fail "setup quotes secret" 'SLACK_INTAKE_TOKEN="my secret val"' "$(cat "$CASE_W/.env.local" 2>/dev/null)"
fi
ROUNDTRIP=$(source "$HOME/.claude/engine/scripts/slack-lib.sh"; extract_env_key "$CASE_W/.env.local" SLACK_INTAKE_TOKEN)
if [ "$ROUNDTRIP" = "my secret val" ]; then
  pass "written secret round-trips through extract_env_key (quote-consistent)"
else
  fail "secret round-trips" "my secret val" "$ROUNDTRIP"
fi
# A second run with the value present reports 'have' — no duplicate append.
OUT=$(cd "$CASE_W" && INTAKE_MANIFEST="$ONE_SECRET" "$INTAKE_SH" setup <<<'ignored' 2>&1 | strip)
LINES2=$(grep -c '^SLACK_INTAKE_TOKEN=' "$CASE_W/.env.local")
if printf '%s' "$OUT" | grep -qE 'have +SLACK_INTAKE_TOKEN' && [ "$LINES2" -eq 1 ]; then
  pass "second setup run reports 'have' and does not duplicate"
else
  fail "setup idempotent" "have + 1 line" "$(printf '%s' "$OUT" | grep SLACK) lines=$LINES2"
fi

# ── 7. non-required miss ⇒ exit 0 (the Phase-0 gate contract, isolated) ──
echo "Test 7: non-required miss keeps exit 0"
OPT_MF="$WORK/optional-only.manifest"
{
  printf 'SLACK_INTAKE_TOKEN|Slack|req|true||.env.local|paste token|file-key\n'
  printf 'SOME_OPTIONAL|Opt|optional|false||.env|hint|file-key\n'
  printf 'SOME_TRIAGE|Tri|triage|false||.env|hint|file-key\n'
  printf 'SOME_BOARDS|Brd|boards|false||.env|hint|file-key\n'
} > "$OPT_MF"
CASE_O="$WORK/o"; mkdir -p "$CASE_O"; printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_O/.env.local"
CODE=$(cd "$CASE_O" && INTAKE_MANIFEST="$OPT_MF" INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_O" && INTAKE_MANIFEST="$OPT_MF" INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor 2>&1 | strip)
if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qE 'WARN +SOME_OPTIONAL'; then
  pass "only non-required creds missing ⇒ WARN + exit 0 (gate stays open)"
else
  fail "non-req miss exit 0" "exit 0 + WARN" "code=$CODE $(printf '%s' "$OUT" | grep -E 'SOME_')"
fi

# ── 8. value-drift is caught (Finding 1 regression) ──
echo "Test 8: default-value drift caught"
VD="$WORK/vd.example"; "$INTAKE_SH" env-example > "$VD"
# Corrupt a non-secret DEFAULT value; keep every key NAME identical.
sed 's/^AWS_REGION=us-east-2/AWS_REGION=eu-WRONG/' "$VD" > "$VD.tmp" && mv "$VD.tmp" "$VD"
OUT=$(cd "$WORK" && INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor --env-example "$VD" 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'WARN +\.env\.example +.*DRIFT'; then
  pass "wrong non-secret DEFAULT value flagged as DRIFT (not a false PASS)"
else
  fail "value drift caught" "WARN DRIFT" "$(printf '%s' "$OUT" | grep -i env.example)"
fi
# A secret row with a filled value must NOT trip drift — secrets compare by name only.
SD="$WORK/sd.example"; "$INTAKE_SH" env-example > "$SD"
sed 's/^SLACK_INTAKE_TOKEN=$/SLACK_INTAKE_TOKEN=xoxb-local-note/' "$SD" > "$SD.tmp" && mv "$SD.tmp" "$SD"
OUT=$(cd "$WORK" && INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor --env-example "$SD" 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'PASS +\.env\.example'; then
  pass "secret value difference does NOT false-trip drift (name-only compare)"
else
  fail "secret compared by name" "PASS" "$(printf '%s' "$OUT" | grep -i env.example)"
fi

# ── 9. empty-key seed idempotency (Finding 2 regression, doctor path) ──
echo "Test 9: empty-key seed does not duplicate"
CASE_E="$WORK/e"; mkdir -p "$CASE_E"; printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_E/.env.local"
printf 'AWS_REGION=\n' > "$CASE_E/.env"   # key present but blank
for _ in 1 2 3; do
  (cd "$CASE_E" && INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor >/dev/null 2>&1)
done
EL=$(grep -c '^AWS_REGION=' "$CASE_E/.env")
if [ "$EL" -eq 1 ]; then
  pass "present-but-empty key is not duplicated across runs (1 line)"
else
  fail "empty key not duplicated" "1 AWS_REGION line" "$EL lines"
fi
if grep -qE '^AWS_REGION=us-east-2$' "$CASE_E/.env"; then
  pass "present-but-empty key filled in place with the default (seed takes effect)"
else
  fail "empty key filled" "AWS_REGION=us-east-2" "$(grep '^AWS_REGION=' "$CASE_E/.env")"
fi

# ── 10. empty-key setup secret path fills in place (Finding 2, setup path) ──
echo "Test 10: empty secret key filled, not duplicated"
CASE_ES="$WORK/es"; mkdir -p "$CASE_ES"; printf 'SLACK_INTAKE_TOKEN=\n' > "$CASE_ES/.env.local"
OUT=$(cd "$CASE_ES" && INTAKE_MANIFEST="$ONE_SECRET" "$INTAKE_SH" setup <<<'xoxb-filled' 2>&1 | strip)
ESL=$(grep -c '^SLACK_INTAKE_TOKEN=' "$CASE_ES/.env.local")
ESV=$(source "$HOME/.claude/engine/scripts/slack-lib.sh"; extract_env_key "$CASE_ES/.env.local" SLACK_INTAKE_TOKEN)
if [ "$ESL" -eq 1 ] && [ "$ESV" = "xoxb-filled" ]; then
  pass "wizard fills a present-but-empty secret in place (1 line, correct value)"
else
  fail "empty secret filled" "1 line + xoxb-filled" "lines=$ESL val=$ESV"
fi

# ── 11. MCP connected match is case-insensitive (Finding 3 regression) ──
echo "Test 11: MCP 'connected' matched case-insensitively"
CASE_L="$WORK/l"; mkdir -p "$CASE_L"; printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_L/.env.local"
LOWER=$'linear-server: https://mcp.linear.app/mcp (HTTP) - ✔ connected\nnotion: https://mcp.notion.com/mcp (HTTP) - ✔ Connected'
CODE=$(cd "$CASE_L" && INTAKE_MCP_LIST_OUTPUT="$LOWER" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_L" && INTAKE_MCP_LIST_OUTPUT="$LOWER" "$INTAKE_SH" doctor 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'PASS +linear-server' && [ "$CODE" -eq 0 ]; then
  pass "lowercase 'connected' → PASS + exit 0 (no false FAIL on format casing)"
else
  fail "case-insensitive connected" "PASS linear-server + exit 0" "code=$CODE $(printf '%s' "$OUT" | grep linear-server)"
fi
# An unrecognized state (not a known-unhealthy one) degrades to WARN, never a hard FAIL.
CASE_U="$WORK/u"; mkdir -p "$CASE_U"; printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_U/.env.local"
UNKNOWN=$'linear-server: https://mcp.linear.app/mcp (HTTP) - ✔ Ready'
CODE=$(cd "$CASE_U" && INTAKE_MCP_LIST_OUTPUT="$UNKNOWN" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_U" && INTAKE_MCP_LIST_OUTPUT="$UNKNOWN" "$INTAKE_SH" doctor 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'WARN +linear-server' && [ "$CODE" -eq 0 ]; then
  pass "unrecognized MCP state degrades to WARN + exit 0 (no false Phase-0 block)"
else
  fail "format-drift WARN" "WARN linear-server + exit 0" "code=$CODE $(printf '%s' "$OUT" | grep linear-server)"
fi

# ── 12. parser robustness: a '|' in 'how' and CRLF endings ──
echo "Test 12: manifest parser tolerates pipe-in-how + CRLF"
PIPE_MF="$WORK/pipe.manifest"
# Row 1: 'how' contains a literal pipe; 'check' must still parse as file-key.
printf 'FOO|Svc|optional|false|bar|.env|hint with a | pipe inside|file-key\n' > "$PIPE_MF"
# Row 2: CRLF line ending; 'check' (mcp:linear-server) must not keep the trailing CR.
printf 'linear-server|Linear|req|false|||OAuth|mcp:linear-server\r\n' >> "$PIPE_MF"
CASE_P="$WORK/p"; mkdir -p "$CASE_P"
OUT=$(cd "$CASE_P" && INTAKE_MANIFEST="$PIPE_MF" INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor 2>&1 | strip)
if grep -qE '^FOO=bar$' "$CASE_P/.env" 2>/dev/null; then
  pass "pipe in 'how' does not corrupt 'check' (FOO seeded via file-key)"
else
  fail "pipe-in-how parse" "FOO=bar seeded" "$(cat "$CASE_P/.env" 2>/dev/null); out=$(printf '%s' "$OUT" | grep FOO)"
fi
if printf '%s' "$OUT" | grep -qE 'PASS +linear-server'; then
  pass "CRLF row parses (mcp:linear-server matched, no trailing CR)"
else
  fail "CRLF parse" "PASS linear-server" "$(printf '%s' "$OUT" | grep linear-server)"
fi

exit_with_results
