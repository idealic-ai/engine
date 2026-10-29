#!/usr/bin/env bash
# Offline harness for the ONE question a publish must be able to answer: WHICH STORE got the bytes.
#
# The premise, measured on this machine: there are two local proof stores and both buckets are
# literally named `proofs`. Only the endpoint PORT separates them, and the other store answers the
# same prefix — so a publish to the wrong one SUCCEEDS, exits 0, and returns a URL. Every
# machine-readable identity the publisher printed or asserted was bucket+prefix, which is
# `proofs/proofs` on both. A check satisfied by a publish to the wrong store is worse than no
# check, because its pass is read as evidence.
#
# So: case A establishes that a bucket comparison CANNOT discriminate (it is the control for the
# whole file — if it ever fails, the premise has changed and the rest of this is theatre), and the
# remaining cases require the port.
#
# Second half: a bare sha comparison at publish fails without meaning it, because the publisher
# REWRITES the page before uploading (a shared-state config for a board, an explicit no-ticket-data
# meta for a page with ticket refs). Verification must compare against the bytes that were SENT and
# state the delta from the source — never expect an identical hash.
#
# NO AWS, NO NETWORK. Shims record argv and serve objects from a local directory.
#
# Run:  ~/.claude/engine/skills/prove/assets/__tests__/destination-discriminator.test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$(cd "$here/.." && pwd)"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
have() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

tmp="$(mktemp -d -t prove-dest)"
trap 'rm -rf "$tmp"' EXIT

KIT_PORT=9440      # the kit store
FINCH_PORT=9010    # the finch store — same bucket name, same prefix, different bytes

# --- shims -------------------------------------------------------------------
# The fake store is a DIRECTORY per endpoint, so "the other store answers the same key" is
# reproducible: a get-object against the wrong endpoint finds somebody else's object rather than
# a 404, which is the whole reason a status code cannot stand in for a content check.
mkdir -p "$tmp/bin" "$tmp/store/$KIT_PORT" "$tmp/store/$FINCH_PORT"
cat > "$tmp/bin/aws" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_SHIM_LOG"
# Which store this call is aimed at, taken from the PORT in --endpoint-url. No port → AWS.
port="aws"
prev=""
for a in "$@"; do
  [ "$prev" = "--endpoint-url" ] && port="${a##*:}"
  prev="$a"
done
dir="$AWS_SHIM_STORE/$port"
mkdir -p "$dir"
case "$1 ${2:-}" in
  "sts get-caller-identity") echo "arn:aws:iam::000000000000:user/testuser"; exit 0 ;;
  "configure export-credentials") exit 1 ;;
  "s3api head-object") exit 1 ;;
  "s3api list-objects-v2") echo '{}'; exit 0 ;;
esac
case "$*" in
  *"s3 cp"*)
    # argv: s3 cp <src> s3://bucket/key ...
    src=""; key=""
    i=0; for a in "$@"; do
      i=$((i+1))
      case "$a" in s3://*) key="${a#s3://}"; key="${key#*/}" ;; esac
      [ "$i" = 3 ] && src="$a"
    done
    if [ -n "$src" ] && [ -f "$src" ] && [ -n "$key" ]; then
      mkdir -p "$dir/$(dirname "$key")"
      cp "$src" "$dir/$key"
    fi
    exit 0 ;;
  *"s3api get-object"*)
    # Walk argv skipping --flag VALUE pairs, so the one bare positional left is the output path.
    # A naive "last non-dash argument" lands on --endpoint-url's value instead, which is how this
    # shim first reported a clean read of a file it never wrote.
    key=""; out=""; skip=0
    for a in "$@"; do
      if [ "$skip" = 1 ]; then skip=0; continue; fi
      case "$a" in
        --key)  skip=1; want_key=1; continue ;;
        --*)    skip=1; continue ;;
        s3api|get-object) continue ;;
        *)      out="$a" ;;
      esac
    done
    prev=""
    for a in "$@"; do [ "$prev" = "--key" ] && key="$a"; prev="$a"; done
    if [ -n "$key" ] && [ -f "$dir/$key" ] && [ -n "$out" ]; then
      cp "$dir/$key" "$out"
      # TAMPER: the control for the content check. When armed, the store hands back a DIFFERENT
      # body at a key that exists, which is precisely what a wrong-store read looks like.
      [ -n "${AWS_SHIM_TAMPER:-}" ] && printf 'TAMPERED\n' >> "$out"
      echo '{"ContentLength": 1}'
      exit 0
    fi
    exit 1 ;;
esac
exit 0
SHIM
chmod +x "$tmp/bin/aws"

cat > "$tmp/bin/curl" <<'CSHIM'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*) url="$a";; esac; done
case " $* " in
  *" -w "*) case "$url" in http://127.0.0.1:*) printf '200' ;; *) printf '404' ;; esac ;;
esac
exit 0
CSHIM
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export AWS_SHIM_STORE="$tmp/store"

# --- the two env files, differing ONLY in the port ---------------------------
mkenv() { # mkenv FILE PORT
  cat > "$1" <<EOF
PROVE_S3_BUCKET=proofs
PROVE_S3_PREFIX=proofs
PROVE_S3_REGION=us-east-2
PROVE_S3_ENDPOINT=http://127.0.0.1:$2
EOF
}
mkenv "$tmp/kit.env"   "$KIT_PORT"
mkenv "$tmp/finch.env" "$FINCH_PORT"

mkpage() { # mkpage FILE [decision]
  if [ "${2:-}" = "decision" ]; then
    cat > "$1" <<'P'
<!doctype html><html><head><title>Dest</title></head>
<body><div data-fb-board="b1"><div data-fb-item="o1"><input type="checkbox" data-fb-key="o1"> one</div></div>
<!-- __PROVE_STATE_CONFIG__ --></body></html>
P
  else
    printf '<!doctype html><html><head><title>Dest</title></head><body><p>plain</p></body></html>\n' > "$1"
  fi
}

# run PORT_ENV PAGE → stderr into $tmp/run.err, stdout (the url) echoed, exit status in $RUN_RC
run() {
  local envfile="$1" page="$2" tag="$3"
  export AWS_SHIM_LOG="$tmp/$tag.log"; : > "$AWS_SHIM_LOG"
  ( export PROVE_S3_ENV="$envfile" PROVE_S3_USER=testuser
    unset PROVE_S3_BUCKET PROVE_S3_ENDPOINT PROVE_S3_PREFIX PROVE_S3_PROFILE \
          PROVE_S3_PUBLIC_BASE PROVE_S3_REGION
    "$assets/publish-s3.sh" "$page" "dest-$tag" 2>"$tmp/$tag.err" )
  RUN_RC=$?
  return 0
}

# ══ A. THE PREMISE — a bucket comparison cannot tell the two stores apart ════
echo "== A. the premise: both stores answer 'proofs', so the bucket is not an identity =="
A_KIT=$(sed -n 's/^PROVE_S3_BUCKET=//p' "$tmp/kit.env")
A_FIN=$(sed -n 's/^PROVE_S3_BUCKET=//p' "$tmp/finch.env")
if [ "$A_KIT" = "$A_FIN" ] && [ -n "$A_KIT" ]; then
  ok "A1: the two configs' bucket names are identical ('$A_KIT') — a bucket check is a no-op here"
else
  no "A1: the premise holds" "buckets differ ('$A_KIT' vs '$A_FIN') — this whole file assumes they do not"
fi
A_PK=$(sed -n 's#^PROVE_S3_ENDPOINT=.*:##p' "$tmp/kit.env")
A_PF=$(sed -n 's#^PROVE_S3_ENDPOINT=.*:##p' "$tmp/finch.env")
if [ "$A_PK" != "$A_PF" ]; then
  ok "A2: the ports differ ($A_PK vs $A_PF) — the port is the only discriminator available"
else
  no "A2: the ports differ" "both $A_PK"
fi

# ══ B. THE RESOLVED ENDPOINT, WITH ITS PORT, IS STATED BEFORE A BYTE MOVES ══
echo "== B. the publisher states the endpoint it resolved, port included =="
mkpage "$tmp/plain.html"
run "$tmp/kit.env" "$tmp/plain.html" kit
B_ERR="$(cat "$tmp/kit.err")"
if [ "$RUN_RC" = 0 ]; then ok "B0: the publish succeeds against the declared store"
else no "B0: publish succeeds" "rc=$RUN_RC: $(tail -3 "$tmp/kit.err")"; fi

if have "$B_ERR" "127.0.0.1:$KIT_PORT"; then
  ok "B1: the resolved endpoint including the port appears in the output"
else
  no "B1: endpoint with port stated" "no '127.0.0.1:$KIT_PORT' in stderr"
fi

# The statement must precede the upload. A destination named only after the bytes landed is a
# receipt, not a check.
B_LINE=$(grep -n "127.0.0.1:$KIT_PORT" "$tmp/kit.err" 2>/dev/null | head -1 | cut -d: -f1)
B_CP=$(grep -n "s3 cp\|upload" "$tmp/kit.err" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$B_LINE" ] && { [ -z "$B_CP" ] || [ "$B_LINE" -le "$B_CP" ]; }; then
  ok "B2: the destination is stated before the upload chatter"
else
  no "B2: stated before the upload" "endpoint at line ${B_LINE:-none}, upload at line ${B_CP:-none}"
fi

# ══ C. THE TWO STORES PRODUCE DIFFERENT DESTINATION TEXT ════════════════════
#
# The discriminating case. Two runs identical but for the port must read differently. A publisher
# whose destination output is byte-identical for both stores has told the reader nothing.
echo "== C. the two stores are distinguishable in the output =="
run "$tmp/finch.env" "$tmp/plain.html" finch
C_ERR="$(cat "$tmp/finch.err")"
if have "$C_ERR" "127.0.0.1:$FINCH_PORT"; then
  ok "C1: the second store's own port is stated"
else
  no "C1: second port stated" "no '127.0.0.1:$FINCH_PORT' in stderr"
fi

# Reduce each run to the lines naming a destination and compare. Identical text = no discriminator.
C_A=$(grep -o "127\.0\.0\.1:[0-9]*" "$tmp/kit.err"   2>/dev/null | sort -u | tr '\n' ' ')
C_B=$(grep -o "127\.0\.0\.1:[0-9]*" "$tmp/finch.err" 2>/dev/null | sort -u | tr '\n' ' ')
if [ -n "$C_A" ] && [ "$C_A" != "$C_B" ]; then
  ok "C2: the destination text differs between the stores ('$C_A' vs '$C_B')"
else
  no "C2: destination text discriminates" "kit='$C_A' finch='$C_B'"
fi

# ══ D. AN AMBIENT OVERRIDE OF THE DECLARED ENDPOINT IS REFUSED ══════════════
#
# The measured shape of a misdirected publish: the file names one store and something in the
# environment wins. The bucket matches, the prefix matches, the publish succeeds — and the page is
# in the other store. Only a port comparison can refuse this.
echo "== D. the file declares one port and the environment another: REFUSED =="
export AWS_SHIM_LOG="$tmp/override.log"; : > "$AWS_SHIM_LOG"
D_OUT=$( export PROVE_S3_ENV="$tmp/kit.env" PROVE_S3_USER=testuser
         export PROVE_S3_ENDPOINT="http://127.0.0.1:$FINCH_PORT"
         unset PROVE_S3_BUCKET PROVE_S3_PREFIX PROVE_S3_PROFILE PROVE_S3_PUBLIC_BASE
         "$assets/publish-s3.sh" "$tmp/plain.html" dest-override 2>&1 >/dev/null )
D_RC=$?
if [ "$D_RC" != 0 ]; then
  ok "D1: the publish is refused (rc=$D_RC) rather than landing in the other store"
else
  no "D1: refused" "exited 0 — the page went to whichever store won, silently"
fi
if have "$D_OUT" "$KIT_PORT" && have "$D_OUT" "$FINCH_PORT"; then
  ok "D2: the refusal names BOTH the declared and the attempted port"
else
  no "D2: both ports named" "$D_OUT"
fi
if grep -q "s3 cp" "$tmp/override.log" 2>/dev/null; then
  no "D3: nothing was uploaded before the refusal" "an s3 cp reached the shim"
else
  ok "D3: the refusal happens before any byte moves"
fi

# ══ E. VERIFY BY CONTENT, WITH THE PUBLISHER'S OWN REWRITE ACCOUNTED FOR ════
#
# A board is REWRITTEN before upload (a shared-state config is injected), so the uploaded bytes
# differ from the source by design. The comparison basis must be what was SENT; a source-sha
# comparison reports a mismatch that means nothing, and a lane that trusts it either ignores a
# real mismatch next time or republishes a page that was fine.
echo "== E. the page is read back and compared to the bytes that were sent =="
mkpage "$tmp/board.html" decision
unset AWS_SHIM_TAMPER
run "$tmp/kit.env" "$tmp/board.html" board
E_ERR="$(cat "$tmp/board.err")"
if [ "$RUN_RC" = 0 ]; then ok "E0: a board publishes clean"
else no "E0: board publishes" "rc=$RUN_RC: $(tail -5 "$tmp/board.err")"; fi

if grep -q "get-object" "$tmp/board.log" 2>/dev/null; then
  ok "E1: the object is fetched back after the upload"
else
  no "E1: object read back" "no get-object in the shim log — nothing was verified"
fi
if printf '%s' "$E_ERR" | grep -qiE "verified by content|content verified|sha256 match"; then
  ok "E2: the output states the verification was by content"
else
  no "E2: content verification stated" "$(printf '%s' "$E_ERR" | tail -5)"
fi
# The delta from the source must be NAMED, not hidden: that is what stops the next reader
# concluding the bytes were corrupted.
if printf '%s' "$E_ERR" | grep -qiE "differ|delta|rewrit|inject"; then
  ok "E3: the byte delta between source and uploaded page is stated"
else
  no "E3: delta stated" "a board was rewritten and nothing said so"
fi

# ══ F. THE CONTROL — a tampered read-back must FAIL ═════════════════════════
#
# Without this, E's pass is consistent with a verification that compares nothing.
echo "== F. control: a read-back that differs from what was sent must fail =="
export AWS_SHIM_TAMPER=1
run "$tmp/kit.env" "$tmp/plain.html" tamper
F_ERR="$(cat "$tmp/tamper.err")"
unset AWS_SHIM_TAMPER
if [ "$RUN_RC" != 0 ]; then
  ok "F1: a mismatching read-back fails the publish (rc=$RUN_RC)"
else
  no "F1: mismatch fails" "exited 0 — the content check cannot discriminate and E means nothing"
fi
if printf '%s' "$F_ERR" | grep -qiE "mismatch|does not match|differs from"; then
  ok "F2: the failure says the fetched bytes are not the bytes sent"
else
  no "F2: mismatch named" "$(printf '%s' "$F_ERR" | tail -5)"
fi

printf '\n  %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
