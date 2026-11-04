#!/usr/bin/env python3
"""IDE-338 ASKCOUNCIL: render a Council Report (.md) as one self-contained HTML page.

`engine ask attach-panel --council` takes an http(s) URL only, so a council report has to be
published before its reads are attached. The renderer is /prove's shared one,
skills/prove/assets/_md-page.py (headings, paragraphs, quotes, lists, tables, fenced code, inline
code, bold, italic and links; every character escaped; no script, no remote asset). publish-s3.sh
now also renders a .md handed to it directly, so this wrapper is kept for callers that want the
page on disk first.

Usage:  council-page.py <report.md> <out.html>
Then:   ~/.claude/engine/skills/prove/assets/publish-s3.sh <out.html> <slug>
"""
import importlib.util
import os
import sys

_MD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "prove", "assets", "_md-page.py")


def _load():
    spec = importlib.util.spec_from_file_location("_md_page", _MD)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: council-page.py <report.md> <out.html>", file=sys.stderr)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    try:
        md_page = _load()
    except (OSError, ImportError) as e:
        print(f"council-page: cannot load the shared renderer {_MD}: {e}", file=sys.stderr)
        return 1
    try:
        with open(src, encoding="utf-8") as f:
            md = f.read()
    except OSError as e:
        print(f"council-page: cannot read {src}: {e}", file=sys.stderr)
        return 1
    with open(dst, "w", encoding="utf-8") as f:
        f.write(md_page.page(md, os.path.basename(src), "Council Report"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
