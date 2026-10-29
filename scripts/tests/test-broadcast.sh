#!/bin/bash
# test-broadcast.sh — Tests for scripts/broadcast.sh (`engine broadcast`).
# All against fixtures: a HOP_LIVE_PANES tree (or a stub `tmux` on PATH), a fixture process table
# and session registry, a temp BROADCAST_DIR, and a stub BROADCAST_DELIVER that appends to a file.
# No live tmux, no socket, no fleet message.
#
#   audience — --children / --subtree / --all; missing seat 3; unreadable tree 4; --all skips
#              panes with no Claude session.
#   identity — live-first via fleet_self (fixture and stub-tmux paths); a cache-only identity is
#              refused for a write; --from must be in the tree; flag values cannot be flags.
#   binding  — delivery by pane: mismatch, ambiguity and a same-named pane elsewhere are refused.
#   record   — written (noclobber) before delivery; sent-by; the text inline (cut at the cap) with the
#              sender on the ack line; done marker; resend reads the text back byte for byte.
#   receipts — own-seat acks only; status states; resend; sticky pending/retract/expires/limit.
#   parity   — live_tree() body equals hop.sh's.
#   go       — go-request reaches exactly the CONTRACTS rows' owner seats with their own receipts;
#              unowned / unmapped / dead-seat / empty-receipt rows refuse; ack = GO bound to the
#              receipts, decline needs a one-line reason, outsiders refused; go-check passes on
#              all GOs and a re-pick, fails on pending / declined / an amended commit.
#
# Plant a defect: BROADCAST_SH=<mutated copy> bash test-broadcast.sh — it must go red.

set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

BROADCAST_SH="${BROADCAST_SH:-$HOME/.claude/engine/scripts/broadcast.sh}"
HOP_SH="${HOP_SH:-$HOME/.claude/engine/skills/coordinate/scripts/hop.sh}"
LIB_SH="${BROADCAST_LIB:-$HOME/.claude/engine/scripts/lib.sh}"

# Pipe-free contains (see test-coordinate-hop.sh: grep -q under pipefail can SIGPIPE echo).
assert_has() {
  if grep -qF -- "$1" <<<"$2"; then pass "$3"; else fail "$3" "contains '$1'" "$2"; fi
}
assert_hasnt() {
  if grep -qF -- "$1" <<<"$2"; then fail "$3" "lacks '$1'" "$2"; else pass "$3"; fi
}

FIX=""
setup() {
  FIX="$(mktemp -d)"
  cat > "$FIX/live.txt" <<'EOF'
manager:director %1 -
manager:app %2 manager:director
manager:domain %3 manager:director
app:ask %4 manager:app
app:ui %5 manager:app
ask:helper %6 app:ask
domain:stats %7 manager:domain
scratch: %8 -
services:term %9 -
EOF
  # Each pane's shell is 100N; panes 1-7 run a Claude child 200N registered under the pane label.
  # Pane 9 runs only a plain child process (a shell pane).
  mkdir -p "$FIX/bc" "$FIX/sess" "$FIX/bin"
  : > "$FIX/panepids"; : > "$FIX/ps"
  local n seat
  for n in 1 2 3 4 5 6 7 8 9; do
    echo "%$n 100$n" >> "$FIX/panepids"
    echo "100$n 1" >> "$FIX/ps"
  done
  n=0
  for seat in manager:director manager:app manager:domain app:ask app:ui ask:helper domain:stats; do
    n=$((n + 1)); reg "200$n" "$seat" "100$n"
  done
  echo "3009 1009" >> "$FIX/ps"
  : > "$FIX/sent.log"
  : > "$FIX/failseats"
  cat > "$FIX/stub.sh" <<EOF
#!/bin/bash
# stub delivery: <seat> <pid> <message>
if grep -qxF -- "\$1" "$FIX/failseats"; then echo "undelivered: stub refused \$1"; exit 1; fi
id=\$(sed -n 's/^ack (from [^)]*): engine broadcast ack //p' <<<"\$3")
printf '%s' "\$3" > "$FIX/msg.\$1"   # the raw bytes, per seat (last message wins)
if [ -n "\$id" ] && [ -f "$FIX/bc/\$id.md" ]; then st=record-present; else st=record-absent; fi
printf '%s|%s|%s|%s\n' "\$1" "\$2" "\$st" "\$(printf '%s' "\$3" | tr '\n' '~')" >> "$FIX/sent.log"
echo delivered
EOF
  chmod +x "$FIX/stub.sh"
}
teardown() { rm -rf "$FIX"; }

# reg <pid> <name> <ppid> [kind] [socket] — a live registered Claude session (kind interactive).
# A socket of "-" registers none.
reg() {
  local sock="${5:-/nonexistent/$1.sock}" field=""
  [ "$sock" = - ] || field=",\"messagingSocketPath\":\"$sock\""
  printf '{"pid":%s,"name":"%s","kind":"%s"%s}\n' "$1" "$2" "${4:-interactive}" "$field" > "$FIX/sess/$1.json"
  echo "$1 $3" >> "$FIX/ps"
}

# bc <args…> — run broadcast.sh against the fixtures, bounded by a 10 s alarm (a hang = rc 142).
# Stdout+stderr in OUT, exit code in RC. PANE → TMUX_PANE, SELF → FLEET_PANE (the launch cache),
# TREE → the fixture tree ("none" = no HOP_LIVE_PANES; the stub tmux on PATH answers).
# PANE defaults to %1 (manager:director); PANE=none runs as if outside tmux. DELIVER=real drops the
# stub so the real deliver.ts path runs. LIB → BROADCAST_LIB. CLEAN=1 runs under `env -i` (only
# PATH, HOME and the fixture variables), as launchd, cron and some hook runners do.
OUT="" RC=0
bc() {
  local tree="${TREE:-$FIX/live.txt}" path="$PATH" pane="${PANE-%1}" stub="$FIX/stub.sh"
  local tmuxenv=""
  # The stub-tmux path: no fixture tree; lib.sh reads tmux only inside a tmux client ($TMUX).
  [ "$tree" = none ] && { tree=""; path="$FIX/bin:$PATH"; tmuxenv="$FIX/fake-tmux-socket,1,0"; }
  [ "$pane" = none ] && pane=""
  [ "${DELIVER:-}" = real ] && stub=""
  local clean="" keep=(); [ "${CLEAN:-}" = 1 ] && { clean=-i; keep=(HOME="$HOME" ${BROADCAST_INLINE_MAX:+BROADCAST_INLINE_MAX="$BROADCAST_INLINE_MAX"}); }
  OUT=$(env $clean -u FLEET_PARENT -u FLEET_PANE -u TMUX_PANE -u HOP_CHAIN_FILE -u FLEET_LIVE_PANES \
    -u HOP_TMUX_SOCKET -u FLEET_TMUX_SOCKET -u TMUX \
    ${keep[@]+"${keep[@]}"} PATH="$path" HOP_LIVE_PANES="$tree" BROADCAST_DIR="$FIX/bc" BROADCAST_DELIVER="$stub" \
    BROADCAST_PANE_PIDS="$FIX/panepids" BROADCAST_PS_FILE="$FIX/ps" ASK_SESSIONS_DIR="$FIX/sess" \
    BROADCAST_LIB="${LIB:-$LIB_SH}" ${pane:+TMUX_PANE="$pane"} ${tmuxenv:+TMUX="$tmuxenv"} ${SELF:+FLEET_PANE="$SELF"} \
    perl -e 'alarm 10; exec @ARGV' bash "$BROADCAST_SH" "$@" 2>&1 <<<"${MSG-Use /ask, not AskUserQuestion.}")
  RC=$?
}
audience() { sed -n 's/^audience: //p' <<<"$OUT"; }
sent_count() { grep -c . "$FIX/sent.log" | tr -d ' '; }
nrec() { ls "$FIX/bc" | grep -c '\.md$' | tr -d ' '; }

# A stub tmux for the live path: list-panes prints the fixture; display answers a pane's label
# (or an unset label, "win:", when called as `stub_tmux unset`), its parent and its pid.
stub_tmux() {
  cat > "$FIX/bin/tmux" <<EOF
#!/bin/bash
while [ "\${1:-}" = -L ] || [ "\${1:-}" = -S ]; do shift 2; done
case "\$1" in
  list-panes) cat "$FIX/live.txt" ;;
  display)
    t=""; fmt=""
    shift; while [ \$# -gt 0 ]; do case "\$1" in -p) shift ;; -t) t="\$2"; shift 2 ;; *) fmt="\$1"; shift ;; esac; done
    case "\$fmt" in
      *pane_label*)
        if [ "${1:-set}" = unset ]; then l=\$(awk -v p="\$t" '\$2 == p { split(\$1, a, ":"); print a[1] ":"; exit }' "$FIX/live.txt")
        else l=\$(awk -v p="\$t" '\$2 == p { print \$1; exit }' "$FIX/live.txt"); fi
        # lib.sh may ask for "label|parent" in one display call.
        case "\$fmt" in *"|"*) echo "\$l|\$(awk -v p="\$t" '\$2 == p { print \$3; exit }' "$FIX/live.txt")" ;; *) echo "\$l" ;; esac ;;
      *pane_parent*) awk -v p="\$t" '\$2 == p { print \$3; exit }' "$FIX/live.txt" ;;
      *pane_pid*) awk -v p="\$t" '\$1 == p { print \$2; exit }' "$FIX/panepids" ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FIX/bin/tmux"
}

# ---------------------------------------------------------------- audience
test_children() {
  bc --children --from manager:app --dry-run
  assert_eq 0 "$RC" "children: dry-run exits 0"
  assert_eq "app:ask app:ui" "$(audience)" "children: direct children only"
  assert_has "sent-by: manager:director" "$OUT" "children: --from names the scope, sent-by the caller"
}

test_subtree() {
  bc --subtree manager:app --from manager:director --dry-run
  assert_eq 0 "$RC" "subtree: exits 0"
  assert_eq "app:ask app:ui ask:helper" "$(audience)" "subtree: every descendant, not the seat itself"
}

test_all() {
  bc --all --from manager:director --dry-run
  assert_eq 0 "$RC" "all: exits 0"
  assert_eq "manager:app manager:domain app:ask app:ui ask:helper domain:stats" "$(audience)" \
    "all: every live seat with a Claude session, except the sender"
  assert_has "skipped (no Claude session in pane): services:term" "$OUT" "all: a shell pane is skipped and listed"
  PANE=%2 bc --all --from manager:director --dry-run
  assert_hasnt "manager:app" "$(audience)" "all: the sender (sent-by) is excluded too, not only --from"
}

test_missing_seat() {
  bc --subtree manager:ghost --from manager:director
  assert_eq 3 "$RC" "missing seat: exits 3"
  assert_has "manager:ghost" "$OUT" "missing seat: named in the error"
  assert_eq 0 "$(sent_count)" "missing seat: nothing sent"
  assert_eq 0 "$(nrec)" "missing seat: no record"
}

test_unreadable_tree() {
  TREE="$FIX/nope.txt" bc --all --from manager:director
  assert_eq 4 "$RC" "unreadable tree: exits 4"
  assert_eq 0 "$(sent_count)" "unreadable tree: nothing sent"
}

# ---------------------------------------------------------------- identity (M1, M3, S8)
test_identity_live_fixture() {
  PANE=%2 SELF=manager:domain bc --children --dry-run
  assert_eq 0 "$RC" "identity: live label resolves"
  assert_has "from: manager:app" "$OUT" "identity: the live label wins over a stale FLEET_PANE"
  assert_has "sent-by: manager:app" "$OUT" "identity: sent-by is the live seat"
  assert_eq "app:ask app:ui" "$(audience)" "identity: --children uses the live seat"
  assert_has "stale" "$OUT" "identity: fleet_self's stale note passes through"
}

test_identity_cache_only_refused() {
  PANE=%99 SELF=manager:app bc --children
  assert_eq 2 "$RC" "M3: a cache-only identity is refused for a send"
  assert_has "cache" "$OUT" "M3: the refusal says why"
  assert_eq 0 "$(sent_count)" "M3: nothing sent"
  assert_eq 0 "$(nrec)" "M3: no record"
}

test_identity_stub_tmux_live() {
  stub_tmux set
  TREE=none PANE=%2 SELF=manager:domain bc --children --dry-run
  assert_eq 0 "$RC" "S8: live tmux path resolves"
  assert_has "sent-by: manager:app" "$OUT" "S8: live label from tmux display wins"
  assert_eq "app:ask app:ui" "$(audience)" "S8: tree from tmux list-panes"
}

test_identity_stub_tmux_unset_label() {
  stub_tmux unset
  TREE=none PANE=%2 SELF=manager:domain bc --children
  assert_eq 2 "$RC" "M3: an unset label with a stale FLEET_PANE is refused"
  assert_eq 0 "$(sent_count)" "M3: the other seat's children are not messaged"
}

test_outside_tmux_refused() {
  PANE=none bc --children --from manager:app
  assert_eq 2 "$RC" "F2: outside tmux, --from without a live identity is refused"
  assert_eq 0 "$(sent_count)" "F2: nothing sent"
  assert_eq 0 "$(nrec)" "F2: no record"
  assert_hasnt "unseated" "$OUT" "F2: there is no unseated sender"
}

test_lib_without_fleet_self() {
  printf 'some_other_fn() { :; }\n' > "$FIX/oldlib.sh"
  LIB="$FIX/oldlib.sh" PANE=%2 bc --children
  assert_eq 2 "$RC" "F2: a lib.sh without fleet_self exits 2"
  assert_has "has no fleet_self" "$OUT" "F2: and says so"
  LIB="$FIX/nolib.sh" PANE=%2 bc --children
  assert_eq 2 "$RC" "F2: a BROADCAST_LIB that does not exist is an error"
  assert_has "missing" "$OUT" "F2: named, not silently replaced"
  assert_eq 0 "$(sent_count)" "F2: nothing sent"
}

test_flag_values() {
  bc --all --from --dry-run
  assert_eq 2 "$RC" "M1: --from --dry-run exits 2"
  assert_eq 0 "$(sent_count)" "M1: --from --dry-run sends nothing"
  assert_eq 0 "$(nrec)" "M1: --from --dry-run writes nothing"
  bc --all --from $'app:ui\nsticky: yes'
  assert_eq 2 "$RC" "M1: a newline in --from exits 2"
  bc --all --from 'app:my seat'
  assert_eq 2 "$RC" "M1: whitespace in --from exits 2"
  bc --all --from
  assert_eq 2 "$RC" "S2: --from with no value exits 2 (no hang)"
  bc --subtree
  assert_eq 2 "$RC" "S2: --subtree with no value exits 2"
  bc --all --from manager:ghost
  assert_eq 3 "$RC" "M1: --from not in the live tree exits 3, for --all too"
  assert_eq 0 "$(sent_count)" "M1: nothing sent on any of these"
}

test_usage() {
  bc --from manager:app
  assert_eq 2 "$RC" "usage: no scope exits 2"
  bc --all --children --from manager:app
  assert_eq 2 "$RC" "usage: two scopes exit 2"
  MSG="" bc --all --from manager:app
  assert_eq 2 "$RC" "usage: empty text exits 2"
  bc --all --from manager:app --id "Bad Id"
  assert_eq 2 "$RC" "usage: bad id exits 2"
  bc --all --from manager:app --expires 2030-01-01
  assert_eq 2 "$RC" "usage: --expires without --sticky exits 2"
}

# ---------------------------------------------------------------- record + delivery
test_dry_run_sends_nothing() {
  bc --subtree manager:app --from manager:director --id dry1 --dry-run
  assert_eq 0 "$RC" "dry-run: exits 0"
  assert_eq 0 "$(sent_count)" "dry-run: the delivery stub was never called"
  assert_file_not_exists "$FIX/bc/dry1.md" "dry-run: no record written"
  assert_has "binds app:ask → ok 2004" "$OUT" "dry-run: shows each seat's pane binding"
}

test_send_writes_record() {
  PANE=%2 bc --children --id ask-rules
  assert_eq 0 "$RC" "send: exits 0 when every seat accepted"
  local rec="$FIX/bc/ask-rules.md"
  assert_file_exists "$rec" "send: record written"
  local body; body=$(cat "$rec" 2>/dev/null)
  assert_has "from: manager:app" "$body" "record: from"
  assert_has "sent-by: manager:app" "$body" "record: sent-by"
  assert_has "scope: children:manager:app" "$body" "record: scope"
  assert_has "audience: app:ask app:ui" "$body" "record: audience"
  assert_has "sticky: no" "$body" "record: sticky flag"
  assert_has "Use /ask, not AskUserQuestion." "$body" "record: full text"
  assert_has "delivered app:ask pid=2004" "$body" "record: delivery line per seat, by pid"
  assert_has "done: rc=0 delivered=2 undelivered=0" "$body" "record: completion marker"
  if grep -qE '^at: [0-9]{4}-[0-9]{2}-[0-9]{2}T' <<<"$body"; then pass "record: time"; else fail "record: time" "at: ISO" "$body"; fi
  local sent; sent=$(cat "$FIX/sent.log")
  assert_eq 2 "$(sent_count)" "send: one message per seat"
  assert_has "app:ask|2004|record-present|Use /ask, not AskUserQuestion.~ack (from manager:app): engine broadcast ack ask-rules" \
    "$sent" "message: the text then the ack line, to the pane's pid, with the record already on disk"
  assert_hasnt "read $rec" "$sent" "message: no pointer to the record when the text fits"
  assert_hasnt "audience:" "$sent" "message: the header and delivery list stay out of the message"
  assert_hasnt "ask:helper" "$sent" "send: grandchild not messaged under --children"
}

test_long_text_is_cut_with_the_record_path() {
  local long; long=$(printf 'x%.0s' $(seq 1600))
  MSG="$long" PANE=%2 bc --children --id long1
  assert_eq 0 "$RC" "long: send exits 0"
  local sent; sent=$(cat "$FIX/sent.log")
  assert_has "full text: $FIX/bc/long1.md~ack (from manager:app): engine broadcast ack long1" "$sent" "long: past the cap the message gives the record path, then the ack line"
  assert_hasnt "$long" "$sent" "long: the text is cut at the cap"
  assert_has "$long" "$(cat "$FIX/bc/long1.md")" "long: the record keeps the full text"
}

test_text_dash_n() {
  MSG="-n" bc --children --from manager:app --id dashn
  assert_eq "-n" "$(sed -n '/^## Text/,/^## Delivery/p' "$FIX/bc/dashn.md" | sed '1,2d' | sed -n 1p)" "N1: a text of '-n' survives"
}

test_undelivered() {
  echo app:ui > "$FIX/failseats"
  bc --children --from manager:app --id partial1
  assert_eq 1 "$RC" "undelivered: exits 1"
  local body; body=$(cat "$FIX/bc/partial1.md" 2>/dev/null)
  assert_has "undelivered app:ui" "$body" "undelivered: recorded per seat"
  assert_has "delivered app:ask" "$body" "undelivered: the others still sent"
}

test_duplicate_id() {
  bc --children --from manager:app --id dup1
  bc --children --from manager:app --id dup1
  assert_eq 2 "$RC" "duplicate id: refused with 2"
  assert_eq 2 "$(sent_count)" "duplicate id: second send delivered nothing"
}

test_bind_by_pane() {
  # app:ui's pane runs a session registered under another name; app:ask's pane holds two sessions;
  # a new pane labelled domain:studio (the name app:ui's session carries) has no session itself.
  reg 2005 domain:studio 1005
  reg 2104 app:ask 1004
  echo "domain:studio %10 manager:domain" >> "$FIX/live.txt"; echo "%10 1010" >> "$FIX/panepids"; echo "1010 1" >> "$FIX/ps"
  bc --children --from manager:app --id bind1
  assert_eq 1 "$RC" "M2: exits 1 when a seat cannot be bound"
  local body; body=$(cat "$FIX/bc/bind1.md")
  assert_has "undelivered app:ui — mismatch 2005:domain:studio" "$body" "M2: registry name ≠ pane label is undelivered, named"
  assert_has "undelivered app:ask — ambiguous" "$body" "M2: two sessions in one pane is undelivered"
  bc --children --from manager:domain --id bind2
  assert_has "undelivered domain:studio — no-session" "$(cat "$FIX/bc/bind2.md")" "M2: a same-named pane elsewhere is not a target"
  assert_hasnt "|2005|" "$(cat "$FIX/sent.log")" "M2: nothing reaches the out-of-scope pid"
}

test_bind_ignores_bg_sessions() {
  # A daemon under app:ask's interactive session hosts a bg spare registered for another seat.
  echo "3104 2004" >> "$FIX/ps"; reg 3204 app:ui 3104 bg
  bc --children --from manager:app --dry-run
  assert_has "binds app:ask → ok 2004 app:ask" "$OUT" "F1: a bg session under the pane does not make it ambiguous"
  # app:ui's interactive session registered no socket; a bg spare under it carries the seat's name.
  reg 2005 app:ui 1005 interactive -
  reg 3105 app:ui 2005 bg
  bc --children --from manager:app --id bg1
  assert_has "undelivered app:ui — no-session" "$(cat "$FIX/bc/bg1.md")" "F1: a bg spare is never the target"
  assert_hasnt "|3105|" "$(cat "$FIX/sent.log")" "F1: nothing reaches the spare"
}

# The real deliver.ts path, no stub: two live scratch listeners both registered as app:ask, only
# one of them under app:ask's pane. The in-pane socket must get exactly one line: one user message
# holding the text and the ack line.
test_real_deliver_path() {
  command -v node >/dev/null 2>&1 || { skip "real deliver: node not found"; return; }
  local d; d=$(mktemp -d /tmp/bcsock.XXXXXX)
  cat > "$d/listen.mjs" <<'EOF2'
import net from "node:net"; import fs from "node:fs";
const [sock, out] = process.argv.slice(2);
net.createServer((c) => c.on("data", (b) => fs.appendFileSync(out, b))).listen(sock, () => fs.writeFileSync(out + ".ready", ""));
EOF2
  node "$d/listen.mjs" "$d/a.sock" "$d/a.out" & local pa=$!
  node "$d/listen.mjs" "$d/b.sock" "$d/b.out" & local pb=$!
  local i=0; while { [ ! -e "$d/a.out.ready" ] || [ ! -e "$d/b.out.ready" ]; } && [ $i -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
  : > "$d/a.out"; : > "$d/b.out"
  rm -f "$FIX/sess/2004.json"
  reg "$pa" app:ask 1004 interactive "$d/a.sock"
  reg "$pb" app:ask 1 interactive "$d/b.sock"
  DELIVER=real bc --children --from manager:app --id real1
  kill "$pa" "$pb" 2>/dev/null; wait "$pa" "$pb" 2>/dev/null
  assert_has "delivered app:ask pid=$pa" "$(cat "$FIX/bc/real1.md")" "real deliver: the in-pane session is delivered"
  assert_eq 1 "$(grep -c . "$d/a.out")" "real deliver: exactly one line on the in-pane socket"
  assert_has '"content":"Use /ask, not AskUserQuestion.\nack (from manager:director): engine broadcast ack real1"' "$(cat "$d/a.out")" "real deliver: the text and ack line, as one user message"
  assert_eq 0 "$(grep -c . "$d/b.out")" "real deliver: the same-named session outside the pane gets nothing"
  rm -rf "$d"
}

# ---------------------------------------------------------------- receipts
test_ack_status() {
  bc --children --from manager:app --id ackme
  PANE=%4 bc ack ackme
  assert_eq 0 "$RC" "ack: exits 0"
  assert_has "acked: app:ask" "$OUT" "ack: records the caller's own seat"
  PANE=%4 bc ack ackme
  assert_has "already acked" "$OUT" "ack: repeated ack is a no-op"
  assert_eq 1 "$(ls "$FIX/bc/ackme.acks.d" | grep -c .)" "ack: one marker"
  bc status ackme
  assert_eq 0 "$RC" "status: exits 0"
  assert_has $'app:ask\tdelivered\tacked' "$OUT" "status: delivered + acked"
  assert_has $'app:ui\tdelivered\tnot-acked' "$OUT" "status: delivered + not acked"
  assert_has "complete: yes" "$OUT" "status: completion marker"
  PANE=%7 bc ack ackme
  assert_eq 2 "$RC" "S4: a seat outside the audience cannot ack"
  PANE=%4 bc ack ackme --seat app:ui
  assert_eq 2 "$RC" "S4: no acking for another seat"
  PANE=%4 bc ack ../outside/victim
  assert_eq 2 "$RC" "S4: a path id is refused"
  PANE=%99 SELF=app:ui bc ack ackme
  assert_eq 2 "$RC" "M3: a cache-only identity cannot ack"
  PANE=%4 bc ack nosuch
  assert_eq 2 "$RC" "ack: unknown id exits 2"
}

test_ack_exact_seat_match() {
  echo "domain:stat %12 manager:app" >> "$FIX/live.txt"
  bc --children --from manager:domain --id exact1
  PANE=%12 bc ack exact1
  assert_eq 2 "$RC" "X5: a seat whose name is a prefix of an audience seat cannot ack"
}

test_ack_after_retract() {
  bc --subtree manager:app --from manager:director --id rt1 --sticky
  bc retract rt1
  cp "$FIX/live.txt" "$FIX/later.txt"; echo "app:new %11 manager:app" >> "$FIX/later.txt"
  TREE="$FIX/later.txt" PANE=%11 bc ack rt1
  assert_eq 2 "$RC" "X6: a later joiner cannot ack a retracted broadcast"
}

test_status_not_attempted() {
  bc --children --from manager:app --id cut1
  # A fan-out killed after the record landed: drop the delivery lines and the done marker.
  sed -i '' '/^delivered /d; /^done: /d' "$FIX/bc/cut1.md"
  bc status cut1
  assert_has $'app:ask\tnot-attempted' "$OUT" "S5: a seat never attempted says so"
  assert_has "complete: no" "$OUT" "S5: an unfinished fan-out says so"
}

test_resend() {
  echo app:ui > "$FIX/failseats"
  bc --children --from manager:app --id re1
  : > "$FIX/failseats"; : > "$FIX/sent.log"
  PANE=%3 bc resend re1 --undelivered
  assert_eq 0 "$RC" "S5: resend exits 0"
  assert_eq 1 "$(sent_count)" "S5: --undelivered resends only the undelivered seat"
  assert_has "app:ui|" "$(cat "$FIX/sent.log")" "S5: it went to app:ui"
  assert_has "app:ui|2005|record-present|Use /ask, not AskUserQuestion.~ack (from manager:domain): engine broadcast ack re1" "$(cat "$FIX/sent.log")" "F5: a resend carries the record's text"
  PANE=none bc resend re1
  assert_eq 2 "$RC" "F2: resend outside tmux is refused"
  bc status re1
  assert_has $'app:ui\tdelivered' "$OUT" "S5: status reads the latest delivery line"
}

test_pending_sticky() {
  PANE=%4 bc --subtree manager:app --from manager:app --id stick1 --sticky
  bc --subtree manager:app --from manager:director --id plain1
  # A seat that started after the broadcast, under manager:app.
  cp "$FIX/live.txt" "$FIX/later.txt"; echo "app:new %11 manager:app" >> "$FIX/later.txt"
  TREE="$FIX/later.txt" bc pending --for app:new
  assert_eq 0 "$RC" "pending: exits 0"
  assert_has "stick1" "$OUT" "pending: a later seat in scope sees the sticky broadcast"
  assert_hasnt "plain1" "$OUT" "pending: a non-sticky broadcast is not preloaded"
  TREE="$FIX/later.txt" bc pending --for app:ask
  assert_hasnt "stick1" "$OUT" "pending: the sender does not get its own broadcast back"
  TREE="$FIX/later.txt" bc pending --for domain:stats
  assert_hasnt "stick1" "$OUT" "pending: a seat outside the scope does not see it"
  TREE="$FIX/later.txt" PANE=%11 bc ack stick1
  assert_eq 0 "$RC" "pending: a later seat in a live sticky scope may ack"
  TREE="$FIX/later.txt" bc pending --for app:new
  assert_hasnt "stick1" "$OUT" "pending: an acked broadcast drops out"
  bc status stick1
  assert_has $'app:new\tjoined-later\tacked' "$OUT" "status: a later joiner's ack is shown"
  TREE="$FIX/later.txt" PANE=%5 bc pending
  assert_eq 0 "$RC" "F3: pending without --for reads the live seat"
  assert_has "stick1" "$OUT" "F3: and lists that seat's broadcasts"
  TREE="$FIX/later.txt" PANE=%99 SELF=app:ui bc pending
  assert_eq 2 "$RC" "F3: pending refuses a cache-only identity"
  assert_hasnt "stick1" "$OUT" "F3: and lists nothing for the cached seat"
  PANE=none bc pending
  assert_eq 2 "$RC" "F3: pending with no identity is refused"
}

test_retract_expires_limit() {
  bc --subtree manager:app --from manager:director --id st1 --sticky
  PANE=%4 bc retract st1
  assert_eq 2 "$RC" "S6: only the sender may retract"
  PANE=none bc retract st1
  assert_eq 2 "$RC" "F6: retract needs a real seat"
  bc retract st1
  assert_eq 0 "$RC" "S6: the sender retracts"
  bc pending --for app:ui
  assert_hasnt "st1" "$OUT" "S6: a retracted broadcast is not pending"
  bc --subtree manager:app --from manager:director --id old1 --sticky --expires 2000-01-01
  bc pending --for app:ui
  assert_hasnt "old1" "$OUT" "S6: an expired broadcast is not pending"
  assert_file_not_exists "$FIX/bc/sticky/old1" "S6: and is pruned from the sticky index"
  assert_file_exists "$FIX/bc/old1.md" "S6: the record itself stays"
  local i; for i in 1 2 3 4 5 6 7; do bc --subtree manager:app --from manager:director --id many$i --sticky; done
  bc pending --for app:ui
  assert_eq 5 "$(grep -c '^many' <<<"$OUT")" "S6: pending is bounded to 5 by default"
  assert_has "+2 more" "$OUT" "S6: and says how many more"
  bc pending --for app:ui --limit 0
  assert_eq 7 "$(grep -c '^many' <<<"$OUT")" "S6: --limit 0 lists all"
}

# ---------------------------------------------------------------- parity (S7)
# ---------------------------------------------------------------- the inline text: cap and resend
xs() { printf 'x%.0s' $(seq "$1"); }

test_cut_is_exact() {
  MSG="$(xs 1600)" PANE=%2 bc --children --id cut1
  assert_eq "$(xs 1500)…"$'\n'"full text: $FIX/bc/cut1.md"$'\n'"ack (from manager:app): engine broadcast ack cut1" \
    "$(cat "$FIX/msg.app:ask")" "S1: past the cap the message is exactly 1500 characters, …, the record path, the ack line"
}

test_text_at_the_cap_is_not_cut() {
  MSG="$(xs 1500)" PANE=%2 bc --children --id cap1
  assert_eq "$(xs 1500)"$'\n'"ack (from manager:app): engine broadcast ack cap1" \
    "$(cat "$FIX/msg.app:ask")" "S1: a text of exactly the cap arrives whole, with no record path"
}

test_inline_max_is_validated() {
  local v
  for v in abc 0 -3 1e3; do
    : > "$FIX/sent.log"; rm -f "$FIX/msg.app:ask"
    BROADCAST_INLINE_MAX="$v" MSG="$(xs 1600)" PANE=%2 bc --children --id "max$(printf %s "$v" | tr -c 'a-z0-9' n)"
    assert_eq 0 "$RC" "S3: BROADCAST_INLINE_MAX='$v' still sends"
    assert_has "BROADCAST_INLINE_MAX '$v' is not a positive integer; using 1500" "$OUT" "S3: BROADCAST_INLINE_MAX='$v' warns"
    assert_eq "$(xs 1500)…" "$(sed -n 1p "$FIX/msg.app:ask")" "S3: BROADCAST_INLINE_MAX='$v' falls back to a 1500 cut"
  done
  BROADCAST_INLINE_MAX=3 MSG="abcdef" PANE=%2 bc --children --id max3
  assert_hasnt "not a positive integer" "$OUT" "S3: a valid cap does not warn"
  assert_eq "abc…" "$(sed -n 1p "$FIX/msg.app:ask")" "S3: a valid cap is used"
}

# M2: the cut counts characters even when the caller's locale counts bytes.
test_multibyte_cut_outside_utf8() {
  local want="ééééé…"$'\n'"full text: $FIX/bc/mb1.md"$'\n'"ack (from manager:app): engine broadcast ack mb1"
  LC_ALL=C BROADCAST_INLINE_MAX=5 MSG="ééééééé" PANE=%2 bc --children --id mb1
  assert_eq "$want" "$(cat "$FIX/msg.app:ask")" "M2: under LC_ALL=C the cut is 5 characters, not 5 bytes"
  if iconv -f UTF-8 -t UTF-8 "$FIX/msg.app:ask" >/dev/null 2>&1; then pass "M2: under LC_ALL=C the message is valid UTF-8"
  else fail "M2: under LC_ALL=C the message is valid UTF-8" "iconv accepts it" "$(od -c "$FIX/msg.app:ask" | head -3)"; fi
  rm -f "$FIX/msg.app:ask"
  CLEAN=1 BROADCAST_INLINE_MAX=5 MSG="ééééééé" PANE=%2 bc --children --id mb2
  assert_eq 0 "$RC" "M2: under env -i the send exits 0"
  assert_eq "${want//mb1/mb2}" "$(cat "$FIX/msg.app:ask" 2>/dev/null)" "M2: under env -i the cut is 5 characters, not 5 bytes"
}

# M1: a resend reads the text back exactly, whatever "## " lines it holds.
test_resend_is_byte_exact() {
  local text=$'\nDo this:\n\n## Step 1\nrun foo\n## Textbook\n## Text\n  a "quoted" \\ $line\t with a tab\n## Delivery\n\n## Step 2\nrun bar'
  echo app:ui > "$FIX/failseats"
  MSG="$text" PANE=%2 bc --children --id rb1
  : > "$FIX/failseats"
  assert_eq "$text"$'\n'"ack (from manager:app): engine broadcast ack rb1" "$(cat "$FIX/msg.app:ask")" "M1: the first send carries the text as given"
  PANE=%3 bc resend rb1 --undelivered
  assert_eq 0 "$RC" "M1: resend exits 0"
  assert_eq "$text"$'\n'"ack (from manager:domain): engine broadcast ack rb1" "$(cat "$FIX/msg.app:ui")" \
    "M1: a resend carries the same text byte for byte, headings and all"
}

test_resend_over_the_cap() {
  echo app:ui > "$FIX/failseats"
  MSG="$(xs 1600)" PANE=%2 bc --children --id rcap1
  : > "$FIX/failseats"
  PANE=%3 bc resend rcap1 --undelivered
  assert_eq "$(xs 1500)…"$'\n'"full text: $FIX/bc/rcap1.md"$'\n'"ack (from manager:domain): engine broadcast ack rcap1" \
    "$(cat "$FIX/msg.app:ui")" "S1: a resend past the cap is cut the same way"
}

# Operator ruling on S2: the sender is named on the ack line — the sent-by seat, not --from; on a
# resend, the resender's seat. The text above it is untouched.
test_sender_on_the_ack_line() {
  MSG="hello" PANE=%2 bc --subtree app:ask --from manager:director --id who1
  assert_eq "hello"$'\n'"ack (from manager:app): engine broadcast ack who1" "$(cat "$FIX/msg.ask:helper")" \
    "S2: the ack line names the sent-by seat, not --from"
  PANE=%4 bc resend who1
  assert_eq "hello"$'\n'"ack (from app:ask): engine broadcast ack who1" "$(cat "$FIX/msg.ask:helper")" \
    "S2: a resend's ack line names the resender"
}

# ---------------------------------------------------------------- go requests (IDE-350)
# A temp git repo with a fake CONTRACTS.md and an owners map. kern/ is app:ask's, stats/ is
# domain:stats's, ui/ is app:ui's, ghost/ belongs to a seat that is not in the live tree, orphan/
# has no owner. c1 touches kern/ and stats/; c2 touches ui/ and kern/.
G() { git -C "$FIX/repo" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"; }
go_repo() {
  mkdir -p "$FIX/repo"; git init -q -b main "$FIX/repo"
  mkdir -p "$FIX/repo/kern" "$FIX/repo/stats" "$FIX/repo/ui" "$FIX/repo/orphan" "$FIX/repo/ghost"
  cat > "$FIX/repo/CONTRACTS.md" <<'EOF'
# Contracts

| Contract | Status | Owner | Import | Doc |
|---|---|---|---|---|
| [Alpha shape](#alpha) | settled | `kern/a.ts` | `import { A } from 'kern'` | `kern/a.ts` |
| [Beta shape](#beta) | settled for stats | `stats/b.ts`, `ui/c.ts` | `import { B } from 'stats'` | `stats/b.ts` |
| [Gamma](#gamma) | pending a ruling | none | none yet | none |
| [Delta](#delta) | settled | `orphan/d.ts` | none | `orphan/d.ts` |
| [Epsilon](#eps) | settled | `kern/untouched.ts` | none | `kern/untouched.ts` |
| [Zeta](#zeta) | settled | `ghost/z.ts` | none | `ghost/z.ts` |
EOF
  printf 'a0\n' > "$FIX/repo/kern/a.ts"; printf 'b0\n' > "$FIX/repo/stats/b.ts"; printf 'c0\n' > "$FIX/repo/ui/c.ts"
  printf 'd0\n' > "$FIX/repo/orphan/d.ts"; printf 'z0\n' > "$FIX/repo/ghost/z.ts"; printf 'u0\n' > "$FIX/repo/kern/untouched.ts"
  G add -A; G commit -qm base; G tag base
  printf 'a1\n' > "$FIX/repo/kern/a.ts"; printf 'b1\n' > "$FIX/repo/stats/b.ts"; G commit -qam c1
  printf 'c2\n' > "$FIX/repo/ui/c.ts"; printf 'a1\na2\n' > "$FIX/repo/kern/a.ts"; G commit -qam c2
  cat > "$FIX/owners" <<'EOF'
# path-glob seat
kern/   app:ask
stats/  domain:stats
ui/     app:ui
ghost/  app:ghost
EOF
}
rid() { git -C "$FIX/repo" show --text "$1" -- "${@:2}" | git patch-id --stable | cut -d' ' -f1; }
goreq() { bc go-request --repo "$FIX/repo" --owners "$FIX/owners" "$@"; }

test_go_request_reaches_exactly_the_owners() {
  go_repo
  local c1 c2; c1=$(G rev-parse HEAD~1); c2=$(G rev-parse HEAD)
  PANE=%2 goreq --pr 28 --rows alpha,beta --commits base..HEAD --id go1
  assert_eq 0 "$RC" "goreq: a go request exits 0"
  assert_eq "app:ask domain:stats app:ui" "$(audience)" "goreq: the audience is exactly the rows' owner seats"
  assert_eq 3 "$(sent_count)" "goreq: one message per owner seat, one broadcast"
  assert_eq 1 "$(nrec)" "goreq: one record"
  assert_eq "app:ask app:ui domain:stats" "$(cut -d'|' -f1 "$FIX/sent.log" | sort | tr '\n' ' ' | sed 's/ $//')" "goreq: the messages went to those seats and nobody else"
  local body; body=$(cat "$FIX/bc/go1.md")
  assert_has "kind: go-request" "$body" "goreq: the record says it is a go request"
  assert_has "pr: 28" "$body" "goreq: the record names the PR"
  assert_has "rows: alpha beta" "$body" "goreq: the record names the rows"
  local m; m=$(cat "$FIX/msg.app:ask")
  assert_has "PR 28" "$m" "goreq: the message carries the PR"
  assert_has "alpha" "$m" "goreq: the message carries the rows"
  assert_has "receipt path app:ask $c1 $(rid "$c1" kern/a.ts) -- kern/a.ts" "$m" "goreq: app:ask's receipt for c1 inline"
  assert_has "receipt path app:ask $c2 $(rid "$c2" kern/a.ts) -- kern/a.ts" "$m" "goreq: app:ask's receipt for c2 inline"
  assert_has "receipt path domain:stats $c1 $(rid "$c1" stats/b.ts) -- stats/b.ts" "$(cat "$FIX/msg.domain:stats")" "goreq: domain:stats gets its own receipt"
  assert_has "untouched path domain:stats $c2 -- stats/b.ts" "$(cat "$FIX/msg.domain:stats")" "goreq: a commit that misses an owner's paths is listed untouched, not a receipt"
  assert_hasnt "domain:stats" "$m" "goreq: each owner's message carries only its own receipt lines"
  assert_has "receipt path app:ui $c2" "$body" "goreq: the record keeps every owner's receipts"
  assert_has "receipt path app:ui $c2 $(rid "$c2" ui/c.ts) -- ui/c.ts" "$(cat "$FIX/msg.app:ui")" "goreq: app:ui gets its own receipt"
  assert_has "engine broadcast decline go1 --reason" "$m" "goreq: the message says how to decline"
  assert_has "ack (from manager:app): engine broadcast ack go1" "$m" "goreq: and how to give the go"
}

test_go_request_refuses_an_unowned_row() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha,gamma --commits base..HEAD
  assert_eq 2 "$RC" "goreq: a row whose owner is none refuses"
  assert_has "gamma" "$OUT" "goreq: and names the row"
  PANE=%2 goreq --pr 28 --rows delta --commits base..HEAD
  assert_eq 2 "$RC" "goreq: an owner path no seat maps refuses"
  assert_has "delta" "$OUT" "goreq: and names that row"
  PANE=%2 goreq --pr 28 --rows nosuch --commits base..HEAD
  assert_eq 2 "$RC" "goreq: a row not in CONTRACTS.md refuses"
  assert_has "nosuch" "$OUT" "goreq: and names it"
  PANE=%2 goreq --pr 28 --rows zeta --commits base..HEAD
  assert_eq 3 "$RC" "goreq: an owner seat not in the live tree refuses with 3"
  assert_has "zeta" "$OUT" "goreq: and names the row"
  printf 'kern/a.ts app:ui\nkern/a.ts domain:stats\n' >> "$FIX/owners"
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD
  assert_eq 2 "$RC" "goreq: two seats equally specific for one path refuse, never a guess"
  assert_eq 0 "$(sent_count)" "goreq: nothing sent on any refusal"
  assert_eq 0 "$(nrec)" "goreq: no record on any refusal"
}

test_go_request_refuses_an_empty_receipt() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha,eps --commits base..HEAD
  assert_eq 2 "$RC" "goreq: an owner whose paths give an empty id refuses"
  assert_has "empty" "$OUT" "goreq: says the receipt is empty"
  assert_has "kern/untouched.ts" "$OUT" "goreq: names the paths"
  assert_eq 0 "$(sent_count)" "goreq: nothing sent"
  assert_eq 0 "$(nrec)" "goreq: no record"
  PANE=%2 goreq --pr 28 --rows alpha --commits base..base
  assert_eq 2 "$RC" "goreq: an empty commit range refuses"
  PANE=%2 goreq --pr x --rows alpha --commits base..HEAD
  assert_eq 2 "$RC" "goreq: --pr takes a number"
  PANE=%2 goreq --pr 28 --commits base..HEAD
  assert_eq 2 "$RC" "goreq: --rows is required"
}

test_go_ack_and_decline_are_recorded() {
  go_repo
  local c1 c2; c1=$(G rev-parse HEAD~1); c2=$(G rev-parse HEAD)
  PANE=%2 goreq --pr 28 --rows alpha,beta --commits base..HEAD --id go2
  : > "$FIX/sent.log"
  PANE=%4 bc ack go2
  assert_eq 0 "$RC" "go ack: exits 0"
  assert_has "GO: app:ask" "$OUT" "go ack: records a GO for the caller's seat"
  assert_has "$(rid "$c1" kern/a.ts)" "$(cat "$FIX/bc/go2.acks.d/app:ask")" "go ack: the GO is bound to the receipts it was sent"
  PANE=%7 bc decline go2 --reason "breaks the stats export"
  assert_eq 0 "$RC" "go decline: exits 0"
  assert_has "DECLINED: domain:stats" "$OUT" "go decline: recorded for the caller's seat"
  assert_eq 0 "$(sent_count)" "go ack/decline: no message is sent"
  bc status go2
  assert_eq 0 "$RC" "go status: exits 0"
  assert_has $'app:ask\tdelivered\tGO\t' "$OUT" "go status: GO"
  assert_has "$(rid "$c2" kern/a.ts)" "$(grep '^app:ask' <<<"$OUT")" "go status: a GO shows its receipts"
  assert_has $'domain:stats\tdelivered\tDECLINED\tbreaks the stats export' "$OUT" "go status: DECLINED with the reason"
  assert_has $'app:ui\tdelivered\tPENDING' "$OUT" "go status: PENDING"
  PANE=%7 bc ack go2
  assert_eq 2 "$RC" "go: a seat that declined cannot turn it into a GO; a new request is needed"
  PANE=%4 bc decline go2 --reason "changed my mind"
  assert_eq 2 "$RC" "go: a seat that gave its GO cannot decline the same request"
  PANE=%4 bc ack go2
  assert_eq 0 "$RC" "go: a repeated GO is a no-op"
  bc --children --from manager:app --id plain9
  PANE=%4 bc decline plain9 --reason "no"
  assert_eq 2 "$RC" "decline: an ordinary broadcast has no decline"
}

test_go_decline_needs_a_reason() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha,beta --commits base..HEAD --id go3
  PANE=%7 bc decline go3
  assert_eq 2 "$RC" "decline: no --reason refuses"
  PANE=%7 bc decline go3 --reason "   "
  assert_eq 2 "$RC" "decline: a blank reason refuses"
  PANE=%7 bc decline go3 --reason $'one\ntwo'
  assert_eq 2 "$RC" "decline: a reason of more than one line refuses"
  assert_file_not_exists "$FIX/bc/go3.declines.d/domain:stats" "decline: nothing recorded"
  bc status go3
  assert_has $'domain:stats\tdelivered\tPENDING' "$OUT" "decline: the seat is still pending"
}

test_go_non_audience_is_refused() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --id go4
  assert_eq 0 "$RC" "go: fixture: the request was sent"
  PANE=%7 bc ack go4
  assert_eq 2 "$RC" "go: a seat outside the owners cannot give a GO"
  assert_has "'domain:stats' is not in the audience of 'go4'" "$OUT" "go: the GO refusal names the seat and the request"
  PANE=%7 bc decline go4 --reason "not mine"
  assert_eq 2 "$RC" "go: a seat outside the owners cannot decline"
  assert_has "'domain:stats' is not an owner in the audience of 'go4'" "$OUT" "go: the decline refusal names the seat and the request"
  PANE=%99 SELF=app:ask bc ack go4
  assert_eq 2 "$RC" "go: a cache-only identity cannot give a GO"
  assert_file_not_exists "$FIX/bc/go4.acks.d/domain:stats" "go: nothing recorded for the outsider"
}

test_go_check() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha,beta --commits base..HEAD --id go5
  PANE=%4 bc ack go5; PANE=%7 bc ack go5
  bc go-check go5 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 1 "$RC" "go-check: a pending owner fails"
  assert_has "PENDING app:ui" "$OUT" "go-check: and names who is missing"
  PANE=%5 bc ack go5
  bc go-check go5 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 0 "$RC" "go-check: every owner GO and every receipt matching passes"
  assert_has "go-check: PASS in " "$OUT" "go-check S4: the PASS line names the repo it checked"
  assert_has "rows alpha beta" "$OUT" "go-check S4: the PASS line names the rows it covers"
  assert_has "nothing outside those paths was checked" "$OUT" "go-check S4: the PASS line says what it does not cover"
  assert_hasnt "every owner's GO covers these commits" "$OUT" "go-check S4: the round-1 overclaim is gone"
  # Re-picked onto a moved tip: an unrelated commit lands first; the ids do not move.
  G checkout -q -b repick base; printf 'x\n' > "$FIX/repo/other.txt"; G add other.txt; G commit -qm other
  G cherry-pick main~1 main >/dev/null
  assert_eq 3 "$(G rev-list --count base..repick)" "go-check: fixture: the stack was re-picked onto a moved base"
  bc go-check go5 --repo "$FIX/repo" --commits base..repick
  assert_eq 0 "$RC" "go-check: a re-picked commit whose receipt still matches keeps its go"
  # Amend c2's ui change: app:ui's receipt moves; app:ask's does not.
  printf 'c2-amended\n' > "$FIX/repo/ui/c.ts"; G commit -q -a --amend -m c2
  bc go-check go5 --repo "$FIX/repo" --commits base..repick
  assert_eq 1 "$RC" "go-check: a changed receipt fails"
  assert_has "MOVED app:ui" "$OUT" "go-check: names the owner whose receipt moved"
  assert_hasnt "MOVED app:ask" "$OUT" "go-check: an owner whose receipts still match is not named"
  assert_has "strict" "$OUT" "go-check S4: the FAIL text says the check is strict"
  assert_has "context-only move" "$OUT" "go-check S4: and that a context-only move fails too"
  assert_has "LANDING.md step 4" "$OUT" "go-check S4: and points at the lander's judgement in LANDING step 4"
  assert_has "fresh go" "$OUT" "go-check S4: or the owner's fresh go"
  bc go-check go5 --repo "$FIX/repo"
  assert_eq 2 "$RC" "go-check: --commits is required"
}

test_go_check_declined() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --id go6
  PANE=%4 bc decline go6 --reason "not yet"
  bc go-check go6 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 1 "$RC" "go-check: a declined owner fails"
  assert_has "DECLINED app:ask: not yet" "$OUT" "go-check: names the decline and its reason"
  bc --children --from manager:app --id plain8
  bc go-check plain8 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 2 "$RC" "go-check: an ordinary broadcast is not a go request"
}

# ---------------------------------------------------------------- go, round 2 (critique M1-N5)
GOH=(-c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null -c commit.gpgsign=false)
rec_of() { cat "$FIX/bc/$1.md"; }

# M1: go-check without --repo checks the worktree it runs in, never the request's recorded repo.
test_go_check_uses_the_cwd_repo() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --id gw
  PANE=%4 bc ack gw
  G worktree add -q -b land "$FIX/wt2" HEAD
  local wt; wt=$(cd "$FIX/wt2" && pwd -P)
  pushd "$FIX/wt2" >/dev/null; bc go-check gw --commits base..HEAD; popd >/dev/null
  assert_eq 0 "$RC" "go-check M1: from an unchanged landing worktree it passes"
  assert_has "$wt" "$OUT" "go-check M1: it names the repo it checked, the cwd's"
  printf 'EVIL\n' > "$FIX/wt2/kern/a.ts"
  git -C "$FIX/wt2" "${GOH[@]}" commit -q -a --amend -m c2
  pushd "$FIX/wt2" >/dev/null; bc go-check gw --commits base..HEAD; popd >/dev/null
  assert_eq 1 "$RC" "go-check M1: an amend in the landing worktree fails when run from it without --repo"
  assert_has "MOVED app:ask" "$OUT" "go-check M1: and names the owner whose receipt moved"
  bc go-check gw --repo "$FIX/repo" --commits base..HEAD
  assert_eq 0 "$RC" "go-check M1: --repo still names a repo explicitly (the request's, unchanged)"
  pushd / >/dev/null; bc go-check gw --commits base..HEAD; popd >/dev/null
  assert_eq 2 "$RC" "go-check M1: outside a git repo with no --repo it refuses, never falls back to the record's"
}

# M2: a resend of a go request gives each seat only its own receipt lines.
test_go_resend_gives_each_seat_its_own_lines() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha,beta --commits base..HEAD --id gs
  rm -f "$FIX"/msg.*; : > "$FIX/sent.log"
  PANE=%2 bc resend gs
  assert_eq 0 "$RC" "go resend: exits 0"
  assert_eq 3 "$(sent_count)" "go resend: reaches the three owners"
  local a s u
  a=$(cat "$FIX/msg.app:ask"); s=$(cat "$FIX/msg.domain:stats"); u=$(cat "$FIX/msg.app:ui")
  assert_has "receipt path app:ask " "$a" "go resend: app:ask gets its own receipts"
  assert_hasnt "domain:stats" "$a" "go resend: app:ask gets no domain:stats line"
  assert_hasnt "app:ui" "$a" "go resend: app:ask gets no app:ui line"
  assert_has "receipt path domain:stats " "$s" "go resend: domain:stats gets its own receipts"
  assert_hasnt "app:ask" "$s" "go resend: domain:stats gets no app:ask line"
  assert_has "receipt path app:ui " "$u" "go resend: app:ui gets its own receipts"
  assert_hasnt "app:ask" "$u" "go resend: app:ui gets no app:ask line"
}

# M2: --text (a binary file) and one owner with several paths in one commit, each equal to the
# LANDING.md step 2 hand command.
test_go_receipts_equal_the_landing_hand_command() {
  go_repo
  printf 'kern/ app:ask\nstats/ app:ui\nui/ app:ui\n' > "$FIX/owners"
  printf '\000\001bin\000\n' > "$FIX/repo/kern/a.ts"; printf 'b9\n' > "$FIX/repo/stats/b.ts"; printf 'c9\n' > "$FIX/repo/ui/c.ts"
  G commit -qam bin
  local c body hand hand2; c=$(G rev-parse HEAD)
  PANE=%2 goreq --pr 1 --rows alpha,beta --commits HEAD~1..HEAD --id gb
  assert_eq 0 "$RC" "receipts: the request is sent"
  body=$(rec_of gb)
  hand=$(rid "$c" kern/a.ts)
  assert_not_empty "$hand" "receipts: fixture: the hand --text id of a binary change is not empty"
  assert_has "receipt path app:ask $c $hand -- kern/a.ts" "$body" "receipts: a binary file's receipt is the --text id"
  hand2=$(rid "$c" stats/b.ts ui/c.ts)
  assert_has "receipt path app:ui $c $hand2 -- stats/b.ts ui/c.ts" "$body" "receipts: one owner, two paths, one commit: one id over both, as the hand command gives"
  assert_eq 1 "$(grep -c "^receipt path app:ui $c " <<<"$body" | tr -d ' ')" "receipts: and only one receipt line for that owner and commit"
}

# M2: the range grows or shrinks between the request and the check.
test_go_check_when_the_range_changes_length() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha,beta --commits base..HEAD --id gl
  PANE=%4 bc ack gl; PANE=%7 bc ack gl; PANE=%5 bc ack gl
  bc go-check gl --repo "$FIX/repo" --commits base..HEAD
  assert_eq 0 "$RC" "range: fixture: every owner's GO passes"
  printf 'x\n' > "$FIX/repo/other.txt"; G add other.txt; G commit -qm unrelated
  bc go-check gl --repo "$FIX/repo" --commits base..HEAD
  assert_eq 0 "$RC" "range: an added commit that touches no owner path passes"
  printf 'a3\n' >> "$FIX/repo/kern/a.ts"; G commit -qam sneaky
  bc go-check gl --repo "$FIX/repo" --commits base..HEAD
  assert_eq 1 "$RC" "range: an added commit that touches an owner path fails"
  assert_has "MOVED app:ask" "$OUT" "range: and names that owner"
  assert_hasnt "MOVED app:ui" "$OUT" "range: an owner it does not touch is not named"
  bc go-check gl --repo "$FIX/repo" --commits HEAD~3..HEAD~2
  assert_eq 1 "$RC" "range: a dropped commit fails"
  assert_has "MOVED domain:stats" "$OUT" "range: the owner whose only receipt was dropped is named"
}

# M2: CONTRACTS.md is read at the range's tip, so a row only the PR adds is found.
test_go_request_reads_contracts_at_the_tip() {
  go_repo
  printf '| [New](#newrow) | settled | `kern/a.ts` | none | `kern/a.ts` |\n' >> "$FIX/repo/CONTRACTS.md"
  printf 'a4\n' >> "$FIX/repo/kern/a.ts"; G commit -qam addrow
  G show HEAD~1:CONTRACTS.md > "$FIX/repo/CONTRACTS.md"   # the working tree lacks the row
  PANE=%2 goreq --pr 28 --rows newrow --commits base..HEAD --id gt
  assert_eq 0 "$RC" "tip: a row only the PR's tip adds is found"
  assert_eq "app:ask" "$(audience)" "tip: and its owner is asked"
}

# N1 + N5: the tip is the range's end (here a merge whose side added the row, with skewed dates so
# rev-list order puts another commit last), and a merge commit gets no receipt line.
test_go_request_tip_is_the_range_end_and_merges_are_skipped() {
  go_repo
  G checkout -q -b side base
  printf '| [Side](#siderow) | settled | `kern/s.ts` | none | `kern/s.ts` |\n' >> "$FIX/repo/CONTRACTS.md"
  printf 's1\n' > "$FIX/repo/kern/s.ts"; G add -A
  GIT_COMMITTER_DATE='2001-01-01T00:00:00Z' GIT_AUTHOR_DATE='2001-01-01T00:00:00Z' G commit -qm side
  G checkout -q main
  printf 'b5\n' > "$FIX/repo/stats/b.ts"
  GIT_COMMITTER_DATE='2030-01-01T00:00:00Z' GIT_AUTHOR_DATE='2030-01-01T00:00:00Z' G commit -qam late
  G merge -q --no-edit side >/dev/null
  local m; m=$(G rev-parse HEAD)
  assert_eq 2 "$(G rev-list --parents -1 HEAD | wc -w | tr -d ' ' | awk '{ print $1 - 1 }')" "tip: fixture: HEAD is a merge"
  PANE=%2 goreq --pr 28 --rows siderow --commits base..HEAD --id gm
  assert_eq 0 "$RC" "tip N1: the row is read at the range's end, the merge, not at the last commit rev-list prints"
  assert_eq 0 "$(grep -cE "^(receipt|untouched) .*$m" "$FIX/bc/gm.md" | tr -d ' ')" "tip N5: the merge commit gets no receipt or untouched line"
  assert_has "receipt path app:ask $(G rev-parse side) " "$(rec_of gm)" "tip N5: the side's lane commit is a receipt"
}

# S1: the audience is each row's owners at the base AND at the tip: a PR that repoints a row's
# Owner cell still asks the owner it repoints away from.
test_go_request_asks_the_owner_at_the_base_too() {
  go_repo
  perl -pi -e 's#`kern/a.ts` \| `import#`stats/b.ts` | `import#' "$FIX/repo/CONTRACTS.md"
  printf 'evil\n' > "$FIX/repo/kern/a.ts"; printf 'b-touch\n' > "$FIX/repo/stats/b.ts"
  G commit -qam repoint
  PANE=%2 goreq --pr 28 --rows alpha --commits HEAD~1..HEAD --id gp
  assert_eq 0 "$RC" "S1: the request is sent"
  assert_has "app:ask" "$(audience)" "S1: the owner at the base (app:ask) is still asked"
  assert_has "domain:stats" "$(audience)" "S1: and the owner at the tip (domain:stats)"
  assert_has "receipt path app:ask " "$(rec_of gp)" "S1: the base owner gets a receipt for its path"
}

# S3: no glob expansion of owner paths or row ids, whatever the cwd.
test_go_request_does_not_glob() {
  go_repo
  # The glob cell is in place at the range's base and its tip; the range then touches kern/a.ts.
  perl -pi -e 's#`kern/a.ts` \| `import#`kern/*.ts` | `import#' "$FIX/repo/CONTRACTS.md"
  G commit -qam globrow; G tag globbase
  printf 'a5\n' >> "$FIX/repo/kern/a.ts"; G commit -qam touch
  local in_rc in_out
  pushd "$FIX/repo" >/dev/null; PANE=%2 goreq --pr 28 --rows alpha --commits globbase..HEAD --dry-run; popd >/dev/null
  in_rc=$RC in_out=$OUT
  pushd / >/dev/null; PANE=%2 goreq --pr 28 --rows alpha --commits globbase..HEAD --dry-run; popd >/dev/null
  assert_eq 2 "$in_rc" "S3: an Owner cell 'kern/*.ts' is one literal path, so from the repo root its receipt is empty and it refuses"
  assert_has "paths: kern/*.ts" "$in_out" "S3: and names the literal path"
  assert_eq "$in_rc" "$RC" "S3: the same from / (no dependence on the cwd)"
  : > "$FIX/alpha"
  pushd "$FIX" >/dev/null; PANE=%2 goreq --pr 28 --rows '*' --commits base..HEAD --dry-run; popd >/dev/null
  assert_eq 2 "$RC" "S3: --rows '*' refuses"
  assert_has "row '*' is not in" "$OUT" "S3: as the literal row '*'"
  assert_hasnt "row 'alpha'" "$OUT" "S3: never expanded to file names in the cwd"
}

# S2: the usage says a GO is attribution, not authentication.
test_go_usage_says_attribution_not_authentication() {
  bc --help
  assert_has "attribution, not authentication" "$OUT" "S2: the usage says a GO records attribution, not authentication"
  assert_has "TMUX_PANE" "$OUT" "S2: and names where the seat comes from"
}

# N2: a GO and a decline for one seat exclude each other at the write, not only at the pre-check.
test_go_answer_is_one_per_seat() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha,beta --commits base..HEAD --id gx
  mkdir -p "$FIX/bc/gx.answers.d"
  printf 'DECLINED\n' > "$FIX/bc/gx.answers.d/app:ask"     # a decline won the race
  PANE=%4 bc ack gx
  assert_eq 2 "$RC" "N2: a GO loses to a decline that claimed the seat first"
  assert_file_not_exists "$FIX/bc/gx.acks.d/app:ask" "N2: no GO is written"
  printf 'GO\n' > "$FIX/bc/gx.answers.d/domain:stats"      # a GO won the race
  PANE=%7 bc decline gx --reason "late"
  assert_eq 2 "$RC" "N2: a decline loses to a GO that claimed the seat first"
  assert_file_not_exists "$FIX/bc/gx.declines.d/domain:stats" "N2: no decline is written"
  PANE=%5 bc ack gx
  assert_eq 0 "$RC" "N2: an unclaimed seat's GO goes through"
  PANE=%5 bc decline gx --reason "x"
  assert_eq 2 "$RC" "N2: and then that seat cannot decline"
}

# N3: an ack file with two fields (a pre-go ack) reads as a GO with no receipts, and fails go-check.
test_go_status_shows_an_ack_without_receipts() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --id gn
  mkdir -p "$FIX/bc/gn.acks.d"; printf 'app:ask\t2026-01-01T00:00:00Z\n' > "$FIX/bc/gn.acks.d/app:ask"
  bc status gn
  assert_has $'app:ask\tdelivered\tGO (no receipts)' "$OUT" "N3: status shows GO (no receipts)"
  bc go-check gn --repo "$FIX/repo" --commits base..HEAD
  assert_eq 1 "$RC" "N3: go-check fails on a GO with no receipts"
  assert_has "app:ask" "$OUT" "N3: and names the seat"
}

# N4: the most specific owners-map pattern is the one with the most path segments, not the most
# characters. kern*a.ts (1 segment, 9 chars) loses to */a.ts (2 segments, 6 chars).
test_go_owners_map_specificity_is_by_segments() {
  go_repo
  printf 'kern*a.ts domain:stats\n*/a.ts app:ui\n' >> "$FIX/owners"
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --dry-run
  assert_eq 0 "$RC" "N4: the request resolves"
  assert_eq "app:ui" "$(audience)" "N4: the two-segment pattern wins over a longer one-segment pattern"
}

# Receipt kind: lines carry a kind ("path"); a round-1 record (no kind) still reads; a kind this
# script cannot recompute fails go-check rather than passing.
test_go_receipt_kind() {
  go_repo
  local c1; c1=$(G rev-parse HEAD~1)
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --id gk1
  assert_has "receipt path app:ask $c1 $(rid "$c1" kern/a.ts) -- kern/a.ts" "$(rec_of gk1)" "kind: a receipt line carries the kind 'path'"
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --id gk2
  perl -pi -e 's/^(receipt|untouched) path /$1 /' "$FIX/bc/gk2.md"   # round 1's form
  assert_has "receipt app:ask $c1 " "$(rec_of gk2)" "kind: fixture: gk2 is in round 1's form"
  PANE=%4 bc ack gk2
  assert_eq 0 "$RC" "kind: a round-1 record takes a GO"
  assert_has "$(rid "$c1" kern/a.ts)" "$(cat "$FIX/bc/gk2.acks.d/app:ask")" "kind: bound to the round-1 receipts"
  bc go-check gk2 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 0 "$RC" "kind: go-check reads a round-1 record and passes"
  rm -f "$FIX"/msg.*; PANE=%2 bc resend gk2
  assert_has "receipt app:ask $c1 " "$(cat "$FIX/msg.app:ask")" "kind: a round-1 record resends its own lines"
  PANE=%4 bc ack gk1
  perl -pi -e 's/^receipt path app:ask /receipt row app:ask /' "$FIX/bc/gk1.md"
  bc go-check gk1 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 1 "$RC" "kind: a receipt kind go-check cannot recompute fails"
  assert_has "kind 'row'" "$OUT" "kind: and names the kind"
}

test_tree_parity() {
  local a b
  a=$(sed -n '/^live_tree() {/,/^}/p' "$BROADCAST_SH")
  b=$(sed -n '/^live_tree() {/,/^}/p' "$HOP_SH")
  assert_not_empty "$b" "S7: hop.sh still has live_tree()"
  assert_eq "$b" "$a" "S7: broadcast's live_tree() body equals hop.sh's"
}

run_discovered_tests
exit_with_results
