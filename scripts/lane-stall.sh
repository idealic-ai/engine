#!/bin/bash
# lane-stall.sh — list loom lanes that have gone quiet.
#
# Usage:
#   engine lane-stall <sessionDir> [--minutes N] [--since-hours H] [--all]
#
# A lane is a subagent of the session whose thread TAG can be established. The tag is read
# from the first source that yields one, and the row says which (the "via" column):
#   desc    the spawn's own Agent/Task `description` in the parent transcript — authoritative,
#           since ¶INV_LOOM_AGENTS_NAMED_BY_THREAD brackets the description
#   head    a "[TAG]" at the very start of the dispatch prompt
#   thread  a "thread <TAG>" / "thread **TAG**" announcement in the prompt's opening
# A bare bracket scan over the whole prompt is deliberately NOT a source: briefs quote
# protocol tokens ([MANDATORY], [NEXT], [KEEP], ...) and would mint phantom lanes.
#
# For each lane it reports:
#   transcript  minutes since the lane's transcript last changed (any tool call or reply)
#   log         minutes since the lane last wrote to any *_LOG.md under the session dir
#               (searched recursively — lane logs live in <sessionDir>/builds/). A "~" marks
#               a reading taken from the log file's mtime because its headings carry no
#               timestamp, which is what `engine log` does to a heading opening with "[".
#   state       done (handed back) | parked (turn ended, no hand-back) | running
#   agent       the lane's agent transcript. Diagnostic only — NEVER a hand-over handle.
#   logpath     the log the "log" reading above was taken from, or "none". This is the field
#               a hand-over carries (¶INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID): a context clear
#               ends every in-process subagent, so an agent id or transcript is unexecutable
#               on arrival while the log survives and briefs a fresh lane. "none" is a
#               reading, not a blank — a lane with no log is a different hand-over from a
#               lane with one. It comes LAST because the tail of a row is what gets copied.
#
# READ logpath AS EVERYTHING AFTER "logpath=" TO END OF LINE: `sed 's/.*logpath=//'`. It is the
# last FIELD only on a path with no spaces, and session directories on a shared drive routinely
# have them ("…/Shared drives/…"), so `awk '{print $NF}'` returns a truncated path that still
# looks like one. Nothing after it is ever printed, which is what makes the sed form exact.
# Prints only lanes that are not done and whose freshest signal is older than --minutes
# (default 30), unless --all. Exit 0 = nothing stale, 3 = at least one stale lane.
#
# The first line states the window, the threshold and the lane count, because every reading
# below is scoped to that window. --since-hours defaults to the SESSION'S OWN AGE (floored at
# 12h), read from the directory's name and its birthtime, wider wins — a fixed 12h default
# hid a long weave's early lanes from the hand-over that most needs them.
#
# It answers lane STATE, never reachability: a dead lane's transcript persists on disk and
# reads "parked", not gone. "parked" means only that the lane's last turn ended without a tool
# call, which covers died, finished, and waiting-on-the-conductor alike — so a healthy lane
# blocked on a reply reads "STALE state=parked" once it crosses the threshold, and a finished
# thread reads the same. A "0 lanes seen" line is a claim about what was recognised. Reconcile
# every reading against the weave's ledger before acting on it.
#
# Read the exit status DIRECTLY, never through a pipeline: `engine lane-stall ... | head` gives
# you head's status, not the verdict.
# Read-only: it never touches lanes, transcripts or the log.

set -euo pipefail

SESSION_DIR="${1:?usage: engine lane-stall <sessionDir> [--minutes N] [--since-hours H] [--all]}"
shift
MINUTES=30; SINCE_HOURS=auto; SHOW_ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --minutes) MINUTES="$2"; shift 2 ;;
    --since-hours) SINCE_HOURS="$2"; shift 2 ;;
    --all) SHOW_ALL=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

exec python3 -I - "$SESSION_DIR" "$MINUTES" "$SINCE_HOURS" "$SHOW_ALL" "$PROJECTS_DIR" <<'PY'
import glob, json, os, re, sys, time
from datetime import datetime

session_dir, minutes, since_hours, show_all, projects_dir = sys.argv[1:]
minutes, show_all = float(minutes), show_all == "1"
now = time.time()

# The window defaults to the SESSION'S OWN AGE, floored at 12h, because a fixed 12h default
# hid a weave's early lanes from the hand-over that most needs them — measured 2026-10-21 on
# a 92.6h-old session: 13 lanes inside 12h against 137 inside the session's life. Width is
# not what this scan costs: 12h/400h/2000h/20000h came in at 0.95s/9.10s/12.24s/9.87s on the
# same corpus, flat past the first, since the cost is the machine's whole transcript set and
# not the slice. So there is no ceiling to trade accuracy against.
#
# The age is read from the directory's own NAME first and its birthtime only as a fallback,
# and the WIDER of the two wins. Neither alone is sound: ctime tracks the newest metadata
# write and read 0.0h on a four-day-old session, and birthtime is reset by a copy or a sync
# — measured on a session whose name declares 2026_10_12, birthtime said 92.7h against the
# name's 238.5h, and the narrower window dropped 46 of its 137 lanes.
DEFAULT_SINCE_HOURS = 12.0
DIR_DATE = re.compile(r"(\d{4})[_-](\d\d)[_-](\d\d)")

def session_age_hours(path):
    ages = []
    m = DIR_DATE.match(os.path.basename(os.path.realpath(path)))
    if m:
        try:
            ages.append((now - datetime(*map(int, m.groups())).timestamp()) / 3600)
        except ValueError:
            pass
    try:
        birth = getattr(os.stat(path), "st_birthtime", None)
        if birth:
            ages.append((now - birth) / 3600)
    except OSError:
        pass
    return max(ages) if ages else 0.0

if since_hours == "auto":
    since_hours = max(DEFAULT_SINCE_HOURS, session_age_hours(session_dir))
else:
    since_hours = float(since_hours)
cutoff = now - since_hours * 3600

TAG = re.compile(r"\[([A-Z][A-Z0-9_-]{2,})\]")
TS = re.compile(r"\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\]")
HEAD_TAG = re.compile(r"\s*\[([A-Z][A-Z0-9_-]{2,})\]")
THREAD_TAG = re.compile(r"\bthread\s+(?:\*\*)?\[?([A-Z][A-Z0-9_-]{2,})\]?(?:\*\*)?")
THREAD_SCAN_CHARS = 400

# agentId -> spawn `description`, per parent transcript. The parent of
# <proj>/<sessionId>/subagents/agent-<id>.jsonl is <proj>/<sessionId>.jsonl; inside it a
# record carries toolUseResult.agentId alongside a tool_result naming the Agent/Task
# tool_use whose input holds both `description` and `prompt`. Written at spawn, not at
# hand-back, so a running lane resolves.
_spawn_cache = {}

def spawn_descriptions(parent_path):
    if parent_path in _spawn_cache:
        return _spawn_cache[parent_path]
    described, tool_desc, agent_tool = {}, {}, {}
    try:
        fh = open(parent_path, encoding="utf-8", errors="replace")
    except OSError:
        _spawn_cache[parent_path] = described
        return described
    try:
        with fh:
            for line in fh:
                # Parse only the two record shapes that matter. Prefiltering on '"tool_use"'
                # instead would parse most assistant turns, which costs minutes on a 15MB
                # transcript.
                if '"agentId"' not in line and '"Agent"' not in line and '"Task"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                blocks = (rec.get("message") or {}).get("content") or []
                if not isinstance(blocks, list):
                    blocks = []
                result = rec.get("toolUseResult")
                if isinstance(result, dict) and result.get("agentId"):
                    for b in blocks:
                        if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id"):
                            agent_tool[result["agentId"]] = b["tool_use_id"]
                for b in blocks:
                    if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task"):
                        tool_desc[b.get("id")] = (b.get("input") or {}).get("description")
    except OSError as exc:
        unreadable.append(str(exc))
    for agent_id, tool_id in agent_tool.items():
        desc = tool_desc.get(tool_id)
        if desc:
            described[agent_id] = desc
    _spawn_cache[parent_path] = described
    return described

def resolve_tag(path, text):
    subagents = os.path.dirname(path)
    agent_id = os.path.basename(path)[len("agent-"):-len(".jsonl")]
    desc = spawn_descriptions(os.path.dirname(subagents) + ".jsonl").get(agent_id)
    if desc:
        m = HEAD_TAG.match(desc)
        if m:
            return m.group(1), "desc"
    m = HEAD_TAG.match(text)
    if m:
        return m.group(1), "head"
    m = THREAD_TAG.search(text[:THREAD_SCAN_CHARS])
    if m:
        return m.group(1), "thread"
    return None, None

# Last log heading per tag; headings without their own timestamp inherit the previous one.
# A log whose headings are ALL unstamped still dates its own tags, from the file mtime —
# `engine log` drops the timestamp from any heading opening with "[", which is every heading
# a lane writes under ¶INV_LOOM_AGENTS_NAMED_BY_THREAD. Capped at two tags so a shared
# conductor log can never date a lane it merely mentions.
MTIME_FALLBACK_MAX_TAGS = 2
# A log whose headings carry NO tag at all is dated to the tag in its own filename, from its
# own last stamped heading (or its mtime when it has none). Without this a lane that stamps
# its headings and does not repeat its tag falls through both branches above and reads
# "logpath=none" with its log sitting at builds/<TAG>_LOG.md — a FALSE reading in the one
# field a successor is told to trust. The guard is "no tag anywhere in the file", not "no tag
# on the stamped headings": measured on one corpus, PROMPTLAB_LOG.md holds 85 headings of
# which the 13 stamped ones are a LATER lane's [IDE-122] entries, so dating PROMPTLAB from
# this file's last stamp would report a stale lane as fresh. It correctly stays "none".
LOGNAME_TAG = re.compile(r"^([A-Z][A-Z0-9_-]{2,})_LOG\.md$")
# log_path is the field every consumer of this sweep is required to hand over and forbidden
# to substitute (`§INV_LOOM_HANDS_OVER_A_PATH_NOT_AN_ID`): a lane's agent id dies with the
# parent context and its transcript is not a brief, while its log survives both. The sweep
# already knows which file dated each tag, so withholding the path only made every caller
# re-derive it.
log_last, log_path, log_approx = {}, {}, set()
unreadable = []

# os.walk with onerror, not glob(recursive=True): a session dir on a cloud-synced mount can
# time out mid-walk, and glob raises that straight out of the process. An unreadable path is
# counted and reported, never swallowed — a silent read failure would read as "no lanes".
def session_logs():
    try:
        walker = os.walk(session_dir, onerror=lambda e: unreadable.append(str(e)))
        for root, dirs, files in walker:
            for name in files:
                if name.endswith("_LOG.md"):
                    yield os.path.join(root, name)
    except OSError as exc:
        unreadable.append(str(exc))

for log in session_logs():
    last_ts = None
    unstamped, seen_tags = set(), set()
    try:
        with open(log, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if not line.startswith("## "):
                    continue
                m = TS.search(line)
                if m:
                    last_ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").timestamp()
                heading_tags = TAG.findall(TS.sub("", line))
                seen_tags.update(heading_tags)
                if last_ts is None:
                    unstamped.update(heading_tags)
                    continue
                for tag in heading_tags:
                    if last_ts > log_last.get(tag, 0):
                        log_last[tag] = last_ts
                        log_path[tag] = log
                        # An exact dating supersedes an mtime one, so the "~" must go with it.
                        log_approx.discard(tag)
        if not seen_tags:
            m = LOGNAME_TAG.match(os.path.basename(log))
            stamp = last_ts if last_ts is not None else os.path.getmtime(log)
            if m and stamp > log_last.get(m.group(1), 0):
                log_last[m.group(1)] = stamp
                log_path[m.group(1)] = log
                if last_ts is None:
                    log_approx.add(m.group(1))
        elif last_ts is None and 0 < len(unstamped) <= MTIME_FALLBACK_MAX_TAGS:
            mtime = os.path.getmtime(log)
            for tag in unstamped:
                if mtime > log_last.get(tag, 0):
                    log_last[tag] = mtime
                    log_path[tag] = log
                    log_approx.add(tag)
    except OSError as exc:
        unreadable.append(str(exc))

# A lane is claimed by this session when its prompt names the session's PARENT DIRECTORY and
# name together ("sessions/2026_10_14_LAND_TREE_BRANCHES"), not the name alone. The bare
# basename is a substring test against a whole dispatch prompt, so an ordinary-word directory
# name harvests other weaves' lanes: a dir named "empty" matched 2073 transcripts, where
# "sessions/empty" matched none. Requiring the full absolute path instead would be a new false
# clean — briefs spell the same session several ways, and that costs 326 of 596 lanes on one
# measured weave. Two same-named sessions under different roots still both match; the brief
# carries only one spelling, so nothing in the prompt separates them.
parts = [p for p in os.path.realpath(session_dir).split(os.sep) if p]
session_key = os.sep.join(parts[-2:]) if len(parts) >= 2 else (parts[-1] if parts else "")

# Lanes from subagent transcripts touched within the window.
lanes = {}
for path in glob.glob(os.path.join(projects_dir, "*", "*", "subagents", "agent-*.jsonl")):
    try:
        mtime = os.path.getmtime(path)
        if mtime < cutoff:
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            first = fh.readline()
    except OSError as exc:
        unreadable.append(str(exc))
        continue
    try:
        content = json.loads(first)["message"]["content"]
    except Exception:
        continue
    text = content if isinstance(content, str) else " ".join(
        b.get("text", "") for b in content if isinstance(b, dict))
    if session_key not in text:
        continue
    tag, via = resolve_tag(path, text)
    if tag is None:
        continue
    state = "running"
    try:
        with open(path, "rb") as fh:
            fh.seek(max(0, os.path.getsize(path) - 65536))
            tail = fh.read().decode("utf-8", "replace").splitlines()
    except OSError as exc:
        unreadable.append(str(exc))
        tail = []
    for raw in reversed(tail):
        try:
            rec = json.loads(raw)
        except Exception:
            continue
        msg = rec.get("message") or {}
        if msg.get("role") != "assistant":
            continue
        blocks = msg.get("content") or []
        names = [b.get("name") for b in blocks if isinstance(b, dict) and b.get("type") == "tool_use"]
        if "SubagentHandback" in names:
            state = "done"
        elif not names and msg.get("stop_reason") == "end_turn":
            state = "parked"
        break
    prev = lanes.get(tag)
    if prev is None or mtime > prev["mtime"]:
        lanes[tag] = {"mtime": mtime, "state": state, "path": path, "via": via}

def age(t):
    # A file written during this run is "newer than now"; report 0, never a negative age.
    return None if not t else max(0.0, (now - t) / 60)

rows, stale = [], 0
for tag, lane in sorted(lanes.items()):
    t_age, l_age = age(lane["mtime"]), age(log_last.get(tag))
    fresh = min(a for a in (t_age, l_age) if a is not None)
    is_stale = lane["state"] != "done" and fresh > minutes
    stale += is_stale
    if show_all or is_stale:
        rows.append((tag, lane["state"], lane["via"], t_age, l_age, is_stale, lane["path"]))

# Every reading below is scoped to this window, and a horizon left unstated is how "0 lanes
# seen" over half a day read identically to the same words over a whole weave.
print(f"window={since_hours:.0f}h  threshold={minutes:.0f}m  lanes={len(lanes)}")
fmt = lambda a: "-" if a is None else f"{a:.0f}m"
for tag, state, via, t_age, l_age, is_stale, path in rows:
    flag = "STALE" if is_stale else "ok"
    log_col = fmt(l_age) + ("~" if tag in log_approx and l_age is not None else "")
    # logpath LAST, because the tail of a row is what a reader copies and the agent
    # transcript in that position is what produced every caller's hand-rolled workaround.
    # "none" is a reading, not a blank: a lane with no log is a different hand-over.
    print(f"{flag:5}  [{tag}]  state={state:7}  via={via:6}  "
          f"transcript={fmt(t_age):>6}  log={log_col:>7}  "
          f"agent={path}  logpath={log_path.get(tag, 'none')}")
if not rows:
    print(f"no stale lanes (threshold {minutes:.0f}m, {len(lanes)} lanes seen)")
if unreadable:
    print(f"warning: {len(unreadable)} path(s) unreadable; counts above are a floor. "
          f"first: {unreadable[0]}", file=sys.stderr)
sys.exit(3 if stale else 0)
PY
