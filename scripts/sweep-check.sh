#!/bin/bash
# sweep-check.sh — list decisions in a loom's log that NO register block was written after.
#
# Usage:
#   engine sweep-check <logFile> [--all]
#
# THE CLAIM, stated at its true size. The key is temporal and nothing else: was any register
# block written AFTER this decision? If none was, the decision cannot have been rowed, and it is
# reported UNROWED. That is a statement about whether a row COULD exist, not whether one does.
# A decision that a register write followed is reported FOLLOWED, and that is NOT evidence it
# was rowed: the later write may not mention it. So UNROWED is certain and FOLLOWED is a
# superset. Exit 0 means "no decision is certainly unrowed", never "every decision was rowed".
# There is deliberately no content comparison (thread names, ids, words): a content key matched
# a thread name rather than the decision and was wrong on half of its verdicts.
#
# A decision is a `## ...` heading whose first word, after an optional `[YYYY-MM-DD HH:MM:SS]`
# stamp, `[TAG]` prefixes and any glyphs, is Decision or Decisions. `engine log` injects the stamp
# between `## ` and the rest, so a log holds both `## 💡 Decision — x` and
# `## [2026-10-21 14:09:47] 💡 Decision — x`; the match is NOT anchored on the emoji. A heading
# that only mentions the word mid-heading (`💡 FOUR DECISIONS`) is not counted; the number of
# such headings is printed so the limit is visible.
#
# The register blocks are `🧵 Ledger`, `🗳️ Asks` (an older log's `🗳️ Boards` still counts), `📚 Docs owed`, `🔓 Open claims` and
# `🅿️ Parked`. Only the heading's position is read, never the block's rows.
#
# Exit 0 = no decision is certainly unrowed, 3 = at least one is (a finding, not a failure),
# 2 = the log could not be read, a code fence is left open, or the instrument disagrees with its
# own control, 1 = usage. Read the exit status DIRECTLY, never through a pipeline.
#
# Every reading carries its timestamp and the line numbers it was taken from, because a
# register is rewritten by ordinary logging and a figure from a minute ago may already be false.
# Read-only: it never touches the log.

set -euo pipefail

LOG="${1:?usage: engine sweep-check <logFile> [--all]}"
shift
SHOW_ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) SHOW_ALL=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

exec python3 -I - "$LOG" "$SHOW_ALL" <<'PY'
import bisect, re, sys, time

log_path, show_all = sys.argv[1], sys.argv[2] == "1"
try:
    with open(log_path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
except OSError as exc:
    print(f"sweep-check: cannot read {log_path}: {exc}", file=sys.stderr)
    sys.exit(2)

STAMP = re.compile(r"^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\]\s*")
DECISION = re.compile(r"^(?:\[[^\]]*\]\s*)*[^A-Za-z0-9]*decision", re.IGNORECASE)
REGISTERS = [
    ("Ledger", re.compile(r"\U0001F9F5\uFE0F?\s*Ledger")),
    # The name ends at a separator or the end of the heading: "🗳️ Asks read — gate 3" is an event named after
    # the trigger, not a write of the register (LOOMASK round 2, S1). "·" is not a separator: it joins an
    # event's detail, as in "🗳️ Asks · read at gate 3" (LOOMASK round 3, R4).
    ("Asks", re.compile(r"\U0001F5F3\uFE0F?\s*(?:Asks|Boards)(?=\s*(?:[\u2014\u2013:(-]|at\b|$))")),
    ("Docs owed", re.compile(r"\U0001F4DA\uFE0F?\s*Docs owed")),
    ("Open claims", re.compile(r"\U0001F513\uFE0F?\s*Open claims")),
    ("Parked", re.compile(r"\U0001F17F\uFE0F?\s*Parked")),
]

def head_text(n):
    return STAMP.sub("", lines[n - 1][3:])

# >>> fence-pass: shared by lane-stall.sh and sweep-check.sh, byte for byte (a test compares them)
# A line inside a fenced code block is an EXAMPLE, not an entry. The rule is CommonMark's for the
# fence characters: a fence opens on a line of 3+ backticks or 3+ tildes and closes only on a line
# of the SAME character, at least as long, with nothing else on it. So a ```` fence can quote a
# ``` example, and ~~~ fences count too. A backtick run with another backtick later on the line is
# an inline span, not a fence (CommonMark forbids backticks in a backtick fence's info string).
# Indentation is read relative to the opener, which may sit at any depth so a fence inside a list
# item is still seen: a line indented 4 or more columns past the opener is content and never
# closes the fence. That is the case that bites: engine docs indent a ``` 4 spaces under a bullet,
# and closing on it would end a top-level fence early and read the quoted rest as real.
# Not handled: fences inside blockquotes ("> ```").
#
# The CALLER owns every counter: one FencePass per file read, so a second read of a log, or a log
# read for another session, never adds to this sweep's figures. A fence left open is reported
# through finish(), which reads whatever the caller did not, so a caller that stops early still
# learns about a fence the rest of the file leaves open. Each caller decides what that means
# for its own exit status.
class FencePass:
    OPEN = re.compile(r"^(`{3,}|~{3,})(.*)$")

    def __init__(self, lines, fenced_marker=None):
        """lines: any iterable of lines. fenced_marker(line) -> bool is counted inside fences."""
        self.fenced_marker = fenced_marker
        self.fenced_markers = 0   # fenced lines fenced_marker matched
        self.fenced_lines = 0     # lines inside a fence, the fence lines themselves excluded
        self.open_at = None       # line number of the fence open at the current position
        self.exhausted = False
        self._gen = self._scan(lines)

    def __iter__(self):
        return self._gen

    @staticmethod
    def _indent(body):
        wide = body.expandtabs(4)
        return len(wide) - len(wide.lstrip(" "))

    def _scan(self, lines):
        fence, fence_indent = None, 0
        for lineno, line in enumerate(lines, 1):
            body = line.rstrip("\r\n")
            stripped = body.lstrip(" \t")
            if fence is None:
                m = self.OPEN.match(stripped)
                if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
                    fence, fence_indent, self.open_at = m.group(1), self._indent(body), lineno
                    continue
                yield lineno, line
                continue
            t = stripped.rstrip()
            if (t and set(t) == {fence[0]} and len(t) >= len(fence)
                    and self._indent(body) < fence_indent + 4):
                fence, self.open_at = None, None
                continue
            self.fenced_lines += 1
            if self.fenced_marker and self.fenced_marker(line):
                self.fenced_markers += 1
        self.exhausted = True

    def finish(self):
        """Read what the caller did not; return the line a fence left open at EOF, or None."""
        for _ in self._gen:
            pass
        return self.open_at
# <<< fence-pass

# Pass 1: headings outside code fences. A fence left open swallows the rest of the log, which
# would read as "0 decisions, exit 0", so it is an instrument fault instead.
fp = FencePass(lines, lambda line: line.startswith("## ") and bool(DECISION.match(STAMP.sub("", line[3:]))))
headings = [i for i, line in fp if line.startswith("## ")]
fence_open = fp.finish()
fenced_decisions, fenced_lines = fp.fenced_markers, fp.fenced_lines
if fence_open is not None:
    print(f"sweep-check: code fence opened at L{fence_open} is never closed; "
          f"the {len(lines) - fence_open} lines after it were not read", file=sys.stderr)
    sys.exit(2)

# Pass 2: every register write, in line order.
writes = []
for n in headings:
    text = head_text(n)
    for name, rx in REGISTERS:
        if rx.match(text):
            writes.append((n, name))
write_lines = [n for n, _ in writes]
latest = {}
for n, name in writes:
    latest[name] = n

decisions = [n for n in headings if DECISION.match(head_text(n))]

# Control with a different shape: a first-word test over every `## ` line, fence or not.
def first_word(text):
    toks = text.split()
    k = 0
    while k < len(toks) and (toks[k].startswith("[") or not re.search(r"[A-Za-z0-9]", toks[k])):
        k += 1
    return toks[k].lower() if k < len(toks) else ""

control_count = sum(1 for i, l in enumerate(lines, 1)
                    if l.startswith("## ") and first_word(head_text(i)).startswith("decision"))
if control_count != len(decisions) + fenced_decisions:
    print(f"sweep-check: instrument disagrees with its control "
          f"(pattern found {len(decisions)} + {fenced_decisions} fenced, first-word test found {control_count})",
          file=sys.stderr)
    sys.exit(2)
stamped = sum(1 for n in decisions if STAMP.match(lines[n - 1][3:]))
decision_set = set(decisions)
mid_mentions = sum(1 for n in headings if n not in decision_set and "decision" in head_text(n).lower())

now = time.strftime("%Y-%m-%d %H:%M:%S")
print(f"sweep-check {log_path} @ {now} · {len(lines)} lines · {len(headings)} '## ' headings · {fenced_lines} fenced lines")
print("claim: temporal only. UNROWED = no register block was written after the decision, so it cannot have been rowed (certain).")
print("       FOLLOWED = a register write came after; that does NOT show the decision was rowed (a superset). No content is compared.")
found = " · ".join(f"{name} L{latest[name]}" if name in latest else f"{name} none" for name, _ in REGISTERS)
print(f"latest register blocks: {found} · {len(writes)} register writes in all")
print(f"decision headings: {len(decisions)} (stamped {stamped}, unstamped {len(decisions) - stamped}"
      f"{', fenced ' + str(fenced_decisions) + ' excluded' if fenced_decisions else ''}"
      f"; {mid_mentions} other headings mention 'decision' mid-heading and are not counted)")

unrowed = 0
for n in decisions:
    title = head_text(n).strip()[:110]
    k = bisect.bisect_right(write_lines, n)
    if k == len(write_lines):
        unrowed += 1
        last = f"latest register write L{write_lines[-1]}" if write_lines else "no register block in the log"
        print(f"UNROWED  L{n}  {title}  [no register block after it; {last}]")
    elif show_all:
        wn, wname = writes[k]
        print(f"FOLLOWED L{n}  {title[:70]}  [{wname} written at L{wn}]")
followed = len(decisions) - unrowed
if not decisions:
    print(f"0 decision headings seen among {len(headings)} headings; this is a claim about what was recognised")
print(f"{len(decisions)} decisions: {unrowed} cannot have been rowed, {followed} followed by a register write (not shown to be rowed)")
sys.exit(3 if unrowed else 0)
PY
