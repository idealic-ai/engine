#!/usr/bin/env python3
"""Mint an S3 presigned POST for the events/<doc>/ prefix — pure stdlib SigV4, no boto3.

Emits {"postUrl", "keyPrefix", "fields", "expiresAt"} JSON on stdout. A browser then POSTs
multipart/form-data to postUrl with: every `fields` entry, a `key` that starts with keyPrefix,
a `Content-Type`, and the `file` — landing one object under events/<doc>/. The POST is authorized
by the signature (NOT anonymous public write), so no bucket public-write is needed.

Config (env):  PROVE_S3_BUCKET, PROVE_S3_REGION (default us-east-2), PROVE_S3_EVENTS_PREFIX (default events)
Creds  (env):  AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN (optional)
Args:          <doc> [expiry_seconds<=604800] [max_bytes]
"""
import os, sys, json, hmac, hashlib, base64, datetime


def _sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: sign-post.py <doc> [expiry_seconds] [max_bytes]")
    doc = sys.argv[1]
    expiry = min(int(sys.argv[2]) if len(sys.argv) > 2 else 3600, 604800)  # S3 caps at 7 days
    max_bytes = int(sys.argv[3]) if len(sys.argv) > 3 else 16384

    bucket = os.environ["PROVE_S3_BUCKET"]
    region = os.environ.get("PROVE_S3_REGION", "us-east-2")
    eprefix = os.environ.get("PROVE_S3_EVENTS_PREFIX", "events")
    ak = os.environ["AWS_ACCESS_KEY_ID"]
    sk = os.environ["AWS_SECRET_ACCESS_KEY"]
    token = os.environ.get("AWS_SESSION_TOKEN")

    now = datetime.datetime.now(datetime.timezone.utc)
    amzdate = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    expires_at = (now + datetime.timedelta(seconds=expiry)).strftime("%Y-%m-%dT%H:%M:%SZ")
    key_prefix = f"{eprefix}/{doc}/"
    credential = f"{ak}/{datestamp}/{region}/s3/aws4_request"

    conditions = [
        {"bucket": bucket},
        ["starts-with", "$key", key_prefix],
        ["content-length-range", 0, max_bytes],
        {"x-amz-algorithm": "AWS4-HMAC-SHA256"},
        {"x-amz-credential": credential},
        {"x-amz-date": amzdate},
        ["starts-with", "$Content-Type", ""],
    ]
    if token:
        conditions.append({"x-amz-security-token": token})

    policy_b64 = base64.b64encode(
        json.dumps({"expiration": expires_at, "conditions": conditions}).encode("utf-8")
    ).decode("utf-8")

    signing_key = _sign(_sign(_sign(_sign(("AWS4" + sk).encode("utf-8"), datestamp), region), "s3"), "aws4_request")
    signature = hmac.new(signing_key, policy_b64.encode("utf-8"), hashlib.sha256).hexdigest()

    fields = {
        "x-amz-algorithm": "AWS4-HMAC-SHA256",
        "x-amz-credential": credential,
        "x-amz-date": amzdate,
        "policy": policy_b64,
        "x-amz-signature": signature,
    }
    if token:
        fields["x-amz-security-token"] = token

    host = f"{bucket}.s3.amazonaws.com" if region == "us-east-1" else f"{bucket}.s3.{region}.amazonaws.com"
    print(json.dumps({
        "postUrl": f"https://{host}/",
        "keyPrefix": key_prefix,
        "fields": fields,
        "expiresAt": expires_at,
    }))


if __name__ == "__main__":
    main()
