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

# Resolution is PROJECT-SCOPED (env-lib.sh reads ./.env.local and ./.env, nothing else),
# so the suite is hermetic by construction: every case cds into its own temp dir and the
# operator's ~/.claude/engine dotfiles are never consulted. Test 16 pins that directly.

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
if printf '%s' "$GEN" | grep -qE '^SLACK_INTAKE_CONTEXT_LOOKBACK_DAYS=7$'; then
  pass "channel-context lookback default filled (SLACK_INTAKE_CONTEXT_LOOKBACK_DAYS=7)"
else
  fail "channel-context lookback default filled" "SLACK_INTAKE_CONTEXT_LOOKBACK_DAYS=7" "$(printf '%s' "$GEN" | grep SLACK_INTAKE_CONTEXT_LOOKBACK_DAYS)"
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

# ── 13. dotfile precedence: EITHER dotfile resolves, .env.local wins ──
# Written RED-first against the pre-change code:
#   • rows 1/2 cross the manifest's preferred dotfile with where the value actually
#     lives, so the old "read exactly the manifest's dotfile" check MISSES both;
#   • the BOTH / NEITHER cases call resolve_env_key, which did not exist (rc 127).
echo "Test 13: dotfile precedence (.env.local preferred, .env fallback)"
PREC_MF="$WORK/prec.manifest"
{
  # preferred home says .env, but the operator put it in .env.local
  printf 'PREC_LOCAL_ONLY|Prec|req|true||.env|put PREC_LOCAL_ONLY in .env.local|file-key\n'
  # preferred home says .env.local, but the operator kept it in .env (back-compat)
  printf 'PREC_ENV_ONLY|Prec|req|true||.env.local|put PREC_ENV_ONLY in .env.local|file-key\n'
} > "$PREC_MF"

# (a) key ONLY in .env → resolves; (b) key ONLY in .env.local → resolves.
CASE_PR="$WORK/pr"; mkdir -p "$CASE_PR"
printf 'PREC_LOCAL_ONLY=from-local\n' > "$CASE_PR/.env.local"
printf 'PREC_ENV_ONLY=from-env\n'     > "$CASE_PR/.env"
CODE=$(cd "$CASE_PR" && INTAKE_MANIFEST="$PREC_MF" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_PR" && INTAKE_MANIFEST="$PREC_MF" "$INTAKE_SH" doctor 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'PASS +PREC_ENV_ONLY'; then
  pass "key ONLY in .env resolves (back-compat widening)"
else
  fail "key only in .env resolves" "PASS PREC_ENV_ONLY" "$(printf '%s' "$OUT" | grep PREC_ENV_ONLY)"
fi
if printf '%s' "$OUT" | grep -qE 'PASS +PREC_LOCAL_ONLY'; then
  pass "key ONLY in .env.local resolves"
else
  fail "key only in .env.local resolves" "PASS PREC_LOCAL_ONLY" "$(printf '%s' "$OUT" | grep PREC_LOCAL_ONLY)"
fi
if [ "$CODE" -eq 0 ]; then
  pass "both required keys found across the two dotfiles ⇒ exit 0"
else
  fail "either-dotfile exit 0" "0" "$CODE"
fi

# (c) key in BOTH → the .env.local value wins (value-level oracle, not presence).
CASE_PB="$WORK/pb"; mkdir -p "$CASE_PB"
printf 'PREC_BOTH=local-wins\n' > "$CASE_PB/.env.local"
printf 'PREC_BOTH=env-loses\n'  > "$CASE_PB/.env"
BOTHVAL=$(cd "$CASE_PB" && source "$HOME/.claude/engine/scripts/slack-lib.sh" && resolve_env_key PREC_BOTH 2>/dev/null)
if [ "$BOTHVAL" = "local-wins" ]; then
  pass "key in BOTH files ⇒ .env.local value wins"
else
  fail "'.env.local' wins" "local-wins" "$BOTHVAL"
fi
# and the same helper still reads a key that lives only in .env
ENVVAL=$(cd "$CASE_PR" && source "$HOME/.claude/engine/scripts/slack-lib.sh" && resolve_env_key PREC_ENV_ONLY 2>/dev/null)
if [ "$ENVVAL" = "from-env" ]; then
  pass "resolve_env_key reads a .env-only key (nothing narrowed)"
else
  fail "resolve_env_key .env fallback" "from-env" "$ENVVAL"
fi
# a real env var still outranks both files
EXPVAL=$(cd "$CASE_PB" && source "$HOME/.claude/engine/scripts/slack-lib.sh" && PREC_BOTH=from-shell resolve_env_key PREC_BOTH 2>/dev/null)
if [ "$EXPVAL" = "from-shell" ]; then
  pass "a real env var outranks both dotfiles"
else
  fail "env var wins" "from-shell" "$EXPVAL"
fi

# (d) key in NEITHER file → miss, with the how-hint printed, and a clean rc 1
#     (rc 1, not 127 — pinning that the helper EXISTS and reports 'unresolved').
CASE_PN="$WORK/pn"; mkdir -p "$CASE_PN"
MISSRC=$(cd "$CASE_PN" && source "$HOME/.claude/engine/scripts/slack-lib.sh" >/dev/null 2>&1; resolve_env_key PREC_MISSING >/dev/null 2>&1; echo $?)
if [ "$MISSRC" -eq 1 ]; then
  pass "key in NEITHER file ⇒ resolve_env_key returns 1 (defined, unresolved)"
else
  fail "miss returns 1" "1" "$MISSRC"
fi
CODE=$(cd "$CASE_PN" && INTAKE_MANIFEST="$PREC_MF" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_PN" && INTAKE_MANIFEST="$PREC_MF" "$INTAKE_SH" doctor 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'FAIL +PREC_ENV_ONLY +put PREC_ENV_ONLY in \.env\.local' && [ "$CODE" -eq 1 ]; then
  pass "key in NEITHER file ⇒ doctor miss prints the how-hint + exit 1"
else
  fail "miss prints how-hint" "FAIL PREC_ENV_ONLY <how> + exit 1" "code=$CODE $(printf '%s' "$OUT" | grep PREC_)"
fi

# ── 14. shared-lib additive proof: nothing that resolved before stops resolving ──
echo "Test 14: slack-lib / linear-lib both-file resolution"
SLACK_LIB="$HOME/.claude/engine/scripts/slack-lib.sh"
LINEAR_LIB="$HOME/.claude/engine/scripts/linear-lib.sh"
CASE_SL="$WORK/sl"; mkdir -p "$CASE_SL"
printf 'SLACK_INTAKE_TOKEN=xoxb-in-local\n' > "$CASE_SL/.env.local"
TOKL=$(cd "$CASE_SL" && unset SLACK_INTAKE_TOKEN SLACK_BOT_TOKEN; source "$SLACK_LIB"; slack_token 2>/dev/null)
if [ "$TOKL" = "xoxb-in-local" ]; then
  pass "slack_token still resolves a token in .env.local (regression)"
else
  fail "slack .env.local still works" "xoxb-in-local" "$TOKL"
fi
CASE_SE="$WORK/se"; mkdir -p "$CASE_SE"
printf 'SLACK_INTAKE_TOKEN=xoxb-in-env\n' > "$CASE_SE/.env"
TOKE=$(cd "$CASE_SE" && unset SLACK_INTAKE_TOKEN SLACK_BOT_TOKEN; source "$SLACK_LIB"; slack_token 2>/dev/null)
if [ "$TOKE" = "xoxb-in-env" ]; then
  pass "slack_token now also resolves a token in .env (widened)"
else
  fail "slack .env fallback" "xoxb-in-env" "$TOKE"
fi
CASE_LE="$WORK/le"; mkdir -p "$CASE_LE"
printf 'LINEAR_API_KEY=lin_api_in_env\n' > "$CASE_LE/.env"
KEYE=$(cd "$CASE_LE" && unset LINEAR_API_KEY; source "$LINEAR_LIB"; _load_key >/dev/null 2>&1; printf '%s' "${LINEAR_API_KEY:-}")
if [ "$KEYE" = "lin_api_in_env" ]; then
  pass "_load_key still resolves LINEAR_API_KEY from .env (regression)"
else
  fail "linear .env still works" "lin_api_in_env" "$KEYE"
fi
CASE_LL="$WORK/ll"; mkdir -p "$CASE_LL"
printf 'LINEAR_API_KEY=lin_api_in_local\n' > "$CASE_LL/.env.local"
KEYL=$(cd "$CASE_LL" && unset LINEAR_API_KEY; source "$LINEAR_LIB"; _load_key >/dev/null 2>&1; printf '%s' "${LINEAR_API_KEY:-}")
if [ "$KEYL" = "lin_api_in_local" ]; then
  pass "_load_key now also resolves LINEAR_API_KEY from .env.local (widened)"
else
  fail "linear .env.local fallback" "lin_api_in_local" "$KEYL"
fi
# .env.local beats .env for Linear too, and the value arrives UNQUOTED
# (behavior change: _load_key used to hand back the surrounding quotes verbatim).
CASE_LB="$WORK/lb"; mkdir -p "$CASE_LB"
printf 'LINEAR_API_KEY="lin_api_quoted_local"\n' > "$CASE_LB/.env.local"
printf 'LINEAR_API_KEY=lin_api_env\n'            > "$CASE_LB/.env"
KEYB=$(cd "$CASE_LB" && unset LINEAR_API_KEY; source "$LINEAR_LIB"; _load_key >/dev/null 2>&1; printf '%s' "${LINEAR_API_KEY:-}")
if [ "$KEYB" = "lin_api_quoted_local" ]; then
  pass "_load_key: .env.local wins over .env and one quote layer is stripped"
else
  fail "linear precedence + unquote" "lin_api_quoted_local" "$KEYB"
fi
# Engine-home is NOT in the chain. Resolution is project-scoped by design: a global
# ~/.claude/engine/.env must never satisfy a per-project credential, or one project's
# wave authenticates as another's. rc 1 (not 127) pins "helper defined, key unresolved".
CASE_LH="$WORK/lh"; mkdir -p "$CASE_LH" "$WORK/enginehome/.claude/engine"
printf 'LINEAR_API_KEY=lin_api_engine_home\n' > "$WORK/enginehome/.claude/engine/.env"
printf 'LINEAR_API_KEY=lin_api_engine_home\n' > "$WORK/enginehome/.claude/engine/.env.local"
RCH=$(cd "$CASE_LH" && unset LINEAR_API_KEY; export HOME="$WORK/enginehome" ENGINE_ENV_HOME="$WORK/enginehome/.claude/engine"; \
      source "$LINEAR_LIB"; resolve_env_key LINEAR_API_KEY >/dev/null 2>&1; echo $?)
if [ "$RCH" -eq 1 ]; then
  pass "engine-home dotfiles are NOT searched (project-scoped resolution, rc 1)"
else
  fail "engine-home dropped from the chain" "1" "$RCH"
fi

# ── 15. .env is never WRITTEN; a blank line there is shadowed, not filled ──
# `.env.local` is the only file these commands write. When the manifest homes a row in
# .env.local and a blank KEY= line sits in .env, the value goes to .env.local and the
# blank line is left where it is — harmless, because .env.local outranks .env on read,
# so the key resolves to the written value and no secret can ever land in .env.
echo "Test 15: .env is never written (blank line there is shadowed by .env.local)"
XF_MF="$WORK/crossfile.manifest"
{
  printf 'SLACK_INTAKE_TOKEN|Slack|req|true||.env.local|paste the xoxb- token|file-key\n'
  printf 'XF_DEFAULTED|Xf|optional|false|xf-default|.env.local|non-secret with a default|file-key\n'
} > "$XF_MF"
CASE_XF="$WORK/xf"; mkdir -p "$CASE_XF"
printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_XF/.env.local"
printf 'XF_DEFAULTED=\n' > "$CASE_XF/.env"          # blank line in the file that is NEVER written
(cd "$CASE_XF" && INTAKE_MANIFEST="$XF_MF" INTAKE_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$INTAKE_SH" doctor >/dev/null 2>&1)
XFE=$(grep -c '^XF_DEFAULTED=' "$CASE_XF/.env")
XFL=$(grep -c '^XF_DEFAULTED=' "$CASE_XF/.env.local" || true)
if grep -qE '^XF_DEFAULTED=xf-default$' "$CASE_XF/.env.local" && [ "$XFL" -eq 1 ] \
   && [ "$XFE" -eq 1 ] && grep -qE '^XF_DEFAULTED=$' "$CASE_XF/.env"; then
  pass "doctor seeds into .env.local and leaves the blank .env line untouched"
else
  fail "seed target is .env.local" "1 filled line in .env.local, .env blank line untouched" ".env=$XFE .env.local=$XFL: $(grep '^XF_DEFAULTED=' "$CASE_XF/.env" "$CASE_XF/.env.local" 2>/dev/null | tr '\n' ' ')"
fi
# The shadowed blank is inert: the key resolves to the value that was actually written.
XFV=$(cd "$CASE_XF" && source "$HOME/.claude/engine/scripts/slack-lib.sh" && resolve_env_key XF_DEFAULTED 2>/dev/null)
if [ "$XFV" = "xf-default" ]; then
  pass "the shadowed blank .env line is inert (.env.local value resolves)"
else
  fail "blank .env line shadowed" "xf-default" "$XFV"
fi
# Same for the wizard's secret write path: a live token must NEVER reach .env.
CASE_XS="$WORK/xs"; mkdir -p "$CASE_XS"
printf 'SLACK_INTAKE_TOKEN=\n' > "$CASE_XS/.env"     # blank secret in the never-written file
OUT=$(cd "$CASE_XS" && INTAKE_MANIFEST="$ONE_SECRET" "$INTAKE_SH" setup <<<'xoxb-crossfile' 2>&1 | strip)
XSE=$(grep -c '^SLACK_INTAKE_TOKEN=' "$CASE_XS/.env")
XSEV=$(source "$HOME/.claude/engine/scripts/slack-lib.sh"; extract_env_key "$CASE_XS/.env" SLACK_INTAKE_TOKEN)
XSV=$(cd "$CASE_XS" && source "$HOME/.claude/engine/scripts/slack-lib.sh" && resolve_env_key SLACK_INTAKE_TOKEN 2>/dev/null)
if [ "$XSE" -eq 1 ] && [ -z "$XSEV" ] && [ "$XSV" = "xoxb-crossfile" ]; then
  pass "wizard writes the secret to .env.local only — .env keeps its blank line, no token"
else
  fail "secret never written to .env" ".env blank + resolved xoxb-crossfile" "envlines=$XSE envval='$XSEV' resolved='$XSV'"
fi

# ── 16. a POPULATED engine-home does not satisfy the per-project doctor ──
# The seam that used to make this suite hermetic now documents behavior instead of
# hiding it: HOME (and the old ENGINE_ENV_HOME) point at a dir holding a real token,
# and the doctor must still FAIL — the credential has to come from the project.
echo "Test 16: populated engine-home does NOT satisfy the doctor"
CASE_EH="$WORK/eh"; mkdir -p "$CASE_EH" "$WORK/fakehome/.claude/engine"
printf 'SLACK_INTAKE_TOKEN=xoxb-operator-global\n' > "$WORK/fakehome/.claude/engine/.env"
printf 'SLACK_INTAKE_TOKEN=xoxb-operator-global\n' > "$WORK/fakehome/.claude/engine/.env.local"
OUT=$(cd "$CASE_EH" && HOME="$WORK/fakehome" ENGINE_ENV_HOME="$WORK/fakehome/.claude/engine" \
      INTAKE_MANIFEST="$ONE_SECRET" "$INTAKE_SH" doctor 2>&1 | strip)
CODE=$(cd "$CASE_EH" && HOME="$WORK/fakehome" ENGINE_ENV_HOME="$WORK/fakehome/.claude/engine" \
      INTAKE_MANIFEST="$ONE_SECRET" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$OUT" | grep -qE 'FAIL +SLACK_INTAKE_TOKEN' && [ "$CODE" -eq 1 ]; then
  pass "a token in ~/.claude/engine/.env{,.local} does not satisfy the doctor (FAIL + exit 1)"
else
  fail "engine-home cannot satisfy the doctor" "FAIL SLACK_INTAKE_TOKEN + exit 1" "code=$CODE $(printf '%s' "$OUT" | grep SLACK_INTAKE_TOKEN)"
fi

# ── 17. one file really does just work: a blank placeholder above a real value ──
# `cp .env.example .env.local` then paste the token at the bottom — the single most
# likely onboarding flow. The first NON-EMPTY match wins, so the blank placeholder
# no longer masks the real value for the rest of the file.
echo "Test 17: first NON-EMPTY match wins inside a file"
CASE_NE="$WORK/ne"; mkdir -p "$CASE_NE"
printf 'SLACK_INTAKE_TOKEN=\nSLACK_INTAKE_CHANNEL=\n# pasted below:\nSLACK_INTAKE_TOKEN=xoxb-appended\n' > "$CASE_NE/.env.local"
CODE=$(cd "$CASE_NE" && INTAKE_MANIFEST="$ONE_SECRET" "$INTAKE_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_NE" && INTAKE_MANIFEST="$ONE_SECRET" "$INTAKE_SH" doctor 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'PASS +SLACK_INTAKE_TOKEN' && [ "$CODE" -eq 0 ]; then
  pass "blank placeholder above a real value ⇒ PASS + exit 0 (not a miss)"
else
  fail "blank-then-real resolves" "PASS SLACK_INTAKE_TOKEN + exit 0" "code=$CODE $(printf '%s' "$OUT" | grep SLACK_INTAKE_TOKEN)"
fi
NEV=$(source "$HOME/.claude/engine/scripts/slack-lib.sh"; extract_env_key "$CASE_NE/.env.local" SLACK_INTAKE_TOKEN)
if [ "$NEV" = "xoxb-appended" ]; then
  pass "extract_env_key skips the empty line and returns the real value"
else
  fail "first non-empty match" "xoxb-appended" "$NEV"
fi

# ── 18. `export KEY=…` is visible to BOTH the reader and the presence check ──
# Otherwise the seed path reads "unparseable" as "absent" and appends a second,
# conflicting definition — which a sourcing shell resolves the other way.
echo "Test 18: export-prefixed keys are read, not duplicated"
EXP_MF="$WORK/export.manifest"
printf 'AWS_REGION|AWS|triage|false|us-east-2|.env|AWS region|file-key\n' > "$EXP_MF"
CASE_EX="$WORK/ex"; mkdir -p "$CASE_EX"
printf 'export AWS_REGION=eu-west-1\n' > "$CASE_EX/.env"
OUT=$(cd "$CASE_EX" && INTAKE_MANIFEST="$EXP_MF" "$INTAKE_SH" doctor 2>&1 | strip)
EXL=$(grep -c 'AWS_REGION=' "$CASE_EX/.env")
if printf '%s' "$OUT" | grep -qE 'PASS +AWS_REGION' && [ "$EXL" -eq 1 ] && grep -qE '^export AWS_REGION=eu-west-1$' "$CASE_EX/.env"; then
  pass "'export KEY=value' reads as present — no conflicting second definition appended"
else
  fail "export form respected" "PASS + 1 untouched line" "$(printf '%s' "$OUT" | grep AWS_REGION); file=$(cat "$CASE_EX/.env")"
fi
# A blank `export KEY=` is filled IN PLACE, and the export prefix survives the fill.
CASE_EB="$WORK/eb"; mkdir -p "$CASE_EB"
printf 'export AWS_REGION=\n' > "$CASE_EB/.env"
(cd "$CASE_EB" && INTAKE_MANIFEST="$EXP_MF" "$INTAKE_SH" doctor >/dev/null 2>&1)
EBL=$(grep -c 'AWS_REGION=' "$CASE_EB/.env")
if [ "$EBL" -eq 1 ] && grep -qE '^export AWS_REGION=us-east-2$' "$CASE_EB/.env"; then
  pass "blank 'export KEY=' filled in place, export prefix preserved"
else
  fail "export blank filled in place" "1 line 'export AWS_REGION=us-east-2'" "lines=$EBL: $(cat "$CASE_EB/.env")"
fi

# ── 19. an explicit env-file is AUTHORITATIVE — never a fallthrough ──
# `--env-file wsB.env` is a statement of intent. Falling through to ./.env.local would
# post into the wrong workspace with no error; a miss must fail loudly instead.
echo "Test 19: explicit --env-file searches only that file"
CASE_XE="$WORK/xe"; mkdir -p "$CASE_XE"
printf 'SLACK_INTAKE_TOKEN=xoxb-WORKSPACE-A\n' > "$CASE_XE/.env.local"
printf 'SLACK_INTAKE_CHANNEL=#wsB\n'           > "$CASE_XE/wsB.env"
XRC=$(cd "$CASE_XE" && unset SLACK_INTAKE_TOKEN SLACK_BOT_TOKEN; source "$SLACK_LIB"; slack_token ./wsB.env >/dev/null 2>&1; echo $?)
if [ "$XRC" -eq 1 ]; then
  pass "explicit env-file without the key ⇒ rc 1 (no fallthrough to ./.env.local)"
else
  fail "explicit env-file authoritative" "1" "$XRC"
fi
XTOK=$(cd "$CASE_XE" && unset SLACK_INTAKE_TOKEN SLACK_BOT_TOKEN; source "$SLACK_LIB"; slack_token 2>/dev/null)
if [ "$XTOK" = "xoxb-WORKSPACE-A" ]; then
  pass "the DEFAULTED call still walks the full chain"
else
  fail "defaulted slack_token chain" "xoxb-WORKSPACE-A" "$XTOK"
fi

# ── 20. the .env.local-wins flip is ANNOUNCED, and never leaks a value ──
echo "Test 20: shadowed-key notice on stderr"
CASE_SW="$WORK/sw"; mkdir -p "$CASE_SW"
printf 'SHADOW_KEY=from-local\n' > "$CASE_SW/.env.local"
printf 'SHADOW_KEY=from-env\n'   > "$CASE_SW/.env"
SWERR=$(cd "$CASE_SW" && source "$SLACK_LIB"; resolve_env_key SHADOW_KEY 2>&1 >/dev/null)
if printf '%s' "$SWERR" | grep -q 'SHADOW_KEY: using ./.env.local (a different value exists in ./.env)'; then
  pass "differing value in .env ⇒ one stderr line naming the flip"
else
  fail "shadow notice printed" "SHADOW_KEY: using ./.env.local (…)" "$SWERR"
fi
if printf '%s' "$SWERR" | grep -qE 'from-local|from-env'; then
  fail "notice leaks no value" "no value in the notice" "$SWERR"
else
  pass "the notice never prints either value"
fi
printf 'SHADOW_KEY=same\n' > "$CASE_SW/.env.local"; printf 'SHADOW_KEY=same\n' > "$CASE_SW/.env"
SWQUIET=$(cd "$CASE_SW" && source "$SLACK_LIB"; resolve_env_key SHADOW_KEY 2>&1 >/dev/null)
if [ -z "$SWQUIET" ]; then
  pass "identical values in both files ⇒ silence (no noise for a harmless duplicate)"
else
  fail "no notice when values agree" "" "$SWQUIET"
fi

exit_with_results
