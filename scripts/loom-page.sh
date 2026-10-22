#!/bin/bash
# loom-page.sh — render a loom log's PRESENT STATE as one self-contained shareable page.
#
# Usage:
#   engine loom-page <logFile> [--out <htmlFile>] [--title <text>] [--text]
#
# THE CLAIM, stated at its true size. A loom's state of record is an append-only log of thousands
# of lines. This renders the PRESENT STATE out of it and nothing else: for each rewritten-in-place
# register it finds the LATEST occurrence and reproduces that block VERBATIM. It is a parser and a
# template — it composes no prose and summarises nothing, so the page cannot disagree with the rows
# it came from. Re-interpreting a register's table into fields would be a second place the state
# could be wrong, so the heading is parsed and the body is passed through.
#
# TWO KINDS OF BLOCK, read differently. Reading these the same way is the one error that produces a
# confidently wrong page.
#   REWRITTEN registers  🧵 Ledger · 🗳️ Boards · 📚 Docs owed · ⚖️ Rules owed · 🔓 Open claims ·
#                        🅿️ Parked · 🌊 Wave. The conductor rewrites these as state advances, so
#                        only the LATEST occurrence is current. Reading "all" of one reports a
#                        weave's history as its present state.
#   APPEND-ONLY events   💡 Decision · 📡 Relay. Every occurrence is a distinct historical event,
#                        so "latest" would show one of seventy-odd as though it were the record.
#                        These render as a COUNT plus a line-number pointer — no titles, no bodies.
#                        A count is a present-state property of the log; a title is the content of
#                        one event, which is the timeline this page deliberately does not show.
#                        `engine sweep-check` answers "decided and not rowed" temporally; this page
#                        does not duplicate it.
#
# THE PREFIX IS BOUNDED, and that bound is load-bearing. `engine log` injects a timestamp between
# `## ` and the glyph, so a log holds both `## 🧵 Ledger` and `## [2026-10-23 01:54] 🧵 Ledger` and
# an anchored `^## 🧵` sees only the unstamped minority — measured at 7 of 44 for 🧵 and 0 of 11 for
# 🌊 on one live log, where the second reading renders no section at all and looks healthy. But a
# merely loose `^## .*<glyph>` over-matches twice over: `🧑‍⚖️` contains `⚖️` as a substring, and a
# heading quoting a register name mid-line (`## ⭐ A finding — `⚖️ Rules owed` is invisible…`)
# matches too. So the prefix may hold only bracket groups and a run of known marks — never free
# prose — and the key is the glyph AND the register's name, never the glyph alone.
#
# WHAT IT COULD NOT READ IS OUTPUT, NEVER SWALLOWED. A grammar drift that gets dropped quietly
# under-reports while the page looks fine. Three readings are printed side by side:
#   instrument   bounded prefix, glyph + name, fence-aware. What the page renders.
#   control      glyph-agnostic: strip the stamp, the bracket groups and every leading non-letter,
#                then match the NAME. It names no glyph anywhere, so it cannot share a glyph
#                anchor's blind spot. Headings it finds and the instrument did not are listed as
#                drift, by line number, and are NOT rendered as registers.
#   naive        `^## <glyph>`, printed only to show how far wrong the anchored reading is.
# A register with zero occurrences renders as a loud NOT FOUND rather than an absent section.
#
# CONSERVATION. Every `## ` heading lands in exactly one bucket (fenced · register · event · drift ·
# other-glyph · plain) and the buckets must sum to the total. A partition that does not sum means a
# heading was counted twice or lost, and that is an instrument fault, not a page.
#
# Exit 0 = rendered, every register present and no drift · 3 = rendered, but a register is missing
# or a drift heading was found (a finding, not a failure) · 2 = instrument fault (unreadable log,
# an unclosed code fence, buckets that do not sum) · 1 = usage. Read the exit status DIRECTLY,
# never through a pipeline. Read-only: it never touches the log.

set -euo pipefail

LOG="${1:?usage: engine loom-page <logFile> [--out <htmlFile>] [--title <text>] [--text]}"
shift
OUT=""
TITLE=""
AS_TEXT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out)   OUT="${2:?--out needs a path}"; shift 2 ;;
    --title) TITLE="${2:?--title needs a value}"; shift 2 ;;
    --text)  AS_TEXT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Default output sits beside the log in the session's builds/ directory, which is where a loom's
# artifacts already live and what the publisher is pointed at.
if [ -z "$OUT" ] && [ "$AS_TEXT" = 0 ]; then
  OUT="$(cd "$(dirname "$LOG")" && pwd)/builds/loom-status.html"
fi

exec python3 -I - "$LOG" "$OUT" "$TITLE" "$AS_TEXT" <<'PY'
import os, re, sys, time

log_path, out_path, title_arg, as_text = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
try:
    with open(log_path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
except OSError as exc:
    print(f"loom-page: cannot read {log_path}: {exc}", file=sys.stderr)
    sys.exit(2)

STAMP = re.compile(r"^\[\d{4}-\d\d-\d\d \d\d:\d\d(?::\d\d)?\]\s*")
# Marks a conductor puts around a glyph for emphasis. An explicit set, not a character class of
# "anything non-alphanumeric": a loose run would cross an em-dash and let free prose into the prefix,
# which is what the mid-line quoted-name trap needs in order to match.
MARKS = r"[\u2B50\u26D4\u2705\u274C\u26A0\u2757\uFE0F\u200D\U0001F534\U0001F7E3\U0001F7E2\U0001F680]*"
BRACKETS = r"(?:\[[^\]]*\]\s*)*"

# (label, base codepoint, name pattern). The name is what disambiguates: 🧵 also heads
# `Thread opened` and `New thread`, 🅿️ also heads `Standing` and `Measured`, 🗳️ also heads
# `Council` — none of which is a register rewrite.
REGISTERS = [
    ("Ledger",      "\U0001F9F5", r"Ledger"),
    ("Boards",      "\U0001F5F3", r"Boards"),
    ("Docs owed",   "\U0001F4DA", r"Docs owed"),
    ("Rules owed",  "\u2696",     r"Rules owed"),
    ("Open claims", "\U0001F513", r"Open claims"),
    ("Parked",      "\U0001F17F", r"Parked"),
    ("Wave",        "\U0001F30A", r"Wave"),
]
EVENTS = [
    ("Decision", "\U0001F4A1", r"Decisions?"),
    ("Relay",    "\U0001F4E1", r"Relay"),
]

def instrument_rx(glyph, name):
    return re.compile(BRACKETS + MARKS + r"\s*" + re.escape(glyph) + r"\uFE0F?" + MARKS +
                      r"\s*" + BRACKETS + name + r"\b", re.IGNORECASE)

def control_rx(name):
    return re.compile(name + r"\b", re.IGNORECASE)

BLOCKS = [(lbl, g, n, instrument_rx(g, n), control_rx(n), "register") for lbl, g, n in REGISTERS] + \
         [(lbl, g, n, instrument_rx(g, n), control_rx(n), "event") for lbl, g, n in EVENTS]
GLYPHS = {g for _, g, _ in REGISTERS} | {g for _, g, _ in EVENTS}

def head_text(n):
    return STAMP.sub("", lines[n - 1][3:])

def control_text(n):
    """Glyph-agnostic: the heading with its stamp, bracket groups and every leading non-letter gone."""
    t = re.sub(r"^" + BRACKETS, "", head_text(n))
    return re.sub(r"^[^A-Za-z]*", "", t)

# --- Pass 1: headings outside code fences ---------------------------------------------------------
# A fence left open would swallow the rest of the log and render as a tidy page with nothing in it,
# so it is an instrument fault instead. A line that opens and closes a fence (an inline span) opens
# nothing.
headings, boundaries = [], []
fenced_headings, fenced_lines = 0, 0
fence, fence_open = False, 0
for i, line in enumerate(lines, 1):
    s = line.lstrip()
    if s.startswith("```"):
        if not fence and s.count("```") >= 2:
            continue
        fence = not fence
        if fence:
            fence_open = i
        continue
    if fence:
        fenced_lines += 1
        if line.startswith("## "):
            fenced_headings += 1
        continue
    if re.match(r"^#{1,2} ", line):
        boundaries.append(i)
    if line.startswith("## "):
        headings.append(i)
if fence:
    print(f"loom-page: code fence opened at L{fence_open} is never closed; the "
          f"{len(lines) - fence_open} lines after it were not read", file=sys.stderr)
    sys.exit(2)

# --- Pass 2: classify every heading into exactly one bucket ---------------------------------------
found = {lbl: [] for lbl, *_ in BLOCKS}
drift, other_glyph, plain = [], [], []
for n in headings:
    text, ctext = head_text(n), control_text(n)
    for lbl, _g, _nm, rx, _crx, _kind in BLOCKS:
        if rx.match(text):
            found[lbl].append(n)
            break
    else:
        hit = next((lbl for lbl, _g, _nm, _rx, crx, _k in BLOCKS if crx.match(ctext)), None)
        if hit:
            drift.append((n, hit))
        elif any(g in text for g in GLYPHS):
            other_glyph.append(n)
        else:
            plain.append(n)

recognised = sum(len(v) for v in found.values())
buckets = recognised + len(drift) + len(other_glyph) + len(plain)
if buckets != len(headings):
    print(f"loom-page: the buckets do not sum — {len(headings)} headings, "
          f"{recognised} recognised + {len(drift)} drift + {len(other_glyph)} other-glyph + "
          f"{len(plain)} plain = {buckets}", file=sys.stderr)
    sys.exit(2)

# Readings, per block: what the page renders, what a glyph-agnostic test finds, and what the
# anchored pattern would have found. The third is printed to show the gap, never to drive anything.
readings = []
for lbl, g, _nm, _rx, crx, kind in BLOCKS:
    control = sum(1 for n in headings if crx.match(control_text(n)))
    naive = sum(1 for n in headings if lines[n - 1][3:].startswith(g))
    readings.append((lbl, kind, len(found[lbl]), control, naive))

def block_body(n):
    """Heading line n's block: every line up to the next `# `/`## ` boundary, trailing blanks gone."""
    end = next((b for b in boundaries if b > n), len(lines) + 1)
    body = lines[n:end - 1]
    while body and not body[-1].strip():
        body.pop()
    return body

present = []
for lbl, _g, _nm, _rx, _crx, kind in BLOCKS:
    if kind != "register":
        continue
    occ = found[lbl]
    present.append((lbl, occ[-1] if occ else None, len(occ), block_body(occ[-1]) if occ else []))

missing = [lbl for lbl, n, _c, _b in present if n is None]
now = time.strftime("%Y-%m-%d %H:%M:%S")
stamped = sum(1 for n in headings if STAMP.match(lines[n - 1][3:]))
session = os.path.basename(os.path.dirname(os.path.abspath(log_path)))
title = title_arg or f"{session} — present state"

# --- Markdown, rendered deterministically ---------------------------------------------------------
LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
BOLD = re.compile(r"\*\*([^*]+)\*\*")
EM = re.compile(r"(?<![*\w])\*([^*\n]+)\*(?![*\w])")

def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def inline(s):
    # Code spans come out FIRST and go back in LAST, via placeholders. Rendering each backtick
    # segment on its own instead would split `**`path`**` across two segments — the opening and
    # closing markers land in different pieces, so the emphasis never matches and the page shows a
    # literal `**`. The log wraps a path in bold-around-code constantly.
    spans = []

    def stash(m):
        spans.append(m.group(1))
        return f"\x00{len(spans) - 1}\x00"

    t = re.sub(r"`([^`]*)`", stash, s)
    t = esc(t)
    t = LINK.sub(lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>', t)
    t = BOLD.sub(r"<strong>\1</strong>", t)
    t = EM.sub(r"<em>\1</em>", t)
    return re.sub(r"\x00(\d+)\x00", lambda m: f"<code>{esc(spans[int(m.group(1))])}</code>", t)

def cells(row):
    r = row.strip()
    if r.startswith("|"):
        r = r[1:]
    if r.endswith("|"):
        r = r[:-1]
    return [c.strip() for c in r.split("|")]

def render_table(rows):
    head, body = cells(rows[0]), [cells(r) for r in rows[2:]]
    out = ["<div class=scroll><table><thead><tr>" +
           "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"]
    for r in body:
        out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)

def render_list(block):
    out, sub = ["<ul>"], False
    for ln in block:
        m = re.match(r"^(\s*)[*+-]\s+(.*)$", ln)
        if not m:
            if out[-1].endswith("</li>"):
                out[-1] = out[-1][:-5] + " " + inline(ln.strip()) + "</li>"
            continue
        nested = len(m.group(1)) >= 2
        if nested and not sub:
            out.append("<ul>")
            sub = True
        elif not nested and sub:
            out.append("</ul>")
            sub = False
        out.append(f"<li>{inline(m.group(2))}</li>")
    if sub:
        out.append("</ul>")
    out.append("</ul>")
    return "".join(out)

BREAK = re.compile(r"^\s*[*+-]\s+|^\s*\||^#{1,6}\s|^\s*```")

def md(body):
    html, i, n = [], 0, len(body)
    while i < n:
        ln = body[i]
        if not ln.strip():
            i += 1
            continue
        if ln.lstrip().startswith("```"):
            i += 1
            buf = []
            while i < n and not body[i].lstrip().startswith("```"):
                buf.append(body[i])
                i += 1
            i += 1
            html.append("<pre><code>" + esc("\n".join(buf)) + "</code></pre>")
            continue
        if ln.lstrip().startswith("|") and i + 1 < n and re.match(r"^\s*\|[\s:|-]+\|\s*$", body[i + 1]):
            rows = []
            while i < n and body[i].lstrip().startswith("|"):
                rows.append(body[i])
                i += 1
            html.append(render_table(rows))
            continue
        if re.match(r"^\s*[*+-]\s+", ln):
            blk = []
            while i < n and (re.match(r"^\s*[*+-]\s+", body[i]) or
                             (body[i].startswith("    ") and body[i].strip())):
                blk.append(body[i])
                i += 1
            html.append(render_list(blk))
            continue
        m = re.match(r"^(#{3,6})\s+(.*)$", ln)
        if m:
            lvl = len(m.group(1))
            html.append(f"<h{lvl}>{inline(m.group(2))}</h{lvl}>")
            i += 1
            continue
        buf = []
        while i < n and body[i].strip() and not BREAK.match(body[i]):
            buf.append(body[i].strip())
            i += 1
        html.append("<p>" + inline(" ".join(buf)) + "</p>")
    return "\n".join(html)

# --- The plain reading, which is also what the tests assert on -------------------------------------
if as_text:
    print(f"loom-page {log_path} @ {now}")
    print(f"{len(lines)} lines · {len(headings)} '## ' headings (stamped {stamped}, unstamped "
          f"{len(headings) - stamped}) · {fenced_headings} fenced headings excluded")
    print("claim: PRESENT STATE only. A rewritten register is read at its LATEST occurrence; an "
          "append-only event is counted, never rendered as a timeline.")
    print(f"buckets: {recognised} recognised + {len(drift)} drift + {len(other_glyph)} other-glyph + "
          f"{len(plain)} plain = {buckets} of {len(headings)}")
    print("READINGS  block / kind / instrument / control(glyph-agnostic) / naive(^## glyph)")
    for lbl, kind, inst, control, naive in readings:
        flag = "  <-- MISSING" if kind == "register" and inst == 0 else ""
        gap = "" if naive == inst else f"  [anchored reading would see {naive} of {inst}]"
        print(f"  {lbl:12s} {kind:8s} instrument={inst:3d} control={control:3d} naive={naive:3d}{gap}{flag}")
    for lbl, n, count, body in present:
        print()
        if n is None:
            print(f"=== {lbl}: NOT FOUND — no occurrence in this log. This is output, not an absent section.")
            continue
        print(f"=== {lbl} — latest of {count}, at L{n}")
        print(lines[n - 1])
        for ln in body:
            print(ln)
    print()
    for lbl, _g, _nm, _rx, _crx, kind in BLOCKS:
        if kind == "event":
            occ = found[lbl]
            where = f"most recent at L{occ[-1]}" if occ else "none"
            print(f"EVENT {lbl}: {len(occ)} occurrences, {where} (count and pointer only — not a timeline)")
    print()
    if drift:
        print(f"DRIFT — {len(drift)} headings name a block but carry no recognised glyph for it. "
              f"Not rendered as registers:")
        for n, lbl in drift:
            print(f"  L{n}  [{lbl}]  {head_text(n).strip()[:100]}")
    else:
        print("DRIFT — none.")
    print(f"OTHER-GLYPH — {len(other_glyph)} headings carry a block glyph in a shape this renderer "
          f"does not read as a block.")
    for n in other_glyph:
        print(f"  L{n}  {head_text(n).strip()[:100]}")
    sys.exit(3 if (missing or drift) else 0)

# --- The page --------------------------------------------------------------------------------------
P = []
w = P.append
w("<!doctype html><html lang=en><head><meta charset=utf-8>")
w('<meta name=viewport content="width=device-width,initial-scale=1">')
w(f"<title>{esc(title)}</title>")
w("""<style>
:root{--bg:#fbfaf7;--fg:#1b1a17;--dim:#6a655c;--line:#e3dfd6;--card:#fff;--accent:#7a5c2e;
--warn:#8a2a1f;--warnbg:#fdf1ef;--code:#f3f0e9;--mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#15140f;--fg:#ece8df;
--dim:#9a948a;--line:#2e2b24;--card:#1c1a15;--accent:#d8b776;--warn:#ff9a88;--warnbg:#2a1a16;--code:#23201a}}
:root[data-theme=dark]{--bg:#15140f;--fg:#ece8df;--dim:#9a948a;--line:#2e2b24;--card:#1c1a15;
--accent:#d8b776;--warn:#ff9a88;--warnbg:#2a1a16;--code:#23201a}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 ui-serif,Georgia,serif;
-webkit-text-size-adjust:100%}
.wrap{max-width:62rem;margin:0 auto;padding:2.2rem 16px 5rem}
h1{font-size:1.65rem;line-height:1.2;margin:0 0 .3rem}
h2{font-size:1.12rem;margin:2.4rem 0 .5rem;letter-spacing:.01em}
h3,h4,h5,h6{font-size:1rem;margin:1.2rem 0 .4rem}
.meta,.note{color:var(--dim);font-size:.82rem;line-height:1.5}
.scope{border-left:3px solid var(--accent);padding:.1rem 0 .1rem .85rem;margin:1.1rem 0 1.8rem}
.scope p{margin:.35rem 0;font-size:.9rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:7px;padding:1rem 1.1rem;
margin:.6rem 0 1.4rem;overflow-wrap:break-word}
.card>:first-child{margin-top:0}.card>:last-child{margin-bottom:0}
.src{font:.74rem/1.4 var(--mono);font-variant-ligatures:none;color:var(--dim);
margin:.1rem 0 .5rem;word-break:break-all}
.hd{font-weight:600;margin:.1rem 0 .7rem;font-size:1rem}
.warn{border-color:var(--warn);background:var(--warnbg);color:var(--warn)}
.scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
table{border-collapse:collapse;width:100%;font-size:.84rem;min-width:30rem}
th,td{border:1px solid var(--line);padding:.35rem .5rem;text-align:left;vertical-align:top}
th{background:var(--code);font-weight:600}
code{font:.86em var(--mono);font-variant-ligatures:none;background:var(--code);
padding:.08em .32em;border-radius:3px}
pre{background:var(--code);padding:.7rem .8rem;border-radius:5px;overflow-x:auto}
pre code{background:none;padding:0;font-size:.78rem;line-height:1.45}
ul{margin:.4rem 0;padding-left:1.25rem}li{margin:.22rem 0}
a{color:var(--accent)}
details{margin:.8rem 0;border:1px solid var(--line);border-radius:6px;padding:.5rem .8rem;
background:var(--card)}
summary{cursor:pointer;font-size:.86rem;color:var(--dim)}
.rows{font:.76rem/1.5 var(--mono);font-variant-ligatures:none;margin:.6rem 0 0}
.rows div{padding:.1rem 0;word-break:break-word}
@media(max-width:560px){.wrap{padding-top:1.4rem}h1{font-size:1.32rem}table{font-size:.78rem}}
</style></head><body><div class=wrap>""")

w(f"<h1>{esc(title)}</h1>")
w(f'<p class=meta>Rendered {now} from <span class=src>{esc(log_path)}</span></p>')
w(f'<p class=meta>{len(lines)} lines · {len(headings)} <code>## </code> headings '
  f'({stamped} stamped, {len(headings) - stamped} unstamped) · {fenced_headings} inside code fences, excluded</p>')

w('<div class=scope>')
w("<p><strong>What this is.</strong> The weave's present state, read mechanically out of its log. "
  "For each rewritten-in-place register the renderer takes the <em>latest</em> occurrence and "
  "reproduces that block verbatim. Nothing on this page is composed, summarised or re-worded, so "
  "it cannot disagree with the rows it came from.</p>")
w("<p><strong>What it is not.</strong> Not the event timeline. Append-only events "
  "(<code>💡 Decision</code>, <code>📡 Relay</code>) appear as counts with a line-number pointer and "
  "nothing more — a count is a property of the log as it stands, while an event's text is history. "
  "Not a judgement either: no verdicts, no recommendations, no provenance claims beyond "
  "<em>this is what the log says</em>.</p>")
w("<p><strong>Who it is for.</strong> Anyone about to take a decision on this weave, including the "
  "conductor at a <code>/next</code> gate. Every figure is stale the moment the log is written to "
  "again, which is why the render time is at the top.</p>")
w('</div>')

if missing:
    w(f'<div class="card warn"><strong>⛔ {len(missing)} register'
      f'{"" if len(missing) == 1 else "s"} not found in this log:</strong> '
      f'{esc(" · ".join(missing))}. Reported rather than left as an absent section — an under-reading '
      f'that renders as silence is indistinguishable from a healthy page.</div>')

w("<h2>Present state</h2>")
for lbl, n, count, body in present:
    if n is None:
        w(f'<div class="card warn"><div class=hd>{esc(lbl)} — NOT FOUND</div>'
          f'<p class=note>No occurrence in this log.</p></div>')
        continue
    w('<div class=card>')
    w(f'<div class=hd>{inline(head_text(n).strip())}</div>')
    w(f'<p class=src>{esc(lbl)} · latest of {count} · L{n}</p>')
    w(md(body) if body else '<p class=note>The block has a heading and no body.</p>')
    w('</div>')

w("<h2>Append-only events</h2>")
w('<p class=note>Counted, not rendered. Every occurrence is a distinct historical event, so a '
  '&ldquo;latest&rdquo; reading would show one of many as though it were the record.</p>')
w('<div class=card><div class=rows>')
for lbl, _g, _nm, _rx, _crx, kind in BLOCKS:
    if kind != "event":
        continue
    occ = found[lbl]
    where = f"most recent at L{occ[-1]}" if occ else "none in this log"
    w(f'<div>{esc(lbl)} — <strong>{len(occ)}</strong> occurrences · {where}</div>')
w('</div></div>')

w("<h2>What the renderer could not read</h2>")
w('<p class=note>Output, never swallowed: a grammar drift that is dropped quietly under-reports '
  'while the page looks fine.</p>')
if drift:
    w(f'<div class="card warn"><div class=hd>{len(drift)} heading'
      f'{"" if len(drift) == 1 else "s"} name a block but carry no recognised glyph for it</div>'
      f'<p class=note>Not rendered as registers. Each is a candidate grammar drift, found by a '
      f'glyph-agnostic control that names no glyph anywhere and so cannot share a glyph anchor&rsquo;s '
      f'blind spot.</p><div class=rows>')
    for n, lbl in drift:
        w(f'<div>L{n} [{esc(lbl)}] {esc(head_text(n).strip()[:160])}</div>')
    w('</div></div>')
else:
    w('<div class=card><p class=note>No drift: every heading naming a block also carried that '
      'block&rsquo;s glyph in a shape the instrument reads.</p></div>')

w(f'<details><summary>{len(other_glyph)} headings carry a block glyph in a shape this renderer does '
  f'not read as a block — e.g. <code>🧵 Thread opened</code>, <code>🅿️ Standing</code>, '
  f'<code>🗳️ Council</code>. Expected, and listed in full.</summary><div class=rows>')
for n in other_glyph:
    w(f'<div>L{n} {esc(head_text(n).strip()[:160])}</div>')
w('</div></details>')

w("<h2>Three readings of the same log</h2>")
w('<p class=note><strong>instrument</strong> is what this page renders: a bounded prefix, then the '
  'glyph <em>and</em> the block&rsquo;s name. <strong>control</strong> is glyph-agnostic — it strips '
  'the stamp, the bracket groups and every leading non-letter, then matches the name, naming no glyph '
  'at all. <strong>naive</strong> is <code>^## &lt;glyph&gt;</code>, shown only to size the trap: '
  '<code>engine log</code> injects a timestamp between <code>## </code> and the glyph, so the '
  'anchored pattern sees the unstamped minority and renders a confident under-count.</p>')
w('<div class=scroll><table><thead><tr><th>block</th><th>kind</th><th>instrument</th>'
  '<th>control</th><th>naive</th></tr></thead><tbody>')
for lbl, kind, inst, control, naive in readings:
    cls = ' style="color:var(--warn)"' if (kind == "register" and inst == 0) else ""
    w(f'<tr{cls}><td>{esc(lbl)}</td><td>{kind}</td><td>{inst}</td><td>{control}</td>'
      f'<td>{naive}</td></tr>')
w('</tbody></table></div>')
w(f'<p class=note>Buckets reconcile: {recognised} recognised + {len(drift)} drift + '
  f'{len(other_glyph)} other-glyph + {len(plain)} plain = {buckets}, against {len(headings)} '
  f'<code>## </code> headings. Every heading lands in exactly one bucket, so a heading cannot be '
  f'counted twice or lost without this sum breaking — the renderer exits 2 rather than render a '
  f'page when it does.</p>')

w('<p class=meta>Generated by <code>engine loom-page</code> — a parser and a template. Read it at '
  'the top of a decision, and re-render it rather than trusting a copy.</p>')
w("</div></body></html>")

html = "\n".join(P)
try:
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(html)
except OSError as exc:
    print(f"loom-page: cannot write {out_path}: {exc}", file=sys.stderr)
    sys.exit(2)

print(f"loom-page: {len(lines)} lines · {len(headings)} headings · {recognised} recognised · "
      f"{len(drift)} drift · {len(missing)} register(s) missing", file=sys.stderr)
for lbl, n, count, _b in present:
    print(f"  {lbl:12s} " + (f"latest of {count} at L{n}" if n else "NOT FOUND"), file=sys.stderr)
print(out_path)
sys.exit(3 if (missing or drift) else 0)
PY
