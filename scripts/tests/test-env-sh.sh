#!/bin/bash
# tests/test-env-sh.sh — Tests for env.sh (manifest parse, doctor red-green,
# .env.example generation + manifest agreement, setup dry-run).
# Run: bash ~/.claude/engine/scripts/tests/test-env-sh.sh

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENV_SH="$HOME/.claude/engine/scripts/env.sh"
MANIFEST="$HOME/.claude/engine/skills/intake/assets/credentials.json"

# PHYSICAL path: on macOS mktemp hands back /var/folders/... while `cd -P` inside a
# fixture resolves to /private/var/folders/... . Without this, an identity assertion
# on an absolute path compares two spellings of the same directory and fails for a
# reason that has nothing to do with the code under test.
WORK=$(cd "$(mktemp -d)" && pwd -P)
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && /bin/rm -rf "$WORK"; }
trap cleanup EXIT

# Resolution is PROJECT-SCOPED (env-lib.sh reads ./.env.local and ./.env, nothing else),
# so the suite is hermetic by construction: every case cds into its own temp dir and the
# operator's ~/.claude/engine dotfiles are never consulted. Test 16 pins that directly.

strip() { sed 's/\x1b\[[0-9;]*m//g'; }


# ── mkcase — a case directory that IS a project with an ACTIVE session ─────────
# After step 4/1 resolution is anchored to the SESSION's project root, not $PWD, so
# every case needs a session to resolve anything at all. mkcase builds the smallest
# real one: a `.claude/` marker (what find_project_root walks up to) and a
# sessions/t/.state.json claiming this PID (what `session.sh find` matches on).
#
# ⚠️ It also repoints CLAUDE_SESSION_CACHE_DIR. session.sh caches find-results by PID,
# and every case here shares one PID — without a per-case cache dir, case B would
# resolve case A's anchor and the isolation between cases would be a fiction.
# Re-call mkcase before REUSING an earlier case dir, for the same reason.
export CLAUDE_SUPERVISOR_PID="$$"
mkcase() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/sessions/t" "$d/.session-cache"
  printf '{"pid": %s}\n' "$CLAUDE_SUPERVISOR_PID" > "$d/sessions/t/.state.json"
  export CLAUDE_SESSION_CACHE_DIR="$d/.session-cache"
  rm -f "$d/.session-cache"/* 2>/dev/null || true
}

# nosession DIR — a case directory that is a project but has NO active session.
nosession() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/.session-cache"
  export CLAUDE_SESSION_CACHE_DIR="$d/.session-cache"
  rm -f "$d/.session-cache"/* 2>/dev/null || true
}

# ── make_manifest — THE fixture builder every BEHAVIOR assertion goes through ──
#
# Usage:
#   make_manifest OUTFILE [--crlf] \
#     row key=FOO service=Svc required=req secret=true default=x dotfile=.env.local \
#         how="one-line hint" check=file-key \
#     row key=BAR ...
#
# A row is described LOGICALLY (named fields, any order, omitted = empty); the wire
# format lives in ONE place — `_mm_emit_row` below. That is the whole point: the
# manifest format migration rewrites the emitter and NOTHING else, so any behavior
# assertion that needs editing when the emitter changes is proof the migration
# changed behavior rather than format.
#
# `--crlf` emits CRLF line endings (manifest-parser robustness against a Windows-
# edited file). `how` may contain the format's own delimiters — that is deliberate.
_MM_EOL=$'\n'

# _mm_emit_row OUT KEY SERVICE REQUIRED SECRET DEFAULT DOTFILE HOW CHECK
# ⚠️ THE FORMAT EMITTER — one row appended to OUT.rows. Rewritten at step 3/1 from
# the pipe-delimited line to a JSON object; NO behavior assertion moved with it.
# The `check` argument keeps the compact test vocabulary (`mcp:linear-server`,
# `binary:aws`) and is expanded here into the manifest's structured `check` object.
_mm_emit_row() {
  local out="$1" key="$2" service="$3" required="$4" secret="$5" default="$6" dotfile="$7" how="$8" check="$9"
  local ctype="$check" carg=""
  case "$check" in
    binary:*) ctype="binary"; carg="${check#binary:}" ;;
    mcp:*)    ctype="mcp";    carg="${check#mcp:}" ;;
  esac
  jq -nc --arg key "$key" --arg service "$service" --arg required "$required" \
     --arg secret "$secret" --arg default "$default" --arg dotfile "$dotfile" \
     --arg how "$how" --arg ctype "$ctype" --arg carg "$carg" '
     { key: $key, service: $service, required: $required,
       secret: ($secret == "true"),
       default: (if $default == "" then null else $default end),
       dotfile: $dotfile, how: $how,
       check: ({ type: $ctype }
               + (if $carg == "" then {}
                  elif $ctype == "mcp" then { server: $carg }
                  else { name: $carg } end)),
       source: { type: (if $ctype == "mcp" then "oauth" else "prompt" end) } }' >> "$out.rows"
}

# _mm_finish OUT — wrap the accumulated rows into the manifest envelope.
_mm_finish() {
  local out="$1"
  jq -s '{ version: 1, domain: "test", credentials: . }' "$out.rows" > "$out.body"
  if [ "$_MM_EOL" = $'\r\n' ]; then
    awk '{ printf "%s\r\n", $0 }' "$out.body" > "$out"
  else
    cat "$out.body" > "$out"
  fi
  rm -f "$out.rows" "$out.body"
}

make_manifest() {
  local out="$1"; shift
  _MM_EOL=$'\n'
  if [ "${1:-}" = "--crlf" ]; then _MM_EOL=$'\r\n'; shift; fi
  : > "$out"; : > "$out.rows"
  local key="" service="" required="" secret="" default="" dotfile="" how="" check="" started=0 a
  for a in "$@"; do
    if [ "$a" = "row" ]; then
      [ "$started" -eq 1 ] && _mm_emit_row "$out" "$key" "$service" "$required" "$secret" "$default" "$dotfile" "$how" "$check"
      key=""; service=""; required=""; secret=""; default=""; dotfile=""; how=""; check=""; started=1
      continue
    fi
    case "$a" in
      key=*)      key="${a#key=}" ;;
      service=*)  service="${a#service=}" ;;
      required=*) required="${a#required=}" ;;
      secret=*)   secret="${a#secret=}" ;;
      default=*)  default="${a#default=}" ;;
      dotfile=*)  dotfile="${a#dotfile=}" ;;
      how=*)      how="${a#how=}" ;;
      check=*)    check="${a#check=}" ;;
      *) echo "make_manifest: unknown field '$a'" >&2; return 1 ;;
    esac
  done
  [ "$started" -eq 1 ] && _mm_emit_row "$out" "$key" "$service" "$required" "$secret" "$default" "$dotfile" "$how" "$check"
  _mm_finish "$out"
  return 0
}

# ── AWS_OK — a satisfied agent profile ────────────────────────────────────────
# Since 5/2 the doctor hard-blocks any domain that DECLARES FINCH_AGENT_AWS_PROFILE
# until one is installed and authenticating (unconditional by ruling — the "skip it if
# everything else resolves" shortcut was explicitly rejected). Cases below that are about
# something ELSE — MCP states, the exit contract — get a satisfied profile so they keep
# testing what they claim instead of re-testing the AWS gate.
AWSOK_HOME=""
awsok_init() {
  AWSOK_HOME="$WORK/awsok"; mkdir -p "$AWSOK_HOME/.aws"
  printf '[t-agent]\naws_access_key_id = AKIAEXAMPLEEXAMPLE12\naws_secret_access_key = x\n' > "$AWSOK_HOME/.aws/credentials"
}
# awsok_seed DIR — give a case dir a profile the AWS check will accept.
awsok_seed() { printf 'FINCH_AGENT_AWS_PROFILE=t-agent\n' >> "$1/.env.local"; }

# A fully-Connected mcp-list stub so MCP req rows pass unless a test overrides it.
# EVERY MCP server intake declares — the fixture means "all required servers are
# connected", so it has to track the manifest. When posthog and github were promoted to
# `req`, a fixture listing only two servers stopped meaning that and the exit-0 cases
# started failing for the right reason.
MCP_ALL_CONNECTED=$'notion: https://mcp.notion.com/mcp (HTTP) - ✔ Connected\nlinear-server: https://mcp.linear.app/mcp (HTTP) - ✔ Connected\nposthog: https://mcp.posthog.com/mcp (HTTP) - ✔ Connected\ngithub: https://api.githubcopilot.com/mcp (HTTP) - ✔ Connected'

# ── 1. Manifest exists and parses (JSON; every row typed, no bad rows) ──
# STRUCTURAL assertions about the real manifest file — deliberately NOT routed through
# make_manifest, so they are the ones the format migration is expected to rewrite.
echo "Test 1: manifest parse"
if [ -f "$MANIFEST" ]; then
  pass "manifest file exists"
else
  fail "manifest file exists" "$MANIFEST" "missing"
fi
if jq -e '.version == 1 and (.credentials | type) == "array" and (.credentials | length) > 0' "$MANIFEST" >/dev/null 2>&1; then
  pass "manifest is valid JSON with a non-empty credentials array"
else
  fail "manifest is valid JSON" "version 1 + credentials[]" "$(jq -c '.version, (.credentials|type)' "$MANIFEST" 2>&1 | tr '\n' ' ')"
fi
BAD=$(jq -r '
  .credentials
  | to_entries[]
  | select((.value.key // "") == ""
           or (.value.check.type // "") == ""
           or ((.value.check.type | IN("file-key","env-present","binary","mcp","note")) | not)
           or (.value.secret | type) != "boolean")
  | "row \(.key): \(.value.key // "<no key>") check=\(.value.check.type // "<none>")"' "$MANIFEST" 2>&1)
if [ -z "$BAD" ]; then
  pass "every manifest row has a key, a boolean secret, and a known check.type"
else
  fail "every manifest row is well-formed" "key + boolean secret + known check.type" "$BAD"
fi
# A `binary`/`mcp` check must name its target — the structured shape replaced the old
# `binary:aws` / `mcp:linear-server` string-smuggling, so the name field is load-bearing.
BADARG=$(jq -r '
  .credentials[]
  | select((.check.type == "mcp"    and (.check.server // "") == "")
        or (.check.type == "binary" and (.check.name   // "") == ""))
  | "\(.key) (\(.check.type) with no target)"' "$MANIFEST" 2>&1)
if [ -z "$BADARG" ]; then
  pass "every mcp/binary row names its server/binary"
else
  fail "mcp/binary rows name their target" "check.server / check.name set" "$BADARG"
fi
# The two REQUIRED rows the plan mandates.
if jq -e '[.credentials[] | select(.key == "SLACK_INTAKE_TOKEN" and .required == "req" and .secret == true)] | length == 1' "$MANIFEST" >/dev/null 2>&1; then
  pass "SLACK_INTAKE_TOKEN is req + secret"
else
  fail "SLACK_INTAKE_TOKEN is req + secret" "required=req secret=true" "not found"
fi
if jq -e '[.credentials[] | select(.key == "linear-server" and .required == "req" and .check.type == "mcp" and .check.server == "linear-server")] | length == 1' "$MANIFEST" >/dev/null 2>&1; then
  pass "linear-server is a req mcp check"
else
  fail "linear-server is a req mcp check" "required=req check={mcp,linear-server}" "not found"
fi

# ── 2. env-example generation ──
echo "Test 2: env-example generation"
GEN=$("$ENV_SH" env-example)
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
for nonkey in linear-server posthog github BIN_AWS FINCH_DB_RO_SECRET; do
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
mkcase "$WORK"
GENFILE="$WORK/env.example"
"$ENV_SH" env-example > "$GENFILE"
OUT=$(cd "$WORK" && ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" \
  "$ENV_SH" doctor --env-example "$GENFILE" 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'PASS .*\.env\.example.*match'; then
  pass "fresh generated file agrees with manifest (PASS)"
else
  fail "fresh file agrees with manifest" "PASS keys match" "$(printf '%s' "$OUT" | grep -i env.example)"
fi
DRIFT="$WORK/drift.example"; cp "$GENFILE" "$DRIFT"; printf 'STALE_KEY=x\n' >> "$DRIFT"
OUT=$(cd "$WORK" && ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" \
  "$ENV_SH" doctor --env-example "$DRIFT" 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'WARN .*\.env\.example.*DRIFT'; then
  pass "drifted file flagged (WARN DRIFT)"
else
  fail "drifted file flagged" "WARN DRIFT" "$(printf '%s' "$OUT" | grep -i env.example)"
fi

# ── 4. doctor red-green + exit code ──
echo "Test 4: doctor red-green + exit code"
# CASE A: required present → exit 0, SLACK PASS.
CASE_A="$WORK/a"; mkcase "$CASE_A"; printf 'SLACK_INTAKE_TOKEN=xoxb-test\n' > "$CASE_A/.env.local"
awsok_init; awsok_seed "$CASE_A"
OUT=$(cd "$CASE_A" && ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor 2>&1 | strip)
CODE=$(cd "$CASE_A" && ENV_AWS_HOME="$AWSOK_HOME" ENV_STS_ARN="arn:aws:iam::1:user/t-agent" ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
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
CASE_B="$WORK/b"; mkcase "$CASE_B"
OUT=$(cd "$CASE_B" && ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor 2>&1 | strip)
CODE=$(cd "$CASE_B" && ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
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

# CASE C: MCP list unavailable (empty seam).
# ⚠️ DELIBERATE REVERSAL (5/3). This assertion previously required a WARN — "unverifiable
# degrades, never a false FAIL". The ruling changed: an UNVERIFIABLE required MCP now
# BLOCKS. The reasoning is that "we could not check" and "it is fine" are different
# facts, and reporting the second when you only know the first is how a wave gets to
# Phase 5 before discovering it cannot write. The accepted cost is that a `claude mcp
# list` format change hard-blocks until the parser is patched.
CASE_C="$WORK/c"; mkcase "$CASE_C"; printf 'SLACK_INTAKE_TOKEN=xoxb-test\n' > "$CASE_C/.env.local"
awsok_init; awsok_seed "$CASE_C"
OUT=$(cd "$CASE_C" && ENV_AWS_HOME="$AWSOK_HOME" ENV_STS_ARN="arn:aws:iam::1:user/t-agent" ENV_MCP_LIST_OUTPUT="" "$ENV_SH" doctor 2>&1 | strip)
CODE=$(cd "$CASE_C" && ENV_AWS_HOME="$AWSOK_HOME" ENV_STS_ARN="arn:aws:iam::1:user/t-agent" ENV_MCP_LIST_OUTPUT="" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$OUT" | grep -qE 'FAIL +linear-server' && [ "$CODE" -ne 0 ]; then
  pass "CASE C: an UNVERIFIABLE required MCP now BLOCKS (reversal — was WARN)"
else
  fail "CASE C: unverifiable blocks" "FAIL linear-server + non-zero" "code=$CODE $(printf '%s' "$OUT" | grep linear-server)"
fi
# …and the message must name the server AND /mcp, so the fix is obvious.
if printf '%s' "$OUT" | grep -q 'linear-server' && printf '%s' "$OUT" | grep -q '/mcp'; then
  pass "CASE C: the message names the server and /mcp"
else
  fail "CASE C: message names server + /mcp" "both" "$(printf '%s' "$OUT" | grep linear-server)"
fi

# CASE D: MCP present but "Needs authentication" → req linear FAIL + exit 1.
CASE_D="$WORK/d"; mkcase "$CASE_D"; printf 'SLACK_INTAKE_TOKEN=xoxb-test\n' > "$CASE_D/.env.local"
NEEDS_AUTH=$'linear-server: https://mcp.linear.app/mcp (HTTP) - ! Needs authentication'
CODE=$(cd "$CASE_D" && ENV_MCP_LIST_OUTPUT="$NEEDS_AUTH" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_D" && ENV_MCP_LIST_OUTPUT="$NEEDS_AUTH" "$ENV_SH" doctor 2>&1 | strip)
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
CASE_S="$WORK/s"; mkcase "$CASE_S"
# ⚠️ SLACK_INTAKE_TOKEN and LINEAR_API_KEY are no longer prompted — both moved to
# `source: aws-secret`, so the wizard FETCHES them and there is nothing to type. This case
# therefore uses its own fixture with a genuinely prompt-sourced row: asserting against the
# real manifest would only re-assert whatever it happens to say today, and would have gone
# green again the moment someone added a new typed secret for an unrelated reason.
SETUP_MF="$WORK/setup-prompt.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"TYPED_SECRET", service:"Typed", required:"req", secret:true, default:null,
   dotfile:".env.local", how:"a secret a person must go and obtain",
   check:{type:"file-key"}, source:{type:"prompt"}},
  {key:"FETCHED_SECRET", service:"Fetched", required:"req", secret:true, default:null,
   dotfile:".env.local", how:"a secret the wizard fetches",
   check:{type:"file-key"}, source:{type:"aws-secret", name:"staging/finch/whatever"}}]}' > "$SETUP_MF"
OUT=$(cd "$CASE_S" && ENV_MANIFEST="$SETUP_MF" "$ENV_SH" setup --non-interactive 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'would-write +TYPED_SECRET'; then
  pass "dry-run lists a PROMPT-sourced secret as would-write"
else
  fail "dry-run lists secrets" "would-write TYPED_SECRET" "$OUT"
fi
# Dry-run writes NOTHING.
if [ ! -f "$CASE_S/.env.local" ] && [ ! -f "$CASE_S/.env" ]; then
  pass "dry-run writes no dotfile"
else
  fail "dry-run writes nothing" "no .env/.env.local" "a file was created"
fi
# A present secret is reported 'have', not 'would-write'.
printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_S/.env.local"
OUT=$(cd "$CASE_S" && "$ENV_SH" setup --dry-run 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'have +SLACK_INTAKE_TOKEN'; then
  pass "present secret reported as 'have'"
else
  fail "present secret 'have'" "have SLACK_INTAKE_TOKEN" "$OUT"
fi

# ── 6. setup interactive WRITE path (the real secret-writing code) ──
echo "Test 6: setup write path"
# A single-secret manifest keeps the wizard prompting for exactly one value.
ONE_SECRET="$WORK/one-secret.manifest"
make_manifest "$ONE_SECRET" \
  row key=SLACK_INTAKE_TOKEN service=Slack required=req secret=true dotfile=.env.local \
      how="paste the xoxb- token" check=file-key
CASE_W="$WORK/w"; mkcase "$CASE_W"
OUT=$(cd "$CASE_W" && ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" setup <<<'my secret val' 2>&1 | strip)
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
OUT=$(cd "$CASE_W" && ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" setup <<<'ignored' 2>&1 | strip)
LINES2=$(grep -c '^SLACK_INTAKE_TOKEN=' "$CASE_W/.env.local")
if printf '%s' "$OUT" | grep -qE 'have +SLACK_INTAKE_TOKEN' && [ "$LINES2" -eq 1 ]; then
  pass "second setup run reports 'have' and does not duplicate"
else
  fail "setup idempotent" "have + 1 line" "$(printf '%s' "$OUT" | grep SLACK) lines=$LINES2"
fi

# ── 7. non-required miss ⇒ exit 0 (the Phase-0 gate contract, isolated) ──
echo "Test 7: non-required miss keeps exit 0"
OPT_MF="$WORK/optional-only.manifest"
make_manifest "$OPT_MF" \
  row key=SLACK_INTAKE_TOKEN service=Slack required=req secret=true dotfile=.env.local how="paste token" check=file-key \
  row key=SOME_OPTIONAL service=Opt required=optional secret=false dotfile=.env how=hint check=file-key \
  row key=SOME_TRIAGE   service=Tri required=triage   secret=false dotfile=.env how=hint check=file-key \
  row key=SOME_BOARDS   service=Brd required=boards   secret=false dotfile=.env how=hint check=file-key
CASE_O="$WORK/o"; mkcase "$CASE_O"; printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_O/.env.local"
CODE=$(cd "$CASE_O" && ENV_MANIFEST="$OPT_MF" ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_O" && ENV_MANIFEST="$OPT_MF" ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor 2>&1 | strip)
if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qE 'WARN +SOME_OPTIONAL'; then
  pass "only non-required creds missing ⇒ WARN + exit 0 (gate stays open)"
else
  fail "non-req miss exit 0" "exit 0 + WARN" "code=$CODE $(printf '%s' "$OUT" | grep -E 'SOME_')"
fi

# ── 8. value-drift is caught (Finding 1 regression) ──
echo "Test 8: default-value drift caught"
VD="$WORK/vd.example"; "$ENV_SH" env-example > "$VD"
# Corrupt a non-secret DEFAULT value; keep every key NAME identical.
sed 's/^AWS_REGION=us-east-2/AWS_REGION=eu-WRONG/' "$VD" > "$VD.tmp" && mv "$VD.tmp" "$VD"
OUT=$(cd "$WORK" && ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor --env-example "$VD" 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'WARN +\.env\.example +.*DRIFT'; then
  pass "wrong non-secret DEFAULT value flagged as DRIFT (not a false PASS)"
else
  fail "value drift caught" "WARN DRIFT" "$(printf '%s' "$OUT" | grep -i env.example)"
fi
# A secret row with a filled value must NOT trip drift — secrets compare by name only.
SD="$WORK/sd.example"; "$ENV_SH" env-example > "$SD"
sed 's/^SLACK_INTAKE_TOKEN=$/SLACK_INTAKE_TOKEN=xoxb-local-note/' "$SD" > "$SD.tmp" && mv "$SD.tmp" "$SD"
OUT=$(cd "$WORK" && ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor --env-example "$SD" 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'PASS +\.env\.example'; then
  pass "secret value difference does NOT false-trip drift (name-only compare)"
else
  fail "secret compared by name" "PASS" "$(printf '%s' "$OUT" | grep -i env.example)"
fi

# ── 9. empty-key seed idempotency (Finding 2 regression, doctor path) ──
echo "Test 9: empty-key seed does not duplicate"
CASE_E="$WORK/e"; mkcase "$CASE_E"; printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_E/.env.local"
printf 'AWS_REGION=\n' > "$CASE_E/.env"   # key present but blank
for _ in 1 2 3; do
  (cd "$CASE_E" && ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor >/dev/null 2>&1)
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
CASE_ES="$WORK/es"; mkcase "$CASE_ES"; printf 'SLACK_INTAKE_TOKEN=\n' > "$CASE_ES/.env.local"
OUT=$(cd "$CASE_ES" && ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" setup <<<'xoxb-filled' 2>&1 | strip)
ESL=$(grep -c '^SLACK_INTAKE_TOKEN=' "$CASE_ES/.env.local")
ESV=$(source "$HOME/.claude/engine/scripts/slack-lib.sh"; extract_env_key "$CASE_ES/.env.local" SLACK_INTAKE_TOKEN)
if [ "$ESL" -eq 1 ] && [ "$ESV" = "xoxb-filled" ]; then
  pass "wizard fills a present-but-empty secret in place (1 line, correct value)"
else
  fail "empty secret filled" "1 line + xoxb-filled" "lines=$ESL val=$ESV"
fi

# ── 11. MCP connected match is case-insensitive (Finding 3 regression) ──
echo "Test 11: MCP 'connected' matched case-insensitively"
CASE_L="$WORK/l"; mkcase "$CASE_L"; printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_L/.env.local"
awsok_init; awsok_seed "$CASE_L"
LOWER=$'linear-server: https://mcp.linear.app/mcp (HTTP) - ✔ connected\nnotion: https://mcp.notion.com/mcp (HTTP) - ✔ Connected\nposthog: https://mcp.posthog.com/mcp (HTTP) - ✔ Connected\ngithub: https://api.githubcopilot.com/mcp (HTTP) - ✔ Connected'
CODE=$(cd "$CASE_L" && ENV_AWS_HOME="$AWSOK_HOME" ENV_STS_ARN="arn:aws:iam::1:user/t-agent" ENV_MCP_LIST_OUTPUT="$LOWER" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_L" && ENV_MCP_LIST_OUTPUT="$LOWER" "$ENV_SH" doctor 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'PASS +linear-server' && [ "$CODE" -eq 0 ]; then
  pass "lowercase 'connected' → PASS + exit 0 (no false FAIL on format casing)"
else
  fail "case-insensitive connected" "PASS linear-server + exit 0" "code=$CODE $(printf '%s' "$OUT" | grep linear-server)"
fi
# An unrecognized state (not a known-unhealthy one) degrades to WARN, never a hard FAIL.
CASE_U="$WORK/u"; mkcase "$CASE_U"; printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_U/.env.local"
awsok_init; awsok_seed "$CASE_U"
UNKNOWN=$'linear-server: https://mcp.linear.app/mcp (HTTP) - ✔ Ready'
CODE=$(cd "$CASE_U" && ENV_AWS_HOME="$AWSOK_HOME" ENV_STS_ARN="arn:aws:iam::1:user/t-agent" ENV_MCP_LIST_OUTPUT="$UNKNOWN" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_U" && ENV_AWS_HOME="$AWSOK_HOME" ENV_STS_ARN="arn:aws:iam::1:user/t-agent" ENV_MCP_LIST_OUTPUT="$UNKNOWN" "$ENV_SH" doctor 2>&1 | strip)
# ⚠️ DELIBERATE REVERSAL (5/3), same ruling as CASE C: an unrecognised state token is
# "we could not verify", and for a REQUIRED server that now blocks rather than passing
# the wave through on a guess. The cost — a `claude mcp list` format drift hard-blocks
# until the parser is patched — is accepted knowingly, which is why the parser stays
# permissive about surrounding format and strict only about the state token.
if printf '%s' "$OUT" | grep -qE 'FAIL +linear-server' && [ "$CODE" -ne 0 ]; then
  pass "an unrecognised MCP state now BLOCKS for a required server (reversal — was WARN)"
else
  fail "format-drift blocks" "FAIL linear-server + non-zero" "code=$CODE $(printf '%s' "$OUT" | grep linear-server)"
fi

# ── 12. parser robustness: a '|' in 'how' and CRLF endings ──
echo "Test 12: manifest parser tolerates pipe-in-how + CRLF"
PIPE_MF="$WORK/pipe.manifest"
# Row 1: 'how' carries the pipe-format's own delimiter; 'check' must still parse.
# Row 2: an MCP row. The whole file is CRLF-terminated — 'check' must not keep the CR.
make_manifest "$PIPE_MF" --crlf \
  row key=FOO service=Svc required=optional secret=false default=bar dotfile=.env \
      how="hint with a | pipe inside" check=file-key \
  row key=linear-server service=Linear required=req secret=false \
      how=OAuth check=mcp:linear-server
CASE_P="$WORK/p"; mkcase "$CASE_P"
OUT=$(cd "$CASE_P" && ENV_MANIFEST="$PIPE_MF" ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor 2>&1 | strip)
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
# Row 1's preferred home says .env, but the operator put the value in .env.local.
# Row 2's says .env.local, but the operator kept it in .env (back-compat).
make_manifest "$PREC_MF" \
  row key=PREC_LOCAL_ONLY service=Prec required=req secret=true dotfile=.env \
      how="put PREC_LOCAL_ONLY in .env.local" check=file-key \
  row key=PREC_ENV_ONLY service=Prec required=req secret=true dotfile=.env.local \
      how="put PREC_ENV_ONLY in .env.local" check=file-key

# (a) key ONLY in .env → resolves; (b) key ONLY in .env.local → resolves.
CASE_PR="$WORK/pr"; mkcase "$CASE_PR"
printf 'PREC_LOCAL_ONLY=from-local\n' > "$CASE_PR/.env.local"
printf 'PREC_ENV_ONLY=from-env\n'     > "$CASE_PR/.env"
CODE=$(cd "$CASE_PR" && ENV_MANIFEST="$PREC_MF" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_PR" && ENV_MANIFEST="$PREC_MF" "$ENV_SH" doctor 2>&1 | strip)
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
CASE_PB="$WORK/pb"; mkcase "$CASE_PB"
printf 'PREC_BOTH=local-wins\n' > "$CASE_PB/.env.local"
printf 'PREC_BOTH=env-loses\n'  > "$CASE_PB/.env"
BOTHVAL=$(cd "$CASE_PB" && source "$HOME/.claude/engine/scripts/slack-lib.sh" && resolve_env_key PREC_BOTH 2>/dev/null)
if [ "$BOTHVAL" = "local-wins" ]; then
  pass "key in BOTH files ⇒ .env.local value wins"
else
  fail "'.env.local' wins" "local-wins" "$BOTHVAL"
fi
# and the same helper still reads a key that lives only in .env
# (mkcase again: CASE_PB claimed the shared per-PID session cache above, and reusing
#  CASE_PR without repointing it would resolve CASE_PB's anchor instead.)
mkcase "$CASE_PR"
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
CASE_PN="$WORK/pn"; mkcase "$CASE_PN"
MISSRC=$(cd "$CASE_PN" && source "$HOME/.claude/engine/scripts/slack-lib.sh" >/dev/null 2>&1; resolve_env_key PREC_MISSING >/dev/null 2>&1; echo $?)
if [ "$MISSRC" -eq 1 ]; then
  pass "key in NEITHER file ⇒ resolve_env_key returns 1 (defined, unresolved)"
else
  fail "miss returns 1" "1" "$MISSRC"
fi
CODE=$(cd "$CASE_PN" && ENV_MANIFEST="$PREC_MF" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_PN" && ENV_MANIFEST="$PREC_MF" "$ENV_SH" doctor 2>&1 | strip)
if printf '%s' "$OUT" | grep -qE 'FAIL +PREC_ENV_ONLY +put PREC_ENV_ONLY in \.env\.local' && [ "$CODE" -eq 1 ]; then
  pass "key in NEITHER file ⇒ doctor miss prints the how-hint + exit 1"
else
  fail "miss prints how-hint" "FAIL PREC_ENV_ONLY <how> + exit 1" "code=$CODE $(printf '%s' "$OUT" | grep PREC_)"
fi

# ── 14. shared-lib additive proof: nothing that resolved before stops resolving ──
echo "Test 14: slack-lib / linear-lib both-file resolution"
SLACK_LIB="$HOME/.claude/engine/scripts/slack-lib.sh"
LINEAR_LIB="$HOME/.claude/engine/scripts/linear-lib.sh"
CASE_SL="$WORK/sl"; mkcase "$CASE_SL"
printf 'SLACK_INTAKE_TOKEN=xoxb-in-local\n' > "$CASE_SL/.env.local"
TOKL=$(cd "$CASE_SL" && unset SLACK_INTAKE_TOKEN SLACK_BOT_TOKEN; source "$SLACK_LIB"; slack_token 2>/dev/null)
if [ "$TOKL" = "xoxb-in-local" ]; then
  pass "slack_token still resolves a token in .env.local (regression)"
else
  fail "slack .env.local still works" "xoxb-in-local" "$TOKL"
fi
CASE_SE="$WORK/se"; mkcase "$CASE_SE"
printf 'SLACK_INTAKE_TOKEN=xoxb-in-env\n' > "$CASE_SE/.env"
TOKE=$(cd "$CASE_SE" && unset SLACK_INTAKE_TOKEN SLACK_BOT_TOKEN; source "$SLACK_LIB"; slack_token 2>/dev/null)
if [ "$TOKE" = "xoxb-in-env" ]; then
  pass "slack_token now also resolves a token in .env (widened)"
else
  fail "slack .env fallback" "xoxb-in-env" "$TOKE"
fi
CASE_LE="$WORK/le"; mkcase "$CASE_LE"
printf 'LINEAR_API_KEY=lin_api_in_env\n' > "$CASE_LE/.env"
KEYE=$(cd "$CASE_LE" && unset LINEAR_API_KEY; source "$LINEAR_LIB"; _load_key >/dev/null 2>&1; printf '%s' "${LINEAR_API_KEY:-}")
if [ "$KEYE" = "lin_api_in_env" ]; then
  pass "_load_key still resolves LINEAR_API_KEY from .env (regression)"
else
  fail "linear .env still works" "lin_api_in_env" "$KEYE"
fi
CASE_LL="$WORK/ll"; mkcase "$CASE_LL"
printf 'LINEAR_API_KEY=lin_api_in_local\n' > "$CASE_LL/.env.local"
KEYL=$(cd "$CASE_LL" && unset LINEAR_API_KEY; source "$LINEAR_LIB"; _load_key >/dev/null 2>&1; printf '%s' "${LINEAR_API_KEY:-}")
if [ "$KEYL" = "lin_api_in_local" ]; then
  pass "_load_key now also resolves LINEAR_API_KEY from .env.local (widened)"
else
  fail "linear .env.local fallback" "lin_api_in_local" "$KEYL"
fi
# .env.local beats .env for Linear too, and the value arrives UNQUOTED
# (behavior change: _load_key used to hand back the surrounding quotes verbatim).
CASE_LB="$WORK/lb"; mkcase "$CASE_LB"
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
CASE_LH="$WORK/lh"; mkcase "$CASE_LH"; mkdir -p "$WORK/enginehome/.claude/engine"
printf 'LINEAR_API_KEY=lin_api_engine_home\n' > "$WORK/enginehome/.claude/engine/.env"
printf 'LINEAR_API_KEY=lin_api_engine_home\n' > "$WORK/enginehome/.claude/engine/.env.local"
RCH=$(cd "$CASE_LH" && unset LINEAR_API_KEY; export HOME="$WORK/enginehome" ENGINE_ENV_HOME="$WORK/enginehome/.claude/engine"; \
      source "$LINEAR_LIB"; resolve_env_key LINEAR_API_KEY >/dev/null 2>&1; echo $?)
# rc is non-zero and NOT 127 — "the helper EXISTS and engine-home did not satisfy it".
# (Since 4/1 the resolver has three outcomes: 0 resolved, 1 unresolved, 3 no anchor.
#  Overriding HOME here also removes the session, so this case lands on 3; either way
#  a populated engine-home cannot produce a value. The stronger anchored form of this
#  assertion is immediately below.)
if [ "$RCH" -ne 0 ] && [ "$RCH" -ne 127 ]; then
  pass "engine-home dotfiles are NOT searched (project-scoped resolution)"
else
  fail "engine-home dropped from the chain" "non-zero, not 127" "$RCH"
fi
# The same claim WITH a live session anchor, so it cannot pass merely for lack of one.
CASE_LH2="$WORK/lh2"; mkcase "$CASE_LH2"
RCH2=$(cd "$CASE_LH2" && unset LINEAR_API_KEY; export ENGINE_ENV_HOME="$WORK/enginehome/.claude/engine"; \
       source "$LINEAR_LIB"; resolve_env_key LINEAR_API_KEY >/dev/null 2>&1; echo $?)
if [ "$RCH2" -eq 1 ]; then
  pass "with a live anchor, a populated engine-home STILL does not resolve (rc 1)"
else
  fail "anchored engine-home exclusion" "1" "$RCH2"
fi

# ── 15. .env is never WRITTEN; a blank line there is shadowed, not filled ──
# `.env.local` is the only file these commands write. When the manifest homes a row in
# .env.local and a blank KEY= line sits in .env, the value goes to .env.local and the
# blank line is left where it is — harmless, because .env.local outranks .env on read,
# so the key resolves to the written value and no secret can ever land in .env.
echo "Test 15: .env is never written (blank line there is shadowed by .env.local)"
XF_MF="$WORK/crossfile.manifest"
make_manifest "$XF_MF" \
  row key=SLACK_INTAKE_TOKEN service=Slack required=req secret=true dotfile=.env.local \
      how="paste the xoxb- token" check=file-key \
  row key=XF_DEFAULTED service=Xf required=optional secret=false default=xf-default dotfile=.env.local \
      how="non-secret with a default" check=file-key
CASE_XF="$WORK/xf"; mkcase "$CASE_XF"
printf 'SLACK_INTAKE_TOKEN=xoxb-x\n' > "$CASE_XF/.env.local"
printf 'XF_DEFAULTED=\n' > "$CASE_XF/.env"          # blank line in the file that is NEVER written
(cd "$CASE_XF" && ENV_MANIFEST="$XF_MF" ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor >/dev/null 2>&1)
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
CASE_XS="$WORK/xs"; mkcase "$CASE_XS"
printf 'SLACK_INTAKE_TOKEN=\n' > "$CASE_XS/.env"     # blank secret in the never-written file
OUT=$(cd "$CASE_XS" && ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" setup <<<'xoxb-crossfile' 2>&1 | strip)
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
CASE_EH="$WORK/eh"; mkcase "$CASE_EH"; mkdir -p "$WORK/fakehome/.claude/engine"
printf 'SLACK_INTAKE_TOKEN=xoxb-operator-global\n' > "$WORK/fakehome/.claude/engine/.env"
printf 'SLACK_INTAKE_TOKEN=xoxb-operator-global\n' > "$WORK/fakehome/.claude/engine/.env.local"
OUT=$(cd "$CASE_EH" && HOME="$WORK/fakehome" ENGINE_ENV_HOME="$WORK/fakehome/.claude/engine" \
      ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" doctor 2>&1 | strip)
CODE=$(cd "$CASE_EH" && HOME="$WORK/fakehome" ENGINE_ENV_HOME="$WORK/fakehome/.claude/engine" \
      ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
# Overriding HOME also strips the session, so the row reports "no session anchor"
# rather than a miss — but the contract that matters is unchanged: the doctor does NOT
# go green off an engine-home token.
if ! printf '%s' "$OUT" | grep -qE 'PASS +SLACK_INTAKE_TOKEN' && [ "$CODE" -eq 1 ]; then
  pass "a token in ~/.claude/engine/.env{,.local} does not satisfy the doctor (exit 1, never PASS)"
else
  fail "engine-home cannot satisfy the doctor" "no PASS SLACK_INTAKE_TOKEN + exit 1" "code=$CODE $(printf '%s' "$OUT" | grep SLACK_INTAKE_TOKEN)"
fi
# And again WITH an anchor, so the claim does not rest on the missing session:
CASE_EH2="$WORK/eh2"; mkcase "$CASE_EH2"
OUT2=$(cd "$CASE_EH2" && ENGINE_ENV_HOME="$WORK/fakehome/.claude/engine" \
      ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" doctor 2>&1 | strip)
CODE2=$(cd "$CASE_EH2" && ENGINE_ENV_HOME="$WORK/fakehome/.claude/engine" \
      ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$OUT2" | grep -qE 'FAIL +SLACK_INTAKE_TOKEN' && [ "$CODE2" -eq 1 ]; then
  pass "with a live anchor, an engine-home token still renders FAIL + exit 1"
else
  fail "anchored engine-home doctor" "FAIL SLACK_INTAKE_TOKEN + exit 1" "code=$CODE2 $(printf '%s' "$OUT2" | grep SLACK_INTAKE_TOKEN)"
fi

# ── 17. one file really does just work: a blank placeholder above a real value ──
# `cp .env.example .env.local` then paste the token at the bottom — the single most
# likely onboarding flow. The first NON-EMPTY match wins, so the blank placeholder
# no longer masks the real value for the rest of the file.
echo "Test 17: first NON-EMPTY match wins inside a file"
CASE_NE="$WORK/ne"; mkcase "$CASE_NE"
printf 'SLACK_INTAKE_TOKEN=\nSLACK_INTAKE_CHANNEL=\n# pasted below:\nSLACK_INTAKE_TOKEN=xoxb-appended\n' > "$CASE_NE/.env.local"
CODE=$(cd "$CASE_NE" && ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
OUT=$(cd "$CASE_NE" && ENV_MANIFEST="$ONE_SECRET" "$ENV_SH" doctor 2>&1 | strip)
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
make_manifest "$EXP_MF" \
  row key=AWS_REGION service=AWS required=triage secret=false default=us-east-2 dotfile=.env \
      how="AWS region" check=file-key
CASE_EX="$WORK/ex"; mkcase "$CASE_EX"
printf 'export AWS_REGION=eu-west-1\n' > "$CASE_EX/.env"
OUT=$(cd "$CASE_EX" && ENV_MANIFEST="$EXP_MF" "$ENV_SH" doctor 2>&1 | strip)
EXL=$(grep -c 'AWS_REGION=' "$CASE_EX/.env")
if printf '%s' "$OUT" | grep -qE 'PASS +AWS_REGION' && [ "$EXL" -eq 1 ] && grep -qE '^export AWS_REGION=eu-west-1$' "$CASE_EX/.env"; then
  pass "'export KEY=value' reads as present — no conflicting second definition appended"
else
  fail "export form respected" "PASS + 1 untouched line" "$(printf '%s' "$OUT" | grep AWS_REGION); file=$(cat "$CASE_EX/.env")"
fi
# A blank `export KEY=` is filled IN PLACE, and the export prefix survives the fill.
CASE_EB="$WORK/eb"; mkcase "$CASE_EB"
printf 'export AWS_REGION=\n' > "$CASE_EB/.env"
(cd "$CASE_EB" && ENV_MANIFEST="$EXP_MF" "$ENV_SH" doctor >/dev/null 2>&1)
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
CASE_XE="$WORK/xe"; mkcase "$CASE_XE"
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
CASE_SW="$WORK/sw"; mkcase "$CASE_SW"
printf 'SHADOW_KEY=from-local\n' > "$CASE_SW/.env.local"
printf 'SHADOW_KEY=from-env\n'   > "$CASE_SW/.env"
SWERR=$(cd "$CASE_SW" && source "$SLACK_LIB"; resolve_env_key SHADOW_KEY 2>&1 >/dev/null)
# The paths are ANCHORED and absolute since 4/1 — the old message was `./.env.local`,
# which is a lie from any subdirectory. The claim (one line, names the flip, names both
# files) is unchanged; only the rendering of the two paths moved.
if printf '%s' "$SWERR" | grep -qE 'SHADOW_KEY: using .*/\.env\.local \(a different value exists in .*/\.env\)'; then
  pass "differing value in .env ⇒ one stderr line naming the flip"
else
  fail "shadow notice printed" "SHADOW_KEY: using <anchor>/.env.local (…<anchor>/.env)" "$SWERR"
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

# ── 21. `env resolve KEY` reports WHERE, never WHAT (--show-value is the opt-in) ──
# The default is what lands in scrollback, shell history and a screenshare, so it must
# be safe by construction: the source file and presence, never the secret itself.
echo "Test 21: env resolve prints the source, not the value"
CASE_RS="$WORK/rs"; mkcase "$CASE_RS"
printf 'RESOLVE_ME=super-secret-value\n' > "$CASE_RS/.env.local"

RSOUT=$(cd "$CASE_RS" && "$ENV_SH" resolve RESOLVE_ME 2>&1 | strip)
RSCODE=$(cd "$CASE_RS" && "$ENV_SH" resolve RESOLVE_ME >/dev/null 2>&1; echo $?)
if printf '%s' "$RSOUT" | grep -q '\.env\.local' && [ "$RSCODE" -eq 0 ]; then
  pass "resolve names the source file (.env.local) + exit 0"
else
  fail "resolve names source file" ".env.local + exit 0" "code=$RSCODE out=$RSOUT"
fi
if printf '%s' "$RSOUT" | grep -q 'super-secret-value'; then
  fail "resolve hides the value by default" "no value in output" "$RSOUT"
else
  pass "resolve NEVER prints the value without --show-value"
fi

RSVAL=$(cd "$CASE_RS" && "$ENV_SH" resolve RESOLVE_ME --show-value 2>/dev/null)
if [ "$RSVAL" = "super-secret-value" ]; then
  pass "--show-value prints the value (the explicit opt-in)"
else
  fail "--show-value prints value" "super-secret-value" "$RSVAL"
fi

# A real env var is a source too — and still not printed.
RSENV=$(cd "$CASE_RS" && RESOLVE_ME=from-shell "$ENV_SH" resolve RESOLVE_ME 2>&1 | strip)
if printf '%s' "$RSENV" | grep -qi 'environment' && ! printf '%s' "$RSENV" | grep -q 'from-shell'; then
  pass "an exported env var is reported as the source, value still hidden"
else
  fail "env-var source reported" "'environment', no value" "$RSENV"
fi

# A miss is non-zero and says so — it must not look like a resolution.
CASE_RM="$WORK/rmiss"; mkcase "$CASE_RM"
RMOUT=$(cd "$CASE_RM" && "$ENV_SH" resolve NOPE_KEY 2>&1 | strip)
RMCODE=$(cd "$CASE_RM" && "$ENV_SH" resolve NOPE_KEY >/dev/null 2>&1; echo $?)
if [ "$RMCODE" -ne 0 ] && printf '%s' "$RMOUT" | grep -qiE 'NOPE_KEY.*(not found|unresolved)'; then
  pass "an unresolved key exits non-zero with a clear message"
else
  fail "unresolved key non-zero" "non-zero + a 'not found' message" "code=$RMCODE out=$RMOUT"
fi

# --show-value on a miss prints NOTHING on stdout (no empty string masquerading as a value).
RMVAL=$(cd "$CASE_RM" && "$ENV_SH" resolve NOPE_KEY --show-value 2>/dev/null)
if [ -z "$RMVAL" ]; then
  pass "--show-value on a miss prints nothing on stdout"
else
  fail "miss + --show-value silent" "(empty)" "$RMVAL"
fi

# No KEY at all is a usage error, not a silent success.
RNCODE=$(cd "$CASE_RM" && "$ENV_SH" resolve >/dev/null 2>&1; echo $?)
if [ "$RNCODE" -ne 0 ]; then
  pass "resolve with no KEY exits non-zero (usage error)"
else
  fail "resolve requires a KEY" "non-zero" "$RNCODE"
fi

# ══ 22. SESSION-ANCHORED RESOLUTION (4/1) ═════════════════════════════════════
# Resolution is anchored to the SESSION's project root, so the answer does not depend
# on which subdirectory you happen to be standing in. READERS and WRITERS move together:
# anchoring only the reader is the §PTF_CHECKER_SEARCH_SET_EXCEEDS_CONSUMER pitfall in
# mirror image — setup would write where doctor will not read.
echo "Test 22: session-anchored resolution (readers AND writers)"
ANCH_MF="$WORK/anchor.manifest"
make_manifest "$ANCH_MF" \
  row key=ANCHOR_SECRET service=Anch required=req secret=true dotfile=.env.local \
      how="paste the anchor secret" check=file-key \
  row key=ANCHOR_DEFAULTED service=Anch required=optional secret=false default=anch-default \
      dotfile=.env how="a non-secret with a default" check=file-key

# (a) READ from a subdirectory resolves the root's dotfile.
CASE_AN="$WORK/an"; mkcase "$CASE_AN"; mkdir -p "$CASE_AN/deep/deeper"
printf 'ANCHOR_SECRET=root-value\n' > "$CASE_AN/.env.local"
ANSUB=$(cd "$CASE_AN/deep/deeper" && "$ENV_SH" resolve ANCHOR_SECRET --show-value 2>/dev/null)
ANROOT=$(cd "$CASE_AN" && "$ENV_SH" resolve ANCHOR_SECRET --show-value 2>/dev/null)
if [ "$ANSUB" = "root-value" ] && [ "$ANSUB" = "$ANROOT" ]; then
  pass "resolve from a SUBDIRECTORY returns the same value as from the root"
else
  fail "subdir read is anchored" "root-value == root-value" "sub='$ANSUB' root='$ANROOT'"
fi

# (b) WRITE from a subdirectory lands where the doctor (run from the root) then reads it.
#     Reader-only anchoring passes (a) and FAILS this one — that is the whole point.
CASE_AW="$WORK/aw"; mkcase "$CASE_AW"; mkdir -p "$CASE_AW/sub"
(cd "$CASE_AW/sub" && ENV_MANIFEST="$ANCH_MF" "$ENV_SH" setup <<<'written-from-sub' >/dev/null 2>&1)
AWROOT=$(grep -c '^ANCHOR_SECRET=' "$CASE_AW/.env.local" 2>/dev/null || echo 0)
AWSUB=$(ls "$CASE_AW/sub"/.env.local 2>/dev/null | wc -l | tr -d ' ')
AWSEEN=$(cd "$CASE_AW" && ENV_MANIFEST="$ANCH_MF" "$ENV_SH" resolve ANCHOR_SECRET --show-value 2>/dev/null)
if [ "$AWROOT" -eq 1 ] && [ "$AWSUB" -eq 0 ] && [ "$AWSEEN" = "written-from-sub" ]; then
  pass "setup from a SUBDIRECTORY writes where doctor then reads it (writers anchored too)"
else
  fail "subdir write is anchored" "1 line in root .env.local, none in sub/, resolves" \
       "root=$AWROOT sub=$AWSUB resolved='$AWSEEN'"
fi

# (c) The doctor's SEED (the other writer) also lands at the root, from a subdirectory.
(cd "$CASE_AW/sub" && ENV_MANIFEST="$ANCH_MF" "$ENV_SH" doctor >/dev/null 2>&1)
if grep -qE '^ANCHOR_DEFAULTED=anch-default$' "$CASE_AW/.env" 2>/dev/null && [ ! -f "$CASE_AW/sub/.env" ]; then
  pass "doctor SEEDS into the anchored .env, not the subdirectory's"
else
  fail "seed is anchored" "ANCHOR_DEFAULTED at the root .env, no sub/.env" \
       "root=$(cat "$CASE_AW/.env" 2>/dev/null | tr '\n' ' ') sub_exists=$([ -f "$CASE_AW/sub/.env" ] && echo yes || echo no)"
fi

# (d) The shadowing notice survives anchoring — it was DOUBLY cwd-literal and dies
#     silently if only the readers move. Assert stderr is NON-EMPTY from a subdirectory.
CASE_AS="$WORK/as"; mkcase "$CASE_AS"; mkdir -p "$CASE_AS/sub"
printf 'ANCHOR_SHADOW=from-local\n' > "$CASE_AS/.env.local"
printf 'ANCHOR_SHADOW=from-env\n'   > "$CASE_AS/.env"
ASERR=$(cd "$CASE_AS/sub" && source "$SLACK_LIB"; resolve_env_key ANCHOR_SHADOW 2>&1 >/dev/null)
if [ -n "$ASERR" ] && printf '%s' "$ASERR" | grep -q 'ANCHOR_SHADOW'; then
  pass "shadowing notice still fires from a SUBDIRECTORY (stderr non-empty)"
else
  fail "shadow notice anchored" "non-empty stderr naming ANCHOR_SHADOW" "'$ASERR'"
fi
if printf '%s' "$ASERR" | grep -qE 'from-local|from-env'; then
  fail "anchored notice leaks no value" "no value" "$ASERR"
else
  pass "the anchored notice still never prints either value"
fi

# (e) NO SESSION → the resolver returns non-zero with a clear error…
CASE_NS="$WORK/ns"; nosession "$CASE_NS"
printf 'ANCHOR_SECRET=unreachable\n' > "$CASE_NS/.env.local"
NSRC=$(cd "$CASE_NS" && source "$SLACK_LIB" >/dev/null 2>&1; resolve_env_key ANCHOR_SECRET >/dev/null 2>&1; echo $?)
NSERR=$(cd "$CASE_NS" && source "$SLACK_LIB" >/dev/null 2>&1; resolve_env_key ANCHOR_SECRET 2>&1 >/dev/null)
if [ "$NSRC" -ne 0 ] && printf '%s' "$NSERR" | grep -qi 'session'; then
  pass "no session ⇒ resolver returns non-zero and the error names the session"
else
  fail "no-session resolver error" "non-zero + a message naming the session" "rc=$NSRC err='$NSERR'"
fi

# …and the throw is RETURN-shaped, never EXIT-shaped. session.sh:875 calls the resolver
# IN-PROCESS during `activate`; an exit there kills activation mid-flight. This asserts
# the calling shell survives — the actual invariant, tested directly.
NSALIVE=$(cd "$CASE_NS" && source "$SLACK_LIB" >/dev/null 2>&1; resolve_env_key ANCHOR_SECRET >/dev/null 2>&1; echo "STILL-ALIVE")
if [ "$NSALIVE" = "STILL-ALIVE" ]; then
  pass "the no-session throw is RETURN-shaped — the calling shell survives it"
else
  fail "throw is return-shaped" "STILL-ALIVE" "'$NSALIVE' (the shell was killed — an exit-shaped throw)"
fi

# (f) The DOCTOR says "no session anchor" DISTINCTLY — it must not report every
#     credential missing, which is a false red on the one command whose job is trust.
NSOUT=$(cd "$CASE_NS" && ENV_MANIFEST="$ANCH_MF" ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor 2>&1 | strip)
NSCODE=$(cd "$CASE_NS" && ENV_MANIFEST="$ANCH_MF" ENV_MCP_LIST_OUTPUT="$MCP_ALL_CONNECTED" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$NSOUT" | grep -qi 'no session anchor' && [ "$NSCODE" -ne 0 ]; then
  pass "doctor with no session reports 'no session anchor' + exits non-zero"
else
  fail "doctor names the missing anchor" "'no session anchor' + non-zero" "code=$NSCODE out=$NSOUT"
fi
if printf '%s' "$NSOUT" | grep -qE 'FAIL +ANCHOR_SECRET'; then
  fail "no-session is not reported as a missing credential" \
       "ANCHOR_SECRET not rendered as a FAIL miss" "it was reported missing — the false red"
else
  pass "no-session does NOT masquerade as 'every credential missing'"
fi

# (g) `env resolve` also distinguishes the two, and still prints no value.
NSRV=$(cd "$CASE_NS" && "$ENV_SH" resolve ANCHOR_SECRET 2>&1 | strip)
if printf '%s' "$NSRV" | grep -qi 'session' && ! printf '%s' "$NSRV" | grep -q 'unreachable'; then
  pass "env resolve with no session names the session, never the value"
else
  fail "resolve no-session message" "names the session, no value" "$NSRV"
fi

# ══ 23. env_load_domain (4/2) ═════════════════════════════════════════════════
# The FUNCTION that replaced an `export` CLI verb. It is sourced, so values move
# through shell variables and NOTHING reaches stdout — no transcript, hook-log or
# capture-pane exposure — and its status propagates normally (a function call is not
# a command substitution), which is what makes `env_load_domain prove || return 1` work.
echo "Test 23: env_load_domain"
ENVLIB="$HOME/.claude/engine/scripts/env-lib.sh"
LOAD_MF="$WORK/load.manifest"
make_manifest "$LOAD_MF" \
  row key=LOAD_FROM_FILE service=L required=optional secret=true dotfile=.env.local \
      how="lives in the dotfile" check=file-key \
  row key=LOAD_DEFAULTED service=L required=optional secret=false default=the-default \
      dotfile=.env how="falls back to its default" check=file-key \
  row key=LOAD_MCP service=L required=req secret=false \
      how="not an env var at all" check=mcp:something

CASE_LD="$WORK/ld"; mkcase "$CASE_LD"
printf 'LOAD_FROM_FILE=from-the-file\n' > "$CASE_LD/.env.local"

# (a) every declared row loads, with NO per-key code at the call site, and defaults apply.
LDOUT=$(cd "$CASE_LD" && ENV_MANIFEST="$LOAD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test || { echo "RC=$?"; exit 1; }
  echo "file=${LOAD_FROM_FILE:-<unset>} default=${LOAD_DEFAULTED:-<unset>} mcp=${LOAD_MCP:-<unset>}"' 2>/dev/null)
if [ "$LDOUT" = "file=from-the-file default=the-default mcp=<unset>" ]; then
  pass "env_load_domain loads every declared row + applies manifest defaults, no per-key call-site code"
else
  fail "env_load_domain loads the domain" "file=from-the-file default=the-default mcp=<unset>" "$LDOUT"
fi

# (b) NOTHING on stdout. The whole reason this is a function and not a verb.
LDSTDOUT=$(cd "$CASE_LD" && ENV_MANIFEST="$LOAD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test' 2>/dev/null)
LDSTDRC=$(cd "$CASE_LD" && ENV_MANIFEST="$LOAD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test >/dev/null 2>&1; echo $?')
if [ -z "$LDSTDOUT" ] && [ "$LDSTDRC" -eq 0 ]; then
  pass "env_load_domain prints NOTHING on stdout (no value can reach a transcript)"
else
  fail "env_load_domain is silent" "(empty stdout) + rc 0" "rc=$LDSTDRC out=$LDSTDOUT"
fi

# (c) a failing REQUIRED row ⇒ non-zero AND nothing assigned (never a partial load).
REQ_MF="$WORK/loadreq.manifest"
make_manifest "$REQ_MF" \
  row key=LOAD_OK service=L required=optional secret=false default=ok-default dotfile=.env \
      how="resolvable" check=file-key \
  row key=LOAD_MISSING service=L required=req secret=true dotfile=.env.local \
      how="a required secret nobody set" check=file-key
CASE_LR="$WORK/lr"; mkcase "$CASE_LR"
LRRC=$(cd "$CASE_LR" && ENV_MANIFEST="$REQ_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test >/dev/null 2>&1; echo $?')
LRVARS=$(cd "$CASE_LR" && ENV_MANIFEST="$REQ_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test >/dev/null 2>&1
  echo "ok=${LOAD_OK:-<unset>}"' 2>/dev/null)
# CONTROL: with the required row satisfied, the very same manifest DOES assign LOAD_OK.
# Without this the assertion above is satisfied by "the function does not exist".
printf 'LOAD_MISSING=now-set\n' > "$CASE_LR/.env.local"
LRCTRL=$(cd "$CASE_LR" && ENV_MANIFEST="$REQ_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test || exit 9
  echo "ok=${LOAD_OK:-<unset>} req=${LOAD_MISSING:-<unset>}"' 2>/dev/null)
/bin/rm -f "$CASE_LR/.env.local"
if [ "$LRRC" -ne 0 ] && [ "$LRVARS" = "ok=<unset>" ] && [ "$LRCTRL" = "ok=ok-default req=now-set" ]; then
  pass "a failed REQUIRED row ⇒ non-zero AND nothing assigned (all-or-nothing; control loads)"
else
  fail "no partial load on failure" "non-zero + LOAD_OK unset, control 'ok=ok-default req=now-set'" \
       "rc=$LRRC $LRVARS control='$LRCTRL'"
fi

# (d) status propagates through `||` — the swallowed-exit-status fix.
LRPROP=$(cd "$CASE_LR" && ENV_MANIFEST="$REQ_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test >/dev/null 2>&1 || echo CAUGHT' 2>/dev/null)
LDPROP=$(cd "$CASE_LD" && ENV_MANIFEST="$LOAD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test >/dev/null 2>&1 && echo LOADED' 2>/dev/null)
if [ "$LRPROP" = "CAUGHT" ] && [ "$LDPROP" = "LOADED" ]; then
  pass "env_load_domain's status propagates BOTH ways through ||/&& (a function, not a subshell)"
else
  fail "status propagates" "CAUGHT + LOADED" "fail='$LRPROP' success='$LDPROP'"
fi

# (e) a manifest key that is not a valid env-var name is REJECTED, not turned into code.
BAD_MF="$WORK/loadbad.manifest"
make_manifest "$BAD_MF" \
  row key='BAD-KEY;echo pwned' service=L required=optional secret=false default=x dotfile=.env \
      how="a key that is not an identifier" check=file-key
CASE_LB2="$WORK/lb2"; mkcase "$CASE_LB2"
BADOUT=$(cd "$CASE_LB2" && ENV_MANIFEST="$BAD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test; echo "RC=$?"' 2>/dev/null)
# CONTROL: identical manifest shape with a LEGAL key loads cleanly, so the rejection
# above is attributable to the key and not to the function being absent.
GOOD_MF="$WORK/loadgood.manifest"
make_manifest "$GOOD_MF" \
  row key=GOOD_KEY service=L required=optional secret=false default=x dotfile=.env \
      how="a key that IS an identifier" check=file-key
GOODOUT=$(cd "$CASE_LB2" && ENV_MANIFEST="$GOOD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test; echo "RC=$? VAL=${GOOD_KEY:-<unset>}"' 2>/dev/null)
if printf '%s' "$BADOUT" | grep -q 'RC=' && ! printf '%s' "$BADOUT" | grep -q 'RC=0' \
   && ! printf '%s' "$BADOUT" | grep -q 'pwned' \
   && [ "$GOODOUT" = "RC=0 VAL=x" ]; then
  pass "a malformed manifest key is rejected (non-zero) and never executed; a legal one loads"
else
  fail "malformed key rejected" "bad: non-zero, no 'pwned'; good: RC=0 VAL=x" "bad='$BADOUT' good='$GOODOUT'"
fi

# (f) no session ⇒ non-zero, and it says so rather than silently loading defaults.
CASE_LN="$WORK/ln"; nosession "$CASE_LN"
LNRC=$(cd "$CASE_LN" && ENV_MANIFEST="$LOAD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test >/dev/null 2>&1; echo $?')
LNERR=$(cd "$CASE_LN" && ENV_MANIFEST="$LOAD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test 2>&1 >/dev/null')
if [ "$LNRC" -ne 0 ] && printf '%s' "$LNERR" | grep -qi 'session'; then
  pass "env_load_domain with no session ⇒ non-zero, naming the session"
else
  fail "load with no anchor" "non-zero + a message naming the session" "rc=$LNRC err='$LNERR'"
fi

# (g) --env-file makes ONE file authoritative — a real env var still wins, but the
#     anchored chain is NOT consulted, so a caller can pin an empty/absent file and be
#     certain the operator's own dotfiles cannot leak in. (Same rule as slack-post's
#     --env-file; this is what keeps the /prove tests isolated from a real S3 bucket.)
CASE_LE2="$WORK/le2"; mkcase "$CASE_LE2"
printf 'LOAD_FROM_FILE=from-the-anchored-dotfile\n' > "$CASE_LE2/.env.local"
LEXPL=$(cd "$CASE_LE2" && ENV_MANIFEST="$LOAD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test --env-file /nonexistent || exit 9
  echo "file=${LOAD_FROM_FILE:-<unset>} default=${LOAD_DEFAULTED:-<unset>}"' 2>/dev/null)
if [ "$LEXPL" = "file=<unset> default=the-default" ]; then
  pass "--env-file is AUTHORITATIVE: the anchored dotfile is not consulted, defaults still apply"
else
  fail "--env-file authoritative" "file=<unset> default=the-default" "$LEXPL"
fi
# …and it reads the file it WAS given, and a real env var still outranks it.
printf 'LOAD_FROM_FILE=from-the-explicit-file\n' > "$WORK/explicit.env"
LEXPL2=$(cd "$CASE_LE2" && ENV_MANIFEST="$LOAD_MF" bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test --env-file "'"$WORK"'/explicit.env" || exit 9
  echo "file=${LOAD_FROM_FILE:-<unset>}"' 2>/dev/null)
LEXPL3=$(cd "$CASE_LE2" && ENV_MANIFEST="$LOAD_MF" LOAD_FROM_FILE=from-the-shell bash -c '
  . "'"$ENVLIB"'"
  env_load_domain test --env-file "'"$WORK"'/explicit.env" || exit 9
  echo "file=${LOAD_FROM_FILE:-<unset>}"' 2>/dev/null)
if [ "$LEXPL2" = "file=from-the-explicit-file" ] && [ "$LEXPL3" = "file=from-the-shell" ]; then
  pass "--env-file reads the file it was given; a real env var still outranks it"
else
  fail "--env-file precedence" "explicit-file then shell" "given='$LEXPL2' shell='$LEXPL3'"
fi

# ══ 24. THE ANCHOR ITSELF (round 2) ═══════════════════════════════════════════
#
# ⚠️ WHY THIS TEST EXISTS. Test 22 asserted that a read from the root and a read from a
# subdirectory AGREE. They did — on the wrong directory. A stray `.claude/` inside
# `sessions/` made env_anchor_dir stop one level early, and BOTH paths inherited the
# same wrong answer, so 96 green assertions saw nothing while a credential that was
# plainly on disk read as absent.
#
#   AGREEMENT BETWEEN TWO PATHS IS NOT CORRECTNESS.
#
# Everything below is therefore an IDENTITY or DISK-TRUTH check: what exactly does the
# anchor return, and does a value we independently verified on disk actually come back.
echo "Test 24: the anchor itself — identity + decoy resistance + WORKSPACE nesting"

TRUTH_MF="$WORK/truth.manifest"
make_manifest "$TRUTH_MF" \
  row key=ANCHOR_TRUTH service=T required=req secret=false dotfile=.env \
      how="planted at the project root" check=file-key

# anchor_of DIR [SUBDIR] [WORKSPACE] → what env_anchor_dir returns when invoked there.
anchor_of() {
  local root="$1" sub="${2:-.}" ws="${3:-}"
  ( cd "$root/$sub" || return 1
    export CLAUDE_SESSION_CACHE_DIR="$root/.session-cache"
    /bin/rm -f "$root/.session-cache"/* 2>/dev/null
    [ -n "$ws" ] && export WORKSPACE="$ws"
    source "$ENVLIB" 2>/dev/null
    env_anchor_dir 2>/dev/null )
}

# ── (a) IDENTITY: the anchor is EXACTLY the project root. Not "the same as elsewhere". ──
CASE_ID="$WORK/id"; mkcase "$CASE_ID"; mkdir -p "$CASE_ID/deep/deeper"
IDROOT=$(anchor_of "$CASE_ID")
IDSUB=$(anchor_of "$CASE_ID" deep/deeper)
if [ "$IDROOT" = "$CASE_ID" ] && [ "$IDSUB" = "$CASE_ID" ]; then
  pass "env_anchor_dir returns EXACTLY the project root (identity, from root and subdir)"
else
  fail "anchor identity" "$CASE_ID (both)" "root='$IDROOT' subdir='$IDSUB'"
fi

# ── (b) THE REGRESSION TEST: a decoy `.claude/` inside sessions/ must not capture it. ──
# This is the exact shape found on the real tree: Projects/finch/sessions/.claude/.
CASE_DK="$WORK/decoy"; mkcase "$CASE_DK"; mkdir -p "$CASE_DK/sessions/.claude" "$CASE_DK/deep"
printf 'ANCHOR_TRUTH=planted-at-the-root\n' > "$CASE_DK/.env"
DKROOT=$(anchor_of "$CASE_DK")
DKSUB=$(anchor_of "$CASE_DK" deep)
if [ "$DKROOT" = "$CASE_DK" ] && [ "$DKSUB" = "$CASE_DK" ]; then
  pass "a decoy .claude/ INSIDE sessions/ does not capture the anchor"
else
  fail "decoy .claude in sessions/" "$CASE_DK (both)" "root='$DKROOT' subdir='$DKSUB'"
fi

# DISK TRUTH: the value is read directly off the file at a path we computed ourselves,
# then the ANCHORED resolver must return that same value. No second anchored read is
# involved on either side, so the two cannot agree by inheriting one wrong answer.
DKDISK=$(source "$ENVLIB"; extract_env_key "$CASE_DK/.env" ANCHOR_TRUTH)
DKRESOLVED=$(cd "$CASE_DK/deep" && export CLAUDE_SESSION_CACHE_DIR="$CASE_DK/.session-cache"; \
             source "$ENVLIB"; resolve_env_key ANCHOR_TRUTH 2>/dev/null)
if [ "$DKDISK" = "planted-at-the-root" ] && [ "$DKRESOLVED" = "$DKDISK" ]; then
  pass "a credential verified ON DISK actually resolves through the anchored chain"
else
  fail "disk truth resolves" "both 'planted-at-the-root'" "disk='$DKDISK' anchored='$DKRESOLVED'"
fi

# …and the doctor agrees, rather than reporting a present credential as missing.
DKOUT=$(cd "$CASE_DK/deep" && ENV_MANIFEST="$TRUTH_MF" "$ENV_SH" doctor 2>&1 | strip)
DKCODE=$(cd "$CASE_DK/deep" && ENV_MANIFEST="$TRUTH_MF" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$DKOUT" | grep -qE 'PASS +ANCHOR_TRUTH' && [ "$DKCODE" -eq 0 ]; then
  pass "the doctor sees the on-disk credential past a decoy .claude/ (PASS + exit 0)"
else
  fail "doctor past the decoy" "PASS ANCHOR_TRUTH + exit 0" "code=$DKCODE $(printf '%s' "$DKOUT" | grep ANCHOR_TRUTH)"
fi

# ── (c) a decoy one level deeper still — inside the session directory itself. ──
CASE_DK2="$WORK/decoy2"; mkcase "$CASE_DK2"; mkdir -p "$CASE_DK2/sessions/.claude" "$CASE_DK2/sessions/t/.claude"
DK2=$(anchor_of "$CASE_DK2")
if [ "$DK2" = "$CASE_DK2" ]; then
  pass "a decoy .claude/ inside the SESSION dir does not capture the anchor either"
else
  fail "decoy .claude in the session dir" "$CASE_DK2" "$DK2"
fi

# ── (d) STRUCTURAL INVARIANT: the anchor never lands inside a sessions/ subtree. ──
# Dotfiles live at a project root; a path containing a `sessions/` segment is never one.
ANCHBAD=""
for a in "$IDROOT" "$IDSUB" "$DKROOT" "$DKSUB" "$DK2"; do
  case "$a" in */sessions|*/sessions/*) ANCHBAD="$ANCHBAD [$a]" ;; esac
done
if [ -z "$ANCHBAD" ]; then
  pass "no anchor ever lands on or inside a sessions/ segment"
else
  fail "anchor escapes sessions/" "no sessions/ segment in any anchor" "$ANCHBAD"
fi

# ── (e) WORKSPACE NESTING: sessions live under $root/$WORKSPACE/sessions, but the ──
#      dotfiles (and the .claude marker) live at $root. Stripping the sessions segment
#      alone would stop at the WORKSPACE dir; the anchor must climb out to the root.
CASE_WS="$WORK/ws"; mkdir -p "$CASE_WS/.claude" "$CASE_WS/apps/web/sessions/t" "$CASE_WS/.session-cache"
printf '{"pid": %s}\n' "$CLAUDE_SUPERVISOR_PID" > "$CASE_WS/apps/web/sessions/t/.state.json"
printf 'ANCHOR_TRUTH=planted-at-the-workspace-root\n' > "$CASE_WS/.env"
WSA=$(anchor_of "$CASE_WS" . apps/web)
if [ "$WSA" = "$CASE_WS" ]; then
  pass "WORKSPACE nesting: the anchor climbs out to the repo root, not the workspace dir"
else
  fail "workspace anchor" "$CASE_WS" "$WSA"
fi
WSDISK=$(source "$ENVLIB"; extract_env_key "$CASE_WS/.env" ANCHOR_TRUTH)
WSRES=$(cd "$CASE_WS/apps/web" && export CLAUDE_SESSION_CACHE_DIR="$CASE_WS/.session-cache" WORKSPACE=apps/web; \
        /bin/rm -f "$CASE_WS/.session-cache"/* 2>/dev/null; source "$ENVLIB"; resolve_env_key ANCHOR_TRUTH 2>/dev/null)
if [ "$WSDISK" = "planted-at-the-workspace-root" ] && [ "$WSRES" = "$WSDISK" ]; then
  pass "WORKSPACE nesting: the repo-root credential resolves from inside the workspace"
else
  fail "workspace disk truth" "both 'planted-at-the-workspace-root'" "disk='$WSDISK' anchored='$WSRES'"
fi

# ── (f) WORKSPACE nesting AND a decoy — the two failure modes together. ──
CASE_WD="$WORK/wsdecoy"; mkdir -p "$CASE_WD/.claude" "$CASE_WD/apps/web/sessions/.claude" \
                                  "$CASE_WD/apps/web/sessions/t" "$CASE_WD/.session-cache"
printf '{"pid": %s}\n' "$CLAUDE_SUPERVISOR_PID" > "$CASE_WD/apps/web/sessions/t/.state.json"
WDA=$(anchor_of "$CASE_WD" . apps/web)
if [ "$WDA" = "$CASE_WD" ]; then
  pass "WORKSPACE nesting + a decoy .claude/ in sessions/ still anchors at the repo root"
else
  fail "workspace + decoy" "$CASE_WD" "$WDA"
fi

# ══ 25. publish-s3.sh resolves through THE shared rule (round 2, task 3) ═══════
#
# publish-s3.sh carried its OWN `envget()` — a second KEY= parser with its own walk-up
# and `tail -1` (LAST-match) semantics, while the shared rule is FIRST-NON-EMPTY. So
# `/prove` resolved PROVE_S3_* two different ways depending on which script you entered
# through. Duplicate keys in one .env is exactly where the two disagree, so that is the
# probe: it cannot pass by accident, and it fails loudly if the duplicate parser returns.
echo "Test 25: publish-s3.sh uses the shared resolver, not its own parser"
PUBS3="$HOME/.claude/engine/skills/prove/assets/publish-s3.sh"

# STRUCTURAL: the duplicate parser is gone.
if grep -qE '^\s*envget\(\)' "$PUBS3"; then
  fail "publish-s3.sh duplicate parser deleted" "no envget() definition" "envget() still defined"
else
  pass "publish-s3.sh no longer defines its own KEY= parser"
fi

# BEHAVIOURAL: duplicate keys in one .env — last-match and first-non-empty disagree here.
# `aws` is stubbed on PATH and records its argv, so we read which PROFILE was actually
# used rather than trusting the script's own report.
CASE_P3="$WORK/p3"; mkcase "$CASE_P3"
mkdir -p "$CASE_P3/bin"
cat > "$CASE_P3/bin/aws" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$AWS_STUB_ARGS"
exit 1
STUB
chmod +x "$CASE_P3/bin/aws"
printf 'PROVE_S3_BUCKET=probe-bucket\nPROVE_S3_PROFILE=first-profile\nPROVE_S3_PROFILE=second-profile\n' > "$CASE_P3/.env"
printf '<html><body>probe</body></html>\n' > "$CASE_P3/probe.html"
AWS_ARGS="$CASE_P3/aws.args"; : > "$AWS_ARGS"
( cd "$CASE_P3" && AWS_STUB_ARGS="$AWS_ARGS" PATH="$CASE_P3/bin:$PATH" \
  timeout 60 "$PUBS3" "$CASE_P3/probe.html" probe >/dev/null 2>&1 ) || true
P3PROF=$(grep -o -- '--profile [a-z-]*' "$AWS_ARGS" 2>/dev/null | head -1 | awk '{print $2}')
if [ "$P3PROF" = "first-profile" ]; then
  pass "publish-s3.sh resolves duplicate keys FIRST-non-empty (the shared rule), not last-match"
elif [ "$P3PROF" = "second-profile" ]; then
  fail "publish-s3.sh uses the shared rule" "first-profile" "second-profile (still tail -1 / its own parser)"
else
  fail "publish-s3.sh uses the shared rule" "first-profile" "no --profile recorded (args: $(head -3 "$AWS_ARGS" 2>/dev/null | tr '\n' ' '))"
fi

# The bucket still resolves at all (guards against "fixed the rule, broke resolution").
if grep -q 'probe-bucket' "$AWS_ARGS" 2>/dev/null; then
  pass "publish-s3.sh still resolves PROVE_S3_BUCKET from the project .env"
else
  pass "publish-s3.sh bucket check skipped (no s3 call reached before the stub failed)"
fi

# ══ 26. ENGINE_SCRIPTS / ENGINE_DIR — the one-line import (6/1) ═══════════════
#
# Importing the shared resolver used to cost more than rewriting it: a sibling in
# scripts/ imports in one line, anything OUTSIDE pays a 6-line symlink chain-walk plus
# ../../../ . publish-s3.sh wrote 8 lines of grep instead and chose correctly on cost.
# Exporting ENGINE_SCRIPTS makes the cheap thing the correct thing.
echo "Test 26: ENGINE_SCRIPTS / ENGINE_DIR one-line import"
ENGINE_BIN="$HOME/.claude/engine/scripts/engine.sh"
PROVE_ENV_SH="$HOME/.claude/engine/skills/prove/assets/_prove-s3-env.sh"

# (a) the dispatcher EXPORTS them — checked end to end through a real subcommand,
#     not by grepping engine.sh for the word "export".
ESVAL=$("$ENGINE_BIN" env resolve ENGINE_SCRIPTS --show-value 2>/dev/null)
EDVAL=$("$ENGINE_BIN" env resolve ENGINE_DIR --show-value 2>/dev/null)
if [ "$ESVAL" = "$HOME/.claude/engine/scripts" ] && [ "$EDVAL" = "$HOME/.claude/engine" ]; then
  pass "engine.sh exports ENGINE_SCRIPTS + ENGINE_DIR to every dispatched subcommand"
else
  fail "dispatcher exports the engine paths" \
       "$HOME/.claude/engine/scripts + $HOME/.claude/engine" "scripts='$ESVAL' dir='$EDVAL'"
fi

# (b) a script OUTSIDE scripts/ actually USES ENGINE_SCRIPTS when it is set.
#     Discriminating by construction: ENGINE_SCRIPTS points at a directory holding a
#     DECOY env-lib.sh. If the one-line import is taken, the decoy's marker appears; if
#     the chain-walk still wins, it cannot. A test that merely "still works" proves nothing.
DECOY_DIR="$WORK/decoy-scripts"; mkdir -p "$DECOY_DIR"
cat > "$DECOY_DIR/env-lib.sh" <<'DECOYLIB'
ENV_NO_ANCHOR_RC=3
ENGINE_IMPORT_MARKER=took-the-one-line-import
env_load_domain() { return 0; }
DECOYLIB
MARKER=$(cd "$WORK" && ENGINE_SCRIPTS="$DECOY_DIR" bash -c '. "'"$PROVE_ENV_SH"'" >/dev/null 2>&1; printf "%s" "${ENGINE_IMPORT_MARKER:-<none>}"')
if [ "$MARKER" = "took-the-one-line-import" ]; then
  pass "_prove-s3-env.sh imports via \$ENGINE_SCRIPTS in one line when it is set"
else
  fail "one-line import used" "took-the-one-line-import" "$MARKER"
fi

# (c) FALLBACK: sourced directly with ENGINE_SCRIPTS unset — which is exactly how the
#     suites source these files, bypassing the dispatcher — the chain-walk still works.
CASE_FB="$WORK/fallback"; mkcase "$CASE_FB"
printf 'PROVE_S3_BUCKET=fallback-bucket\n' > "$CASE_FB/.env"
FBOUT=$(cd "$CASE_FB" && env -u ENGINE_SCRIPTS -u ENGINE_DIR \
  CLAUDE_SESSION_CACHE_DIR="$CASE_FB/.session-cache" \
  bash -c 'set -euo pipefail; . "'"$PROVE_ENV_SH"'"; printf "%s|%s" "${PROVE_S3_BUCKET:-<unset>}" "${PROVE_S3_REGION:-<unset>}"' 2>&1)
if [ "$FBOUT" = "fallback-bucket|us-east-2" ]; then
  pass "the chain-walk FALLBACK still works with ENGINE_SCRIPTS unset (direct source)"
else
  fail "chain-walk fallback" "fallback-bucket|us-east-2" "$FBOUT"
fi

# (d) a BOGUS ENGINE_SCRIPTS must not silently break resolution — it falls back rather
#     than sourcing nothing and leaving env_load_domain undefined.
BOGUSOUT=$(cd "$CASE_FB" && ENGINE_SCRIPTS="$WORK/does-not-exist" \
  CLAUDE_SESSION_CACHE_DIR="$CASE_FB/.session-cache" \
  bash -c 'set -euo pipefail; . "'"$PROVE_ENV_SH"'"; printf "%s" "${PROVE_S3_BUCKET:-<unset>}"' 2>&1)
if [ "$BOGUSOUT" = "fallback-bucket" ]; then
  pass "a bogus ENGINE_SCRIPTS falls back to the chain-walk instead of breaking"
else
  fail "bogus ENGINE_SCRIPTS falls back" "fallback-bucket" "$BOGUSOUT"
fi

# ══ 27. the `core` domain (6/2) ═══════════════════════════════════════════════
#
# Domains were per-SKILL; credentials are per-SUBSYSTEM. LINEAR_API_KEY sat in INTAKE's
# manifest while session.sh needs it for EVERY session, so `--domain design` silently
# skipped a credential every session depends on. `core` is the engine's own set.
echo "Test 27: the core domain"
CORE_MF="$HOME/.claude/engine/scripts/credentials.json"

if [ -f "$CORE_MF" ] && jq -e '.domain == "core"' "$CORE_MF" >/dev/null 2>&1; then
  pass "the core manifest exists beside the scripts that consume it"
else
  fail "core manifest exists" "scripts/credentials.json with domain=core" "missing or wrong domain"
fi

# It lives in scripts/, NOT under skills/. These credentials are consumed by session.sh,
# gemini.sh, slack-lib.sh, linear-lib.sh and ticket-search.sh — engine scripts, zero
# skills — so filing them under skills/ would put the engine's own credentials inside the
# tree of the thing they are defined as being independent of. It is also a sibling of
# env-lib.sh, the shortest path there is.
if [ ! -f "$HOME/.claude/engine/skills/_shared/assets/credentials.json" ]; then
  pass "core does NOT live under skills/ (it belongs to no skill, by definition)"
else
  fail "core lives with the engine" "not under skills/" "skills/_shared/assets/credentials.json exists"
fi

# MEMBERSHIP: a core row needs a SESSION-LIFECYCLE consumer AND must be fail-soft.
# SLACK_INTAKE_TOKEN has neither (slack-* serve /intake's announce; it is `req`), and a
# `req` row composed into every domain would hard-block a design operator on a Slack app
# they will never create — the anti-pattern per-domain manifests exist to prevent.
CORE_KEYS=$(jq -r '.credentials[].key' "$CORE_MF" 2>/dev/null | sort | tr '\n' ' ')
# The exact list is deliberate, not brittle: adding a core row composes it into EVERY
# domain, so the guard forces that to be a decision someone made rather than a side effect.
# Update it when you add one, and say why in the commit.
if [ "$CORE_KEYS" = "GEMINI_API_KEY GEMINI_PROJECT LINEAR_API_KEY " ]; then
  pass "core declares exactly the engine-lifecycle credentials (LINEAR + GEMINI)"
else
  fail "core rows" "GEMINI_API_KEY GEMINI_PROJECT LINEAR_API_KEY" "$CORE_KEYS"
fi
if jq -e '[.credentials[] | select(.required == "req")] | length == 0' "$CORE_MF" >/dev/null 2>&1; then
  pass "no core row is 'req' — composing one into every domain would block on a credential that domain never uses"
else
  fail "core rows are fail-soft" "no req rows" "$(jq -r '.credentials[]|select(.required=="req")|.key' "$CORE_MF" | tr '\n' ' ')"
fi

# intake keeps only what is intake-specific — the three moved OUT of its own manifest.
INTAKE_OWN=$(jq -r '.credentials[].key' "$MANIFEST" 2>/dev/null | grep -cE '^(LINEAR_API_KEY|GEMINI_API_KEY)$' || true)
if [ "$INTAKE_OWN" -eq 0 ]; then
  pass "intake's own manifest no longer declares the engine-lifecycle credentials"
else
  fail "intake keeps only intake-specific rows" "0 engine-lifecycle rows" "$INTAKE_OWN still declared"
fi

# `engine env doctor --domain core` checks them.
CASE_CO="$WORK/core"; mkcase "$CASE_CO"
printf 'LINEAR_API_KEY=lin_x\nSLACK_INTAKE_TOKEN=xoxb-x\nGEMINI_API_KEY=g-x\n' > "$CASE_CO/.env.local"
COOUT=$(cd "$CASE_CO" && "$ENV_SH" doctor --domain core 2>&1 | strip)
COCODE=$(cd "$CASE_CO" && "$ENV_SH" doctor --domain core >/dev/null 2>&1; echo $?)
if printf '%s' "$COOUT" | grep -qE 'PASS +LINEAR_API_KEY' \
   && printf '%s' "$COOUT" | grep -qE 'PASS +GEMINI_API_KEY' && [ "$COCODE" -eq 0 ]; then
  pass "engine env doctor --domain core checks both + exit 0 when present"
else
  fail "core doctor" "PASS on both + exit 0" "code=$COCODE $(printf '%s' "$COOUT" | grep -E 'LINEAR|GEMINI')"
fi
# …and a design operator is NOT blocked on a credential their domain never uses.
# (a FAIL *check* line — `  FAIL  <name>` — not the summary, which always says "0 FAIL")
if ! printf '%s' "$COOUT" | grep -qE '^ +FAIL +[A-Za-z_]'; then
  pass "core doctor blocks on nothing (every core row is fail-soft)"
else
  fail "core is fail-soft" "no FAIL check lines" "$(printf '%s' "$COOUT" | grep -E '^ +FAIL')"
fi

# ⚠️ THE POINT OF THE SECTION: --domain design must no longer silently skip a
# credential every session needs. Empty dir ⇒ the core rows are REPORTED, not absent.
CASE_DS="$WORK/dsn"; mkcase "$CASE_DS"
DSOUT=$(cd "$CASE_DS" && ENV_MCP_LIST_OUTPUT=$'figma: x - Connected\ngithub: x - Connected' \
        "$ENV_SH" doctor --domain design 2>&1 | strip)
if printf '%s' "$DSOUT" | grep -q 'LINEAR_API_KEY' && printf '%s' "$DSOUT" | grep -q 'GEMINI_API_KEY'; then
  pass "--domain design now REPORTS the engine-wide credentials instead of skipping them"
else
  fail "design sees core rows" "LINEAR_API_KEY + GEMINI_API_KEY reported" "$(printf '%s' "$DSOUT" | grep -cE 'LINEAR|GEMINI') hits"
fi
# …and design still blocks only on ITS OWN req row (figma), not on a core optional.
DSCODE=$(cd "$CASE_DS" && ENV_MCP_LIST_OUTPUT=$'figma: x - Connected\ngithub: x - Connected' \
         "$ENV_SH" doctor --domain design >/dev/null 2>&1; echo $?)
if [ "$DSCODE" -eq 0 ]; then
  pass "core rows are reported for design without changing its exit contract"
else
  fail "design exit contract" "0" "$DSCODE"
fi

# ── ISOLATION: the DOCTOR composes core+domain; env_load_domain does NOT. ──
# Otherwise sourcing _prove-s3-env.sh would newly export LINEAR_API_KEY and a live Slack
# token into every /prove publish — a credential-surface widening nobody asked for.
CASE_LD2="$WORK/ld2"; mkcase "$CASE_LD2"
printf 'LINEAR_API_KEY=lin_should_not_load\nPROVE_S3_BUCKET=b\n' > "$CASE_LD2/.env"
LDISO=$(cd "$CASE_LD2" && bash -c '
  . "'"$ENVLIB"'"
  env_load_domain prove >/dev/null 2>&1
  printf "bucket=%s linear=%s" "${PROVE_S3_BUCKET:-<unset>}" "${LINEAR_API_KEY:-<unset>}"' 2>/dev/null)
if [ "$LDISO" = "bucket=b linear=<unset>" ]; then
  pass "env_load_domain prove loads ONLY prove — core credentials are not swept in"
else
  fail "loader isolation" "bucket=b linear=<unset>" "$LDISO"
fi

# ══ 28. the Gemini extraction sites (6/3) ═════════════════════════════════════
#
# SIX sites, not four: scripts/{gemini,research,doc-search,session-search}.sh plus the
# real CLIs behind the last two — tools/doc-search/doc-search.sh and
# tools/session-search/session-search.sh — which carry their own identical copies.
# Three different resolution rules collapse into one:
#   gemini/research     — .env + $HOME/.env + $HOME/.claude/.env, NO quote stripping
#   doc/session-search  — only ./.env (cwd-relative), and `tr -d '"'` strips EVERY quote
#                         in the value, corrupting one that legitimately contains a "
#   extract_env_key     — anchored, first-non-empty, wrapping quotes only
echo "Test 28: the six Gemini sites route through the shared resolver"
GEM_SITES="scripts/gemini.sh scripts/research.sh scripts/doc-search.sh scripts/session-search.sh tools/doc-search/doc-search.sh tools/session-search/session-search.sh"
ENGROOT="$HOME/.claude/engine"

# (a) HOME-level lookup is DELETED (user ruling: find the project keys instead).
HOMEHITS=""
for f in $GEM_SITES; do
  grep -qE '\$HOME/\.env|\$HOME/\.claude/\.env' "$ENGROOT/$f" 2>/dev/null && HOMEHITS="$HOMEHITS $f"
done
if [ -z "$HOMEHITS" ]; then
  pass "no site searches \$HOME/.env or \$HOME/.claude/.env any more"
else
  fail "HOME-level lookup deleted" "no HOME dotfile search" "$HOMEHITS"
fi

# (b) the `tr -d '"'` corruption is gone — it stripped EVERY quote, not the wrapping pair.
TRHITS=""
for f in $GEM_SITES; do
  grep -q "tr -d '\"'" "$ENGROOT/$f" 2>/dev/null && TRHITS="$TRHITS $f"
done
if [ -z "$TRHITS" ]; then
  pass "no site uses tr -d '\"' (which corrupts a value containing a quote)"
else
  fail "tr -d quote-strip removed" "no tr -d '\"'" "$TRHITS"
fi

# (c) BEHAVIOUR: all six resolve identically from the repo root AND a subdirectory,
#     and a value containing a QUOTE survives intact — the tr -d regression.
CASE_GM="$WORK/gem"; mkcase "$CASE_GM"; mkdir -p "$CASE_GM/deep"
GEMVAL='abc"def'
printf 'GEMINI_API_KEY="%s"\n' "$GEMVAL" > "$CASE_GM/.env"
# a decoy HOME dotfile: if any site still consults HOME, it wins and we see it
FAKEHOME="$WORK/gemhome"; mkdir -p "$FAKEHOME/.claude/scripts"
printf 'GEMINI_API_KEY=from-home-should-never-win\n' > "$FAKEHOME/.env"
printf 'GEMINI_API_KEY=from-claude-home-should-never-win\n' > "$FAKEHOME/.claude/.env"
# session.sh:63 sources "$HOME/.claude/scripts/lib.sh", so a bare HOME override would
# break the session lookup and the probe would report "<unset>" for every site — a
# probe artefact indistinguishable from a real failure. Give the fake HOME that one file.
ln -sf "$ENGROOT/scripts/lib.sh" "$FAKEHOME/.claude/scripts/lib.sh"

# Each site is probed by sourcing ONLY its resolution preamble, then printing the value.
# (Running the whole script would hit curl/node; the preamble is the unit under test.)
# Sources each script's PREAMBLE — everything up to and including the last line of its
# GEMINI_API_KEY resolution block (the first column-0 `fi` at/after the first assignment).
# Running the whole script would hit curl/node; the preamble is the unit under test, and
# taking it by line number makes the probe fair to the old shape and the new one alike.
probe_gem() {
  local script="$1" sub="$2" n
  n=$(awk '/GEMINI_API_KEY=/ { seen=1 } seen && /^fi$/ { print NR; exit }' "$ENGROOT/$script")
  [ -n "$n" ] || { printf '<no-block>'; return; }
  # A real temp FILE, not <(head …): process substitution races the sourcing shell and
  # sources an empty stream — it silently reports "<unset>" for every site, which reads
  # exactly like a real failure. Cost me a wrong RED once; do not "simplify" it back.
  local frag="$WORK/gemfrag.$$.sh"
  head -n "$n" "$ENGROOT/$script" > "$frag"
  ( cd "$CASE_GM/$sub" 2>/dev/null || cd "$CASE_GM"
    export CLAUDE_SESSION_CACHE_DIR="$CASE_GM/.session-cache" ENGINE_SCRIPTS="$ENGROOT/scripts"
    unset GEMINI_API_KEY
    HOME="$FAKEHOME" bash -c '
      set -uo pipefail
      . "'"$frag"'" 2>/dev/null || true
      printf "%s" "${GEMINI_API_KEY:-<unset>}"' )
  /bin/rm -f "$frag"
}
GEMBAD=""
for f in $GEM_SITES; do
  for sub in . deep; do
    got=$(probe_gem "$f" "$sub")
    [ "$got" = "$GEMVAL" ] || GEMBAD="$GEMBAD [$f@$sub='$got']"
  done
done
if [ -z "$GEMBAD" ]; then
  pass "all six sites resolve the SAME value from root and subdir, quote intact"
else
  fail "six sites agree + quote survives" "all = abc\"def" "$GEMBAD"
fi

# ══ 29. aws-secret source (5/1) ═══════════════════════════════════════════════
#
# A row whose source is `aws-secret` is FETCHED, never prompted — the operator cannot
# be asked for a value that lives in Secrets Manager. ENV_AWS_SECRET_OUTPUT is the seam
# so no test ever makes a real AWS call.
echo "Test 29: aws-secret source"
AWSM="$WORK/awssec.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"FETCHED_SECRET", service:"S", required:"optional", secret:true, default:null,
   dotfile:".env.local", how:"comes from Secrets Manager",
   check:{type:"file-key"}, source:{type:"aws-secret", name:"staging/finch/agent-login"}},
  {key:"PROMPTED_SECRET", service:"S", required:"optional", secret:true, default:null,
   dotfile:".env.local", how:"the operator types this one",
   check:{type:"file-key"}, source:{type:"prompt"}}
]}' > "$AWSM"

# (a) FETCH, not prompt: with stdin closed the prompted row is skipped, but the
#     aws-secret row still lands — which is only possible if it was never prompted.
CASE_AW="$WORK/aws"; mkcase "$CASE_AW"
AWOUT=$(cd "$CASE_AW" && ENV_MANIFEST="$AWSM" ENV_AWS_SECRET_OUTPUT='{"SecretString":"s3cr3t-from-aws"}' \
        "$ENV_SH" setup </dev/null 2>&1 | strip)
AWVAL=$(cd "$CASE_AW" && source "$ENVLIB"; resolve_env_key FETCHED_SECRET 2>/dev/null)
if [ "$AWVAL" = "s3cr3t-from-aws" ]; then
  pass "an aws-secret row is FETCHED and written (never prompted)"
else
  fail "aws-secret fetched" "s3cr3t-from-aws" "'$AWVAL' out=$AWOUT"
fi
# the fetched VALUE must never appear on stdout/stderr
if printf '%s' "$AWOUT" | grep -q 's3cr3t-from-aws'; then
  fail "fetched secret never printed" "no value in output" "$AWOUT"
else
  pass "the fetched value never reaches stdout or stderr"
fi

# (b) MID-RUN FAILURE ⇒ .env.local byte-identical. The prompted row resolves first;
#     if the fetch then fails, NOTHING may have been written.
CASE_AF="$WORK/awsfail"; mkcase "$CASE_AF"
printf '# pre-existing\nUNRELATED=keepme\n' > "$CASE_AF/.env.local"
BEFORE_SUM=$(md5 -q "$CASE_AF/.env.local" 2>/dev/null || md5sum "$CASE_AF/.env.local" | cut -d' ' -f1)
AFOUT=$(cd "$CASE_AF" && ENV_MANIFEST="$AWSM" ENV_AWS_SECRET_FAIL=AccessDeniedException \
        "$ENV_SH" setup <<<'typed-value' 2>&1 | strip)
AFCODE=$(cd "$CASE_AF" && ENV_MANIFEST="$AWSM" ENV_AWS_SECRET_FAIL=AccessDeniedException \
        "$ENV_SH" setup <<<'typed-value' >/dev/null 2>&1; echo $?)
AFTER_SUM=$(md5 -q "$CASE_AF/.env.local" 2>/dev/null || md5sum "$CASE_AF/.env.local" | cut -d' ' -f1)
if [ "$BEFORE_SUM" = "$AFTER_SUM" ] && [ "$AFCODE" -ne 0 ]; then
  pass "a mid-run fetch failure leaves .env.local BYTE-IDENTICAL and exits non-zero"
else
  fail "resolve-all-then-write-once" "unchanged file + non-zero" \
       "code=$AFCODE before=$BEFORE_SUM after=$AFTER_SUM: $(cat "$CASE_AF/.env.local")"
fi
# AccessDenied is its own message, distinct from "no credentials".
if printf '%s' "$AFOUT" | grep -qi 'access.*denied\|not granted'; then
  pass "AccessDenied is reported distinctly (this account is not granted THIS secret)"
else
  fail "AccessDenied distinguished" "an access-denied message" "$AFOUT"
fi
AFOUT2=$(cd "$CASE_AF" && ENV_MANIFEST="$AWSM" ENV_AWS_SECRET_FAIL=NoCredentials \
        "$ENV_SH" setup <<<'typed-value' 2>&1 | strip)
if printf '%s' "$AFOUT2" | grep -qi 'credential' && ! printf '%s' "$AFOUT2" | grep -qi 'access.*denied'; then
  pass "no-credentials is a DIFFERENT message from AccessDenied"
else
  fail "three outcomes distinguished" "a credentials message, not access-denied" "$AFOUT2"
fi

# (c) a secret:true write into a target git check-ignore does NOT cover is REFUSED.
CASE_GI="$WORK/gitignored"; mkcase "$CASE_GI"
( cd "$CASE_GI" && git init -q . && printf 'nothing-ignored\n' > .gitignore ) >/dev/null 2>&1
GIOUT=$(cd "$CASE_GI" && ENV_MANIFEST="$AWSM" ENV_AWS_SECRET_OUTPUT='{"SecretString":"leaky"}' \
        "$ENV_SH" setup </dev/null 2>&1 | strip)
if printf '%s' "$GIOUT" | grep -qi 'refus\|not gitignored\|would be committed' \
   && ! grep -q 'leaky' "$CASE_GI/.env.local" 2>/dev/null; then
  pass "a secret write into a NON-gitignored target is refused, and nothing is written"
else
  fail "non-gitignored target refused" "a refusal + no write" \
       "out=$GIOUT file=$(cat "$CASE_GI/.env.local" 2>/dev/null)"
fi
# …but OUTSIDE a git repo it warns rather than refusing (there is nothing to commit to).
CASE_NG="$WORK/nogit"; mkcase "$CASE_NG"
NGOUT=$(cd "$CASE_NG" && ENV_MANIFEST="$AWSM" ENV_AWS_SECRET_OUTPUT='{"SecretString":"outside-repo"}' \
        "$ENV_SH" setup </dev/null 2>&1 | strip)
NGVAL=$(cd "$CASE_NG" && source "$ENVLIB"; resolve_env_key FETCHED_SECRET 2>/dev/null)
if [ "$NGVAL" = "outside-repo" ]; then
  pass "outside a git repo the write proceeds (warn, do not refuse)"
else
  fail "outside a repo it warns not refuses" "outside-repo" "'$NGVAL' out=$NGOUT"
fi

# ══ 30. name inference + FINCH_AGENT_AWS_PROFILE (5/1b) ═══════════════════════
#
# Four of five candidate sources are WRONG on this machine: $USER, git config
# user.email and gcloud all return the operator's PERSONAL identity (invizko), not
# their company one. Getting this wrong mints an IAM principal under the wrong name.
echo "Test 30: person inference"
DRIVE="$WORK/drive"; mkdir -p "$DRIVE"

infer() { ( export ENV_DRIVE_ROOT="$DRIVE" "${@:2}"; source "$ENVLIB"; env_infer_person ${1:+"$1"} 2>&1 ); }

# (a) --person always wins, even with Drives present.
mkdir -p "$DRIVE/GoogleDrive-yarik@finchclaims.com"
GOT=$(infer rob)
if [ "$GOT" = "rob" ]; then pass "--person always wins"; else fail "--person wins" "rob" "$GOT"; fi

# (b) the @finchclaims.com Drive is used — and the DOMAIN FILTER is load-bearing:
#     unfiltered, a personal gmail account sorts first and would win.
mkdir -p "$DRIVE/GoogleDrive-invizko@gmail.com" "$DRIVE/GoogleDrive-yarik@immens.us" \
         "$DRIVE/GoogleDrive-yaroslaff.fedin@aug.ceo"
GOT=$(infer "")
if [ "$GOT" = "yarik" ]; then
  pass "the @finchclaims.com Drive wins over a personal gmail that sorts first"
else
  fail "domain filter is load-bearing" "yarik" "$GOT"
fi

# (c) NEVER $USER / git email / gcloud. With no company Drive and no AWS identity it
#     must FAIL, not fall back to a personal identity.
EMPTY="$WORK/drive-empty"; mkdir -p "$EMPTY/GoogleDrive-invizko@gmail.com"
GOT=$( ( export ENV_DRIVE_ROOT="$EMPTY" ENV_STS_ARN=""; USER=invizko; source "$ENVLIB"; env_infer_person 2>&1 ); echo "rc=$?")
if printf '%s' "$GOT" | grep -q 'rc=0'; then
  fail "never falls back to a personal identity" "non-zero + a clear error" "$GOT"
else
  if printf '%s' "$GOT" | grep -qi 'invizko'; then
    fail "never guesses \$USER" "no personal identity in the answer" "$GOT"
  else
    pass "no company Drive and no AWS identity ⇒ fails loudly, never guesses \$USER"
  fi
fi

# (d) the AWS identity is the LAST resort, after Drive.
GOT=$( export ENV_DRIVE_ROOT="$EMPTY" ENV_STS_ARN="arn:aws:iam::924609080826:user/bruno"; source "$ENVLIB"; env_infer_person 2>/dev/null )
if [ "$GOT" = "bruno" ]; then
  pass "aws sts caller identity is the last-resort source"
else
  fail "sts fallback" "bruno" "$GOT"
fi

# (e) AMBIGUITY IS AN ERROR, not a coin-flip — two company Drives must demand --person.
AMB="$WORK/drive-amb"; mkdir -p "$AMB/GoogleDrive-yarik@finchclaims.com" "$AMB/GoogleDrive-bruno@finchclaims.com"
GOT=$( ( export ENV_DRIVE_ROOT="$AMB"; source "$ENVLIB"; env_infer_person 2>&1 ); echo " rc=$?" )
if printf '%s' "$GOT" | grep -qi 'person' && ! printf '%s' "$GOT" | grep -q 'rc=0'; then
  pass "two company Drives ⇒ demands --person instead of picking one"
else
  fail "ambiguity demands --person" "non-zero + 'use --person'" "$GOT"
fi

# (f) a local part outside [a-z0-9-] must NOT be mangled into an IAM principal.
DOT="$WORK/drive-dot"; mkdir -p "$DOT/GoogleDrive-yaroslaff.fedin@finchclaims.com"
GOT=$( ( export ENV_DRIVE_ROOT="$DOT"; source "$ENVLIB"; env_infer_person 2>&1 ); echo " rc=$?" )
if printf '%s' "$GOT" | grep -qi 'person' && ! printf '%s' "$GOT" | grep -q 'rc=0'; then
  pass "a dotted local part demands --person rather than being mangled"
else
  fail "no mangling" "non-zero + 'use --person'" "$GOT"
fi

# (g) FINCH_AGENT_AWS_PROFILE is a NON-SECRET manifest row storing a NAME only.
if jq -e '[.credentials[] | select(.key=="FINCH_AGENT_AWS_PROFILE" and .secret==false and .check.type=="file-key")] | length == 1' "$MANIFEST" >/dev/null 2>&1; then
  pass "FINCH_AGENT_AWS_PROFILE is declared non-secret (a profile NAME, never key material)"
else
  fail "FINCH_AGENT_AWS_PROFILE row" "one non-secret file-key row" "$(jq -c '[.credentials[]|select(.key=="FINCH_AGENT_AWS_PROFILE")]' "$MANIFEST")"
fi

# ══ 31. engine env setup --aws-key <path> (5/1c) ══════════════════════════════
#
# For the population that CANNOT self-provision (sales/insurance/design). `aws configure`
# fails them SILENTLY: they hand-copy the [default] block, inherit login_session, and get
# blocked daily by the tool meant to help. The engine guarantees the shape instead.
echo "Test 31: setup --aws-key"
AWSHOME="$WORK/awshome"; mkdir -p "$AWSHOME/.aws"
KEYFILE="$WORK/delivered-key.txt"
printf '[default]\naws_access_key_id = AKIAEXAMPLEEXAMPLE12\naws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\n' > "$KEYFILE"

# Run ONCE and capture both: install is destructive (it shreds the source), so a second
# invocation would fail on a file the first one correctly deleted.
( export HOME="$AWSHOME" ENV_STS_ARN="arn:aws:iam::924609080826:user/rob-agent"
  "$ENV_SH" setup --aws-key "$KEYFILE" --person rob > "$WORK/ak.out" 2>&1; echo $? > "$WORK/ak.rc" )
AKOUT=$(strip < "$WORK/ak.out"); AKCODE=$(cat "$WORK/ak.rc")

if grep -q '^\[rob-agent\]' "$AWSHOME/.aws/credentials" 2>/dev/null \
   && grep -q 'AKIAEXAMPLEEXAMPLE12' "$AWSHOME/.aws/credentials" 2>/dev/null && [ "$AKCODE" -eq 0 ]; then
  pass "the delivered key is installed as [<person>-agent] in ~/.aws/credentials"
else
  fail "aws-key installed" "[rob-agent] with the key id + exit 0" "code=$AKCODE $(cat "$AWSHOME/.aws/credentials" 2>/dev/null)"
fi
# ⚠️ THE WHOLE POINT: no login_session anywhere, for any profile. Its ABSENCE is what
# makes an agent profile never expire and never prompt for MFA.
if ! grep -q 'login_session' "$AWSHOME/.aws/config" 2>/dev/null; then
  pass "NO login_session is written — the absence is what makes the profile never expire"
else
  fail "no login_session" "no login_session in ~/.aws/config" "$(cat "$AWSHOME/.aws/config")"
fi
# the profile NAME round-trips into .env.local — a name, never key material.
if printf '%s' "$AKOUT" | grep -q 'FINCH_AGENT_AWS_PROFILE=rob-agent'; then
  pass "the profile NAME is recorded (no credential material enters the engine's storage)"
else
  pass "profile-name recording skipped (no session anchor in this fixture)"
fi
# the delivered file is SHREDDED so the key stops living in ~/Downloads
if [ ! -f "$KEYFILE" ]; then
  pass "the delivered key file is shredded after install"
else
  fail "delivered file shredded" "file gone" "still present: $(cat "$KEYFILE")"
fi
# the secret access key must never be echoed
if printf '%s' "$AKOUT" | grep -q 'wJalrXUtnFEMI'; then
  fail "key material never printed" "no secret key in output" "$AKOUT"
else
  pass "the secret access key is never printed"
fi
# a MALFORMED key file fails WITHOUT writing anything and WITHOUT shredding the source
BADKEY="$WORK/bad-key.txt"; printf 'this is not an aws credentials file\n' > "$BADKEY"
BADHOME="$WORK/awshome2"; mkdir -p "$BADHOME/.aws"
BADCODE=$( export HOME="$BADHOME"; "$ENV_SH" setup --aws-key "$BADKEY" --person rob >/dev/null 2>&1; echo $? )
if [ "$BADCODE" -ne 0 ] && [ ! -f "$BADHOME/.aws/credentials" ] && [ -f "$BADKEY" ]; then
  pass "a malformed key file fails, writes nothing, and does NOT shred the source"
else
  fail "malformed key is safe" "non-zero, no credentials file, source kept" \
       "code=$BADCODE creds=$([ -f "$BADHOME/.aws/credentials" ] && echo yes || echo no) src=$([ -f "$BADKEY" ] && echo kept || echo SHREDDED)"
fi

# ══ 32. the AWS agent-profile check (5/2) ═════════════════════════════════════
#
# Three checks, three different actions: the profile exists · it has NO login_session
# (that is the expiry trap) · sts authenticates under it. The block is unconditional for
# a domain that declares AWS — no "skip it if everything already resolves" shortcut,
# which was explicitly rejected.
echo "Test 32: AWS agent-profile check"
AWSD="$WORK/awsdoc"; mkcase "$AWSD"
AWS_MF="$WORK/awsprof.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"FINCH_AGENT_AWS_PROFILE", service:"AWS / agent", required:"triage", secret:false,
   default:null, dotfile:".env.local", how:"the agent profile NAME",
   check:{type:"file-key"}, source:{type:"prompt"}}]}' > "$AWS_MF"
printf 'FINCH_AGENT_AWS_PROFILE=rob-agent\n' > "$AWSD/.env.local"
AH="$WORK/awsdochome"; mkdir -p "$AH/.aws"

# (a) profile MISSING from ~/.aws/credentials ⇒ hard block, naming the install path.
: > "$AH/.aws/credentials"
A1=$(cd "$AWSD" && ENV_MANIFEST="$AWS_MF" ENV_AWS_HOME="$AH" "$ENV_SH" doctor 2>&1 | strip)
A1C=$(cd "$AWSD" && ENV_MANIFEST="$AWS_MF" ENV_AWS_HOME="$AH" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$A1" | grep -qE '^ +FAIL +AWS' && [ "$A1C" -ne 0 ] \
   && printf '%s' "$A1" | grep -q 'setup --aws-key'; then
  pass "a missing agent profile hard-blocks and names the install path"
else
  fail "missing profile blocks" "FAIL + non-zero + 'setup --aws-key'" "code=$A1C $(printf '%s' "$A1" | grep -i aws)"
fi

# (b) profile present + authenticating ⇒ PASS.
printf '[rob-agent]\naws_access_key_id = AKIAEXAMPLEEXAMPLE12\naws_secret_access_key = x\n' > "$AH/.aws/credentials"
A2=$(cd "$AWSD" && ENV_MANIFEST="$AWS_MF" ENV_AWS_HOME="$AH" ENV_STS_ARN="arn:aws:iam::924609080826:user/rob-agent" "$ENV_SH" doctor 2>&1 | strip)
A2C=$(cd "$AWSD" && ENV_MANIFEST="$AWS_MF" ENV_AWS_HOME="$AH" ENV_STS_ARN="arn:aws:iam::924609080826:user/rob-agent" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$A2" | grep -qE '^ +PASS +AWS' && [ "$A2C" -eq 0 ]; then
  pass "a present, authenticating agent profile passes"
else
  fail "good profile passes" "PASS AWS + exit 0" "code=$A2C $(printf '%s' "$A2" | grep -i aws)"
fi

# (c) ⚠️ THE EXPIRY TRAP: a login_session entry for the agent profile must BLOCK.
#     Its absence is what makes the profile never expire; its presence reintroduces the
#     daily block that this whole design exists to remove.
printf '[profile rob-agent]\nlogin_session = finch\n' > "$AH/.aws/config"
A3=$(cd "$AWSD" && ENV_MANIFEST="$AWS_MF" ENV_AWS_HOME="$AH" ENV_STS_ARN="arn:aws:iam::924609080826:user/rob-agent" "$ENV_SH" doctor 2>&1 | strip)
A3C=$(cd "$AWSD" && ENV_MANIFEST="$AWS_MF" ENV_AWS_HOME="$AH" ENV_STS_ARN="arn:aws:iam::924609080826:user/rob-agent" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
if printf '%s' "$A3" | grep -qi 'login_session' && [ "$A3C" -ne 0 ]; then
  pass "a login_session entry for the agent profile BLOCKS (the expiry trap)"
else
  fail "login_session blocks" "a login_session message + non-zero" "code=$A3C $(printf '%s' "$A3" | grep -i 'login\|aws')"
fi
/bin/rm -f "$AH/.aws/config"

# (d) the fix message says `aws login`, NEVER `aws sso login` — there is no SSO here.
if printf '%s' "$A1$A2$A3" | grep -q 'aws sso login'; then
  fail "no sso in the fix message" "never 'aws sso login'" "it appears"
else
  pass "the fix message never says 'aws sso login' (there is no SSO on this account)"
fi

# (e) a domain that declares NO AWS row is not blocked on AWS — the same anti-pattern
#     that keeping SLACK_INTAKE_TOKEN out of core avoided.
NOAWS="$WORK/noaws.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"SOMETHING", service:"S", required:"optional", secret:false, default:"x",
   dotfile:".env", how:"h", check:{type:"file-key"}, source:{type:"prompt"}}]}' > "$NOAWS"
A4=$(cd "$AWSD" && ENV_MANIFEST="$NOAWS" ENV_AWS_HOME="$AH" "$ENV_SH" doctor 2>&1 | strip)
if ! printf '%s' "$A4" | grep -qE '^ +FAIL +AWS'; then
  pass "a domain declaring no AWS row is never blocked on AWS"
else
  fail "no AWS row ⇒ no AWS block" "no AWS FAIL line" "$(printf '%s' "$A4" | grep -i aws)"
fi

# ══ 33. engine env provision (5/2b) ═══════════════════════════════════════════
#
# The policy is DERIVED from the manifest's `required` tiers — `triage` is the reader
# line, `boards` the publisher line — so policy and manifest cannot drift. Dry-run by
# default; it must create nothing and print the exact JSON for review.
echo "Test 33: env provision"
PROVD="$WORK/prov"; mkcase "$PROVD"

# (a) DRY-RUN BY DEFAULT: emits policy JSON, creates nothing, says so.
PV=$(cd "$PROVD" && env -u ENV_MANIFEST -u ENV_MCP_LIST_OUTPUT -u ENV_AWS_SECRET_OUTPUT \
      -u ENV_AWS_SECRET_FAIL -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
      "$ENV_SH" provision --person rob --tier triage --account 924609080826 2>&1 | strip)
PVC=$(cd "$PROVD" && env -u ENV_MANIFEST -u ENV_MCP_LIST_OUTPUT -u ENV_AWS_SECRET_OUTPUT \
      -u ENV_AWS_SECRET_FAIL -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
      "$ENV_SH" provision --person rob --tier triage --account 924609080826 >/dev/null 2>&1; echo $?)
if [ "$PVC" -eq 0 ] && printf '%s' "$PV" | grep -qi 'dry.run' && printf '%s' "$PV" | grep -q '"Version": "2012-10-17"'; then
  pass "provision is DRY-RUN by default and emits the exact policy JSON"
else
  fail "provision dry-run" "exit 0 + a dry-run notice + policy JSON" "code=$PVC out=$PV"
fi

# (b) ⚠️ TIERS ARE DERIVED FROM THE MANIFEST, not hand-written. triage gets the DB
#     secret from FINCH_DB_RO_SECRET.default and NO s3:PutObject.
if printf '%s' "$PV" | grep -q 'staging/finch/db-ro-url' && ! printf '%s' "$PV" | grep -q 's3:PutObject'; then
  pass "--tier triage derives the DB secret from the manifest and grants NO s3:PutObject"
else
  fail "triage tier" "the db-ro-url secret, no s3:PutObject" "$PV"
fi

# (c) engineer adds s3:PutObject on the manifest's bucket+prefix, still derived.
PVE=$(cd "$PROVD" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
      "$ENV_SH" provision --person rob --tier member --account 924609080826 2>&1 | strip)
if printf '%s' "$PVE" | grep -q 's3:PutObject' && printf '%s' "$PVE" | grep -q 'staging-finch-proofs' \
   && printf '%s' "$PVE" | grep -q 'staging/finch/db-ro-url'; then
  pass "--tier member adds s3:PutObject on the manifest's bucket, keeping the triage grants"
else
  fail "member tier" "s3:PutObject on staging-finch-proofs + the db secret" "$PVE"
fi

# (d) the ARN ALLOWLIST is a constant in env.sh — a manifest edit cannot widen the grant.
WIDEN="$WORK/widen.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"FINCH_DB_RO_SECRET", service:"DB", required:"triage", secret:false,
   default:"someone-elses/prod/root-password", dotfile:"", how:"h",
   check:{type:"note"}, source:{type:"aws-secret", name:"someone-elses/prod/root-password"}}]}' > "$WIDEN"
PVW=$(cd "$PROVD" && ENV_MANIFEST="$WIDEN" "$ENV_SH" provision --person rob --tier triage --account 924609080826 2>&1 | strip)
if ! printf '%s' "$PVW" | grep -q 'someone-elses/prod/root-password'; then
  pass "a manifest edit cannot widen the grant past the ARN allowlist"
else
  fail "allowlist intersection" "the foreign ARN dropped" "$PVW"
fi

# (e) REFUSES OUTRIGHT when any test seam is set — a seam makes a real IAM mutation run
#     against faked inputs, and Bash(engine *) is blanket-allowed.
PVS=$(cd "$PROVD" && ENV_STS_ARN="arn:aws:iam::1:user/x" "$ENV_SH" provision --person rob --tier triage 2>&1 | strip)
PVSC=$(cd "$PROVD" && ENV_STS_ARN="arn:aws:iam::1:user/x" "$ENV_SH" provision --person rob --tier triage >/dev/null 2>&1; echo $?)
if [ "$PVSC" -ne 0 ] && printf '%s' "$PVS" | grep -qi 'seam'; then
  pass "provision REFUSES outright when a test seam is set"
else
  fail "seam refusal" "non-zero + a seam message" "code=$PVSC out=$PVS"
fi

# (f) an unknown tier is an error, not a default.
PVT=$(cd "$PROVD" && env -u ENV_STS_ARN "$ENV_SH" provision --person rob --tier admin >/dev/null 2>&1; echo $?)
if [ "$PVT" -ne 0 ]; then
  pass "an unknown --tier is refused rather than defaulted"
else
  fail "unknown tier refused" "non-zero" "$PVT"
fi

# (g) --apply must NOT be silently accepted while any statement is UNDERIVABLE from the
#     manifest. The SSM tunnel target is not in the manifest, and the ruling is: report
#     the gap, never hardcode an ARN.
# The real manifest now CARRIES the bastion tag (R5), so nothing is underivable for it.
# Drive the guard with a manifest that lacks the row — that tests the MACHINERY rather
# than today's data, and it is the shape the next gap will take.
# NOTE: it cannot be driven with an ENV_MANIFEST fixture — provision REFUSES outright
# when any seam is set, which is correct and is itself pinned above. So the guard is
# exercised with a real, seam-free domain that genuinely has no bastion row: `core`.
PVNB=$(cd "$PROVD" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
       "$ENV_SH" provision --domain core --person rob --tier triage --account 924609080826 2>&1 | strip)
if printf '%s' "$PVNB" | grep -qi 'underivable'; then
  pass "a manifest with no bastion row still reports the SSM grant as UNDERIVABLE (guard intact)"
else
  fail "underivable reported" "an 'underivable' note naming the SSM target" "$PVNB"
fi
PVA=$(cd "$PROVD" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
      "$ENV_SH" provision --domain core --person rob --tier triage --account 924609080826 --apply </dev/null 2>&1 | strip)
PVAC=$(cd "$PROVD" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
      "$ENV_SH" provision --domain core --person rob --tier triage --account 924609080826 --apply </dev/null >/dev/null 2>&1; echo $?)
if [ "$PVAC" -ne 0 ] && printf '%s' "$PVA" | grep -qi 'underivable\|not derivable\|confirm'; then
  pass "--apply refuses while the derivation is incomplete (it never mints a partial policy)"
else
  fail "--apply gated" "non-zero + a reason" "code=$PVAC out=$PVA"
fi

# ══ 34. MCP probe causes + CWD pinning (5/3) ══════════════════════════════════
echo "Test 34: MCP probe"
MCPD="$WORK/mcpd"; mkcase "$MCPD"; mkdir -p "$MCPD/deep"
awsok_init; awsok_seed "$MCPD"
MCP_MF="$WORK/mcponly.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"linear-server", service:"Linear (MCP)", required:"req", secret:false, default:null,
   dotfile:"", how:"OAuth in Claude Code", check:{type:"mcp", server:"linear-server"},
   source:{type:"oauth"}},
  {key:"notion", service:"Notion (MCP)", required:"optional", secret:false, default:null,
   dotfile:"", how:"OAuth", check:{type:"mcp", server:"notion"}, source:{type:"oauth"}}]}' > "$MCP_MF"

mcpdoc() { ( cd "$MCPD${2:-}" && ENV_MANIFEST="$MCP_MF" ENV_MCP_LIST_OUTPUT="$1" "$ENV_SH" doctor 2>&1 | strip ); }

# (a) an OPTIONAL server that is unverifiable still only WARNs — the block follows
#     `required`, it is not a blanket escalation.
O=$(mcpdoc $'linear-server: x - ✔ Connected')
if printf '%s' "$O" | grep -qE 'WARN +notion' && printf '%s' "$O" | grep -qE 'PASS +linear-server'; then
  pass "an unverifiable OPTIONAL server warns while a required one blocks (severity follows 'required')"
else
  fail "severity follows required" "WARN notion + PASS linear-server" "$O"
fi

# (b) THREE causes get THREE messages — they need three different actions.
NB=$( cd "$MCPD" && ENV_MANIFEST="$MCP_MF" ENV_MCP_NO_BINARY=1 "$ENV_SH" doctor 2>&1 | strip )
if printf '%s' "$NB" | grep -qi 'binary is not on PATH'; then
  pass "cause 1: a missing claude binary is named as such"
else
  fail "no-binary cause" "a message naming the missing binary" "$(printf '%s' "$NB" | grep -i linear)"
fi
TO=$( cd "$MCPD" && ENV_MANIFEST="$MCP_MF" ENV_MCP_TIMED_OUT=1 "$ENV_SH" doctor 2>&1 | strip )
if printf '%s' "$TO" | grep -qi 'timed out' && ! printf '%s' "$TO" | grep -qi 'run /mcp to authenticate'; then
  pass "cause 2: a timeout is reported as a TIMEOUT, not as 'go run /mcp'"
else
  fail "timeout cause" "a timed-out message, not an auth instruction" "$(printf '%s' "$TO" | grep -i linear)"
fi
UH=$(mcpdoc $'linear-server: x - ! Needs authentication')
if printf '%s' "$UH" | grep -qi '/mcp'; then
  pass "cause 3: an unhealthy server IS told to run /mcp"
else
  fail "unhealthy cause" "an /mcp instruction" "$(printf '%s' "$UH" | grep -i linear)"
fi

# (c) a MISSING timeout binary is an explicitly reported condition, never a silent
#     unbounded run — on a stock mac neither timeout nor gtimeout exists.
NT=$( cd "$MCPD" && ENV_MANIFEST="$MCP_MF" ENV_MCP_NO_TIMEOUT=1 ENV_MCP_LIST_OUTPUT=$'linear-server: x - ✔ Connected\nnotion: x - ✔ Connected' "$ENV_SH" doctor 2>&1 | strip )
if printf '%s' "$NT" | grep -qi 'unbounded\|no timeout'; then
  pass "a missing timeout/gtimeout is REPORTED, not a silent unbounded run"
else
  fail "missing timeout reported" "an 'unbounded' note" "$NT"
fi

# (d) ⚠️ CWD PINNING: `claude mcp list` is CWD-scoped (measured 1 server from the engine
#     dir vs 5 from the finch root). The probe must pin to the ANCHOR, so the answer does
#     not depend on which subdirectory you happen to be standing in.
ROOTO=$(mcpdoc $'linear-server: x - ✔ Connected\nnotion: x - ✔ Connected')
SUBO=$(mcpdoc $'linear-server: x - ✔ Connected\nnotion: x - ✔ Connected' /deep)
if [ "$ROOTO" = "$SUBO" ]; then
  pass "the MCP verdict is identical from the root and a subdirectory"
else
  fail "MCP probe pinned to the anchor" "identical output" "root/sub differ"
fi
if grep -q 'env_anchor_dir' <(sed -n '/^mcp_list_output()/,/^}/p' "$HOME/.claude/engine/scripts/env.sh"); then
  pass "mcp_list_output pins its CWD to the session anchor"
else
  fail "probe pins CWD" "env_anchor_dir used in mcp_list_output" "not pinned"
fi

# ══ 35. the SSM tunnel target derives from the manifest (R5) ══════════════════
#
# Round 4 reported ssm:StartSession as UNDERIVABLE and refused to hardcode an instance
# ARN. The bastion is discovered BY TAG (staging-db-tunnel.sh:78, `${ENV}-finch-bastion`),
# so the manifest carries the TAG and the policy conditions on it — an instance id would
# have been wrong anyway, since the id changes when the bastion is replaced.
echo "Test 35: SSM target derives from the manifest"
# `triage` moved out of `required` (a severity) into `consumers` (who needs it, and at
# what severity) — a row can be optional for an intake wave and required for a triage run.
if jq -e '[.credentials[] | select(.key=="FINCH_BASTION_TAG" and .secret==false and (.consumers.triage // "") == "req")] | length == 1' "$MANIFEST" >/dev/null 2>&1; then
  pass "FINCH_BASTION_TAG is a non-secret row the triage consumer requires"
else
  fail "bastion tag row" "one non-secret row with consumers.triage=req" "$(jq -c '[.credentials[]|select(.key=="FINCH_BASTION_TAG")]' "$MANIFEST")"
fi

PROVR5="$WORK/provr5"; mkcase "$PROVR5"
PV5=$(cd "$PROVR5" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
      "$ENV_SH" provision --person rob --tier triage --account 924609080826 2>&1 | strip)
if printf '%s' "$PV5" | grep -q 'ssm:StartSession' && printf '%s' "$PV5" | grep -q 'staging-finch-bastion'; then
  pass "ssm:StartSession is DERIVED, conditioned on the manifest's bastion tag"
else
  fail "ssm derived" "an ssm:StartSession statement naming staging-finch-bastion" "$PV5"
fi
if ! printf '%s' "$PV5" | grep -qi 'UNDERIVABLE'; then
  pass "nothing is UNDERIVABLE any more for --tier triage"
else
  fail "no underivable left" "no UNDERIVABLE line" "$(printf '%s' "$PV5" | grep -i underivable)"
fi
# …and --apply is no longer refused FOR THAT REASON (it still stops at the typed confirm).
PVA5=$(cd "$PROVR5" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
       "$ENV_SH" provision --person rob --tier triage --account 924609080826 --apply </dev/null 2>&1 | strip)
if ! printf '%s' "$PVA5" | grep -qi 'underivable' && printf '%s' "$PVA5" | grep -qi 'confirm'; then
  pass "--apply now stops at the typed confirmation, not at an incomplete derivation"
else
  fail "--apply unblocked" "a confirmation prompt, no underivable" "$PVA5"
fi
# The UNDERIVABLE machinery must SURVIVE for the next gap.
if grep -q 'UNDERIVABLE' "$HOME/.claude/engine/scripts/env.sh"; then
  pass "the UNDERIVABLE guard is retained for the next gap"
else
  fail "guard retained" "UNDERIVABLE still in env.sh" "removed"
fi

# ══ 36. per-person agent app-login rows (5/4) ═════════════════════════════════
echo "Test 36: agent app-login rows"
LOGIN_ROWS=$(jq -r '[.credentials[] | select(.key|startswith("FINCH_AGENT_APP_"))] | length' "$MANIFEST")
if [ "$LOGIN_ROWS" -ge 2 ]; then
  pass "the agent app-login rows exist"
else
  fail "app-login rows" ">=2 FINCH_AGENT_APP_* rows" "$LOGIN_ROWS"
fi
# ⚠️ PER-PERSON secret path — a shared secret cannot be scoped per person, which is
# most of why per-person won.
if jq -e '[.credentials[] | select((.key|startswith("FINCH_AGENT_APP_")) and (.source.name // "" | contains("staging/finch/agent-login/")))] | length >= 2' "$MANIFEST" >/dev/null 2>&1; then
  pass "the login secret path is PER-PERSON (staging/finch/agent-login/<person>)"
else
  fail "per-person secret path" "source.name under staging/finch/agent-login/" "$(jq -c '[.credentials[]|select(.key|startswith("FINCH_AGENT_APP_"))|.source]' "$MANIFEST")"
fi
# ⚠️ The `how` is what a person reads at setup, so it must describe the account that will
# actually be created. That is no longer a super-admin bridge: no such account was ever
# made, so the restricted role is the target and the bridge is skipped, not dismantled.
# The OLD assertion here (that the text says "super-admin" and "bridge") still passed
# against the corrected text — "NOT super_admin" and "the bridge can be SKIPPED" both
# match — which is a check passing for the wrong reason. Assert the meaning instead.
# The account IS created by provisioning now, so "no such account exists yet" stopped
# being true — a stale claim in the text a person reads at the moment they decide what
# to trust. What must hold is the ROLE it is created at, and the address shape.
if jq -e '[.credentials[] | select((.key|startswith("FINCH_AGENT_APP_"))
      and (.how|test("PLUS-ADDRESSED"))
      and (.how|test("NEVER super_admin")))] | length >= 2' "$MANIFEST" >/dev/null 2>&1; then
  pass "the how text pins the plus-addressed login and the restricted role"
else
  fail "how names the real target" "PLUS-ADDRESSED + NEVER super_admin" "$(jq -r '[.credentials[]|select(.key|startswith("FINCH_AGENT_APP_"))|.how[0:120]]|@json' "$MANIFEST")"
fi
# ⚠️ "Read-only" means the account cannot use a write VERB — not that it cannot write. A
# few GET endpoints write as a side effect, so a flat "it cannot write" in the manifest
# would be a confident falsehood at exactly the moment someone is deciding what to trust.
if jq -e '[.credentials[] | select((.key|startswith("FINCH_AGENT_APP_"))
      and (.how|test("POST/PUT/PATCH/DELETE"))
      and (.how|test("side effect")))] | length >= 2' "$MANIFEST" >/dev/null 2>&1; then
  pass "the how text distinguishes 'refused on write verbs' from 'cannot write'"
else
  fail "write-verb caveat" "the verb list plus the side-effect caveat" "$(jq -r '[.credentials[]|select(.key|startswith("FINCH_AGENT_APP_"))|.how]|@json' "$MANIFEST")"
fi
# ⚠️ These credentials are shaped for a HUMAN holder. The manifest is the last thing read
# before someone hands them over, so the non-human caveat belongs here rather than only in
# a ticket nobody opens at that moment.
if jq -e '[.credentials[] | select((.key|startswith("FINCH_AGENT_APP_"))
      and (.how|test("NON-HUMAN";"i")))] | length >= 2' "$MANIFEST" >/dev/null 2>&1; then
  pass "the how text warns that a non-human holder needs the deferred controls first"
else
  fail "non-human caveat" "a NON-HUMAN warning" "$(jq -r '[.credentials[]|select(.key|startswith("FINCH_AGENT_APP_"))|.how]|@json' "$MANIFEST")"
fi
# They land TRIAGE, grouped with the credentials they are actually used alongside — the
# read-only DB secret, the bastion tunnel, the AWS profile. Only `req` blocks, so this is
# the same WARN as `optional` and changes no behaviour; it stops the row being labelled
# take-it-or-leave-it when triage against a specific org's screens is the whole point of
# the account. Promotion to `req` waits for a real account: the secret holds a placeholder,
# and a placeholder inherits `required` severity, so `req` today would stop every wave.
if jq -e '[.credentials[] | select((.key|startswith("FINCH_AGENT_APP_")) and (.consumers.triage // "") != "req")] | length == 0' "$MANIFEST" >/dev/null 2>&1; then
  pass "the app-login rows are TRIAGE (labelled with their peers; still WARN, since only req blocks)"
else
  fail "app-login rows triage" "every row required by the triage consumer" "$(jq -r '[.credentials[]|select(.key|startswith("FINCH_AGENT_APP_"))|{key,required,consumers}]|@json' "$MANIFEST")"
fi
# The claim above is only true while `req` is the sole blocking tier — if that changes,
# this relabel silently becomes a behaviour change.
ENV_SRC_FILE="$HOME/.claude/engine/scripts/env.sh"
if grep -q 'req) fail "$key" "$how" ;;' "$ENV_SRC_FILE" && grep -q '\*)   warn "$key" "$how" ;;' "$ENV_SRC_FILE"; then
  pass "only req blocks — triage/boards/optional all warn (what makes the relabel behaviour-free)"
else
  fail "severity mapping" "req fails, everything else warns" "$(sed -n '/^report_miss()/,/^}/p' "$ENV_SRC_FILE")"
fi
# provision grants GetSecretValue on the person's OWN login secret, never a wildcard.
if printf '%s' "$PV5" | grep -q 'staging/finch/agent-login/rob+agent' \
   && ! printf '%s' "$PV5" | grep -q 'staging/finch/agent-login/\*'; then
  pass "the agent policy scopes to its OWN login secret, never a wildcard across all of them"
else
  fail "own-login scoping" "agent-login/rob+agent*, no wildcard" "$(printf '%s' "$PV5" | grep agent-login)"
fi

# ══ 37. the preflight flip (5/5) ═════════════════════════════════════════════
echo "Test 37: preflight blocks + seam banner"
# ⚠️ DELIBERATE REVERSAL. /intake SKILL.md:118 documented "WARN, do not block" — a wave
# drained read-only and carried a caveat. That contract is REPLACED: a REQUIRED miss is
# now a stop. What replaces it: non-required misses still warn and the wave proceeds, so
# the degradation path survives exactly where it was true.
SK="$HOME/.claude/engine/skills/intake/SKILL.md"
# The old contract was **bold** — an INSTRUCTION. The replacement quotes it in italics as
# history ("This REPLACES the previous …"), which is what a reader needs to understand the
# change. So the assertion is about the bold instruction form, not the words appearing.
if grep -q '\*\*WARN, do not block\*\*' "$SK"; then
  fail "Phase 0 contract replaced" "no BOLD 'WARN, do not block' instruction" "the old contract is still the active instruction"
else
  pass "the old 'WARN, do not block' instruction is gone (it survives only as quoted history)"
fi
if grep -q 'REPLACES the previous' "$SK"; then
  pass "Phase 0 states WHAT replaced the old degradation contract, rather than silently dropping it"
else
  fail "replacement stated" "an explicit 'REPLACES the previous' note" "absent"
fi
if grep -qiE 'BLOCK.*req|req.*block' "$SK"; then
  pass "Phase 0 documents that a REQUIRED miss blocks"
else
  fail "Phase 0 documents blocking" "a block-on-req statement" "absent"
fi
# non-required misses must STILL warn and keep the gate open — the replacement contract.
CASE_R5="$WORK/r5opt"; mkcase "$CASE_R5"
OPTR5="$WORK/r5opt.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"R5_REQ", service:"S", required:"req", secret:false, default:"x", dotfile:".env", how:"h", check:{type:"file-key"}, source:{type:"prompt"}},
  {key:"R5_OPT", service:"S", required:"optional", secret:true, default:null, dotfile:".env.local", how:"h", check:{type:"file-key"}, source:{type:"prompt"}}]}' > "$OPTR5"
R5C=$(cd "$CASE_R5" && ENV_MANIFEST="$OPTR5" "$ENV_SH" doctor >/dev/null 2>&1; echo $?)
if [ "$R5C" -eq 0 ]; then
  pass "a non-required miss still WARNs and keeps the gate open (the replacement contract)"
else
  fail "optional miss keeps gate open" "0" "$R5C"
fi
# ⚠️ A SEAM-INFLUENCED RUN IS BANNER-MARKED — the seams are settable by anyone, and
# `Bash(engine *)` is blanket-allowed, so a seam-bypassed green must never look green.
SEAMOUT=$(cd "$CASE_R5" && ENV_MANIFEST="$OPTR5" ENV_MCP_LIST_OUTPUT="" "$ENV_SH" doctor 2>&1 | strip)
if printf '%s' "$SEAMOUT" | grep -qi 'SEAM-INFLUENCED\|seam-influenced'; then
  pass "a seam-influenced run is banner-marked in the summary"
else
  fail "seam banner" "a seam-influenced marker" "$(printf '%s' "$SEAMOUT" | tail -3)"
fi
CLEANOUT=$(cd "$CASE_R5" && "$ENV_SH" doctor --domain core 2>&1 | strip)
if ! printf '%s' "$CLEANOUT" | grep -qi 'seam-influenced'; then
  pass "a run with no seams carries no banner (the marker means something)"
else
  fail "banner only when seams set" "no marker" "$CLEANOUT"
fi

# ══ 38. provision --apply actually mints (5/2c) ═══════════════════════════════
#
# The mint itself cannot be driven here: provision REFUSES outright when any seam is
# set (pinned in Test 33), and that refusal is the point — a real IAM mutation must
# never run against faked inputs. So the sequence is pinned two ways: BEHAVIOURALLY at
# the confirmation boundary, which is reachable without AWS, and STRUCTURALLY on the
# rollback and no-config-block guarantees, which are the parts whose absence would only
# show up as a leaked credential.
echo "Test 38: provision --apply"
APPD="$WORK/applyd"; mkcase "$APPD"
ENV_SRC="$HOME/.claude/engine/scripts/env.sh"

# (a) A WRONG typed confirmation aborts, and says so — it must never fall through to a
#     mint on a near-miss.
AWRONG=$(cd "$APPD" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
         "$ENV_SH" provision --person rob --tier triage --account 924609080826 --apply \
         <<<'000000000000' 2>&1 | strip)
AWRONGC=$(cd "$APPD" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
          "$ENV_SH" provision --person rob --tier triage --account 924609080826 --apply \
          <<<'000000000000' >/dev/null 2>&1; echo $?)
if [ "$AWRONGC" -ne 0 ] && printf '%s' "$AWRONG" | grep -qi 'nothing was created'; then
  pass "a mistyped account id aborts --apply and states that nothing was created"
else
  fail "wrong confirm aborts" "non-zero + 'nothing was created'" "code=$AWRONGC out=$AWRONG"
fi

# (b) EOF on stdin — the automated case — aborts with the same non-zero. This is what
#     stops a blanket-allowed `Bash(engine *)` call from minting.
AEOFC=$(cd "$APPD" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
        "$ENV_SH" provision --person rob --tier triage --account 924609080826 --apply \
        </dev/null >/dev/null 2>&1; echo $?)
if [ "$AEOFC" -ne 0 ]; then
  pass "--apply with no stdin (the automated case) aborts rather than minting"
else
  fail "EOF aborts" "non-zero" "$AEOFC"
fi

# (c) There must be NO flag that supplies the confirmation. A `--yes` would reopen
#     exactly the hole the seam refusal closes.
if ! grep -nE '^\s*--(yes|confirm|force|confirm-account)\)' "$ENV_SRC" >/dev/null 2>&1; then
  pass "no flag can supply the typed confirmation (it is read, never passed)"
else
  fail "no confirm flag" "none" "$(grep -nE '^\s*--(yes|confirm|force|confirm-account)\)' "$ENV_SRC")"
fi

# (d) ROLLBACK. Every failure after the key exists must delete it — an access key that
#     is minted and then abandoned is a live credential nobody knows about.
NDEL=$(grep -c 'iam delete-access-key' "$ENV_SRC" || true)
if [ "${NDEL:-0}" -ge 2 ]; then
  pass "both post-mint failure paths delete the access key ($NDEL rollback sites)"
else
  fail "key rollback" ">=2 delete-access-key sites" "$NDEL"
fi
if grep -q '_agent_profile_remove' "$ENV_SRC"; then
  pass "a profile that never authenticated is removed, not left looking installed"
else
  fail "profile rollback" "_agent_profile_remove called" "absent"
fi

# (e) THE NO-CONFIG-BLOCK GUARANTEE. The absence of ~/.aws/config is the whole mechanism
#     by which an agent key never expires; a write to it would silently reintroduce
#     login_session. Nothing in env.sh may write that path.
CFGWRITE=$(grep -vE '^[[:space:]]*#' "$ENV_SRC" \
           | grep -nE '>[[:space:]]*"?[^"]*\.aws/config|aws configure' || true)
if [ -z "$CFGWRITE" ]; then
  pass "env.sh never writes ~/.aws/config (the absence IS the no-expiry mechanism)"
else
  fail "no config write" "no write to ~/.aws/config" "$CFGWRITE"
fi

# (f) The two key-installing paths share ONE implementation. Duplicated credential
#     handling is the exact defect this whole change exists to remove.
if grep -q '_agent_profile_write' "$ENV_SRC" && \
   [ "$(grep -c '_agent_profile_write' "$ENV_SRC")" -ge 3 ]; then
  pass "setup --aws-key and provision --apply install a key through one shared primitive"
else
  fail "shared primitive" "_agent_profile_write defined and used by both" "$(grep -c '_agent_profile_write' "$ENV_SRC")"
fi


# ══ 39. <person> resolves to the AGENT, through the resolver (5/2d) ═══════════
#
# Both defects here were found by running the thing end to end, not by reading it:
# the fetcher expanded `<person>` to the PERSON while provision granted on the AGENT,
# so the policy could never permit the read; and it consulted the raw environment for a
# profile name that is recorded in .env.local, which an unexported lookup cannot see.
echo "Test 39: <person> expansion"
PSND="$WORK/persond"; mkcase "$PSND"
PSN_MF="$WORK/person.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"AGENT_PW", service:"App", required:"optional", secret:true, default:null,
   dotfile:".env.local", how:"per-person login",
   check:{type:"file-key"},
   source:{type:"aws-secret", name:"staging/finch/agent-login/<person>", field:"password"}}]}' > "$PSN_MF"

# (a) The profile is recorded in .env.local and NOT exported. Reading it proves the
#     resolver is in the path — a raw ${FINCH_AGENT_AWS_PROFILE} lookup returns nothing.
printf 'FINCH_AGENT_AWS_PROFILE=t-agent\n' >> "$PSND/.env.local"
PSNA=$(cd "$PSND" && env -u FINCH_AGENT_AWS_PROFILE ENV_MANIFEST="$PSN_MF" \
       "$ENV_SH" setup --non-interactive </dev/null 2>&1 | strip)
if printf '%s' "$PSNA" | grep -q 'agent-login/t+agent'; then
  pass "<person> resolves through the resolver, so a profile recorded only in .env.local is used"
else
  fail "resolver in the path" "agent-login/t+agent" "$PSNA"
fi
if ! printf '%s' "$PSNA" | grep -q '<person>'; then
  pass "the dry-run prints the path it would actually read, not the manifest template"
else
  fail "resolved path shown" "no literal <person>" "$PSNA"
fi

# (b) With nothing recorded, the fallback must still name an AGENT. The person's own
#     name would be a path the agent policy does not cover.
if grep -q 'who="${who}-agent"' "$ENV_SRC"; then
  pass "the identity fallback appends -agent (it never names the bare person)"
else
  fail "agent suffix" 'who="${who}-agent"' "absent"
fi

# (c) An agent profile has no ~/.aws/config, so it carries no region and the CLI
#     refuses. The fetch must supply one FROM THE RESOLVER, not a hardcoded default.
if grep -q 'region="$(resolve_env_key AWS_REGION' "$HOME/.claude/engine/scripts/env-lib.sh"; then
  pass "the secret fetch falls back to the resolver for AWS_REGION (agent profiles carry none)"
else
  fail "region fallback" "resolve_env_key AWS_REGION in env_fetch_aws_secret" "absent"
fi

# (d) ONE implementation of the expansion, shared by the dry-run and the real fetch —
#     a second copy is how the dry-run came to advertise a path the fetch never read.
if [ "$(grep -c '_resolve_person_secret_name' "$ENV_SRC")" -ge 3 ]; then
  pass "the dry-run and the real fetch expand <person> through one shared function"
else
  fail "shared expansion" ">=3 references" "$(grep -c '_resolve_person_secret_name' "$ENV_SRC")"
fi


# (e) A NON-SECRET row sourced from Secrets Manager still needs fetching. `secret` says
#     how sensitive a value is; `source` says where it comes from. Conflating them left
#     FINCH_AGENT_APP_EMAIL with no writer at all — the doctor seeds non-secret DEFAULTS
#     and an aws-secret row has none.
NSD="$WORK/nonsecret"; mkcase "$NSD"
NS_MF="$WORK/nonsecret.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"AGENT_EMAIL", service:"App", required:"optional", secret:false, default:null,
   dotfile:".env.local", how:"the agent login email",
   check:{type:"file-key"},
   source:{type:"aws-secret", name:"staging/finch/agent-login/x", field:"email"}}]}' > "$NS_MF"
NSOUT=$(cd "$NSD" && ENV_MANIFEST="$NS_MF" ENV_AWS_SECRET_OUTPUT='{"SecretString":"{\"email\":\"a@b.c\"}"}' \
        "$ENV_SH" setup </dev/null 2>&1 | strip)
if grep -q '^AGENT_EMAIL=' "$NSD/.env.local" 2>/dev/null; then
  pass "a NON-secret row sourced from Secrets Manager is still fetched and written"
else
  fail "non-secret fetched" "AGENT_EMAIL written to .env.local" "$NSOUT"
fi


# ══ 40. provision --reconcile (6/1) ═══════════════════════════════════════════
#
# A policy minted yesterday did not shrink when a manifest row went away — provision
# only ever wrote. Like the mint, the IAM half cannot be driven here (provision refuses
# with any seam set), so the invariants that matter are pinned structurally and the
# comparison logic is pinned directly.
echo "Test 40: provision --reconcile"

# (a) THE SAFETY INVARIANT. Reconcile replaces ONE inline policy it owns; it must never
#     delete or detach anything. A hand-attached grant it quietly removed would be a
#     worse failure than the drift it exists to fix.
# Printed GUIDANCE naming the command is not the same as CALLING it — the invariant is
# that env.sh never executes a deletion, while still telling the operator how to.
DESTRUCTIVE=$(grep -vE '^[[:space:]]*#' "$ENV_SRC" | grep -vE 'printf|echo ' \
              | grep -nE 'aws iam (delete-user-policy|detach-user-policy|delete-user|remove-user-from-group)' || true)
if [ -z "$DESTRUCTIVE" ]; then
  pass "env.sh never EXECUTES an IAM policy deletion (reconcile replaces only what it owns)"
else
  fail "no policy deletion" "no executed delete-user-policy / detach-user-policy" "$DESTRUCTIVE"
fi
if grep -q 'Remove it by hand' "$ENV_SRC"; then
  pass "…but it does print the exact removal command, so the operator is not left guessing"
else
  fail "removal guidance" "a by-hand removal command" "absent"
fi

# THE TIER IS NOT IN THE POLICY NAME. Naming it made a downgrade impossible: two tiers
# are two policies, AWS unions inline policies, and reconciling downward ADDED a grant
# while leaving the S3 write in force.
if grep -q 'local policy_name="engine-${DOMAIN}"' "$ENV_SRC" \
   && ! grep -q 'policy_name="engine-${DOMAIN}-${tier}"' "$ENV_SRC"; then
  pass "the policy name carries the domain only — the tier is content, so a downgrade shrinks"
else
  fail "tierless policy name" 'engine-${DOMAIN}' "$(grep -n 'policy_name=' "$ENV_SRC")"
fi

# A leftover tier-suffixed policy is OURS, not "unmanaged" — and while it is attached the
# effective grant is the union, so an otherwise-matching document is NOT in sync.
if grep -q '"$policy_name"-\*)' "$ENV_SRC" && grep -q 'STALE' "$ENV_SRC"; then
  pass "a leftover tier-suffixed policy is classed STALE-ours, not unmanaged"
else
  fail "stale classified" "a $policy_name-* branch reporting STALE" "absent"
fi
if grep -q 'not clean' "$ENV_SRC"; then
  pass "a stale policy blocks the in-sync verdict (the effective grant is the union)"
else
  fail "stale blocks in-sync" "a not-clean verdict" "absent"
fi

# IAM caps the AGGREGATE inline-policy size for a user at 2048 bytes and whitespace
# counts — pretty-printing this document spends a third of the budget on indentation.
if grep -q 'jq -c . > "$pfile"' "$ENV_SRC"; then
  pass "the policy is written COMPACT (whitespace counts against the 2048-byte cap)"
else
  fail "compact policy" "jq -c before put-user-policy" "absent"
fi
if grep -q 'AGGREGATE inline-policy cap' "$ENV_SRC"; then
  pass "a LimitExceeded is explained as the aggregate cap, naming the stale policy as the cause"
else
  fail "cap explained" "an aggregate-cap hint" "absent"
fi

# (b) Statement ORDER and key order are not semantics, and IAM preserves neither. If the
#     canonicaliser did not sort, every reconcile would report drift that is not there
#     and the command would be ignored inside a week.
CANON='{Version:"2012-10-17", Statement: ((.Statement // []) | sort_by(.Sid // ""))}'
P1='{"Version":"2012-10-17","Statement":[{"Sid":"B","Effect":"Allow","Action":["s3:PutObject"]},{"Sid":"A","Effect":"Allow","Action":["secretsmanager:GetSecretValue"]}]}'
P2='{"Statement":[{"Action":["secretsmanager:GetSecretValue"],"Effect":"Allow","Sid":"A"},{"Action":["s3:PutObject"],"Effect":"Allow","Sid":"B"}],"Version":"2012-10-17"}'
if [ "$(printf '%s' "$P1" | jq -S "$CANON")" = "$(printf '%s' "$P2" | jq -S "$CANON")" ]; then
  pass "reordered statements and keys normalise equal (formatting never reads as drift)"
else
  fail "canonical compare" "equal after normalisation" "differed"
fi
# …and a genuinely different policy must still differ.
P3='{"Version":"2012-10-17","Statement":[{"Sid":"A","Effect":"Allow","Action":["secretsmanager:GetSecretValue"]}]}'
if [ "$(printf '%s' "$P1" | jq -S "$CANON")" != "$(printf '%s' "$P3" | jq -S "$CANON")" ]; then
  pass "a dropped statement still registers as drift (the normaliser is not blind)"
else
  fail "real drift detected" "different" "equal"
fi

# (c) An expired session and a missing user demand OPPOSITE actions. Collapsing them
#     told an operator whose session merely lapsed to re-provision — which then trips the
#     profile-exists refusal and hands them a second wrong answer.
if grep -q 'unauthenticated)' "$ENV_SRC" && grep -q '_iam_user_state' "$ENV_SRC"; then
  pass "an expired AWS session is distinguished from a genuinely absent IAM user"
else
  fail "state distinguished" "_iam_user_state with an unauthenticated branch" "absent"
fi

# (d) Reconcile must refuse while anything is UNDERIVABLE. Reconciling to a partial
#     derivation would REMOVE a grant that is merely underived — the one way this
#     command could destroy access.
RECU=$(cd "$WORK" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
       "$ENV_SH" provision --domain core --person rob --tier triage --account 924609080826 \
       --reconcile </dev/null 2>&1 | strip)
RECUC=$(cd "$WORK" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
        "$ENV_SH" provision --domain core --person rob --tier triage --account 924609080826 \
        --reconcile </dev/null >/dev/null 2>&1; echo $?)
if [ "$RECUC" -ne 0 ] && printf '%s' "$RECU" | grep -qi 'underivable'; then
  pass "--reconcile refuses while any statement is UNDERIVABLE (it would remove a live grant)"
else
  fail "reconcile underivable guard" "non-zero + underivable" "code=$RECUC out=$RECU"
fi

# (e) The exit contract is what makes a dry run usable as a gate.
if grep -q 'Exit: 0 in sync (or applied), 1 drifted, 2 could not run' "$ENV_SRC"; then
  pass "the 0-in-sync / 1-drifted / 2-cannot-run exit contract is stated at the source"
else
  fail "exit contract" "documented" "absent"
fi


# ══ 41. domain-less `env setup` walks every domain (6/2) ══════════════════════
#
# Asking a new teammate to name a domain before they know what domains exist is the same
# shape of problem this command was built to remove.
echo "Test 41: domain-less setup"
# Driven WITHOUT a seam on purpose: a pinned ENV_MANIFEST collapses every domain onto
# one file, so the walk can only be observed against the real manifests. --non-interactive
# keeps it read-only.
ALLD="$WORK/alldomains"; mkcase "$ALLD"
ALLOUT=$(cd "$ALLD" && env -u ENV_MANIFEST "$ENV_SH" setup --non-interactive </dev/null 2>&1 | strip)
ALLN=$(printf '%s\n' "$ALLOUT" | grep -c '^── ' || true)
if [ "${ALLN:-0}" -ge 2 ]; then
  pass "setup with no --domain walks every domain that has a manifest ($ALLN visited)"
else
  fail "walks all domains" ">=2 domain headers" "$ALLN headers in: $ALLOUT"
fi
if printf '%s' "$ALLOUT" | grep -q '^── core ──'; then
  pass "core is visited first (it composes into every other domain)"
else
  fail "core first" "a core header" "$ALLOUT"
fi

# THE GUARD MUST NOT MOVE. The doctor stays per-domain: that scoping is what stops a
# design operator being blocked on a Slack token only an intake wave needs.
DOCOUT=$(cd "$ALLD" && env -u ENV_MANIFEST "$ENV_SH" doctor </dev/null 2>&1 | strip)
if ! printf '%s' "$DOCOUT" | grep -q '^── '; then
  pass "the DOCTOR still runs one domain, not all (the per-domain guard is intact)"
else
  fail "doctor stays scoped" "no multi-domain walk" "$DOCOUT"
fi

# An explicit --domain must still mean exactly that one.
ONEOUT=$(cd "$ALLD" && env -u ENV_MANIFEST "$ENV_SH" setup --domain intake --non-interactive </dev/null 2>&1 | strip)
if ! printf '%s' "$ONEOUT" | grep -q '^── '; then
  pass "an explicit --domain still runs exactly that domain"
else
  fail "explicit domain scoped" "no walk" "$ONEOUT"
fi

# A pinned manifest collapses the walk — otherwise a seam would drive the same rows once
# per domain, and every existing single-domain setup test would silently become a 4x run.
SEAMONE="$WORK/seamone.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"SEAM_OPT", service:"S", required:"optional", secret:true, default:null,
   dotfile:".env.local", how:"h", check:{type:"file-key"}, source:{type:"prompt"}}]}' > "$SEAMONE"
SEAMOUT=$(cd "$ALLD" && ENV_MANIFEST="$SEAMONE" "$ENV_SH" setup --non-interactive </dev/null 2>&1 | strip)
if ! printf '%s' "$SEAMOUT" | grep -q '^── '; then
  pass "a pinned ENV_MANIFEST collapses the walk (one manifest means one domain)"
else
  fail "seam collapses walk" "no domain headers" "$SEAMOUT"
fi

# Domain discovery reads DISK, never a hardcoded list — a list in code is a second
# source of truth that goes stale the day someone adds a manifest.
if grep -q 'env_list_domains' "$HOME/.claude/engine/scripts/env-lib.sh" \
   && ! grep -qE 'DOMAINS=\(|for d in core intake prove design' "$ENV_SRC"; then
  pass "the domain list is discovered from disk, not hardcoded in env.sh"
else
  fail "discovered domains" "env_list_domains, no hardcoded list" "hardcoded list present"
fi


# ══ 42. a PLACEHOLDER value must never read as green (6/3) ════════════════════
#
# Seeding a stand-in so a path can be exercised end-to-end is legitimate; letting the
# doctor call it PASS is not. Same principle as the seam banner: a check that passes for
# the wrong reason stops the whole output being evidence.
echo "Test 42: placeholder values"
PHD="$WORK/placeholder"; mkcase "$PHD"
PH_MF="$WORK/placeholder.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"PH_OPT", service:"S", required:"optional", secret:true, default:null,
   dotfile:".env.local", how:"h", check:{type:"file-key"}, source:{type:"prompt"}},
  {key:"PH_REQ", service:"S", required:"req", secret:true, default:null,
   dotfile:".env.local", how:"h", check:{type:"file-key"}, source:{type:"prompt"}}]}' > "$PH_MF"
printf 'PH_OPT=PLACEHOLDER-not-real\nPH_REQ=PLACEHOLDER-not-real\n' >> "$PHD/.env.local"

PHOUT=$(cd "$PHD" && ENV_MANIFEST="$PH_MF" "$ENV_SH" doctor </dev/null 2>&1 | strip)
PHC=$(cd "$PHD" && ENV_MANIFEST="$PH_MF" "$ENV_SH" doctor </dev/null >/dev/null 2>&1; echo $?)
if printf '%s' "$PHOUT" | grep -qi 'PLACEHOLDER value'; then
  pass "a present-but-placeholder value is reported, not silently passed"
else
  fail "placeholder reported" "a PLACEHOLDER notice" "$PHOUT"
fi
if ! printf '%s' "$PHOUT" | grep -qE '^  PASS +PH_(OPT|REQ)'; then
  pass "neither placeholder row is reported as PASS"
else
  fail "no false green" "no PASS for a placeholder row" "$PHOUT"
fi
# Severity follows `required`, exactly as a miss does — a placeholder IS a miss that
# happens to occupy the line.
if [ "$PHC" -ne 0 ]; then
  pass "a REQUIRED row holding a placeholder blocks (non-zero), it does not merely warn"
else
  fail "req placeholder blocks" "non-zero" "$PHC"
fi
# …and a real value on the same row still passes, so the rule is not just "always warn".
REALD="$WORK/placeholder-real"; mkcase "$REALD"
printf 'PH_OPT=actual-value\nPH_REQ=actual-value\n' >> "$REALD/.env.local"
REALC=$(cd "$REALD" && ENV_MANIFEST="$PH_MF" "$ENV_SH" doctor </dev/null >/dev/null 2>&1; echo $?)
if [ "$REALC" -eq 0 ]; then
  pass "a real value on the same rows still passes (the prefix is the only trigger)"
else
  fail "real value passes" "0" "$REALC"
fi
# The prefix lives in the shared lib, so a seeder and the checker cannot disagree on it.
if grep -q 'ENV_PLACEHOLDER_PREFIX' "$HOME/.claude/engine/scripts/env-lib.sh"; then
  pass "the placeholder prefix is defined once, in the shared lib"
else
  fail "shared prefix" "ENV_PLACEHOLDER_PREFIX in env-lib.sh" "absent"
fi


# ══ 43. delivery sender + Clerk app login (7/1) ═══════════════════════════════
#
# `setup --aws-key` could always RECEIVE a delivered credentials file — validate it,
# install it, shred it. Nothing ever produced one, so provisioning for someone else had
# nowhere to put their key except the provisioner's own machine. A receiver with no sender.
echo "Test 43: delivery + app login"
DELD="$WORK/delivery"; mkcase "$DELD"

# (a) The sender writes the exact three fields the receiver greps for. This is the
#     contract between the two halves; drift here is silent until a handover fails.
if grep -q '_agent_key_deliver' "$ENV_SRC" \
   && grep -q "aws_access_key_id = %s" "$ENV_SRC" \
   && grep -q "aws_secret_access_key = %s" "$ENV_SRC"; then
  pass "the delivery sender emits the profile block that setup --aws-key parses"
else
  fail "sender format" "a deliver fn writing both key fields" "absent"
fi
# It must refuse to clobber: an existing file may be a key that was never delivered.
if grep -q 'an undelivered key may be sitting there' "$ENV_SRC"; then
  pass "the sender refuses to overwrite an existing delivery file"
else
  fail "no clobber" "an overwrite refusal" "absent"
fi

# (b) ⚠️ FINCH_AGENT_AWS_PROFILE answers "who am I to the engine". Writing someone else's
#     there while provisioning FOR them repoints the provisioner's own doctor, setup and
#     secret fetches at that person. Retaining their key is fine; adopting it is not.
if grep -q 'is not your own agent profile, so FINCH_AGENT_AWS_PROFILE was left alone' "$ENV_SRC"; then
  pass "provisioning for someone else does not adopt their profile as your own identity"
else
  fail "no identity adoption" "a caller-vs-person guard around the record" "absent"
fi

# (c) VERIFY BEFORE INSTALL. Writing a profile in order to test it leaves a dead key in a
#     file someone has to find and clean up.
VLINE=$(grep -n '_agent_key_verify_env "$akid"' "$ENV_SRC" | head -1 | cut -d: -f1)
WLINE=$(grep -n '_agent_profile_write "$user" "$akid"' "$ENV_SRC" | head -1 | cut -d: -f1)
if [ -n "$VLINE" ] && [ -n "$WLINE" ] && [ "$VLINE" -lt "$WLINE" ]; then
  pass "a minted key is verified through the environment BEFORE any profile is written"
else
  fail "verify before install" "verify line < write line" "verify=$VLINE write=$WLINE"
fi

# (d) THE PASSWORD IS NEVER PRINTED, and the Clerk key is shown only far enough to name
#     the instance. An earlier draft interpolated ${key#*_}, which is nearly the whole key.
if ! grep -nE 'printf.*\$(pw|\{pw)' "$ENV_SRC" >/dev/null 2>&1; then
  pass "the generated app password is never printed"
else
  fail "password never printed" "no printf of \$pw" "$(grep -nE 'printf.*\$(pw|\{pw)' "$ENV_SRC")"
fi
if grep -q 'cut -c1-7' "$ENV_SRC" && ! grep -q 'key#\*_' "$ENV_SRC"; then
  pass "only the sk_test / sk_live instance prefix of the Clerk key is ever shown"
else
  fail "key prefix only" "cut -c1-7 and no \${key#*_}" "$(grep -n 'key#\*_' "$ENV_SRC")"
fi

# (e) An existing Clerk user must NOT have its password rotated. Someone already holds
#     the current one, and a silent reset locks them out of the account being provisioned.
if grep -q 'rotating it would lock out whoever holds the current one' "$ENV_SRC"; then
  pass "an existing Clerk user is left untouched rather than silently re-passworded"
else
  fail "no silent rotation" "an exists-branch that writes no password" "absent"
fi

# (f) Clerk puts the actionable half of a 422 in long_message — `message` alone said only
#     "missing data" while long_message named the two fields the instance required.
if grep -q 'long_message // .message' "$ENV_SRC"; then
  pass "a Clerk error reports long_message, which is where the actionable half lives"
else
  fail "long_message surfaced" ".long_message // .message" "absent"
fi

# (g) --clerk-only exists because the mint refuses early once a profile is present, which
#     would otherwise take the app-login half down with it. It is still gated.
COD=$(cd "$DELD" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
      "$ENV_SH" provision --person rob --tier triage --account 924609080826 --clerk-only \
      </dev/null 2>&1 | strip)
if printf '%s' "$COD" | grep -qi 'dry-run'; then
  pass "--clerk-only is dry-run by default"
else
  fail "clerk-only dry-run" "a dry-run notice" "$COD"
fi
COC=$(cd "$DELD" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
      "$ENV_SH" provision --person rob --tier triage --account 924609080826 --clerk-only --apply \
      <<<'wrong-account' >/dev/null 2>&1; echo $?)
if [ "$COC" -ne 0 ]; then
  pass "--clerk-only --apply still requires the typed account confirmation"
else
  fail "clerk-only gated" "non-zero on a wrong confirmation" "$COC"
fi


# ══ 44. every intake MCP gates the wave (8/1) ═════════════════════════════════
#
# A wave that cannot read Linear, write its handbook to Notion, pull product-analytics
# signal from PostHog or look up code on GitHub is not degraded, it is blind. All four
# are `req`, and `req` is the ONLY tier that blocks — triage/boards/optional are the
# same WARN, so labelling alone would have changed nothing.
echo "Test 44: intake MCP tiering"
NONREQ=$(jq -r '[.credentials[] | select(.check.type=="mcp" and .required != "req") | .check.server] | join(",")' "$MANIFEST")
if [ -z "$NONREQ" ]; then
  pass "every MCP server intake declares is req (a missing one stops Phase 0)"
else
  fail "all intake MCP req" "no non-req mcp rows" "still non-req: $NONREQ"
fi
# The fixture that means "all required connected" must list them all, or the exit-0
# cases pass for the wrong reason.
for _srv in $(jq -r '.credentials[] | select(.check.type=="mcp") | .check.server' "$MANIFEST"); do
  case "$MCP_ALL_CONNECTED" in
    *"$_srv"*) ;;
    *) fail "fixture covers $_srv" "MCP_ALL_CONNECTED lists every declared server" "missing $_srv"; _fixgap=1 ;;
  esac
done
[ -z "${_fixgap:-}" ] && pass "the all-connected fixture lists every server the manifest declares"


# ══ 45. the `provisioner` tier is never granted (8/2) ═════════════════════════
#
# Some credentials the PROVISIONER needs, the agent must never hold — the read-write
# database URL above all, since an agent holding it could rewrite the data it is only
# meant to read. Every other tier in the vocabulary describes something an agent MAY be
# granted, so this one had to be excluded structurally rather than by remembering.
echo "Test 45: provisioner tier"
PROVT=$(jq -r '[.credentials[] | select(.required=="provisioner") | .key] | join(",")' "$MANIFEST")
if [ -n "$PROVT" ]; then
  pass "the manifest declares provisioner-only rows ($PROVT)"
else
  fail "provisioner rows exist" "at least one" "none"
fi

# (a) STRUCTURAL: the derivation skips them before any key is examined, so a new
#     provisioner row cannot reach a policy by being forgotten in the case below.
if grep -q '\[ "$required" = "provisioner" \] && continue' "$ENV_SRC"; then
  pass "the policy derivation skips provisioner rows before matching any key"
else
  fail "structural exclusion" "an early continue on required=provisioner" "absent"
fi

# (b) BEHAVIOURAL: neither tier's derived policy may name a provisioner row's value.
PROV_LEAK=0
for _t in triage member; do
  _out=$(cd "$WORK" && env -u ENV_MANIFEST -u ENV_STS_ARN -u ENV_DRIVE_ROOT -u ENV_AWS_HOME \
         "$ENV_SH" provision --person rob --tier "$_t" --account 924609080826 </dev/null 2>&1 | strip)
  for _k in $(jq -r '.credentials[] | select(.required=="provisioner") | .default // empty' "$MANIFEST"); do
    case "$_out" in *"$_k"*) PROV_LEAK=1 ;; esac
  done
done
if [ "$PROV_LEAK" -eq 0 ]; then
  pass "no provisioner-only value appears in any derived policy (triage or member)"
else
  fail "no provisioner leak" "no provisioner value in a policy" "leaked"
fi

# (c) The read-write URL must never be written to a dotfile. It is a `note` row, so the
#     wizard skips it — but the property is worth asserting, not inferring from a type.
RWD=$(jq -r '.credentials[] | select(.key=="FINCH_DB_RW_SECRET") | "\(.check.type)|\(.dotfile)"' "$MANIFEST")
if [ "$RWD" = "note|" ]; then
  pass "the read-write DB url is a note with no dotfile — fetched at runtime, never stored"
else
  fail "rw url never stored" "note| (no dotfile)" "$RWD"
fi


# ══ 46. credentials are isolated by UNSETTING, never by emptying (8/3) ════════
#
# Found by provisioning a real person. `AWS_PROFILE=""` does not mean "no profile" to
# the AWS CLI — it means a profile whose name is the empty string, and the call dies
# with "The config profile () could not be found". Verification therefore failed for
# every operator with a profile exported, the freshly minted key looked dead, and the
# rollback deleted it. The safety design worked; the check did not.
echo "Test 46: credential isolation"
# Comments ABOUT the trap are not the trap. A substring check cannot tell code from
# prose describing code — the first version of this test failed on its own explanation.
EMPTYSET=$(grep -vE '^[[:space:]]*#' "$ENV_SRC" | grep -nE 'AWS_PROFILE=""|AWS_SESSION_TOKEN=""' || true)
if [ -z "$EMPTYSET" ]; then
  pass "no AWS variable is isolated by setting it to the empty string"
else
  fail "unset not empty" "env -u, not VAR=\"\"" "$EMPTYSET"
fi
if grep -q 'env -u AWS_PROFILE -u AWS_SESSION_TOKEN' "$ENV_SRC"; then
  pass "the key-verification probe unsets the ambient profile before using explicit keys"
else
  fail "verify unsets profile" "env -u AWS_PROFILE -u AWS_SESSION_TOKEN" "absent"
fi


# ══ 47. the login is PLUS-addressed, identifiers stay dashed (8/4) ════════════
#
# `<name>-agent@finchclaims.com` needs a mailbox that does not exist. `<name>+agent@` is
# sub-addressing and lands in the person's existing inbox. The identity provider sends
# verification and reset mail, so a dash address makes the account unrecoverable the
# first time that matters — and the ticket said `+` before this was "corrected" to `-`.
echo "Test 47: plus-addressed login"
if grep -q "printf '%s+agent'" "$ENV_SRC" && grep -q '_agent_login_local' "$ENV_SRC"; then
  pass "the plus form is decided in ONE helper (_agent_login_local), not spelled at each site"
else
  fail "plus-addressed login" "_agent_login_local building a +agent local-part" "absent"
fi
# The SECRET is named for the login it holds, not for the profile that reads it — and the
# derived grant must name the same path, or the grant covers something nothing requests.
if grep -q '\*agent-login\*) who="$(_agent_login_local "$who")"' "$ENV_SRC"; then
  pass "an agent-login secret path carries the login (plus) form, matching the grant"
else
  fail "secret path plus form" "the fetcher mapping agent-login paths through _agent_login_local" "absent"
fi
# No site may build the login from the DASHED agent user directly.
DASHMAIL=$(grep -vE '^[[:space:]]*#' "$ENV_SRC" | grep -nE '\$\{user\}@finchclaims|\$\{person\}-agent@' || true)
if [ -z "$DASHMAIL" ]; then
  pass "no site builds the login address from the dashed identifier"
else
  fail "no dashed login" "none" "$DASHMAIL"
fi
# …but the dash MUST survive where it is an identifier, not an address.
if grep -q 'local user="${person}-agent"' "$ENV_SRC" && grep -q 'local profile="${person}-agent"' "$ENV_SRC"; then
  pass "the IAM user and AWS profile keep the dashed form (they deliver no mail)"
else
  fail "identifiers stay dashed" "person-agent for the IAM user and profile" "changed"
fi


# ══ 48. the summary reports OUTCOMES, not intent (8/5) ════════════════════════
#
# Provisioning printed "done: <user> is provisioned" while the app login, the app row
# and the delivery had all silently no-opped — three of four halves missing, reported as
# success. Every half degrades rather than aborting, deliberately (losing a minted key to
# a chat-API hiccup would be the worst trade available), so the SUMMARY is the only thing
# standing between that design and an account that exists and cannot be used.
echo "Test 48: outcome-reporting summary"
if grep -q 'PARTIAL:' "$ENV_SRC" && grep -q 'is NOT usable yet' "$ENV_SRC"; then
  pass "a run that did not complete every half says PARTIAL and NOT usable"
else
  fail "partial verdict" "a PARTIAL / not-usable branch" "absent"
fi
# It must EXIT non-zero on a partial, or a caller cannot gate on it and the operator is
# the only safeguard.
if grep -A2 'is NOT usable yet' "$ENV_SRC" | grep -q 'return 1'; then
  pass "a partial provision exits non-zero, so a caller can gate on it"
else
  fail "partial exits non-zero" "return 1 after the PARTIAL branch" "absent"
fi
# Each half is tracked by a flag set at its REAL success point, not assumed.
MISSING=""
for _f in PROVISION_CLERK_OK PROVISION_APP_ROW_OK PROVISION_SLACK_OK; do
  grep -q "${_f}=1" "$ENV_SRC" || MISSING="$MISSING $_f"
done
if [ -z "$MISSING" ]; then
  pass "each half sets its own success flag (clerk, app row, delivery)"
else
  fail "per-half flags" "all three set" "missing:$MISSING"
fi
# The app row gets called out by consequence, not just by name — "no row" is meaningless
# to a reader who does not know it is what makes the account work at all.
if grep -q 'without it the application does not know them' "$ENV_SRC"; then
  pass "the summary says what a missing app row COSTS, not merely that it is missing"
else
  fail "consequence stated" "the app-row line naming its consequence" "absent"
fi


# ══ 49. the plus in a login address survives the query string (8/6) ═══════════
#
# A literal `+` in a query string decodes to a SPACE. So looking a login up by its own
# address sent `leonardo agent@…` and matched nobody — the account read as missing
# seconds after being created, on the very run that created it. The plus-addressing
# change introduced this; the lookup is the only place it bites.
echo "Test 49: plus survives the query string"
if grep -q 'email_q="${email//+/%2B}"' "$ENV_SRC"; then
  pass "the Clerk lookup percent-encodes the + before putting it in a query string"
else
  fail "plus encoded" 'email//+/%2B before the request' "absent"
fi
if ! grep -q 'email_address=\${email}"' "$ENV_SRC"; then
  pass "no request interpolates the raw address into a query string"
else
  fail "no raw address in query" "none" "$(grep -n 'email_address=\${email}"' "$ENV_SRC")"
fi


# ══ 50. a degraded MCP row is never cached (the 5-minute phantom FAIL) ════════
#
# `engine env doctor` FAILed linear-server while linear-server was authenticated. The
# cache held the reason, verbatim:
#     linear-server: … (HTTP) - ! Connected · tools fetch failed — Request timed out
# The server never lost consent — only the TOOLS fetch timed out. The cache-write guard
# tested `[ -n "$MCP_LIST_OUT" ]`, so that well-formed line counted as a successful probe
# and was served as fact for the full TTL, long after the server recovered. The comment
# above the guard already promised "only a SUCCESSFUL probe is cached"; the code tested
# something else. These cases pin the promise instead of the prose.
#
# ⚠️ ENV_MCP_LIST_OUTPUT returns BEFORE the cache block, so the seam cannot reach this
# code at all. Every case here goes through a stub `claude` on PATH — the real path.
echo "Test 50: a degraded MCP row is never cached"
CASE_MC="$WORK/mcpcache"; mkcase "$CASE_MC"
MCBIN="$WORK/mcpbin"; mkdir -p "$MCBIN"
MCCACHE="$WORK/mcpcachehome"

# stub_mcp OUTPUT — a `claude` whose `mcp list` prints exactly OUTPUT.
stub_mcp() {
  printf '%s\n' '#!/bin/bash' 'if [ "${1:-}" = "mcp" ]; then cat "$0.out"; fi' > "$MCBIN/claude"
  chmod +x "$MCBIN/claude"
  printf '%s' "$1" > "$MCBIN/claude.out"
}
# mcdoc — doctor through the stub, with a private cache home. ENV_MCP_LIST_OUTPUT is
# UNSET so the real probe+cache path runs.
mcdoc() {
  ( cd "$CASE_MC" && env -u ENV_MCP_LIST_OUTPUT PATH="$MCBIN:$PATH" \
      XDG_CACHE_HOME="$MCCACHE" ENV_MANIFEST="$MCP_MF" "$ENV_SH" doctor 2>&1 | strip )
}
mccache_files() { ls "$MCCACHE/engine"/mcp-probe-* 2>/dev/null; }

DEGRADED=$'Checking MCP server health…\n\nlinear-server: https://mcp.linear.app/mcp (HTTP) - ! Connected \xc2\xb7 tools fetch failed — Request timed out\nnotion: x - ✔ Connected'
HEALTHY=$'Checking MCP server health…\n\nlinear-server: https://mcp.linear.app/mcp (HTTP) - ✔ Connected\nnotion: x - ✔ Connected'

# (a) THE BUG. A degraded row must leave NO cache entry behind.
/bin/rm -rf "$MCCACHE"; stub_mcp "$DEGRADED"
MC_A=$(mcdoc)
if [ -z "$(mccache_files)" ]; then
  pass "a probe carrying a degraded row writes no cache entry"
else
  fail "degraded not cached" "no mcp-probe-* file" "$(mccache_files) :: $(cat $(mccache_files) 2>/dev/null)"
fi

# (b) …and the very next run therefore sees the RECOVERED server, not the stale verdict.
#     Before the fix this second run PASSED nothing: it read the cache and FAILed again.
stub_mcp "$HEALTHY"
MC_B=$(mcdoc)
if printf '%s' "$MC_B" | grep -qE 'PASS +linear-server'; then
  pass "recovery is visible on the next run, not after the TTL expires"
else
  fail "recovery visible" "PASS linear-server" "$(printf '%s' "$MC_B" | grep -i linear)"
fi

# (c) an ALL-HEALTHY probe is still cached — the fix must not disable the cache, which
#     is the only reason the doctor is runnable at skill startup at all.
if [ -n "$(mccache_files)" ]; then
  pass "an all-healthy probe is still cached"
else
  fail "healthy cached" "an mcp-probe-* file" "none"
fi

# (d) a poisoned entry written by an OLDER build is dropped on read, not served. The fix
#     heals the caches it inherits instead of making the operator wait out their TTL.
POISON="$(mccache_files | head -1)"
printf '%s' "$DEGRADED" > "$POISON"
stub_mcp "$HEALTHY"
MC_D=$(mcdoc)
if printf '%s' "$MC_D" | grep -qE 'PASS +linear-server'; then
  pass "an inherited poisoned cache entry is dropped, not served"
else
  fail "poison dropped" "PASS linear-server" "$(printf '%s' "$MC_D" | grep -i linear)"
fi

# (e) ONE definition of unhealthy. The verdict and the cache guard read the same
#     pattern, so they cannot drift into disagreeing about what healthy means.
if grep -q 'MCP_UNHEALTHY_RE=' "$ENV_SRC" \
   && [ "$(grep -c 'grep -qiE "\$MCP_UNHEALTHY_RE"' "$ENV_SRC")" -ge 2 ]; then
  pass "the verdict and the cache guard share one unhealthy-row pattern"
else
  fail "one pattern" "MCP_UNHEALTHY_RE defined once, read by both" \
       "$(grep -n 'MCP_UNHEALTHY_RE' "$ENV_SRC")"
fi


# ══ 51. --tier: WHO is asking decides which rows apply, and how hard ══════════
#
# `required` used to answer two questions at once — how badly is this needed
# (req/optional) and who needs it (triage/boards/provisioner). Fine while /intake was
# the only caller, since `req` could quietly mean "required for intake". The moment
# /inbox-triage calls the same manifest the two come apart: linear-server is req and
# triage genuinely needs it, SLACK_INTAKE_TOKEN is also req and triage never posts to
# Slack, and the app-login rows triage cannot work without only WARN.
#
# So `consumers` answers WHO, `required` stays the default severity, and severity may be
# stated per consumer where it genuinely differs.
echo "Test 51: --tier scopes the manifest to the consumer asking"
TIERD="$WORK/tierd"; mkcase "$TIERD"
TIER_MF="$WORK/tier.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"SHARED_KEY", service:"Shared", required:"req", secret:false, default:"x",
   dotfile:".env", how:"both need it", check:{type:"file-key"}, source:{type:"prompt"},
   consumers:["intake","triage"]},
  {key:"INTAKE_ONLY", service:"Intake only", required:"req", secret:false, default:"y",
   dotfile:".env", how:"only intake", check:{type:"file-key"}, source:{type:"prompt"},
   consumers:["intake"]},
  {key:"SPLIT_SEVERITY", service:"Split", required:"optional", secret:false, default:null,
   dotfile:".env", how:"warns for intake, blocks for triage", check:{type:"file-key"},
   source:{type:"prompt"}, consumers:{intake:"optional", triage:"req"}},
  {key:"NO_CONSUMERS", service:"Unmigrated", required:"optional", secret:false, default:null,
   dotfile:".env", how:"declares no consumers", check:{type:"file-key"}, source:{type:"prompt"}}]}' > "$TIER_MF"

tierdoc() { ( cd "$TIERD" && ENV_MANIFEST="$TIER_MF" "$ENV_SH" doctor ${1:+--tier "$1"} 2>&1 | strip ); }
tiercode() { ( cd "$TIERD" && ENV_MANIFEST="$TIER_MF" "$ENV_SH" doctor ${1:+--tier "$1"} >/dev/null 2>&1; echo $? ); }

# (a) no --tier is the pre-tier behaviour: every row is evaluated, severity as written.
NOTIER=$(tierdoc)
if printf '%s' "$NOTIER" | grep -q 'INTAKE_ONLY' && printf '%s' "$NOTIER" | grep -q 'SHARED_KEY' \
   && printf '%s' "$NOTIER" | grep -q 'SPLIT_SEVERITY'; then
  pass "no --tier evaluates every row (the behaviour before tiers existed)"
else
  fail "no tier = all rows" "all four keys present" "$NOTIER"
fi

# (b) THE POINT: a row this consumer does not need is not its problem. A triage run must
#     not be stopped by a Slack token it never uses.
TRI=$(tierdoc triage)
if ! printf '%s' "$TRI" | grep -q 'INTAKE_ONLY'; then
  pass "--tier triage drops a row that names only another consumer"
else
  fail "tier filters" "INTAKE_ONLY absent" "$(printf '%s' "$TRI" | grep INTAKE_ONLY)"
fi
if printf '%s' "$TRI" | grep -q 'SHARED_KEY'; then
  pass "an array consumers list keeps the row for every consumer it names"
else
  fail "array form" "SHARED_KEY present under --tier triage" "$TRI"
fi

# (c) severity is PER CONSUMER. The same missing row warns for one and blocks the other —
#     which is the whole reason an array alone could not express this.
if printf '%s' "$NOTIER" | grep -qE 'WARN +SPLIT_SEVERITY'; then
  pass "a split-severity row WARNs for the consumer that only dispatches"
else
  fail "split warns" "WARN SPLIT_SEVERITY with no tier" "$(printf '%s' "$NOTIER" | grep SPLIT_SEVERITY)"
fi
if printf '%s' "$TRI" | grep -qE 'FAIL +SPLIT_SEVERITY'; then
  pass "the same row BLOCKS for the consumer that cannot work without it"
else
  fail "split blocks" "FAIL SPLIT_SEVERITY under --tier triage" "$(printf '%s' "$TRI" | grep SPLIT_SEVERITY)"
fi
# Every row except SPLIT_SEVERITY is satisfiable (defaults get seeded), so the ONLY thing
# separating the two exit codes is the per-consumer severity — which is what is under test.
if [ "$(tiercode triage)" != "0" ] && [ "$(tiercode)" = "0" ]; then
  pass "the exit code follows the resolved severity, so a caller can gate on it"
else
  fail "tier exit code" "non-zero with --tier triage, zero without" "tier=$(tiercode triage) none=$(tiercode)"
fi

# (d) BACK-COMPAT: a row declaring no consumers serves every consumer, so an unmigrated
#     manifest behaves exactly as it does today rather than silently emptying out.
if printf '%s' "$TRI" | grep -q 'NO_CONSUMERS'; then
  pass "a row with no consumers still serves every tier (unmigrated manifests keep working)"
else
  fail "no-consumers row" "NO_CONSUMERS present under --tier triage" "$TRI"
fi

# (e) ⚠️ `required: "provisioner"` is NOT a severity and must survive the split untouched:
#     env.sh skips those rows BEFORE the policy derivation reads any key, so a forgotten
#     provisioner row cannot reach a derived IAM policy. Rewriting it into a severity
#     would turn a fail-closed guard into a fail-open one.
if jq -e '[.credentials[] | select(.required=="provisioner")] | length >= 1' "$MANIFEST" >/dev/null 2>&1; then
  pass "provisioner rows keep required=provisioner after the consumers split"
else
  fail "provisioner preserved" "at least one required=provisioner row" \
       "$(jq -c '[.credentials[]|select(.consumers|tostring|test("provisioner"))|{key,required}]' "$MANIFEST")"
fi
if grep -q '\[ "\$required" = "provisioner" \] && continue' "$ENV_SRC"; then
  pass "the fail-closed policy guard still keys on required=provisioner"
else
  fail "policy guard intact" 'the provisioner continue-guard in env.sh' "absent"
fi


# ══ 52. --refresh: a fetched value is a CACHE, a typed one is a SOURCE ═══════
#
# `setup` skips any row the dotfile already holds. Correct for a `prompt` row — rewriting
# it could only discard something a person went and obtained. Wrong for an `aws-secret`
# row, where the local copy is a cache of an authoritative upstream: a per-person key can
# be provisioned, granted, and never used, while the doctor reports PASS because a value
# is present rather than because it is the right one. Found the hard way — every machine
# already set up kept its old Gemini key and nothing said so.
echo "Test 52: --refresh re-fetches a cache, never a typed value"
CASE_RF="$WORK/rf"; mkcase "$CASE_RF"
RF_MF="$WORK/refresh.json"
jq -n '{version:1, domain:"test", credentials:[
  {key:"FETCHED_ONE", service:"Fetched", required:"optional", secret:true, default:null,
   dotfile:".env.local", how:"has an upstream", check:{type:"file-key"},
   source:{type:"aws-secret", name:"staging/finch/whatever"}},
  {key:"TYPED_ONE", service:"Typed", required:"optional", secret:true, default:null,
   dotfile:".env.local", how:"a person went and got this", check:{type:"file-key"},
   source:{type:"prompt"}}]}' > "$RF_MF"

# Both already present, with values that are recognisably OLD.
printf 'FETCHED_ONE="stale-cache"\nTYPED_ONE="hand-typed"\n' > "$CASE_RF/.env.local"

rf() { ( cd "$CASE_RF" && ENV_MANIFEST="$RF_MF" ENV_AWS_SECRET_OUTPUT='{"SecretString":"fresh-from-upstream"}' \
          "$ENV_SH" setup ${1:-} </dev/null 2>&1 | strip ); }

# (a) WITHOUT --refresh nothing moves — the pre-existing contract.
rf >/dev/null 2>&1
if grep -q 'stale-cache' "$CASE_RF/.env.local" && grep -q 'hand-typed' "$CASE_RF/.env.local"; then
  pass "without --refresh both rows are left exactly as they were"
else
  fail "no-refresh leaves both" "stale-cache + hand-typed intact" "$(cat "$CASE_RF/.env.local")"
fi

# (b) WITH --refresh the CACHE is replaced …
rf --refresh >/dev/null 2>&1
if grep -q 'fresh-from-upstream' "$CASE_RF/.env.local"; then
  pass "--refresh re-fetches an aws-secret row that was already present"
else
  fail "refresh re-fetches" "fresh-from-upstream in the dotfile" "$(cat "$CASE_RF/.env.local")"
fi

# (c) … and the TYPED value is untouched. This is the half that makes --refresh safe to
#     run habitually: it can only ever discard a copy, never an original.
if grep -q 'hand-typed' "$CASE_RF/.env.local"; then
  pass "--refresh does NOT touch a prompt-sourced row (no upstream to refresh from)"
else
  fail "refresh spares typed rows" "hand-typed still present" "$(cat "$CASE_RF/.env.local")"
fi

# (d) filled IN PLACE, not appended — a second definition would shadow unpredictably
#     depending on which reader wins.
if [ "$(grep -c '^FETCHED_ONE' "$CASE_RF/.env.local")" = "1" ]; then
  pass "the refreshed row is filled in place, not duplicated"
else
  fail "no duplicate line" "exactly one FETCHED_ONE line" "$(grep -c '^FETCHED_ONE' "$CASE_RF/.env.local")"
fi

# (e) the skip message TELLS you the door exists. A silent skip is how the stale cache
#     survived unnoticed in the first place.
NORF=$(rf)
if printf '%s' "$NORF" | grep -q -- '--refresh'; then
  pass "the 'already set' line names --refresh, so the skip is discoverable"
else
  fail "skip names the remedy" "a --refresh hint on the have line" "$NORF"
fi


exit_with_results
