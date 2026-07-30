#!/usr/bin/env python3
"""Test helper: POST a file to an S3 presigned-POST endpoint the way a browser's FormData would.
Faithfully mimics the widget: all signed fields, then `key`, `Content-Type`, then `file` LAST.
usage: post-event.py <mint.json> <event-file> <key>   → prints the HTTP status (204 = stored).
"""
import sys, json, uuid, urllib.request, urllib.error

mint = json.load(open(sys.argv[1]))
event_path, key = sys.argv[2], sys.argv[3]
boundary = "----proveEvent" + uuid.uuid4().hex


def part(name, value):
    return (f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n').encode()


body = b""
for k, v in mint["fields"].items():          # signed policy fields
    body += part(k, v)
body += part("key", key)                     # object key (starts-with the signed prefix)
body += part("Content-Type", "application/json")
data = open(event_path, "rb").read()
body += (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
         f'filename="event.json"\r\nContent-Type: application/json\r\n\r\n').encode() + data + b"\r\n"
body += f"--{boundary}--\r\n".encode()

req = urllib.request.Request(
    mint["postUrl"], data=body,
    headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
)
try:
    r = urllib.request.urlopen(req)
    print(r.status)
except urllib.error.HTTPError as e:
    print(e.code)
    sys.stderr.write(e.read().decode()[:500] + "\n")
