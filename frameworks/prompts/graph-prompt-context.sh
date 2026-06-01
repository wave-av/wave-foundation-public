#!/usr/bin/env bash
# Graph Prompt Context — UserPromptSubmit hook
# Extracts entity names (PascalCase services, file paths) from user prompt,
# queries graph for blast radius, injects scope warnings. Pure bash, <50ms.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/graph-query-helper.sh" 2>/dev/null || exit 0
_graph_available || exit 0

HOOK_DATA=""
IFS= read -r -t 1 HOOK_DATA || true
[[ -z "$HOOK_DATA" ]] && exit 0

ENTITIES=$(echo "$HOOK_DATA" | python3 -c "
import json,sys,signal,re
signal.alarm(2)
try:
    d = json.load(sys.stdin)
    p = d.get('user_prompt', d.get('prompt', d.get('content', '')))
    if not p:
        for m in d.get('messages', []):
            if m.get('role') == 'user': p = m.get('content', '')
    ents = re.findall(r'[A-Z][a-zA-Z]{8,}(?:Service|Controller|Handler|Manager|Provider|Client|Store|Cache)', p)
    paths = re.findall(r'[a-zA-Z0-9/_-]+\.(?:ts|tsx|py)', p)
    print(' '.join(set(ents + paths)))
except: pass
" 2>/dev/null) || exit 0
[[ -z "$ENTITIES" ]] && exit 0

CTX=""
for e in $ENTITIES; do
  r=$(graph_risk_detail "$e")
  [[ -z "$r" || "$r" == *"0 callers, 0 deps"* ]] && continue
  CTX="${CTX}${e}: ${r}. "
done
[[ -z "$CTX" ]] && exit 0

python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput':{'hookEventName':'UserPromptSubmit','additionalContext':'[Graph Scope] '+sys.argv[1]}}))" "$CTX" 2>/dev/null || exit 0
exit 0
