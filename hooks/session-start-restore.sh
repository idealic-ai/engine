#!/bin/bash
# SessionStart hook: Restore dehydrated context after context overflow restart
#
# Fires on Claude start. Scans sessions/ for a .state.json with dehydratedContext,
# reads required files, injects as additionalContext, then clears the field.
#
# Input (stdin): {"hook_event_name":"SessionStart","source":"startup|resume|clear|compact",...}
# Output (stdout): Plain text injected as Claude's additional context
#
# Fires on all sources (startup, resume, clear, compact).
# Standards are preloaded on every fire. Dehydration restore is startup-only.

set -euo pipefail

# Debug logging
DEBUG_LOG="/tmp/hooks-debug.log"
debug() {
  if [ "${HOOK_DEBUG:-}" = "1" ] || [ -f /tmp/hooks-debug-enabled ]; then
    echo "[$(date +%H:%M:%S)] [session-start] $*" >> "$DEBUG_LOG"
  fi
}

# Read hook input
INPUT=$(cat)
debug "fired: source=$(echo "$INPUT" | jq -r '.source // "?"')"

# Parse source for dehydration guard (dehydration is startup-only)
SOURCE=$(echo "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null)

# Find sessions directories (project root cwd from hook input)
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
if [ -z "$CWD" ]; then
  exit 0
fi

# Source lib.sh for safe_json_write, pid_exists, find_project_root
source "$HOME/.claude/scripts/lib.sh"

# Anchor the sessions dir to the nearest .claude/ ancestor of the hook's cwd, so a
# `cd` into a subfolder still resolves the repo-root sessions/ (no stray dirs).
PROJECT_ROOT=$(find_project_root "$CWD" 2>/dev/null || echo "$CWD")
SESSION_DIRS=()
if [ -d "$PROJECT_ROOT/sessions" ]; then
  SESSION_DIRS+=("$PROJECT_ROOT/sessions")
fi

if [ ${#SESSION_DIRS[@]} -eq 0 ]; then
  exit 0
fi

# Seeds are keyed to Claude's process so PostToolUse (a direct child of Claude)
# can find them. When invoked via the chunker, our own $PPID is the chunker's
# transient PID, so the chunker passes Claude's PID as CLAUDE_HOOK_PPID.
CLAUDE_PID="${CLAUDE_HOOK_PPID:-$PPID}"

# --- Session Context Block (fires on every source) ---
# Gather ambient context: time, active session, skill, phase, heartbeat
SESSION_CONTEXT_LINE=""
ACTIVE_SESSION=""
ACTIVE_SKILL=""
ACTIVE_PHASE=""
ACTIVE_HEARTBEAT=""

# Helper: extract session fields from .state.json into ACTIVE_* vars
_set_active_session() {
  local f="$1"
  ACTIVE_SESSION=$(basename "$(dirname "$f")")
  ACTIVE_SESSION_DIR=$(dirname "$f")
  ACTIVE_SKILL=$(jq -r '.skill // "unknown"' "$f" 2>/dev/null)
  ACTIVE_PHASE=$(jq -r '.currentPhase // "unknown"' "$f" 2>/dev/null)
  S_HEARTBEAT=$(jq -r '.toolCallsSinceLastLog // 0' "$f" 2>/dev/null)
  S_HEARTBEAT_MAX=$(jq -r '.toolUseWithoutLogsBlockAfter // 10' "$f" 2>/dev/null)
  ACTIVE_HEARTBEAT="${S_HEARTBEAT}/${S_HEARTBEAT_MAX}"
}

# Resolve the active session via the canonical resolver (`session.sh find`):
# fleet-pane exact match first, then strict PID (== this Claude process), with a
# PID-guard that rejects sessions held by a different live process. No match =>
# this pane owns no session (correct for scratch/meta panes and fresh startups).
# Single source of truth — never attaches an unrelated session because "some
# other agent's PID happens to be alive".
FOUND_DIR=$(cd "$CWD" 2>/dev/null && "$HOME/.claude/scripts/session.sh" find 2>/dev/null || true)
if [ -n "$FOUND_DIR" ] && [ -f "$FOUND_DIR/.state.json" ]; then
  _set_active_session "$FOUND_DIR/.state.json"
  debug "active session (session find): $ACTIVE_SESSION"
else
  debug "no active session for this process (session find: none)"
fi

# Dehydrated-context detection — startup-only restore. Scan for the first session
# carrying a dehydratedContext object, independent of active-session resolution.
DEHYDRATED_STATE_FILE=""
if [ "$SOURCE" = "startup" ]; then
  for sessions_dir in "${SESSION_DIRS[@]}"; do
    for f in "$sessions_dir"/*/.state.json; do
      [ -f "$f" ] || continue
      S_DEHY_TYPE=$(jq -r '.dehydratedContext // null | type' "$f" 2>/dev/null) || continue
      if [ "$S_DEHY_TYPE" = "object" ]; then
        DEHYDRATED_STATE_FILE="$f"
        break 2
      fi
    done
  done
fi

CONTEXT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
WORKSPACE_INFO=""
if [ -n "${WORKSPACE:-}" ]; then
  WORKSPACE_INFO=" | Workspace: $WORKSPACE"
fi
if [ -n "$ACTIVE_SESSION" ]; then
  SESSION_CONTEXT_LINE="[Session Context] Time: $CONTEXT_TIME${WORKSPACE_INFO} | Session: $ACTIVE_SESSION | Skill: $ACTIVE_SKILL | Phase: $ACTIVE_PHASE | Heartbeat: $ACTIVE_HEARTBEAT"
else
  SESSION_CONTEXT_LINE="[Session Context] Time: $CONTEXT_TIME${WORKSPACE_INFO} | Session: (none)"
fi
debug "session context: $SESSION_CONTEXT_LINE"

# Clear stale preload state for the active session only — these track what was injected
# into the PREVIOUS context window. A new Claude process = new context = must re-inject.
# Only the active session matters; dead sessions' state is never read by PostToolUse hooks.
debug "clearing preload state for fresh context"
PRELOAD_SEEDS=$(get_session_start_seeds)

# Pitfalls are on demand: an index generated from the files is injected instead of their bytes,
# so the files stay unregistered; PostToolUse discovery delivers a large one as its index too.
PITFALLS_INDEX_SOURCES=()
[ -f "$HOME/.claude/.directives/PITFALLS.md" ] && PITFALLS_INDEX_SOURCES+=("$HOME/.claude/.directives/PITFALLS.md")
if [ -f "$PROJECT_ROOT/.directives/PITFALLS.md" ]; then
  PROJECT_PITFALLS_REAL=$(normalize_preload_path "$PROJECT_ROOT/.directives/PITFALLS.md")
  ENGINE_PITFALLS_REAL=$(normalize_preload_path "$HOME/.claude/.directives/PITFALLS.md")
  [ "$PROJECT_PITFALLS_REAL" = "$ENGINE_PITFALLS_REAL" ] || PITFALLS_INDEX_SOURCES+=("$PROJECT_ROOT/.directives/PITFALLS.md")
fi

# Project docs index — when the repo follows the docs/TOC.md convention, treat it
# as a session-start preload: register it in the seeds (so PostToolUse dedup won't
# re-inject it) and inject its content alongside the standards below. No-op when absent.
PROJECT_DOCS_INDEX=""
if [ -f "$CWD/docs/TOC.md" ]; then
  PROJECT_DOCS_INDEX="$CWD/docs/TOC.md"
  TOC_NORM=$(normalize_preload_path "$PROJECT_DOCS_INDEX" 2>/dev/null || echo "$PROJECT_DOCS_INDEX")
  PRELOAD_SEEDS=$(echo "$PRELOAD_SEEDS" | jq --arg p "$TOC_NORM" 'if index($p) then . else . + [$p] end')
  debug "project docs index registered: $TOC_NORM"
fi

if [ -n "${ACTIVE_SESSION_DIR:-}" ] && [ -f "$ACTIVE_SESSION_DIR/.state.json" ]; then
  debug "  clearing preload state in $ACTIVE_SESSION (active)"
  jq --argjson stds "$PRELOAD_SEEDS" \
    '.preloadedFiles = $stds | .touchedDirs = {} | .pendingPreloads = [] | .pendingAllowInjections = []' \
    "$ACTIVE_SESSION_DIR/.state.json" | safe_json_write "$ACTIVE_SESSION_DIR/.state.json"
fi

for sessions_dir in "${SESSION_DIRS[@]}"; do
  # Clean stale seed files (dead PIDs) and create fresh seed for this process
  SEEDS_DIR="$sessions_dir/.seeds"
  if [ -d "$SEEDS_DIR" ]; then
    for seed_file in "$SEEDS_DIR"/*.json; do
      [ -f "$seed_file" ] || continue
      SEED_PID=$(jq -r '.pid // 0' "$seed_file" 2>/dev/null || echo "0")
      if [ "$SEED_PID" != "0" ] && ! pid_exists "$SEED_PID"; then
        debug "  cleaning stale seed: $(basename "$seed_file") (PID $SEED_PID dead)"
        rm -f "$seed_file"
      fi
    done
  fi

  # Create fresh seed for this Claude process
  mkdir -p "$sessions_dir/.seeds"
  SEED_FILE="$sessions_dir/.seeds/$CLAUDE_PID.json"
  jq -n --argjson pid "$CLAUDE_PID" --argjson seeds "$PRELOAD_SEEDS" '{
    pid: $pid,
    lifecycle: "seeding",
    preloadedFiles: $seeds,
    pendingPreloads: [],
    touchedDirs: {}
  }' > "$SEED_FILE"
  _log_delivery "session-start" "seed" "$SEED_FILE" "create-seed(pid=$CLAUDE_PID)"
  debug "  created seed: $SEED_FILE"
done

# --- Active skill dep delivery (when active session detected) ---
# After /clear, the agent needs SKILL.md + Phase 0 CMDs + templates immediately.
# Without this, they only arrive on the next PostToolUse (templates hook), which
# requires a tool call — leaving the agent without skill context after /clear.
SKILL_DEPS_OUTPUT=""
if [ -n "$ACTIVE_SKILL" ]; then
  debug "active skill detected: $ACTIVE_SKILL — delivering skill deps"

  # SKILL.md
  skill_md="$HOME/.claude/skills/$ACTIVE_SKILL/SKILL.md"
  if [ -f "$skill_md" ]; then
    skill_md_content=$(cat "$skill_md" 2>/dev/null || true)
    if [ -n "$skill_md_content" ]; then
      SKILL_DEPS_OUTPUT="[Preloaded: $skill_md]
$skill_md_content

"
      debug "  delivered SKILL.md"

      # Collect all dep paths: prose refs + current-phase CMDs + templates
      # Deduplicate before delivery to prevent dupes (e.g., CMD_REPORT_INTENT in both)
      ALL_DEP_PATHS=""
      SEEN_DEPS=""

      # 1. Prose refs from SKILL.md (orchestrator CMDs, FMTs, INVs outside code fences)
      skill_prose_refs=$(resolve_refs "$skill_md" 1 "$PRELOAD_SEEDS" 2>/dev/null || true)
      if [ -n "$skill_prose_refs" ]; then
        while IFS= read -r ref_path; do
          [ -n "$ref_path" ] || continue
          case "$SEEN_DEPS" in *"|$ref_path|"*) continue ;; esac
          SEEN_DEPS="${SEEN_DEPS}|${ref_path}|"
          ALL_DEP_PATHS="${ALL_DEP_PATHS}${ALL_DEP_PATHS:+
}$ref_path"
        done <<< "$skill_prose_refs"
      fi

      # 2. Current phase CMDs + templates (phase-aware)
      PHASE_LABEL=$(echo "$ACTIVE_PHASE" | sed 's/:.*//' | tr -d ' ')
      debug "  phase label: '$PHASE_LABEL'"
      phase_paths=$(resolve_phase_cmds "$ACTIVE_SKILL" "$PHASE_LABEL" 2>/dev/null || true)
      if [ -n "$phase_paths" ]; then
        while IFS= read -r dep_path; do
          [ -n "$dep_path" ] || continue
          # Normalize for dedup comparison
          local_norm=$(normalize_preload_path "${dep_path/#\~/$HOME}" 2>/dev/null || echo "$dep_path")
          case "$SEEN_DEPS" in *"|$local_norm|"*) debug "  skip dedup: $(basename "$dep_path") (already in prose refs)"; continue ;; esac
          SEEN_DEPS="${SEEN_DEPS}|${local_norm}|"
          ALL_DEP_PATHS="${ALL_DEP_PATHS}${ALL_DEP_PATHS:+
}$dep_path"
        done <<< "$phase_paths"
      fi

      # The log template is skipped once the session's own log exists: the live log shows the
      # format. Left out of the tracked paths too, so it can still be delivered later.
      SKIP_LOG_TEMPLATE=""
      skill_log_template=$(sed -n '/^```json$/,/^```$/p' "$skill_md" 2>/dev/null | sed '1d;$d' | jq -r '.logTemplate // ""' 2>/dev/null || true)
      if [ -n "$skill_log_template" ] && [ -n "${ACTIVE_SESSION_DIR:-}" ] \
        && [ -f "$ACTIVE_SESSION_DIR/$(basename "$skill_log_template" | sed 's/^TEMPLATE_//')" ]; then
        SKIP_LOG_TEMPLATE=$(normalize_preload_path "$(dirname "$skill_md")/$skill_log_template" 2>/dev/null || true)
      fi

      # Deliver all unique deps, deduped against boot standards
      KEPT_DEP_PATHS=""
      if [ -n "$ALL_DEP_PATHS" ]; then
        while IFS= read -r dep_path; do
          [ -n "$dep_path" ] || continue
          resolved="${dep_path/#\~/$HOME}"
          resolved_real=$(cd "$(dirname "$resolved")" 2>/dev/null && echo "$(pwd -P)/$(basename "$resolved")")
          if [ -n "$SKIP_LOG_TEMPLATE" ] && [ "$resolved_real" = "$SKIP_LOG_TEMPLATE" ]; then
            debug "  skip: $(basename "$resolved") (session log exists)"
            continue
          fi
          KEPT_DEP_PATHS="${KEPT_DEP_PATHS}${KEPT_DEP_PATHS:+
}$dep_path"
          if echo "$PRELOAD_SEEDS" | jq -e --arg p "$resolved_real" 'index($p) != null' >/dev/null 2>&1; then
            debug "  skip dedup: $(basename "$resolved") (boot standard)"
            continue
          fi
          if [ -f "$resolved" ]; then
            dep_content=$(cat "$resolved" 2>/dev/null || true)
            if [ -n "$dep_content" ]; then
              SKILL_DEPS_OUTPUT="${SKILL_DEPS_OUTPUT}[Preloaded: $dep_path]
$dep_content

"
              debug "  delivered dep: $(basename "$resolved")"
            fi
          fi
        done <<< "$ALL_DEP_PATHS"
      fi
    fi
  fi

  # Track skill deps in seed preloadedFiles
  if [ -n "$SKILL_DEPS_OUTPUT" ]; then
    # Build list of delivered skill dep paths (SKILL.md + all unique deps)
    SKILL_DEP_PATHS=""
    skill_md_norm=$(normalize_preload_path "$skill_md" 2>/dev/null || true)
    [ -n "$skill_md_norm" ] && SKILL_DEP_PATHS="$skill_md_norm"
    if [ -n "${KEPT_DEP_PATHS:-}" ]; then
      SKILL_DEP_PATHS="${SKILL_DEP_PATHS}${SKILL_DEP_PATHS:+
}${KEPT_DEP_PATHS}"
    fi

    # Update seed files with skill dep paths
    for sessions_dir in "${SESSION_DIRS[@]}"; do
      SEED_FILE="$sessions_dir/.seeds/$CLAUDE_PID.json"
      if [ -f "$SEED_FILE" ]; then
        # Add each path to preloadedFiles
        while IFS= read -r add_path; do
          [ -n "$add_path" ] || continue
          jq --arg p "$add_path" '
            (.preloadedFiles //= []) |
            if (.preloadedFiles | index($p)) then .
            else .preloadedFiles += [$p]
            end
          ' "$SEED_FILE" | safe_json_write "$SEED_FILE"
        done <<< "$SKILL_DEP_PATHS"
        debug "  updated seed with $(echo "$SKILL_DEP_PATHS" | wc -l | tr -d ' ') skill dep paths"
      fi
    done
  fi
fi

# --- Session artifact delivery (debrief or log fallback) ---
# After /clear or restart, preload the session's debrief (or log as fallback)
# so the agent has full context about what happened in this session.
ARTIFACT_OUTPUT=""
if [ -n "$ACTIVE_SKILL" ] && [ -n "${ACTIVE_SESSION_DIR:-}" ] && [ -f "${skill_md:-}" ]; then
  debug "checking session artifacts in $ACTIVE_SESSION_DIR"

  # Extract debrief and log filenames from SKILL.md JSON block
  # debriefTemplate: "assets/TEMPLATE_IMPLEMENTATION.md" → IMPLEMENTATION.md
  # logTemplate: "assets/TEMPLATE_IMPLEMENTATION_LOG.md" → IMPLEMENTATION_LOG.md
  SKILL_JSON=$(sed -n '/^```json$/,/^```$/p' "$skill_md" 2>/dev/null | sed '1d;$d' || true)
  DEBRIEF_TEMPLATE=$(echo "$SKILL_JSON" | jq -r '.debriefTemplate // ""' 2>/dev/null || true)
  LOG_TEMPLATE=$(echo "$SKILL_JSON" | jq -r '.logTemplate // ""' 2>/dev/null || true)

  DEBRIEF_NAME=""
  LOG_NAME=""
  if [ -n "$DEBRIEF_TEMPLATE" ]; then
    DEBRIEF_NAME=$(basename "$DEBRIEF_TEMPLATE" | sed 's/^TEMPLATE_//')
  fi
  if [ -n "$LOG_TEMPLATE" ]; then
    LOG_NAME=$(basename "$LOG_TEMPLATE" | sed 's/^TEMPLATE_//')
  fi

  debug "  debrief=$DEBRIEF_NAME log=$LOG_NAME"

  ARTIFACT_PATH=""
  if [ -n "$DEBRIEF_NAME" ] && [ -f "$ACTIVE_SESSION_DIR/$DEBRIEF_NAME" ]; then
    ARTIFACT_PATH="$ACTIVE_SESSION_DIR/$DEBRIEF_NAME"
    debug "  found debrief: $DEBRIEF_NAME"
  elif [ -n "$LOG_NAME" ] && [ -f "$ACTIVE_SESSION_DIR/$LOG_NAME" ]; then
    ARTIFACT_PATH="$ACTIVE_SESSION_DIR/$LOG_NAME"
    debug "  no debrief, using log fallback: $LOG_NAME"
  fi

  # Collect artifact paths to preload (debrief or log, plus DIALOGUE.md)
  ARTIFACT_PATHS=""
  if [ -n "$ARTIFACT_PATH" ]; then
    ARTIFACT_PATHS="$ARTIFACT_PATH"
  fi
  # Always include DIALOGUE.md if it exists (interrogation context)
  if [ -f "$ACTIVE_SESSION_DIR/DIALOGUE.md" ]; then
    ARTIFACT_PATHS="${ARTIFACT_PATHS}${ARTIFACT_PATHS:+
}$ACTIVE_SESSION_DIR/DIALOGUE.md"
  fi

  if [ -n "$ARTIFACT_PATHS" ]; then
    while IFS= read -r art_path; do
      [ -n "$art_path" ] || continue
      if [[ "$(basename "$art_path")" == "DIALOGUE.md" ]]; then
        ART_CONTENT=$(dialogue_tail "$art_path" 100 16000 || true)
      elif [ "$art_path" = "$ACTIVE_SESSION_DIR/${LOG_NAME:-}" ]; then
        # A log is append-only and can run to megabytes; a debrief is bounded and goes whole.
        if [ "$LOG_NAME" = "LOOM_LOG.md" ] && ART_CONTENT=$(loom_log_excerpt "$art_path"); then
          :
        else
          ART_CONTENT=$(heading_aligned_tail "$art_path" 50000 || true)
        fi
      else
        ART_CONTENT=$(cat "$art_path" 2>/dev/null || true)
      fi
      if [ -n "$ART_CONTENT" ]; then
        ARTIFACT_OUTPUT="${ARTIFACT_OUTPUT}[Preloaded: $art_path]
$ART_CONTENT

"
        debug "  preloaded session artifact: $(basename "$art_path")"

        # A log or DIALOGUE went out as an excerpt, so it is recorded under preloadedExcerpts:
        # preloadedFiles means "delivered whole", and SubagentStart cats every path listed there.
        ART_NORM=$(normalize_preload_path "$art_path" 2>/dev/null || echo "$art_path")
        DELIVERED_IN_PRELOAD="${DELIVERED_IN_PRELOAD:-}|$ART_NORM=the session excerpts above|"
        ART_FIELD="preloadedFiles"
        case "$art_path" in */DIALOGUE.md|"$ACTIVE_SESSION_DIR/${LOG_NAME:-}") ART_FIELD="preloadedExcerpts" ;; esac
        for sessions_dir in "${SESSION_DIRS[@]}"; do
          SEED_FILE="$sessions_dir/.seeds/$CLAUDE_PID.json"
          if [ -f "$SEED_FILE" ]; then
            jq --arg p "$ART_NORM" --arg k "$ART_FIELD" '
              (.[$k] //= []) |
              if (.[$k] | index($p)) then .
              else .[$k] += [$p]
              end
            ' "$SEED_FILE" | safe_json_write "$SEED_FILE"
          fi
        done
      fi
    done <<< "$ARTIFACT_PATHS"
  fi

  # Session directory listing — agent can see what artifacts exist
  SESSION_DIR_LISTING=""
  if [ -d "$ACTIVE_SESSION_DIR" ]; then
    FILE_LIST=$(ls -1 "$ACTIVE_SESSION_DIR" 2>/dev/null | grep -v '^\.' || true)
    if [ -n "$FILE_LIST" ]; then
      SESSION_DIR_LISTING="[Session Files: $ACTIVE_SESSION_DIR]
$FILE_LIST

"
      debug "  session dir listing: $(echo "$FILE_LIST" | wc -l | tr -d ' ') files"
    fi
  fi
  ARTIFACT_OUTPUT="${ARTIFACT_OUTPUT}${SESSION_DIR_LISTING}"
fi

# Preload core standards — exactly the get_session_start_seeds list, which is what dedup records.
STANDARDS_OUTPUT=""
while IFS= read -r std_file; do
  [ -n "$std_file" ] || continue
  STD_CONTENT=$(cat "$std_file" 2>/dev/null || true)
  if [ -n "$STD_CONTENT" ]; then
    STANDARDS_OUTPUT="${STANDARDS_OUTPUT}[Preloaded: $std_file]
$STD_CONTENT

"
    debug "  preloaded standard: $(basename "$std_file")"
  fi
done < <(get_session_start_seeds | jq -r '.[]')

if [ ${#PITFALLS_INDEX_SOURCES[@]} -gt 0 ]; then
  PITFALLS_INDEX=$(generate_pitfalls_index "${PITFALLS_INDEX_SOURCES[@]}" 2>/dev/null || true)
  if [ -n "$PITFALLS_INDEX" ]; then
    STANDARDS_OUTPUT="${STANDARDS_OUTPUT}[Pitfalls index, generated at session start from: ${PITFALLS_INDEX_SOURCES[*]}. The files themselves are not preloaded; read an entry with grep -n -A12 '¶PTF_<NAME>' <file>]
$PITFALLS_INDEX

"
    debug "  preloaded pitfalls index: ${#PITFALLS_INDEX_SOURCES[@]} file(s)"
  fi
fi

# Inject the project docs index (registered in PRELOAD_SEEDS above)
if [ -n "$PROJECT_DOCS_INDEX" ]; then
  TOC_CONTENT=$(cat "$PROJECT_DOCS_INDEX" 2>/dev/null || true)
  if [ -n "$TOC_CONTENT" ]; then
    STANDARDS_OUTPUT="${STANDARDS_OUTPUT}[Preloaded: docs/TOC.md]
$TOC_CONTENT

"
    debug "  preloaded project docs index: docs/TOC.md"
  fi
fi

# Mandatory-preload banner — MUST be the first bytes so it survives Claude Code's
# ~2KB additionalContext preview when large hook stdout is spilled to a file.
PRELOAD_BANNER="════════════════════════════════════════════════════════════════════
⚠️  MANDATORY PRELOAD — DO NOT SKIP  ⚠️
EVERYTHING BELOW IS PRELOADED CONTEXT AND MUST BE LOADED IN FULL.
Claude Code truncates large SessionStart hook output to a file and shows you
only a small preview from the top (COMMANDS.md). If you see a notice like
\"Output too large … Full output saved to: <path>\" with only a preview, you are
seeing ONLY THE FIRST CHUNK. BEFORE you plan, answer, or call any tool, READ
THAT ENTIRE FILE end-to-end so every [Preloaded: …] block below (standards,
docs/TOC.md, dehydrated recovery context, session artifacts, skill deps) is
actually in your context. Acting on the preview alone is a protocol violation.
════════════════════════════════════════════════════════════════════"

# Order: standards, the dehydrated summary, the session excerpts, the dehydrated required files,
# then skill files. An overflow therefore cuts files that can be re-read whole before the newest
# session state, which cannot be.
HEAD_OUTPUT="${PRELOAD_BANNER}
${SESSION_CONTEXT_LINE}
${STANDARDS_OUTPUT}"

# Dehydrated context restore — startup only (other sources: user didn't restart)
CONTEXT=""
STATE_FILE=""
if [ "$SOURCE" = "startup" ]; then
  STATE_FILE="${DEHYDRATED_STATE_FILE:-}"
else
  debug "$SOURCE source — skipping dehydration"
fi
[ -n "$STATE_FILE" ] || debug "no dehydrated context to restore"

if [ -n "$STATE_FILE" ]; then
SESSION_DIR=$(dirname "$STATE_FILE")
SESSION_NAME=$(basename "$SESSION_DIR")

# Extract dehydrated context fields
SUMMARY=$(jq -r '.dehydratedContext.summary // "No summary"' "$STATE_FILE")
LAST_ACTION=$(jq -r '.dehydratedContext.lastAction // "Unknown"' "$STATE_FILE")
NEXT_STEPS=$(jq -r '.dehydratedContext.nextSteps // [] | join("\n- ")' "$STATE_FILE")
HANDOVER=$(jq -r '.dehydratedContext.handoverInstructions // ""' "$STATE_FILE")
USER_HISTORY=$(jq -r '.dehydratedContext.userHistory // ""' "$STATE_FILE")
SKILL=$(jq -r '.skill // "unknown"' "$STATE_FILE")
PHASE=$(jq -r '.currentPhase // "unknown"' "$STATE_FILE")

# Build the context string
CONTEXT="## Session Recovery (Dehydrated Context)

**Session**: $SESSION_NAME
**Skill**: $SKILL
**Phase**: $PHASE

### Summary
$SUMMARY

### Last Action
$LAST_ACTION

### Next Steps
- $NEXT_STEPS

### Handover Instructions
$HANDOVER"

if [ -n "$USER_HISTORY" ]; then
  CONTEXT="$CONTEXT

### User Interaction History
$USER_HISTORY"
fi

# Skill files delivered at the end of this preload, so a required file naming one is not repeated.
if [ -n "${SKILL_DEP_PATHS:-}" ]; then
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    dep_norm=$(normalize_preload_path "${dep/#\~/$HOME}" 2>/dev/null || echo "$dep")
    DELIVERED_IN_PRELOAD="${DELIVERED_IN_PRELOAD:-}|$dep_norm=the skill files below|"
  done <<< "$SKILL_DEP_PATHS"
fi

# Read required files into their own block, which goes after the session excerpts
REQUIRED_OUTPUT=""
REQUIRED_FILES=$(jq -r '.dehydratedContext.requiredFiles // [] | .[]' "$STATE_FILE" 2>/dev/null)
if [ -n "$REQUIRED_FILES" ]; then
  REQUIRED_OUTPUT="## Session Recovery: Required Files (Auto-Loaded)"

  while IFS= read -r filepath; do
    [ -z "$filepath" ] && continue

    # Resolve path prefixes
    resolved="$filepath"
    case "$filepath" in
      "~/.claude/"*) resolved="$HOME/.claude/${filepath#\~/.claude/}" ;;
      "~/"*) resolved="$HOME/${filepath#\~/}" ;;
      "sessions/"*|"packages/"*|"apps/"*|"src/"*|".claude/"*) resolved="$CWD/$filepath" ;;
    esac

    resolved_norm=$(normalize_preload_path "$resolved" 2>/dev/null || echo "$resolved")
    delivered_as=""
    case "${DELIVERED_IN_PRELOAD:-}" in
      *"|$resolved_norm="*) delivered_as="${DELIVERED_IN_PRELOAD#*|$resolved_norm=}"; delivered_as="${delivered_as%%|*}" ;;
    esac
    if [ -n "$delivered_as" ]; then
      REQUIRED_OUTPUT="$REQUIRED_OUTPUT

---
#### File: $filepath
[Already in this preload — see $delivered_as. Not repeated here.]"
    elif [ -f "$resolved" ]; then
      FILE_CONTENT=$(heading_aligned_tail "$resolved" 50000 || echo "[Error reading file]")
      REQUIRED_OUTPUT="$REQUIRED_OUTPUT

---
#### File: $filepath
\`\`\`
$FILE_CONTENT
\`\`\`"
    else
      REQUIRED_OUTPUT="$REQUIRED_OUTPUT

---
#### File: $filepath
[MISSING — file not found at $resolved]"
    fi
  done <<< "$REQUIRED_FILES"
fi

# Clear dehydratedContext from .state.json (consumed)
jq 'del(.dehydratedContext)' "$STATE_FILE" | safe_json_write "$STATE_FILE"
CONTEXT="${CONTEXT}

"
[ -z "$REQUIRED_OUTPUT" ] || REQUIRED_OUTPUT="${REQUIRED_OUTPUT}

"
fi

# The dehydrated summary and the session excerpts (ledger, hand-over, newest log entries, DIALOGUE
# tail) come before the required files and the skill files, so an overflow cuts those first.
echo "${HEAD_OUTPUT}${CONTEXT}${ARTIFACT_OUTPUT}${REQUIRED_OUTPUT:-}${SKILL_DEPS_OUTPUT}"
