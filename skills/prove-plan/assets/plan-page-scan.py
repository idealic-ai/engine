#!/usr/bin/env python3
"""Mechanical half of /prove-plan's route gate (P1's vague-check phrases, P2, P3 and the scope
line), run over the composed builds/<slug>_PLAN.html. Stdlib only; run with `python3 -I`.

    plan-page-scan.py done  <page.html>   P1 phrases + P2: nothing is presented as done
    plan-page-scan.py graph <page.html>   P3: the drawn graph is a DAG and the cards follow it
    plan-page-scan.py scope <page.html>   the scope line sits above the graph, with as-of and out-of-scope
    plan-page-scan.py all   <page.html>   all three
    plan-page-scan.py --print-words       the done-words P2 searches for, one per line
    plan-page-scan.py --print-marks       the marks this scanner reads, one per line

Exit 0 when clean, 1 on a finding, 2 on a usage or read error. The page is scanned, never printed,
so the orchestrator can run this without reading the HTML into its context.

Marks (the brief's item 4 must name exactly these; the test compares the two):
  data-route            the route sentence (at most one)
  data-scope            the scope line (exactly one, above the flowgraph)
  data-legend           the colour legend (at most one)
  data-starting-point   work the source already records as complete (at most one)
  data-card="<id>"      a step card, in page order
  data-acceptance       an acceptance cell, inside a card, text starting "Passes when:"
  data-check            a check cell, inside a card, text starting "Checked by:"
  data-step="<id>"      a step node in the flowgraph
  data-external="<id>"  a precondition owned outside this route
  data-edge="<a>-><b>"  b waits on a
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _page_regions import RegionParser, parse  # noqa: E402

MARKS = ["data-route", "data-scope", "data-legend", "data-starting-point", "data-card",
         "data-acceptance", "data-check", "data-step", "data-external", "data-edge"]
DONE_WORDS = [
    "done", "complete", "completed", "finished", "shipped", "passed", "merged",
    "landed", "committed", "fixed", "built", "published", "resolved", "closed",
    "green", "released", "succeeded", "deployed", "verified",
]
DONE_MARKS = ["✓", "✔", "✅", "☑", "[x]"]
# Regions whose wording the skill itself requires; their words are not searched, their ticks are.
EXCLUDED = ("data-route", "data-scope", "data-legend", "data-starting-point",
            "data-acceptance", "data-check")
LIMITS = {"data-scope": (1, 1), "data-route": (0, 1), "data-legend": (0, 1),
          "data-starting-point": (0, 1)}
FIXED_PREFIX = {"data-acceptance": "Passes when:", "data-check": "Checked by:"}
VAGUE_CHECKS = ["test it", "verify it", "verify", "confirm it works", "check it",
                "check that it's right", "check that it works", "make sure it works"]
QUOTE_TAGS = ("pre", "code", "blockquote")
STATUS_ATTRS = ("aria-label", "title")
# A done-word as its own word: not part of a hyphenated compound ("built-in"), and not a
# possibility or a future ("may be closed", "will be merged").
WORD_RE = re.compile(r"(?<![\w-])(" + "|".join(DONE_WORDS) + r")(?![\w-])", re.IGNORECASE)
MODAL_RE = re.compile(r"\b(may|might|could|would|will|can|should|must|to)\s+(not\s+)?(be|get|have been)\s*$",
                      re.IGNORECASE)


class Page(RegionParser):
    REGION_ATTRS = EXCLUDED

    def __init__(self):
        super().__init__()
        self.free_text, self.region_text = [], []
        self.cells = []                  # [attr, [text]] for acceptance / check cells
        self.counts = {k: 0 for k in LIMITS}
        self.findings = []
        self.steps, self.externals, self.edges, self.cards = [], [], [], []
        self.order = 0
        self.scope_at = self.first_step_at = None
        self.scope_text = []

    def on_start(self, tag, a):
        self.order += 1
        here = self.regions()
        if tag == "input" and a.get("type", "").lower() == "checkbox" and "checked" in a:
            self.findings.append("checked checkbox")
        if tag in ("progress", "meter"):
            self.findings.append(f"<{tag}> element: a progress display")
        for k in STATUS_ATTRS:
            v = a.get(k, "")
            if v:
                (self.region_text if here else self.free_text).append(v)
        for k in LIMITS:
            if k in a:
                self.counts[k] += 1
        if "data-scope" in a and self.scope_at is None:
            self.scope_at = self.order
        mine = [k for k in EXCLUDED if k in a]
        for k in mine:
            if k in ("data-acceptance", "data-check"):
                if self.ancestor_attr("data-card") is None:
                    self.findings.append(f"{k} cell outside a data-card")
                self.cells.append([k, []])
            if here:
                self.findings.append(f"{k} opened inside {here[0]}: regions may not nest")
        if "data-card" in a:
            self.cards.append(a["data-card"])
            if here:
                self.findings.append(f"data-card {a['data-card']!r} inside {here[0]}: "
                                     f"a card may not sit in an excluded region")
        if "data-step" in a:
            self.steps.append(a["data-step"])
            if self.first_step_at is None:
                self.first_step_at = self.order
        if "data-external" in a:
            self.externals.append(a["data-external"])
        if "data-edge" in a:
            self.edges.append(a["data-edge"])

    def on_text(self, data):
        here = self.regions()
        if here:
            self.region_text.append(data)
            if self.cells and here[0] == self.cells[-1][0]:
                self.cells[-1][1].append(data)
            if here[0] == "data-scope":
                self.scope_text.append(data)
            return
        if any(self.inside(t) for t in QUOTE_TAGS):
            return
        if any(self.inside(t) for t in ("s", "del", "strike")):
            self.findings.append(f"strike-through: {data.strip()[:60]!r}")
        self.free_text.append(data)


def has_mark(text):
    low = text.lower()
    return [m for m in DONE_MARKS if m in low]


def check_done(p):
    hits = list(p.findings) + list(p.errors)
    for text in p.free_text:
        for m in WORD_RE.finditer(text):
            if MODAL_RE.search(text[:m.start()]):
                continue
            s = max(0, m.start() - 30)
            hits.append(f"done-word {m.group(1).lower()!r}: …{text[s:m.end() + 30].strip()}…")
        for mark in has_mark(text):
            hits.append(f"done-mark {mark!r}: {text.strip()[:60]!r}")
    for text in p.region_text:
        for mark in has_mark(text):
            hits.append(f"done-mark {mark!r} inside an excluded region: {text.strip()[:60]!r}")
    for k, (lo, hi) in LIMITS.items():
        n = p.counts[k]
        if not lo <= n <= hi:
            hits.append(f"{k} appears {n} times; allowed {lo}..{hi}")
    for attr, parts in p.cells:
        text = " ".join(t.strip() for t in parts).strip()
        if not text.startswith(FIXED_PREFIX[attr]):
            hits.append(f"{attr} cell does not start with {FIXED_PREFIX[attr]!r}: {text[:60]!r}")
        elif attr == "data-check":
            rest = text[len(FIXED_PREFIX[attr]):].strip().rstrip(".").lower()
            if not rest or rest in VAGUE_CHECKS:
                hits.append(f"P1 vague check: {text[:60]!r}")
    for h in hits:
        print(f"P2 FAIL {h}")
    print(f"shown as done: {len(hits)}")
    return not hits


def check_graph(p):
    bad = list(p.errors)
    steps, ext = p.steps, p.externals
    for name, ids in (("data-step", steps), ("data-external", ext), ("data-card", p.cards),
                      ("data-edge", p.edges)):
        dup = sorted({i for i in ids if ids.count(i) > 1})
        if dup:
            bad.append(f"duplicate {name}: {', '.join(dup)}")
    nodes = set(steps) | set(ext)
    pairs = []
    for e in p.edges:
        m = re.fullmatch(r"\s*(\S+?)\s*->\s*(\S+)\s*", e)
        if not m:
            bad.append(f"edge not in '<a>-><b>' form: {e!r}")
            continue
        a, b = m.groups()
        for end in (a, b):
            if end not in nodes:
                bad.append(f"edge {e!r} names {end!r}, which is not a data-step or data-external")
        if b in ext:
            bad.append(f"edge {e!r} points INTO an external precondition; externals only feed steps")
        pairs.append((a, b))
    feeding = {a for a, _ in pairs}
    for x in ext:
        if x not in feeding:
            bad.append(f"external {x!r} feeds no step")
    if set(p.cards) != set(steps):
        bad.append(f"cards and steps differ: cards-only {sorted(set(p.cards) - set(steps))}, "
                   f"steps-only {sorted(set(steps) - set(p.cards))}")
    cycle = "none"
    if pairs:
        r = subprocess.run(["tsort"], input="\n".join(f"{a} {b}" for a, b in pairs) + "\n",
                           capture_output=True, text=True)
        if "cycle" in r.stderr.lower() or r.returncode != 0:
            cycle = "present"
            bad.append("tsort reports a cycle: " + " ".join(r.stderr.split())[:160])
    pos = {c: i for i, c in enumerate(p.cards)}
    for a, b in pairs:
        if a in pos and b in pos and pos[a] > pos[b]:
            bad.append(f"card order is not topological: {b} is shown before {a}, which it waits on")
    for b in bad:
        print(f"P3 FAIL {b}")
    print(f"steps: {len(steps)} · externals: {len(ext)} · nodes: {len(nodes)} · "
          f"edges: {len(pairs)} · cards: {len(p.cards)} · cycles: {cycle}")
    return not bad


def check_scope(p):
    bad = list(p.errors)
    text = " ".join(" ".join(p.scope_text).split()).lower()
    if p.scope_at is None:
        bad.append("no data-scope element")
    else:
        if p.first_step_at is not None and p.scope_at > p.first_step_at:
            bad.append("the scope line comes after the flowgraph")
        if not re.search(r"\bas of\b[^@]*\S\s*@\s*\S+", text):
            bad.append("the scope line has no 'as of <source> @ <version>' stamp")
        if not re.search(r"\bout[- ]of[- ]scope\b", text):
            bad.append("the scope line does not say what is out of scope")
    for b in bad:
        print(f"SCOPE FAIL {b}")
    return not bad


def main(argv):
    if argv[1:] == ["--print-words"]:
        print("\n".join(DONE_WORDS + DONE_MARKS))
        return 0
    if argv[1:] == ["--print-marks"]:
        print("\n".join(MARKS))
        return 0
    if len(argv) != 3 or argv[1] not in ("done", "graph", "scope", "all"):
        print(__doc__, file=sys.stderr)
        return 2
    p = parse(argv[2], Page)
    mode, ok = argv[1], True
    if mode in ("done", "all"):
        ok = check_done(p) and ok
    if mode in ("graph", "all"):
        ok = check_graph(p) and ok
    if mode in ("scope", "all"):
        ok = check_scope(p) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
