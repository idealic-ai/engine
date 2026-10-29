#!/usr/bin/env python3
"""Stamp the seat strip onto a page publish-s3.sh is about to upload.

    _seat-strip.py <page.html> --seat <seat> --source <src> [--board] [--origin host:cwd]
                   [--when <ISO-8601 UTC>]          → the page, with the strip, on stdout

The strip answers the operator's question for every published page: WHO published this, and HOW do
I answer them? It names the seat, says "message <seat>" (plus "or answer on this board" when the page
carries a decision board's state config), and gives the publish time. With no seat it says so, and
names the host and cwd the publish ran from, rather than guessing a seat.

Rules this file keeps:
  * IDEMPOTENT. The strip sits between <!--prove-seat-strip:begin--> and <!--prove-seat-strip:end-->.
    When the tag walker meets that pair as REAL comments (not inside a <script> string or another
    comment), the strip is REPLACED in place, so a page fetched back and re-published carries one
    strip, never two, and a page that embeds old published bytes as data keeps them untouched.
  * PLACEMENT. The strip is the first child of <body>. If the page has no <body> tag (the /prove
    composer often omits it), the strip goes before the first element that is not a head element,
    which is exactly where the HTML parser opens the body anyway.
  * STATIC, IN FLOW. The strip is not fixed or sticky. A sticky page bar (the kit's .idbar) sits
    below it at scroll 0. A fixed header that pads the body pushes the strip down below itself,
    because the strip is inside the body's padding, so it is never painted under the header.
  * SELF-CONTAINED. It uses inline CSS only and loads no external asset. It is styled in light and
    dark, both for the OS scheme and for the page's own data-theme override.
  * Outside the markers, the page is byte-identical, CRLF and bare CR included.
  * --board is passed only when THIS publish injected a state config (publish-s3.sh decides; a grep
    of the page would be fooled by a page that merely mentions the attribute). --copy-back says the
    board has no write grant. --via names the live seat an explicit PROVE_SEAT overrode.
"""
import argparse
import datetime
import html
import re
import sys

BEGIN = "<!--prove-seat-strip:begin-->"
END = "<!--prove-seat-strip:end-->"

CSS = (
    ".prove-seat-strip{--pss-bg:#eef1f6;--pss-ink:#1b2330;--pss-mute:#566173;--pss-rule:#cdd4df;"
    "--pss-code:#ffffff;"
    "display:block;box-sizing:border-box;width:100%;margin:0;padding:6px 16px;"
    "background:var(--pss-bg);color:var(--pss-ink);border-bottom:1px solid var(--pss-rule);"
    "font:13px/1.45 system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;letter-spacing:0;"
    "text-align:left;position:relative;z-index:1;overflow-wrap:anywhere;}"
    ".prove-seat-strip *{box-sizing:border-box;font:inherit;color:inherit;margin:0;padding:0;}"
    ".prove-seat-strip .pss-row{display:flex;flex-wrap:wrap;gap:2px 14px;align-items:baseline;"
    "max-width:1100px;margin:0 auto;}"
    ".prove-seat-strip b,.prove-seat-strip .pss-warn{font-weight:600;}"
    ".prove-seat-strip .pss-mute{color:var(--pss-mute);}"
    ".prove-seat-strip code{font-family:ui-monospace,'SF Mono',Menlo,Consolas,monospace;"
    "font-size:12px;background:var(--pss-code);border:1px solid var(--pss-rule);border-radius:3px;"
    "padding:0 4px;}"
    ".prove-seat-strip[data-seat-unknown] {--pss-bg:#fbefd9;--pss-rule:#e6c98f;}"
    "@media (prefers-color-scheme: dark){:root:not([data-theme=\"light\"]) .prove-seat-strip{"
    "--pss-bg:#1a2029;--pss-ink:#e4e8ef;--pss-mute:#9aa5b6;--pss-rule:#2d3644;--pss-code:#0f1319;}"
    ":root:not([data-theme=\"light\"]) .prove-seat-strip[data-seat-unknown]{--pss-bg:#352713;--pss-rule:#6b4f1d;}}"
    ":root[data-theme=\"dark\"] .prove-seat-strip{"
    "--pss-bg:#1a2029;--pss-ink:#e4e8ef;--pss-mute:#9aa5b6;--pss-rule:#2d3644;--pss-code:#0f1319;}"
    ":root[data-theme=\"dark\"] .prove-seat-strip[data-seat-unknown]{--pss-bg:#352713;--pss-rule:#6b4f1d;}"
    "@media print{.prove-seat-strip{display:none}}"
)

HEAD_TAGS = {"html", "head", "meta", "link", "style", "script", "title", "base", "noscript", "template"}
RAW_TEXT = {"style", "script", "title", "noscript", "template"}


def build(seat, source, board, copy_back, via, origin, when):
    e = html.escape  # quote=True: every value below may land in an attribute
    shown = when.replace("T", " ").replace("Z", " UTC")
    answer = "answer on this board (copy-back)" if copy_back else "answer on this board"
    if seat:
        reply = 'Reply: message <code>%s</code>' % e(seat)
        if board:
            reply += ", or " + answer
        who = '<span>Published by <b>%s</b>%s</span>' % (
            e(seat), (' (via <code>%s</code>)' % e(via)) if via else "")
        attrs = 'data-seat="%s" data-seat-source="%s"' % (e(seat), e(source))
        if via:
            attrs += ' data-seat-via="%s"' % e(via)
        body = '%s<span>%s</span>' % (who, reply)
    else:
        attrs = 'data-seat="" data-seat-source="unknown" data-seat-unknown'
        body = '<span class="pss-warn">seat unknown — published from <code>%s</code></span>' % e(origin)
        if board:
            body += "<span>You can still %s</span>" % answer
    return (
        BEGIN
        + '<div class="prove-seat-strip" data-prove-seat-strip %s role="note" aria-label="Who published this page">'
          % attrs
        + "<style>" + CSS + "</style>"
        + '<div class="pss-row">%s<span class="pss-mute">published <time datetime="%s">%s</time></span></div>'
          % (body, e(when), e(shown))
        + "</div>"
        + END
    )


# Attribute-aware: a quoted attribute may itself hold '>' (the kit's favicon is an inline
# data:image/svg+xml,<svg ...> in an href), so a tag runs to the first '>' OUTSIDE quotes.
TAG = re.compile(r"<!--.*?-->|<![^>]*>|<(/?)([A-Za-z][A-Za-z0-9-]*)\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>",
                 re.I | re.S)
# Compiled once and searched from an offset: slicing page[pos:] per element was quadratic.
RAW_CLOSE = {n: re.compile(r"</%s\s*>" % n, re.I) for n in RAW_TEXT}
STRIP_OPEN = BEGIN + '<div class="prove-seat-strip"'


def walk(page):
    """One pass over the REAL markup.

    Returns (insertion point, span of this page's existing strip or None).

    A text search is not enough, for either answer:
      * the /decide skeleton names `<body>` inside its authoring comment, and a page that embeds
        earlier published bytes carries a whole marker pair inside a <script> string. Both are data.
      * so comments, the doctype and the contents of raw-text elements (style, script, title, ...)
        are skipped, and a tag ends at the first '>' outside its quoted attributes.
    The insertion point is just after the first real <body> tag; without one, before the first
    element that is not a head element (where the parser opens the body); on a page with no
    leading tag at all, offset 0. An existing strip counts only when the walker meets BEGIN as a
    real comment, immediately followed by the strip's own div, and then meets END as a real comment.
    """
    # Bare text before any tag (markdown or plain text uploaded as .html): the top is offset 0.
    at = 0 if page.lstrip()[:1] != "<" else None
    begin = None
    pos = 0
    while True:
        m = TAG.search(page, pos)
        if not m:
            break
        tok = m.group(0)
        name = (m.group(2) or "").lower()
        pos = m.end()
        if not name:
            if tok == BEGIN and begin is None and page.startswith(STRIP_OPEN, m.start()):
                begin = m.start()
            elif tok == END and begin is not None:
                return (at if at is not None else begin), (begin, m.end())
            continue
        if at is None:
            if m.group(1):
                if name not in ("head", "html"):
                    at = m.start()
            elif name == "body":
                at = m.end()
            elif name not in HEAD_TAGS:
                at = m.start()
        if not m.group(1) and name in RAW_TEXT:
            close = RAW_CLOSE[name].search(page, pos)
            pos = close.end() if close else len(page)
    return (len(page) if at is None else at), None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("page")
    ap.add_argument("--seat", default="")
    ap.add_argument("--source", default="unknown")
    ap.add_argument("--via", default="")
    ap.add_argument("--board", action="store_true",
                    help="this publish injected a state config: the page can be answered in place")
    ap.add_argument("--copy-back", action="store_true",
                    help="the board carries no write grant; answers go through the copy bar")
    ap.add_argument("--origin", default="")
    ap.add_argument("--when", default="")
    a = ap.parse_args()

    # newline="" keeps CRLF and bare CR exactly as they are: outside the markers the page is the
    # page, byte for byte (a <pre> or an inline script's CSP hash must not change).
    page = open(a.page, encoding="utf-8", newline="").read()
    when = a.when or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    strip = build(a.seat.strip(), a.source, a.board, a.copy_back, a.via.strip(), a.origin, when)

    at, existing = walk(page)
    if existing:
        page = page[: existing[0]] + strip + page[existing[1]:]
        where = "replaced the existing strip"
    else:
        page = page[:at] + strip + page[at:]
        where = "inserted"
    sys.stderr.write("seat strip %s\n" % where)
    sys.stdout.buffer.write(page.encode("utf-8"))


if __name__ == "__main__":
    main()
