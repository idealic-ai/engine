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
# Whether the seat's queue still held this id when it was pushed (IDE-352 NIT-5).
if [ -n "\$id" ] && [ -e "$FIX/bc/queued/\$1/\$id" ]; then echo "\$1 \$id" >> "$FIX/queued-at-push"; fi
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
    -u HOP_TMUX_SOCKET -u FLEET_TMUX_SOCKET -u TMUX -u BROADCAST_OWNERS ${OWNERS_ENV:+BROADCAST_OWNERS="$OWNERS_ENV"} \
    ${keep[@]+"${keep[@]}"} PATH="$path" HOP_LIVE_PANES="$tree" BROADCAST_DIR="$FIX/bc" BROADCAST_DELIVER="$stub" \
    BROADCAST_PANE_PIDS="$FIX/panepids" BROADCAST_PS_FILE="$FIX/ps" ASK_SESSIONS_DIR="$FIX/sess" BROADCAST_PROJECTS_DIR="$FIX/projects" \
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

# ---------------------------------------------------------------- queue for idle seats (IDE-352)
# act <pid> <status> <minutes-ago> — give a registered session the activity reading Claude Code
# writes: status and statusUpdatedAt (epoch ms). A session without one has no reading.
act() {
  local ms=$(( ($(date +%s) - $3 * 60) * 1000 ))
  jq -c --arg st "$2" --argjson t "$ms" '. + {status: $st, statusUpdatedAt: $t}' "$FIX/sess/$1.json" > "$FIX/sess/$1.tmp" \
    && mv "$FIX/sess/$1.tmp" "$FIX/sess/$1.json"
}

test_queue_idle_seat_is_queued_not_pushed() {
  act 2004 idle 120; act 2005 idle 5
  bc --children --from manager:app --id q1
  assert_eq 0 "$RC" "queue: a send with a queued seat exits 0"
  assert_eq "app:ui" "$(cut -d'|' -f1 "$FIX/sent.log" | tr '\n' ' ' | sed 's/ $//')" "queue: only the seat active within the hour is pushed"
  local body; body=$(cat "$FIX/bc/q1.md")
  assert_has "queued app:ask pid=2004 idle=120m" "$body" "queue: the idle seat gets a queued line with its idle time"
  assert_has "delivered app:ui pid=2005" "$body" "queue: the active seat is delivered as before"
  assert_has "done: rc=0 delivered=1 undelivered=0 queued=1 at " "$body" "queue: the done line counts the queued seat"
  assert_file_exists "$FIX/bc/queued/app:ask/q1" "queue: the seat's queue holds the id"
  assert_has "queued app:ask" "$OUT" "queue: the sender is told the seat was queued"
  bc status q1
  assert_has $'app:ask\tqueued\tnot-acked' "$OUT" "queue: status says queued, apart from delivered"
  assert_has $'app:ui\tdelivered\tnot-acked' "$OUT" "queue: status says delivered for the pushed seat"
}

test_queue_busy_and_unread_seats_are_live() {
  act 2004 busy 300
  bc --children --from manager:app --id q2
  assert_eq 2 "$(sent_count)" "queue: a busy seat (mid-turn) and a seat with no reading are both pushed live"
  assert_hasnt "queued" "$(cat "$FIX/bc/q2.md")" "queue: nothing is queued"
  assert_has "done: rc=0 delivered=2 undelivered=0 at " "$(cat "$FIX/bc/q2.md")" "queue: the done line is unchanged when nothing is queued"
}

test_queue_window_is_a_setting() {
  act 2004 idle 120; act 2005 idle 5
  BROADCAST_LIVE_WINDOW=180 bc --children --from manager:app --id w1
  assert_eq 2 "$(sent_count)" "window: 180 minutes pushes a seat idle 120m"
  : > "$FIX/sent.log"
  BROADCAST_LIVE_WINDOW=1 bc --children --from manager:app --id w2
  assert_eq 0 "$(sent_count)" "window: 1 minute queues a seat idle 5m"
  assert_has "queued app:ui pid=2005 idle=5m" "$(cat "$FIX/bc/w2.md")" "window: and records it queued"
  BROADCAST_LIVE_WINDOW=soon bc --children --from manager:app --id w3
  assert_has "BROADCAST_LIVE_WINDOW 'soon' is not" "$OUT" "window: a bad value warns"
  assert_has "queued app:ask" "$(cat "$FIX/bc/w3.md")" "window: and falls back to 60 minutes"
  assert_has "delivered app:ui" "$(cat "$FIX/bc/w3.md")" "window: 60 minutes still pushes a seat idle 5m"
}

test_queue_all_live_pushes_everyone() {
  act 2004 idle 120; act 2005 idle 500
  bc --children --from manager:app --id al1 --all-live
  assert_eq 0 "$RC" "all-live: exits 0"
  assert_eq 2 "$(sent_count)" "all-live: every audience seat is pushed whatever its activity"
  assert_hasnt "queued" "$(cat "$FIX/bc/al1.md")" "all-live: nothing queued"
  : > "$FIX/sent.log"
  bc --all --all-live --from manager:director --id al2
  assert_eq "manager:app manager:domain app:ask app:ui ask:helper domain:stats" "$(audience)" "all-live: --all keeps its audience"
  assert_eq 6 "$(sent_count)" "all-live: and pushes all of it"
  bc --all --from manager:director --id al3 --dry-run
  assert_has "binds app:ask → ok 2004 app:ask (queue: idle=120m via=status)" "$OUT" "dry-run: shows which seats would be queued"
}

test_queue_shown_once_at_wake() {
  act 2004 idle 120
  bc --children --from manager:app --id wk1
  bc pending --for app:ask
  assert_has $'wk1\tmanager:director\tqueued' "$OUT" "wake: pending --for lists a queued broadcast"
  bc status wk1
  assert_has $'app:ask\tqueued' "$OUT" "wake: --for is a read; it does not mark it delivered"
  PANE=%4 bc pending
  assert_eq 0 "$RC" "wake: pending at the seat's wake exits 0"
  assert_has $'wk1\tmanager:director\tqueued\t'"$FIX/bc/wk1.md" "$OUT" "wake: the seat is shown its queued broadcast"
  assert_has "Use /ask, not AskUserQuestion."$'\n'"ack (from manager:director): engine broadcast ack wk1" "$OUT" "wake: with the text and ack line the push would have carried"
  assert_has "delivered app:ask at-wake " "$(cat "$FIX/bc/wk1.md")" "wake: the record marks it delivered at wake"
  assert_file_not_exists "$FIX/bc/queued/app:ask/wk1" "wake: and the queue entry is gone"
  bc status wk1
  assert_has $'app:ask\tdelivered\tnot-acked' "$OUT" "wake: status reads delivered once shown"
  PANE=%4 bc pending
  assert_hasnt "wk1" "$OUT" "wake: it is shown once"
  PANE=%4 bc ack wk1
  assert_eq 0 "$RC" "wake: the woken seat acks it"
}

test_queue_queued_mode_fast_path() {
  PANE=none bc pending --queued
  assert_eq 0 "$RC" "queued mode: no queue anywhere exits 0 before reading an identity"
  assert_eq "" "$OUT" "queued mode: and prints nothing"
  act 2004 idle 120; act 2005 idle 120
  bc --subtree manager:app --from manager:director --id qm1 --sticky
  PANE=%5 bc pending --queued
  assert_has $'qm1\tmanager:director\tqueued' "$OUT" "queued mode: shows the seat's queued broadcast"
  assert_eq 1 "$(grep -c '^qm1' <<<"$OUT")" "queued mode: once, not again as a sticky line"
  PANE=%4 bc pending
  assert_eq 1 "$(grep -c '^qm1' <<<"$OUT")" "full pending: a sticky that was also queued is listed once"
  PANE=%4 bc pending
  assert_has $'qm1\tmanager:director\tsubtree:manager:app' "$OUT" "full pending: once shown, an unacked sticky stands as before"
  PANE=%5 bc pending --queued
  assert_hasnt "qm1" "$OUT" "queued mode: never lists standing sticky broadcasts"
  bc --children --from manager:app --id qm2
  PANE=none bc pending --queued
  assert_eq 2 "$RC" "queued mode: with a queue present, no identity is refused"
  assert_file_exists "$FIX/bc/queued/app:ask/qm2" "queued mode: and the refusal leaves the queue as it was"
}

test_queue_limit() {
  act 2005 idle 120
  local i; for i in 1 2 3 4 5 6 7; do bc --children --from manager:app --id ql$i; done
  PANE=%5 bc pending
  assert_eq 5 "$(grep -c '^ql' <<<"$OUT")" "queue limit: 5 shown"
  assert_has "+2 more queued" "$OUT" "queue limit: and the rest named"
  assert_eq 2 "$(ls "$FIX/bc/queued/app:ui" | grep -c .)" "queue limit: the rest stay queued for the next wake"
  PANE=%5 bc pending
  assert_eq 2 "$(grep -c '^ql' <<<"$OUT")" "queue limit: the next wake shows the rest"
}

test_queue_resend_all_live_clears_the_queue() {
  act 2004 idle 120
  bc --children --from manager:app --id rq1
  : > "$FIX/sent.log"
  PANE=%3 bc resend rq1 --undelivered
  assert_eq 0 "$(sent_count)" "resend: an idle queued seat stays queued"
  PANE=%3 bc resend rq1 --undelivered --wake
  assert_eq 1 "$(sent_count)" "resend --all-live: pushes the queued seat"
  assert_file_not_exists "$FIX/bc/queued/app:ask/rq1" "resend --all-live: the queue entry is cleared"
  PANE=%4 bc pending
  assert_hasnt "rq1" "$OUT" "resend --all-live: it is not shown again at wake"
}

test_queue_go_request_idle_owner() {
  go_repo
  act 2004 idle 120
  local c1; c1=$(G rev-parse HEAD~1)
  PANE=%2 goreq --pr 29 --rows alpha,beta --commits base..HEAD --id gq1
  assert_eq 0 "$RC" "go queue: exits 0"
  assert_hasnt "app:ask|" "$(cat "$FIX/sent.log")" "go queue: the idle owner is not pushed"
  bc status gq1
  assert_has $'app:ask\tqueued\tPENDING' "$OUT" "go queue: status says queued and pending"
  PANE=%4 bc pending
  assert_has "receipt path app:ask $c1 $(rid "$c1" kern/a.ts) -- kern/a.ts" "$OUT" "go queue: at wake the owner sees its own receipts"
  assert_hasnt "receipt path domain:stats" "$OUT" "go queue: and only its own"
  assert_has "ack (from manager:app): engine broadcast ack gq1" "$OUT" "go queue: with the go command"
}

# ---------------------------------------------------------------- queue, round 2 (critique SHOULD/NIT)
test_queue_unwritable_falls_back_live() {
  act 2004 idle 120
  : > "$FIX/bc/queued"   # a file where the queue directory should be: no seat's queue can be written
  bc --children --from manager:app --id uw1
  assert_eq 0 "$RC" "unwritable queue: exits 0"
  assert_has "app:ask|" "$(cat "$FIX/sent.log")" "unwritable queue: the idle seat is pushed live instead"
  assert_has "delivered app:ask pid=2004" "$(cat "$FIX/bc/uw1.md")" "unwritable queue: and recorded delivered"
  assert_hasnt "queued app:ask" "$(cat "$FIX/bc/uw1.md")" "unwritable queue: never a queued line with no entry"
  bc status uw1
  assert_has $'app:ask\tdelivered' "$OUT" "unwritable queue: status reads delivered, not queued"
}

test_queue_retracted_or_expired_is_dropped_unshown() {
  act 2004 idle 120; act 2005 idle 120
  bc --children --from manager:app --id rx1 --sticky
  bc --children --from manager:app --id rx2 --sticky --expires 2030-01-01
  assert_file_exists "$FIX/bc/queued/app:ask/rx1" "dropped: rx1 queued"
  bc retract rx1
  assert_eq 0 "$RC" "dropped: rx1 retracted"
  # Expire rx2 in place: its record now says it ended in 2000.
  sed -i.bak 's/^expires: .*/expires: 2000-01-01T00:00:00Z/' "$FIX/bc/rx2.md"
  PANE=%4 bc pending
  assert_hasnt "rx1" "$OUT" "dropped: a retracted queued broadcast is not shown"
  assert_hasnt "rx2" "$OUT" "dropped: an expired queued broadcast is not shown"
  assert_hasnt "delivered app:ask at-wake" "$(cat "$FIX/bc/rx1.md")" "dropped: a retracted one is not marked delivered"
  assert_hasnt "delivered app:ask at-wake" "$(cat "$FIX/bc/rx2.md")" "dropped: an expired one is not marked delivered"
  assert_file_not_exists "$FIX/bc/queued/app:ask/rx1" "dropped: the retracted entry is removed"
  assert_file_not_exists "$FIX/bc/queued/app:ask/rx2" "dropped: the expired entry is removed"
  PANE=%5 bc pending --for app:ui
  assert_hasnt "rx1" "$OUT" "dropped: pending --for does not list a retracted one either"
}

test_queue_waiting_status_is_named() {
  act 2004 waiting 120; act 2005 idle 120
  bc --children --from manager:app --id ws1 --dry-run
  assert_has "binds app:ask → ok 2004 app:ask (queue: idle=120m status=waiting via=status)" "$OUT" "waiting: the dry run names the status"
  bc --children --from manager:app --id ws1
  assert_has "queued app:ask pid=2004 idle=120m status=waiting" "$(cat "$FIX/bc/ws1.md")" "waiting: the queued line says status=waiting"
  assert_has "queued app:ask pid=2004 idle=120m status=waiting" "$OUT" "waiting: and the sender sees it"
  assert_has "queued app:ui pid=2005 idle=120m" "$(cat "$FIX/bc/ws1.md")" "waiting: an idle seat is queued as before"
  assert_hasnt "app:ui pid=2005 idle=120m status=" "$(cat "$FIX/bc/ws1.md")" "waiting: with no status field for an idle one"
}

# ---------------------------------------------------------------- wake kind (IDE-352 round 4)
test_wake_reaches_an_idle_seat_live() {
  act 2004 idle 120; act 2005 idle 500
  bc --children --from manager:app --id wk1 --wake
  assert_eq 0 "$RC" "wake: exits 0"
  assert_has "kind: wake" "$OUT" "wake: the sender is shown the kind"
  assert_eq 2 "$(sent_count)" "wake: both idle seats are pushed live"
  assert_has "delivered app:ask pid=2004" "$(cat "$FIX/bc/wk1.md")" "wake: the idle seat is delivered, not queued"
  assert_hasnt "queued" "$(cat "$FIX/bc/wk1.md")" "wake: nothing queued"
  assert_file_not_exists "$FIX/bc/queued/app:ask/wk1" "wake: no queue entry"
  assert_eq "wake" "$(awk '/^## Text/ { exit } /^kind: / { print $2 }' "$FIX/bc/wk1.md")" "wake: the record header says kind: wake"
  bc status wk1
  assert_has $'app:ask\tdelivered\tnot-acked' "$OUT" "wake: status says delivered"
  assert_has "kind: wake (pushed live to every seat)" "$OUT" "wake: status shows the kind"
}

test_wake_ordinary_still_queues() {
  act 2004 idle 120
  bc --children --from manager:app --id or1
  assert_has "queued app:ask" "$(cat "$FIX/bc/or1.md")" "ordinary: the idle seat is queued"
  assert_hasnt "kind:" "$(awk '/^## Text/ { exit } { print }' "$FIX/bc/or1.md")" "ordinary: no kind header"
  bc status or1
  assert_has "kind: ordinary (idle seats queued)" "$OUT" "ordinary: status shows the kind"
  assert_hasnt "resent as wake" "$OUT" "ordinary: and no wake resend"
}

test_wake_all_live_is_its_alias() {
  act 2004 idle 120
  bc --children --from manager:app --id wa1 --all-live
  assert_hasnt "queued" "$(cat "$FIX/bc/wa1.md")" "alias: --all-live pushes the idle seat"
  bc status wa1
  assert_has "kind: wake" "$OUT" "alias: and records the wake kind"
}

test_wake_choice_gate_and_queue_idle_are_gone() {
  act 2004 idle 120
  BROADCAST_QUEUE_NEEDS_CHOICE=1 bc --children --from manager:app --id gg1
  assert_eq 0 "$RC" "gate gone: the old variable refuses nothing"
  assert_has "queued app:ask" "$(cat "$FIX/bc/gg1.md")" "gate gone: the ordinary send queues"
  bc --children --from manager:app --id gg2 --queue-idle
  assert_eq 2 "$RC" "queue-idle gone: an unknown argument"
  assert_file_not_exists "$FIX/bc/gg2.md" "queue-idle gone: nothing written"
  assert_hasnt "queue-idle" "$(sed -n '1,80p' "$BROADCAST_SH")" "usage: no --queue-idle"
  assert_hasnt "NEEDS_CHOICE" "$(cat "$BROADCAST_SH")" "the gate variable is gone from the script"
  assert_has "engine broadcast --all --wake" "$(sed -n '1,80p' "$BROADCAST_SH")" "usage: names the resume command"
}

test_wake_resend() {
  act 2004 idle 120
  bc --children --from manager:app --id wr1 --wake
  : > "$FIX/sent.log"
  PANE=%3 bc resend wr1
  assert_eq 2 "$(sent_count)" "wake resend: a wake record is resent as a wake"
  assert_has "kind=wake" "$(grep '^resend: ' "$FIX/bc/wr1.md")" "wake resend: the resend line says so"
  bc --children --from manager:app --id wr2
  : > "$FIX/sent.log"
  PANE=%3 bc resend wr2 --undelivered
  assert_eq 0 "$(sent_count)" "ordinary resend: the idle seat stays queued"
  PANE=%3 bc resend wr2 --undelivered --wake
  assert_eq 1 "$(sent_count)" "resend --wake: pushes the queued seat live"
  assert_file_not_exists "$FIX/bc/queued/app:ask/wr2" "resend --wake: the queue entry is cleared"
  bc status wr2
  assert_has "kind: ordinary (idle seats queued); resent as wake 1×" "$OUT" "resend --wake: status shows the wake resend"
}

test_wake_go_request_interplay_unchanged() {
  go_repo
  act 2004 idle 120
  local c1; c1=$(G rev-parse HEAD~1)
  PANE=%2 goreq --pr 29 --rows alpha,beta --commits base..HEAD --id gw1
  assert_hasnt "app:ask|" "$(cat "$FIX/sent.log")" "go+wake: the idle owner is queued, as before"
  assert_eq "go-request" "$(awk '/^## Text/ { exit } /^kind: / { print $2 }' "$FIX/bc/gw1.md")" "go+wake: the record stays kind: go-request"
  : > "$FIX/sent.log"
  PANE=%2 bc resend gw1 --undelivered --wake
  assert_has "app:ask|" "$(cat "$FIX/sent.log")" "go+wake: resend --wake pushes the idle owner"
  assert_has "receipt path app:ask $c1 $(rid "$c1" kern/a.ts) -- kern/a.ts" "$(cat "$FIX/sent.log")" "go+wake: with its own receipt lines"
  assert_hasnt "receipt path domain:stats" "$(grep '^app:ask|' "$FIX/sent.log")" "go+wake: and only its own"
  assert_file_not_exists "$FIX/bc/queued/app:ask/gw1" "go+wake: its queue entry is cleared"
  bc status gw1
  assert_has "go-request: PR 29" "$OUT" "go+wake: status is still the go status"
  assert_has $'app:ask\tdelivered\tPENDING' "$OUT" "go+wake: delivered and pending its answer"
}

test_queue_wake_key_keeps_what_it_claimed() {
  act 2004 idle 120
  bc --children --from manager:app --id wkk1
  PANE=%4 BROADCAST_WAKE_KEY=ss-sid1_startup bc pending
  assert_has $'wkk1\tmanager:director\tqueued' "$OUT" "wake key: the first generation shows it"
  PANE=%4 BROADCAST_WAKE_KEY=ss-sid1_startup bc pending
  assert_has $'wkk1\tmanager:director\tqueued' "$OUT" "wake key: a second generation for the same event shows it again"
  assert_has "ack (from manager:director): engine broadcast ack wkk1" "$OUT" "wake key: with its message"
  assert_eq 1 "$(grep -c '^delivered app:ask at-wake' "$FIX/bc/wkk1.md")" "wake key: marked delivered once"
  PANE=%4 BROADCAST_WAKE_KEY=ss-sid2_clear bc pending
  assert_hasnt "wkk1" "$OUT" "wake key: another event does not see it"
  PANE=%4 bc pending
  assert_hasnt "wkk1" "$OUT" "wake key: nor does a pending with no key"
  PANE=%4 BROADCAST_WAKE_KEY='../x' bc pending
  assert_eq 2 "$RC" "wake key: a key that is not a plain name is refused"
}

test_queue_dead_claim_is_recovered() {
  act 2004 idle 120
  bc --children --from manager:app --id dc1
  bc --children --from manager:app --id dc2
  local qd="$FIX/bc/queued/app:ask"
  mv "$qd/dc1" "$qd/.dc1.claim.99999999"   # its hook was killed after the claim
  mv "$qd/dc2" "$qd/.dc2.claim.$$"         # a claim whose process still runs
  PANE=%4 bc pending --for app:ask
  assert_hasnt "dc1" "$OUT" "dead claim: a read does not recover it"
  PANE=%4 bc pending
  assert_has $'dc1\tmanager:director\tqueued' "$OUT" "dead claim: a claim whose process died is shown again"
  assert_file_not_exists "$qd/.dc1.claim.99999999" "dead claim: and the claim file is gone"
  assert_hasnt "dc2" "$OUT" "dead claim: a live process's claim is left to it"
  assert_file_exists "$qd/.dc2.claim.$$" "dead claim: untouched"
}

test_queue_ack_clears_the_entry() {
  act 2004 idle 120
  bc --children --from manager:app --id ak1
  PANE=%4 bc ack ak1
  assert_eq 0 "$RC" "ack clears: the seat acks from the record"
  assert_file_not_exists "$FIX/bc/queued/app:ask/ak1" "ack clears: its queue entry is gone"
  PANE=%4 bc pending
  assert_hasnt "ak1" "$OUT" "ack clears: it is not shown at the next wake"
}

test_queue_push_sets_the_entry_aside_first() {
  act 2004 idle 120
  bc --children --from manager:app --id ps1
  echo app:ask > "$FIX/failseats"
  PANE=%3 bc resend ps1 --undelivered --all-live
  assert_has "undelivered app:ask" "$(cat "$FIX/bc/ps1.md")" "push aside: a failed push is undelivered"
  assert_file_exists "$FIX/bc/queued/app:ask/ps1" "push aside: and its queue entry is put back"
  : > "$FIX/failseats"; rm -f "$FIX/queued-at-push"
  PANE=%3 bc resend ps1 --undelivered --all-live
  assert_has "delivered app:ask pid=2004" "$(cat "$FIX/bc/ps1.md")" "push aside: the retry lands"
  assert_file_not_exists "$FIX/queued-at-push" "push aside: the entry was out of the queue while the push ran"
  assert_file_not_exists "$FIX/bc/queued/app:ask/ps1" "push aside: and is gone after it"
}

# ---------------------------------------------------------------- round 5 (critique R-B, R-C, P1, P3, NITs)
test_queue_peek_lists_without_marking() {
  act 2004 idle 120
  bc --children --from manager:app --id pk1
  PANE=%4 bc pending --queued --peek
  assert_eq 0 "$RC" "peek: exits 0"
  assert_has $'pk1\tmanager:director\tqueued' "$OUT" "peek: lists this pane's own queue"
  assert_has "ack (from manager:director): engine broadcast ack pk1" "$OUT" "peek: with the message"
  assert_file_exists "$FIX/bc/queued/app:ask/pk1" "peek: the entry stays queued"
  assert_hasnt "at-wake" "$(cat "$FIX/bc/pk1.md")" "peek: nothing is marked delivered"
  PANE=%4 bc pending --queued
  assert_has $'pk1\tmanager:director\tqueued' "$OUT" "peek: a later marking read still shows it"
  assert_file_not_exists "$FIX/bc/queued/app:ask/pk1" "peek: and that one consumes it"
}

test_queue_readonly_dir_falls_back_live() {
  act 2004 idle 120
  mkdir -p "$FIX/bc/queued/app:ask"; chmod 555 "$FIX/bc/queued/app:ask"
  bc --children --from manager:app --id ro1
  chmod 755 "$FIX/bc/queued/app:ask"
  assert_eq 0 "$RC" "read-only queue: exits 0"
  assert_has "app:ask|" "$(cat "$FIX/sent.log")" "read-only queue: the idle seat is pushed live instead"
  assert_has "delivered app:ask pid=2004" "$(cat "$FIX/bc/ro1.md")" "read-only queue: and recorded delivered"
  assert_hasnt "queued app:ask" "$(cat "$FIX/bc/ro1.md")" "read-only queue: never a queued line with no entry"
  assert_file_not_exists "$FIX/bc/queued/app:ask/ro1" "read-only queue: and no entry was written"
}

test_idle_status_field_missing_still_reads() {
  local ms=$(( ($(date +%s) - 7200) * 1000 ))
  jq -c --argjson t "$ms" 'del(.status) + {statusUpdatedAt: $t, sessionId: "", cwd: "/w/x"}' "$FIX/sess/2004.json" > "$FIX/sess/2004.tmp" \
    && mv "$FIX/sess/2004.tmp" "$FIX/sess/2004.json"
  bc --children --from manager:app --id ef1
  assert_has "queued app:ask pid=2004 idle=120m via=status" "$(cat "$FIX/bc/ef1.md")" "empty field: no status and an empty sessionId do not shift statusUpdatedAt"
}

test_idle_same_name_in_two_projects_takes_newest() {
  act 2004 idle 120; tx 2004 3
  local sid="sess-2004" a="$FIX/projects/-a-stale" z="$FIX/projects/-z-live"
  mkdir -p "$a" "$z"
  { printf '{"type":"user","timestamp":"%s"}\n' "$(iso_ago 1000)"; } > "$a/$sid.jsonl"
  touch -t 202001010000 "$a/$sid.jsonl"
  mv "$TXF" "$z/$sid.jsonl"   # the cwd's slug now misses; the live copy sorts after the stale one
  rmdir "$(dirname "$TXF")" 2>/dev/null
  bc --children --from manager:app --id nw1
  assert_has "delivered app:ask pid=2004" "$(cat "$FIX/bc/nw1.md")" "same name: the newest copy (a turn 3m ago) is read, not the first directory's"
  assert_hasnt "queued app:ask" "$(cat "$FIX/bc/nw1.md")" "same name: and the seat is not queued from the stale copy"
  local got; got=$(bash -c 'source "$1" >/dev/null 2>&1; transcript_by_key "$2" /w/none "$3"' _ "$LIB_SH" "$sid.jsonl" "$FIX/projects")
  assert_eq "$z/$sid.jsonl" "$got" "same name: transcript_by_key prints the newest by mtime"
  touch -t 202001010000 "$z/$sid.jsonl"; touch "$a/$sid.jsonl"
  got=$(bash -c 'source "$1" >/dev/null 2>&1; transcript_by_key "$2" /w/none "$3"' _ "$LIB_SH" "$sid.jsonl" "$FIX/projects")
  assert_eq "$a/$sid.jsonl" "$got" "same name: and follows the mtime, not the directory order"
}

test_ack_drops_the_wake_copy() {
  act 2004 idle 120
  bc --children --from manager:app --id wc1
  PANE=%4 BROADCAST_WAKE_KEY=ss-sid9_startup bc pending
  assert_file_exists "$FIX/bc/queued/app:ask/.wake.ss-sid9_startup/wc1" "wake copy: the claimed item is kept for its wake key"
  PANE=%4 bc ack wc1
  assert_file_not_exists "$FIX/bc/queued/app:ask/.wake.ss-sid9_startup/wc1" "wake copy: an ack drops it"
  PANE=%4 BROADCAST_WAKE_KEY=ss-sid9_startup bc pending
  assert_hasnt "wc1" "$OUT" "wake copy: a regenerated preload does not list an acked item"
}

test_go_request_takes_wake() {
  go_repo
  act 2004 idle 120
  PANE=%2 goreq --pr 29 --rows alpha,beta --commits base..HEAD --id gwk1 --wake
  assert_eq 0 "$RC" "go --wake: accepted"
  assert_has "app:ask|" "$(cat "$FIX/sent.log")" "go --wake: the idle owner is pushed live"
  assert_eq "go-request" "$(awk '/^## Text/ { exit } /^kind: / { print $2 }' "$FIX/bc/gwk1.md")" "go --wake: the record stays kind: go-request"
}

test_queue_requeue_keeps_its_place() {
  act 2004 idle 120
  bc --children --from manager:app --id rp1
  touch -t 202001010000 "$FIX/bc/queued/app:ask/rp1"
  touch "$FIX/now"
  PANE=%3 bc resend rp1 --undelivered
  assert_has "queued app:ask" "$(tail -n 3 "$FIX/bc/rp1.md")" "requeue: queued again"
  if [ "$FIX/bc/queued/app:ask/rp1" -ot "$FIX/now" ]; then pass "requeue: the entry keeps its mtime (its place in the queue)"
  else fail "requeue: the entry keeps its mtime (its place in the queue)" "older than now" "touched"; fi
}

# ---------------------------------------------------------------- idle by transcript (IDE-352 round 3)
# tx <pid> <user-minutes-ago> [assistant-minutes-ago] — bind the session to a transcript under
# $FIX/projects (slugged from its cwd, as lib.sh transcript_by_key finds it) holding one user and
# one assistant event at those ages, after a summary line that carries no timestamp of its own.
iso_ago() { date -u -r $(( $(date +%s) - $1 * 60 )) +%Y-%m-%dT%H:%M:%S.123Z; }
tx() {
  local sid="sess-$1" cwd="/w/seat$1" d
  jq -c --arg s "$sid" --arg c "$cwd" '. + {sessionId: $s, cwd: $c}' "$FIX/sess/$1.json" > "$FIX/sess/$1.tmp" \
    && mv "$FIX/sess/$1.tmp" "$FIX/sess/$1.json"
  d="$FIX/projects/$(printf '%s' "$cwd" | sed 's|/|-|g')"; mkdir -p "$d"
  { printf '{"type":"summary","summary":"s"}\n'
    printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"hi"}}\n' "$(iso_ago "$2")"
    printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[]}}\n' "$(iso_ago "${3:-$2}")"
  } > "$d/$sid.jsonl"
  TXF="$d/$sid.jsonl"
}

test_idle_transcript_newer_than_status_is_active() {
  act 2004 idle 120; tx 2004 3
  bc --children --from manager:app --id tr1
  assert_has "delivered app:ask pid=2004" "$(cat "$FIX/bc/tr1.md")" "transcript: a turn 3m ago in the transcript is active though the status is 120m old"
  assert_hasnt "queued app:ask" "$(cat "$FIX/bc/tr1.md")" "transcript: and is not queued"
}

test_idle_status_newer_but_transcript_old_is_idle() {
  act 2004 idle 5; tx 2004 130 120
  bc --children --from manager:app --id tr2
  assert_has "queued app:ask pid=2004 idle=120m via=transcript" "$(cat "$FIX/bc/tr2.md")" "transcript: an old transcript queues the seat though the status changed 5m ago, from its newest event"
  assert_file_exists "$FIX/bc/queued/app:ask/tr2" "transcript: and the queue holds it"
  bc --children --from manager:app --id tr2d --dry-run
  assert_has "(queue: idle=120m via=transcript)" "$OUT" "transcript: the dry run names the source"
}

test_idle_busy_is_active_whatever_the_transcript() {
  act 2004 busy 120; tx 2004 120
  bc --children --from manager:app --id tr3
  assert_has "delivered app:ask pid=2004" "$(cat "$FIX/bc/tr3.md")" "transcript: a busy session is active even with an old transcript"
}

test_idle_no_transcript_falls_back_to_status() {
  act 2004 idle 120; act 2005 idle 120; tx 2005 120
  jq -c '. + {sessionId: "no-such-session", cwd: "/w/none"}' "$FIX/sess/2004.json" > "$FIX/sess/2004.tmp" && mv "$FIX/sess/2004.tmp" "$FIX/sess/2004.json"
  bc --children --from manager:app --id tr4
  assert_has "queued app:ask pid=2004 idle=120m via=status" "$(cat "$FIX/bc/tr4.md")" "fallback: no transcript for the session id reads statusUpdatedAt"
  assert_has "queued app:ui pid=2005 idle=120m via=transcript" "$(cat "$FIX/bc/tr4.md")" "fallback: beside a seat read from its transcript"
  act 2004 idle 5
  bc --children --from manager:app --id tr4b
  assert_has "delivered app:ask pid=2004" "$(cat "$FIX/bc/tr4b.md")" "fallback: a recent status with no transcript is active"
}

test_idle_transcript_without_event_falls_back() {
  act 2004 idle 120; tx 2004 3
  printf '{"type":"summary","summary":"s"}\n' > "$TXF"
  bc --children --from manager:app --id tr5
  assert_has "queued app:ask pid=2004 idle=120m via=status" "$(cat "$FIX/bc/tr5.md")" "fallback: a transcript with no user/assistant event reads statusUpdatedAt"
}

test_idle_malformed_last_line_is_skipped() {
  act 2004 idle 5; tx 2004 130 120
  printf '{"type":"assistant","timestamp":"%s","message":' "$(iso_ago 1)" >> "$TXF"
  bc --children --from manager:app --id tr6
  assert_has "queued app:ask pid=2004 idle=120m via=transcript" "$(cat "$FIX/bc/tr6.md")" "malformed: a cut-off last line is skipped; the previous event is read"
}

test_idle_reads_only_the_tail() {
  act 2004 idle 120; tx 2004 120
  local big; big=$(printf 'x%.0s' $(seq 3000))
  printf '{"type":"user","timestamp":"%s","message":{"content":"%s"}}\n' "$(iso_ago 2)" "$big" > "$TXF.new"
  printf '{"type":"progress","data":"%s"}\n' "$big" >> "$TXF.new"
  mv "$TXF.new" "$TXF"
  BROADCAST_TRANSCRIPT_TAIL=2000 bc --children --from manager:app --id tr7
  assert_has "queued app:ask pid=2004 idle=120m via=status" "$(cat "$FIX/bc/tr7.md")" "tail: an event before the tail is not read (the cut first line is dropped)"
  bc --children --from manager:app --id tr7b
  assert_has "delivered app:ask pid=2004" "$(cat "$FIX/bc/tr7b.md")" "tail: with the default tail the same event is read"
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
  assert_hasnt "strict" "$OUT" "go-check R4: the FAIL text no longer calls the check strict"
  assert_hasnt "a context-only move included" "$OUT" "go-check R4: nor says a context-only move fails without recourse"
  assert_has "MOVED means the diff text" "$OUT" "go-check R4: the FAIL text says what MOVED means: the diff text changed"
  assert_has "context lines" "$OUT" "go-check R4: and names a change only in context lines"
  assert_has "LANDING.md step 4" "$OUT" "go-check R4: as covered by LANDING step 4's judgement"
  assert_has "anything else needs the owner's fresh go" "$OUT" "go-check R4: and anything else needs the owner's fresh go"
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
  # Globs alone: a kern/ dir line would outrank both (round 5: every literal beats every glob).
  sed -i.bak '/^kern\//d' "$FIX/owners"; rm -f "$FIX/owners.bak"
  printf 'kern*a.ts domain:stats\n*/a.ts app:ui\n' >> "$FIX/owners"
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --dry-run
  assert_eq 0 "$RC" "N4: the request resolves"
  assert_eq "app:ui" "$(audience)" "N4: the two-segment pattern wins over a longer one-segment pattern"
}

# R2-S1: at equal segments a literal pattern (a path, or a dir/ prefix) beats one holding * or ?.
# "resource-* except resource-kernel" is written as the family glob plus the exception's dir/ line.
test_go_owners_map_except_shape() {
  go_repo
  cat > "$FIX/owners" <<'X'
kern*   app:ui
kern/   app:ask
stat*   domain:stats
ui/     app:ui
X
  PANE=%2 goreq --pr 28 --rows alpha,beta --commits base..HEAD --dry-run
  assert_eq 0 "$RC" "R2-S1: 'kern*' and the exception 'kern/' do not tie"
  assert_eq "app:ask domain:stats app:ui" "$(audience)" "R2-S1: the exception's dir/ line wins its tree, the family glob still maps the rest"
}

# A catch-all '*' is the default seat; it does not tie with every top-level dir/ line.
test_go_owners_map_catchall_default() {
  go_repo
  cat > "$FIX/owners" <<'X'
*       app:ui
kern/   app:ask
stats/  domain:stats
X
  PANE=%2 goreq --pr 28 --rows alpha,beta --commits base..HEAD --dry-run
  assert_eq 0 "$RC" "R2-S1: a catch-all '*' does not tie with a top-level dir/ line"
  assert_eq "app:ask domain:stats app:ui" "$(audience)" "R2-S1: the dir/ lines win their trees, the catch-all takes the rest"
}

# A literal file beats a file glob at the same depth, in either order in the map.
test_go_owners_map_literal_file_beats_file_glob() {
  go_repo
  printf 'kern/*.ts app:ui\nkern/a.ts domain:stats\n' >> "$FIX/owners"
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --dry-run
  assert_eq 0 "$RC" "R2-S1: kern/a.ts against kern/*.ts resolves (glob listed first)"
  assert_eq "domain:stats" "$(audience)" "R2-S1: the literal file wins (glob listed first)"
  printf 'kern/   app:ask\nkern/a.ts domain:stats\nkern/*.ts app:ui\n' > "$FIX/owners"
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --dry-run
  assert_eq 0 "$RC" "R2-S1: kern/a.ts against kern/*.ts resolves (literal listed first)"
  assert_eq "domain:stats" "$(audience)" "R2-S1: the literal file wins (literal listed first)"
}

# Two globs at the same depth that map to different seats still tie and refuse.
test_go_owners_map_glob_vs_glob_still_ties() {
  go_repo
  sed -i.bak '/^kern\//d' "$FIX/owners"; rm -f "$FIX/owners.bak"   # no dir line to outrank them
  printf 'kern/*.ts app:ui\nkern/a.* domain:stats\n' >> "$FIX/owners"
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD
  assert_eq 2 "$RC" "R2-S1: two globs at equal depth for one path, two seats, refuse"
  assert_has "maps to two seats equally" "$OUT" "R2-S1: and say it is a tie"
  assert_eq 0 "$(sent_count)" "R2-S1: nothing sent on the tie"
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

# ---------------------------------------------------------------- go, round 4: --paths, MOVED wording
# --paths alone: each path's owner is asked through the owners map, as a row's owner path would be.
test_go_paths_reach_their_owners() {
  go_repo
  local c1 c2; c1=$(G rev-parse HEAD~1); c2=$(G rev-parse HEAD)
  PANE=%2 goreq --pr 28 --paths kern/a.ts,ui/c.ts --commits base..HEAD --id gp1
  assert_eq 0 "$RC" "paths: a go request with --paths alone exits 0"
  assert_eq "app:ask app:ui" "$(audience)" "paths: the audience is exactly the paths' owner seats"
  assert_eq 2 "$(sent_count)" "paths: one message per owner seat"
  assert_has "paths: kern/a.ts ui/c.ts" "$(rec_of gp1)" "paths: the record header names the paths"
  assert_has "receipt path app:ask $c1 $(rid "$c1" kern/a.ts) -- kern/a.ts" "$(cat "$FIX/msg.app:ask")" "paths: app:ask's receipt for c1, over its given path"
  assert_has "receipt path app:ask $c2 $(rid "$c2" kern/a.ts) -- kern/a.ts" "$(cat "$FIX/msg.app:ask")" "paths: app:ask's receipt for c2"
  assert_has "receipt path app:ui $c2 $(rid "$c2" ui/c.ts) -- ui/c.ts" "$(cat "$FIX/msg.app:ui")" "paths: app:ui's receipt"
  assert_hasnt "app:ui" "$(cat "$FIX/msg.app:ask")" "paths: each owner's message carries only its own lines"
  bc status gp1
  assert_has "paths kern/a.ts ui/c.ts" "$OUT" "paths: status reads the paths header"
  PANE=%4 bc ack gp1; PANE=%5 bc ack gp1
  bc go-check gp1 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 0 "$RC" "paths: go-check passes when every path owner gave its GO"
  assert_has "paths kern/a.ts ui/c.ts" "$(grep 'go-check: PASS' <<<"$OUT")" "paths: the PASS line names the paths it covered"
  printf 'c2-amended\n' > "$FIX/repo/ui/c.ts"; G commit -q -a --amend -m c2
  bc go-check gp1 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 1 "$RC" "paths: an amended commit on a given path fails go-check"
  assert_has "MOVED app:ui" "$OUT" "paths: naming the path's owner"
}

# --rows and --paths together: the audience is the union, and a seat reached both ways gets one
# receipt line per commit over the union of its paths.
test_go_rows_and_paths_union() {
  go_repo
  local c1 c2; c1=$(G rev-parse HEAD~1); c2=$(G rev-parse HEAD)
  PANE=%2 goreq --pr 28 --rows alpha --paths stats/b.ts --commits base..HEAD --id gu1
  assert_eq 0 "$RC" "union: rows and paths together exit 0"
  assert_eq "app:ask domain:stats" "$(audience)" "union: the audience is the union of the rows' and the paths' seats"
  assert_has "rows: alpha" "$(rec_of gu1)" "union: the record keeps the rows header"
  assert_has "paths: stats/b.ts" "$(rec_of gu1)" "union: and adds the paths header"
  PANE=%4 bc ack gu1; PANE=%7 bc ack gu1
  bc go-check gu1 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 0 "$RC" "union: go-check passes"
  assert_has "rows alpha" "$(grep 'go-check: PASS' <<<"$OUT")" "union: the PASS line names the rows"
  assert_has "paths stats/b.ts" "$(grep 'go-check: PASS' <<<"$OUT")" "union: and the paths"
  # beta's owner paths are stats/b.ts and ui/c.ts; --paths repeats ui/c.ts: one path, one line.
  PANE=%2 goreq --pr 28 --rows beta --paths ui/c.ts --commits base..HEAD --id gu2
  assert_eq 0 "$RC" "union: a path a row already names is fine"
  assert_has "receipt path app:ui $c2 $(rid "$c2" ui/c.ts) -- ui/c.ts" "$(rec_of gu2)" "union: one receipt over ui/c.ts, not the path twice"
  assert_hasnt "-- ui/c.ts ui/c.ts" "$(rec_of gu2)" "union: the path is not repeated"
  # A seat reached by a row and by a path: one id over both paths, equal to the hand command.
  PANE=%2 goreq --pr 28 --rows alpha --paths kern/untouched.ts --commits base..HEAD --id gu3
  assert_eq 2 "$RC" "union: an owner whose --paths give an empty receipt refuses even when its row has one"
  printf 'u1\n' > "$FIX/repo/kern/untouched.ts"; printf 'a3\n' >> "$FIX/repo/kern/a.ts"; G commit -qam c3
  local c3; c3=$(G rev-parse HEAD)
  PANE=%2 goreq --pr 28 --rows alpha --paths kern/untouched.ts --commits base..HEAD --id gu4
  assert_eq 0 "$RC" "union: once the path is touched, the request goes"
  assert_has "receipt path app:ask $c3 $(rid "$c3" kern/a.ts kern/untouched.ts) -- kern/a.ts kern/untouched.ts" "$(rec_of gu4)" "union: one receipt per commit over the row's and the given paths"
  assert_eq 1 "$(grep -c "^receipt path app:ask $c3 " "$FIX/bc/gu4.md" | tr -d ' ')" "union: exactly one line for that seat and commit"
}

# Refusals mirror rows: unmapped, tie, non-live seat, empty receipt — each naming the path.
test_go_paths_refusals() {
  go_repo
  PANE=%2 goreq --pr 28 --paths orphan/d.ts --commits base..HEAD
  assert_eq 2 "$RC" "paths: a path no seat maps refuses"
  assert_has "path 'orphan/d.ts'" "$OUT" "paths: and names the path"
  PANE=%2 goreq --pr 28 --paths ghost/z.ts --commits base..HEAD
  assert_eq 3 "$RC" "paths: a path whose seat is not live refuses with 3"
  assert_has "ghost/z.ts" "$OUT" "paths: and names the path"
  PANE=%2 goreq --pr 28 --paths kern/untouched.ts --commits base..HEAD
  assert_eq 2 "$RC" "paths: a path whose receipt is empty on every commit refuses"
  assert_has "empty" "$OUT" "paths: says the receipt is empty"
  assert_has "kern/untouched.ts" "$OUT" "paths: and names the path"
  PANE=%2 goreq --pr 28 --rows alpha --paths orphan/d.ts --commits base..HEAD
  assert_eq 2 "$RC" "paths: a bad path refuses even beside a good row"
  printf 'kern/a.ts app:ui\nkern/a.ts domain:stats\n' >> "$FIX/owners"
  PANE=%2 goreq --pr 28 --paths kern/a.ts --commits base..HEAD
  assert_eq 2 "$RC" "paths: a path two seats map equally refuses"
  assert_has "two seats equally" "$OUT" "paths: says it is a tie"
  PANE=%2 goreq --pr 28 --commits base..HEAD
  assert_eq 2 "$RC" "paths: neither --rows nor --paths refuses"
  assert_has "--paths" "$OUT" "paths: and the refusal names both flags"
  assert_eq 0 "$(sent_count)" "paths: nothing sent on any refusal"
  assert_eq 0 "$(nrec)" "paths: no record on any refusal"
}

# Paths are literal: kern/*.ts from a cwd where it would match files is still the one path kern/*.ts.
test_go_paths_are_literal() {
  go_repo
  pushd "$FIX/repo" >/dev/null; PANE=%2 goreq --pr 28 --paths 'kern/*.ts' --commits base..HEAD --dry-run; popd >/dev/null
  assert_eq 2 "$RC" "paths literal: 'kern/*.ts' is one path, so from the repo root its receipt is empty and it refuses"
  assert_has "kern/*.ts" "$OUT" "paths literal: and names the literal path"
  assert_hasnt "kern/a.ts" "$OUT" "paths literal: never expanded to the files it would match"
  pushd "$FIX/repo" >/dev/null; PANE=%2 goreq --pr 28 --paths 'kern/a.ts,kern/*.ts' --commits base..HEAD --id gl1; popd >/dev/null
  assert_eq 0 "$RC" "paths literal: beside a real path the request goes"
  assert_has "-- kern/a.ts kern/*.ts" "$(rec_of gl1)" "paths literal: the receipt line keeps the literal path"
}

# A record from before --paths (no paths: header) still reads the same in status and go-check.
test_go_rows_only_record_has_no_paths_header() {
  go_repo
  PANE=%2 goreq --pr 28 --rows alpha --commits base..HEAD --id gr1
  assert_hasnt "paths:" "$(sed -n '/^## Text/q;p' "$FIX/bc/gr1.md")" "rows only: the record has no paths header"
  bc status gr1
  assert_hasnt "paths" "$OUT" "rows only: status does not mention paths"
  PANE=%4 bc ack gr1
  bc go-check gr1 --repo "$FIX/repo" --commits base..HEAD
  assert_eq 0 "$RC" "rows only: go-check passes"
  assert_has "each owner of rows alpha has a GO" "$OUT" "rows only: the PASS line reads as before, naming only the rows"
}

test_go_usage_names_paths() {
  bc --help
  assert_has "--paths" "$OUT" "usage: names --paths"
}

# patch-id --stable ignores line numbers: a re-pick that only shifts lines (an unrelated commit
# earlier in the same file) keeps the id and passes; a change to a context line moves it.
test_go_check_line_shift_passes() {
  go_repo
  seq 1 20 > "$FIX/repo/kern/a.ts"; G commit -qam long; G tag lbase
  sed -i.bak 's/^15$/fifteen/' "$FIX/repo/kern/a.ts"; rm -f "$FIX/repo/kern/a.ts.bak"; G commit -qam x
  local x; x=$(G rev-parse HEAD)
  PANE=%2 goreq --pr 28 --rows alpha --commits lbase..HEAD --id gs1
  PANE=%4 bc ack gs1
  G checkout -q -b shifted lbase
  { printf 'h1\nh2\nh3\nh4\nh5\n'; cat "$FIX/repo/kern/a.ts"; } > "$FIX/repo/kern/a.ts.n"; mv "$FIX/repo/kern/a.ts.n" "$FIX/repo/kern/a.ts"
  G commit -qam unrelated-top; G tag sbase
  G cherry-pick "$x" >/dev/null
  local h0 h1
  h0=$(git -C "$FIX/repo" show "$x" -- kern/a.ts | grep '^@@')
  h1=$(git -C "$FIX/repo" show HEAD -- kern/a.ts | grep '^@@')
  assert_not_empty "$h0" "line shift: fixture: the original hunk has a header"
  [ "$h0" != "$h1" ] && pass "line shift: fixture: the re-picked hunk sits at other line numbers" \
    || fail "line shift: fixture: the re-picked hunk sits at other line numbers" "differ" "$h0 / $h1"
  bc go-check gs1 --repo "$FIX/repo" --commits sbase..HEAD
  assert_eq 0 "$RC" "line shift: a re-pick that only shifts lines keeps its go"
  # Control: a context line beside the change moves, so the id moves.
  G checkout -q -b ctx lbase
  sed -i.bak 's/^12$/twelve/' "$FIX/repo/kern/a.ts"; rm -f "$FIX/repo/kern/a.ts.bak"; G commit -qam ctxchange; G tag cbase
  G cherry-pick "$x" >/dev/null
  bc go-check gs1 --repo "$FIX/repo" --commits cbase..HEAD
  assert_eq 1 "$RC" "line shift control: a changed context line moves the receipt"
  assert_has "MOVED app:ask" "$OUT" "line shift control: naming the owner"
  assert_has "context lines" "$OUT" "line shift control: and the FAIL text points context-only changes at LANDING step 4"
}

# ---------------------------------------------------------------- owners from the doc (round 5)
# Operator rulings OWNERS=LINE and SHARED=ALLLANES: with no --owners, a go-request reads the seats
# from the "Ownership is fixed" line of docs/LIVE_MARKET_DIRECT.md at the range's tip, through
# doc-signals.sh owners-from-doc --emit lane. Fixtures are copies of that line from kit:
# ownfix-073237f16.md (docs:handbook's fixed line, the expected-good case) and ide330c-a31c445f1.md.
OWN_FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/ownership"
DOC_SEATS="domain:platform core:exchange domain:language core:world core:realm domain:agent packages:converge packages:schemistry core:kernel domain:storage domain:security domain:stats app:deploy core:ops docs:handbook docs:api app:writer core:ui"
# live_add <seat>… — more live seats (pane %2N, a registered interactive session each).
live_add() {
  local n=20 seat
  for seat in "$@"; do
    grep -q "^$seat " "$FIX/live.txt" && continue
    n=$((n + 1)); echo "$seat %$n manager:director" >> "$FIX/live.txt"
    echo "%$n 10$n" >> "$FIX/panepids"; echo "10$n 1" >> "$FIX/ps"; reg "20$n" "$seat" "10$n"
  done
}
# doc_repo <fixture> — go_repo plus that doc committed at the tag dbase, then one commit (HEAD)
# touching a file under each lane the tests ask about.
DOC_FILES="README.md ARCHITECTURE.md VOICE.md LANDING.md CI.md world-runner/src/ideas-app/server/main.ts world-runner/src/ideas-app/server/server.ts world-runner/src/ideas-app/hire.ts world-runner/src/ideas-app/server/worker-main.ts world-runner/src/other.ts ideas-exchange/x.ts ideas-storage/x.ts design/a.ts design/cli-theme/t.css handbook/README.md playground/p.ts app/Dockerfile package.json .husky/pre-commit"
# A second fixture argument is copied to handbook/README.md (its "Who owns each folder" table);
# DOC_EXTRA names more files, made and touched like DOC_FILES.
doc_repo() {
  go_repo
  live_add $DOC_SEATS
  local f
  for f in $DOC_FILES ${DOC_EXTRA-}; do mkdir -p "$FIX/repo/$(dirname "$f")"; echo 0 > "$FIX/repo/$f"; done
  mkdir -p "$FIX/repo/docs"; cp "$OWN_FIX/$1" "$FIX/repo/docs/LIVE_MARKET_DIRECT.md"
  [ -z "${2:-}" ] || cp "$OWN_FIX/$2" "$FIX/repo/handbook/README.md"
  G add -A; G commit -qm doc; G tag dbase
  for f in $DOC_FILES ${DOC_EXTRA-} CONTRACTS.md; do echo 1 >> "$FIX/repo/$f"; done
  G commit -qam lanes
}
# msg_has <seat> <path> → 0 when that seat's last message has a receipt line over the path
msg_has() { grep -E "^receipt path $1 [0-9a-f]+ [0-9a-f]+ -- (.* )?$2( |\$)" "$FIX/msg.$1" >/dev/null 2>&1; }
goreqd() { bc go-request --repo "$FIX/repo" --commits dbase..HEAD "$@"; }

test_go_owners_from_doc_is_the_default() {
  doc_repo ownfix-073237f16.md
  PANE=%2 goreqd --pr 5 --paths world-runner/src/other.ts --dry-run
  assert_eq 0 "$RC" "doc owners: a request with no --owners resolves from the doc"
  assert_eq "domain:language" "$(audience)" "doc owners: world-runner/ is domain:language's"
  assert_has 'The owners map is the "Ownership is fixed" line of docs/LIVE_MARKET_DIRECT.md at' "$OUT" "doc owners: the message names the line and the tip it was read at"
  PANE=%2 goreqd --pr 5 --paths ideas-exchange/x.ts --dry-run
  assert_eq "core:exchange" "$(audience)" "doc owners: ideas-exchange/ is core:exchange's"
  PANE=%2 goreqd --pr 5 --paths playground/p.ts --dry-run
  assert_eq "domain:agent" "$(audience)" "doc owners: playground/, its own lane bullet in the fixed line"
}

test_go_owners_from_doc_reads_the_tip_not_the_worktree() {
  doc_repo ownfix-073237f16.md
  sed -i.bak 's/^  - core:world: /  - domain:stats: /; s/^  - domain:language: /  - app:ui: /' "$FIX/repo/docs/LIVE_MARKET_DIRECT.md"; rm -f "$FIX/repo/docs/LIVE_MARKET_DIRECT.md.bak"
  PANE=%2 goreqd --pr 5 --paths world-runner/src/ideas-app/server/main.ts,world-runner/src/other.ts --dry-run
  assert_eq 0 "$RC" "doc tip: an uncommitted edit of the doc does not change the answer"
  assert_eq "core:world domain:language" "$(audience)" "doc tip: the seats are the committed line's"
  # A later commit that removes the doc: a range ending before it still reads it; one ending on it refuses.
  G checkout -q docs/LIVE_MARKET_DIRECT.md; G rm -q docs/LIVE_MARKET_DIRECT.md; G commit -qm nodoc
  PANE=%2 bc go-request --repo "$FIX/repo" --commits dbase..HEAD~1 --pr 5 --paths world-runner/src/other.ts --dry-run
  assert_eq 0 "$RC" "doc tip: the doc is read at the range's tip, not at HEAD"
  PANE=%2 goreqd --pr 5 --paths world-runner/src/other.ts --dry-run
  assert_eq 2 "$RC" "doc tip: no doc at the tip refuses"
  assert_has "no docs/LIVE_MARKET_DIRECT.md at the tip" "$OUT" "doc tip: naming the doc and the tip"
}

test_go_owners_from_doc_precedence() {
  doc_repo ownfix-073237f16.md
  PANE=%2 goreqd --pr 5 --paths world-runner/src/ideas-app/server/main.ts --dry-run
  assert_eq "core:world" "$(audience)" "doc precedence: an exact path beats its dir/ (main.ts → core:world)"
  PANE=%2 goreqd --pr 5 --paths world-runner/src/other.ts --dry-run
  assert_eq "domain:language" "$(audience)" "doc precedence: the rest of world-runner/ stays domain:language's"
  PANE=%2 goreqd --pr 5 --paths design/cli-theme/t.css --dry-run
  assert_eq "app:writer" "$(audience)" "doc precedence: a longer dir/ beats a shorter one (design/cli-theme/ over design/)"
  PANE=%2 goreqd --pr 5 --paths ideas-storage/x.ts --dry-run
  assert_eq "domain:storage" "$(audience)" "doc precedence: a dir/ beats a glob (ideas-storage/ over ideas-*)"
  # A deeper glob still loses to a shallower dir/: every literal outranks every glob.
  printf 'kern/*.ts app:ui\nkern/ app:ask\n' > "$FIX/owners2"
  PANE=%2 bc go-request --repo "$FIX/repo" --owners "$FIX/owners2" --commits base..dbase --pr 5 --rows alpha --dry-run
  assert_eq 0 "$RC" "precedence: kern/ against a deeper kern/*.ts resolves"
  assert_eq "app:ask" "$(audience)" "precedence: the dir/ wins over a deeper glob"
}

test_go_owners_from_doc_tie_refused() {
  doc_repo ownfix-073237f16.md
  awk '{ print } /^  - core:exchange: / { print "  - domain:stats: world-runner." }' "$OWN_FIX/ownfix-073237f16.md" > "$FIX/repo/docs/LIVE_MARKET_DIRECT.md"
  G commit -qam tie
  PANE=%2 goreqd --pr 5 --paths world-runner/src/other.ts
  assert_eq 2 "$RC" "doc tie: two lanes giving world-runner/ refuse"
  assert_has "maps to two seats equally" "$OUT" "doc tie: and say it is a tie"
  assert_eq 0 "$(sent_count)" "doc tie: nothing sent"
}

test_go_owners_from_doc_shared_asks_every_lane() {
  doc_repo ownfix-073237f16.md
  local c; c=$(G rev-parse HEAD)
  local all; all=$(tr ' ' '\n' <<<"$DOC_SEATS" | sort | tr '\n' ' ' | sed 's/ $//')
  PANE=%2 goreqd --pr 5 --paths CONTRACTS.md --id gsh1
  assert_eq 0 "$RC" "shared: a shared-ground path is asked"
  assert_eq "$all" "$(audience)" "shared: every lane seat the line names is asked, docs:api (no path of its own) included"
  assert_eq 18 "$(sent_count)" "shared: one message per lane seat"
  assert_has "receipt path core:ui $c $(rid "$c" CONTRACTS.md) -- CONTRACTS.md" "$(cat "$FIX/msg.core:ui")" "shared: each seat's receipt is over the shared path"
  assert_has "Shared ground (CONTRACTS.md) asks every lane seat" "$(cat "$FIX/msg.core:ui")" "shared: the message says why this seat is asked"
  PANE=%2 goreqd --pr 5 --paths .husky/pre-commit --dry-run
  assert_eq "$all" "$(audience)" "shared: .husky/ asks every lane (its wording-only carve-out cannot be read from a diff)"
  PANE=%2 goreqd --pr 5 --paths package.json --dry-run
  assert_eq "$all" "$(audience)" "shared: a root config file the line lists is shared"
  PANE=%2 goreqd --pr 5 --paths app/Dockerfile --dry-run
  assert_eq 0 "$RC" "shared: a Dockerfile at the app/ root the line lists by name is shared"
  assert_eq "$all" "$(audience)" "shared: and asks every lane"
  echo 1 > "$FIX/repo/app/other.ts"; G add -A; G commit -qm appother
  PANE=%2 goreqd --pr 5 --paths app/other.ts --dry-run
  assert_eq 2 "$RC" "shared: 'the Dockerfiles at the app/ root' does not make all of app/ shared"
}

test_go_owners_from_doc_guards_and_uncovered() {
  doc_repo ownfix-073237f16.md
  PANE=%2 goreqd --pr 5 --paths handbook/README.md
  assert_eq 2 "$RC" "guard: a path a sentence names but no lane assigns refuses"
  assert_has "assigns it to no lane" "$OUT" "guard: saying why"
  assert_has "Each lane owns" "$OUT" "guard: quoting the sentence"
  PANE=%2 goreqd --pr 5 --paths design/a.ts
  assert_eq 2 "$RC" "guard: design/ is named by app:writer's themes-and-materials clause too, so it refuses"
  echo 1 > "$FIX/repo/nowhere.ts"; G add -A; G commit -qm nowhere
  PANE=%2 goreqd --pr 5 --paths nowhere.ts
  assert_eq 2 "$RC" "uncovered: an unmapped path refuses"
  assert_has "which the owners parser does not cover" "$OUT" "uncovered: the refusal says some lanes the line names are not covered, never just 'no owner'"
  assert_has "docs:api" "$(sed -n 's/.*the line names lane(s) \([^,]*\), which.*/\1/p' <<<"$OUT")" "uncovered: naming docs:api, a lane whose only path is not landed yet"
  assert_eq 0 "$(sent_count)" "guard/uncovered: nothing sent"
}

test_go_owners_from_doc_partial_paths_guard_only_their_files() {
  doc_repo ide330c-a31c445f1.md
  PANE=%2 goreqd --pr 5 --paths world-runner/src/other.ts --dry-run
  assert_eq 0 "$RC" "M2 ide330c: a lane naming a real file by a partial path no longer refuses the whole map"
  assert_eq "domain:language" "$(audience)" "M2 ide330c: an unrelated path still resolves"
  PANE=%2 goreqd --pr 5 --paths world-runner/src/ideas-app/server/main.ts
  assert_eq 2 "$RC" "M2 ide330c: the file the partial path names is guarded and refuses"
  assert_has "lane core:world names it only as \`main.ts\`" "$OUT" "M2 ide330c: naming the lane and the partial path"
  assert_has "world-runner/src/ideas-app/server/worker-main.ts" "$(cat "$OWN_FIX/ide330c-a31c445f1.md" | sed -n 's/.*(`\(ideas-app[^`]*\)`).*/world-runner\/src\/\1/p')" "ide330c: fixture: the partial path is the tail of the real file"
  PANE=%2 goreqd --pr 5 --paths world-runner/src/ideas-app/server/worker-main.ts
  assert_has "names it only as \`ideas-app/server/worker-main.ts\`" "$OUT" "M2 tail: worker-main.ts is guarded by its own partial path"
  assert_hasnt "only as \`main.ts\`" "$OUT" "M2 tail: and not by 'main.ts' (a tail is whole segments)"
}

# The kit line at a63569b6d (after 789e8f6bf: docs:visions, the .envrc rule) and its handbook table.
A63_SEATS="$DOC_SEATS docs:visions"
A63_EXTRA="VISION.md .gitignore .envrc .env.example world-runner/src/ideas-app/world.ts world-runner/src/ideas-app/worker/boot.ts design/brand-new.md handbook/agent/a.md handbook/worlds/w.md docs/packages.md ideas-storage/.idea/workspace.xml world-runner/.idea/workspace.xml"
a63_repo() { DOC_EXTRA="$A63_EXTRA" doc_repo ownfix-a63569b6d.md handbook-a63569b6d.md; live_add docs:visions; }

test_go_owners_kit_tip_shared_ground_drops_guards() {
  a63_repo
  local all p; all=$(tr ' ' '\n' <<<"$A63_SEATS" | sort | tr '\n' ' ' | sed 's/ $//')
  for p in .husky/pre-commit .gitignore .envrc .env.example; do
    PANE=%2 goreqd --pr 5 --paths "$p" --dry-run
    assert_eq 0 "$RC" "S1 a63569b6d: $p, guarded by the .envrc sentence and shared ground, resolves"
    assert_eq "$all" "$(audience)" "S1 a63569b6d: $p asks every lane (a guard on shared ground is dropped)"
  done
}

test_go_owners_kit_tip_guard_drop_by_named_seat() {
  a63_repo
  PANE=%2 goreqd --pr 5 --paths world-runner/src/ideas-app/world.ts --dry-run
  assert_eq 0 "$RC" "S2: world.ts, which the boot sentence names as domain:language's, resolves"
  assert_eq "domain:language" "$(audience)" "S2: through the ancestor world-runner/ row, a seat the sentence names"
  PANE=%2 goreqd --pr 5 --paths world-runner/src/ideas-app/worker/boot.ts --dry-run
  assert_eq "domain:language" "$(audience)" "S2: worker/boot.ts likewise"
  PANE=%2 goreqd --pr 5 --paths VISION.md --dry-run
  assert_eq "docs:visions" "$(audience)" "N1: the sentence after '. ' in docs:visions' bullet guards VISION.md, and names docs:visions, so the guard drops"
  PANE=%2 goreqd --pr 5 --paths design/brand-new.md
  assert_eq 2 "$RC" "S2: a design/ file outside the themes still refuses (the materials clause names no seat)"
  assert_has "that covers the site's build" "$OUT" "N4: the refusal quotes the sentence"
  assert_hasnt "('app:writer" "$OUT" "N4: not the lane key"
  # The guard-drop rule itself, on a FILE map: a guard that ties is dropped only for a named seat.
  printf 'w/ domain:language\nw/a.ts unread core:world,domain:language the sentence\nw/b.ts unread core:world the other sentence\n' > "$FIX/owners3"
  mkdir -p "$FIX/repo/w"; echo 0 > "$FIX/repo/w/a.ts"; echo 0 > "$FIX/repo/w/b.ts"; G add -A; G commit -qm w
  PANE=%2 bc go-request --repo "$FIX/repo" --owners "$FIX/owners3" --commits HEAD --pr 5 --paths w/a.ts --dry-run
  assert_eq "domain:language" "$(audience)" "guard drop: a guard naming the path's resolved seat (from an ancestor dir/) is dropped"
  PANE=%2 bc go-request --repo "$FIX/repo" --owners "$FIX/owners3" --commits HEAD --pr 5 --paths w/b.ts --dry-run
  assert_eq 2 "$RC" "guard drop: a guard that does not name the resolved seat refuses"
  assert_has "the other sentence" "$OUT" "guard drop: quoting its sentence"
}

test_go_owners_kit_tip_partial_paths_and_idea_dirs() {
  a63_repo
  PANE=%2 goreqd --pr 5 --paths world-runner/src/other.ts --dry-run
  assert_eq 0 "$RC" "M2 scenario A: docs/packages.md landed and a .idea/ dir committed: the map still loads"
  PANE=%2 goreqd --pr 5 --paths docs/packages.md
  assert_eq 2 "$RC" "M2 scenario A: docs/packages.md, which docs:api names only as packages.md, refuses"
  assert_has "lane docs:api names it only as \`packages.md\`" "$OUT" "M2 scenario A: naming the lane and the item"
  PANE=%2 goreqd --pr 5 --paths ideas-storage/.idea/workspace.xml
  assert_eq 2 "$RC" "M2 .idea: a .idea/ dir under another lane's tree is guarded"
  assert_has "lane domain:language names it only as \`.idea\`" "$OUT" "M2 .idea: naming the lane"
  PANE=%2 goreqd --pr 5 --paths world-runner/.idea/workspace.xml --dry-run
  assert_eq "domain:language" "$(audience)" "M2 .idea: under the naming lane's own tree the guard drops"
}

test_go_owners_kit_tip_handbook_table() {
  a63_repo
  PANE=%2 goreqd --pr 5 --paths handbook/agent/a.md --dry-run
  assert_eq "domain:agent" "$(audience)" "handbook table: handbook/agent/ is domain:agent's"
  PANE=%2 goreqd --pr 5 --paths handbook/worlds/w.md --dry-run
  assert_eq "docs:handbook" "$(audience)" "handbook table: 'docs:handbook, until a lane claims it' is docs:handbook"
  PANE=%2 goreqd --pr 5 --paths handbook/README.md --dry-run
  assert_eq 0 "$RC" "handbook table: the sentence deferring to the table no longer guards handbook/README.md"
  assert_eq "docs:handbook" "$(audience)" "handbook table: the root is the hub's"
  # A claim: the table moves handbook/agent/ to core:ui; both owners are asked for the folder and the table.
  sed -i.bak 's/^| `handbook\/agent\/` | domain:agent |/| `handbook\/agent\/` | core:ui |/' "$FIX/repo/handbook/README.md"; rm -f "$FIX/repo/handbook/README.md.bak"
  echo 2 >> "$FIX/repo/handbook/agent/a.md"; G commit -qam claim
  PANE=%2 goreqd --pr 5 --paths handbook/agent/a.md --id ghb1
  assert_eq 0 "$RC" "handbook claim: a request over the claimed folder is sent"
  assert_eq "core:ui domain:agent" "$(audience)" "handbook claim: the folder's owner at the tip and at the base are asked"
  msg_has domain:agent handbook/agent/a.md && pass "handbook claim: the losing owner gets the folder's receipt" || fail "handbook claim: the losing owner gets the folder's receipt" "receipt over handbook/agent/a.md" "$(cat "$FIX/msg.domain:agent")"
  msg_has domain:agent handbook/README.md && pass "handbook claim: and the table's" || fail "handbook claim: and the table's" "receipt over handbook/README.md" "$(cat "$FIX/msg.domain:agent")"
  # A cell that is not a seat refuses, naming it.
  printf '## Who owns each folder\n\n| Folder | Owner |\n| --- | --- |\n| `handbook/agent/` | Agent lane |\n' > "$FIX/repo/handbook/README.md"; G commit -qam badcell
  PANE=%2 goreqd --pr 5 --paths handbook/agent/a.md
  assert_eq 2 "$RC" "handbook table: an owner cell that is not a fleet seat refuses"
  assert_has '"Agent lane"' "$OUT" "handbook table: naming the cell"
}

test_go_owners_kit_tip_uncovered_lanes_in_every_request() {
  a63_repo
  PANE=%2 goreqd --pr 5 --paths world-runner/src/other.ts --id gunc
  assert_eq 0 "$RC" "S3: a request whose path resolves"
  assert_has "docs:api (the generated package map" "$(cat "$FIX/msg.domain:language")" "S3: still names the uncovered lane and what the line gives it"
  assert_has "forward this request" "$(cat "$FIX/msg.domain:language")" "S3: so the asked seat can forward it"
}

# M1: the critic's scenario B2. A PR moves resource-kernel to domain:agent in the line (+1/-2).
test_go_owners_union_of_base_and_tip() {
  DOC_EXTRA="resource-kernel/src/x.ts" doc_repo ownfix-073237f16.md
  local d="$FIX/repo/docs/LIVE_MARKET_DIRECT.md" all
  all=$(tr ' ' '\n' <<<"$DOC_SEATS" | sort | tr '\n' ' ' | sed 's/ $//')
  sed -i.bak 's/^  - core:kernel: resource-kernel;/  - domain:agent: resource-kernel, `docs\/LIVE_MARKET_DIRECT.md`;/; /^    - core:kernel: /d' "$d"; rm -f "$d.bak"
  echo 2 >> "$FIX/repo/resource-kernel/src/x.ts"; G commit -qam hijack
  PANE=%2 goreqd --pr 5 --paths resource-kernel/src/x.ts --id gb2
  assert_eq 0 "$RC" "M1 B2: the request is sent"
  msg_has core:kernel resource-kernel/src/x.ts && pass "M1 B2: core:kernel, the base owner, is asked for the path the PR moves away from it" || fail "M1 B2: core:kernel, the base owner, is asked for the path the PR moves away from it" "receipt over resource-kernel/src/x.ts" "$(cat "$FIX/msg.core:kernel" 2>/dev/null)"
  msg_has domain:agent resource-kernel/src/x.ts && pass "M1 B2: and domain:agent, the tip owner" || fail "M1 B2: and domain:agent, the tip owner" "receipt" "$(cat "$FIX/msg.domain:agent" 2>/dev/null)"
  assert_eq "$all" "$(tr ' ' '\n' <<<"$(audience)" | sort | tr '\n' ' ' | sed 's/ $//')" "M1 B2: the range edits the Ownership line, so every lane of base ∪ tip is asked"
  msg_has core:ui docs/LIVE_MARKET_DIRECT.md && pass "M1 B2: each lane's receipt is over the doc" || fail "M1 B2: each lane's receipt is over the doc" "receipt over the doc" "$(cat "$FIX/msg.core:ui")"
  assert_has 'edits the "Ownership is fixed" line' "$(cat "$FIX/msg.core:ui")" "M1 B2: the message says why"
  assert_has "at the base" "$(cat "$FIX/msg.core:ui")" "M1 B2: and that both sides were read"
}

test_go_owners_base_side_refusal_and_fallbacks() {
  DOC_EXTRA="newpkg/x.ts" doc_repo ownfix-073237f16.md
  local d="$FIX/repo/docs/LIVE_MARKET_DIRECT.md"
  # A tie at the base, fixed at the tip: still refused, naming the base.
  awk '{ print } /^  - core:exchange: / { print "  - domain:stats: world-runner." }' "$OWN_FIX/ownfix-073237f16.md" > "$d"; G commit -qam tie; G tag tbase
  cp "$OWN_FIX/ownfix-073237f16.md" "$d"; echo 3 >> "$FIX/repo/world-runner/src/other.ts"; G commit -qam fix
  PANE=%2 bc go-request --repo "$FIX/repo" --commits tbase..HEAD --pr 5 --paths world-runner/src/other.ts
  assert_eq 2 "$RC" "M1: a tie on the base side refuses"
  assert_has "maps to two seats equally in docs/LIVE_MARKET_DIRECT.md at the base" "$OUT" "M1: naming the base"
  # A new package the PR gives a lane: no seat at the base, so the tip's owner is asked.
  awk '{ print } /^  - core:exchange: / { print "  - domain:stats: `newpkg/`." }' "$OWN_FIX/ownfix-073237f16.md" > "$d"; echo 4 >> "$FIX/repo/newpkg/x.ts"; G commit -qam newpkg; G tag nbase
  PANE=%2 bc go-request --repo "$FIX/repo" --commits nbase~1..nbase --pr 5 --paths newpkg/x.ts --id gnp
  assert_eq 0 "$RC" "M1: a path with no seat at the base is asked of its tip owner"
  msg_has domain:stats newpkg/x.ts && pass "M1: domain:stats gets newpkg/x.ts" || fail "M1: domain:stats gets newpkg/x.ts" "receipt" "$(cat "$FIX/msg.domain:stats" 2>/dev/null)"
  # A base with no Ownership line: the tip alone, said in the message.
  PANE=%2 bc go-request --repo "$FIX/repo" --commits base..dbase --pr 5 --paths world-runner/src/other.ts --dry-run
  assert_eq 0 "$RC" "M1: a base with no doc reads the tip alone"
  assert_has "so the owners are the tip's alone" "$OUT" "M1: and says so"
}

test_go_owners_missing_doc_or_line_refused() {
  go_repo
  PANE=%2 bc go-request --repo "$FIX/repo" --commits base..HEAD --pr 5 --rows alpha
  assert_eq 2 "$RC" "missing: no doc at the tip refuses"
  assert_has "no docs/LIVE_MARKET_DIRECT.md at the tip" "$OUT" "missing: naming the doc"
  mkdir -p "$FIX/repo/docs"; printf '# Live market\n\n- **Something else.**\n' > "$FIX/repo/docs/LIVE_MARKET_DIRECT.md"; G add -A; G commit -qm nolines
  PANE=%2 bc go-request --repo "$FIX/repo" --commits base..HEAD --pr 5 --rows alpha
  assert_eq 2 "$RC" "missing: a doc with no Ownership line refuses"
  assert_has "Ownership is fixed" "$OUT" "missing: naming the line"
  OWNERS_ENV="$FIX/owners" PANE=%2 bc go-request --repo "$FIX/repo" --commits base..HEAD --pr 5 --rows alpha --dry-run
  assert_eq 0 "$RC" "override: BROADCAST_OWNERS still replaces the doc"
  assert_eq "app:ask" "$(audience)" "override: with its own seats"
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
