#!/bin/bash
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UUID="11111111-1111-1111-1111-111111111111"
SINCE="2026-07-20T00:00:00Z"

# Synthetic Linear GraphQL responses covering every payload shape.
write_fixtures() {
  # Main issues response: one Inboxes channel (comment tree + Backlog→Done + attachment +
  # bot comment + a pre-since comment/history that must be filtered) and one new ordinary issue.
  cat > "$FXDIR/main.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"Product: Intake System","url":"https://linear.app/x/project/p",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"},{"id":"m2","name":"Ready for action"}]},
  "channels":{"nodes":[{"id":"i1","identifier":"FIN-3447","title":"Feature requirements","projectMilestone":{"name":"Inboxes"}}]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-3447","title":"Feature requirements","url":"u1",
     "createdAt":"2026-07-01T00:00:00Z","updatedAt":"2026-07-29T01:00:00Z","priority":2,
     "state":{"name":"Backlog"},"projectMilestone":{"name":"Inboxes"},
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
       {"id":"c1","body":"root","createdAt":"2026-07-28T00:00:00Z","quotedText":null,"parent":null,"user":{"name":"Yarik"},"botActor":null},
       {"id":"c2","body":"reply","createdAt":"2026-07-28T01:00:00Z","quotedText":null,"parent":{"id":"c1"},"user":{"name":"Alice"},"botActor":null},
       {"id":"c3","body":"nested","createdAt":"2026-07-28T02:00:00Z","quotedText":null,"parent":{"id":"c2"},"user":null,"botActor":{"name":"Zapier"}},
       {"id":"c0","body":"OLD","createdAt":"2026-07-10T00:00:00Z","quotedText":null,"parent":null,"user":{"name":"Old"},"botActor":null}
     ]},
     "history":{"pageInfo":{"hasNextPage":false},"nodes":[
       {"createdAt":"2026-07-28T03:00:00Z","actor":{"name":"Yarik"},"fromState":{"name":"Backlog"},"toState":{"name":"Done"},"fromPriority":null,"toPriority":null,"fromAssignee":null,"toAssignee":null,"fromProjectMilestone":null,"toProjectMilestone":null},
       {"createdAt":"2026-07-10T00:00:00Z","actor":{"name":"Old"},"fromState":{"name":"Todo"},"toState":{"name":"Backlog"},"fromPriority":null,"toPriority":null,"fromAssignee":null,"toAssignee":null,"fromProjectMilestone":null,"toProjectMilestone":null}
     ]},
     "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[{"id":"a1","title":"call.mp3","url":"https://files/call"}]}
    },
    {"id":"i2","identifier":"FIN-3500","title":"New ticket","url":"u2",
     "createdAt":"2026-07-25T00:00:00Z","updatedAt":"2026-07-25T00:00:00Z","priority":3,
     "state":{"name":"Todo"},"projectMilestone":null,
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},
     "history":{"pageInfo":{"hasNextPage":false},"nodes":[
       {"createdAt":"2026-07-26T00:00:00Z","actor":{"name":"Bob"},"fromState":null,"toState":null,"fromPriority":4,"toPriority":3,"fromAssignee":null,"toAssignee":null,"fromProjectMilestone":null,"toProjectMilestone":null}
     ]},
     "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}
    }
  ]}
}}}
JSON

  cat > "$FXDIR/errors.json" <<'JSON'
{"errors":[{"message":"Authentication required"}]}
JSON

  cat > "$FXDIR/empty.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"Empty","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"}]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}
}}}
JSON

  # Outer pagination: page1 hasNextPage:true, page2 hasNextPage:false.
  cat > "$FXDIR/page1.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"P","url":"u",
  "projectMilestones":{"nodes":[]},
  "issues":{"pageInfo":{"hasNextPage":true,"endCursor":"CUR1"},"nodes":[
    {"id":"i1","identifier":"FIN-1","title":"one","url":"u1","createdAt":"2026-07-25T00:00:00Z","updatedAt":"2026-07-25T00:00:00Z","priority":0,"state":{"name":"Todo"},"projectMilestone":null,
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},
     "history":{"pageInfo":{"hasNextPage":false},"nodes":[]},
     "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
  ]}
}}}
JSON
  cat > "$FXDIR/page2.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"P","url":"u",
  "projectMilestones":{"nodes":[]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i2","identifier":"FIN-2","title":"two","url":"u2","createdAt":"2026-07-26T00:00:00Z","updatedAt":"2026-07-26T00:00:00Z","priority":0,"state":{"name":"Todo"},"projectMilestone":null,
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},
     "history":{"pageInfo":{"hasNextPage":false},"nodes":[]},
     "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
  ]}
}}}
JSON

  cat > "$FXDIR/projects-one.json" <<'JSON'
{"data":{"projects":{"nodes":[{"id":"11111111-1111-1111-1111-111111111111","name":"Product: Intake System","url":"u"}]}}}
JSON
  cat > "$FXDIR/projects-ambiguous.json" <<'JSON'
{"data":{"projects":{"nodes":[
  {"id":"11111111-1111-1111-1111-111111111111","name":"Dup","url":"u1"},
  {"id":"22222222-2222-2222-2222-222222222222","name":"Dup","url":"u2"}
]}}}
JSON

  # F1 regression: a NEW reply (post-since) to a PRE-since parent — must NOT be dropped.
  cat > "$FXDIR/orphan.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"O","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"}]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-9","title":"thread","url":"u","createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-07-28T00:00:00Z","priority":0,"state":{"name":"Backlog"},"projectMilestone":{"name":"Inboxes"},
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
       {"id":"cP","body":"old parent","createdAt":"2026-07-10T00:00:00Z","parent":null,"user":{"name":"Old"},"botActor":null},
       {"id":"cNEW","body":"new reply to old thread","createdAt":"2026-07-28T00:00:00Z","parent":{"id":"cP"},"user":{"name":"Ann"},"botActor":null}
     ]},
     "history":{"pageInfo":{"hasNextPage":false},"nodes":[]},
     "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
  ]}
}}}
JSON

  # F2 regression: one history entry changing state AND assignee → both events, not just the first.
  cat > "$FXDIR/multifield.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"M","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"}]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-8","title":"multi","url":"u","createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-07-28T00:00:00Z","priority":0,"state":{"name":"Done"},"projectMilestone":{"name":"Inboxes"},
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},
     "history":{"pageInfo":{"hasNextPage":false},"nodes":[
       {"createdAt":"2026-07-28T00:00:00Z","actor":{"name":"Yarik"},"fromState":{"name":"Backlog"},"toState":{"name":"Done"},"fromPriority":null,"toPriority":null,"fromAssignee":{"name":"Alice"},"toAssignee":{"name":"Bob"},"fromProjectMilestone":null,"toProjectMilestone":null}
     ]},
     "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
  ]}
}}}
JSON

  # Council #9 regression: hasNextPage:true with a non-advancing (null) endCursor → abort, not loop.
  cat > "$FXDIR/cursor-stuck.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"C","url":"u",
  "projectMilestones":{"nodes":[]},
  "issues":{"pageInfo":{"hasNextPage":true,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-C","title":"c","url":"u","createdAt":"2026-07-25T00:00:00Z","updatedAt":"2026-07-25T00:00:00Z","priority":0,"state":{"name":"Todo"},"projectMilestone":null,
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},"history":{"pageInfo":{"hasNextPage":false},"nodes":[]},"attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
  ]}
}}}
JSON

  cat > "$FXDIR/precision.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"P","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"}]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-7","title":"prec","url":"u","createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-07-20T00:00:01.000Z","priority":0,"state":{"name":"Todo"},"projectMilestone":{"name":"Inboxes"},
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
       {"id":"cBefore","body":"just before","createdAt":"2026-07-19T23:59:59.999Z","parent":null,"user":{"name":"A"},"botActor":null},
       {"id":"cAfter","body":"just after","createdAt":"2026-07-20T00:00:00.500Z","parent":null,"user":{"name":"B"},"botActor":null}
     ]},
     "history":{"pageInfo":{"hasNextPage":false},"nodes":[]},
     "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
  ]}
}}}
JSON

  # Overflow fixtures: an issue whose first child page is truncated (hasNextPage:true) →
  # the per-issue follow-up query (shape {"data":{"issue":{<conn>:...}}}) returns the rest.
  # comments-overflow: c1 first page + c2 follow-up.
  cat > "$FXDIR/co-main.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"CO","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"}]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-CO","title":"co","url":"u","createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-07-28T00:00:00Z","priority":0,"state":{"name":"Backlog"},"projectMilestone":{"name":"Inboxes"},
     "comments":{"pageInfo":{"hasNextPage":true,"endCursor":"CC1"},"nodes":[
       {"id":"c1","body":"first page","createdAt":"2026-07-28T00:00:00Z","parent":null,"user":{"name":"A"},"botActor":null}
     ]},
     "history":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},
     "attachments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}
  ]}
}}}
JSON
  cat > "$FXDIR/co-page2.json" <<'JSON'
{"data":{"issue":{"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"id":"c2","body":"second page","createdAt":"2026-07-28T01:00:00Z","parent":null,"user":{"name":"B"},"botActor":null}
]}}}}
JSON

  # history-overflow: h1 (state) first page + h2 (priority) follow-up.
  cat > "$FXDIR/ho-main.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"HO","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"}]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-HO","title":"ho","url":"u","createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-07-28T00:00:00Z","priority":0,"state":{"name":"Done"},"projectMilestone":{"name":"Inboxes"},
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},
     "history":{"pageInfo":{"hasNextPage":true,"endCursor":"HC1"},"nodes":[
       {"createdAt":"2026-07-28T00:00:00Z","actor":{"name":"Y"},"fromState":{"name":"Backlog"},"toState":{"name":"Done"},"fromPriority":null,"toPriority":null,"fromAssignee":null,"toAssignee":null,"fromProjectMilestone":null,"toProjectMilestone":null}
     ]},
     "attachments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}
  ]}
}}}
JSON
  cat > "$FXDIR/ho-page2.json" <<'JSON'
{"data":{"issue":{"history":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"createdAt":"2026-07-28T02:00:00Z","actor":{"name":"Y"},"fromState":null,"toState":null,"fromPriority":4,"toPriority":3,"fromAssignee":null,"toAssignee":null,"fromProjectMilestone":null,"toProjectMilestone":null}
]}}}}
JSON

  # attachments-overflow: a1 first page + a2 follow-up.
  cat > "$FXDIR/ao-main.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"AO","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"}]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-AO","title":"ao","url":"u","createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-07-28T00:00:00Z","priority":0,"state":{"name":"Backlog"},"projectMilestone":{"name":"Inboxes"},
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},
     "history":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},
     "attachments":{"pageInfo":{"hasNextPage":true,"endCursor":"AC1"},"nodes":[{"id":"a1","title":"one","url":"https://f/1"}]}}
  ]}
}}}
JSON
  cat > "$FXDIR/ao-page2.json" <<'JSON'
{"data":{"issue":{"attachments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"id":"a2","title":"two","url":"https://f/2"}
]}}}}
JSON

  # A2 (finding #5): a quiet channel — present in the aliased `channels` catalog but with
  # NO delta activity (its updatedAt < since, so it's absent from the delta `issues` nodes).
  # It must STILL enumerate in structure.channels (channels are independent of the delta).
  cat > "$FXDIR/channels-quiet.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"Quiet","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"}]},
  "channels":{"nodes":[
    {"id":"ch1","identifier":"FIN-QUIET","title":"Observed problems","projectMilestone":{"name":"Inboxes"}}
  ]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}
}}}
JSON

  # A3 (finding #6): one anchored comment (quotedText set) + one thread comment (quotedText null)
  # → both surface, distinguishable by quotedText, so /intake can skip anchored annotations.
  cat > "$FXDIR/quoted.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"QT","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Inboxes"}]},
  "channels":{"nodes":[{"id":"i1","identifier":"FIN-QT","title":"c","projectMilestone":{"name":"Inboxes"}}]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-QT","title":"qt","url":"u","createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-07-28T00:00:00Z","priority":0,"state":{"name":"Backlog"},"projectMilestone":{"name":"Inboxes"},
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
       {"id":"cAnchor","body":"anchored note","createdAt":"2026-07-28T00:00:00Z","quotedText":"the quoted description text","parent":null,"user":{"name":"A"},"botActor":null},
       {"id":"cThread","body":"thread comment","createdAt":"2026-07-28T01:00:00Z","quotedText":null,"parent":null,"user":{"name":"B"},"botActor":null}
     ]},
     "history":{"pageInfo":{"hasNextPage":false},"nodes":[]},
     "attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
  ]}
}}}
JSON

  # A4 (C5-flag): a project whose milestones do NOT include the inbox milestone → channelsResolved:false.
  cat > "$FXDIR/no-inbox.json" <<'JSON'
{"data":{"project":{
  "id":"11111111-1111-1111-1111-111111111111","name":"NI","url":"u",
  "projectMilestones":{"nodes":[{"id":"m1","name":"Ready for action"}]},
  "channels":{"nodes":[]},
  "issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"i1","identifier":"FIN-NI","title":"ni","url":"u","createdAt":"2026-07-25T00:00:00Z","updatedAt":"2026-07-25T00:00:00Z","priority":0,"state":{"name":"Todo"},"projectMilestone":null,
     "comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]},"history":{"pageInfo":{"hasNextPage":false},"nodes":[]},"attachments":{"pageInfo":{"hasNextPage":false},"nodes":[]}}
  ]}
}}}
JSON
}

setup() {
  TMP_DIR=$(mktemp -d)
  setup_fake_home "$TMP_DIR"
  disable_fleet_tmux
  ln -sf "$SRC_DIR/project.sh" "$FAKE_HOME/.claude/scripts/project.sh"
  ln -sf "$SRC_DIR/lib.sh" "$FAKE_HOME/.claude/scripts/lib.sh"
  PROJ="$FAKE_HOME/.claude/scripts/project.sh"
  export PROJECT_FETCH_STATE_DIR="$TMP_DIR/state"
  FXDIR="$TMP_DIR/fx"; mkdir -p "$FXDIR"
  write_fixtures
  unset LINEAR_API_KEY 2>/dev/null || true
  unset PROJECT_FETCH_FIXTURE 2>/dev/null || true
}

teardown() {
  teardown_fake_home
  rm -rf "$TMP_DIR"
}

# Run fetch with a fixture (or fixture list) and capture the payload path (last stdout line).
_fetch_out() {
  local fixture="$1"; shift
  local out="$TMP_DIR/payload.json"
  PROJECT_FETCH_FIXTURE="$fixture" "$PROJ" fetch "$@" --out="$out" >/dev/null 2>&1
  printf '%s' "$out"
}

# ---- Cases ----

test_project_usage_and_bad_subcommand() {
  local out rc
  out=$("$PROJ" 2>&1); assert_contains "project fetch" "$out" "usage lists fetch"
  "$PROJ" bogus >/dev/null 2>&1; rc=$?
  assert_neq "0" "$rc" "unknown subcommand exits non-zero"
}

test_project_envelope_shape() {
  local out; out=$(_fetch_out "$FXDIR/main.json" "$UUID" --since="$SINCE")
  assert_file_exists "$out" "payload written"
  assert_json "$out" '.project.name' "Product: Intake System" "project name present"
  assert_json "$out" '.tickets | length' "2" "two tickets"
  assert_json "$out" '(has("structure") and has("summary") and has("since") and has("fetchedAt"))' "true" "envelope keys present"
}

test_project_comment_trees() {
  local out; out=$(_fetch_out "$FXDIR/main.json" "$UUID" --since="$SINCE")
  # root has one child (c2), which has one child (c3) — nested, not loose rows
  assert_json "$out" '.tickets[0].comments | length' "1" "one root comment (replies nested)"
  assert_json "$out" '.tickets[0].comments[0].children[0].id' "c2" "reply nested under root"
  assert_json "$out" '.tickets[0].comments[0].children[0].children[0].id' "c3" "depth-2 reply nested"
}

test_project_lifecycle_normalization() {
  local out; out=$(_fetch_out "$FXDIR/main.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[0].lifecycle | length' "1" "one lifecycle event (pre-since filtered)"
  assert_json "$out" '.tickets[0].lifecycle[0].type' "state" "state transition typed"
  assert_json "$out" '.tickets[0].lifecycle[0].from' "Backlog" "from state"
  assert_json "$out" '.tickets[0].lifecycle[0].to' "Done" "to state (Backlog→Done legible)"
  assert_json "$out" '.tickets[0].lifecycle[0].actor' "Yarik" "actor captured (by whom)"
  assert_json "$out" '.tickets[1].lifecycle[0].type' "priority" "priority transition typed"
}

test_project_since_filters_comments() {
  local out; out=$(_fetch_out "$FXDIR/main.json" "$UUID" --since="$SINCE")
  # c0 (2026-07-10, pre-since) excluded → tree count 3 across the channel
  assert_json "$out" '.summary.activity[] | select(.identifier=="FIN-3447") | .comments' "3" "pre-since comment filtered from tree"
}

test_project_attachments() {
  local out; out=$(_fetch_out "$FXDIR/main.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[0].attachments[0].url' "https://files/call" "attachment url surfaced"
  assert_json "$out" '.tickets[1].attachments | length' "0" "no attachments → empty array (no crash)"
}

test_project_structure_catalog() {
  local out; out=$(_fetch_out "$FXDIR/main.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.structure.channels | length' "1" "one Inboxes channel"
  assert_json "$out" '.structure.channels[0].identifier' "FIN-3447" "channel is the Inboxes issue"
  assert_json "$out" '.tickets[0].isChannel' "true" "channel ticket flagged"
  assert_json "$out" '.tickets[1].isChannel' "false" "non-Inboxes ticket not a channel"
}

test_project_new_ticket_flag() {
  local out; out=$(_fetch_out "$FXDIR/main.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[1].isNew' "true" "created-after-since ticket flagged new"
  assert_json "$out" '.tickets[0].isNew' "false" "old ticket not new"
  assert_json "$out" '.summary.newTicketCount' "1" "summary new count"
}

test_project_pagination_merges_pages() {
  local out; out=$(_fetch_out "$FXDIR/page1.json:$FXDIR/page2.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets | length' "2" "both pages merged into one payload"
  assert_json "$out" '[.tickets[].identifier] | sort | join(",")' "FIN-1,FIN-2" "issues from both pages present"
}

test_project_no_waterline_subcommand() {
  # The stored waterline is removed — `waterline` is no longer a subcommand (errors like any bogus one).
  local out rc
  out=$("$PROJ" waterline get "$UUID" 2>&1); rc=$?
  assert_neq "0" "$rc" "waterline subcommand now exits non-zero"
  assert_contains "unknown subcommand" "$out" "waterline reported as unknown subcommand"
}

test_project_fail_closed_on_graphql_error() {
  local out="$TMP_DIR/err-out.json" rc
  PROJECT_FETCH_FIXTURE="$FXDIR/errors.json" "$PROJ" fetch "$UUID" --out="$out" >/dev/null 2>&1; rc=$?
  assert_neq "0" "$rc" "graphql error → non-zero exit"
  assert_file_not_exists "$out" "no payload written on error"
}

test_project_fail_closed_on_missing_key() {
  local out="$TMP_DIR/nokey-out.json" rc
  unset LINEAR_API_KEY
  # no fixture → live path; no key + no .env → fail before any network call
  "$PROJ" fetch "$UUID" --out="$out" >/dev/null 2>&1; rc=$?
  assert_neq "0" "$rc" "missing key → non-zero exit"
  assert_file_not_exists "$out" "no payload without key"
}

test_project_since_sets_window() {
  # --since is the sole window source (no stored waterline). An early --since widens the
  # window so the old comment c0 (2026-07-10) is included → tree count 4.
  local out="$TMP_DIR/ov.json"
  PROJECT_FETCH_FIXTURE="$FXDIR/main.json" "$PROJ" fetch "$UUID" --since="2026-01-01T00:00:00Z" --out="$out" >/dev/null 2>&1
  assert_json "$out" '.since' "2026-01-01T00:00:00Z" "payload records the since window"
  assert_json "$out" '.summary.activity[] | select(.identifier=="FIN-3447") | .comments' "4" "early since widens window → old comment included"
}

test_project_empty_delta() {
  local out="$TMP_DIR/empty-out.json" rc
  PROJECT_FETCH_FIXTURE="$FXDIR/empty.json" "$PROJ" fetch "$UUID" --out="$out" >/dev/null 2>&1; rc=$?
  assert_eq "0" "$rc" "empty delta exits 0"
  assert_file_exists "$out" "empty payload still written"
  assert_json "$out" '.tickets | length' "0" "no tickets"
  assert_json "$out" '.summary.ticketCount' "0" "summary zero"
}

test_project_name_resolution() {
  # first fixture = projects resolve, second = issues
  local out="$TMP_DIR/name-out.json"
  PROJECT_FETCH_FIXTURE="$FXDIR/projects-one.json:$FXDIR/main.json" \
    "$PROJ" fetch "Product: Intake System" --since="$SINCE" --out="$out" >/dev/null 2>&1
  assert_json "$out" '.tickets | length' "2" "name resolved to id then fetched"
  # ambiguous → fail
  local rc
  PROJECT_FETCH_FIXTURE="$FXDIR/projects-ambiguous.json" "$PROJ" fetch "Dup" >/dev/null 2>&1; rc=$?
  assert_neq "0" "$rc" "ambiguous name exits non-zero"
}

test_project_bot_comment_author() {
  local out; out=$(_fetch_out "$FXDIR/main.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[0].comments[0].children[0].children[0].author' "Zapier" "bot comment author = botActor.name"
}

test_project_channels_live_catalog() {
  # A2 (finding #5): a channel with no delta activity still enumerates in structure.channels —
  # channels come from the aliased inbox-milestone catalog, not from the delta tickets.
  local out; out=$(_fetch_out "$FXDIR/channels-quiet.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets | length' "0" "quiet channel has no delta activity"
  assert_json "$out" '.structure.channels | length' "1" "quiet channel still enumerates (catalog independent of delta)"
  assert_json "$out" '.structure.channels[0].identifier' "FIN-QUIET" "the catalog channel is present"
  assert_json "$out" '.structure.channels[0].milestone' "Inboxes" "channel carries its milestone"
}

test_project_comment_quotedText() {
  # A3 (finding #6): anchored comments carry quotedText; thread comments have quotedText null —
  # both surface, distinguishable, so /intake can skip anchored annotations on rewire.
  local out; out=$(_fetch_out "$FXDIR/quoted.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[0].comments | length' "2" "both comments surface"
  assert_json "$out" '.tickets[0].comments[0].quotedText' "the quoted description text" "anchored comment carries quotedText"
  assert_json "$out" '.tickets[0].comments[1].quotedText' "null" "thread comment has quotedText null"
}

test_project_channels_resolved_flag() {
  # A4 (C5-flag): channelsResolved reflects whether the inbox milestone name resolved.
  local main; main=$(_fetch_out "$FXDIR/main.json" "$UUID" --since="$SINCE")
  assert_json "$main" '.channelsResolved' "true" "inbox milestone present → channelsResolved true"
  local ni; ni=$(_fetch_out "$FXDIR/no-inbox.json" "$UUID" --since="$SINCE")
  assert_json "$ni" '.channelsResolved' "false" "no inbox milestone → channelsResolved false"
  assert_json "$ni" '.structure.channels | length' "0" "no inbox milestone → empty channels"
}

test_project_orphan_reply_not_dropped() {
  # F1: a post-since reply to a pre-since parent must survive (re-rooted), not vanish.
  local out; out=$(_fetch_out "$FXDIR/orphan.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[0].comments | length' "1" "new reply to old thread is present"
  assert_json "$out" '.tickets[0].comments[0].id' "cNEW" "the re-rooted comment is the new reply"
  assert_json "$out" '.tickets[0].comments[0].orphanReply' "true" "flagged as reply-to-filtered-parent"
  assert_json "$out" '.summary.activity[] | select(.identifier=="FIN-9") | .comments' "1" "summary counts the orphan reply"
}

test_project_multifield_history_all_events() {
  # F2: one history entry changing state AND assignee → two normalized events.
  local out; out=$(_fetch_out "$FXDIR/multifield.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[0].lifecycle | length' "2" "both transitions emitted from one node"
  assert_json "$out" '[.tickets[0].lifecycle[].type] | sort | join(",")' "assignee,state" "state + assignee both present"
  assert_json "$out" '.tickets[0].lifecycle[] | select(.type=="assignee") | .to' "Bob" "assignee change not lost"
}

test_project_mixed_iso_precision() {
  # F3: --since without fraction vs Linear's .SSSZ — boundary items filtered correctly.
  local out; out=$(_fetch_out "$FXDIR/precision.json" "$UUID" --since="2026-07-20T00:00:00Z")
  assert_json "$out" '.tickets[0].comments | length' "1" "only the post-boundary comment kept"
  assert_json "$out" '.tickets[0].comments[0].id' "cAfter" "millisecond comparison is correct"
}

test_project_cursor_progress_guard() {
  # Council #9: hasNextPage:true + non-advancing cursor aborts instead of looping forever.
  local out="$TMP_DIR/stuck.json" rc
  PROJECT_FETCH_FIXTURE="$FXDIR/cursor-stuck.json" "$PROJ" fetch "$UUID" --out="$out" >/dev/null 2>&1; rc=$?
  assert_neq "0" "$rc" "stuck pagination cursor → non-zero exit (no infinite loop)"
  assert_file_not_exists "$out" "no payload written on stuck-cursor abort"
}

test_project_comments_overflow_paginated() {
  # A comment beyond the first inline page is fetched via the per-issue follow-up, not dropped.
  local out; out=$(_fetch_out "$FXDIR/co-main.json:$FXDIR/co-page2.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[0].comments | length' "2" "both comment pages present (follow-up paginated)"
  assert_json "$out" '[.tickets[0].comments[].id] | sort | join(",")' "c1,c2" "first + second page comments merged"
}

test_project_history_overflow_paginated() {
  # History beyond the first inline page must paginate (previously fail-closed → abort).
  local out; out=$(_fetch_out "$FXDIR/ho-main.json:$FXDIR/ho-page2.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[0].lifecycle | length' "2" "both history pages produce events (follow-up paginated)"
  assert_json "$out" '[.tickets[0].lifecycle[].type] | sort | join(",")' "priority,state" "state (pg1) + priority (pg2) both present"
}

test_project_attachments_overflow_paginated() {
  # Attachments beyond the first inline page must paginate (previously fail-closed → abort).
  local out; out=$(_fetch_out "$FXDIR/ao-main.json:$FXDIR/ao-page2.json" "$UUID" --since="$SINCE")
  assert_json "$out" '.tickets[0].attachments | length' "2" "both attachment pages present (follow-up paginated)"
  assert_json "$out" '[.tickets[0].attachments[].id] | sort | join(",")' "a1,a2" "first + second page attachments merged"
}

test_project_real_shape_fixture() {
  # FIN-3475 Part 3: replay REAL (PII-sanitized) Linear responses to lock the live payload shape.
  # Chain exercises all three captured fixtures: resolve (name→id) → main issues (channels alias +
  # quotedText) → FIN-1623 history follow-up (its inline history page was truncated live).
  local rd="$SRC_DIR/tests/fixtures/project-real"
  local out; out=$(_fetch_out "$rd/resolve.json:$rd/issues.json:$rd/history-followup.json" "Product: Claims & Policies")
  assert_file_exists "$out" "real-shape payload written"
  assert_json "$out" '(has("channelsResolved") and has("structure") and has("summary") and has("since") and has("fetchedAt"))' "true" "envelope keys present on real shape"
  assert_json "$out" '.channelsResolved' "true" "real project resolves the Inboxes milestone"
  assert_json "$out" '.structure.channels | length' "8" "all 8 real inbox channels enumerate (delta-independent)"
  assert_json "$out" '[.structure.channels[].milestone] | unique | join(",")' "Inboxes" "every real channel sits under Inboxes"
  assert_json "$out" '[.tickets[].comments | .. | objects | select(has("body"))] | all(has("quotedText"))' "true" "every real comment carries a quotedText key"
  assert_json "$out" '.tickets[] | select(.identifier=="FIN-1623") | (.lifecycle | length) > 0' "true" "FIN-1623 history follow-up merged (real follow-up fixture consumed)"
}

test_project_blank_since_fetches_all() {
  # First fetch: no --since, no stored waterline → the updatedAt filter is OMITTED ({}), never gt:null.
  # Offline the fixture ignores the filter, so this guards the blank-since assembly path (normTs("")
  # is "" → every comment passes the cutoff); the live gt:null→{} fix is verified against Linear.
  local out; out=$(_fetch_out "$FXDIR/main.json" "$UUID")
  assert_json "$out" '.tickets | length' "2" "blank since still returns tickets"
  assert_json "$out" '.since' "" "payload records empty since (first fetch)"
  assert_json "$out" '.summary.activity[] | select(.identifier=="FIN-3447") | .comments' "4" "blank since includes all comments (no cutoff)"
}

run_discovered_tests
