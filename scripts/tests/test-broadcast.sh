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
#   record   — written (noclobber) before delivery; sent-by; fixed pointer message; done marker.
#   receipts — own-seat acks only; status states; resend; sticky pending/retract/expires/limit.
#   parity   — live_tree() body equals hop.sh's.
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
rec=\$(sed -n 's/.* read \(.*\); ack: .*/\1/p' <<<"\$3")
if [ -f "\$rec" ]; then st=record-present; else st=record-absent; fi
printf '%s|%s|%s|%s\n' "\$1" "\$2" "\$st" "\$3" >> "$FIX/sent.log"
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
# stub so the real deliver.ts path runs. LIB → BROADCAST_LIB.
OUT="" RC=0
bc() {
  local tree="${TREE:-$FIX/live.txt}" path="$PATH" pane="${PANE-%1}" stub="$FIX/stub.sh"
  local tmuxenv=""
  # The stub-tmux path: no fixture tree; lib.sh reads tmux only inside a tmux client ($TMUX).
  [ "$tree" = none ] && { tree=""; path="$FIX/bin:$PATH"; tmuxenv="$FIX/fake-tmux-socket,1,0"; }
  [ "$pane" = none ] && pane=""
  [ "${DELIVER:-}" = real ] && stub=""
  OUT=$(env -u FLEET_PARENT -u FLEET_PANE -u TMUX_PANE -u HOP_CHAIN_FILE -u FLEET_LIVE_PANES \
    -u HOP_TMUX_SOCKET -u FLEET_TMUX_SOCKET -u TMUX \
    PATH="$path" HOP_LIVE_PANES="$tree" BROADCAST_DIR="$FIX/bc" BROADCAST_DELIVER="$stub" \
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
  assert_has "app:ask|2004|record-present|[broadcast ask-rules from manager:app] read $rec; ack: engine broadcast ack ask-rules" \
    "$sent" "message: the fixed pointer line, to the pane's pid, with the record already on disk"
  assert_hasnt "AskUserQuestion" "$sent" "message: no user text reaches the socket"
  assert_hasnt "ask:helper" "$sent" "send: grandchild not messaged under --children"
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
# one of them under app:ask's pane. The in-pane socket must get exactly one pointer line.
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
  assert_has '"content":"[broadcast real1 from manager:director] read ' "$(cat "$d/a.out")" "real deliver: it is the pointer line, as a user message"
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
  assert_has "[broadcast re1 resent by manager:domain] read " "$(cat "$FIX/sent.log")" "F5: the pointer names the resender"
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
test_tree_parity() {
  local a b
  a=$(sed -n '/^live_tree() {/,/^}/p' "$BROADCAST_SH")
  b=$(sed -n '/^live_tree() {/,/^}/p' "$HOP_SH")
  assert_not_empty "$b" "S7: hop.sh still has live_tree()"
  assert_eq "$b" "$a" "S7: broadcast's live_tree() body equals hop.sh's"
}

run_discovered_tests
exit_with_results
