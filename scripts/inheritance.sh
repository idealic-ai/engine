#!/bin/bash
# inheritance.sh — print one loom's blocks from the sessions root's LOOM_INHERITANCE.md.
#   engine inheritance show <seat|session-dir> [--latest] [--raw] [--file <path>]
#   engine inheritance list [--file <path>]
#
# Many looms append to one shared file, and a successor needs only its own loom's rows. `show`
# prints that loom's chunks in file order (newest last), each under a marker naming its source
# lines and whether it is a block or a delta; `--latest` prints the newest block and the chunks
# after it; `--raw` drops the markers and the footers. After the chunks, `show` lists the lines
# OUTSIDE them that name one of the loom's seats or sessions ("named elsewhere"): rows a writer put
# inside another loom's chunk, which no heading rule can find. `list` prints one `owner` line per
# loom, then a footer of figures that are non-zero when the file holds a shape the reader is unsure
# of (see the footer's own words).
#
# Boundaries are the ones skills/loom/assets/TEMPLATE_LOOM_INHERITANCE.md defines ("Blocks and
# deltas"), and the legacy shapes the file already holds:
#   * A `# ` heading always opens a chunk. Its owner is the first dated session name in it
#     (`2026_10_29_META_ENGINE`, bare or inside a path) and the first seat it names as owner. A
#     `# ` heading naming neither (`# ⏩ DELTA`, `# ⛔ CORRECTION`) continues the previous `# `
#     owner as a delta; the file's first block, if ownerless, takes the first session in its body.
#   * A `## ` or `### ` heading opens a chunk when it names a dated session, or names an owner seat
#     AND carries a hand-over word (addendum, delta, hand-over, inheritance, supersedes, rows,
#     block, written, refresh). A register heading (a template emoji 🧵 🗳️ 📚 ⚖️ 🔓 ❓ 📨 ⚙️, or
#     a register name such as Threads, Open claims, Seat handovers) never opens one.
#   * A heading that opens nothing is a register of the chunk above. A register-shaped heading at
#     the level of an open `## `/`### ` delta stays in that delta; any other heading at that level
#     closes it, and the enclosing chunk resumes (show's footer says when that hands the line to a
#     different owner).
#   * A seat is a RELATION, never the owner, when with/to/from/by/via/for/and stands directly
#     before it, or parent/formerly/was/now/"on behalf of"/an arrow stands earlier in its clause.
#   * Who is one loom: a chunk links its session to its owner seat; a heading with an owner seat and
#     no session takes the session its first 3 body lines name beside owner/session/loom. Only a
#     heading that opens a chunk can rename: a seat right after formerly/renamed/was/now/becoming
#     joins the chunk's owner, and `A → B` is a rename only when the heading also says rename,
#     formerly or becomes (elsewhere an arrow is a direction). A loom is everything so linked, so a
#     renamed seat, its old name and every session it ran in reach the same rows. `--latest` is the
#     newest block in the subject's own chain: the session given, or the sessions the given seat
#     headed a chunk with; a seat reached only through renames must reach one session, else exit 2.
#   * Kind: a heading saying addendum, delta or correction is a delta; any other chunk is a block.
#   * Headings inside a fence (``` or ~~~, matched by character and length) are text. A fence still
#     open at the end of the file is an instrument fault: every heading after it would be lost.
# The file defaults to the parent of a session-dir subject, else the engine's resolved sessions dir.
#
# Exit 0 = printed · 3 = the subject is named nowhere in the file · 2 = instrument fault (bad
# arguments, no file, an unclosed fence, or a subject the file names but cannot attribute a chunk to).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT=""
if [ -f "$SCRIPT_DIR/lib.sh" ]; then
  # shellcheck source=/dev/null
  DEFAULT_ROOT=$( (source "$SCRIPT_DIR/lib.sh" >/dev/null 2>&1; resolve_sessions_dir) 2>/dev/null || true)
fi
export INHERITANCE_DEFAULT_ROOT="$DEFAULT_ROOT"
exec python3 - "$@" <<'PY'
import os, re, sys
from collections import OrderedDict

USAGE = ("usage: engine inheritance show <seat|session-dir> [--latest] [--raw] [--file <path>]\n"
         "       engine inheritance list [--file <path>]")

def fault(msg):
    print(f"inheritance: {msg}", file=sys.stderr)
    sys.exit(2)

args = sys.argv[1:]
if not args or args[0] not in ("show", "list"):
    fault(f"unknown or missing verb ({USAGE})")
verb, args = args[0], args[1:]
subject, latest, raw, path = None, False, False, None
while args:
    a = args.pop(0)
    if a == "--latest": latest = True
    elif a == "--raw": raw = True
    elif a == "--file":
        if not args: fault("--file needs a path")
        path = args.pop(0)
    elif a.startswith("-"): fault(f"bad argument: {a} ({USAGE})")
    elif subject is None and verb == "show": subject = a
    else: fault(f"bad argument: {a} ({USAGE})")
if verb == "show" and not subject:
    fault(f"show needs a seat or a session dir ({USAGE})")
if path is None:
    if subject and os.path.isdir(subject):
        path = os.path.join(os.path.dirname(os.path.abspath(subject.rstrip("/"))), "LOOM_INHERITANCE.md")
    elif os.environ.get("INHERITANCE_DEFAULT_ROOT"):
        path = os.path.join(os.environ["INHERITANCE_DEFAULT_ROOT"], "LOOM_INHERITANCE.md")
    else:
        fault("no file: pass --file <path>")
if not os.path.isfile(path):
    fault(f"no such file: {path}")
try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
except OSError as e:
    fault(f"{path}: {e.strerror}")
if lines and lines[-1] == "":
    lines.pop()
N = len(lines)
base = os.path.basename(path)

SESSION = re.compile(r"(?<![A-Za-z0-9])(\d{4}_\d{2}_\d{2}_[A-Z0-9][A-Z0-9_]*[A-Z0-9])")
SEAT = re.compile(r"(?<![\w/:.\-])([a-z]+):([A-Za-z][A-Za-z0-9_\-]*)")
DIRECT = re.compile(r"\b(?:with|to|from|by|via|for|and)\s*[`\"'(]*\s*$", re.I)
CLAUSE_REL = re.compile(r"\bparent\b|\bformerly\b|\bwas\b|\bnow\b|\bon behalf of\b|→|->", re.I)
SEP = re.compile(r"[,;()\[\]—–|]|:\s")
ARROW = re.compile(r"[\s`\"'(,]*(?:→|->)[\s`\"'(]*")
RENAME_SAID = re.compile(r"\brenam|\bformerly\b|\bbecom", re.I)
RENAME_WORD = re.compile(r"\b(?:formerly|renamed(?:\s+(?:to|from))?|was|now|becoming|becomes)\s*[`\"'(]*\s*$", re.I)
CUE = re.compile(r"addend|delta|hand-?over|inheritance|supersed|\brows\b|\bblock\b|written|refresh", re.I)
DELTA = re.compile(r"addend|\bdelta\b|correction", re.I)
REGISTER = re.compile(r"^[\W_]*(?:threads|asks\b|lane asks|open claims|operator asks|docs owed|rules owed|"
                      r"seat handovers|standing|re-?measure|read first|renames|landed|in flight|cleanup owed)", re.I)
REG_EMOJI = ("🧵", "🗳", "📚", "⚖", "🔓", "❓", "📨", "⚙", "♻", "🔴", "🔁", "✅", "🔨")
BODY_OWNER = re.compile(r"\b(?:owner|session|loom)\b", re.I)
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
STAMP = re.compile(r"^\[\d{4}-\d{2}-\d{2}[^\]]*\]\s*")
FENCE = re.compile(r"^\s*(?:>\s*)*(`{3,}|~{3,})(.*)$")

def seat_name(m):
    return f"{m.group(1)}:{m.group(2)}".lower()

def parse(txt):
    """-> (session, owner seat, renames) for one heading's text. A rename is (a, b), where a None
    means "this chunk's session". Only a heading that opens a chunk contributes its renames."""
    s = SESSION.search(txt)
    owner, renames, prev = None, [], None
    said = RENAME_SAID.search(txt)
    for m in SEAT.finditer(txt):
        seat, before = seat_name(m), txt[:m.start()]
        clause = SEP.split(before)[-1]
        if prev and said and ARROW.fullmatch(txt[prev[1]:m.start()]):
            renames.append((prev[0], seat))          # "A → B" in a heading that says rename/formerly/becomes
        elif RENAME_WORD.search(before):
            renames.append((owner, seat))            # "B, formerly A" / "(… now B)": links to this chunk's owner
        if owner is None and not DIRECT.search(before) and not CLAUSE_REL.search(clause):
            owner = seat
        prev = (seat, m.end())
    return (s.group(1) if s else None), owner, renames

def register_shaped(txt):
    t = txt.lstrip()
    return t.startswith(REG_EMOJI) or bool(REGISTER.match(t))

# Pass 1: headings outside fences; a fence closes on its own character at its own length or more.
heads, fence = [], None
for i, ln in enumerate(lines):
    m = FENCE.match(ln)
    if fence:
        if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1] and not m.group(2).strip():
            fence = None
        continue
    if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
        fence = (m.group(1)[0], len(m.group(1)), i)
        continue
    h = HEADING.match(ln)
    if h:
        heads.append((i, len(h.group(1)), STAMP.sub("", h.group(2))))
if fence:
    fault(f"{path}:{fence[2] + 1}: a {fence[0] * fence[1]} fence opened here is never closed, so every "
          f"heading after it would be read as text; close it, then read again")
head_at = {i: (lvl, txt) for i, lvl, txt in heads}

def body_session(i):
    """The session a chunk's first 3 non-blank body lines name beside owner/session/loom."""
    seen = 0
    for j in range(i + 1, N):
        if j in head_at or seen >= 3: break
        if not lines[j].strip(): continue
        seen += 1
        s = SESSION.search(lines[j])
        if s and BODY_OWNER.search(lines[j][:s.start()]):
            return s.group(1)
    return None

# Union-find over seats and sessions: one loom is everything linked.
parent = {}
def find(x):
    parent.setdefault(x, x)
    while parent[x] != x:
        parent[x] = parent[parent[x]]; x = parent[x]
    return x
def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb: parent[rb] = ra

# Pass 2: chunks. Lines are attributed to the top of a stack of open chunks.
PRE = {"owner": "(preamble)", "session": None, "seat": None, "kind": "block", "level": 0, "start": 0}
chunks, owner_line, stack, last_l1, cut, pairs = [], [None] * N, [], None, [], set()
for i in range(N):
    if i in head_at and head_at[i][0] <= 3:
        lvl, txt = head_at[i]
        sess, seat, renames = parse(txt)
        opens = None
        if lvl == 1:
            kind = "delta" if DELTA.search(txt) else "block"
            if seat and not sess: sess = body_session(i)
            if not sess and not seat and last_l1 is None:
                for j in range(i + 1, min(N, i + 15)):
                    if j in head_at: break
                    s = SESSION.search(lines[j])
                    if s: sess = s.group(1); break
            if not sess and not seat:
                if last_l1: sess, seat = last_l1["session"], last_l1["seat"]
                kind = "delta"
            opens = (sess, seat, kind)
        elif not register_shaped(txt) and (sess or (seat and CUE.search(txt))):
            if seat and not sess: sess = body_session(i)
            opens = (sess, seat, "delta" if DELTA.search(txt) else "block")
        if lvl == 1:
            stack = []
        elif opens:
            while stack and stack[-1]["level"] >= lvl and stack[-1]["level"] > 1:
                stack.pop()
        elif not (stack and stack[-1]["level"] == lvl and register_shaped(txt)):
            popped = None
            while stack and stack[-1]["level"] >= lvl and stack[-1]["level"] > 1:
                popped = stack.pop()
            if popped:
                cut.append((popped, i))
        if opens:
            sess, seat, kind = opens
            if sess and seat:
                union(sess, seat); pairs.add((sess, seat))
            own = sess or seat or "(unowned)"
            find(own)
            for a, b in renames:
                a = a or own
                if a != b: union(a, b)
            c = {"owner": own, "session": sess, "seat": seat, "kind": kind, "level": lvl,
                 "heading": lines[i], "start": i}
            chunks.append(c)
            stack.append(c)
            if lvl == 1: last_l1 = c
    top = stack[-1] if stack else PRE
    if top is PRE and PRE not in chunks:
        chunks.insert(0, PRE)
    owner_line[i] = top

def loom(c):
    return None if c is PRE else find(c["owner"])

def segments(chunk):
    segs, a = [], None
    for i in range(chunk["start"], N):
        if owner_line[i] is chunk:
            if a is None: a = i
        elif a is not None:
            segs.append((a, i - 1)); a = None
    if a is not None: segs.append((a, N - 1))
    return segs

def size(chunk):
    return sum(b - a + 1 for a, b in segments(chunk))

by_loom = OrderedDict()
for c in chunks:
    by_loom.setdefault(loom(c), []).append(c)
members = {}
for x in list(parent):
    members.setdefault(find(x), set()).add(x)

def names(root):
    ms = members.get(root, {root})
    return sorted(m for m in ms if SESSION.fullmatch(m)), sorted(m for m in ms if not SESSION.fullmatch(m))

def key_of(root, cs):
    """The newest session the loom wrote under, else its newest seat."""
    for c in reversed(cs):
        if c["session"]: return c["session"]
    for c in reversed(cs):
        if c["seat"]: return c["seat"]
    return root

def short(c):
    return "preamble" if c is PRE else c["owner"]

if verb == "list":
    sessionless, multi = 0, []
    for root, cs in by_loom.items():
        if root is None:
            print(f"(preamble)  lines={sum(size(c) for c in cs)}")
            continue
        sessions, seats = names(root)
        if not sessions: sessionless += 1
        if len(sessions) > 1: multi.append(key_of(root, cs))
        blocks = [c for c in cs if c["kind"] == "block"]
        tail = cs[cs.index(blocks[-1]):] if blocks else cs
        segs = [s for c in tail for s in segments(c)]
        lat = f":{segs[0][0] + 1}-{segs[-1][1] + 1}" if segs else "-"
        print(f"owner {key_of(root, cs)}  sessions={','.join(sessions) or '-'}  seats={','.join(seats) or '-'}  "
              f"blocks={len(blocks)} deltas={len(cs) - len(blocks)}  lines={sum(size(c) for c in cs)}  "
              f"latest={lat} ({len(tail)} chunk(s), {sum(size(c) for c in tail)} lines)")
    owners = sum(1 for r in by_loom if r is not None)
    l1 = sum(1 for _, lvl, _ in heads if lvl == 1)
    foreign = sum(1 for p, i in cut if loom(p) != loom(owner_line[i]))
    print(f"{base}: {N} lines · level-1 sections: {l1} · owners: {owners} · owners with no session: "
          f"{sessionless} · owners over more than one session: {len(multi)}"
          f"{' (' + ', '.join(multi) + ')' if multi else ''} · deltas closed into another owner by a plain heading: {foreign}")
    sys.exit(0)

# show
key = subject.rstrip("/")
if "/" in key: key = os.path.basename(key)
if not SESSION.fullmatch(key): key = key.lower()
root = find(key) if key in parent else None
cs = by_loom.get(root, []) if root else []
if not cs:
    pat = re.compile(r"(?<![\w/:.\-])" + re.escape(key) + r"(?![A-Za-z0-9_])", 0 if SESSION.fullmatch(key) else re.I)
    hits = [i + 1 for i, ln in enumerate(lines) if pat.search(ln)]
    if hits:
        shown = ", ".join(f":{h}" for h in hits[:12]) + (f" and {len(hits) - 12} more" if len(hits) > 12 else "")
        print(f"inheritance: {subject} (key {key}) owns no chunk in {path}, but the file names it at {shown}. "
              f"Its rows may sit under another owner: read those lines (`engine inheritance list` names the owners)",
              file=sys.stderr)
        sys.exit(2)
    print(f"inheritance: no block for {subject} (key {key}) in {path}, and the file never names it; "
          f"`engine inheritance list` names the owners", file=sys.stderr)
    sys.exit(3)
mine = set(id(c) for c in cs)
if latest:
    # Stay in the subject's own session chain: the session it names, or the sessions its seat
    # headed a chunk with. A loom reached only through renames must have one session to choose.
    lsess = sorted({c["session"] for c in cs if c["session"]})
    own = {key} if SESSION.fullmatch(key) else {s for s, t in pairs if t == key}
    if not own:
        if len(lsess) > 1:
            print(f"inheritance: {subject} reaches {', '.join(lsess)} only through renames, so --latest cannot "
                  f"choose one; run show with the session name you inherit from", file=sys.stderr)
            sys.exit(2)
        own = set(lsess)
    chain = [c for c in cs if c["session"] in own or not c["session"]]
    blocks = [c for c in chain if c["kind"] == "block"]
    every = [c for c in cs if c["kind"] == "block"]
    if every and blocks and every[-1] is not blocks[-1]:
        print(f"inheritance: this loom spans {', '.join(lsess)}; --latest kept to {', '.join(sorted(own))}, and "
              f"{every[-1]['session'] or every[-1]['seat']} has a newer block at :{every[-1]['start'] + 1}",
              file=sys.stderr)
    cs = chain[chain.index(blocks[-1]):] if blocks else chain
printed = 0
runs = sorted((a, b, n, c) for c in cs for n, (a, b) in enumerate(segments(c)))
for a, b, n, c in runs:
    if not raw:
        print(f"==> {base}:{a + 1}-{b + 1} {c['kind']}{' (continued)' if n else ''} · session={c['session'] or '-'} seat={c['seat'] or '-'}")
    for i in range(a, b + 1):
        print(lines[i])
    printed += b - a + 1
if raw:
    sys.exit(0)
sessions, seats = names(root)
lk = key_of(root, by_loom[root])
print(f"==> {lk}: {len(cs)} chunk(s), {printed} of {N} lines of {path} · sessions={','.join(sessions) or '-'} "
      f"seats={','.join(seats) or '-'}")
for p, i in cut:
    if id(p) in mine and loom(owner_line[i]) != root:
        print(f"==> note: {base}:{i + 1} `{lines[i][:80]}` closed this loom's delta at :{p['start'] + 1} and was read "
              f"as {short(owner_line[i])}'s. If it is this loom's, write it at one level deeper or as a register heading")
toks = sessions + seats
tok_re = re.compile(r"(?<![\w/:.\-])(?:" + "|".join(re.escape(t) for t in toks) + r")(?![A-Za-z0-9_])", re.I)
hits = [i for i in range(N) if id(owner_line[i]) not in mine and tok_re.search(lines[i])]
if hits:
    print(f"==> named elsewhere: {len(hits)} line(s) outside this loom's chunks name {', '.join(toks)}. "
          f"A row written inside another loom's chunk is one of these (newest first):")
    for i in reversed(hits[-12:]):
        print(f"  {base}:{i + 1} [{short(owner_line[i])}] {lines[i].strip()[:110]}")
    if len(hits) > 12:
        print(f"  … and {len(hits) - 12} older; grep -n the file for the rest")
PY
