#!/usr/bin/env bash
# task-carryover-restore.sh — SessionStart hook. Re-materializes open tasks that would otherwise
# be orphaned when /clear rotates the session ID (tasks are keyed by ~/.claude/tasks/<SESSION_ID>/
# with no lineage pointer). Pairs with task-export.sh.
#
# Safe-by-design:
#   • Skips on /compact and resume (same session → tasks already intact).
#   • Only restores when the NEW session's task dir is empty (never clobbers live tasks).
#   • Only restores a FRESH, unconsumed carryover (default <24h) — avoids injecting stale tasks
#     into a genuinely unrelated new session.
#   • Marks the carryover consumed so it imports at most once.
#   • Copies the task JSONs into the new session dir (best case the task manager reads them) AND
#     emits the list as SessionStart context with an instruction to verify via TaskList and
#     re-create any missing — deterministic fallback if the manager cached an empty list.
# Always exits 0.
set -u

OUT_DIR="$HOME/.claude/tasks-carryover"
TASKS_ROOT="$HOME/.claude/tasks"
MAX_AGE_SEC="${WAVE_CARRYOVER_MAX_AGE:-86400}"   # 24h default

stdin_json=""
if [ ! -t 0 ]; then stdin_json="$(cat 2>/dev/null || true)"; fi

read -r sid source <<<"$(printf '%s' "$stdin_json" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print((d.get("session_id") or "-"), (d.get("source") or "-"))
except Exception: print("- -")' 2>/dev/null)"

# Only restore on an actual /clear. compact|resume keep the session id (tasks intact); a plain
# `startup` is a genuinely new, unrelated session and must NOT inherit a PreCompact-exported
# carryover (that would leak tasks into an unrelated session).
[ "$source" = "clear" ] || exit 0

# carryover store is keyed by project (cwd) — must match task-export.sh. /clear preserves cwd, so
# this loads THIS project's predecessor and never a concurrent session's store.
cwd="$(printf '%s' "$stdin_json" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("cwd") or "")
except Exception: print("")' 2>/dev/null)"
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
key="$(printf '%s' "$cwd" | python3 -c 'import sys,hashlib; print("p_"+hashlib.sha1(sys.stdin.buffer.read().strip()).hexdigest()[:16])')"
CARRY="$OUT_DIR/$key.json"
[ -f "$CARRY" ] || exit 0

python3 - "$CARRY" "$TASKS_ROOT" "$sid" "$MAX_AGE_SEC" <<'PY' 2>/dev/null
import json, os, sys, glob, time, datetime
carry, root, sid, max_age = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

def _emit_context(p, tasks):
    # SessionStart context (injected) — deterministic fallback if the task manager cached empty.
    lines = [f"♻️ Carryover: {len(tasks)} open task(s) restored after a session reset (source={p.get('source_session','?')}).",
             "Verify with TaskList; if any are missing, re-create them from this list:"]
    for t in tasks:
        dep = t.get("blockedBy") or []
        suffix = f" [blockedBy {', '.join('#'+d for d in dep)}]" if dep else ""
        lines.append(f"  • #{t.get('id','?')} {t.get('subject','')}{suffix}")
    print("\n".join(lines))

try:
    p = json.load(open(carry))
except Exception:
    sys.exit(0)
if p.get("consumed"):
    sys.exit(0)
tasks = p.get("tasks") or []
if not tasks:
    sys.exit(0)

# freshness guard — fail CLOSED: a missing/malformed timestamp is treated as stale (a well-formed
# export always writes one, so a bad value means a corrupt/foreign store) rather than restored.
try:
    exported = datetime.datetime.strptime(p.get("exported_at",""), "%Y-%m-%dT%H:%M:%S").timestamp()
except Exception:
    sys.exit(0)
if time.time() - exported > max_age:
    sys.exit(0)

# Without a valid new-session id we cannot materialize the task files. Leave the carryover
# UNCONSUMED (so a later SessionStart with a real id can restore it) and just surface the list.
if not sid or sid == "-":
    _emit_context(p, tasks)
    sys.exit(0)

# only restore into an EMPTY new-session dir (never clobber live tasks)
dest = os.path.join(root, sid)
existing = glob.glob(os.path.join(dest, "*.json")) if os.path.isdir(dest) else []
if existing:
    sys.exit(0)  # session already has tasks — leave carryover armed, don't clobber or consume
os.makedirs(dest, exist_ok=True)
for t in tasks:
    tid = str(t.get("id", "")).strip()
    if not tid:
        continue
    # write the full task object back, ids/deps preserved
    with open(os.path.join(dest, f"{tid}.json"), "w") as f:
        json.dump(t, f, indent=2)

# mark consumed — only now that the files are actually written
p["consumed"] = True
p["consumed_into"] = sid
with open(carry, "w") as f:
    json.dump(p, f, indent=2)

_emit_context(p, tasks)
PY
exit 0
