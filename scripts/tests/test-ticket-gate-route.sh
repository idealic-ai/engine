#!/bin/bash
# test-ticket-gate-route.sh — /ticket must not stall a seat that has a parent.
#
# Every gate in /ticket used to be an AskUserQuestion, so a seat whose operator was not at its
# terminal waited on it forever. The operator's ruling (ruling-ticket-tier, 2026-10-29 01:11) sends
# a routine ticket's confirm to the seat's manager as an ask, a scope-level one to the operator as
# a reserved ask, and keeps AskUserQuestion only for a seat with no parent whose operator is at the
# terminal. These arms hold the skill text to that, sentence by sentence rather than token by token:
#
#   1. skills/ticket/SKILL.md has a "## Gate route" section whose load-bearing sentences are
#      present: the lane bullet BEFORE the seat → ask-route bullet, FILE needing every visible fork,
#      the re-ask (acted + a new -r<N> ask), "No answer is not a yes", /ticket-search --report and
#      /inbox-post --channel.
#   2. Outside that section no sentence asks a person at a terminal: no AskUserQuestion, no
#      "ask the user", "at this terminal", "wait for the reply", "stop and ask".
#   3. Inside that section, a sentence naming AskUserQuestion is allowed only in the
#      operator-present bullet, or as the lane bullet's "call no AskUserQuestion".
#   4. Nowhere in /ticket does silence or a timeout count as an answer.
#   5. /snapshot states that --yes never creates a ticket.
#   6. /ticket-search has a --report mode, and every AskUserQuestion it names outside that section
#      is exempted under --report (its §4 walkthrough as a whole).
#   7. /inbox-post has a --channel mode, and every AskUserQuestion it names is exempted under
#      --channel or is the parentless-operator-present branch of its ticket offer.
#
# Every arm has a control that mutates a temp copy and must go red. The four mutants a critic
# planted against round 1 (a reworded terminal prompt, an AskUserQuestion fallback appended to the
# seat bullet, the seat bullet deleted, a timeout read as a yes) are ported as controls here.
#
# DECLARED BOUNDARY (¶INV_A_NEGATIVE_ONLY_CHECK_SAYS_SO): these arms read skill TEXT. They prove the
# skills no longer instruct a parented seat to prompt at its terminal on any path they cover; they
# cannot prove a model obeys the text, and they read only the three skills /ticket runs on that path.
#
# TICKET_SKILL_FILE / TICKET_SEARCH_SKILL_FILE / INBOX_POST_SKILL_FILE / SNAPSHOT_SKILL_FILE override
# the files read, so a mutant can be run through the same arms.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

ENGINE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TICKET="${TICKET_SKILL_FILE:-$ENGINE_DIR/skills/ticket/SKILL.md}"
TSEARCH="${TICKET_SEARCH_SKILL_FILE:-$ENGINE_DIR/skills/ticket-search/SKILL.md}"
INBOXPOST="${INBOX_POST_SKILL_FILE:-$ENGINE_DIR/skills/inbox-post/SKILL.md}"
SNAPSHOT="${SNAPSHOT_SKILL_FILE:-$ENGINE_DIR/skills/snapshot/SKILL.md}"

# One python helper; each subcommand prints a count (or offending units, then a count on the last line).
check() {
  python3 - "$@" <<'PY'
import re, sys
cmd, path = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
lines = text.split("\n")
if lines and lines[0] == "---":           # drop YAML frontmatter
    end = lines.index("---", 1)
    lines = [""] * (end + 1) + lines[end + 1:]

def sections():
    """yield (heading, [(lineno, line)]) for each '## ' section; preamble heading is ''."""
    cur, buf = "", []
    for i, l in enumerate(lines, 1):
        if l.startswith("## "):
            yield cur, buf
            cur, buf = l, []
        buf.append((i, l))
    yield cur, buf

def sentences(line):
    # split a line (a paragraph or bullet) into sentences; keep it simple and conservative
    return [s for s in re.split(r"(?<=[.!?])\s+(?=[*`A-Z(])", line) if s.strip()]

TERMINAL = re.compile(r"AskUserQuestion|ask the user|at this terminal|wait for (the|a) reply|stop and ask", re.I)
OP_PRESENT = "**`operator`, and the operator is demonstrably at this terminal**"
SILENCE_YES = [
    re.compile(r"\b(no answer|unanswered|silence|no reply)\b[^.]*\b(is|counts as|means|as)\s+(a\s+)?(yes|approval|consent|approved)\b", re.I),
    re.compile(r"\b(within|after)\s+(an?|\d+)\s+(hour|hours|minute|minutes|min|mins)\b[^.]*\b(yes|file it|file the|post it|post the)\b", re.I),
]

def out(bad):
    for b in bad: print("  " + b)
    print(len(bad))

if cmd == "outside-route":
    bad = []
    for head, body in sections():
        if head.startswith("## Gate route"): continue
        for i, l in body:
            for s in sentences(l):
                if TERMINAL.search(s): bad.append(f"line {i}: {s[:110]}")
    out(bad)

elif cmd == "inside-route":
    bad = []
    for head, body in sections():
        if not head.startswith("## Gate route"): continue
        for i, l in body:
            for s in sentences(l):
                if "AskUserQuestion" not in s: continue
                if l.lstrip().startswith("- " + OP_PRESENT): continue
                if "call no `AskUserQuestion`" in s: continue
                bad.append(f"line {i}: {s[:110]}")
    out(bad)

elif cmd == "pins":
    route = "\n".join(l for h, b in sections() if h.startswith("## Gate route") for _, l in b)
    blines = route.split("\n")
    def idx(prefix):
        for n, l in enumerate(blines):
            if l.lstrip().startswith(prefix): return n
        return -1
    missing = []
    lane = idx("- **A loom lane, or any subagent another agent dispatched, stops here.**")
    seat = idx("- **A seat (any first word but `operator`) → the ask route.**")
    if lane < 0: missing.append("lane bullet")
    if seat < 0: missing.append("seat -> ask route bullet")
    if lane >= 0 and seat >= 0 and lane > seat: missing.append("lane bullet comes before the seat bullet")
    if idx("- " + OP_PRESENT) < 0: missing.append("operator-present bullet")
    for needle in ["hop.sh target", "§CMD_CONTINUE_ON_STOP", "engine ask new --to", "engine ask read",
                   "--reserved-for operator", "Rendered description (postable)", "ONE ask",
                   "`/ticket-search --report`", "/inbox-post --channel",
                   "**`FILE` counts only when every visible fork is answered**",
                   "engine ask acted <seat>/<id> \"re-asked as <id>-r<N>", "the id `<id>-r<N>`",
                   "An unanswered ask files nothing", "**No answer is not a yes.**", "PROVISIONAL",
                   "Re-run §4 step 1's backstop dedup", "re-read the parent with `get_issue`",
                   "**If either check now differs from what the ask showed, post nothing and re-ask**",
                   "started you with its Agent or Task tool"]:
        if needle not in route: missing.append(needle)
    out(missing)

elif cmd == "silence-yes":
    bad = []
    for i, l in enumerate(lines, 1):
        for s in sentences(l):
            if any(r.search(s) for r in SILENCE_YES): bad.append(f"line {i}: {s[:110]}")
    out(bad)

elif cmd == "snapshot":
    print(1 if "`--yes` never creates a ticket" in text else 0)

elif cmd == "ticket-search":
    bad = []
    secs = list(sections())
    if not any(h.startswith("## Report mode (`--report`)") for h, _ in secs): bad.append("no Report mode section")
    rm = "\n".join(l for h, b in secs if h.startswith("## Report mode") for _, l in b)
    if "never calls `AskUserQuestion`" not in rm: bad.append("report mode does not say it never calls AskUserQuestion")
    for h, b in secs:
        if h.startswith("## Report mode"): continue
        if h.startswith("## 4."):
            intro = next((l for _, l in b[1:] if l.strip()), "")
            if "skipped under `--report`" not in intro: bad.append(f"{h}: intro does not exempt it under --report")
            continue
        for i, l in b:
            if "AskUserQuestion" in l and "--report" not in l: bad.append(f"line {i}: {l.strip()[:110]}")
    out(bad)

elif cmd == "inbox-post":
    bad = []
    secs = list(sections())
    if not any(h.startswith("## Preset mode (`--channel`)") for h, _ in secs): bad.append("no Preset mode section")
    for h, b in secs:
        if h.startswith("## Preset mode"): continue
        for i, l in b:
            for s in sentences(l):
                if "AskUserQuestion" not in s: continue
                if "--channel" in s or "no parent whose operator is at this terminal" in s: continue
                bad.append(f"line {i}: {s[:110]}")
    out(bad)
PY
}

count_of() { tail -n1; }

expect_zero() {   # $1 label, $2 subcommand, $3 file
  local outp n; outp=$(check "$2" "$3"); n=$(printf '%s\n' "$outp" | count_of)
  if [ "$n" = "0" ]; then pass "$1"; else printf '%s\n' "$outp" | sed '$d'; fail "$1" "0" "$n"; fi
}

expect_red() {    # $1 label, $2 subcommand, $3 mutated file — the arm must report >=1
  local n; n=$(check "$2" "$3" | count_of)
  if [ "${n:-0}" -ge 1 ]; then pass "control: $1"; else fail "control: $1" ">=1" "$n"; fi
}

# mutate SRC DST python-expr-on-s  (s is the file text; the expression returns the new text)
mutate() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
src, dst, expr = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src, encoding="utf-8").read()
new = eval(expr)
if new == s: sys.exit("mutation did not apply: " + expr[:80])
open(dst, "w", encoding="utf-8").write(new)
PY
}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# ------------------------------------------------------------ arm 1
test_route_pins() { expect_zero "the gate route's load-bearing sentences are present, lane bullet first" pins "$TICKET"; }

test_route_pins_control_m3() {   # critic's M3: the seat -> ask route bullet deleted
  mutate "$TICKET" "$TMPD/m3.md" "'\n'.join(l for l in s.split('\n') if not l.lstrip().startswith('- **A seat (any first word but'))" \
    && expect_red "M3 — deleting the seat → ask-route bullet goes red" pins "$TMPD/m3.md"
}

test_route_pins_control_lane_order() {   # S-1: the lane bullet moved after the seat bullet
  # swap the lane bullet with the seat bullet
  mutate "$TICKET" "$TMPD/lane.md" "(lambda L, a, b: '\n'.join(L[b] if i == a else L[a] if i == b else l for i, l in enumerate(L)))(s.split('\n'), next(i for i, l in enumerate(s.split('\n')) if l.lstrip().startswith('- **A loom lane')), next(i for i, l in enumerate(s.split('\n')) if l.lstrip().startswith('- **A seat (any first word')))" \
    && expect_red "a lane bullet that follows the seat bullet goes red" pins "$TMPD/lane.md"
}

# ------------------------------------------------------------ arm 2
test_outside_route() { expect_zero "no sentence outside the gate route asks a person at a terminal" outside-route "$TICKET"; }

test_outside_route_control_m1() {   # critic's M1: the batch confirm reworded as a terminal prompt
  mutate "$TICKET" "$TMPD/m1.md" "s.replace('Then ask **\"Post all N to Linear?\"**', 'Then stop and ask the user at this terminal **\"Post all N to Linear?\"** and wait for the reply', 1)" \
    && expect_red "M1 — a reworded terminal prompt in §4 goes red" outside-route "$TMPD/m1.md"
}

test_outside_route_control_tool() {
  mutate "$TICKET" "$TMPD/tool.md" "s.replace('## 3. Calibrate — Walk the Drafts with the User\n', '## 3. Calibrate — Walk the Drafts with the User\nThen confirm the draft with \`AskUserQuestion\`.\n', 1)" \
    && expect_red "a calibration gate that calls AskUserQuestion directly goes red" outside-route "$TMPD/tool.md"
}

# ------------------------------------------------------------ arm 3
test_inside_route() { expect_zero "inside the gate route, AskUserQuestion appears only in the operator-present branch" inside-route "$TICKET"; }

test_inside_route_control_m2() {   # critic's M2: a fallback appended to the seat bullet
  mutate "$TICKET" "$TMPD/m2.md" "s.replace('so this route is stricter than', 'If the ask goes unanswered, fall back to \`AskUserQuestion\` for the operator. So this route is stricter than', 1)" \
    && expect_red "M2 — an AskUserQuestion fallback appended to the seat bullet goes red" inside-route "$TMPD/m2.md"
}

# ------------------------------------------------------------ arm 4
test_silence_is_not_yes() { expect_zero "nowhere in /ticket does silence or a timeout count as an answer" silence-yes "$TICKET"; }

test_silence_control_m4() {   # critic's M4: step 5 rewritten as a timeout yes
  mutate "$TICKET" "$TMPD/m4.md" "s.replace('5. **No answer is not a yes.** An unanswered ask files nothing, however long it waits;', '5. **No answer within an hour is a yes.** File the draft at the lean;', 1)" \
    && expect_red "M4 — 'no answer within an hour is a yes' goes red (silence arm)" silence-yes "$TMPD/m4.md" \
    && expect_red "M4 — and its pinned sentence is missing (pins arm)" pins "$TMPD/m4.md"
}

# ------------------------------------------------------------ arm 5
test_snapshot_yes_never_files() {
  if [ "$(check snapshot "$SNAPSHOT")" = "1" ]; then pass "/snapshot states that --yes never creates a ticket"
  else fail "/snapshot states that --yes never creates a ticket" "present" "absent"; fi
}

test_snapshot_control() {
  grep -vF -- '`--yes` never creates a ticket' "$SNAPSHOT" > "$TMPD/snap.md"
  if [ "$(check snapshot "$TMPD/snap.md")" = "0" ]; then pass "control: the snapshot arm goes red with the statement removed"
  else fail "control: the snapshot arm goes red with the statement removed" "0" "1"; fi
}

# ------------------------------------------------------------ arm 6
test_ticket_search_report_mode() { expect_zero "/ticket-search --report asks nothing; its other prompts are exempted under --report" ticket-search "$TSEARCH"; }

test_ticket_search_control() {
  mutate "$TSEARCH" "$TMPD/ts.md" "s.replace('## 3. Report Intake & Relay\n', '## 3. Report Intake & Relay\n\nConfirm the headline with \`AskUserQuestion\` first.\n', 1)" \
    && expect_red "an unexempted AskUserQuestion in /ticket-search goes red" ticket-search "$TMPD/ts.md"
}

# ------------------------------------------------------------ arm 7
test_inbox_post_channel_mode() { expect_zero "/inbox-post --channel asks nothing; its offer routes by the gate route" inbox-post "$INBOXPOST"; }

test_inbox_post_control() {
  mutate "$INBOXPOST" "$TMPD/ip.md" "s.replace('So **offer** to file it, and let the human decide.', 'So **offer** to file it with \`AskUserQuestion\`, and let the human decide.', 1)" \
    && expect_red "an unrouted AskUserQuestion ticket offer in /inbox-post goes red" inbox-post "$TMPD/ip.md"
}

# ------------------------------------------------------------
run_discovered_tests
