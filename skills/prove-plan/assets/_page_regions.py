"""Shared HTML walking for the prove family's page scanners (plan-page-scan.py and
prove-explanation's explain-page-scan.py). Stdlib only.

It keeps a stack of open elements and knows three things the scanners must agree on:

- what text a reader never sees: <style> and <script> anywhere, and <title> only inside <head>
  (an SVG <title> is a tooltip a reader does see, so it is scanned);
- which elements are VOID, so they never sit on the stack;
- that a REGION — an element carrying one of the subclass's REGION_ATTRS — ends at its own end
  tag. A region whose end tag is missing would otherwise stretch over the rest of the page and
  silently exempt it, so it is recorded as an error: either an outer end tag closed it, or the
  document ended with it open.

A subclass overrides on_start(tag, attrs) and on_text(text), and reads self.regions(),
self.inside(tag) and self.errors.
"""
import sys
from html.parser import HTMLParser

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source",
        "track", "wbr", "path", "line", "circle", "ellipse", "polygon", "polyline", "use", "stop",
        "rect"}
ALWAYS_HIDDEN = {"style", "script"}


class Frame:
    __slots__ = ("tag", "attrs", "region")

    def __init__(self, tag, attrs, region):
        self.tag, self.attrs, self.region = tag, attrs, region


class RegionParser(HTMLParser):
    REGION_ATTRS = ()

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.errors = []

    # --- hooks for subclasses ---
    def on_start(self, tag, attrs):
        pass

    def on_text(self, text):
        pass

    # --- queries ---
    def regions(self):
        """Region attribute names that enclose the current position, innermost first."""
        out = []
        for f in reversed(self.stack):
            out.extend(f.region)
        return out

    def inside(self, tag):
        return any(f.tag == tag for f in self.stack)

    def ancestor_attr(self, name):
        for f in reversed(self.stack):
            if name in f.attrs:
                return f.attrs[name]
        return None

    def hidden(self):
        tags = [f.tag for f in self.stack]
        if any(t in ALWAYS_HIDDEN for t in tags):
            return True
        if "title" in tags:
            i = len(tags) - 1 - tags[::-1].index("title")
            return "head" in tags[:i] and "svg" not in tags[:i]
        return False

    # --- HTMLParser plumbing ---
    def handle_starttag(self, tag, attrs):
        a = {k: (v if v is not None else "") for k, v in attrs}
        self.on_start(tag, a)
        if tag in VOID:
            return
        self.stack.append(Frame(tag, a, tuple(k for k in self.REGION_ATTRS if k in a)))

    def handle_startendtag(self, tag, attrs):
        a = {k: (v if v is not None else "") for k, v in attrs}
        self.on_start(tag, a)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i].tag == tag:
                for f in self.stack[i + 1:]:
                    if f.region:
                        self.errors.append(f"unclosed region <{f.tag} {' '.join(f.region)}>: "
                                           f"closed only by an outer </{tag}>")
                del self.stack[i:]
                return

    def handle_data(self, data):
        if data.strip() and not self.hidden():
            self.on_text(data)

    def close(self):
        super().close()
        for f in self.stack:
            if f.region:
                self.errors.append(f"unclosed region <{f.tag} {' '.join(f.region)}>: "
                                   f"still open at the end of the document")


def parse(path, cls):
    try:
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
    except OSError as e:
        print(f"cannot read {path}: {e}", file=sys.stderr)
        sys.exit(2)
    p = cls()
    p.feed(src)
    p.close()
    return p
