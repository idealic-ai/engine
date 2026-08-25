#!/bin/bash
# intake-announce.sh — engine intake-announce: compose the wave announce's blocks from wave FACTS
#
# A wave supplies facts; this emits Block Kit. It pairs with the generic poster:
#
#   engine intake-announce --state decision <<'EOF' | engine slack-post --channel '#name' --blocks -
#   { "project": "Email Classification", "pass": 3, ... }
#   EOF
#
# The announce is ONE message with TWO states. `--state decision` is what event 1
# posts; `--state outcomes` is what event 2 EDITS it into (slack-post --update-ts).
# The skeleton is the same and the closed state ADDS the outcome paragraph rather
# than swapping content, so the record grows instead of being replaced.
#
# WHAT THIS DOES NOT DO: write the overview prose. That block characterises the
# pass — scope, cadence and why it slipped, the back-and-forth, what is genuinely
# new, what is blocked — which is judgement, not data. It is passed in (`overview`,
# and `outcome` at close). Generating it would produce the filler it exists to
# replace, so the composer deliberately leaves a hole rather than filling it.
#
# Facts (stdin JSON). All optional but `project` — a missing field drops its block
# or its line rather than failing, because a wave with nothing to say in a slot is
# a normal wave:
#   project pass operator drained window gap boardUrl updateUrl watermark
#   decisionsOpen | filed folded parked        overview  outcome
#   counts  [{label, value}]
#   refs    [{n, id, label, why}]   moreCount
#   waiting [{name, slackId, slug, count}]
#   signal  [{emoji, slug, count}]  quiet
#
# TWO RULES ENFORCED HERE rather than trusted to the caller:
#   * a `waiting` entry with NO `slackId` renders the plain name and NO mention.
#     An unresolved `@name` notifies nobody while looking like an ask, and an
#     invented one manufactures an obligation for a person who does not exist.
#   * `signal` entries with count 0 are DROPPED, so a caller cannot ship `🔵 0`.
#     The `quiet` line is what carries their absence.
#
# `[n]` ref numbers come from the facts, never from array position — a threaded
# reply citing `[3]` must still resolve after the message is edited.
#
# Exit: 0 and the payload on stdout; non-zero with the reason on stderr.
set -uo pipefail

die() { echo "intake-announce: $1" >&2; exit 1; }

usage() { sed -n '2,/^set /p' "$0" | sed 's/^# \{0,1\}//; s/^#$//' | sed '$d'; exit "${1:-0}"; }

state=""; pretty=0
while [ $# -gt 0 ]; do
  case "$1" in
    --state)  state="${2:-}"; shift 2 ;;
    --pretty) pretty=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

case "$state" in
  decision|outcomes) ;;
  "") die "--state required (decision | outcomes)" ;;
  *)  die "--state must be 'decision' or 'outcomes' (got '$state')" ;;
esac

command -v jq >/dev/null 2>&1 || die "jq is required"

facts="$(cat)"
[ -n "$facts" ] || die "no facts on stdin — pipe the wave's facts JSON in"
printf '%s' "$facts" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || die "facts must be a JSON object"
printf '%s' "$facts" | jq -e 'has("project")' >/dev/null 2>&1 \
  || die "facts.project is required (it names the wave)"

blocks=$(printf '%s' "$facts" | jq --arg state "$state" '
  def esc: tostring;
  def open: $state == "decision";

  # --- header: the state reads from the emoji before any text is parsed
  def b_header:
    { type: "header",
      text: { type: "plain_text", emoji: true,
              text: ((if open then "🟠 " else "✅ " end)
                     + (.project|esc)
                     + (if .pass then " — grooming pass \(.pass)" else "" end)) } };

  # --- context: who/how much/when, plus the gap line that makes silence legible
  def b_meta:
    [ (.operator // empty | esc),
      (if .drained then "*\(.drained)* drained" else empty end),
      (if .window then "`\(.window)`" else empty end),
      (if open then (if .gap then "previous pass *\(.gap)*" else empty end)
                else (if .closed then "closed *\(.closed)*" else empty end) end)
    ] | join("  ·  ")
    | if . == "" then empty else { type: "context", elements: [ { type: "mrkdwn", text: . } ] } end;

  # --- callout: THE state indicator. colour + copy + the one link that matters
  def b_callout:
    (if open
       then { colour: "orange",
              line: ("*\(.decisionsOpen // 0) decisions open — nothing filed yet.* "
                     + "Every one still needs a human confirm. This message is edited in place when the wave closes."),
              link: (if .boardUrl then "🗳️  <\(.boardUrl)|*Open the Decision Board — steer / vote*>" else null end) }
       else { colour: "green",
              line: ("*Wave closed.* \(.filed // 0) filed  ·  \(.folded // 0) folded into existing work  ·  "
                     + "\(.parked // 0) parked. Every disposition passed a human confirm."),
              link: (if .boardUrl then "📋  <\(.boardUrl)|*Open the Outcomes Board — what changed*>" else null end) }
     end) as $c
    | { type: "callout", background_color: $c.colour,
        child_blocks: ([ { type: "section", text: { type: "mrkdwn", text: $c.line } } ]
                       + (if $c.link then [ { type: "section", text: { type: "mrkdwn", text: $c.link } } ] else [] end)) };

  # --- overview: PASSED IN, never generated. at close, the outcome joins it below
  def b_prose:
    [ (if .overview then { type: "section", text: { type: "mrkdwn", text: (.overview|esc) } } else empty end),
      (if (open|not) and .outcome then { type: "section", text: { type: "mrkdwn", text: (.outcome|esc) } } else empty end) ];

  def b_counts:
    (.counts // []) as $c
    | if ($c|length) == 0 then empty
      else { type: "table",
             column_settings: [ { is_wrapped: true }, { align: "right" } ],
             rows: ([ [ { type: "raw_text", text: "Outcome" }, { type: "raw_text", text: "Count" } ] ]
                    + ($c | map([ { type: "raw_text", text: (.label|esc) },
                                  { type: "raw_text", text: (.value|esc) } ]))) }
      end;

  # --- refs: [n] from the FACTS, never array position. no @s — this stays a list of decisions
  def b_refs:
    . as $f
    | ($f.refs // []) as $r
    | if ($r|length) == 0 then empty
      else ($r | map(
              ((if $f.boardUrl and .id then "<\($f.boardUrl)#\(.id)|*[\(.n)]*  \(.label|esc)>"
                else "*[\(.n)]*  \(.label|esc)" end)
               + (if .why then "  ·  _\(.why|esc)_" else "" end))) | join("\n")) as $lines
        | { type: "container", is_collapsible: false, default_collapsed: false,
            title: { type: "plain_text", text: (if open then "Pull these first" else "What we decided" end) },
            child_blocks: ([ { type: "section", text: { type: "mrkdwn", text: $lines } } ]
                           + (if ($f.moreCount // 0) > 0 and $f.boardUrl
                              then [ { type: "section", text: { type: "mrkdwn",
                                       text: "_+ \($f.moreCount) more_  ·  <\($f.boardUrl)|all on the board →>" } } ]
                              else [] end)) }
      end;

  # --- waiting: one line per PERSON. NO slackId -> plain name, NO mention.
  def b_waiting:
    . as $f
    | ($f.waiting // []) as $w
    | if ($w|length) == 0 then empty
      else ($w | map(
              ((if .slackId then "<@\(.slackId)>" else (.name|esc) end)
               + "  —  "
               + (if $f.boardUrl and .slug
                  then "<\($f.boardUrl)?user=\(.slug)|*\(if open then "\(.count // 0) decision\(if (.count // 0) == 1 then "" else "s" end) to make" else "answered \(.count // 0)" end)*>"
                  else (if open then "*\(.count // 0) decision\(if (.count // 0) == 1 then "" else "s" end) to make*" else "answered *\(.count // 0)*" end) end))) | join("\n")) as $lines
        | { type: "container", is_collapsible: false, default_collapsed: false,
            title: { type: "plain_text", text: (if open then "Waiting on" else "Who weighed in" end) },
            child_blocks: [ { type: "section", text: { type: "mrkdwn", text: $lines } } ] }
      end;

  # --- signal: ZERO COUNTS DROPPED HERE so a caller cannot ship "🔵 0"
  def b_signal:
    . as $f
    | (($f.signal // []) | map(select((.count // 0) > 0))) as $s
    | if ($s|length) == 0 and ($f.quiet == null) then empty
      else (($s | map(if $f.boardUrl and .slug
                      then "<\($f.boardUrl)?inbox=\(.slug)|\(.emoji) `\(.count)`>"
                      else "\(.emoji) `\(.count)`" end) | join("   ")) as $row
            | { type: "context", elements: [ { type: "mrkdwn",
                text: ("*Signal in* — " + $row + (if $f.quiet then "    _\($f.quiet|esc)_" else "" end)) } ] })
      end;

  def b_footer:
    [ (if .watermark then "Watermark `\(.watermark|esc)`" else empty end),
      (if .updateUrl then "<\(.updateUrl)|Project Update →>" else empty end)
    ] | join("  ·  ")
    | if . == "" then empty else { type: "context", elements: [ { type: "mrkdwn", text: . } ] } end;

  { blocks: ([ b_header, b_meta, b_callout ] + b_prose
             + [ b_counts, b_refs, b_waiting, b_signal, { type: "divider" }, b_footer ]
             | map(select(. != null))) }
') || die "failed to compose blocks — check the facts JSON"

if [ "$pretty" -eq 1 ]; then printf '%s\n' "$blocks"; else printf '%s\n' "$blocks" | jq -c .; fi
