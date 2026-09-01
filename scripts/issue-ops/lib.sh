#!/usr/bin/env bash
# shellcheck shell=bash
# lib.sh — shared helpers for issue-ops. Source me; don't execute.
set -euo pipefail

# Repo owner login (override in tests / CI via IO_OWNER).
IO_OWNER="${IO_OWNER:-yakimoto}"

# io::log <msg...> — stderr progress line.
io::log() { printf '[issue-ops] %s\n' "$*" >&2; }

# io::slug <text> — lowercase, non-alnum -> single dash, trim dashes.
io::slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# io::is_owner <login> — exit 0 if login is the repo owner.
io::is_owner() { [ "$1" = "$IO_OWNER" ]; }
