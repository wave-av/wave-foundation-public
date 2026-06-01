#!/usr/bin/env bash
# lease.sh — a lightweight, git-native lease so concurrent agents/sessions don't collide on the same work.
#
# WHY: multiple Claude sessions operate on the same repos at once. With no coordination they independently
# start overlapping work — two release PRs for the same version, two branches fixing the same file, a
# retarget that strands another session's PR. This session hit exactly that (a near-duplicate v1.7.0
# release). A lease lets a session ANNOUNCE "I'm working <branch>/PR#<n>" and lets the next session SEE
# that before starting — turning silent collisions into an explicit, checkable signal.
#
# HOW (atomic, no extra service): a lease is a git ref `refs/agent-leases/<slug>` created via the GitHub
# API. Ref creation is ATOMIC — POST .../git/refs returns 422 if the ref already exists — so two agents
# racing the same claim cannot both win. The ref points at an annotated tag object whose message carries
# the metadata (who/branch/pr/when/ttl), so `list` shows holders, age, and expiry. Custom `refs/agent-leases/*`
# is NOT fetched by `git fetch` by default, so leases stay out of everyone's tag/branch lists.
#
# This is a COORDINATION AID, not a hard mutex: a stale lease past its TTL is auto-pruned on the next
# claim/list. Treat a live lease as "ask/coordinate before overlapping", and always `release` when done.
#
# Usage:
#   lease.sh claim  <branch> [--pr N] [--ttl MIN] [--agent ID] [--note TEXT]   # atomic; nonzero if held
#   lease.sh release <branch>                                                  # drop your lease
#   lease.sh list                                                              # all active leases
#   lease.sh mine [--agent ID]                                                 # leases held by you
#   lease.sh prune                                                             # delete expired leases
#   lease.sh doctor                                                            # local self-check (no API writes)
#
# Env: LEASE_AGENT_ID (default: $USER@$(hostname -s)), GH_REPO (default: gh-detected nameWithOwner).
# Requires: gh (authenticated), python3. Exit codes: 0 ok · 2 usage/env · 3 lease held by someone else.
set -euo pipefail

die() { echo "lease: error: $*" >&2; exit 2; }
held() { echo "lease: HELD: $*" >&2; exit 3; }

command -v gh >/dev/null 2>&1 || die "gh CLI not installed/authenticated"
command -v python3 >/dev/null 2>&1 || die "python3 not installed"

AGENT_ID="${LEASE_AGENT_ID:-${USER:-unknown}@$(hostname -s 2>/dev/null || echo host)}"
DEFAULT_TTL=120   # minutes; a lease older than this is considered abandoned and is auto-pruned

# slugify a branch name into a safe ref component: keep [A-Za-z0-9._-], collapse the rest to '-'.
slug() { printf '%s' "$1" | python3 -c 'import re,sys; print(re.sub(r"[^A-Za-z0-9._-]+","-", sys.stdin.read().strip()).strip("-") or "unnamed")'; }

repo() { echo "${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"; }

# epoch-now without Date.now restrictions (this is a normal shell, not a Workflow script).
now() { date -u +%s; }

# Default-branch tip sha — every lease tag-object points here (the object is irrelevant; we only use the
# tag MESSAGE for metadata, but the API requires a real object sha that exists on the remote).
anchor_sha() {
  local r="$1" db
  db="$(gh api "repos/$r" -q .default_branch)"
  gh api "repos/$r/git/ref/heads/$db" -q .object.sha
}

# Read one lease's metadata JSON (the tag-object message) given its ref object sha. Empty on any failure.
lease_meta() { gh api "repos/$1/git/tags/$2" -q .message 2>/dev/null || true; }

# Print all active leases as TSV: slug<TAB>json. Auto-skips refs whose tag object can't be read.
_each_lease() {
  local r="$1" ref objsha slugname
  gh api "repos/$r/git/matching-refs/agent-leases/" \
    -q '.[] | [.ref, .object.sha] | @tsv' 2>/dev/null | while IFS=$'\t' read -r ref objsha; do
      slugname="${ref#refs/agent-leases/}"
      printf '%s\t%s\n' "$slugname" "$(lease_meta "$r" "$objsha")"
    done
}

# expired? <json> -> exit 0 if past ttl
_expired() {
  python3 - "$1" "$(now)" <<'PY'
import json,sys
try: m=json.loads(sys.argv[1] or "{}")
except Exception: sys.exit(0)            # unparseable → treat as expired (cleanable)
ttl=int(m.get("ttl_min",120))*60
sys.exit(0 if (int(sys.argv[2]) - int(m.get("claimed_at",0))) > ttl else 1)
PY
}

_fmt() {  # pretty one-liner from slug + json
  python3 - "$1" "$2" "$(now)" <<'PY'
import json,sys
slug,raw,now=sys.argv[1],sys.argv[2],int(sys.argv[3])
try: m=json.loads(raw or "{}")
except Exception: m={}
age=(now-int(m.get("claimed_at",0)))//60 if m.get("claimed_at") else "?"
ttl=m.get("ttl_min",120)
exp=" EXPIRED" if isinstance(age,int) and age>int(ttl) else ""
pr=f" PR#{m['pr']}" if m.get("pr") else ""
note=f" — {m['note']}" if m.get("note") else ""
print(f"  [{m.get('agent','?')}] {m.get('branch',slug)}{pr}  ({age}m ago, ttl {ttl}m){exp}{note}")
PY
}

cmd="${1:-}"; shift || true
case "$cmd" in
  claim)
    branch="${1:-}"; shift || true
    [ -n "$branch" ] || die "usage: lease.sh claim <branch> [--pr N] [--ttl MIN] [--agent ID] [--note TEXT]"
    pr=""; ttl="$DEFAULT_TTL"; note=""
    while [ $# -gt 0 ]; do case "$1" in
      --pr) pr="$2"; shift 2;; --ttl) ttl="$2"; shift 2;;
      --agent) AGENT_ID="$2"; shift 2;; --note) note="$2"; shift 2;;
      *) die "unknown flag: $1";; esac; done
    r="$(repo)"; s="$(slug "$branch")"; ref="refs/agent-leases/$s"

    # auto-prune an expired lease for this slug so an abandoned session never blocks forever.
    existing="$(_each_lease "$r" | awk -F'\t' -v s="$s" '$1==s{print $2}')"
    if [ -n "$existing" ]; then
      if _expired "$existing"; then
        gh api -X DELETE "repos/$r/git/refs/agent-leases/$s" >/dev/null 2>&1 || true
      else
        echo "lease: $branch is already leased:" >&2
        _fmt "$s" "$existing" >&2
        held "coordinate with the holder (or wait for its TTL) before overlapping"
      fi
    fi

    meta="$(python3 - "$AGENT_ID" "$branch" "$pr" "$ttl" "$note" "$(now)" <<'PY'
import json,sys
a,b,pr,ttl,note,ts=sys.argv[1:7]
print(json.dumps({"agent":a,"branch":b,"pr":pr,"ttl_min":int(ttl),"note":note,"claimed_at":int(ts)},separators=(",",":")))
PY
)"
    tagsha="$(gh api -X POST "repos/$r/git/tags" -f tag="agent-lease/$s" -f message="$meta" -f object="$(anchor_sha "$r")" -f type=commit -q .sha)"
    # ATOMIC create — fails (nonzero) if the ref already exists (someone won the race in between).
    if gh api -X POST "repos/$r/git/refs" -f ref="$ref" -f sha="$tagsha" >/dev/null 2>&1; then
      echo "lease: ✓ claimed $branch as [$AGENT_ID] (ttl ${ttl}m). Release with: lease.sh release $branch"
    else
      cur="$(_each_lease "$r" | awk -F'\t' -v s="$s" '$1==s{print $2}')"
      echo "lease: lost the race for $branch:" >&2; _fmt "$s" "$cur" >&2
      held "another agent claimed it first"
    fi
    ;;
  release)
    branch="${1:-}"; [ -n "$branch" ] || die "usage: lease.sh release <branch>"
    r="$(repo)"; s="$(slug "$branch")"
    if gh api -X DELETE "repos/$r/git/refs/agent-leases/$s" >/dev/null 2>&1; then
      echo "lease: ✓ released $branch"
    else
      echo "lease: no active lease for $branch (already released or never claimed)"
    fi
    ;;
  list)
    r="$(repo)"; any=0
    while IFS=$'\t' read -r s j; do [ -z "$s" ] && continue; any=1; _fmt "$s" "$j"; done < <(_each_lease "$r")
    [ "$any" = 1 ] || echo "lease: no active leases on $r"
    ;;
  mine)
    while [ $# -gt 0 ]; do case "$1" in --agent) AGENT_ID="$2"; shift 2;; *) shift;; esac; done
    r="$(repo)"; any=0
    while IFS=$'\t' read -r s j; do
      [ -z "$s" ] && continue
      echo "$j" | python3 -c 'import json,sys; m=json.load(sys.stdin); sys.exit(0 if m.get("agent")==sys.argv[1] else 1)' "$AGENT_ID" 2>/dev/null && { any=1; _fmt "$s" "$j"; }
    done < <(_each_lease "$r")
    [ "$any" = 1 ] || echo "lease: you ([$AGENT_ID]) hold no leases on $r"
    ;;
  prune)
    r="$(repo)"; n=0
    while IFS=$'\t' read -r s j; do
      [ -z "$s" ] && continue
      if _expired "$j"; then gh api -X DELETE "repos/$r/git/refs/agent-leases/$s" >/dev/null 2>&1 && { n=$((n+1)); echo "lease: pruned expired $s"; }; fi
    done < <(_each_lease "$r")
    echo "lease: pruned $n expired lease(s)"
    ;;
  doctor)
    # Local self-check: no API writes. Validates deps, slug logic, and JSON round-trips.
    echo "agent: $AGENT_ID"
    echo "slug('feat/Foo Bar#1') = $(slug 'feat/Foo Bar#1')   (expect feat-Foo-Bar-1)"
    _expired '{"claimed_at":1,"ttl_min":1}' && echo "expiry check: ✓ ancient lease reads EXPIRED" || echo "expiry check: ✗"
    _expired "{\"claimed_at\":$(now),\"ttl_min\":120}" || echo "expiry check: ✓ fresh lease reads ACTIVE"
    echo "repo (gh-detected): $(repo 2>/dev/null || echo '<run inside a gh repo>')"
    echo "doctor: ok"
    ;;
  *)
    die "usage: lease.sh {claim|release|list|mine|prune|doctor} ... (see header)"
    ;;
esac
