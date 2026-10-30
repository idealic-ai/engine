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
expect_check "the refusal names the tag migration command" 6 '<pre>x</pre>' '_fence-lang.py tag '
expect_check "an uppercase class is not a language, and the message says classes are case-sensitive" 6 \
  '<pre class="LANGUAGE-JS">x</pre>' 'case-sensitive'

printf '\n== CHECK · what counts as tagged (round 2) ==\n'
expect_check "a board payload read-out <pre data-fb-payload> is exempt" 0 '<pre class="fb-payload" data-fb-payload></pre>'
expect_check "control: data-fb-payload exempts only its own <pre>" 6 '<pre data-fb-payload></pre><pre>x</pre>' 'line 4'
expect_check "a hand-coloured block (kit .c/.k/.g spans) counts as tagged" 0 \
  '<pre><span class="c">// note</span>
<span class="k">return</span> <span class="g">1</span></pre>'
expect_check "kit .was/.now and the highlighter's own hl-* spans count too" 0 \
  '<pre><span class="was">7</span> <span class="now">8</span></pre><pre><span class="hl-k">let</span> a</pre>'
expect_check "control: spans with classes the kit does not colour are not a highlight" 6 \
  '<pre><span class="add">+x</span><span class="cmd">$ ls</span></pre>'
expect_check "a duplicated class: the first one counts, as in a browser (refused)" 6 '<pre class="x" class="language-js">a</pre>'
expect_check "a duplicated class: the first one counts, as in a browser (passes)" 0 '<pre class="language-js" class="x">a</pre>'
expect_check "a <code> nested deeper than pre > code is not the block's tag" 6 \
  '<pre><span><code class="language-js">a</code></span></pre>'
expect_check "every direct <code> must be tagged, not just one of them" 6 \
  '<pre><code>a</code><code class="language-js">b</code></pre>'
expect_check "control: two direct <code>s, both tagged" 0 \
  '<pre><code class="language-js">a</code><br><code class="language-text">b</code></pre>'

printf '\n== CHECK · the kit itself passes (the skeleton and the galleries authors copy from) ==\n'
for f in "$here/../../skills/decide/assets/skeletons/decision-board.skeleton.html" \
         "$kit/PROOF_BLOCKS.html" "$kit/CREATIVE_LAYOUTS.html"; do
  nm="$(basename "$f")"
  if python3 "$fence" check "$f" > /dev/null 2> "$tmp/kit.err"; then ok "check passes on $nm"
  else no "check passes on $nm" "$(head -4 "$tmp/kit.err" | tr '\n' ' ')"; fi
done
grep -q 'data-fb-payload' "$here/../../skills/decide/assets/skeletons/decision-board.skeleton.html" \
  && ok "control: the skeleton does hold the payload <pre> the exemption is for" \
  || no "control: the skeleton does hold the payload <pre> the exemption is for"
# Discriminating control: the same gallery with its colour spans unwrapped is refused, so the pass
# above is the hand-colour rule at work and not a gallery with no blocks in it.
python3 - "$kit/PROOF_BLOCKS.html" "$tmp/blocks-bare.html" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(re.sub(r'<span class="(?:c|k|g)">(.*?)</span>', r"\1", s))
PY
python3 "$fence" check "$tmp/blocks-bare.html" > /dev/null 2>&1; rc=$?
[ "$rc" = 6 ] && ok "control: PROOF_BLOCKS.html with its .c/.k/.g spans unwrapped is refused" \
  || no "control: PROOF_BLOCKS.html with its .c/.k/.g spans unwrapped is refused" "rc=$rc"
# KIT_DIGEST_MARKUP.md is markdown, not a page (its prose names `<pre>`): check each ```html block.
python3 - "$kit/KIT_DIGEST_MARKUP.md" "$tmp/digest" <<'PY'
import os, re, sys
md = open(sys.argv[1], encoding="utf-8").read()
os.makedirs(sys.argv[2], exist_ok=True)
for i, b in enumerate(re.findall(r"^```html\n(.*?)^```", md, re.S | re.M)):
    open(os.path.join(sys.argv[2], "b%02d.html" % i), "w", encoding="utf-8").write(b)
PY
n_md=0; bad_md=""
for f in "$tmp"/digest/b*.html; do
  [ -f "$f" ] || continue; n_md=$((n_md+1))
  python3 "$fence" check "$f" > /dev/null 2>&1 || bad_md="$bad_md $(basename "$f")"
done
[ "$n_md" -gt 0 ] && [ -z "$bad_md" ] && grep -l '<pre><span class="c">' "$tmp"/digest/b*.html > /dev/null \
  && ok "check passes on every \`\`\`html block of KIT_DIGEST_MARKUP.md ($n_md, hand-coloured <pre> among them)" \
  || no "check passes on every \`\`\`html block of KIT_DIGEST_MARKUP.md" "blocks=$n_md refused:$bad_md"

printf '\n== TAG · the migration adds language-text and nothing else ==\n'
printf '<!doctype html>\r\n<body>\r\n<pre>a</pre>\r\n<PRE CLASS="codewrap">b</PRE>\n<pre class='"'"'x y'"'"' id=p>c</pre>\n<pre class=bare>d</pre>\n<pre class>e</pre>\n<pre title="class=no" class="">f</pre>\n<pre><code>g</code></pre>\n<pre class="language-ts">h</pre>\n<pre data-fb-payload></pre>\n<pre><span class="k">i</span></pre>\n</body>\r\n' > "$tmp/tag.html"
printf '<!doctype html>\r\n<body>\r\n<pre class="language-text">a</pre>\r\n<PRE CLASS="language-text codewrap">b</PRE>\n<pre class='"'"'language-text x y'"'"' id=p>c</pre>\n<pre class="language-text bare">d</pre>\n<pre class="language-text">e</pre>\n<pre title="class=no" class="language-text">f</pre>\n<pre class="language-text"><code>g</code></pre>\n<pre class="language-ts">h</pre>\n<pre data-fb-payload></pre>\n<pre><span class="k">i</span></pre>\n</body>\r\n' > "$tmp/tag.want"
python3 "$fence" tag "$tmp/tag.html" 2> "$tmp/tag.err"; rc=$?
[ "$rc" = 0 ] && cmp -s "$tmp/tag.html" "$tmp/tag.want" \
  && ok "tag adds language-text to each untagged <pre> (first class attr, or a new one), CRLF and the rest kept" \
  || no "tag adds language-text to each untagged <pre>" "rc=$rc $(diff "$tmp/tag.want" "$tmp/tag.html" | head -6 | tr '\n' ' ')"
grep -q 'tagged 7 blocks' "$tmp/tag.err" && ok "tag reports how many blocks it tagged" || no "tag reports how many blocks it tagged" "$(cat "$tmp/tag.err")"
python3 "$fence" check "$tmp/tag.html" > /dev/null 2>&1 && ok "a tagged page then passes check" || no "a tagged page then passes check"
cp "$tmp/tag.html" "$tmp/tag.once"
python3 "$fence" tag "$tmp/tag.html" 2> "$tmp/tag2.err"
cmp -s "$tmp/tag.html" "$tmp/tag.once" && grep -q 'tagged 0 blocks' "$tmp/tag2.err" \
  && ok "tag is idempotent (second run tags 0, bytes unchanged)" || no "tag is idempotent" "$(cat "$tmp/tag2.err")"

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

p="$(page handonly '<pre><span class="k">const</span> x</pre>')"
python3 "$fence" inject "$p" > "$tmp/handonly.out" 2>/dev/null
cmp -s "$p" "$tmp/handonly.out" && ok "a page whose only blocks are hand-coloured gets no highlighter" \
  || no "a page whose only blocks are hand-coloured gets no highlighter"
printf '<html><body>\n<pre class="language-js">a</pre>\n</body>\n<script>var s="</body>";</script>\n' > "$tmp/late.html"
python3 "$fence" inject "$tmp/late.html" > "$tmp/late.out" 2>/dev/null
python3 - "$tmp/late.out" <<'PY' && ok "inject goes before the real </body>, not a \"</body>\" in a later script string" || no "inject goes before the real </body>, not a \"</body>\" in a later script string"
import sys
s = open(sys.argv[1], encoding="utf-8").read()
i = s.find("<style data-proof-highlight")
sys.exit(0 if 0 <= i < s.find("</body>\n<script>") and 'var s="</body>";</script>' in s else 1)
PY
mkdir -p "$tmp/badkit"; cp "$kit/proof-highlight.css" "$tmp/badkit/"
printf '/* <!-- */ var a = 1;\n' > "$tmp/badkit/proof-highlight.js"
p="$(page guard '<pre><code class="language-ts">a</code></pre>')"
PROVE_KIT_DIR="$tmp/badkit" python3 "$fence" inject "$p" > /dev/null 2>&1 \
  && no "the inline guard refuses a highlighter holding <!--" || ok "the inline guard refuses a highlighter holding <!--"

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
t('prototype names are not languages', ['constructor', '__proto__', 'toString', 'hasOwnProperty']
  .every(n => H.highlight('x', n) === null));
// run(): a language <pre> with a direct <code> leaves the work to the <code>.
const code = el('', 'let z', 0); code.tagName = 'CODE'; code.nextElementSibling = null;
code.parentNode = { tagName: 'PRE', className: 'language-ts' };
const pre = { tagName: 'PRE', className: 'language-ts', firstElementChild: code, children: { length: 1 },
  textContent: 'let z', innerHTML: 'UNTOUCHED', dataset: {} };
H.run({ querySelectorAll: () => [pre, code] });
t('run: pre > code is coloured through the <code>, the <pre> left alone',
  pre.innerHTML === 'UNTOUCHED' && code.innerHTML.includes('hl-k'), JSON.stringify([pre.innerHTML, code.innerHTML]));
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
