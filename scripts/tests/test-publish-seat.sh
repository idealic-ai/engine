#!/usr/bin/env bash
# Does every page publish-s3.sh uploads say WHO published it and HOW to answer them?
#
# The operator reads many /prove and /decide pages from many seats and could not tell which seat to
# message back. publish-s3.sh now stamps a seat strip at the top of every page it uploads. This file
# fails if any of these stop being true:
#   - the strip is injected, names the seat, says "message <seat>", and carries the publish time;
#   - a page carrying a decision board's state config also says "or answer on this board";
#   - re-publishing a page that already carries a strip REPLACES it (one strip, never two);
#   - the seat resolves live seat file → FLEET_PANE → PROVE_SEAT, and a session file that is NOT an
#     ancestor of the publisher is never taken;
#   - no seat at all says so on the page ("seat unknown — published from <host>:<cwd>") and warns;
#   - the content-verification read-back still passes (it compares the bytes sent, strip included),
#     and stdout is still the URL alone.
#
# NO NETWORK. The end-to-end cases run the real publish-s3.sh with a stub `aws` on PATH that stores
# objects in a temp dir, against a loopback endpoint on a port nothing listens on.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$here/../../skills/prove/assets"
publisher="$assets/publish-s3.sh"
strip="$assets/_seat-strip.py"
seatlib="$assets/_prove-seat.sh"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check() { # check <name> <cmd...>
  local name="$1"; shift
  if "$@"; then ok "$name"; else no "$name" "command failed: $*"; fi
}

tmp="$(mktemp -d -t prove-seat)"
trap 'rm -rf "$tmp"' EXIT

# The real environment of a dispatched lane carries FLEET_PANE and a live seat file. Every case
# below sets exactly the inputs it means to test, so clear the ambient ones first.
unset FLEET_PANE PROVE_SEAT AWS_PROFILE PROVE_S3_PROFILE PROVE_DOC_ID PROVE_KIT_PIN || true
fake_sessions="$tmp/sessions"; mkdir -p "$fake_sessions"
export PROVE_SEAT_SESSIONS_DIR="$fake_sessions"

count() { grep -o "$1" "$2" | wc -l | tr -d ' '; }
# run_strip <out> <args...> — runs the helper and FAILS the case loudly if it exits non-zero or prints
# nothing, so a negative grep that follows can never pass on empty output.
run_strip() {
  local out="$1"; shift
  if python3 "$strip" "$@" > "$out" 2> "$out.err" && [ -s "$out" ]; then return 0; fi
  no "the strip helper ran cleanly for $(basename "$out")" "exit/empty: $(tail -2 "$out.err")"
  : > "$out"; return 1
}

plain="$tmp/plain.html"
cat > "$plain" <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Plain proof</title>
<style>body{margin:0}</style></head>
<body class="x"><header style="position:fixed;top:0;left:0;right:0;height:40px">fixed</header>
<main style="padding-top:40px"><h1>Claim</h1></main>
</body></html>
HTML

# A /prove page as the composer writes it: no <head>/<body> tags at all, head elements first.
bodiless="$tmp/bodiless.html"
cat > "$bodiless" <<'HTML'
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>Bodiless</title>
<style>.page{max-width:880px}</style>
<div class="page"><header><h1>Claim</h1></header></div>
HTML

printf '\n== RESOLVE · PROVE_SEAT, then live seat file, then FLEET_PANE, never a stranger ==\n'

# shellcheck source=/dev/null
. "$seatlib"
# Output is "<seat>\t<source>\t<via>". via is the live seat an explicit PROVE_SEAT overrode, else empty.
T=$'\t'

# The test shell IS an ancestor of the resolver's subshell, so a seat file keyed by $$ is "live".
printf '{"pid":%s,"name":"idealic:runner","cwd":"/x"}' "$$" > "$fake_sessions/$$.json"
got="$(FLEET_PANE=pane:seat prove_seat_resolve)"
[ "$got" = "idealic:runner${T}session-file${T}" ] && ok "an ancestor's seat file wins over FLEET_PANE" \
  || no "an ancestor's seat file wins over FLEET_PANE" "got '$got'"

# PROVE_SEAT is FIRST (an explicit per-invocation value beats an inferred one), and the live seat it
# overrode is kept as "via" so a stale export is visible on the page, not silent.
got="$(FLEET_PANE=pane:seat PROVE_SEAT=worker:seat prove_seat_resolve)"
[ "$got" = "worker:seat${T}PROVE_SEAT${T}idealic:runner" ] && ok "PROVE_SEAT overrides the live seat and records it as via" \
  || no "PROVE_SEAT overrides the live seat and records it as via" "got '$got'"
got="$(PROVE_SEAT=idealic:runner prove_seat_resolve)"
[ "$got" = "idealic:runner${T}PROVE_SEAT${T}" ] && ok "PROVE_SEAT equal to the live seat carries no via" \
  || no "PROVE_SEAT equal to the live seat carries no via" "got '$got'"

# Pid reuse: a lingering seat file whose procStart is not this pid's start time is a dead session's.
printf '{"pid":%s,"name":"reused:seat","procStart":"Mon Jan  1 00:00:00 2001"}' "$$" > "$fake_sessions/$$.json"
got="$(FLEET_PANE=pane:seat prove_seat_resolve)"
[ "$got" = "pane:seat${T}FLEET_PANE${T}" ] && ok "a seat file whose procStart mismatches the live pid is skipped (pid reuse)" \
  || no "a seat file whose procStart mismatches the live pid is skipped (pid reuse)" "got '$got'"
realstart="$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ | tr -s ' ' | sed 's/ *$//')"
printf '{"pid":%s,"name":"started:seat","procStart":"%s"}' "$$" "$realstart" > "$fake_sessions/$$.json"
got="$(FLEET_PANE=pane:seat prove_seat_resolve)"
[ "$got" = "started:seat${T}session-file${T}" ] && ok "a seat file whose procStart matches is taken" \
  || no "a seat file whose procStart matches is taken" "got '$got' (lstart '$realstart')"
rm -f "$fake_sessions/$$.json"

# A seat file for a LIVE process that is NOT our ancestor must be ignored — picking "some live
# claude" is exactly the guess the brief forbids. A background sleep is live and is nobody's parent.
sleep 60 & stranger=$!
printf '{"pid":%s,"name":"stranger:seat"}' "$stranger" > "$fake_sessions/$stranger.json"
printf '{"pid":999999,"name":"dead:seat"}' > "$fake_sessions/999999.json"
got="$(FLEET_PANE=pane:seat prove_seat_resolve)"
[ "$got" = "pane:seat${T}FLEET_PANE${T}" ] && ok "a LIVE non-ancestor seat file is never taken; FLEET_PANE is next" \
  || no "a LIVE non-ancestor seat file is never taken; FLEET_PANE is next" "got '$got'"
got="$(PROVE_SEAT_START_PID=$stranger FLEET_PANE=pane:seat prove_seat_resolve)"
[ "$got" = "stranger:seat${T}session-file${T}" ] && ok "control: the same file IS taken when that pid is the start of the walk" \
  || no "control: the same file IS taken when that pid is the start of the walk" "got '$got'"
kill "$stranger" 2>/dev/null; wait "$stranger" 2>/dev/null

got="$(PROVE_SEAT=env:seat prove_seat_resolve)"
[ "$got" = "env:seat${T}PROVE_SEAT${T}" ] && ok "PROVE_SEAT alone resolves, with no via" \
  || no "PROVE_SEAT alone resolves, with no via" "got '$got'"

got="$(prove_seat_resolve)"
[ "$got" = "${T}unknown${T}" ] && ok "nothing resolves → empty seat, source 'unknown'" \
  || no "nothing resolves → empty seat, source 'unknown'" "got '$got'"

# A seat file with an empty name is not a seat.
printf '{"pid":%s,"name":""}' "$$" > "$fake_sessions/$$.json"
got="$(FLEET_PANE=pane:seat prove_seat_resolve)"
[ "$got" = "pane:seat${T}FLEET_PANE${T}" ] && ok "an ancestor seat file with an empty name falls through" \
  || no "an ancestor seat file with an empty name falls through" "got '$got'"
rm -f "$fake_sessions/$$.json"

printf '\n== INJECT · the strip names the seat, how to reply, and when ==\n'

run_strip "$tmp/p1.html" "$plain" --seat 'manager:director' --source session-file --when 2026-10-28T14:00:00Z \
  && ok "the strip helper exits 0 with output"
[ "$(count 'data-prove-seat-strip' "$tmp/p1.html")" -ge 1 ] && ok "the strip element is present" || no "the strip element is present" "$(cat "$tmp/p1.err")"
grep -q 'manager:director' "$tmp/p1.html" && ok "the strip names the seat" || no "the strip names the seat"
grep -q 'message <code[^>]*>manager:director</code>' "$tmp/p1.html" && ok "the strip says how to reply: message <seat>" \
  || no "the strip says how to reply: message <seat>" "$(grep -o 'data-prove-seat-strip.\{0,600\}' "$tmp/p1.html" | head -1)"
grep -q 'datetime="2026-10-28T14:00:00Z"' "$tmp/p1.html" && ok "the strip carries the publish time" || no "the strip carries the publish time"
grep -q 'answer on this board' "$tmp/p1.html" && no "a plain page carries NO board line" || ok "a plain page carries NO board line"
# Placed as the first thing in <body>: after the open tag, before the page's own fixed header.
python3 - "$tmp/p1.html" <<'PY' && ok "the strip is the first child of <body>, before the page's fixed header" || no "the strip is the first child of <body>, before the page's fixed header"
import re, sys
p = open(sys.argv[1]).read()
b = re.search(r"<body\b[^>]*>", p); s = p.find("<!--prove-seat-strip:begin"); h = p.find("<header")
sys.exit(0 if b and b.end() <= s < h and p[b.end():s].strip() == "" else 1)
PY
# Everything outside the strip is the original page, byte for byte.
python3 - "$tmp/p1.html" "$plain" <<'PY' && ok "outside the strip the page is byte-identical" || no "outside the strip the page is byte-identical"
import re, sys
out = open(sys.argv[1]).read(); src = open(sys.argv[2]).read()
stripped = re.sub(r"<!--prove-seat-strip:begin-->.*?<!--prove-seat-strip:end-->", "", out, flags=re.S)
sys.exit(0 if stripped == src else 1)
PY
# No external assets: no src/href to anything inside the strip.
python3 - "$tmp/p1.html" <<'PY' && ok "the strip references no external asset" || no "the strip references no external asset"
import re, sys
p = open(sys.argv[1]).read()
m = re.search(r"<!--prove-seat-strip:begin-->(.*?)<!--prove-seat-strip:end-->", p, re.S)
sys.exit(0 if m and not re.search(r"\b(src|href)\s*=|url\(|@import", m.group(1)) else 1)
PY
# Theme-safe: a light palette, a dark palette for prefers-color-scheme AND for data-theme="dark".
grep -q 'prefers-color-scheme: *dark' "$tmp/p1.html" && grep -q 'data-theme="dark"' "$tmp/p1.html" \
  && ok "the strip declares both the OS dark scheme and the page's data-theme dark" \
  || no "the strip declares both the OS dark scheme and the page's data-theme dark"

run_strip "$tmp/esc.html" "$plain" --seat '<b>evil</b>' --source PROVE_SEAT --when 2026-10-28T14:00:00Z
grep -q '&lt;b&gt;evil&lt;/b&gt;' "$tmp/esc.html" && ! grep -q '<b>evil</b>' "$tmp/esc.html" \
  && ok "a seat name is HTML-escaped in text (and the helper did not crash on '<')" || no "a seat name is HTML-escaped in text (and the helper did not crash on '<')"
# Attribute context: a quote in the seat must not break out of data-seat="…".
run_strip "$tmp/q.html" "$plain" --seat 'x" onmouseover="alert(1)' --source PROVE_SEAT --via 'a"b' --when 2026-10-28T14:00:00Z
grep -q 'data-seat="x&quot; onmouseover=&quot;alert(1)"' "$tmp/q.html" && ! grep -q ' onmouseover="alert' "$tmp/q.html" \
  && ok "a quote in the seat is escaped inside the data-seat attribute" \
  || no "a quote in the seat is escaped inside the data-seat attribute" "$(grep -o 'data-seat=.\{0,80\}' "$tmp/q.html" | head -1)"

run_strip "$tmp/bl.html" "$bodiless" --seat 'manager:director' --source FLEET_PANE --when 2026-10-28T14:00:00Z
python3 - "$tmp/bl.html" <<'PY' && ok "a page with no <body> tag gets the strip after its head elements, before its first content" || no "a page with no <body> tag gets the strip after its head elements, before its first content"
import sys
p = open(sys.argv[1]).read()
s = p.find("prove-seat-strip:begin"); st = p.find("</style>"); d = p.find('<div class="page"')
sys.exit(0 if st < s < d else 1)
PY

# Two traps, both from the real /decide skeleton. Each one put the strip in the wrong place:
#   1. it names `<body>` inside its leading authoring comment. A text search put the strip in that
#      comment, the strip's `-->` closed it early, and the head fell into the body. The 400px page
#      went 1478px wide.
#   2. its favicon <link> holds an inline <svg …> inside a quoted href, so a tag that ends at the
#      first '>' stops mid-attribute, and the strip landed in an attribute inside <head>.
commented="$tmp/commented.html"
cat > "$commented" <<'HTML'
<!doctype html>
<!-- AUTHORING: put data-fb-board on <body> — cut this comment -->
<html><head><meta charset="utf-8"><title>T</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg'><text>x</text></svg>">
<script>var s = "<body class=fake>";</script>
<style>/* <body> */</style></head>
<body data-real="1"><main>x</main></body></html>
HTML
run_strip "$tmp/cm.html" "$commented" --seat 'manager:director' --source FLEET_PANE --when 2026-10-28T14:00:00Z
python3 - "$tmp/cm.html" <<'PY' && ok "a <body> named in a comment, script or quoted attribute is skipped; the strip follows the REAL <body>" || no "a <body> named in a comment, script or quoted attribute is skipped; the strip follows the REAL <body>"
import sys
p = open(sys.argv[1]).read()
real = p.find('<body data-real="1">'); s = p.find("<!--prove-seat-strip:begin")
sys.exit(0 if real >= 0 and s == real + len('<body data-real="1">') else 1)
PY
# Same favicon trap on a page with NO <body> tag: the strip must still land after the head.
sed 's|<body data-real="1">||; s|</body>||' "$commented" > "$tmp/cm2-src.html"
run_strip "$tmp/cm2.html" "$tmp/cm2-src.html" --seat 'manager:director' --source FLEET_PANE --when 2026-10-28T14:00:00Z
python3 - "$tmp/cm2.html" <<'PY' && ok "with no <body>, a quoted '>' in a head attribute does not pull the strip into <head>" || no "with no <body>, a quoted '>' in a head attribute does not pull the strip into <head>"
import sys
p = open(sys.argv[1]).read()
s = p.find("<!--prove-seat-strip:begin"); h = p.find("</head>"); m = p.find("<main>")
sys.exit(0 if h < s < m else 1)
PY

printf '\n== BOARD · a page carrying a state config says it can be answered in place ==\n'
run_strip "$tmp/b1.html" "$plain" --seat 'manager:director' --source session-file --board --when 2026-10-28T14:00:00Z
grep -q 'or answer on this board' "$tmp/b1.html" && ok "the board strip adds 'or answer on this board'" || no "the board strip adds 'or answer on this board'"

run_strip "$tmp/b2.html" "$plain" --seat 'manager:director' --source session-file --board --copy-back --when 2026-10-28T14:00:00Z
grep -q 'or answer on this board (copy-back)' "$tmp/b2.html" && ok "a board with no write grant says 'answer on this board (copy-back)'" \
  || no "a board with no write grant says 'answer on this board (copy-back)'"

printf '\n== VIA · an explicit PROVE_SEAT that overrides a live seat says so on the page ==\n'
run_strip "$tmp/v1.html" "$plain" --seat 'worker:seat' --source PROVE_SEAT --via 'manager:director' --when 2026-10-28T14:00:00Z
grep -q 'Published by <b>worker:seat</b> (via <code>manager:director</code>)' "$tmp/v1.html" \
  && ok "the strip reads 'Published by X (via <live seat>)'" || no "the strip reads 'Published by X (via <live seat>)'" "$(grep -o 'Published by.\{0,120\}' "$tmp/v1.html")"
grep -q 'message <code>worker:seat</code>' "$tmp/v1.html" && ok "the reply route is the PROVE_SEAT seat" || no "the reply route is the PROVE_SEAT seat"
run_strip "$tmp/v2.html" "$plain" --seat 'worker:seat' --source PROVE_SEAT --when 2026-10-28T14:00:00Z
grep -q '(via' "$tmp/v2.html" && no "no via when nothing was overridden" || ok "no via when nothing was overridden"

printf '\n== IDEMPOTENT · a re-publish replaces the strip, never stacks a second ==\n'
run_strip "$tmp/p2.html" "$tmp/p1.html" --seat 'idealic:runner' --source FLEET_PANE --board --when 2026-10-29T09:00:00Z
[ "$(count 'prove-seat-strip:begin' "$tmp/p2.html")" = 1 ] && ok "one strip after two injections" \
  || no "one strip after two injections" "found $(count 'prove-seat-strip:begin' "$tmp/p2.html")"
grep -q 'manager:director' "$tmp/p2.html" && no "the second injection REPLACED the first seat" || ok "the second injection REPLACED the first seat"
grep -q 'datetime="2026-10-29T09:00:00Z"' "$tmp/p2.html" && ! grep -q 'datetime="2026-10-28T14:00:00Z"' "$tmp/p2.html" \
  && ok "the time is the latest publish's" || no "the time is the latest publish's"
run_strip "$tmp/p3.html" "$tmp/p2.html" --seat 'idealic:runner' --source FLEET_PANE --board --when 2026-10-29T09:00:00Z
cmp -s "$tmp/p2.html" "$tmp/p3.html" && ok "the same inputs twice produce the same bytes" || no "the same inputs twice produce the same bytes"

# A page that EMBEDS earlier published bytes (a before/after exhibit, a JSON blob) carries a marker
# pair inside a <script>. That is data, not this page's strip: the strip must go at the top and the
# script must be untouched. Measured before the fix: the strip was spliced into the JS string.
embed="$tmp/embed.html"
cat > "$embed" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>E</title>
<script>var before = "<body><!--prove-seat-strip:begin--><div>old strip</div><!--prove-seat-strip:end--><main>x</main>";</script>
</head><body><!-- <!--prove-seat-strip:begin--> --><main>y</main></body></html>
HTML
run_strip "$tmp/em.html" "$embed" --seat 'manager:director' --source FLEET_PANE --when 2026-10-28T14:00:00Z
python3 - "$tmp/em.html" "$embed" <<'PY' && ok "markers inside a <script> or a comment are not an existing strip; the script is untouched" || no "markers inside a <script> or a comment are not an existing strip; the script is untouched"
import re, sys
out = open(sys.argv[1]).read(); src = open(sys.argv[2]).read()
script = re.search(r"<script>.*?</script>", src, re.S).group(0)
body = out.find("</head><body>") + len("</head><body>")  # the REAL body tag; the script string holds a fake one
ok = script in out and out.startswith('<!--prove-seat-strip:begin--><div class="prove-seat-strip"', body)
sys.exit(0 if ok else 1)
PY
run_strip "$tmp/em2.html" "$tmp/em.html" --seat 'idealic:runner' --source FLEET_PANE --when 2026-10-28T14:00:00Z
[ "$(count '<!--prove-seat-strip:begin--><div class="prove-seat-strip"' "$tmp/em2.html")" = 1 ] && grep -q 'old strip' "$tmp/em2.html" \
  && grep -q 'idealic:runner' "$tmp/em2.html" && ! grep -q 'manager:director' "$tmp/em2.html" \
  && ok "re-stamping that page replaces only its real strip" || no "re-stamping that page replaces only its real strip"

# CRLF and bare CR survive: the page is bytes outside the markers, not text-mode-normalised.
printf '<!doctype html>\r\n<html><head><title>c</title></head>\r\n<body><pre>a\rb</pre>\r\n</body></html>\r\n' > "$tmp/crlf.html"
run_strip "$tmp/crlf-out.html" "$tmp/crlf.html" --seat 'manager:director' --source FLEET_PANE --when 2026-10-28T14:00:00Z
python3 - "$tmp/crlf-out.html" "$tmp/crlf.html" <<'PY' && ok "CRLF and bare CR are preserved byte for byte outside the strip" || no "CRLF and bare CR are preserved byte for byte outside the strip"
import re, sys
out = open(sys.argv[1], "rb").read(); src = open(sys.argv[2], "rb").read()
sys.exit(0 if re.sub(rb"<!--prove-seat-strip:begin-->.*?<!--prove-seat-strip:end-->", b"", out, flags=re.S) == src else 1)
PY

# A tagless upload (markdown or text served as text/html) gets the strip on top, not at the bottom.
printf 'Plain notes\nsecond line\n' > "$tmp/text.html"
run_strip "$tmp/text-out.html" "$tmp/text.html" --seat 'manager:director' --source FLEET_PANE --when 2026-10-28T14:00:00Z
head -c 29 "$tmp/text-out.html" | grep -q '^<!--prove-seat-strip:begin-->' && ok "a page with no leading tag gets the strip at the top" \
  || no "a page with no leading tag gets the strip at the top"

printf '\n== UNKNOWN · no seat is said on the page, never guessed ==\n'
run_strip "$tmp/u1.html" "$plain" --seat '' --source unknown --origin 'box:/some/cwd' --when 2026-10-28T14:00:00Z
grep -q 'seat unknown — published from <code[^>]*>box:/some/cwd</code>' "$tmp/u1.html" && ok "the unknown-seat strip names host:cwd" \
  || no "the unknown-seat strip names host:cwd" "$(grep -o 'seat unknown.\{0,120\}' "$tmp/u1.html" | head -1)"
grep -q 'message <code' "$tmp/u1.html" && no "the unknown-seat strip offers no 'message' target" || ok "the unknown-seat strip offers no 'message' target"

printf '\n== END TO END · the real publisher, a stub store, the read-back still verifies ==\n'
stub="$tmp/bin"; store="$tmp/store"; mkdir -p "$stub" "$store"
cat > "$stub/aws" <<'STUB'
#!/usr/bin/env bash
# Minimal object store: enough of `aws` for publish-s3.sh, objects kept under $STUB_STORE.
store="${STUB_STORE:?}"; args=("$@"); bucket=""; key=""; body=""; out=""
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    --bucket) bucket="${args[$((i+1))]}" ;;
    --key) key="${args[$((i+1))]}" ;;
    --body) body="${args[$((i+1))]}" ;;
  esac
done
case "$1 $2" in
  "s3 cp")
    src="$3"; dst="$4"; dst="${dst#s3://}"; mkdir -p "$store/$(dirname "$dst")"; cp "$src" "$store/$dst" ;;
  "s3api get-object")
    out="${args[$((${#args[@]}-1))]}"; [ -f "$store/$bucket/$key" ] || exit 1
    cp "$store/$bucket/$key" "$out"; printf '{"ETag":"\\"x\\""}\n' ;;
  "s3api put-object")
    mkdir -p "$store/$bucket/$(dirname "$key")"; cp "$body" "$store/$bucket/$key" ;;
  "s3api list-objects-v2") echo None ;;
  "s3api delete-object") : ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub/aws"
envfile="$tmp/proj.env"
printf 'PROVE_S3_BUCKET=proofs\nPROVE_S3_ENDPOINT=http://127.0.0.1:9\nPROVE_S3_PUBLIC_BASE=http://127.0.0.1:9\nPROVE_S3_PREFIX=proofs\nPROVE_S3_USER=t\n' > "$envfile"

publish() { # publish <page> <outvar-prefix> [env...]
  local page="$1" tag="$2"; shift 2
  env PATH="$stub:$PATH" STUB_STORE="$store" PROVE_S3_ENV="$envfile" "$@" \
    bash "$publisher" "$page" "$tag" > "$tmp/$tag.out" 2> "$tmp/$tag.err"
}
stored() { local url; url="$(cat "$tmp/$1.out")"; printf '%s/%s' "$store" "${url#http://127.0.0.1:9/}"; }

printf '{"pid":%s,"name":"idealic:runner"}' "$$" > "$fake_sessions/$$.json"
if publish "$plain" e2eplain; then
  ok "the publisher exits 0 against the stub store"
  [ "$(wc -l < "$tmp/e2eplain.out" | tr -d ' ')" = 1 ] && grep -q '^http://127.0.0.1:9/proofs/proofs/t/e2eplain-' "$tmp/e2eplain.out" \
    && ok "stdout is still the URL and nothing else" || no "stdout is still the URL and nothing else" "$(cat "$tmp/e2eplain.out")"
  obj="$(stored e2eplain)"
  grep -q 'message <code[^>]*>idealic:runner</code>' "$obj" && ok "the uploaded object carries the strip with the live seat" \
    || no "the uploaded object carries the strip with the live seat" "$(grep -i seat "$tmp/e2eplain.err" | head -3)"
  grep -q 'verified by content' "$tmp/e2eplain.err" && ok "the read-back still verifies by content, strip included" \
    || no "the read-back still verifies by content, strip included" "$(tail -5 "$tmp/e2eplain.err")"
  grep -q 'seat strip: idealic:runner (from session-file' "$tmp/e2eplain.err" && ok "the publisher states the seat and where it came from" \
    || no "the publisher states the seat and where it came from" "$(grep -i seat "$tmp/e2eplain.err")"
  grep -q 'prove-seat-strip' "$plain" && no "the source page is never edited" || ok "the source page is never edited"

  # Re-publish the PUBLISHED bytes (a page fetched back and republished) — still one strip.
  cp "$obj" "$tmp/republish.html"
  if publish "$tmp/republish.html" e2ere FLEET_PANE=ignored:pane; then
    [ "$(count 'prove-seat-strip:begin' "$(stored e2ere)")" = 1 ] && ok "re-publishing a published page leaves exactly one strip" \
      || no "re-publishing a published page leaves exactly one strip" "found $(count 'prove-seat-strip:begin' "$(stored e2ere)")"
  else
    no "re-publish exits 0" "$(tail -5 "$tmp/e2ere.err")"
  fi
else
  no "the publisher exits 0 against the stub store" "$(tail -8 "$tmp/e2eplain.err")"
fi
rm -f "$fake_sessions/$$.json"

board="$tmp/board.html"
cat > "$board" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Board</title></head>
<body data-fb-board="t"><article data-fb-item="a"><input type="radio" data-fb-key="yes"></article></body></html>
HTML
if publish "$board" e2eboard FLEET_PANE=manager:director; then
  obj="$(stored e2eboard)"
  grep -q 'data-fb-state-config' "$obj" && ok "the board got its state config (unchanged behaviour)" || no "the board got its state config (unchanged behaviour)"
  grep -q 'or answer on this board' "$obj" && ok "the published board's strip says it can be answered on the board" \
    || no "the published board's strip says it can be answered on the board"
  grep -q 'message <code[^>]*>manager:director</code>' "$obj" && ok "FLEET_PANE resolves the seat when no seat file is an ancestor" \
    || no "FLEET_PANE resolves the seat when no seat file is an ancestor"
  grep -q 'verified by content' "$tmp/e2eboard.err" && ok "the board's read-back still verifies" || no "the board's read-back still verifies"
else
  no "the board publishes against the stub store" "$(tail -8 "$tmp/e2eboard.err")"
fi

# M1 — the board line comes from what the publish DID, never from a grep of the page.
mention="$tmp/mention.html"
cat > "$mention" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Docs</title></head>
<body><p>The publisher injects <code>&lt;script data-fb-state-config&gt;</code>.</p>
<pre class="language-text">data-fb-state-config &lt;script id="prove-state-config" data-fb-state-config&gt;</pre></body></html>
HTML
if publish "$mention" e2emention FLEET_PANE=manager:director; then
  obj="$(stored e2emention)"
  grep -q 'message <code>manager:director</code>' "$obj" && ! grep -q 'answer on this board' "$obj" \
    && ok "a page that only MENTIONS data-fb-state-config gets no board line" \
    || no "a page that only MENTIONS data-fb-state-config gets no board line" "$(grep 'seat strip' "$tmp/e2emention.err")"
else
  no "the mention page publishes" "$(tail -5 "$tmp/e2emention.err")"
fi
# R5 — the flags are this script's own state: exported values of the same names must not leak in.
if publish "$mention" e2eleak FLEET_PANE=manager:director seatBoard=--board seatCopyBack=--copy-back; then
  obj="$(stored e2eleak)"
  grep -q 'message <code>manager:director</code>' "$obj" && ! grep -q 'answer on this board' "$obj" \
    && ok "seatBoard/seatCopyBack exported in the environment do not leak a board line" \
    || no "seatBoard/seatCopyBack exported in the environment do not leak a board line" "$(grep 'seat strip' "$tmp/e2eleak.err")"
else
  no "the leak-check page publishes" "$(tail -5 "$tmp/e2eleak.err")"
fi
if publish "$assets/state-demo.html" e2edemo FLEET_PANE=manager:director; then
  obj="$(stored e2edemo)"
  grep -q 'state config injected' "$tmp/e2edemo.err" && grep -q 'or answer on this board' "$obj" \
    && ok "state-demo (placeholder, no data-fb-state-config attribute) gets the board line" \
    || no "state-demo (placeholder, no data-fb-state-config attribute) gets the board line" "$(grep -E 'seat strip|state config' "$tmp/e2edemo.err")"
else
  no "state-demo publishes" "$(tail -5 "$tmp/e2edemo.err")"
fi

# S4 end to end: PROVE_SEAT overrides the live seat file, visibly on the page and on stderr.
printf '{"pid":%s,"name":"idealic:runner"}' "$$" > "$fake_sessions/$$.json"
if publish "$plain" e2evia PROVE_SEAT=worker:seat; then
  obj="$(stored e2evia)"
  grep -q 'Published by <b>worker:seat</b> (via <code>idealic:runner</code>)' "$obj" && ok "PROVE_SEAT publishes as worker:seat (via the live seat)" \
    || no "PROVE_SEAT publishes as worker:seat (via the live seat)"
  grep -q 'PROVE_SEAT overrides live seat idealic:runner' "$tmp/e2evia.err" && ok "stderr says PROVE_SEAT overrode the live seat" \
    || no "stderr says PROVE_SEAT overrode the live seat" "$(grep -i seat "$tmp/e2evia.err")"
else
  no "the PROVE_SEAT publish exits 0" "$(tail -5 "$tmp/e2evia.err")"
fi
printf '{}' > "$fake_sessions/$$.json"

# S2 — a partial landing (helper missing) must fail LOUDLY and before any byte moves, under the
# macOS bash 3.2 whose EXIT trap otherwise turns a failed `.` into exit 0.
for missing in _prove-seat.sh _seat-strip.py; do
  part="$tmp/partial-$missing"; cp -R "$assets" "$part"; mv "$part/$missing" "$tmp/moved-$missing"
  find "$store" -type f | sort > "$tmp/before.list"
  env PATH="$stub:$PATH" STUB_STORE="$store" PROVE_S3_ENV="$envfile" FLEET_PANE=manager:director \
    /bin/bash "$part/publish-s3.sh" "$plain" partial > "$tmp/partial.out" 2> "$tmp/partial.err"; rc=$?
  find "$store" -type f | sort > "$tmp/after.list"
  [ "$rc" != 0 ] && [ ! -s "$tmp/partial.out" ] && grep -q "$missing" "$tmp/partial.err" && cmp -s "$tmp/before.list" "$tmp/after.list" \
    && ok "missing $missing → non-zero exit ($rc), a message, nothing uploaded (/bin/bash 3.2)" \
    || no "missing $missing → non-zero exit, a message, nothing uploaded (/bin/bash 3.2)" "rc=$rc out='$(cat "$tmp/partial.out")' err='$(tail -2 "$tmp/partial.err")'"
done

if publish "$plain" e2eunk; then
  obj="$(stored e2eunk)"
  grep -q "seat unknown — published from <code[^>]*>$(hostname -s 2>/dev/null || hostname):" "$obj" && ok "no seat → the page says 'seat unknown — published from <host>:<cwd>'" \
    || no "no seat → the page says 'seat unknown — published from <host>:<cwd>'" "$(grep -o 'seat unknown.\{0,120\}' "$obj")"
  grep -q 'WARNING — no seat resolved' "$tmp/e2eunk.err" && ok "no seat → the publisher prints a warning" \
    || no "no seat → the publisher prints a warning" "$(grep -i seat "$tmp/e2eunk.err")"
else
  no "the unknown-seat publish exits 0" "$(tail -8 "$tmp/e2eunk.err")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
