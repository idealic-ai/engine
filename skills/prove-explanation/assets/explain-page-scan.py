#!/usr/bin/env python3
"""Mechanical half of /prove-explanation's teaching gate (E2, E3 and the pins E5 relies on), run
over the composed builds/<slug>_EXPLAIN.html. Stdlib only; run with `python3 -I`.

    explain-page-scan.py order  <page.html>               E2: scope line, then the five parts in order
    explain-page-scan.py jargon <page.html>               E3: part 1 defines every code-like or working word
    explain-page-scan.py pins   <page.html> --root <repo> E5: every quote, capture and line reference is
                                                          pinned, and each pin belongs to the file it cites
    explain-page-scan.py all    <page.html> --root <repo> all three
    explain-page-scan.py --print-marks                    the marks this scanner reads, one per line

Exit 0 when clean, 1 on a finding, 2 on a usage or read error. The page is scanned, never printed.

What it does NOT check: whether a value in the worked example was invented. That stays E4, by eye.

E3 does not trust the teacher's own term list: it finds the terms itself, from the page. A term
counts as defined when part 1 wraps it in <dfn>; a <dfn> may hold its definition after a comma,
colon or dash ("<dfn>placeHold, the call that sets money aside</dfn>").

Marks (the brief's item 4 must name exactly these; the test compares the two):
  data-scope                                 the one-line scope at the top
  data-part="idea|how|example|edges|not"     the five parts, in this order
  dfn                                        a term defined where it is first used
  data-source="<path>[:<lines>]"             on every <pre>, table capture and source fixture
  data-pin="<commit sha>|sha256:<hex>"       the version of THAT file the source was read at
  data-fixture="source|teacher-written"      an input
  data-adapted-from="<fixture or test>"      what a teacher-written fixture was adapted from
"""
import hashlib
import os
import re
import subprocess
import sys

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, "..", "..", "prove-plan", "assets"))
from _page_regions import RegionParser, parse  # noqa: E402

MARKS = ["data-scope", "data-part", "dfn", "data-source", "data-pin", "data-fixture",
         "data-adapted-from"]
PARTS = ["idea", "how", "example", "edges", "not"]
PINNED_PARTS = ("how", "example")
# VOICE.md § "Talking about the work" names these as working words that stay out of text for
# people. Its everyday ones (checks, guards, claims) are left to the reviewer, because a newcomer
# reads "a quick check" correctly.
WORKING_WORDS = ["gate", "ledger", "lane", "patch-id"]
# A pin is a commit sha (hex with at least one letter, so a date with its dashes removed is not
# one) or sha256:<hex>.
PIN_RE = re.compile(r"^((?=[0-9a-f]*[a-f])[0-9a-f]{7,40}|sha256:[0-9a-f]{12,64})$")
CODEISH = re.compile(
    r"(?<![\w-])(--[a-zA-Z][\w-]*|-[a-zA-Z](?![\w-]))"          # --flags and -v
    r"|\b([A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+"                   # snake_case, ENV_NAMES
    r"|[a-z]{2,}[A-Z][a-z][A-Za-z0-9]*"                          # camelCase (not iPhone, macOS)
    r"|[A-Za-z0-9_-]+\.(?:sh|py|ts|tsx|js|json|md|sql|yml|yaml|rb|go|rs))\b")
KEBAB = re.compile(r"(?<![\w-])([a-z][a-z0-9]*(?:-[a-z0-9]+)+)(?![\w-])")
LINE_REF = re.compile(r"[\w./-]+\.(?:sh|py|ts|tsx|js|json|md|sql|yml|yaml|rb|go|rs):\d+(?:-\d+)?")
TABLE_TAGS = ("table",)


def norm(t):
    t = t.strip().lower()
    return t[:-1] if t.endswith("s") and len(t) > 3 else t


class Page(RegionParser):
    REGION_ATTRS = ("data-scope", "data-part", "data-fixture")

    def __init__(self):
        super().__init__()
        self.order = []
        self.idea_text, self.idea_code, self.dfns = [], [], set()
        self.code_corpus = []            # code text outside part 1: what counts as a code name here
        self.unpinned, self.bad_fixtures = [], []
        self.pins = []                   # (source, pin)
        self.pinned_in = set()           # parts holding at least one pinned block
        self.teacher_fixtures = []
        self._dfn_buf = None

    def _part(self):
        return self.ancestor_attr("data-part")

    def _pinned_here(self):
        return PIN_RE.match(self.ancestor_attr("data-pin") or "") is not None

    def on_start(self, tag, a):
        if "data-scope" in a:
            self.order.append("scope")
        if "data-part" in a:
            self.order.append(a["data-part"])
        part = a.get("data-part") or self._part()
        needs_pin = (tag == "pre" or tag in TABLE_TAGS or "data-source" in a
                     or a.get("data-fixture") == "source")
        if needs_pin:
            src = a.get("data-source", "") or (self.ancestor_attr("data-source") or "")
            pin = a.get("data-pin", "") or (self.ancestor_attr("data-pin") or "")
            if not src:
                self.unpinned.append(f"<{tag}> with no data-source (a quote or capture must say where it was read)")
            elif not PIN_RE.match(pin):
                self.unpinned.append(f"{src}: data-pin {pin!r} is not a commit sha or sha256:<hex>")
            else:
                self.pins.append((src, pin))
                if part:
                    self.pinned_in.add(part)
        if "data-fixture" in a:
            kind = a["data-fixture"]
            if kind not in ("source", "teacher-written"):
                self.bad_fixtures.append(f"data-fixture={kind!r} is neither 'source' nor 'teacher-written'")
            elif kind == "teacher-written":
                if not a.get("data-adapted-from", "").strip():
                    self.bad_fixtures.append("teacher-written fixture with no data-adapted-from")
                self.teacher_fixtures.append("")
        if tag == "dfn":
            self._dfn_buf = []

    def handle_endtag(self, tag):
        if tag == "dfn" and self._dfn_buf is not None:
            whole = " ".join(self._dfn_buf).strip()
            self.dfns.add(norm(re.split(r"[,:;—–]| - ", whole, maxsplit=1)[0]))
            for m in CODEISH.finditer(whole):
                self.dfns.add(norm(m.group(1) or m.group(2)))
            self._dfn_buf = None
        super().handle_endtag(tag)

    def on_text(self, data):
        part = self._part()
        if self.ancestor_attr("data-fixture") == "teacher-written" and self.teacher_fixtures:
            self.teacher_fixtures[-1] += data
        if self._dfn_buf is not None:
            self._dfn_buf.append(data)
        in_code = self.inside("code") or self.inside("pre")
        for m in LINE_REF.finditer(data):
            if not self._pinned_here():
                self.unpinned.append(f"line reference {m.group(0)!r} with no data-pin around it")
        if part == "idea":
            (self.idea_code if in_code else self.idea_text).append(data.strip() if in_code else data)
        elif in_code:
            self.code_corpus.append(data)


def check_order(p):
    bad = list(p.errors)
    if not p.order or p.order[0] != "scope":
        bad.append("the page does not open with its data-scope line")
    parts = [x for x in p.order if x != "scope"]
    if parts != PARTS:
        bad.append(f"parts are {parts}, expected {PARTS} once each in that order")
    for b in bad:
        print(f"E2 FAIL {b}")
    return not bad


def check_jargon(p):
    terms = set(p.idea_code)
    text = " ".join(p.idea_text)
    for m in CODEISH.finditer(text):
        terms.add(m.group(1) or m.group(2))
    corpus = set(re.findall(r"[A-Za-z0-9_-]+", " ".join(p.code_corpus)))
    for m in KEBAB.finditer(text):
        if m.group(1) in corpus:          # a hyphenated word that is a code name on this page
            terms.add(m.group(1))
    for w in WORKING_WORDS:
        if re.search(r"(?<![\w-])" + re.escape(w) + r"s?(?![\w-])", text, re.IGNORECASE):
            terms.add(w)
    undefined = sorted(t for t in terms if norm(t) not in p.dfns)
    for t in undefined:
        print(f"E3 FAIL part 1 uses {t!r} without a <dfn> for it there")
    print(f"part-1 terms found: {len(terms)} · defined: {len(terms) - len(undefined)}")
    return not undefined


def pin_owner_problem(root, src, pin):
    path = src.split(":", 1)[0]
    if pin.startswith("sha256:"):
        full = os.path.join(root, path)
        try:
            with open(full, "rb") as fh:
                digest = hashlib.sha256(fh.read()).hexdigest()
        except OSError:
            return f"{path}: cannot read it under --root to check its sha256 pin"
        return None if digest.startswith(pin[7:]) else f"{path}: sha256 pin {pin} is not this file's ({digest[:12]}…)"
    r = subprocess.run(["git", "-C", root, "cat-file", "-e", f"{pin}:{path}"],
                       capture_output=True, text=True)
    return None if r.returncode == 0 else f"{path}: commit {pin} does not contain this file"


def check_pins(p, root):
    bad = list(p.errors) + list(p.unpinned) + list(p.bad_fixtures)
    for text in p.teacher_fixtures:
        if "written for this page" not in text.lower():
            bad.append("a teacher-written fixture is not labelled 'written for this page' inside its own element")
    for part in PINNED_PARTS:
        if part not in p.pinned_in:
            bad.append(f"part {part!r} holds no pinned block (data-source + data-pin)")
    for src, pin in sorted(set(p.pins)):
        prob = pin_owner_problem(root, src, pin)
        if prob:
            bad.append(prob)
    for b in bad:
        print(f"E5 FAIL {b}")
    print(f"pinned blocks: {len(p.pins)} · pin owners checked under {root}")
    return not bad


def main(argv):
    if argv[1:] == ["--print-marks"]:
        print("\n".join(MARKS))
        return 0
    args = argv[1:]
    root = None
    if "--root" in args:
        i = args.index("--root")
        if i + 1 >= len(args):
            print(__doc__, file=sys.stderr)
            return 2
        root = args[i + 1]
        del args[i:i + 2]
    if len(args) != 2 or args[0] not in ("order", "jargon", "pins", "all"):
        print(__doc__, file=sys.stderr)
        return 2
    if args[0] in ("pins", "all") and not root:
        print("pins needs --root <repo>, the tree the data-source paths are relative to", file=sys.stderr)
        return 2
    p = parse(args[1], Page)
    ok = True
    if args[0] in ("order", "all"):
        ok = check_order(p) and ok
    if args[0] in ("jargon", "all"):
        ok = check_jargon(p) and ok
    if args[0] in ("pins", "all"):
        ok = check_pins(p, root) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
