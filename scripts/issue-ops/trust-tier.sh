#!/usr/bin/env bash
# trust-tier.sh <login> <author_association> -> owner|member|outside
#
# The IO_OWNER login is always 'owner'. Otherwise the author_association maps to
# 'member' only if it is in IO_TRUSTED_ASSOC; anything else is 'outside' (parked).
#
# IO_TRUSTED_ASSOC defaults to "OWNER MEMBER COLLABORATOR" (today's behavior).
# PUBLIC repos should TIGHTEN this — on a public repo COLLABORATOR is anyone ever
# invited to that repo and MEMBER is any org member, neither of which should
# auto-flow toward the runner/agent. Set IO_TRUSTED_ASSOC="" to trust only the
# IO_OWNER (everyone else parked for an explicit human go-ahead), or to a narrower
# set (security audit 2026-05-31, owner + insider lenses).
set -euo pipefail
# shellcheck source=scripts/issue-ops/lib.sh
source "$(dirname "$0")/lib.sh"

login="${1:?login required}"
assoc="${2:-NONE}"

if io::is_owner "$login"; then
  printf 'owner'
  exit 0
fi

# Note `${IO_TRUSTED_ASSOC-default}` (no colon): an explicitly empty value means
# "trust no association" and is honored, while unset falls back to the default.
trusted="${IO_TRUSTED_ASSOC-OWNER MEMBER COLLABORATOR}"
for a in $trusted; do
  if [ "$assoc" = "$a" ]; then
    printf 'member'
    exit 0
  fi
done
printf 'outside'
