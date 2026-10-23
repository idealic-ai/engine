#!/bin/bash
# open-asks.sh — list lane asks with no answer yet, across every *_LOG.md under the given roots.
#   engine open-asks <sessionDir> [--also <dir>]...
#
# An ask is a heading "## … [TAG] ❓ Ask <id>: …"; the tag is the bracket directly before the emoji,
# so the timestamp bracket `engine log` injects stays out of it. It is closed by
# "## … [TAG] ✅ Answered <id>" later in the same log, or anywhere in a LOOM_LOG.md. An ask written
# after its answer in the same log reopens it. Ids match case-insensitively and end at punctuation;
# U+FE0F after either emoji is ignored. Headings inside a code fence are examples, not asks.
#
# Output: one "OPEN <heading> · logpath=<path>" or "UNPARSED <heading> · logpath=<path>" row per
# finding (read logpath as everything after "logpath=" to end of line), then a verdict line.
# Exit 0 = none open · 3 = at least one open or unparsed ask · 2 = instrument fault (bad arguments,
# an unreadable directory or file). Symlinked roots and log files are followed; a file reached by
# two paths is read once.
exec python3 - "$@" <<'PY'
import os, re, sys

def fault(msg):
    print(f"open-asks: {msg}", file=sys.stderr)
    sys.exit(2)

USAGE = "usage: engine open-asks <sessionDir> [--also <dir>]..."
args, roots = sys.argv[1:], []
if not args or args[0].startswith("-"):
    fault(USAGE)
roots.append(args.pop(0))
while args:
    a = args.pop(0)
    if a == "--also" and args and not args[0].startswith("-"):
        roots.append(args.pop(0))
    else:
        fault(f"bad argument: {a} ({USAGE})")
for r in roots:
    if not os.path.isdir(r):
        fault(f"not a directory: {r}")

errors, logs, seen = [], [], set()
for root in roots:
    for d, _, files in os.walk(os.path.abspath(root), onerror=lambda e: errors.append(f"{e.filename}: {e.strerror}")):
        for f in sorted(files):
            if not f.endswith("_LOG.md"):
                continue
            p = os.path.join(d, f)
            try:
                st = os.stat(p)
            except OSError as e:
                errors.append(f"{p}: {e.strerror}")
                continue
            if (st.st_dev, st.st_ino) not in seen:
                seen.add((st.st_dev, st.st_ino))
                logs.append(p)

HEAD = re.compile(r"^#{1,6} ")
ASK = re.compile(r"\[([^\[\]]+)\] ❓ Ask (\w[\w-]*)")
ANS = re.compile(r"\[([^\[\]]+)\] ✅ Answered (\w[\w-]*)")

def headings(path):
    fenced = False
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n").replace("\ufe0f", "")
                if line.lstrip().startswith(("```", "~~~")):
                    fenced = not fenced
                elif not fenced and HEAD.match(line):
                    yield line
    except OSError as e:
        errors.append(f"{path}: {e.strerror}")

def is_loom(p):
    return os.path.basename(p) == "LOOM_LOG.md"

per_log, loom_answers = {}, set()
for p in logs:
    events = []
    for h in headings(p):
        m = ASK.search(h)
        if m:
            events.append(("ask", (m.group(1), m.group(2).lower()), h))
        elif "❓ Ask" in h:
            events.append(("unparsed", None, h))
        for a in ANS.finditer(h):
            key = (a.group(1), a.group(2).lower())
            events.append(("ans", key, h))
            if is_loom(p):
                loom_answers.add(key)
    per_log[p] = events

rows, n_open, n_unparsed = [], 0, 0
for p, events in per_log.items():
    asks, order = {}, []
    for kind, key, h in events:
        if kind == "unparsed":
            rows.append(f"UNPARSED {h} · logpath={p}")
            n_unparsed += 1
        elif kind == "ask":
            if key not in asks:
                order.append(key)
            asks[key] = h
        elif key in asks:
            asks[key] = None
    for key in order:
        if asks[key] is None or (not is_loom(p) and key in loom_answers):
            continue
        rows.append(f"OPEN {asks[key]} · logpath={p}")
        n_open += 1

for r in rows:
    print(r)
if errors:
    for e in errors:
        print(f"open-asks: unreadable: {e}", file=sys.stderr)
    fault(f"{len(errors)} path(s) could not be read, so this reading is incomplete")
if not logs:
    print(f"open-asks: no *_LOG.md found under {', '.join(roots)}", file=sys.stderr)
print(f"open asks: {n_open} · unparsed: {n_unparsed} · logs read: {len(logs)}")
sys.exit(3 if n_open or n_unparsed else 0)
PY
