#!/bin/bash
# lint-lib.sh — pure container-conformance logic for `engine project lint`.
#
# Sourced, never invoked directly. No network, no Linear, no $HOME resolution — every
# function here takes a schema path and a text file and returns JSON. That is what keeps
# the rules testable offline and keeps project.sh from growing a second personality.
#
# Public surface:
#   lint_container <schema> <container> <file> [--strict] [--target NAME]  -> findings JSON array
#   lint_peers     <schema> <container> <label:file> ...                   -> findings JSON array
#   lint_exit_code <findings-json> [unreachable-count]                     -> 0 | 1 | 2
#
# Findings model (one shape, three renderers live in project.sh):
#   { container, target, severity: fail|warn, rule, id, heading, belongsIn, message }
#
# WHY `belongsIn` IS DERIVED AND NOT LOOKED UP IN A TABLE
# ------------------------------------------------------
# A heading this container does not name is searched across the OTHER containers' section
# lists in the same schema. If a sibling names it, that sibling IS the destination. There is
# no bad-heading -> destination map anywhere in this file or in the schema, and none should be
# added: such a map is a hand-curated snapshot of the headings someone happened to have seen,
# and it goes stale exactly like the prose enumerations this linter exists to replace. The
# lookup is also self-teaching — declaring a section on the handbook automatically teaches the
# description linter that the heading does not belong there, with no second edit.
# A heading NO container names suggests nothing. There is deliberately no fuzzy/nearest-name
# fallback: this check states facts about the schema, never opinions about intent.
#
# NORMALIZATION IS GENERIC; ALIASING IS CURATION.
# `norm` below case-folds and collapses whitespace on every heading lookup. That is a RULE — it
# holds for every heading forever, it stores no data, and it recovers `Data Handling` ->
# `Data handling` for free. An alias list recording that a section used to be called something
# else is the opposite: a maintained fact about one heading's history, and the first row of the
# curated table this library exists without. Normalization may be extended; aliases may not.
# A heading whose words genuinely changed reports "not named by any container" — the honest answer.
#
# Bash 3.2 (macOS) note: nothing here uses a named array, precisely because an empty findings
# array under `set -u` is the happy path and the classic place that crashes.

[ -n "${_LINT_LIB_LOADED:-}" ] && return 0
_LINT_LIB_LOADED=1

_lint_die() { echo "lint-lib: $1" >&2; return 1; }

_lint_need_jq() {
  command -v jq >/dev/null 2>&1 || { _lint_die "jq is required"; return 1; }
}

# _lint_parse FILE -> { lines: [...], preamble: [non-empty lines before the first `## `],
#                       sections: [{ heading, index, body }] }
_lint_parse() {
  local file="$1"
  [ -f "$file" ] || { _lint_die "no such file: $file"; return 1; }
  jq -Rn '
    [inputs] as $lines
    | [ range(0; $lines|length) as $i | select($lines[$i] | startswith("## ")) | $i ] as $h
    | {
        lines: $lines,
        preamble: ( (if ($h|length) > 0 then $lines[0:$h[0]] else $lines end)
                    | map(select(test("\\S"))) ),
        sections: [ range(0; $h|length) as $k
          | { heading: ($lines[$h[$k]] | ltrimstr("## ") | sub("\\s+$"; "")),
              index: $k,
              body: ( $lines[ ($h[$k] + 1) : (if ($k + 1) < ($h|length) then $h[$k+1] else ($lines|length) end) ]
                      | map(select(test("\\S"))) | join("\n") ) } ]
      }
  ' < "$file"
}

# Shared jq preamble: normalization + the cross-container lookup both entry points need.
_lint_jq_common() {
  cat <<'JQ'
def norm: ascii_downcase | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");

$schema.containers[$container] as $C
| $C.sections as $S
# Names THIS container claims.
| [ $S[] | select(.heading != null) | .heading | norm ] as $mine
# The cross-container lookup. Built from the schema's own section lists at run time —
# this is the whole of "canonicalization", and it is derived, never curated.
| ( reduce ($schema.containers | to_entries | .[] | select(.key != $container)) as $c
      ({};
        reduce ($c.value.sections[] | select(.heading != null) | .heading | norm) as $h
          (.; if has($h) then . else . + {($h): $c.key} end))
  ) as $elsewhere
# heading-norm -> { id, ord } for this container, used for order and peer alignment.
| ( reduce ( range(0; $S|length) as $i
             | ($S[$i] | select(.heading != null) | .heading
                | {k: norm, v: {id: $S[$i].id, ord: $i}}) ) as $e
      ({}; . + {($e.k): $e.v})
  ) as $byName
JQ
}

# lint_container SCHEMA CONTAINER FILE [--strict] [--target NAME]
lint_container() {
  _lint_need_jq || return 1
  local schema="$1" container="$2" file="$3"; shift 3
  local strict=false target=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --strict) strict=true; shift ;;
      --target) target="${2:-}"; shift 2 ;;
      *) _lint_die "unknown option: $1"; return 1 ;;
    esac
  done
  [ -n "$target" ] || target=$(basename "$file")
  [ -f "$schema" ] || { _lint_die "no such schema: $schema"; return 1; }
  jq -e --arg c "$container" '.containers | has($c)' "$schema" >/dev/null 2>&1 \
    || { _lint_die "unknown container '$container' (schema declares: $(jq -r '.containers|keys|join(", ")' "$schema" 2>/dev/null))"; return 1; }

  local doc
  doc=$(_lint_parse "$file") || return 1
  jq -n --argjson doc "$doc" --slurpfile _s "$schema" \
        --arg container "$container" --arg target "$target" --argjson strict "$strict" \
        "\$_s[0] as \$schema | $(_lint_jq_common)"'
| [ $doc.sections[] | . + {n: (.heading | norm)} ] as $secs
| ($secs | map(. as $s | select(($mine | index($s.n)) == null))) as $stray
| ($S | map(select(.freeform == true)) | first) as $free
# Strays no container names at all — "absorbed" by a freeform section, if the container has one.
| ($stray | map(. as $s | select($elsewhere[$s.n] == null))) as $absorbed

# Strays: derived destination, or an honest "no container names this".
| [ $stray[]
    | . as $s
    | ($elsewhere[$s.n] // null) as $dest
    | if $dest != null then
        { container: $container, target: $target,
          severity: (if $strict then "fail" else "warn" end),
          rule: "undeclared-heading", id: null, heading: $s.heading, belongsIn: $dest,
          message: ("`## " + $s.heading + "` is not a " + $container + " section. The "
                    + $dest + " container names it — it belongs in the " + $dest + ".") }
      elif $free != null then
        # Absorbed by a freeform section: the container declares that its own prose voice owns
        # headings the schema does not enumerate. Silent by default; surfaced (never blocking)
        # under --strict, because the pre-write gate must not refuse a description whose prose
        # headings are already live and correct.
        if $strict then
          { container: $container, target: $target, severity: "warn",
            rule: "unknown-heading", id: $free.id, heading: $s.heading, belongsIn: null,
            message: ("`## " + $s.heading + "` is not named by any container; it is absorbed by the freeform `"
                      + $free.id + "` section.") }
        else empty end
      else
        { container: $container, target: $target, severity: "warn",
          rule: "unknown-heading", id: null, heading: $s.heading, belongsIn: null,
          message: ("`## " + $s.heading + "` is not named by any container.") }
      end ] as $f_stray

# Required sections.
| [ $S[] | select(.required == true) | . as $sec
    | ( if $sec.heading != null then
          ($sec.heading | norm) as $name
          | ($secs | map(select(.n == $name)) | length) > 0
        elif $sec.locator == "match" then
          ($doc.lines | map(select(test($sec.match))) | length) > 0
        elif $sec.locator == "preamble" then
          ( ($doc.preamble | length) >= ($sec.minLines // 1) )
          or ($sec.freeform == true and ($absorbed | length) > 0)
        else true end ) as $present
    | select($present | not)
    | { container: $container, target: $target, severity: "fail",
        rule: "missing-required", id: $sec.id,
        heading: ($sec.heading // null), belongsIn: null,
        message: ("required section `" + $sec.id + "` is missing from this " + $container + ".") } ] as $f_req

# Order (advisory).
| [ $secs[] | . as $s | ($byName[$s.n] // empty) | . + {heading: $s.heading} ] as $seq
| [ range(1; $seq|length) as $k
    | select($seq[$k].ord < $seq[$k-1].ord)
    | { container: $container, target: $target, severity: "warn",
        rule: "section-order", id: $seq[$k].id, heading: $seq[$k].heading, belongsIn: null,
        message: ("`## " + $seq[$k].heading + "` appears after `## " + $seq[$k-1].heading
                  + "`; the schema fixes the opposite order.") } ] as $f_order

# A heading declared twice. Cheap to state and a real conformance fact — and without it the
# duplicate is invisible: the required-section check is satisfied by either copy, and the order
# rule reports the second copy as an ordering nit instead of as the duplication it is.
| [ $secs | group_by(.n) | .[] | select(length > 1) | . as $g
    | { container: $container, target: $target, severity: "warn",
        rule: "duplicate-heading", id: ($byName[$g[0].n].id // null),
        heading: $g[0].heading, belongsIn: null,
        message: ("`## " + $g[0].heading + "` appears " + ($g|length|tostring) + " times in this "
                  + $container + "; a heading must identify exactly one section.") } ] as $f_dup

| $f_req + $f_stray + $f_dup + $f_order
'
}

# lint_peers SCHEMA CONTAINER label:file [label:file ...]
# peerCompare: "same"  -> an identical section body across peers is the smell
#              "differ" -> divergence across hand-synced copies is the smell
#              "none"   -> no peer axis; returns []
# `perProject` sections and `sharedTextAllowlist` ids are exempt — without those exemptions
# the handbook comparison flags its two most correct sections.
lint_peers() {
  _lint_need_jq || return 1
  local schema="$1" container="$2"; shift 2
  [ -f "$schema" ] || { _lint_die "no such schema: $schema"; return 1; }
  jq -e --arg c "$container" '.containers | has($c)' "$schema" >/dev/null 2>&1 \
    || { _lint_die "unknown container '$container' (schema declares: $(jq -r '.containers|keys|join(", ")' "$schema" 2>/dev/null))"; return 1; }

  local peers="[]" spec label file doc
  for spec in "$@"; do
    # Split at the LAST colon, not the first: every real peer label is a Linear project name and
    # every one of them contains a colon ("Product: Differ"). Paths never do.
    label="${spec%:*}"; file="${spec##*:}"
    doc=$(_lint_parse "$file") || return 1
    peers=$(printf '%s' "$peers" | jq --arg l "$label" --argjson d "$doc" '. + [{target: $l, doc: $d}]') || return 1
  done

  # `sectionlabel` names a comparable section the way the reader can act on it: by schema id when the
  # schema declares the heading, by the heading itself when it does not.
  jq -n --argjson peers "$peers" --slurpfile _s "$schema" --arg container "$container" \
        "def sectionlabel(\$bn; \$k; \$h): if \$bn[\$k] then \"section \`\" + \$bn[\$k].id + \"\`\" else \"\`## \" + \$h + \"\`\" end;
         \$_s[0] as \$schema | $(_lint_jq_common)"'
| ($C.peerCompare // "none") as $mode
| ($C.sharedTextAllowlist // []) as $allow
# EVERY `## ` section is peer-comparable, keyed by its NORMALIZED HEADING — not only the ones
# the schema already declares for this container. Restricting the comparison to declared sections
# inverts the rule it implements: "text byte-identical across all five projects is evidence it
# belongs in the shared document" would then fire only where the schema already knows the answer,
# and a novel block copy-pasted into five descriptions would be absorbed by `freeform` and seen
# by nothing. An id is attached where the schema has one, and is null where it does not.
#
# Deduped to FIRST OCCURRENCE per key: a container that declares one heading twice must not
# inflate the per-key body count, or the "present on every peer" guards below silently no-op
# for that section across the whole population. The duplicate itself is reported by
# the `duplicate-heading` rule in lint_container.
# NOTE (bash): this jq program is single-quoted — an apostrophe anywhere in a comment ends it.
| [ $peers[] | . as $p
    | { target: $p.target,
        sections: [ ( reduce ( $p.doc.sections[]
                               | {key: (.heading | norm), heading: .heading, body: .body} ) as $e
                        ({}; if has($e.key) then . else . + {($e.key): $e} end) ) | .[] ] } ] as $P
# The two exemptions stay keyed by the schema, because both are statements the schema makes:
# `perProject` sections are SUPPOSED to diverge, and `sharedTextAllowlist` ids are identical
# across peers by construction. An undeclared heading is neither, so it is always comparable.
# `index` (element equality), never `inside` (substring containment) — `["Product: Claims"]
# inside ["Product: Claims & Policies"]` is TRUE, which silently exempts any id or peer name
# that happens to be a substring of another.
# The needle is bound to a variable at every `index` call: inside `index(f)`, `.` is the ARRAY
# being searched, not the surrounding input, so a bare `index(.id)` reads `.id` off the haystack.
| [ $S[] | select(.heading != null) | . as $sec
         | select(($sec.perProject // false) == true or (($allow | index($sec.id)) != null))
         | .heading | norm ] as $exempt
| ( [ $P[] | .sections[] | .key ] | unique ) as $allkeys
| [ $allkeys[] | . as $key | select(($exempt | index($key)) == null) ] as $keys
| ( if $mode == "same" then
      [ $keys[] as $k
        | [ $P[] | .sections[] | select(.key == $k) ] as $hits
        | ($hits | map(.body)) as $bodies
        | select(($bodies | length) >= 2 and ($bodies | unique | length) == 1)
        | { container: $container, target: ([$P[].target] | join(", ")), severity: "warn",
            rule: "shared-text", id: ($byName[$k].id // null), heading: $hits[0].heading, belongsIn: null,
            message: (sectionlabel($byName; $k; $hits[0].heading) + " is byte-identical across " + ($bodies|length|tostring)
                      + " peers — evidence it belongs in the shared document, not in each description.") } ]
    elif $mode == "differ" then
      ( [ $keys[] as $k
          | [ $P[] | .sections[] | select(.key == $k) ] as $hits
          | ([ $P[] | select(any(.sections[]; .key == $k)) | .target ]) as $has
          | select(($has | length) >= 2)
          | $P[] | . as $peer | select(($has | index($peer.target)) == null)
          | { container: $container, target: .target, severity: "warn",
              rule: "missing-peer-section", id: ($byName[$k].id // null), heading: $hits[0].heading,
              belongsIn: null,
              message: (sectionlabel($byName; $k; $hits[0].heading)
                        + " is present on sibling copies but missing here — the copies have drifted.") } ]
        +
        [ $keys[] as $k
          | [ $P[] | .sections[] | select(.key == $k) ] as $hits
          | ($hits | map(.body)) as $bodies
          | select(($bodies | length) == ($P | length) and ($bodies | unique | length) > 1)
          | { container: $container, target: ([$P[].target] | join(", ")), severity: "warn",
              rule: "peer-text-differs", id: ($byName[$k].id // null), heading: $hits[0].heading,
              belongsIn: null,
              message: (sectionlabel($byName; $k; $hits[0].heading)
                        + " differs across hand-synced copies and is not marked perProject.") } ] )
    else [] end )
'
}

# lint_is_findings JSON -> 0 when JSON is a well-formed findings array.
# Every accumulation step rebuilds the findings string through jq. A step that fails leaves an
# empty or malformed string behind, which silently erases every finding collected so far — so
# callers validate BEFORE merging and record could-not-run instead of merging garbage.
lint_is_findings() {
  printf '%s' "${1:-}" | jq -e 'type == "array"' >/dev/null 2>&1
}

# lint_exit_code FINDINGS_JSON [UNREACHABLE_COUNT] -> prints 0 | 1 | 2
# 2 outranks 1 on purpose: partial coverage must never read as a clean-or-even-a-known-bad
# bill of health. An infrastructure problem is not drift.
lint_exit_code() {
  # `${1-}` and not `${1:-}`: an OMITTED argument defaults, an argument that is present but EMPTY
  # does not. An empty findings string is a wiped accumulator, which is the whole hazard here.
  local findings="${1-[]}" unreachable="${2-0}"
  # A count that cannot be read is not a count of zero.
  case "$unreachable" in
    ''|*[!0-9]*) echo 2; return 0 ;;
  esac
  # An unusable findings string is could-not-run, never clean. `jq -e` exits non-zero for "no
  # failures" AND for empty input AND for a parse error, so the fail test alone reads a wiped
  # accumulator as a clean bill of health — failure-open inside the one function whose job is
  # to be failure-closed. The shape is checked first, and separately.
  lint_is_findings "$findings" || { echo 2; return 0; }
  if [ "$unreachable" -gt 0 ]; then echo 2; return 0; fi
  if printf '%s' "$findings" | jq -e 'any(.[]; .severity == "fail")' >/dev/null 2>&1; then
    echo 1
  else
    echo 0
  fi
}
