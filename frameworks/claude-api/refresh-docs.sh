#!/usr/bin/env bash
# Re-pull the Anthropic docs snapshot that backs frameworks/claude-api. Idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REF="$HERE/reference"
curl -s --max-time 20 https://platform.claude.com/llms.txt -o /tmp/claude-llms.txt
{ for s in build-with-claude agents-and-tools managed-agents manage-claude api/messages api/models api/admin about-claude/models; do
    grep -oE "https://platform\.claude\.com/docs/en/${s}[a-zA-Z0-9/_-]*" /tmp/claude-llms.txt; done; } | sort -u > /tmp/_refresh_urls.txt
while IFS= read -r u; do rel="${u#https://platform.claude.com/docs/en/}"; d="$REF/$rel.md"; mkdir -p "$(dirname "$d")"
  curl -s --max-time 25 -o "$d" "$u.md" || rm -f "$d"; sleep 0.15; done < /tmp/_refresh_urls.txt
date -u +%Y-%m-%d > "$REF/.refreshed"; echo "refreshed $(find "$REF" -name '*.md'|wc -l) pages"
