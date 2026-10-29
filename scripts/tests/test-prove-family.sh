#!/usr/bin/env bash
# Are /prove-plan and /prove-explanation still thin, well-formed siblings of /prove, and do their
# gates still catch what they exist to catch?
#
# Both skills are deliberately thin: their prover brief, provenance rules, templates and S3 publish
# are /prove's, cited by path, by section heading and by brief item number rather than copied. A
# citation that stops resolving (an asset renamed under prove/assets, a /prove section retitled, a
# brief item renumbered) leaves a skill that tells its subagent to read something that is not
# there, and nothing else would notice. So this file:
#   - parses the frontmatter and manifest the way the skill loader and `engine doctor` read them;
#   - resolves every cited asset, section, invariant, VOICE.md section and /prove brief item, and
#     checks that the brief items each skill includes or replaces add up to all of /prove's;
#   - checks each gate rule by its label;
#   - runs each skill's own page scanner on small pages built here — a clean plan page must pass,
#     and a status page that says "landed" must fail — so the honesty gate is tested as behaviour,
#     not only as wording;
#   - checks the boundary sentence between /prove-explanation and /prove-explore, in both skills.
#
# SKILLS_ROOT and DIRECTIVES_ROOT can be pointed at a copy, which is how the planted-defect runs
# prove this file can go red. PROVEFAM_STRICT=0 turns the /prove-explore boundary check back into
# a non-fatal OWED line; the default is strict.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="${SKILLS_ROOT:-$here/../../skills}"
DIRECTIVES_ROOT="${DIRECTIVES_ROOT:-$here/../../.directives}"
STRICT="${PROVEFAM_STRICT:-1}"
prove_md="$SKILLS_ROOT/prove/SKILL.md"
explore_md="$SKILLS_ROOT/prove-explore/SKILL.md"
voice_md="$DIRECTIVES_ROOT/VOICE.md"

pass=0; fail=0; owed=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no()   { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
owe()  { owed=$((owed+1)); printf '  OWED %s\n     %s\n' "$1" "${2:-}"; }

for tool in ruby jq python3 tsort; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'test-prove-family: required tool %s is not on PATH; nothing was checked\n' "$tool" >&2
    exit 2
  fi
done

tmp="$(mktemp -d -t provefam)"
trap 'rm -rf "$tmp"' EXIT

# Frontmatter as JSON, parsed by a real YAML parser (ruby's bundled Psych), or empty on a parse error.
fm_json() {
  ruby -ryaml -rjson -e '
    parts = File.read(ARGV[0]).split(/^---[ \t]*$/, 3)
    abort "no frontmatter" unless parts.length == 3 && parts[0].strip.empty?
    y = YAML.safe_load(parts[1])
    abort "frontmatter is not a mapping" unless y.is_a?(Hash)
    puts JSON.generate(y)' "$1" 2>/dev/null
}
fm_raw() { awk 'NR==1 && /^---/ {f=1; next} f && /^---/ {exit} f {print}' "$1"; }

# A path written as ~/.claude/skills/X, ~/.claude/engine/skills/X or ../X resolves under SKILLS_ROOT.
resolve_skill_path() {
  local p="$1"
  p="${p#\~/.claude/engine/skills/}"; p="${p#\~/.claude/skills/}"; p="${p#../}"
  printf '%s/%s' "$SKILLS_ROOT" "$p"
}
# Sections cited as `<file>` § "Heading" or /<skill>` § "Heading"; prints the headings.
cited_sections() { # cited_sections <md> <regex for the citing prefix>
  grep -oE "$2"' § "[^"]+"' "$1" | sed -E 's/.*§ "([^"]+)"/\1/' | sort -u
}
# The numbers on a "Brief items … :" line, plus the words opening / Substituting.
brief_line() { grep -m1 -F "$2" "$1" | sed 's/.*: *//; s/\.$//' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$'; }

printf '\n== /prove and its siblings are there to be cited ==\n'
for f in "$prove_md" "$explore_md" "$voice_md"; do
  [ -f "$f" ] && ok "exists: ${f#$SKILLS_ROOT/}" || no "exists: $f" "missing"
done
prove_items="$(grep -oE '^> \*\*[0-9]+\. ' "$prove_md" | grep -oE '[0-9]+' | sort -n | tr '\n' ' ')"
[ -n "$prove_items" ] && ok "/prove brief items found: $prove_items" || no "/prove brief items found" "no '> **N. ' items"

for skill in prove-plan prove-explanation; do
  dir="$SKILLS_ROOT/$skill"; md="$dir/SKILL.md"; mf="$dir/manifest.json"
  printf '\n== %s ==\n' "$skill"

  if [ -f "$md" ]; then ok "$skill: SKILL.md exists"; else no "$skill: SKILL.md exists" "$md"; continue; fi

  # --- Frontmatter parses, and its fields are the ones the loader and doctor read ---
  fm="$(fm_json "$md")"
  if [ -n "$fm" ]; then ok "$skill: frontmatter parses as a YAML mapping"
  else no "$skill: frontmatter parses as a YAML mapping" "ruby YAML.safe_load refused it"; continue; fi
  for k in name description version tier args; do
    v="$(jq -r --arg k "$k" '.[$k] // empty | tostring' <<<"$fm")"
    if [ -n "$v" ]; then ok "$skill: frontmatter has $k"; else no "$skill: frontmatter has $k" "missing or empty"; fi
  done
  fm_name="$(jq -r '.name // empty' <<<"$fm")"
  if [ "$fm_name" = "$skill" ]; then ok "$skill: name matches its directory"
  else no "$skill: name matches its directory" "frontmatter name='$fm_name'"; fi
  case "$(jq -r '.tier // empty' <<<"$fm")" in
    protocol|lightweight|utility|suggest) ok "$skill: tier is one doctor accepts" ;;
    *) no "$skill: tier is one doctor accepts" "tier='$(jq -r '.tier' <<<"$fm")'" ;;
  esac
  fm_desc="$(jq -r '.description // empty' <<<"$fm")"

  # --- Any top-level scalar holding a colon is quoted (doctor's awk reader and YAML both need it) ---
  bad_lines="$(fm_raw "$md" | awk '
    /^[A-Za-z_][A-Za-z0-9_-]*:[ \t]*/ {
      v=$0; sub(/^[A-Za-z_][A-Za-z0-9_-]*:[ \t]*/, "", v)
      if (v ~ /:/ && v !~ /^["\x27]/) print $0
    }')"
  if [ -z "$bad_lines" ]; then ok "$skill: every frontmatter value containing a colon is quoted"
  else no "$skill: every frontmatter value containing a colon is quoted" "$(printf '%s' "$bad_lines" | cut -c1-120)"; fi

  # --- Manifest matches the siblings' shape and the frontmatter ---
  if [ -f "$mf" ] && jq empty "$mf" 2>/dev/null; then
    ok "$skill: manifest.json parses"
    [ "$(jq -r '.name' "$mf")" = "$skill" ] && ok "$skill: manifest name matches" \
      || no "$skill: manifest name matches" "manifest name='$(jq -r '.name' "$mf")'"
    [ "$(jq -r '.description' "$mf")" = "$fm_desc" ] && ok "$skill: manifest description equals the frontmatter's" \
      || no "$skill: manifest description equals the frontmatter's" "the two have drifted"
    [ "$(jq -r '.tier' "$mf")" = "$(jq -r '.tier' <<<"$fm")" ] && ok "$skill: manifest tier matches" \
      || no "$skill: manifest tier matches" "manifest tier='$(jq -r '.tier' "$mf")'"
    [ "$(jq -r '.sibling // empty' "$mf")" = "prove" ] && ok "$skill: manifest names /prove as its sibling" \
      || no "$skill: manifest names /prove as its sibling" "sibling='$(jq -r '.sibling // empty' "$mf")'"
    n_shared=0
    while IFS= read -r p; do
      [ -n "$p" ] || continue; n_shared=$((n_shared+1))
      t="$(resolve_skill_path "$p")"
      [ -f "$t" ] && ok "$skill: manifest asset resolves: $p" || no "$skill: manifest asset resolves: $p" "$t"
    done < <(jq -r '(.sharedAssets // {}), (.localAssets // {}) | .[]' "$mf")
    [ "$n_shared" -ge 4 ] && ok "$skill: manifest declares shared + local assets ($n_shared)" \
      || no "$skill: manifest declares shared + local assets" "only $n_shared"
  else
    no "$skill: manifest.json parses" "$mf"
  fi

  # --- Every cited asset path resolves (/prove's and the skill's own) ---
  n_assets=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue; n_assets=$((n_assets+1))
    t="$(resolve_skill_path "$p")"
    [ -f "$t" ] && ok "$skill: cited asset resolves: $p" || no "$skill: cited asset resolves: $p" "$t"
  done < <(grep -oE '(~/\.claude/(engine/)?skills/|\.\./)prove(-plan|-explanation)?/assets/[A-Za-z0-9_.-]+' "$md" | sort -u)
  grep -qE 'prove/assets/publish-s3\.sh' "$md" && ok "$skill: cites /prove's publish-s3.sh" \
    || no "$skill: cites /prove's publish-s3.sh" "no publish citation"
  [ "$n_assets" -ge 4 ] && ok "$skill: cites assets ($n_assets)" \
    || no "$skill: cites assets" "only $n_assets cited; expected the publisher, both templates and the scanner"

  # --- Every cited /prove and /prove-explore section heading exists ---
  n_sec=0
  while IFS= read -r h; do
    [ -n "$h" ] || continue; n_sec=$((n_sec+1))
    grep -qxF "## $h" "$prove_md" && ok "$skill: cited /prove section exists: $h" \
      || no "$skill: cited /prove section exists: $h" "no '## $h' heading in prove/SKILL.md"
  done < <(cited_sections "$md" '(prove/SKILL\.md`|/prove`)')
  [ "$n_sec" -ge 4 ] && ok "$skill: cites /prove sections ($n_sec)" || no "$skill: cites /prove sections" "only $n_sec cited"
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    grep -qxF "## $h" "$explore_md" && ok "$skill: cited /prove-explore section exists: $h" \
      || no "$skill: cited /prove-explore section exists: $h" "no '## $h' heading in prove-explore/SKILL.md"
  done < <(cited_sections "$md" 'prove-explore/SKILL\.md`')
  if grep -qF 'C9' "$md"; then
    grep -qE '^\*\*C9 — ' "$explore_md" && ok "$skill: cited /prove-explore check C9 exists" \
      || no "$skill: cited /prove-explore check C9 exists" "no '**C9 — ' in prove-explore/SKILL.md"
  else
    no "$skill: page mechanics cite /prove-explore C9" "no C9 citation"
  fi
  while IFS= read -r inv; do
    [ -n "$inv" ] || continue
    grep -qF "$inv" "$prove_md" && ok "$skill: cited invariant exists: $inv" \
      || no "$skill: cited invariant exists: $inv" "not in prove/SKILL.md"
  done < <(grep -oE '¶INV_PROVE_[A-Z_]+' "$md" | sort -u)

  # --- The brief: every /prove item is either included or replaced, and each cited item exists ---
  inc="$(brief_line "$md" 'Brief items included from /prove:')"
  rep="$(brief_line "$md" 'Brief items replaced here:')"
  if [ -z "$inc" ] || [ -z "$rep" ]; then
    no "$skill: states which /prove brief items it includes and replaces" "missing a 'Brief items …:' line"
  else
    ok "$skill: states which /prove brief items it includes and replaces"
    for n in $(printf '%s\n%s\n' "$inc" "$rep" | grep -E '^[0-9]+$'); do
      grep -qE "^> \*\*$n\. " "$prove_md" && ok "$skill: cited brief item $n exists in /prove" \
        || no "$skill: cited brief item $n exists in /prove" "no '> **$n. ' in prove/SKILL.md"
    done
    covered="$(printf '%s\n%s\n' "$inc" "$rep" | grep -E '^[0-9]+$' | sort -n | tr '\n' ' ')"
    [ "$covered" = "$prove_items" ] && ok "$skill: brief items included + replaced = all of /prove's ($covered)" \
      || no "$skill: brief items included + replaced = all of /prove's" "covered '$covered' vs /prove '$prove_items'"
    dup="$(printf '%s\n%s\n' "$inc" "$rep" | grep -E '^[0-9]+$' | sort | uniq -d | tr '\n' ' ')"
    [ -z "$dup" ] && ok "$skill: no brief item is both included and replaced" || no "$skill: no brief item is both included and replaced" "$dup"
    grep -qx 'opening' <<<"$inc" && grep -qF 'You are an **evidence engineer**' "$prove_md" \
      && ok "$skill: includes /prove's opening paragraph, which exists" \
      || no "$skill: includes /prove's opening paragraph, which exists" "'opening' not included, or /prove's opening moved"
    n_subst="$(grep -cE '^\*\*Substituting ' "$prove_md")"
    grep -qx 'Substituting' <<<"$inc" && [ "$n_subst" -eq 2 ] \
      && ok "$skill: includes /prove's two Substituting paragraphs, which exist" \
      || no "$skill: includes /prove's two Substituting paragraphs, which exist" "included? found $n_subst in /prove"
  fi
  grep -qF '"Write from the reader'"'"'s side"' "$md" && grep -qF "**Write from the reader's side:**" "$prove_md" \
    && ok "$skill: names the item-5 bullet it overrides, which exists in /prove" \
    || no "$skill: names the item-5 bullet it overrides, which exists in /prove" "override not named, or bullet gone from /prove"
  grep -qF 'read `<pagePath>`' "$md" && ok "$skill: says <proofPath> reads <pagePath>" \
    || no "$skill: says <proofPath> reads <pagePath>" "no mapping sentence"

  # --- Paths stated once (a second statement can drift from the first) ---
  case "$skill" in prove-plan) pg='_PLAN.html'; ds='_PROVE_PLAN.md' ;; *) pg='_EXPLAIN.html'; ds='_PROVE_EXPLANATION.md' ;; esac
  for s in "$pg" "$ds"; do
    c="$(grep -oF "$s" "$md" | wc -l | tr -d ' ')"
    [ "$c" -eq 1 ] && ok "$skill: $s is stated exactly once" || no "$skill: $s is stated exactly once" "stated $c times"
  done

  # --- Cites rather than copies: /prove's publish prose must not be pasted in ---
  copied=""
  for s in 'Read the PORT, never the bucket' 'mints an **unguessable** key' 'Every published page carries a seat strip'; do
    grep -qF "$s" "$md" && copied="$copied [$s]"
  done
  [ -z "$copied" ] && ok "$skill: does not copy /prove's publish prose" \
    || no "$skill: does not copy /prove's publish prose" "found:$copied"

  # --- The skill states its gate, every rule by its label ---
  grep -qE '^## 3\. The (Route|Teaching) Gate$' "$md" && ok "$skill: has its gate section" \
    || no "$skill: has its gate section" "no '## 3. The … Gate' heading"
  grep -qF '§ "3. Presentation-Integrity Pass (the gate)" first' "$md" && ok "$skill: gate runs /prove's integrity pass first" \
    || no "$skill: gate runs /prove's integrity pass first" "missing the citation"
done

printf '\n== every gate rule, by its label ==\n'
plan="$SKILLS_ROOT/prove-plan/SKILL.md"; expl="$SKILLS_ROOT/prove-explanation/SKILL.md"
need() { # need <file> <label> <fixed string>
  if [ -f "$1" ] && grep -qF "$3" "$1"; then ok "$2"; else no "$2" "missing: $3"; fi
}
while IFS='|' read -r f label; do
  [ -n "$f" ] || continue
  case "$f" in plan) file="$plan" ;; *) file="$expl" ;; esac
  need "$file" "$f: ${label%% —*}" "$label"
done <<'EOF'
plan|**P1 — Every step names its check.**
plan|**P2 — Nothing is presented as done.**
plan|**P3 — The graph is the ledger.**
plan|**P4 — Acceptance is an end state.**
plan|**P5 — Owners are real.**
plan|**P6 — Scope, risks and out-of-scope are where the reader meets them.**
plan|**P7 — Provenance is visible.**
plan|**P8 — Page mechanics.**
plan|**P9 — The page alone answers the job.**
expl|**E1 — One mechanism.**
expl|**E2 — The order holds.**
expl|**E3 — The first part is in everyday words.**
expl|**E4 — Every value in the worked example is real.**
expl|**E5 — Every claim carries evidence or honest provenance, pinned.**
expl|**E6 — Edge cases are grounded.**
expl|**E7 — "What it is not" earns its place.**
expl|**E8 — Page mechanics.**
expl|**E9 — The page alone answers the job.**
EOF
need "$plan" "plan: no end-state on a plan page" 'A plan page has **no end-state**'
need "$plan" "plan: derived-here is its own provenance class" '`derived-here` means you proposed it'
need "$expl" "expl: derived-here is its own provenance class" '`derived-here` covers what the teacher wrote'
need "$plan" "plan: dossier section map" '**Dossier section map.**'
need "$expl" "expl: dossier section map" '**Dossier section map.**'
need "$expl" "expl: teacher-written fixtures are addressed" 'data-fixture="teacher-written"'
if [ -f "$expl" ] && grep -qE '~/\.claude/(engine/)?\.directives/VOICE\.md' "$expl"; then ok "expl: cites VOICE.md"
else no "expl: cites VOICE.md" "no ~/.claude/[engine/].directives/VOICE.md path"; fi
if [ -f "$expl" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    r="$DIRECTIVES_ROOT/${p##*/.directives/}"
    [ -f "$r" ] && ok "expl: cited VOICE path resolves: $p" || no "expl: cited VOICE path resolves: $p" "$r"
  done < <(grep -oE '~/\.claude/(engine/)?\.directives/VOICE\.md' "$expl" | sort -u)
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    grep -qxF "## $h" "$voice_md" && ok "expl: cited VOICE.md section exists: $h" \
      || no "expl: cited VOICE.md section exists: $h" "no '## $h' in $voice_md"
  done < <(cited_sections "$expl" 'VOICE\.md`?')
fi

printf '\n== the brief and its scanner name the same marks ==\n'
# The brief's item 4 tells the subagent which marks to emit; the scanner reads marks. If the two
# lists differ, every real page fails (or a check silently reads nothing), so they must be equal.
item4_marks() { # item4_marks <md> — data-* tokens (and dfn) in the brief's item-4 blockquote
  awk '/^> \*\*4\. /{f=1} f && !/^>/{exit} f{print}' "$1" > "$tmp/item4.txt"
  { grep -oE 'data-[a-z]+(-[a-z]+)*' "$tmp/item4.txt"; grep -q '<dfn>' "$tmp/item4.txt" && echo dfn; } | sort -u
}
plan_scan="$SKILLS_ROOT/prove-plan/assets/plan-page-scan.py"
expl_scan="$SKILLS_ROOT/prove-explanation/assets/explain-page-scan.py"
for pair in "prove-plan:$plan_scan" "prove-explanation:$expl_scan"; do
  s="${pair%%:*}"; sc="${pair#*:}"; md="$SKILLS_ROOT/$s/SKILL.md"
  if [ -f "$md" ] && [ -f "$sc" ]; then
    brief="$(item4_marks "$md" | tr '\n' ' ')"
    scanner="$(python3 -I "$sc" --print-marks 2>/dev/null | sort -u | tr '\n' ' ')"
    [ -n "$brief" ] && [ "$brief" = "$scanner" ] && ok "$s: brief item 4 marks = scanner marks ($scanner)" \
      || no "$s: brief item 4 marks = scanner marks" "brief: '$brief' · scanner: '$scanner'"
    if [ "$s" = prove-explanation ]; then
      ml="$(grep -m1 -F '**Marks the gate scans for:**' "$md" | grep -oE 'data-[a-z]+(-[a-z]+)*|`dfn`' | tr -d '`' | sort -u | tr '\n' ' ')"
      [ "$ml" = "$scanner" ] && ok "$s: the brief's mark list = scanner marks" || no "$s: the brief's mark list = scanner marks" "list: '$ml'"
      grep -E '^> 2\. \*\*`data-part="how"`' "$md" | grep -q 'data-pin' && ok "$s: the 'how' part tells the teacher to pin with data-pin" \
        || no "$s: the 'how' part tells the teacher to pin with data-pin" "part 2 of item 4 no longer names data-pin"
    fi
  else
    no "$s: brief item 4 marks = scanner marks" "missing $md or $sc"
  fi
done
for s in prove-plan prove-explanation; do
  md="$SKILLS_ROOT/$s/SKILL.md"
  line="$(grep -E '^\*\*[PE]8 — Page mechanics\.\*\*' "$md" 2>/dev/null)"
  case "$line" in
    *390px*|*"<script>"*|*mermaid*) no "$s: P8/E8 cites C9 without restating it" "restates C9's contents" ;;
    *C9*) ok "$s: P8/E8 cites C9 without restating it" ;;
    *) no "$s: P8/E8 cites C9 without restating it" "no C9 citation on the line" ;;
  esac
  need "$md" "$s: return manifest counts derived-here" 'gain a third, `N derived-here`'
done
need "$expl" "expl: E4 says it is by eye only" 'This check is by eye only; no scanner looks for invented values.'

printf '\n== P2 behaviour · the plan scanner on pages built here ==\n'
scan() { python3 -I "$@" >"$tmp/scan.out" 2>&1; }
expect() { # expect <green|red> <label> <scanner> <args…>
  local want="$1" label="$2"; shift 2
  if [ ! -f "$1" ]; then no "$label" "scanner missing: $1"; return; fi
  scan "$@"; local rc=$?
  if { [ "$want" = green ] && [ $rc -eq 0 ]; } || { [ "$want" = red ] && [ $rc -eq 1 ]; }; then ok "$label"
  else no "$label" "want $want, exit $rc: $(head -3 "$tmp/scan.out" | tr '\n' ' ' | cut -c1-220)"; fi
}

if [ -f "$plan_scan" ]; then
  words="$(python3 -I "$plan_scan" --print-words | sort)"
  skill_words="$(grep -m1 '^Done-words: ' "$plan" | sed 's/^Done-words: //; s/\.$//' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sort)"
  [ -n "$skill_words" ] && [ "$words" = "$skill_words" ] && ok "P2's Done-words line equals the scanner's list" \
    || no "P2's Done-words line equals the scanner's list" "skill and scanner disagree"
  missing=""
  for w in done complete merged shipped landed committed fixed built published resolved closed green released succeeded deployed verified; do
    grep -qx "$w" <<<"$words" || missing="$missing $w"
  done
  [ -z "$missing" ] && ok "the scanner searches every required done-word" || no "the scanner searches every required done-word" "missing:$missing"
fi

page() { # page <file> <body> [head-title] — wraps a body in a minimal document
  printf '<!doctype html><html><head><title>%s</title><style>.done{}</style></head><body>%s</body></html>\n' "${3:-Route}" "$2" > "$1"
}
ROUTE='<h1 data-route>From one retry to three, ending with the fix merged and released.</h1>'
SCOPE='<p data-scope>Covers the retry route. Out of scope: billing. Every step is planned and none is done. As of plan.md @ 4f1c2a9, 02:40.</p>'
LEGEND='<p data-legend>Colour is the owner: green is manager:domain, blue is director.</p>'
SVG='<svg><g data-step="S1"><rect/><text>S1</text></g><g data-step="S2"><text>S2</text></g><g data-step="S3"><text>S3</text></g><g data-external="X1"><text>SDK release</text></g><path data-edge="S1->S2"/><path data-edge="S2->S3"/><path data-edge="X1->S3"/></svg>'
START='<ul data-starting-point><li>Already done before this route: schema built at 01:06 (per plan.md, ticked).</li></ul>'
card() { printf '<section data-card="%s"><h3>%s</h3><p data-acceptance>Passes when: %s</p><p data-check>Checked by: %s</p></section>' "$1" "$1" "$2" "$3"; }
CARDS="$(card S1 'the branch is merged' 'CI reports green on the PR')$(card S2 'the config is read' 'npm test exits 0')$(card S3 'staging survives 3 failures' 'the upload test passed 3/3')"
RISK='<p>Risk to S2: the PR may be closed by the owner, and the built-in retry stays.</p>'
GOOD="$ROUTE$SCOPE$LEGEND$SVG$START$CARDS$RISK<pre>git log: landed fix</pre>"

page "$tmp/plan-good.html" "$GOOD" "Shipped and done: the head title is not page text"
expect green "P2: a clean plan page passes (route sentence, legend, built-in, 'may be closed', head <title>, required regions)" "$plan_scan" done "$tmp/plan-good.html"
expect green "P3: a clean plan page's graph passes" "$plan_scan" graph "$tmp/plan-good.html"
expect green "P6: a clean plan page's scope line passes" "$plan_scan" scope "$tmp/plan-good.html"
page "$tmp/plan-hyphen.html" "${GOOD/Out of scope:/Out-of-scope:}"
expect green "P6: 'Out-of-scope' with hyphens passes" "$plan_scan" scope "$tmp/plan-hyphen.html"

page "$tmp/plan-landed.html" "$ROUTE$SCOPE$SVG$CARDS<p>Status: S1 landed, S2 fixed and committed.</p>"
expect red "P2: a status page worded with 'landed' fails" "$plan_scan" done "$tmp/plan-landed.html"
if grep -q "done-word 'landed'" "$tmp/scan.out"; then ok "P2: the failure names 'landed'"; else no "P2: the failure names 'landed'" "$(head -2 "$tmp/scan.out")"; fi
for w in succeeded deployed verified; do
  page "$tmp/plan-$w.html" "$SCOPE$SVG$CARDS<p>S1 $w at 02:10.</p>"
  expect red "P2: '$w' outside the regions fails" "$plan_scan" done "$tmp/plan-$w.html"
done
page "$tmp/plan-cardtext.html" "$SCOPE$SVG$(card S1 a b | sed 's|<h3>S1</h3>|<h3>S1 (shipped)</h3>|')$(card S2 a b)$(card S3 a b)"
expect red "P2 (D4): a done-word in a card's own text, outside its cells, fails" "$plan_scan" done "$tmp/plan-cardtext.html"
page "$tmp/plan-tick.html" "$SCOPE$SVG$(card S1 '✓ merged' 'CI')$(card S2 'x' 'y')$(card S3 'x' 'y')"
expect red "P2: a tick inside an acceptance cell still fails" "$plan_scan" done "$tmp/plan-tick.html"
page "$tmp/plan-tickroute.html" "<h1 data-route>Route ✅</h1>$SCOPE$SVG$CARDS"
expect red "P2: a tick inside the route sentence still fails" "$plan_scan" done "$tmp/plan-tickroute.html"
page "$tmp/plan-bigx.html" "$SCOPE$SVG$CARDS<p>[X] S1</p>"
expect red "P2: an uppercase [X] fails" "$plan_scan" done "$tmp/plan-bigx.html"
page "$tmp/plan-prefix.html" "$SCOPE$SVG<section data-card=\"S1\"><p data-acceptance>Done: shipped</p></section>"
expect red "P2: an acceptance cell without 'Passes when:' fails" "$plan_scan" done "$tmp/plan-prefix.html"
page "$tmp/plan-vague.html" "$SCOPE$SVG$(card S1 a 'verify it')$(card S2 a b)$(card S3 a b)"
expect red "P1: a check cell that only says 'verify it' fails" "$plan_scan" done "$tmp/plan-vague.html"
page "$tmp/plan-strike.html" "$SCOPE$SVG$CARDS<p><s>S1</s></p><input type=\"checkbox\" checked>"
expect red "P2: a strike-through or checked box fails" "$plan_scan" done "$tmp/plan-strike.html"
page "$tmp/plan-svgtitle.html" "$SCOPE<svg><g data-step=\"S1\"><title>S1 done</title></g></svg>$(card S1 a b)"
expect red "P2: an SVG <title> saying 'done' fails" "$plan_scan" done "$tmp/plan-svgtitle.html"
page "$tmp/plan-aria.html" "$SCOPE$SVG$CARDS<span aria-label=\"S1 (merged)\">S1</span>"
expect red "P2: status in an aria-label fails" "$plan_scan" done "$tmp/plan-aria.html"
page "$tmp/plan-progress.html" "$SCOPE$SVG$CARDS<progress value=\"100\" max=\"100\"></progress>"
expect red "P2: a <progress> element fails" "$plan_scan" done "$tmp/plan-progress.html"
page "$tmp/plan-twoscope.html" "$SCOPE<p data-scope>As of x @ y. Out of scope: none. S1 landed, S2 merged, shipped.</p>$SVG$CARDS"
expect red "P2: a second data-scope fails" "$plan_scan" done "$tmp/plan-twoscope.html"
page "$tmp/plan-noscope.html" "$SVG$CARDS"
expect red "P2: a page with no data-scope fails" "$plan_scan" done "$tmp/plan-noscope.html"
page "$tmp/plan-twostart.html" "$SCOPE$SVG$START$START$CARDS"
expect red "P2: a second data-starting-point fails" "$plan_scan" done "$tmp/plan-twostart.html"
page "$tmp/plan-wrapcards.html" "$SCOPE$SVG<div data-starting-point>$CARDS</div>"
expect red "P2: a data-starting-point wrapped around the cards fails" "$plan_scan" done "$tmp/plan-wrapcards.html"
page "$tmp/plan-cardinregion.html" "$SCOPE$SVG<div data-starting-point><section data-card=\"S1\"><h3>S1 shipped</h3></section></div>$(card S2 a b)$(card S3 a b)"
expect red "P2: a card (even one with no cells) inside an excluded region fails" "$plan_scan" done "$tmp/plan-cardinregion.html"
grep -q "a card may not sit in an excluded region" "$tmp/scan.out" && ok "P2: the failure names the card-in-region rule" \
  || no "P2: the failure names the card-in-region rule" "$(head -2 "$tmp/scan.out")"
page "$tmp/plan-loosecell.html" "$SCOPE$SVG$CARDS<p data-acceptance>Passes when: S1 landed</p>"
expect red "P2: an acceptance cell outside a card fails" "$plan_scan" done "$tmp/plan-loosecell.html"
page "$tmp/plan-nested.html" "<p data-scope>As of a @ b; out of scope: c. <span data-legend>green</span></p>$SVG$CARDS"
expect red "P2: a region nested inside another fails" "$plan_scan" done "$tmp/plan-nested.html"
page "$tmp/plan-unclosed.html" "<div><p data-scope>As of a @ b; out of scope: c.</div>$SVG$CARDS<p>S1 landed, S2 merged.</p>"
expect red "P2: an unclosed region fails instead of swallowing the page" "$plan_scan" done "$tmp/plan-unclosed.html"
printf '<!doctype html><html><body>%s%s<p data-scope>As of a @ b; out of scope: c. S1 landed\n' "$SVG" "$CARDS" > "$tmp/plan-unclosed-eof.html"   # no closing tags at all: the true end-of-document case
expect red "P2: a region still open at the end of the document fails" "$plan_scan" done "$tmp/plan-unclosed-eof.html"

page "$tmp/plan-cycle.html" "$SCOPE<svg><g data-step=\"S1\"></g><g data-step=\"S2\"></g><path data-edge=\"S1->S2\"/><path data-edge=\"S2->S1\"/></svg>$(card S1 a b)$(card S2 a b)"
expect red "P3: a cycle fails (tsort)" "$plan_scan" graph "$tmp/plan-cycle.html"
page "$tmp/plan-order.html" "$SCOPE$SVG$(card S2 a b)$(card S1 a b)$(card S3 a b)"
expect red "P3: cards out of topological order fail" "$plan_scan" graph "$tmp/plan-order.html"
page "$tmp/plan-orphan.html" "$SCOPE$SVG$(card S1 a b)$(card S2 a b)$(card S3 a b)$(card S4 a b)"
expect red "P3: a card with no node fails" "$plan_scan" graph "$tmp/plan-orphan.html"
page "$tmp/plan-dangle.html" "$SCOPE<svg><g data-step=\"S1\"></g><path data-edge=\"S0->S1\"/></svg>$(card S1 a b)"
expect red "P3: an edge to an unknown node fails" "$plan_scan" graph "$tmp/plan-dangle.html"
page "$tmp/plan-dupedge.html" "$SCOPE${SVG/<\/svg>/<path data-edge=\"S1->S2\"/></svg>}$CARDS"
expect red "P3: a duplicate edge fails" "$plan_scan" graph "$tmp/plan-dupedge.html"
page "$tmp/plan-idleext.html" "$SCOPE${SVG/<\/svg>/<g data-external=\"X2\"></g></svg>}$CARDS"
expect red "P3: an external that feeds no step fails" "$plan_scan" graph "$tmp/plan-idleext.html"

page "$tmp/plan-noasof.html" "<p data-scope>Covers the route; out of scope: billing.</p>$SVG$CARDS"
expect red "P6: a scope line with no as-of stamp fails" "$plan_scan" scope "$tmp/plan-noasof.html"
page "$tmp/plan-asofnow.html" "<p data-scope>As of now; out of scope: billing.</p>$SVG$CARDS"
expect red "P6: 'as of' with no '@ <version>' fails" "$plan_scan" scope "$tmp/plan-asofnow.html"
page "$tmp/plan-nooos.html" "<p data-scope>Covers the route. As of plan.md @ 4f1c2a9.</p>$SVG$CARDS"
expect red "P6 (D3): a scope line that does not say what is out of scope fails" "$plan_scan" scope "$tmp/plan-nooos.html"
page "$tmp/plan-late.html" "$SVG$SCOPE$CARDS"
expect red "P6: a scope line below the flowgraph fails" "$plan_scan" scope "$tmp/plan-late.html"

printf '\n== E2/E3/E5 behaviour · the explanation scanner on pages built here ==\n'
repo="$tmp/repo"; mkdir -p "$repo/ledger"
printf 'export function placeHold(job) {}\n' > "$repo/ledger/hold.ts"
printf 'test("hold", () => placeHold({amount: 120}))\n' > "$repo/ledger/hold.test.ts"
git -C "$repo" init -q && git -C "$repo" add -A \
  && git -C "$repo" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -qm fixture --no-verify
sha="$(git -C "$repo" rev-parse --short=10 HEAD 2>/dev/null)"
case "$sha" in *[a-f]*) : ;; *) git -C "$repo" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -qm again --allow-empty --no-verify; sha="$(git -C "$repo" rev-parse --short=10 HEAD)";; esac
fsha="sha256:$(shasum -a 256 "$repo/ledger/hold.test.ts" | cut -c1-16)"
osha="sha256:$(shasum -a 256 "$repo/ledger/hold.ts" | cut -c1-16)"
[ -n "$sha" ] && ok "a scratch repo for pin ownership exists (HEAD $sha)" || no "a scratch repo for pin ownership exists" "git init/commit failed"

ESCOPE='<p data-scope>How a hold is placed, for a newcomer; not covered: refunds.</p>'
IDEA='<section data-part="idea"><p>When you post work, its money is set aside at once, a set-aside a newcomer reads as plain English. That amount is a <dfn>hold</dfn>, money no one else can spend. A quick check guards against claims for money twice, on an iPhone or macOS alike. <dfn>placeHold, the call that sets it aside</dfn> does it.</p></section>'
HOW="<section data-part=\"how\"><pre data-source=\"ledger/hold.ts:1\" data-pin=\"$sha\">placeHold(job) // may-rule</pre><p data-pin=\"$sha\">See <code>ledger/hold.ts:1</code>.</p></section>"
EX="<section data-part=\"example\"><div data-fixture=\"source\" data-source=\"ledger/hold.test.ts:1\" data-pin=\"$fsha\">job 120.00</div></section>"
EDGES='<section data-part="edges"><p>Zero amounts are refused.</p></section>'
NOT='<section data-part="not"><p>It is not a charge.</p></section>'
R=(--root "$repo")
page "$tmp/ex-good.html" "$ESCOPE$IDEA$HOW$EX$EDGES$NOT"
expect green "E2/E3/E5: a clean page passes (everyday check/guard/claim, iPhone/macOS, set-aside, a <dfn> holding its definition)" "$expl_scan" all "$tmp/ex-good.html" "${R[@]}"
python3 -I "$expl_scan" pins "$tmp/ex-good.html" >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && ok "E5: pins without --root is a usage error, not a pass" || no "E5: pins without --root is a usage error, not a pass" "exit $rc"
page "$tmp/ex-order.html" "$ESCOPE$HOW$IDEA$EX$EDGES$NOT"
expect red "E2: parts out of order fail" "$expl_scan" order "$tmp/ex-order.html"
page "$tmp/ex-noscope.html" "$IDEA$HOW$EX$EDGES$NOT"
expect red "E2: a page that does not open with its scope line fails" "$expl_scan" order "$tmp/ex-noscope.html"
page "$tmp/ex-unclosed.html" "$ESCOPE<section data-part=\"idea\"><p>x</p>$HOW$EX$EDGES$NOT"
expect red "E2: an unclosed part fails" "$expl_scan" order "$tmp/ex-unclosed.html"
ideap() { printf '<section data-part="idea"><p>%s</p></section>' "$1"; }
for case_ in 'code|The <code>placeHold</code> call sets money aside.' \
             'flag|Pass --chain-file to walk the chain.' \
             'short|Run it with -v to see more.' \
             'kebab|The may-rule decides it.' \
             'env|It reads FLEET_PARENT first.' \
             'work|Each lane passes a gate before money moves.'; do
  n="${case_%%|*}"; t="${case_#*|}"
  page "$tmp/ex-j-$n.html" "$ESCOPE$(ideap "$t")$HOW$EX$EDGES$NOT"
  expect red "E3: part 1 with an undefined $n term fails" "$expl_scan" jargon "$tmp/ex-j-$n.html"
done
page "$tmp/ex-p-digits.html" "$ESCOPE$IDEA${HOW//$sha/20261029}$EX$EDGES$NOT"
expect red "E5: a digits-only pin (a date without dashes) fails" "$expl_scan" pins "$tmp/ex-p-digits.html" "${R[@]}"
grep -q "data-pin '20261029' is not a commit sha" "$tmp/scan.out" && ok "E5: the digits-only pin is refused as a pin, not only as a missing commit" \
  || no "E5: the digits-only pin is refused as a pin, not only as a missing commit" "$(head -2 "$tmp/scan.out")"
page "$tmp/ex-p-date.html" "$ESCOPE$IDEA${HOW//$sha/2026-10-29}$EX$EDGES$NOT"
expect red "E5: a date is not a pin" "$expl_scan" pins "$tmp/ex-p-date.html" "${R[@]}"
grep -q "data-pin '2026-10-29' is not a commit sha" "$tmp/scan.out" && ok "E5: the date is refused as a pin" \
  || no "E5: the date is refused as a pin" "$(head -2 "$tmp/scan.out")"
page "$tmp/ex-p-nopin.html" "$ESCOPE$IDEA<section data-part=\"how\"><pre data-source=\"ledger/hold.ts:1\">x</pre></section>$EX$EDGES$NOT"
expect red "E5: a code quote with no pin fails" "$expl_scan" pins "$tmp/ex-p-nopin.html" "${R[@]}"
page "$tmp/ex-p-prose.html" "$ESCOPE$IDEA$HOW$EX<section data-part=\"edges\"><p>Zero amounts are refused at hold.ts:12-18.</p></section>$NOT"
expect red "E5: a line reference in prose with no pin fails" "$expl_scan" pins "$tmp/ex-p-prose.html" "${R[@]}"
page "$tmp/ex-p-code.html" "$ESCOPE$IDEA$HOW$EX<section data-part=\"edges\"><p>See <code>ledger/hold.ts:1</code>.</p></section>$NOT"
expect red "E5: a line reference in <code> with no pin fails" "$expl_scan" pins "$tmp/ex-p-code.html" "${R[@]}"
page "$tmp/ex-p-table.html" "$ESCOPE$IDEA$HOW$EX<section data-part=\"edges\"><table><tr><td>500.00</td></tr></table></section>$NOT"
expect red "E5: a capture table with no pin fails" "$expl_scan" pins "$tmp/ex-p-table.html" "${R[@]}"
page "$tmp/ex-p-fixture.html" "$ESCOPE$IDEA$HOW<section data-part=\"example\"><pre data-source=\"ledger/hold.test.ts\" data-pin=\"$fsha\">t</pre><div data-fixture=\"source\">job 120.00</div></section>$EDGES$NOT"
expect red "E5: a data-fixture=\"source\" with no pin fails" "$expl_scan" pins "$tmp/ex-p-fixture.html" "${R[@]}"
page "$tmp/ex-p-howbare.html" "$ESCOPE$IDEA<section data-part=\"how\"><p>It sets money aside.</p></section>$EX$EDGES$NOT"
expect red "E5: a 'how' part with no pinned block fails" "$expl_scan" pins "$tmp/ex-p-howbare.html" "${R[@]}"
page "$tmp/ex-p-exbare.html" "$ESCOPE$IDEA$HOW<section data-part=\"example\"><p>A job of 100.00 leaves 400.00.</p></section>$EDGES$NOT"
expect red "E5: an 'example' part with no pinned block fails" "$expl_scan" pins "$tmp/ex-p-exbare.html" "${R[@]}"
page "$tmp/ex-p-wrongfile.html" "$ESCOPE$IDEA$HOW${EX//$fsha/$osha}$EDGES$NOT"
expect red "E5: a sha256 pin of a different file fails" "$expl_scan" pins "$tmp/ex-p-wrongfile.html" "${R[@]}"
page "$tmp/ex-p-nopath.html" "$ESCOPE$IDEA${HOW//ledger\/hold.ts:1/ledger\/gone.ts:1}$EX$EDGES$NOT"
expect red "E5: a commit pin whose commit lacks the cited file fails" "$expl_scan" pins "$tmp/ex-p-nopath.html" "${R[@]}"
page "$tmp/ex-teacher.html" "$ESCOPE$IDEA$HOW<section data-part=\"example\"><div data-fixture=\"teacher-written\" data-adapted-from=\"hold.test.ts:5\" data-source=\"ledger/hold.test.ts\" data-pin=\"$fsha\">job 120.00</div></section>$EDGES$NOT"
expect red "E5: a teacher-written fixture without its visible label fails" "$expl_scan" pins "$tmp/ex-teacher.html" "${R[@]}"
page "$tmp/ex-teacher2.html" "$ESCOPE$IDEA$HOW<section data-part=\"example\"><div data-fixture=\"teacher-written\" data-source=\"ledger/hold.test.ts\" data-pin=\"$fsha\">job 120.00, written for this page</div></section>$EDGES$NOT"
expect red "E5: a teacher-written fixture without data-adapted-from fails" "$expl_scan" pins "$tmp/ex-teacher2.html" "${R[@]}"
page "$tmp/ex-teacher-ok.html" "$ESCOPE$IDEA$HOW<section data-part=\"example\"><div data-fixture=\"teacher-written\" data-adapted-from=\"hold.test.ts:5\" data-source=\"ledger/hold.test.ts\" data-pin=\"$fsha\">job 120.00, written for this page</div></section>$EDGES$NOT"
expect green "E5: a labelled, sourced, pinned teacher-written fixture passes" "$expl_scan" pins "$tmp/ex-teacher-ok.html" "${R[@]}"

printf '\n== the boundary between /prove-explanation and /prove-explore ==\n'
expl_desc=""; [ -f "$expl" ] && expl_desc="$(fm_json "$expl" | jq -r '.description // empty')"
case "$expl_desc" in
  *"Boundary with /prove-explore:"*) ok "prove-explanation: description states the boundary with /prove-explore" ;;
  *) no "prove-explanation: description states the boundary with /prove-explore" "no 'Boundary with /prove-explore:' sentence" ;;
esac
need "$expl" "prove-explanation: body states the boundary, in both skills" 'The boundary with `/prove-explore`, stated in both skills'
plan_desc=""; [ -f "$plan" ] && plan_desc="$(fm_json "$plan" | jq -r '.description // empty')"
case "$plan_desc" in
  *"/prove-visionary"*) ok "prove-plan: description states its boundary with /prove-visionary" ;;
  *) no "prove-plan: description states its boundary with /prove-visionary" "no /prove-visionary mention" ;;
esac
explore_desc=""; [ -f "$explore_md" ] && explore_desc="$(fm_json "$explore_md" | jq -r '.description // empty')"
case "$explore_desc" in
  *"use /prove-explanation instead"*) ok "prove-explore: description states the boundary with /prove-explanation" ;;
  *)
    if [ "$STRICT" = "1" ]; then
      no "prove-explore: description states the boundary with /prove-explanation" "absent"
    else
      owe "prove-explore: description states the boundary with /prove-explanation" "absent (PROVEFAM_STRICT=0)"
    fi ;;
esac

printf '\n%d passed, %d failed, %d owed\n' "$pass" "$fail" "$owed"
[ "$fail" -eq 0 ]
