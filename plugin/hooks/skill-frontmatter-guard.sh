#!/usr/bin/env bash
# PostToolUse(Write|Edit) guard: if a SKILL.md was just written, validate its frontmatter
# immediately so a bad edit is caught IN-SESSION (not days later in CI). This is the hook that
# would have surfaced the 2026-05-26 regression the moment it happened.
# Advisory-but-blocking: exit 2 feeds the reason back to Claude to self-correct. Degrades to a
# no-op if python3/pyyaml are unavailable (never breaks a session over missing tooling).
set -uo pipefail

HOOK_DATA=""
IFS= read -r -t 2 HOOK_DATA || true
[[ -z "$HOOK_DATA" ]] && exit 0

FILE_PATH=""
{ IFS= read -r FILE_PATH; } < <(printf '%s' "$HOOK_DATA" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('tool_input',{}).get('file_path', d.get('tool_response',{}).get('filePath','')))
except Exception:
    print('')
" 2>/dev/null)

[[ "$FILE_PATH" == *"/SKILL.md" || "$FILE_PATH" == "SKILL.md" ]] || exit 0
[[ -f "$FILE_PATH" ]] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
python3 -c "import yaml" 2>/dev/null || exit 0 # no validator available -> skip silently

ERR=$(
  python3 - "$FILE_PATH" <<'PY'
import sys,os,re,yaml
p=sys.argv[1]; d=os.path.basename(os.path.dirname(p))
t=open(p,encoding="utf-8",errors="replace").read()
m=re.match(r"^---\s*\n(.*?)\n---",t,re.S)
if not m: print("no frontmatter block"); sys.exit(0)
fm=m.group(1)
# duplicate top-level keys (yaml silently keeps last)
seen=set(); dup=set()
for line in fm.split("\n"):
    k=re.match(r"^([A-Za-z_][\w-]*):",line)
    if k: (dup if k.group(1) in seen else seen).add(k.group(1))
errs=[]
if dup: errs.append(f"duplicate frontmatter keys: {', '.join(sorted(dup))}")
try:
    data=yaml.safe_load(fm) or {}
except yaml.YAMLError as e:
    print(f"invalid YAML frontmatter: {e}"); sys.exit(0)
if not isinstance(data,dict): print("frontmatter is not a mapping"); sys.exit(0)
# WSC issue #45 reconciliation: drop name==dir equality (false-positives at scale with
# namespaced/category-prefixed skill dirs like `plugin:skill`). Replace with NAME format check.
NAME_RE = re.compile(r"^[a-z0-9_]+(?:[:-][a-z0-9_]+)*$")
DESC_MAX = 1536  # CC 2.1.105 raised SKILL desc cap 250 → 1536
name=data.get("name")
if not isinstance(name,str) or not NAME_RE.match(name):
    errs.append(f"name '{name}' not slug/namespace format (must match {NAME_RE.pattern})")
desc=data.get("description")
if not desc or not str(desc).strip(): errs.append("missing/empty description")
elif len(str(desc)) > DESC_MAX: errs.append(f"description {len(str(desc))} chars > {DESC_MAX} cap")
for key in ("allowed-tools","hooks"):
    if key in data:
        v=data[key]
        if v is None or (isinstance(v,(list,dict,str)) and len(v)==0):
            errs.append(f"'{key}' present but EMPTY")
print("; ".join(errs))
PY
)

if [[ -n "$ERR" ]]; then
  echo "SKILL.md frontmatter invalid ($FILE_PATH): $ERR" >&2
  exit 2
fi
exit 0
