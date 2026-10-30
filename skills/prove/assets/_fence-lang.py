#!/usr/bin/env python3
"""Every code block on a proof page names its language, and the page highlights it.

Usage:
  _fence-lang.py check  <page.html>   exit 0 when every <pre> is tagged, 6 otherwise
  _fence-lang.py inject <page.html>   print the page with the kit highlighter inlined (stdout)
  _fence-lang.py tag    <page.html>   add language-text to every untagged <pre>, in place

A CODE BLOCK is a <pre>. It is TAGGED when any of these holds:
  - the <pre> carries a class `language-<name>` with a non-empty name;
  - it has <code> children directly inside it (`pre > code`, as the highlighter selects them) and
    every one of them carries such a class — a <code> nested deeper does not count;
  - it is HAND-COLOURED: it holds a <span> carrying one of the kit's colour classes (c, k, g,
    chan-g, was, now — proof-blocks.css, proof-creative.css) or the highlighter's own hl-*. Such a
    block is already highlighted, which is what the rule asks for; the highlighter leaves it as
    written.
A <pre data-fb-payload> is not a code block at all: it is a decision board's answer read-out, which
the kit fills at runtime, and it is exempt.

Only the FIRST `class` attribute on an element counts, as in a browser. Class names are
case-sensitive, so `LANGUAGE-JS` is not a language. `language-text` is the answer when nothing fits:
it is tagged, and the highlighter leaves it as plain text. Inline <code> outside a <pre> is not a
block. Markup inside <script>/<style> is not parsed as markup, so a "<pre>" in a JS string is not a
block.

`check` is the mechanical half of every prove skill's integrity pass, run by publish-s3.sh before a
byte moves. An untagged block is refused, named by line, rather than warned about: a warning on
every publish is a warning nobody reads.

`tag` is the migration for a page written before the rule: it adds `language-text` to every
untagged <pre> (into its first class attribute, or as a new one), changes no other byte, and is
idempotent. It says how many blocks it tagged. Name a real language by hand where one fits.

`inject` inlines skills/intake/assets/proof-highlight.{css,js} (the kit highlighter) as one <style>
and one <script>, both marked `data-proof-highlight`, just before the page's last real </body> tag
(as the HTML parser sees it, so a "</body>" in a script string is not it), or at the end of the
page when it has none. Inline, not linked: a proof page loads no script from anywhere, so the
highlighter rides in the page's own bytes. Idempotent: an earlier injection is replaced, so a
republish carries one copy. A page on which the highlighter would colour nothing (no block, only
language-text / plaintext, only hand-coloured blocks) is printed byte-identical.

The kit dir is $PROVE_KIT_DIR, else ../../intake/assets beside this file.
"""
import html.parser
import os
import re
import sys

LANG_RE = re.compile(r"(?:^|\s)language-([A-Za-z0-9_+#.-]+)(?=\s|$)")
PLAIN = {"text", "plaintext", "plain", "txt", "none", "nohighlight", "output", "log"}
KIT_COLOURS = {"c", "k", "g", "chan-g", "was", "now"}
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source",
        "track", "wbr"}
MARK_RE = re.compile(r"<style data-proof-highlight[^>]*>.*?</style>\s*"
                     r"<script data-proof-highlight[^>]*>.*?</script>\n?", re.S)
# One attribute inside a start tag, as html.parser reads them: name, then an optional value.
ATTR_RE = re.compile(r"""\s*([^\s/>"'=][^\s/>=]*)(\s*=\s*("[^"]*"|'[^']*'|[^\s>]*))?""")
HERE = os.path.dirname(os.path.abspath(__file__))


def first_class(attrs):
    for name, value in attrs:  # the first `class` wins, as in a browser
        if name == "class":
            return value or ""
    return ""


def lang_of(attrs):
    m = LANG_RE.search(first_class(attrs))
    return m.group(1).lower() if m else None


def kit_coloured(attrs):
    return any(c in KIT_COLOURS or c.startswith("hl-") for c in first_class(attrs).split())


class Pre:
    __slots__ = ("line", "offset", "tag_text", "lang", "payload", "coloured", "codes", "kids", "open")

    def __init__(self, line, offset, tag_text, attrs):
        self.line, self.offset, self.tag_text = line, offset, tag_text
        self.lang = lang_of(attrs)
        self.payload = any(name == "data-fb-payload" for name, _ in attrs)
        self.coloured = False
        self.codes = []    # direct <code> children: [lang, has element children]
        self.kids = False  # the <pre> holds an element
        self.open = []     # elements open inside the <pre>; open[0] == "code" is a direct <code>

    @property
    def tagged(self):
        return (self.payload or self.coloured or self.lang is not None
                or (bool(self.codes) and all(c[0] for c in self.codes)))

    @property
    def colourable(self):
        """Would proof-highlight.js's run() colour anything in this block?"""
        if self.payload:
            return False
        if self.codes:
            return any((c[0] or self.lang) and (c[0] or self.lang) not in PLAIN and not c[1]
                       for c in self.codes)
        return self.lang is not None and self.lang not in PLAIN and not self.kids


class Blocks(html.parser.HTMLParser):
    """Collect each <pre> as a Pre, and where the last real </body> starts."""

    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.starts = [0]  # offset of each line; html.parser counts lines by "\n" alone
        for i, ch in enumerate(text):
            if ch == "\n":
                self.starts.append(i + 1)
        self.blocks = []
        self.stack = []
        self.body_end = None

    def at(self):
        line, col = self.getpos()
        return self.starts[line - 1] + col

    def handle_starttag(self, tag, attrs):
        if self.stack:
            p = self.stack[-1]
            p.kids = True
            if p.open[:1] == ["code"]:
                p.codes[-1][1] = True
            if tag == "span" and kit_coloured(attrs):
                p.coloured = True
            if tag == "code" and not p.open:
                p.codes.append([lang_of(attrs), False])
            if tag not in VOID and tag != "pre":
                p.open.append(tag)
        if tag == "pre":
            self.stack.append(Pre(self.getpos()[0], self.at(), self.get_starttag_text(), attrs))

    def handle_endtag(self, tag):
        if tag == "body" and not self.stack:
            self.body_end = self.at()
        if not self.stack:
            return
        if tag == "pre":
            self.blocks.append(self.stack.pop())
            return
        p = self.stack[-1]
        for i in range(len(p.open) - 1, -1, -1):
            if p.open[i] == tag:
                del p.open[i:]
                break

    def close(self):
        super().close()
        while self.stack:  # an unclosed <pre> is still a block
            self.blocks.append(self.stack.pop())


def parse(text):
    p = Blocks(text)
    p.feed(text)
    p.close()
    p.blocks.sort(key=lambda b: b.offset)
    return p


def check(path, text):
    bad = [b.line for b in parse(text).blocks if not b.tagged]
    if not bad:
        return 0
    n = len(bad)
    print("fence-lang: REFUSED — %d code block%s on %s carr%s no language-* class:"
          % (n, "" if n == 1 else "s", path, "ies" if n == 1 else "y"), file=sys.stderr)
    for line in bad:
        print("  line %d: <pre> with no language-* on it or on a <code> directly inside it" % line,
              file=sys.stderr)
    print("  Tag each block: <pre><code class=\"language-ts\">…</code></pre>. Use language-text when no"
          " language fits (it renders unhighlighted). Class names are case-sensitive: language-ts, not"
          " LANGUAGE-TS.", file=sys.stderr)
    print("  To tag every untagged block language-text in one go (the migration for a page written"
          " before this rule):\n    python3 %s tag %s"
          % (os.path.join(HERE, "_fence-lang.py"), path), file=sys.stderr)
    return 6


def tagged_start(tag_text):
    """The <pre ...> start tag with language-text added to its first class attribute."""
    name_end = len(re.match(r"<[A-Za-z][^\s/>]*", tag_text).group(0))
    pos = name_end
    while True:
        m = ATTR_RE.match(tag_text, pos)
        if not m or m.end() == pos:
            break
        if m.group(1).lower() == "class":
            raw = m.group(3)
            if raw is None:  # a bare `class`
                return tag_text[:m.end(1)] + '="language-text"' + tag_text[m.end():]
            if raw[:1] in "\"'":
                q, value = raw[0], raw[1:-1]
            else:
                q, value = '"', raw
            new = q + ("language-text " + value if value.strip() else "language-text") + q
            return tag_text[:m.start(3)] + new + tag_text[m.end(3):]
        pos = m.end()
    return tag_text[:name_end] + ' class="language-text"' + tag_text[name_end:]


def tag(text):
    """Return (new text, number of blocks tagged)."""
    untagged = [b for b in parse(text).blocks if not b.tagged]
    out, last = [], 0
    for b in untagged:
        assert text.startswith(b.tag_text, b.offset), "start tag not where the parser put it"
        out.append(text[last:b.offset])
        out.append(tagged_start(b.tag_text))
        last = b.offset + len(b.tag_text)
    out.append(text[last:])
    return "".join(out), len(untagged)


def kit_dir():
    env = os.environ.get("PROVE_KIT_DIR")
    if env:
        return env
    return os.path.normpath(os.path.join(HERE, "..", "..", "intake", "assets"))


def inline_safe(js, css):
    """Inlined, the js must not end its <script> or open an HTML comment/script inside it (the
    double-escaped state), and the css must not end its <style>."""
    jl, cl = js.lower(), css.lower()
    return not ("</script" in jl or "<!--" in jl or "<script" in jl or "</style" in cl)


def inject(text):
    stripped = MARK_RE.sub("", text)
    page = parse(stripped)
    if not any(b.colourable for b in page.blocks):
        return text if stripped == text else stripped
    kd = kit_dir()
    with open(os.path.join(kd, "proof-highlight.css"), encoding="utf-8", newline="") as f:
        css = f.read().strip()
    with open(os.path.join(kd, "proof-highlight.js"), encoding="utf-8", newline="") as f:
        js = f.read().strip()
    if not inline_safe(js, css):
        raise SystemExit("fence-lang: the kit highlighter contains </script, <script, <!-- or </style"
                         " and cannot be inlined")
    block = ("<style data-proof-highlight>\n%s\n</style>\n<script data-proof-highlight>\n%s\n</script>\n"
             % (css, js))
    idx = page.body_end
    if idx is None:
        return stripped.rstrip("\n") + "\n" + block
    return stripped[:idx] + block + stripped[idx:]


def main(argv):
    if len(argv) != 3 or argv[1] not in ("check", "inject", "tag"):
        for line in __doc__.strip().splitlines()[2:5]:
            print(line, file=sys.stderr)
        return 2
    path = argv[2]
    # newline="" keeps CRLF and bare CR as they are: inject and tag change nothing else.
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:
        text = f.read()
    if argv[1] == "check":
        return check(path, text)
    if argv[1] == "tag":
        new, n = tag(text)
        if n:
            with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
                f.write(new)
        print("fence-lang: tagged %d block%s language-text on %s" % (n, "" if n == 1 else "s", path),
              file=sys.stderr)
        return 0
    sys.stdout.buffer.write(inject(text).encode("utf-8", "surrogateescape"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
