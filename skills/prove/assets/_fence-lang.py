#!/usr/bin/env python3
"""Every code block on a proof page names its language, and the page highlights it.

Usage:
  _fence-lang.py check  <page.html>   exit 0 when every <pre> carries a language, 6 otherwise
  _fence-lang.py inject <page.html>   print the page with the kit highlighter inlined (stdout)

A CODE BLOCK is a <pre>. It is TAGGED when the <pre> itself, or a <code> inside it, carries a class
`language-<name>` with a non-empty name. `language-text` is the answer when nothing fits: it is
tagged, and the highlighter leaves it as plain text. Inline <code> outside a <pre> is not a block.
Markup inside <script>/<style> is not parsed as markup, so a "<pre>" in a JS string is not a block.

`check` is the mechanical half of every prove skill's integrity pass, run by publish-s3.sh before a
byte moves. An untagged block is refused, named by line, rather than warned about: a warning on
every publish is a warning nobody reads.

`inject` inlines skills/intake/assets/proof-highlight.{css,js} (the kit highlighter) as one <style>
and one <script>, both marked `data-proof-highlight`, just before </body> (or at the end of the
page when it has no </body>). Inline, not linked: a proof page loads no script from anywhere, so the
highlighter rides in the page's own bytes. Idempotent: an earlier injection is replaced, so a
republish carries one copy. A page with no block worth highlighting (none, or only language-text /
plaintext) is printed byte-identical.

The kit dir is $PROVE_KIT_DIR, else ../../intake/assets beside this file.
"""
import html.parser
import os
import re
import sys

LANG_RE = re.compile(r"(?:^|\s)language-([A-Za-z0-9_+#.-]+)(?=\s|$)")
PLAIN = {"text", "plaintext", "plain", "txt", "none", "nohighlight", "output", "log"}
MARK_RE = re.compile(r"<style data-proof-highlight[^>]*>.*?</style>\s*"
                     r"<script data-proof-highlight[^>]*>.*?</script>\n?", re.S)


def lang_of(attrs):
    m = LANG_RE.search(dict(attrs).get("class") or "")
    return m.group(1).lower() if m else None


class Blocks(html.parser.HTMLParser):
    """Collect each <pre> as (line, language-or-None)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []
        self.stack = []  # open <pre>s: [line, lang]

    def handle_starttag(self, tag, attrs):
        if tag == "pre":
            self.stack.append([self.getpos()[0], lang_of(attrs)])
        elif tag == "code" and self.stack and self.stack[-1][1] is None:
            self.stack[-1][1] = lang_of(attrs)

    def handle_endtag(self, tag):
        if tag == "pre" and self.stack:
            self.blocks.append(tuple(self.stack.pop()))

    def close(self):
        super().close()
        while self.stack:  # an unclosed <pre> is still a block
            self.blocks.append(tuple(self.stack.pop()))


def blocks_of(text):
    p = Blocks()
    p.feed(text)
    p.close()
    return sorted(p.blocks, key=lambda b: b[0])


def check(path, text):
    bad = [line for line, lang in blocks_of(text) if lang is None]
    if not bad:
        return 0
    n = len(bad)
    print("fence-lang: REFUSED — %d code block%s on %s carr%s no language-* class:"
          % (n, "" if n == 1 else "s", path, "ies" if n == 1 else "y"), file=sys.stderr)
    for line in bad:
        print("  line %d: <pre> with no language-* on it or on a <code> inside it" % line, file=sys.stderr)
    print("  Tag each block: <pre><code class=\"language-ts\">…</code></pre>. Use language-text when no"
          " language fits (it renders unhighlighted).", file=sys.stderr)
    return 6


def kit_dir():
    env = os.environ.get("PROVE_KIT_DIR")
    if env:
        return env
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, "..", "..", "intake", "assets"))


def inject(text):
    stripped = MARK_RE.sub("", text)
    wanted = any(lang and lang not in PLAIN for _, lang in blocks_of(stripped))
    if not wanted:
        return text if stripped == text else stripped
    kd = kit_dir()
    with open(os.path.join(kd, "proof-highlight.css"), encoding="utf-8", newline="") as f:
        css = f.read().strip()
    with open(os.path.join(kd, "proof-highlight.js"), encoding="utf-8", newline="") as f:
        js = f.read().strip()
    if "</script" in js.lower() or "</style" in css.lower():
        raise SystemExit("fence-lang: the kit highlighter contains a closing tag and cannot be inlined")
    block = ("<style data-proof-highlight>\n%s\n</style>\n<script data-proof-highlight>\n%s\n</script>\n"
             % (css, js))
    idx = stripped.lower().rfind("</body>")
    if idx < 0:
        return stripped.rstrip("\n") + "\n" + block
    return stripped[:idx] + block + stripped[idx:]


def main(argv):
    if len(argv) != 3 or argv[1] not in ("check", "inject"):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        print(__doc__.strip().splitlines()[3], file=sys.stderr)
        return 2
    path = argv[2]
    # newline="" keeps CRLF and bare CR as they are: inject must change nothing outside its block.
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:
        text = f.read()
    if argv[1] == "check":
        return check(path, text)
    sys.stdout.buffer.write(inject(text).encode("utf-8", "surrogateescape"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
