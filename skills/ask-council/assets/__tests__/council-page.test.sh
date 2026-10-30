#!/usr/bin/env bash
# IDE-338 ASKCOUNCIL: council-page.py turns a Council Report (.md) into the self-contained HTML page
# publish-s3.sh takes, so `Council:` on an ask is always a URL. Offline: no publish here.
# Checks: the page passes the kit's own fence-language gate (publish-s3.sh exit 6 otherwise),
# markdown text is escaped (a report quoting `<script>` must not run it), headings/lists/tables/code
# survive, and the title is the report's first heading.
#
# Run:  skills/ask-council/assets/__tests__/council-page.test.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$(cd "$here/.." && pwd)"
engine="$(cd "$assets/../../.." && pwd)"
page="$assets/council-page.py"
fence="$engine/skills/prove/assets/_fence-lang.py"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/r.md" <<'MD'
# Council Report — fund-roots

## Verdict
**sound_with_fixes** — the panel read `FUND` and `SECOND`; one quoted <script>alert(1)</script> stays text.

| # | Tier | Finding |
|---|------|---------|
| 1 | CONSIDER | a root again |

- Security → B
- Economist → A

```json
{ "verdict": "sound_with_fixes" }
```

```
untagged fence
```

## Ask Lines
```
core:kernel/fund ¶ASK_FUND
Panel: Security → B — small blast
```
MD

python3 "$page" "$tmp/r.md" "$tmp/r.html"; rc=$?
[ "$rc" -eq 0 ] && ok "renders (exit 0)" || no "renders (exit 0)" "exit $rc"
[ -s "$tmp/r.html" ] && ok "writes the page" || no "writes the page" "no output file"
python3 "$fence" check "$tmp/r.html" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "every <pre> names its language (publish gate passes)" || no "every <pre> names its language" "_fence-lang check exit $rc"
grep -q '<title>Council Report — fund-roots</title>' "$tmp/r.html" && ok "title is the first heading" || no "title is the first heading" "$(grep -o '<title>.*</title>' "$tmp/r.html")"
grep -q '<script>alert' "$tmp/r.html" && no "markdown text is escaped" "a raw <script> reached the page" || ok "markdown text is escaped"
grep -q '&lt;script&gt;alert(1)&lt;/script&gt;' "$tmp/r.html" && ok "the quoted tag shows as text" || no "the quoted tag shows as text" "escaped form missing"
grep -q '<h2[^>]*>Ask Lines</h2>' "$tmp/r.html" && ok "headings render" || no "headings render" "no <h2>Ask Lines"
grep -q '<li>Security → B</li>' "$tmp/r.html" && ok "list items render" || no "list items render"
grep -q '<table' "$tmp/r.html" && grep -q '<td>a root again</td>' "$tmp/r.html" && ok "tables render" || no "tables render"
grep -q 'class="language-json"' "$tmp/r.html" && ok "a tagged fence keeps its language" || no "a tagged fence keeps its language"
grep -q 'Panel: Security → B — small blast' "$tmp/r.html" && ok "the Ask Lines block survives verbatim" || no "the Ask Lines block survives verbatim"
grep -q '<strong>sound_with_fixes</strong>' "$tmp/r.html" && grep -q '<code>FUND</code>' "$tmp/r.html" && ok "inline bold and code render" || no "inline bold and code render"
grep -qi '<script' "$tmp/r.html" && no "the page loads no script" "a <script tag is present" || ok "the page loads no script"
python3 "$page" "$tmp/missing.md" "$tmp/x.html" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "a missing report is refused (exit $rc)" || no "a missing report is refused" "exit 0"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
