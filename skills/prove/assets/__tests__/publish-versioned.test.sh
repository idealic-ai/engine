#!/usr/bin/env bash
# End-to-end harness for versioned HTML publishing. LOCAL TARGET ONLY — no AWS, no network.
#
# The local target exists to rehearse the S3 run, and it mirrors the S3 key layout exactly rather
# than flattening into something nicer to browse, so an assertion made here is an assertion about
# the key an S3 run would write. That is the only reason these tests are worth anything.
#
# Run:  ~/.claude/engine/skills/prove/assets/__tests__/publish-versioned.test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$(cd "$here/.." && pwd)"
pub="$assets/publish.sh"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

tmp="$(mktemp -d -t prove-versioned)"
trap 'rm -rf "$tmp"' EXIT
export PROVE_S3_ENV=/nonexistent
unset PROVE_S3_BUCKET PROVE_S3_PROFILE 2>/dev/null || true
export PROVE_S3_REGION=us-east-2

src="$tmp/study.bundle"; out="$tmp/out"
mkdir -p "$src"
write() { printf '<!doctype html><title>study</title><link rel=stylesheet href="css/s.css"><h1>%s</h1>' "$1" > "$src/index.html"; }
mkdir -p "$src/css"; printf 'h1{color:red}' > "$src/css/s.css"

run() { "$pub" "$src" --to "$out" "$@" > "$tmp/o.txt" 2> "$tmp/e.txt"; echo $?; }
outp() { cat "$tmp/o.txt" "$tmp/e.txt"; }
tree() { (cd "$out" 2>/dev/null && find . -type d -mindepth 1 -maxdepth 1 | sed 's|^\./||' | sort | tr '\n' ' '); }
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }

echo "== GATE 1 · the five version-flag behaviours, end to end =="

write one;   e=$(run);                    [ "$e" = 0 ] && ok "first publish exits 0" || no "first publish" "$(outp)"
[ -f "$out/study.v1/index.html" ] && ok "first publish mints study.v1/" || no "study.v1/" "$(tree)"
[ -f "$out/study/index.html" ]    && ok "…and the bare reference study/" || no "study/" "$(tree)"
[ -f "$out/study.v1/css/s.css" ]  && ok "the whole tree publishes, subdirectories included" \
                                  || no "css/s.css missing" "$(tree)"

write two;   e=$(run)                     # default: deepest position
[ -d "$out/study.v2" ] && ok "default bump: 1 -> 2" || no "default bump" "$(outp)"
write three; e=$(run --minor)             # position 2, absolute — creates it
[ -d "$out/study.v2.1" ] && ok "--minor on 2 -> 2.1 (position 2 starts at 1)" || no "--minor" "$(outp)"
write four;  e=$(run)                     # deepest again
[ -d "$out/study.v2.2" ] && ok "default on 2.1 -> 2.2 (deepest position)" || no "default deep" "$(outp)"
write five;  e=$(run --bump)              # RELATIVE: one shallower than depth 2 -> position 1
[ -d "$out/study.v3" ] && ok "--bump on 2.2 (depth 2) -> 3, one level shallower" || no "--bump" "$(outp)"
write six;   e=$(run --major)             # position 1, absolute
[ -d "$out/study.v4" ] && ok "--major on 3 -> 4" || no "--major" "$(outp)"
write seven; e=$(run --fork wip)          # named branch at 1
[ -d "$out/study.v4.wip.1" ] && ok "--fork wip on 4 -> 4.wip.1" || no "--fork" "$(outp)"
write eight; e=$(run)                     # default walks the fork
[ -d "$out/study.v4.wip.2" ] && ok "default on 4.wip.1 -> 4.wip.2 (walks the branch)" || no "fork walk" "$(outp)"
grep -q "walking the 'wip' branch" "$tmp/o.txt" \
  && ok "…and it SAYS it is on a branch, naming --major as the way back" || no "branch notice" "$(outp)"

echo
echo "== GATE 1b · a fork never answers a trunk reference =="
bare_before="$(sha "$out/study/index.html")"
write nine; e=$(run)                                   # still on the wip branch
[ "$(sha "$out/study/index.html")" = "$bare_before" ] \
  && ok "publishing on the wip branch did NOT move the bare study/ reference" \
  || no "bare reference moved on a fork publish" "a branch build became 'latest'"
[ -f "$out/study.v4.wip/index.html" ] && ok "the branch gets its OWN reference study.v4.wip/" \
  || no "branch reference" "$(tree)"
[ -d "$out/study.v4.wip.3" ] && ok "…and its own resolved address" || no "branch resolved" "$(tree)"

echo
echo "== GATE 2 + 3 · resolved addresses are immovable, and the guard proves it BY CONSTRUCTION =="
# In unit mode the guard's refusal branch is defence in depth rather than a path you can walk into:
# `latest` is the maximum published version, so every flag mints an address nobody holds. The
# property that actually matters is therefore not "the guard fires" but "no published resolved tree
# ever changes", and that is what is asserted here — against every version published so far.
# A fresh unit, so every RESOLVED version is captured from the run that minted it. Globbing
# study.v* would sweep in the REFERENCE directories, and references are supposed to move — that is
# the entire distinction being tested.
im="$tmp/imm"; imsrc="$tmp/immsrc"; mkdir -p "$imsrc"
snap="$tmp/snap.txt"; : > "$snap"
i=0
for flag in "" "" "--minor" "" "--fork side" "" "--major"; do
  i=$((i+1)); printf '<!doctype html><h1>rev %d</h1>' "$i" > "$imsrc/index.html"
  # shellcheck disable=SC2086
  "$pub" "$imsrc" --to "$im" --as immut $flag > "$tmp/i.txt" 2>&1
  v="$(sed -n 's/^  version  immut  [^ ]* -> \([^ ]*\).*/\1/p' "$tmp/i.txt" | head -1)"
  [ -n "$v" ] || continue
  printf '%s %s\n' "$(shasum -a 256 "$im/immut.v$v/index.html" | cut -d' ' -f1)" "immut.v$v" >> "$snap"
done
n_snap="$(wc -l < "$snap" | tr -d ' ')"
moved=0
while read -r digest dir; do
  now="$(shasum -a 256 "$im/$dir/index.html" | cut -d' ' -f1)"
  [ "$now" = "$digest" ] || { moved=$((moved+1)); printf '     moved: %s\n' "$dir"; }
done < "$snap"
[ "$n_snap" -ge 6 ] && [ "$moved" = 0 ] \
  && ok "every one of the $n_snap resolved trees still holds its original bytes after all 7 publishes" \
  || no "a resolved tree moved" "$moved of $n_snap moved"
awk '{print $2}' "$snap" | sort | uniq -d | grep -q . \
  && no "a version was minted twice" "$(awk '{print $2}' "$snap" | sort | uniq -d)" \
  || ok "no version was ever minted twice across the $n_snap publishes"

# And the refusal itself, exercised where it IS reachable: a resolved tree pre-seeded with the same
# key holding different bytes, published under an explicit --as so the unit is fresh.
mkdir -p "$tmp/pre/one.v1"; printf 'DIFFERENT BYTES' > "$tmp/pre/one.v1/index.html"
mkdir -p "$tmp/one"; printf '<!doctype html><h1>a</h1>' > "$tmp/one/index.html"
e=$("$pub" "$tmp/one" --to "$tmp/pre" --as one >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
# v1 is taken, so the run mints v2 and the seeded v1 is simply left alone — which is the point.
[ "$e" = 0 ] && [ -d "$tmp/pre/one.v2" ] \
  && [ "$(cat "$tmp/pre/one.v1/index.html")" = "DIFFERENT BYTES" ] \
  && ok "an occupied resolved address is stepped OVER, never written through" || no "step over" "$(outp)"

# The immutable-refusal text and --force exclusion live on the CAS address, which is flat mode's
# mechanism and the one 142 published pages actually depend on.
cas="$tmp/cas"; mkdir -p "$cas"
printf 'body{}' > "$cas/x.v1.css"
casSha="$(shasum -a 256 "$cas/x.v1.css" | cut -c1-12)"
mv "$cas/x.v1.css" "$cas/x.v1.$casSha.css"
e=$("$pub" "$cas" --to "$tmp/casout" --flat >/dev/null 2>&1; echo $?)
printf 'body{color:red}' > "$cas/x.v1.$casSha.css"     # same NAME, different bytes: corruption
e=$("$pub" "$cas" --to "$tmp/casout" --flat --force >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 1 ] && ok "a content address holding different bytes refuses even WITH --force (exit 1)" \
  || no "CAS guard" "exit $e: $(outp)"
grep -q "IMMUTABLE" "$tmp/o.txt" && ok "…and the plan names it immutable" || no "immutable notice" "$(outp)"
grep -q "force does not apply" "$tmp/e.txt" && ok "…and stderr says --force does not apply" \
  || no "force message" "$(outp)"

echo
echo "== GATE 5 · idempotence: publishing the same directory twice writes nothing the second time =="
write thirteen; e=$(run --major)                        # land on a clean trunk version
v_first="$(sed -n 's/^  version  study  [^ ]* -> \([^ ]*\).*/\1/p' "$tmp/o.txt" | head -1)"
before="$(find "$out" -type f | sort | xargs shasum -a 256 | shasum -a 256)"
n_before="$(find "$out" -type f | wc -l | tr -d ' ')"
e2=$(run)
after="$(find "$out" -type f | sort | xargs shasum -a 256 | shasum -a 256)"
n_after="$(find "$out" -type f | wc -l | tr -d ' ')"
[ "$e2" = 0 ] && ok "the second run exits 0 (a no-op is not a failure)" || no "second run exit" "$e2"
[ "$before" = "$after" ] && ok "the second run changed NOTHING (digest-of-digests identical)" \
  || no "second run wrote" "$n_before -> $n_after files, digest moved"
grep -q "unchanged, nothing to publish" "$tmp/o.txt" \
  && ok "…and says so, naming what to do next" || no "no-op message" "$(outp)"
grep -q "version  study  $v_first — unchanged" "$tmp/o.txt" \
  && ok "…and the version did NOT climb (still $v_first)" || no "version climbed" "$(outp)"

# The reference trees are part of the no-op decision, not just the resolved one.
printf 'CORRUPT' > "$out/study/index.html"
e3=$(run)
[ "$e3" = 0 ] && [ "$(cat "$out/study/index.html")" != "CORRUPT" ] \
  && ok "a corrupted REFERENCE is healed by re-publishing, not declared a no-op" \
  || no "corrupt reference survived a republish" "exit $e3: $(outp)"

echo
echo "== GATE 8 · the local layout mirrors the S3 key layout exactly =="
# Same directory, same flags, against a DRY-RUN S3 target: the keys must be the same strings.
localkeys="$(cd "$out" && find . -type f | sed 's|^\./||' | sort)"
export PROVE_S3_BUCKET=test-bucket PROVE_S3_PREFIX=proofs
mkdir -p "$tmp/bin"
cat > "$tmp/bin/aws" <<'SHIM'
#!/usr/bin/env bash
case "$*" in
  *"s3api head-object"*) exit 1 ;;
  *"s3api list-objects-v2"*) echo '{}' ;;
esac
exit 0
SHIM
chmod +x "$tmp/bin/aws"; export PATH="$tmp/bin:$PATH"
write eleven
"$pub" "$src" --to "s3://test-bucket/proofs" --dry-run > "$tmp/s3.txt" 2>&1
"$pub" "$src" --to "$tmp/out2" --dry-run > "$tmp/lo.txt" 2>&1
s3keys="$(grep -E '^ +new ' "$tmp/s3.txt" | awk '{print $2}' | sort)"
lokeys="$(grep -E '^ +new ' "$tmp/lo.txt" | awk '{print $2}' | sort)"
[ -n "$s3keys" ] && [ "$s3keys" = "$lokeys" ] \
  && ok "S3 and local plan the IDENTICAL key set ($(echo "$s3keys" | wc -l | tr -d ' ') keys)" \
  || no "layouts diverge" "s3=[$s3keys] local=[$lokeys]"
unset PROVE_S3_BUCKET PROVE_S3_PREFIX

echo
echo "== ergonomics · every refusal names the fix =="
e=$("$pub" >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 2 ] && grep -q -- "--help" "$tmp/e.txt" && ok "no arguments -> exit 2, points at --help" \
  || no "bare invocation" "exit $e: $(cat "$tmp/e.txt")"
e=$("$pub" "$src/index.html" --to "$out" >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 2 ] && grep -q "is a file, and publish moves a DIRECTORY" "$tmp/e.txt" \
  && ok "a FILE -> exit 2, and the message shows the mkdir/cp that fixes it" \
  || no "file argument" "exit $e: $(cat "$tmp/e.txt")"
e=$("$pub" "$tmp/nope" --to "$out" >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 2 ] && grep -q "no such directory" "$tmp/e.txt" && ok "a missing directory -> exit 2" \
  || no "missing dir" "exit $e"
e=$("$pub" "$src" --to "$out" --bump --major >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 2 ] && grep -q "cannot both be the answer" "$tmp/e.txt" \
  && ok "two version flags -> exit 2, explaining why they conflict" || no "conflicting flags" "exit $e"
e=$("$pub" "$src" --to "$out" --flat --minor >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 2 ] && grep -q "no unit to name or version" "$tmp/e.txt" \
  && ok "--flat with a version flag -> exit 2, names both ways out" || no "--flat conflict" "exit $e"
e=$("$pub" "$src" --to "$out" --fork 9bad >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 2 ] && grep -q "needs a branch NAME" "$tmp/e.txt" && ok "a bad --fork name -> exit 2" \
  || no "bad fork name" "exit $e"

echo
echo "== --flat · the kit path is untouched by any of this =="
flat="$tmp/flat"; mkdir -p "$flat/kit"
printf 'a{}' > "$flat/kit/proof-x.v2.css"
e=$("$pub" "$flat" --to "$tmp/flatout" --flat >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 0 ] && [ -f "$tmp/flatout/kit/proof-x.v2.css" ] \
  && ok "--flat publishes the filename verbatim at kit/proof-x.v2.css" || no "--flat" "$(outp)"
[ ! -d "$tmp/flatout/flat.v1" ] && ok "…and mints no unit directory" || no "--flat versioned anyway" ""
printf 'b{}' > "$flat/kit/proof-x.v2.css"
e=$("$pub" "$flat" --to "$tmp/flatout" --flat >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 1 ] && grep -q "different bytes" "$tmp/o.txt" \
  && ok "a flat ALIAS holding different bytes refuses (exit 1) — the guard that caught six" \
  || no "flat alias guard" "exit $e: $(outp)"
e=$("$pub" "$flat" --to "$tmp/flatout" --flat --force >"$tmp/o.txt" 2>"$tmp/e.txt"; echo $?)
[ "$e" = 0 ] && ok "…and --force DOES move a flat alias, deliberately (the retint path)" \
  || no "flat alias --force" "exit $e: $(outp)"

echo
echo "-------------------------------------"
printf 'passed %d   failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
