#!/usr/bin/env bash
# Does every code block on a published proof page carry a language, and does the page highlight it?
#
# Operator request (2026-10-30): every code fence on a proof page gets a highlighter language and
# is highlighted in the browser. The proof-page half lives in three places, and this file fails if
# any of them stops doing its part:
#   - skills/prove/assets/_fence-lang.py `check` — a <pre> with no `language-*` class on itself or on
#     a <code> inside it is an offender, named by line, exit 6; a tagged block passes;
#   - skills/prove/assets/_fence-lang.py `inject` — a page with a highlightable block gets the kit
#     highlighter inlined exactly once (idempotent on republish); a page with none is left alone;
#   - skills/intake/assets/proof-highlight.js — tokenises the languages it knows into hl-* spans,
#     escapes HTML, leaves `language-text` and any hand-marked block untouched;
#   - skills/prove/assets/publish-s3.sh — refuses an untagged page before any byte moves, and
#     uploads a tagged one carrying the highlighter.
#
# NO NETWORK. The end-to-end cases run the real publish-s3.sh with a stub `aws` on PATH that keeps
# objects in a temp dir, against a loopback endpoint on a port nothing listens on.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$here/../../skills/prove/assets"
kit="$here/../../skills/intake/assets"
fence="$assets/_fence-lang.py"
publisher="$assets/publish-s3.sh"
hljs="$kit/proof-highlight.js"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

for tool in python3 node; do
  command -v "$tool" >/dev/null 2>&1 || { echo "test-prove-fence-lang: $tool not on PATH; nothing checked" >&2; exit 2; }
done

tmp="$(mktemp -d -t prove-fence)"
trap 'rm -rf "$tmp"' EXIT

page() { # page <name> <body html> — a minimal page around the given body
  printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><title>t</title></head>\n<body>\n%s\n</body></html>\n' "$2" > "$tmp/$1.html"
  printf '%s' "$tmp/$1.html"
}

# expect_check <name> <want-rc> <body> [stderr-substring]
expect_check() {
  local name="$1" want="$2" body="$3" needle="${4:-}" p rc
  p="$(page "c$pass$fail" "$body")"
  python3 "$fence" check "$p" > "$tmp/chk.out" 2> "$tmp/chk.err"; rc=$?
  if [ "$rc" != "$want" ]; then
    no "$name" "rc=$rc want=$want err='$(tr '\n' ' ' < "$tmp/chk.err" | cut -c1-200)'"
  elif [ -n "$needle" ] && ! grep -qF -- "$needle" "$tmp/chk.err"; then
    no "$name" "rc=$rc but stderr lacks '$needle': $(tr '\n' ' ' < "$tmp/chk.err" | cut -c1-200)"
  else
    ok "$name"
  fi
}

printf '\n== CHECK · every <pre> names its language ==\n'
expect_check "an untagged <pre> is refused (exit 6) and named by line" 6 '<pre>npm test</pre>' 'line 4'
expect_check "a <pre><code> with no class is refused" 6 '<pre><code>x = 1</code></pre>' 'no language-*'
expect_check "a class that is not language-* does not count" 6 '<pre class="codewrap"><code class="hljs">x</code></pre>'
expect_check "an empty language- class does not count" 6 '<pre><code class="language-">x</code></pre>'
expect_check "an uppercase <PRE> is still a code block" 6 '<PRE>x</PRE>'
expect_check "control: <pre><code class=\"language-ts\"> passes" 0 '<pre><code class="language-ts">const x = 1</code></pre>'
expect_check "control: <pre class=\"language-text\"> passes" 0 '<pre class="language-text">plain output</pre>'
expect_check "control: the language class may sit beside others" 0 '<div class="codewrap"><pre class="x"><code class="k language-bash y">ls</code></pre></div>'
expect_check "inline <code> outside a <pre> is not a block" 0 '<p>run <code>npm test</code> first</p>'
expect_check "a <pre> inside a script string is not a block" 0 '<script>const s = "<pre>x</pre>";</script>'
expect_check "one bad block among good ones still refuses" 6 '<pre><code class="language-ts">a</code></pre><pre>b</pre>' '1 code block'

printf '\n== INJECT · the kit highlighter rides inline, once ==\n'
p="$(page inj '<pre><code class="language-ts">const x = 1</code></pre>')"
if python3 "$fence" inject "$p" > "$tmp/inj1.html" 2> "$tmp/inj.err" && [ -s "$tmp/inj1.html" ]; then
  n_s="$(grep -c '<script data-proof-highlight' "$tmp/inj1.html")"
  n_c="$(grep -c '<style data-proof-highlight' "$tmp/inj1.html")"
  [ "$n_s" = 1 ] && [ "$n_c" = 1 ] && ok "a tagged page gets one inline <script> and one <style>" \
    || no "a tagged page gets one inline <script> and one <style>" "script=$n_s style=$n_c"
  grep -q 'src=' "$tmp/inj1.html" && no "the injected highlighter references no external file" "$(grep -o '<script[^>]*>' "$tmp/inj1.html")" \
    || ok "the injected highlighter references no external file"
  awk '/data-proof-highlight/{a=NR} /<\/body>/{b=NR} END{exit !(a && b && a<=b)}' "$tmp/inj1.html" \
    && ok "it lands before </body>" || no "it lands before </body>"
  python3 "$fence" inject "$tmp/inj1.html" > "$tmp/inj2.html" 2>/dev/null
  n_s="$(grep -c '<script data-proof-highlight' "$tmp/inj2.html")"
  [ "$n_s" = 1 ] && cmp -s "$tmp/inj1.html" "$tmp/inj2.html" && ok "re-injecting is idempotent (byte-identical, one copy)" \
    || no "re-injecting is idempotent (byte-identical, one copy)" "scripts=$n_s"
else
  no "inject runs cleanly on a tagged page" "$(tail -3 "$tmp/inj.err")"
fi
for case_ in "nopre|<p>no code here</p>" "textonly|<pre class=\"language-text\">plain</pre>"; do
  nm="${case_%%|*}"; body="${case_#*|}"
  p="$(page "$nm" "$body")"
  python3 "$fence" inject "$p" > "$tmp/$nm.out" 2>/dev/null
  cmp -s "$p" "$tmp/$nm.out" && ok "a page with nothing to highlight ($nm) is left byte-identical" \
    || no "a page with nothing to highlight ($nm) is left byte-identical"
done

printf '<!doctype html>\r\n<html><body>\r\n<pre><code class="language-ts">a\rb</code></pre>\r\n</body></html>\r\n' > "$tmp/crlf.html"
python3 "$fence" inject "$tmp/crlf.html" > "$tmp/crlf-out.html" 2>/dev/null
python3 - "$tmp/crlf-out.html" "$tmp/crlf.html" <<'PY' && ok "CRLF and bare CR survive injection byte for byte outside the block" || no "CRLF and bare CR survive injection byte for byte outside the block"
import re, sys
out = open(sys.argv[1], "rb").read(); src = open(sys.argv[2], "rb").read()
stripped = re.sub(rb"<style data-proof-highlight>.*?</script>\n", b"", out, flags=re.S)
sys.exit(0 if stripped == src and out != src else 1)
PY

printf '\n== HIGHLIGHT · the kit tokeniser ==\n'
node - "$hljs" > "$tmp/node.out" 2>&1 <<'JS'
const H = require(process.argv[2]);
const out = [];
const t = (name, cond, extra) => out.push((cond ? 'ok   ' : 'FAIL ') + name + (cond ? '' : '\n     ' + (extra || '')));
let h = H.highlight('const x = "a<b"; // note\nfoo(42)', 'ts');
t('ts: keyword, string, comment, number, call get their spans', h &&
  h.includes('<span class="hl-k">const</span>') && h.includes('<span class="hl-s">&quot;a&lt;b&quot;</span>') &&
  h.includes('<span class="hl-c">// note</span>') && h.includes('<span class="hl-n">42</span>') &&
  h.includes('<span class="hl-f">foo</span>'), h);
t('ts: the text round-trips (strip spans, unescape = source)', h &&
  h.replace(/<[^>]+>/g, '').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&')
  === 'const x = "a<b"; // note\nfoo(42)', h);
h = H.highlight('# say hi\necho "x" $HOME && ls', 'bash');
t('bash: comment, string, variable', h && h.includes('<span class="hl-c"># say hi</span>') &&
  h.includes('<span class="hl-s">&quot;x&quot;</span>') && h.includes('<span class="hl-v">$HOME</span>'), h);
h = H.highlight('-old\n+new\n@@ -1 +1 @@', 'diff');
t('diff: added, removed and hunk lines', h && h.includes('<span class="hl-add">+new</span>') &&
  h.includes('<span class="hl-del">-old</span>') && h.includes('<span class="hl-hunk">@@ -1 +1 @@</span>'), h);
h = H.highlight('{"k": true, "n": 1}', 'json');
t('json: key, literal, number', h && h.includes('<span class="hl-a">&quot;k&quot;</span>') &&
  h.includes('<span class="hl-l">true</span>'), h);
t('text renders unhighlighted (null: leave the block alone)', H.highlight('if (x) "y"', 'text') === null);
t('an unknown language renders unhighlighted', H.highlight('if (x)', 'klingon') === null);
// The DOM half, on a stand-in element: a hand-marked block (child elements) is never rewritten.
const el = (cls, text, kids) => ({ className: cls, textContent: text, children: { length: kids }, innerHTML: '', dataset: {},
  parentNode: { tagName: 'PRE', className: '' } });
let a = el('language-ts', 'let y', 0); H.highlightElement(a);
t('highlightElement fills a plain tagged block', a.innerHTML.includes('hl-k') && a.dataset.hl === 'done', JSON.stringify(a));
let b = el('language-ts', 'let y', 2); H.highlightElement(b);
t('highlightElement leaves a hand-marked block alone', b.innerHTML === '', JSON.stringify(b));
let c = el('language-text', 'let y', 0); H.highlightElement(c);
t('highlightElement leaves language-text alone', c.innerHTML === '', JSON.stringify(c));
console.log(out.join('\n'));
JS
while IFS= read -r line; do
  case "$line" in
    "ok   "*) ok "${line#ok   }" ;;
    "FAIL "*) no "${line#FAIL }" ;;
    "     "*) printf '%s\n' "$line" ;;
    *) no "node harness output" "$line" ;;
  esac
done < "$tmp/node.out"
grep -q '^ok\|^FAIL' "$tmp/node.out" || no "the node harness ran" "$(head -5 "$tmp/node.out")"
grep -qE 'PROOF_HIGHLIGHT_VERSION[[:space:]]*=[[:space:]]*[0-9]+' "$hljs" && ok "proof-highlight.js declares PROOF_HIGHLIGHT_VERSION" \
  || no "proof-highlight.js declares PROOF_HIGHLIGHT_VERSION"
bash "$assets/kit-manifest.sh" "$kit" > "$tmp/manifest.tsv" 2> "$tmp/manifest.err"
grep -q '^proof-highlight.js	' "$tmp/manifest.tsv" && grep -q '^proof-highlight.css	' "$tmp/manifest.tsv" \
  && ok "kit-manifest publishes proof-highlight.js and .css" \
  || no "kit-manifest publishes proof-highlight.js and .css" "$(tail -3 "$tmp/manifest.err")"

printf '\n== END TO END · publish-s3.sh refuses an untagged page, highlights a tagged one ==\n'
unset FLEET_PANE PROVE_SEAT AWS_PROFILE PROVE_S3_PROFILE PROVE_DOC_ID PROVE_KIT_PIN || true
mkdir -p "$tmp/sessions"; export PROVE_SEAT_SESSIONS_DIR="$tmp/sessions"
stub="$tmp/bin"; store="$tmp/store"; mkdir -p "$stub" "$store"
cat > "$stub/aws" <<'STUB'
#!/usr/bin/env bash
store="${STUB_STORE:?}"; args=("$@"); bucket=""; key=""; body=""; out=""
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    --bucket) bucket="${args[$((i+1))]}" ;;
    --key) key="${args[$((i+1))]}" ;;
    --body) body="${args[$((i+1))]}" ;;
  esac
done
case "$1 $2" in
  "s3 cp") src="$3"; dst="${4#s3://}"; mkdir -p "$store/$(dirname "$dst")"; cp "$src" "$store/$dst" ;;
  "s3api get-object") out="${args[$((${#args[@]}-1))]}"; [ -f "$store/$bucket/$key" ] || exit 1
    cp "$store/$bucket/$key" "$out"; printf '{"ETag":"\\"x\\""}\n' ;;
  "s3api put-object") mkdir -p "$store/$bucket/$(dirname "$key")"; cp "$body" "$store/$bucket/$key" ;;
  "s3api list-objects-v2") echo None ;;
  "s3api delete-object") : ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub/aws"
envfile="$tmp/proj.env"
printf 'PROVE_S3_BUCKET=proofs\nPROVE_S3_ENDPOINT=http://127.0.0.1:9\nPROVE_S3_PUBLIC_BASE=http://127.0.0.1:9\nPROVE_S3_PREFIX=proofs\nPROVE_S3_USER=t\n' > "$envfile"
publish() { # publish <page> <tag>
  env PATH="$stub:$PATH" STUB_STORE="$store" PROVE_S3_ENV="$envfile" FLEET_PANE=test:seat \
    bash "$publisher" "$1" "$2" > "$tmp/$2.out" 2> "$tmp/$2.err"
}

bad="$(page e2ebad '<pre>untagged output</pre>')"
find "$store" -type f | sort > "$tmp/before.list"
publish "$bad" e2ebad; rc=$?
find "$store" -type f | sort > "$tmp/after.list"
[ "$rc" = 6 ] && [ ! -s "$tmp/e2ebad.out" ] && grep -q 'REFUSED' "$tmp/e2ebad.err" && cmp -s "$tmp/before.list" "$tmp/after.list" \
  && ok "an untagged page → exit 6, a REFUSED message, no URL, nothing uploaded" \
  || no "an untagged page → exit 6, a REFUSED message, no URL, nothing uploaded" "rc=$rc err='$(tail -3 "$tmp/e2ebad.err" | tr '\n' ' ')'"

good="$(page e2egood '<pre><code class="language-bash">echo hi</code></pre>')"
if publish "$good" e2egood; then
  url="$(cat "$tmp/e2egood.out")"; obj="$store/${url#http://127.0.0.1:9/}"
  [ -f "$obj" ] && grep -q '<script data-proof-highlight' "$obj" && ok "a tagged page uploads carrying the inline highlighter" \
    || no "a tagged page uploads carrying the inline highlighter" "obj=$obj"
  grep -q 'verified by content' "$tmp/e2egood.err" && ok "the read-back still verifies the injected bytes" \
    || no "the read-back still verifies the injected bytes" "$(tail -3 "$tmp/e2egood.err")"
else
  no "a tagged page publishes (exit 0)" "$(tail -5 "$tmp/e2egood.err")"
fi

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
