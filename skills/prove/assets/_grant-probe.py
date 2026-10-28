#!/usr/bin/env python3
"""Spend a minted presigned-POST grant ONCE against its own destination and report the verdict.

usage: _grant-probe.py <mint.json> <key>
stdout: exactly one line —
    accepted <http>
    refused <http> <S3ErrorCode>
    unverified <reason>
Exit status is always 0: the verdict is the stdout line, and a publisher that read an exit
status through a pipe would read the pipeline's last command instead.

A minted grant is not an accepted grant. The three facts a publisher needs to tell apart are
whether the destination TOOK the write, whether it REFUSED it, and whether the probe never
reached the destination to ask — collapsing the third into either of the first two is how a
board ships a grant nobody has ever spent.

The multipart body is the one board-widgets.js sends: every signed field, then `key`, then
`Content-Type`, then `file` LAST. A probe that posted a different shape could pass while the
widget's own post failed the same policy.
"""
import json
import sys
import urllib.error
import urllib.request
import uuid

PROBE_BODY = b'{"probe":"grant-verification"}'


def refusal_code(body: bytes) -> str:
    text = body.decode("utf-8", "replace")
    start = text.find("<Code>")
    if start < 0:
        return "unknown"
    end = text.find("</Code>", start)
    return text[start + 6:end] if end > start else "unknown"


def main() -> None:
    if len(sys.argv) < 3:
        print("unverified usage: _grant-probe.py <mint.json> <key>")
        return
    try:
        mint = json.load(open(sys.argv[1], encoding="utf-8"))
        post_url = mint["postUrl"]
        fields = mint["fields"]
    except Exception as exc:
        print("unverified the mint could not be read (%s)" % type(exc).__name__)
        return
    key = sys.argv[2]

    boundary = "----proveGrantProbe" + uuid.uuid4().hex

    def part(name, value):
        return ('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n'
                % (boundary, name, value)).encode("utf-8")

    body = b"".join(part(k, v) for k, v in fields.items())
    body += part("key", key)
    body += part("Content-Type", "application/json")
    body += ('--%s\r\nContent-Disposition: form-data; name="file"; filename="probe.json"\r\n'
             'Content-Type: application/json\r\n\r\n' % boundary).encode("utf-8")
    body += PROBE_BODY + b"\r\n"
    body += ("--%s--\r\n" % boundary).encode("utf-8")

    request = urllib.request.Request(
        post_url, data=body,
        headers={"Content-Type": "multipart/form-data; boundary=%s" % boundary},
    )
    try:
        response = urllib.request.urlopen(request, timeout=20)
        print("accepted %d" % response.status)
    except urllib.error.HTTPError as err:
        # The destination answered and said no. This is the verdict that must drop the grant.
        print("refused %d %s" % (err.code, refusal_code(err.read())))
    except Exception as exc:
        # Nothing was established either way — a store that is down, a DNS failure, a proxy.
        # Reporting this as a refusal would strip a working grant off a board for a network blip.
        print("unverified the probe could not reach %s (%s)" % (post_url, type(exc).__name__))


if __name__ == "__main__":
    main()
