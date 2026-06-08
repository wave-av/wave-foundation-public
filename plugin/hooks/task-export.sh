#!/usr/bin/env bash
# task-export.sh — capture open tasks to a durable, session-independent carryover store.
#
# WHY: tasks live at ~/.claude/tasks/<SESSION_ID>/<n>.json and there is NO session-lineage
# pointer. /compact keeps the session ID (tasks survive natively), but /clear rotates it →
# the new session gets an empty task dir and the old tasks are orphaned on disk. This script
# snapshots open tasks (status != completed/deleted) to ~/.claude/tasks-carryover/ so a
# SessionStart restore (task-carryover-restore.sh) can re-materialize them after a /clear.
#
# Runs as a PreCompact hook (insurance) AND can be invoked standalone before a /clear.
# Always exits 0 — never blocks a turn or a compaction.
set -u

TASKS_ROOT="$HOME/.claude/tasks"
OUT_DIR="$HOME/.claude/tasks-carryover"
mkdir -p "$OUT_DIR"

# --- resolve the source session id -------------------------------------------------
# Prefer the hook stdin (session_id); fall back to transcript_path basename; finally to the
# most-recently-modified task dir (covers standalone invocation with no stdin).
stdin_json=""
if [ ! -t 0 ]; then stdin_json="$(cat 2>/dev/null || true)"; fi

sid="$(printf '%s' "$stdin_json" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("session_id") or "")
except Exception: print("")' 2>/dev/null)"

if [ -z "${sid:-}" ]; then
  tp="$(printf '%s' "$stdin_json" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("transcript_path") or "")
except Exception: print("")' 2>/dev/null)"
  [ -n "$tp" ] && sid="$(basename "$tp" .jsonl)"
fi

# allow explicit override: task-export.sh <session_id>
[ -n "${1:-}" ] && sid="$1"

if [ -z "${sid:-}" ] || [ ! -d "$TASKS_ROOT/$sid" ]; then
  # autodetect: newest dir under TASKS_ROOT that actually holds task json
  sid="$(ls -dt "$TASKS_ROOT"/*/ 2>/dev/null | while read -r d; do
           ls "$d"*.json >/dev/null 2>&1 && { basename "$d"; break; }
         done)"
fi
[ -n "${sid:-}" ] && [ -d "$TASKS_ROOT/$sid" ] || { echo "task-export: no source session found"; exit 0; }

# --- store key: PROJECT (cwd), which survives /clear --------------------------------
# A single shared store is last-writer-wins: with multiple concurrent sessions, each Stop-export
# clobbers the others, so a /clear could restore a DIFFERENT session's tasks. Keying by cwd means
# a cleared session reunites with its OWN predecessor and other projects never collide.
cwd="$(printf '%s' "$stdin_json" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("cwd") or "")
except Exception: print("")' 2>/dev/null)"
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
key="$(printf '%s' "$cwd" | python3 -c 'import sys,hashlib; print("p_"+hashlib.sha1(sys.stdin.buffer.read().strip()).hexdigest()[:16])')"
STORE="$OUT_DIR/$key.json"; STORE_MD="$OUT_DIR/$key.md"

# --- snapshot open tasks ------------------------------------------------------------
python3 - "$TASKS_ROOT/$sid" "$STORE" "$STORE_MD" "$sid" "$cwd" <<'PY' 2>/dev/null
import json, os, sys, glob, datetime
src, store, store_md, sid, cwd = sys.argv[1:6]
open_tasks = []
for fp in glob.glob(os.path.join(src, "*.json")):
    try:
        t = json.load(open(fp))
    except Exception:
        continue
    if t.get("status") in ("completed", "deleted"):
        continue
    open_tasks.append(t)
# stable order by numeric id
def _id(t):
    try: return int(t.get("id", 0))
    except Exception: return 0
open_tasks.sort(key=_id)

stamp = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
payload = {"source_session": sid, "project": cwd, "exported_at": stamp,
           "count": len(open_tasks), "consumed": False, "tasks": open_tasks}
with open(store, "w") as f:
    json.dump(payload, f, indent=2)

# human-readable mirror
lines = [f"# Carryover tasks ({len(open_tasks)} open) — exported {stamp} from {sid} [{cwd}]", ""]
for t in open_tasks:
    dep = t.get("blockedBy") or []
    suffix = f"  [blockedBy {', '.join('#'+d for d in dep)}]" if dep else ""
    lines.append(f"- #{t.get('id','?')} [{t.get('status','?')}] {t.get('subject','')}{suffix}")
with open(store_md, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"task-export: {len(open_tasks)} open task(s) → {store}")
PY
exit 0
