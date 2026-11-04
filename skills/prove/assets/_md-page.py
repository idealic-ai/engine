#!/usr/bin/env python3
"""Markdown on a proof page is rendered, never shown as one run of text.

Usage:
  _md-page.py page  <in.md> <out.html> [<fallback title>]   write a self-contained page
  _md-page.py embed <page.html>                             print the page with every
                                                            <pre data-md-render> block rendered

publish-s3.sh uploads every object as text/html. A raw .md uploaded that way shows as one
unformatted block, because HTML collapses its line breaks. So publish-s3.sh renders a .md input
with `page` before anything else looks at it, and runs `embed` on every HTML page it publishes.

`page` renders the slice of markdown the engine's reports use: headings, paragraphs, block quotes,
lists, tables, fenced code, horizontal rules, inline code, bold, italic and http(s) links. The page
has light and dark themes, loads no script and no remote asset, and every fenced block names its
language (`language-text` when the fence has none), so publish-s3.sh's fence check passes it.

`embed` is the opt-in for a markdown file shown INSIDE a proof page. The author writes the file
HTML-escaped in a block marked for rendering:

    <pre data-md-render><code class="language-markdown">…escaped markdown…</code></pre>

Opened from builds/, that block is readable source, and the fence check accepts it. At publish it is
replaced by a <div class="md-render"> holding the rendered markdown, with one scoped stylesheet
that takes its colours from the host page's text colour, so it suits the page's own theme. A
<pre class="language-markdown"> WITHOUT the attribute is left alone, because a page may want to
show markdown source as source. A page with no marked block is printed byte-identical.

Every character of the markdown is HTML-escaped, so a report that quotes `<script>` shows it as
text, and a link renders only when its target is http(s). Nothing is ever executed.

ask-council's council-page.py renders a Council Report through this module.
"""
import html
import os
import re
import sys

PAGE_CSS = """
:root { --bg:#fbfaf7; --fg:#1d1c1a; --muted:#6b675f; --line:#e3dfd6; --code:#f1eee7; --accent:#3a5bab; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#16161a; --fg:#e8e6e1; --muted:#a19d94; --line:#2f2e33; --code:#222227; --accent:#8fa8ec; } }
:root[data-theme="dark"] { --bg:#16161a; --fg:#e8e6e1; --muted:#a19d94; --line:#2f2e33; --code:#222227; --accent:#8fa8ec; }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif; }
main { max-width:860px; margin:0 auto; padding:24px 16px 64px; }
h1 { font-size:1.6rem; line-height:1.25; margin:0 0 12px; }
h2 { font-size:1.2rem; margin:32px 0 8px; padding-top:12px; border-top:1px solid var(--line); }
h3 { font-size:1.05rem; margin:22px 0 6px; }
h4, h5, h6 { font-size:1rem; margin:18px 0 6px; }
p, li { overflow-wrap:anywhere; }
a { color:var(--accent); }
code, pre { font-family:ui-monospace,"SF Mono",Menlo,monospace; font-size:.88em; font-variant-ligatures:none; }
code { background:var(--code); padding:1px 4px; border-radius:4px; }
pre { background:var(--code); padding:12px; border-radius:6px; overflow-x:auto; white-space:pre; }
pre code { background:none; padding:0; }
blockquote { margin:12px 0; padding:2px 14px; border-left:3px solid var(--line); color:var(--muted); }
.table { overflow-x:auto; }
table { border-collapse:collapse; font-size:.92em; }
th, td { border:1px solid var(--line); padding:4px 8px; text-align:left; vertical-align:top; }
.src { color:var(--muted); font-size:.85em; }
"""

# Scoped to .md-render and built from currentColor, so it reads in whatever theme the host page has.
EMBED_CSS = """
.md-render { overflow-wrap:anywhere; }
.md-render h1, .md-render h2, .md-render h3, .md-render h4, .md-render h5, .md-render h6 { line-height:1.3; margin:1.1em 0 .4em; }
.md-render code, .md-render pre { font-family:ui-monospace,"SF Mono",Menlo,monospace; font-size:.88em; font-variant-ligatures:none; }
.md-render code { background:color-mix(in srgb, currentColor 9%, transparent); padding:1px 4px; border-radius:4px; }
.md-render pre { background:color-mix(in srgb, currentColor 7%, transparent); padding:12px; border-radius:6px; overflow-x:auto; white-space:pre; }
.md-render pre code { background:none; padding:0; }
.md-render blockquote { margin:10px 0; padding:2px 14px; border-left:3px solid color-mix(in srgb, currentColor 30%, transparent); opacity:.85; }
.md-render .table { overflow-x:auto; }
.md-render table { border-collapse:collapse; font-size:.92em; }
.md-render th, .md-render td { border:1px solid color-mix(in srgb, currentColor 25%, transparent); padding:4px 8px; text-align:left; vertical-align:top; }
"""

LIST_RE = re.compile(r"^\s*([-*+]|\d+\.)\s+(.*)$")
TABLE_RE = re.compile(r"^\s*\|.*\|\s*$")
FENCE_RE = re.compile(r"^(\s*)(`{3,}|~{3,})\s*([\w+#.-]*)\s*$")


def inline(text: str) -> str:
    out, i = [], 0
    for m in re.finditer(r"`([^`]+)`", text):
        out.append(_marks(text[i:m.start()]))
        out.append(f"<code>{html.escape(m.group(1))}</code>")
        i = m.end()
    out.append(_marks(text[i:]))
    return "".join(out)


def _marks(text: str) -> str:
    t = html.escape(text, quote=False)
    t = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
               lambda m: f'<a href="{m.group(2).replace(chr(34), "&quot;")}">{m.group(1)}</a>', t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<![\w*])\*([^*\s][^*]*?)\*(?![\w*])", r"<em>\1</em>", t)
    return t


def render(md: str) -> tuple[str, str]:
    """Return (first level-1 heading or "", body HTML)."""
    lines = md.replace("\r\n", "\n").split("\n")
    out: list[str] = []
    title = ""
    i = 0
    para: list[str] = []

    def flush():
        if para:
            out.append(f"<p>{inline(' '.join(x.strip() for x in para))}</p>")
            para.clear()

    while i < len(lines):
        line = lines[i]
        fm = FENCE_RE.match(line)
        if fm:
            flush()
            fence, lang = fm.group(2), fm.group(3) or "text"
            body = []
            i += 1
            close = re.compile(rf"^\s*{re.escape(fence[0])}{{{len(fence)},}}\s*$")
            while i < len(lines) and not close.match(lines[i]):
                body.append(lines[i])
                i += 1
            i += 1
            lang = html.escape(lang)
            out.append(f'<pre class="language-{lang}"><code class="language-{lang}">'
                       f'{html.escape(chr(10).join(body))}</code></pre>')
            continue
        hm = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if hm:
            flush()
            level = len(hm.group(1))
            if not title and level == 1:
                title = hm.group(2).strip()
            out.append(f"<h{level}>{inline(hm.group(2).strip())}</h{level}>")
            i += 1
            continue
        if TABLE_RE.match(line):
            flush()
            rows = []
            while i < len(lines) and TABLE_RE.match(lines[i]):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            body_rows = [r for r in rows if not all(re.fullmatch(r":?-{2,}:?", c) for c in r)]
            if body_rows:
                head, rest = body_rows[0], body_rows[1:]
                t = ['<div class="table"><table><thead><tr>', *(f"<th>{inline(c)}</th>" for c in head),
                     "</tr></thead><tbody>"]
                for r in rest:
                    t.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
                t.append("</tbody></table></div>")
                out.append("".join(t))
            continue
        if re.match(r"^\s*>", line):
            flush()
            quoted = []
            while i < len(lines) and re.match(r"^\s*>", lines[i]):
                quoted.append(re.sub(r"^\s*>\s?", "", lines[i]))
                i += 1
            _, inner = render("\n".join(quoted))
            out.append(f"<blockquote>{inner}</blockquote>")
            continue
        lm = LIST_RE.match(line)
        if lm:
            flush()
            ordered = lm.group(1)[0].isdigit()
            items = []
            while i < len(lines):
                m = LIST_RE.match(lines[i])
                if m:
                    items.append(m.group(2))
                elif lines[i].startswith("  ") and lines[i].strip() and items:
                    items[-1] += " " + lines[i].strip()
                else:
                    break
                i += 1
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{inline(x)}</li>" for x in items) + f"</{tag}>")
            continue
        if re.match(r"^\s*(-{3,}|\*{3,}|_{3,})\s*$", line):
            flush()
            out.append("<hr>")
            i += 1
            continue
        if not line.strip():
            flush()
        else:
            para.append(line)
        i += 1
    flush()
    return title, "\n".join(out)


def page(md: str, src_name: str, fallback_title: str = "") -> str:
    title, body = render(md)
    title = title or fallback_title or src_name
    return (
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        f"<title>{html.escape(title)}</title><style>{PAGE_CSS}</style></head>\n"
        f"<body><main>\n<p class=\"src\">Rendered from {html.escape(src_name)}</p>\n{body}\n</main></body></html>\n"
    )


EMBED_RE = re.compile(r"<pre\b[^>]*\bdata-md-render\b[^>]*>\s*(?:<code\b[^>]*>)?(.*?)(?:</code>\s*)?</pre>",
                      re.S | re.I)
EMBED_CSS_RE = re.compile(r"<style data-md-render-css>.*?</style>\n?", re.S)


def embed(text: str) -> tuple[str, int]:
    """Replace each marked block with its rendering. Returns (page, blocks rendered)."""
    count = 0

    def repl(m):
        nonlocal count
        count += 1
        _, body = render(html.unescape(m.group(1)))
        return f'<div class="md-render">\n{body}\n</div>'

    out = EMBED_RE.sub(repl, text)
    if not count:
        return text, 0
    out = EMBED_CSS_RE.sub("", out)
    style = f"<style data-md-render-css>{EMBED_CSS}</style>\n"
    m = re.search(r"</head\s*>", out, re.I)
    if m:
        out = out[:m.start()] + style + out[m.start():]
    else:
        out = style + out
    return out, count


def main(argv: list[str]) -> int:
    if len(argv) >= 4 and argv[1] == "page":
        src, dst = argv[2], argv[3]
        fallback = argv[4] if len(argv) > 4 else ""
        try:
            with open(src, encoding="utf-8") as f:
                md = f.read()
        except (OSError, UnicodeDecodeError) as e:
            print(f"_md-page: cannot read {src}: {e}", file=sys.stderr)
            return 1
        with open(dst, "w", encoding="utf-8") as f:
            f.write(page(md, os.path.basename(src), fallback))
        return 0
    if len(argv) == 3 and argv[1] == "embed":
        try:
            with open(argv[2], encoding="utf-8") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError) as e:
            print(f"_md-page: cannot read {argv[2]}: {e}", file=sys.stderr)
            return 1
        out, n = embed(text)
        sys.stdout.write(out)
        print(f"_md-page: rendered {n} markdown block(s)", file=sys.stderr)
        return 0
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
