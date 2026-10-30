#!/usr/bin/env python3
"""IDE-338 ASKCOUNCIL: render a Council Report (.md) as one self-contained HTML page.

`engine ask attach-panel --council` takes an http(s) URL only, so a council report has to be
published before its reads are attached. publish-s3.sh publishes HTML, and it refuses a page that
has a <pre> with no language-* class (exit 6). This renders the slice of markdown that
TEMPLATE_COUNCIL.md uses: headings, paragraphs, lists, tables, fenced code, inline code, bold,
italic and links. Every character of the report is escaped, so a report that quotes markup shows
it as text. The page loads no script and no remote asset.

Usage:  council-page.py <report.md> <out.html>
Then:   ~/.claude/engine/skills/prove/assets/publish-s3.sh <out.html> <slug>
"""
import html
import os
import re
import sys

CSS = """
:root { --bg:#fbfaf7; --fg:#1d1c1a; --muted:#6b675f; --line:#e3dfd6; --code:#f1eee7; --accent:#3a5bab; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#16161a; --fg:#e8e6e1; --muted:#a19d94; --line:#2f2e33; --code:#222227; --accent:#8fa8ec; } }
:root[data-theme="dark"] { --bg:#16161a; --fg:#e8e6e1; --muted:#a19d94; --line:#2f2e33; --code:#222227; --accent:#8fa8ec; }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif; }
main { max-width:860px; margin:0 auto; padding:24px 16px 64px; }
h1 { font-size:1.6rem; line-height:1.25; margin:0 0 12px; }
h2 { font-size:1.2rem; margin:32px 0 8px; padding-top:12px; border-top:1px solid var(--line); }
h3 { font-size:1.05rem; margin:22px 0 6px; }
p, li { overflow-wrap:anywhere; }
a { color:var(--accent); }
code, pre { font-family:ui-monospace,"SF Mono",Menlo,monospace; font-size:.88em; font-variant-ligatures:none; }
code { background:var(--code); padding:1px 4px; border-radius:4px; }
pre { background:var(--code); padding:12px; border-radius:6px; overflow-x:auto; white-space:pre; }
pre code { background:none; padding:0; }
.table { overflow-x:auto; }
table { border-collapse:collapse; font-size:.92em; }
th, td { border:1px solid var(--line); padding:4px 8px; text-align:left; vertical-align:top; }
.src { color:var(--muted); font-size:.85em; }
"""


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
    t = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", lambda m: f'<a href="{m.group(2).replace(chr(34), "&quot;")}">{m.group(1)}</a>', t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<![\w*])\*([^*\s][^*]*?)\*(?![\w*])", r"<em>\1</em>", t)
    return t


def render(md: str) -> tuple[str, str]:
    lines = md.split("\n")
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
        fm = re.match(r"^(\s*)(`{3,})\s*([\w+-]*)\s*$", line)
        if fm:
            flush()
            fence, lang = fm.group(2), fm.group(3) or "text"
            body = []
            i += 1
            while i < len(lines) and not re.match(rf"^\s*{fence}\s*$", lines[i]):
                body.append(lines[i])
                i += 1
            i += 1
            out.append(f'<pre class="language-{html.escape(lang)}"><code class="language-{html.escape(lang)}">{html.escape(chr(10).join(body))}</code></pre>')
            continue
        hm = re.match(r"^(#{1,4})\s+(.*)$", line)
        if hm:
            flush()
            level = len(hm.group(1))
            if not title and level == 1:
                title = hm.group(2).strip()
            out.append(f"<h{level}>{inline(hm.group(2).strip())}</h{level}>")
            i += 1
            continue
        if re.match(r"^\s*\|.*\|\s*$", line):
            flush()
            rows = []
            while i < len(lines) and re.match(r"^\s*\|.*\|\s*$", lines[i]):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            body_rows = [r for r in rows if not all(re.fullmatch(r":?-{2,}:?", c) for c in r)]
            if body_rows:
                head, rest = body_rows[0], body_rows[1:]
                t = ["<div class=\"table\"><table><thead><tr>", *(f"<th>{inline(c)}</th>" for c in head), "</tr></thead><tbody>"]
                for r in rest:
                    t.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
                t.append("</tbody></table></div>")
                out.append("".join(t))
            continue
        lm = re.match(r"^\s*([-*]|\d+\.)\s+(.*)$", line)
        if lm:
            flush()
            ordered = lm.group(1)[0].isdigit()
            items = []
            while i < len(lines):
                m = re.match(r"^\s*([-*]|\d+\.)\s+(.*)$", lines[i])
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
        if re.match(r"^\s*(-{3,}|\*{3,})\s*$", line):
            flush()
            out.append("<hr>")
            i += 1
            continue
        if not line.strip():
            flush()
        else:
            para.append(re.sub(r"^>\s?", "", line))
        i += 1
    flush()
    return title or "Council Report", "\n".join(out)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: council-page.py <report.md> <out.html>", file=sys.stderr)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    try:
        with open(src, encoding="utf-8") as f:
            md = f.read()
    except OSError as e:
        print(f"council-page: cannot read {src}: {e}", file=sys.stderr)
        return 1
    title, body = render(md)
    page = (
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        f"<title>{html.escape(title)}</title><style>{CSS}</style></head>\n"
        f"<body><main>\n<p class=\"src\">Rendered from {html.escape(os.path.basename(src))}</p>\n{body}\n</main></body></html>\n"
    )
    with open(dst, "w", encoding="utf-8") as f:
        f.write(page)
    return 0


if __name__ == "__main__":
    sys.exit(main())
