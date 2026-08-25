#!/bin/bash
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# One root-level issues response (data.issues.nodes[…]) — two tickets; FIN-100 carries a
# comment tree (root c1 + reply, + a pre-since c0 that the transform must filter) and a 👀
# reaction from an externalUser; FIN-200 is bare.
write_fixtures() {
  cat > "$FXDIR/two.json" <<'JSON'
{"data":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"id":"i1","identifier":"FIN-100","title":"First","url":"u1","createdAt":"2026-07-25T00:00:00Z","updatedAt":"2026-07-29T00:00:00Z","priority":2,"state":{"name":"Todo"},"projectMilestone":null,
   "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
     {"id":"c1","body":"root","createdAt":"2026-07-28T00:00:00Z","quotedText":null,"resolvedAt":"2026-07-28T06:00:00Z","resolvingUser":{"name":"Rob"},"parent":null,"user":{"name":"Yarik"},"botActor":null,"reactions":[{"emoji":"👀","createdAt":"2026-07-28T00:05:00Z","user":null,"externalUser":{"name":"Codex"}}]},
     {"id":"c2","body":"reply","createdAt":"2026-07-28T01:00:00Z","quotedText":null,"parent":{"id":"c1"},"user":{"name":"Alice"},"botActor":null,"reactions":[]},
     {"id":"c0","body":"OLD","createdAt":"2026-07-10T00:00:00Z","quotedText":null,"parent":null,"user":{"name":"Old"},"botActor":null,"reactions":[]}
   ]},
   "history":{"pageInfo":{"hasNextPage":false},"nodes":[
     {"createdAt":"2026-07-28T03:00:00Z","actor":{"name":"Yarik"},"fromState":{"name":"Backlog"},"toState":{"name":"Done"},"fromPriority":null,"toPriority":null,"fromAssignee":null,"toAssignee":null,"fromProjectMilestone":null,"toProjectMilestone":null}
   ]},
   "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[{"id":"a1","title":"call.mp3","url":"https://files/call"}]}},
  {"id":"i2","identifier":"FIN-200","title":"Second","url":"u2","createdAt":"2026-07-26T00:00:00Z","updatedAt":"2026-07-26T00:00:00Z","priority":3,"state":{"name":"Backlog"},"projectMilestone":null,
   "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},
   "history":{"pageInfo":{"hasNextPage":false},"nodes":[]},
   "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
]}}}
JSON

  cat > "$FXDIR/errors.json" <<'JSON'
{"errors":[{"message":"Authentication required"}]}
JSON

  # Two single-team responses for the multi-team grouping path (one fetch per team, merged).
  cat > "$FXDIR/team-fin.json" <<'JSON'
{"data":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"id":"f1","identifier":"FIN-100","title":"Fin","url":"u","createdAt":"2026-07-25T00:00:00Z","updatedAt":"2026-07-29T00:00:00Z","priority":1,"state":{"name":"Todo"},"projectMilestone":null,
   "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},"history":{"pageInfo":{"hasNextPage":false},"nodes":[]},"attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
]}}}
JSON
  cat > "$FXDIR/team-eng.json" <<'JSON'
{"data":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"id":"e1","identifier":"ENG-9","title":"Eng","url":"u","createdAt":"2026-07-25T00:00:00Z","updatedAt":"2026-07-29T00:00:00Z","priority":1,"state":{"name":"Todo"},"projectMilestone":null,
   "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},"history":{"pageInfo":{"hasNextPage":false},"nodes":[]},"attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
]}}}
JSON
}

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux
  ln -sf "$SRC_DIR/ticket.sh" "$FAKE_HOME/.claude/scripts/ticket.sh"
  ln -sf "$SRC_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
  ln -sf "$SRC_DIR/linear-lib.sh" "$FAKE_HOME/.claude/scripts/linear-lib.sh"
  ln -sf "$SRC_DIR/session.sh" "$FAKE_HOME/.claude/scripts/session.sh"
  TICKET="$FAKE_HOME/.claude/scripts/ticket.sh"
  export TICKET_FETCH_STATE_DIR="$TMP_DIR/state"
  FXDIR="$TMP_DIR/fx"; mkdir -p "$FXDIR"
  write_fixtures
  unset LINEAR_API_KEY 2>/dev/null || true
  unset LINEAR_FIXTURE PROJECT_FETCH_FIXTURE 2>/dev/null || true
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# Run `ticket fetch` with a fixture and capture the payload path (last stdout line).
_fetch_out() {
  local fixture="$1"; shift
  local out="$TMP_DIR/payload.json"
  LINEAR_FIXTURE="$fixture" "$TICKET" fetch "$@" --out="$out" >/dev/null 2>&1
  printf '%s' "$out"
}

# ---- Cases ----

test_ticket_fetch_multi_key_envelope() {
  local out; out=$(_fetch_out "$FXDIR/two.json" FIN-100 FIN-200 --since="2026-07-20T00:00:00Z")
  assert_file_exists "$out" "payload written"
  assert_json "$out" '.tickets | length' "2" "both requested tickets in payload"
  assert_json "$out" '.keys | join(",")' "FIN-100,FIN-200" "keys echoed in envelope"
  assert_json "$out" '.summary.requested' "2" "requested count recorded"
  assert_json "$out" '(has("since") and has("fetchedAt") and has("tickets"))' "true" "envelope keys present"
  # thin envelope — NO project/structure/channels (that's project fetch only)
  assert_json "$out" 'has("structure")' "false" "no project envelope on ticket fetch"
}

test_ticket_fetch_comment_tree_and_since() {
  local out; out=$(_fetch_out "$FXDIR/two.json" FIN-100 FIN-200 --since="2026-07-20T00:00:00Z")
  # c1 root + nested c2 reply; c0 (pre-since) filtered by the transform.
  assert_json "$out" '.tickets[0].comments | length' "1" "one root comment (c0 pre-since filtered)"
  assert_json "$out" '.tickets[0].comments[0].children[0].id' "c2" "reply nested under root"
  assert_json "$out" '.tickets[0].lifecycle[0].to' "Done" "lifecycle normalized (Backlog→Done)"
  assert_json "$out" '.tickets[0].attachments[0].url' "https://files/call" "attachment surfaced"
}

test_ticket_fetch_reactions() {
  local out; out=$(_fetch_out "$FXDIR/two.json" FIN-100 --since="2026-07-20T00:00:00Z")
  assert_json "$out" '.tickets[0].comments[0].reactions[0].emoji' "👀" "reaction emoji surfaced"
  assert_json "$out" '.tickets[0].comments[0].reactions[0].by' "Codex" "reaction actor falls back to externalUser"
  assert_json "$out" '.tickets[0].comments[0].children[0].reactions | length' "0" "no reactions → empty array"
}

test_ticket_fetch_full_read_no_since() {
  # No --since = cold read: the pre-since c0 is NOT filtered (empty cutoff passes all).
  local out; out=$(_fetch_out "$FXDIR/two.json" FIN-100)
  assert_json "$out" '.since' "" "empty since recorded"
  assert_json "$out" '.tickets[0].comments | length' "2" "full read keeps the old comment (c0 + c1 roots)"
}

test_ticket_fetch_prints_path() {
  local out
  out=$(LINEAR_FIXTURE="$FXDIR/two.json" "$TICKET" fetch FIN-100 2>/dev/null | tail -1)
  assert_contains ".json" "$out" "prints a payload path"
  assert_file_exists "$out" "printed path exists (payload → file, not stdout)"
}

test_ticket_fetch_fail_closed_on_graphql_error() {
  local out="$TMP_DIR/err.json" rc
  LINEAR_FIXTURE="$FXDIR/errors.json" "$TICKET" fetch FIN-100 --out="$out" >/dev/null 2>&1; rc=$?
  assert_neq "0" "$rc" "GraphQL error → non-zero exit"
  assert_file_not_exists "$out" "no payload written on error (¶INV_WRITE_BEFORE_WATERMARK)"
}

test_ticket_fetch_rejects_bad_key() {
  local rc
  LINEAR_FIXTURE="$FXDIR/two.json" "$TICKET" fetch "not a key" >/dev/null 2>&1; rc=$?
  assert_neq "0" "$rc" "invalid key rejected"
  "$TICKET" fetch >/dev/null 2>&1; rc=$?
  assert_neq "0" "$rc" "no keys → non-zero"
}

test_ticket_fetch_comment_resolution() {
  # ticket.sh carried its own copy of the comment selection and now renders the shared
  # @COMMENT_FIELDS@ token, so this asserts the token actually resolved on THIS path too — an
  # unsubstituted token would drop the field silently from the caller's point of view.
  local out="$TMP_DIR/res.json"
  LINEAR_FIXTURE="$FXDIR/two.json" "$TICKET" fetch FIN-100 --out="$out" >/dev/null 2>&1
  assert_file_exists "$out" "payload written"
  assert_json "$out" '[.tickets[0].comments | .. | objects | select(.id=="c1")][0].resolvedAt' "2026-07-28T06:00:00Z" "resolved root carries resolvedAt"
  assert_json "$out" '[.tickets[0].comments | .. | objects | select(.id=="c1")][0].resolvedBy' "Rob" "resolved root carries the resolver name"
  assert_json "$out" '[.tickets[0].comments | .. | objects | select(.id=="c2")][0].resolvedAt' "null" "unresolved reply → resolvedAt null"
  assert_json "$out" '[.tickets[].comments | .. | objects | select(has("body"))] | all(has("resolvedAt"))' "true" "every comment carries a resolvedAt key"
}

test_ticket_fetch_multi_team_grouping() {
  # Keys spanning two teams → one fetch per team (fixture list served in order), results merged.
  # Guards the bug where a compound {team,number} inside an `or` returned the whole workspace.
  local out="$TMP_DIR/mt.json"
  LINEAR_FIXTURE="$FXDIR/team-fin.json:$FXDIR/team-eng.json" "$TICKET" fetch FIN-100 ENG-9 --out="$out" >/dev/null 2>&1
  assert_file_exists "$out" "multi-team payload written"
  assert_json "$out" '[.tickets[].identifier] | sort | join(",")' "ENG-9,FIN-100" "both teams merged into one payload"
  assert_json "$out" '.keys | length' "2" "both keys echoed"
}

run_discovered_tests
