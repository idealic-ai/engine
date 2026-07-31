#!/usr/bin/env python3
"""Mint an S3 presigned POST for the events/<doc>/ prefix — pure stdlib SigV4, no boto3.

Emits {"postUrl", "keyPrefix", "fields", "expiresAt", "expirySeconds", "expiryRequested",
"expiryClampedBy"} JSON on stdout. A browser then POSTs multipart/form-data to postUrl with:
every `fields` entry, a `key` that starts with keyPrefix, a `Content-Type`, and the `file` —
landing one object under events/<doc>/. The POST is authorized by the signature (NOT anonymous
public write), so no bucket public-write is needed.

A presign cannot outlive the credential that signed it, so `expiresAt` is clamped to
AWS_CREDENTIAL_EXPIRATION when the environment declares one. Without that clamp the emitted
value is `now + <whatever was asked for>`, which S3 rejects at REQUEST time — on the reader's
machine, long after publish, as ExpiredToken rather than a policy expiry. Long-lived keys
declare no expiration, so the clamp is a no-op for them and the full window is real.

Config (env):  PROVE_S3_BUCKET, PROVE_S3_REGION (default us-east-2), PROVE_S3_EVENTS_PREFIX (default events)
Creds  (env):  AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN (optional),
               AWS_CREDENTIAL_EXPIRATION (optional; `aws configure export-credentials --format env` emits it)
Args:          <doc> [expiry_seconds<=604800] [max_bytes]
"""
import os, sys, json, hmac, hashlib, base64, datetime


S3_MAX_EXPIRY = 604800   # 7 days — the protocol ceiling, not a policy choice
DEFAULT_EXPIRY = 3600    # emitted as expiryRequested so a caller that omits the arg can see it


def _sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def _credential_expiry():
    """When the signing credential itself dies, if the environment says so."""
    raw = os.environ.get("AWS_CREDENTIAL_EXPIRATION")
    if not raw:
        return None
    try:
        return datetime.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        # An unparseable expiry must not be read as "no expiry" — that is the failure this
        # whole function exists to prevent. Fail closed with a sane instant rather than
        # datetime.min, which would bake a year-0001 timestamp into a published page.
        return datetime.datetime.now(datetime.timezone.utc)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: sign-post.py <doc> [expiry_seconds] [max_bytes]")
    doc = sys.argv[1]
    requested = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_EXPIRY
    expiry = min(requested, S3_MAX_EXPIRY)
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
    expires_dt = now + datetime.timedelta(seconds=expiry)
    clamped_by = "s3-max" if requested > S3_MAX_EXPIRY else None
    cred_expiry = _credential_expiry()
    if cred_expiry is not None and cred_expiry < expires_dt:
        expires_dt = cred_expiry
        clamped_by = "credential"
    expiry = max(0, int((expires_dt - now).total_seconds()))
    expires_at = expires_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
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
        "expirySeconds": expiry,
        "expiryRequested": requested,
        "expiryClampedBy": clamped_by,
    }))


if __name__ == "__main__":
    main()
