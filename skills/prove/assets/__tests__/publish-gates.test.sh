#!/usr/bin/env bash
# Offline harness for the two publish gates in publish.sh: DESTINATION and PROVENANCE LEAK.
#
# Neither gate needs AWS, and that is deliberate — both answer their question before a byte moves,
# so the whole harness runs against a fake `aws`/`python3` shim on PATH. The question each test
# asks is "would publish.sh have refused, and for the RIGHT REASON" — a refusal that happens for a
# different reason than the one under test is a pass by accident, so every case asserts the
# message, not only the exit code.
#
# Each negative case is paired with its NEAREST LEGAL NEIGHBOUR rather than an unrelated input: a
# gate proved only against something obviously wrong tells you nothing about what it will actually
# be handed. For the destination gate the neighbour is the SAME declaration satisfied; for the leak
# gate it is a relative path that is legitimate page content.
#
# Run:  ~/.claude/skills/prove/assets/__tests__/publish-gates.test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$(cd "$here/.." && pwd)"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
have() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

tmp="$(mktemp -d -t prove-gates)"
trap 'rm -rf "$tmp"' EXIT

# --- shims: the gates run before any upload, so nothing here needs to reach S3 ----------------
mkdir -p "$tmp/bin"
cat > "$tmp/bin/aws" <<'SHIM'
#!/usr/bin/env bash
case "$*" in
  *"sts get-caller-identity"*) echo "arn:aws:iam::000000000000:user/testuser" ;;
  *"configure export-credentials"*) exit 1 ;;
esac
exit 0
SHIM
chmod +x "$tmp/bin/aws"
# A python3 shim stands in for _publish.py so a PASS is observable: reaching the uploader at all
# means both gates let the publish through, which is the only thing these tests need from it.
cat > "$tmp/bin/python3" <<'SHIM'
#!/usr/bin/env bash
printf 'UPLOADER REACHED\n'
exit 0
SHIM
chmod +x "$tmp/bin/python3"
export PATH="$tmp/bin:$PATH"

# --- a staged page directory, the thing publish.sh is handed -----------------------------------
stage() {
  local d="$tmp/$1"; shift
  mkdir -p "$d"
  printf '%s\n' "$@" > "$d/index.html"
  printf '%s' "$d"
}

envfile() {
  local f="$tmp/$1.env"; shift
  : > "$f"
  for kv in "$@"; do printf '%s\n' "$kv" >> "$f"; done
  printf '%s' "$f"
}

# A command substitution runs in a SUBSHELL, so an rc assigned inside one never reaches the
# caller — under `set -u` that reads as "RC: unbound variable" rather than as a wrong number,
# which is the good outcome. The status goes through a file so both halves survive.
run() { # run <envfile> <stagedir> [extra args…] -> prints combined output; status via rc
  local ef="$1" sd="$2"; shift 2
  PROVE_S3_ENV="$ef" "$assets/publish.sh" "$sd" "$@" > "$tmp/run.out" 2>&1
  printf '%s' "$?" > "$tmp/run.rc"
  cat "$tmp/run.out"
}
rc() { cat "$tmp/run.rc"; }

echo "== destination gate =================================================="

# THE CASE THIS GATE EXISTS FOR. The pinned .env names the local MinIO endpoint; the publish is
# aimed at an AWS bucket instead. Five real pages went out exactly this way: the file said one
# store, something else won, and nothing in the output said so. The gate reads the PINNED FILE
# directly rather than the resolved environment, because an ambient override is precisely what
# shadowed the declaration.
ef="$(envfile mismatch 'PROVE_S3_BUCKET=kit-proofs' 'PROVE_S3_ENDPOINT=http://127.0.0.1:9440')"
sd="$(stage clean '<p>nothing to leak here</p>')"
out="$(run "$ef" "$sd" --to 's3://staging-finch-proofs/proofs/yarik')"
if [ "$(rc)" -ne 0 ] && have "$out" 'declared'; then
  ok "refuses a bucket the pinned .env does not declare, and says so"
else
  no "refuses a bucket the pinned .env does not declare, and says so" "rc=$(rc) out=$out"
fi
# The refusal must name BOTH stores. A refusal that says only "mismatch" leaves the publisher
# guessing which side is wrong, and the whole defect was not knowing where the bytes were going.
if have "$out" 'staging-finch-proofs' && have "$out" 'kit-proofs'; then
  ok "the refusal names the declared store and the attempted one"
else
  no "the refusal names the declared store and the attempted one" "out=$out"
fi

# NEAREST LEGAL NEIGHBOUR: the same declaration, satisfied. If this refused, the gate would be
# unusable and would be turned off within a day.
out="$(run "$ef" "$sd" --to 's3://kit-proofs/proofs/yarik')"
if [ "$(rc)" -eq 0 ] && have "$out" 'UPLOADER REACHED'; then
  ok "allows the bucket the pinned .env declares"
else
  no "allows the bucket the pinned .env declares" "rc=$(rc) out=$out"
fi

# A project that declares nothing keeps its existing behaviour. The gate adds a check on a
# DECLARATION; it must not invent one, or it becomes a second place that guesses a destination.
ef2="$(envfile nodecl 'PROVE_S3_BUCKET=whatever')"
out="$(run "$ef2" "$sd" --to 's3://whatever/p')"
if [ "$(rc)" -eq 0 ]; then
  ok "no endpoint declared: the gate stays silent rather than inventing one"
else
  no "no endpoint declared: the gate stays silent rather than inventing one" "rc=$(rc) out=$out"
fi

# A local directory target is not a store and must not be judged against one, or the offline
# escape hatch the help text advertises stops working.
out="$(run "$ef" "$sd" --to "$tmp/out")"
if [ "$(rc)" -eq 0 ]; then
  ok "a directory target is exempt from the destination gate"
else
  no "a directory target is exempt from the destination gate" "rc=$(rc) out=$out"
fi

echo "== provenance leak gate ============================================="

# An absolute local path carrying the username is never legitimate page content, and two live
# pages carry one — eleven occurrences on a single page.
sd_leak="$(stage leak '<pre>ran in /Users/someone/scratchpad/run-3</pre>')"
out="$(run "$ef" "$sd_leak" --to 's3://kit-proofs/p')"
if [ "$(rc)" -ne 0 ] && have "$out" 'index.html'; then
  ok "refuses an absolute local path and names the file carrying it"
else
  no "refuses an absolute local path and names the file carrying it" "rc=$(rc) out=$out"
fi

# The sandbox spelling of the same thing, which is what actually appears in these pages.
sd_leak2="$(stage leak2 '<pre>/private/tmp/claude-501/-Users-someone-Projects/x</pre>')"
out="$(run "$ef" "$sd_leak2" --to 's3://kit-proofs/p')"
if [ "$(rc)" -ne 0 ]; then
  ok "refuses the -Users- sandbox spelling too"
else
  no "refuses the -Users- sandbox spelling too" "rc=$(rc) out=$out"
fi

# NEAREST LEGAL NEIGHBOUR, and the reason this gate refuses only absolute paths: a RELATIVE
# reference to a session artifact is ordinary page content. A gate that fired here would fire on
# most real pages and be disabled, taking the username check with it.
sd_rel="$(stage rel '<p>workings in builds/FLAKYLOAD_PAPER.md and runs/pass-3.log</p>')"
out="$(run "$ef" "$sd_rel" --to 's3://kit-proofs/p')"
if [ "$(rc)" -eq 0 ] && have "$out" 'UPLOADER REACHED'; then
  ok "a relative builds/ or runs/ reference publishes (warn, never refuse)"
else
  no "a relative builds/ or runs/ reference publishes (warn, never refuse)" "rc=$(rc) out=$out"
fi
# …but it does not pass SILENTLY. An unreachable pointer is a real defect for a reader, just not
# one worth blocking a publish over, so the publisher is told.
if have "$out" 'builds/'; then
  ok "and the relative reference is still reported to the publisher"
else
  no "and the relative reference is still reported to the publisher" "out=$out"
fi

# CONTROL for the whole leak gate: a page with neither spelling must reach the uploader. Without
# this, every refusal above is consistent with a gate that refuses everything.
out="$(run "$ef" "$sd" --to 's3://kit-proofs/p')"
if [ "$(rc)" -eq 0 ] && have "$out" 'UPLOADER REACHED'; then
  ok "a clean page reaches the uploader (control: the gate is not refusing everything)"
else
  no "a clean page reaches the uploader (control: the gate is not refusing everything)" "rc=$(rc) out=$out"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
