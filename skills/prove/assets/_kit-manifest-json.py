#!/usr/bin/env python3
"""Turn kit-manifest.sh's TSV into the published index, kit/kit-manifest.json.

Usage:  KIT_BASE_URL=<url> _kit-manifest-json.py <rows.tsv>   # JSON to stdout

This object is the answer to "what does proof-blocks.v2.css currently resolve to?" — the question
nothing in the system could answer before, which is how one declared version came to name several
different bodies. It is deliberately the ONE object in the kit with no content address: an index
that could not be updated would be an index of the past.
"""
import json
import os
import sys

rows = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    name, alias, cas, sha, size, ctype = line.split("\t")
    _, _, tail = alias.partition(".v")
    head = tail.split(".")[0] if tail else ""
    rows.append({
        "source": name,
        "version": int(head) if head.isdigit() else None,
        "alias": alias,
        "contentAddress": cas,
        "sha256": sha,
        "bytes": int(size),
        "contentType": ctype,
    })

# No publish timestamp in the body, deliberately. One was here and it made the index differ on every
# run even when no asset had changed — which turned "publishing identical bytes is a no-op" into a
# guaranteed conflict, and (because the guard is atomic) blocked the whole run. The object's own
# LastModified already records when it was written; a field that invalidates itself records nothing.
json.dump({
    "schema": "prove/kit-manifest@1",
    "base": os.environ["KIT_BASE_URL"],
    "note": ("alias is mutable and receives fixes; contentAddress is immutable and pins these exact "
             "bytes. A page chooses per reference."),
    "assets": rows,
}, sys.stdout, indent=2)
sys.stdout.write("\n")
