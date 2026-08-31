#!/usr/bin/env bash
# Probe upstream ffmpeg for the two signals that gate WAVE task #170:
#   1. A tag of the form n8.[2-9]+ or n9.+ (8.2+, 9.x+).
#   2. The `--enable-libavm` flag landing in master's configure script.
#
# Pure shell + curl + grep — runs in any minimal CI image without extra deps.
# Output: a one-line cause + machine-readable exit code.
#
#   exit 0  → neither signal tripped (nothing to do)
#   exit 10 → 8.2+ tag exists upstream
#   exit 11 → libavm flag exists in master configure
#   exit 2  → upstream unreachable / unexpected response (don't trip the alarm)
#
# Why not parse ffmpeg.org/releases/: the static HTML reformats periodically
# and the failure mode is silent. The Git source-of-truth tag list and
# configure script are the canonical signals and don't reformat.

set -euo pipefail

# Development moved to code.ffmpeg.org (Forgejo) in 2025; github.com/FFmpeg/FFmpeg
# is now a downstream mirror. Poll the canonical Forgejo git remote for tags,
# and its raw-file endpoint for the configure script (verified: curl -sI
# https://code.ffmpeg.org/FFmpeg/FFmpeg/raw/branch/master/configure -> HTTP/2 200).
FFMPEG_GIT_URL="${FFMPEG_GIT_URL:-https://git.ffmpeg.org/ffmpeg.git}"
FFMPEG_RAW_URL="${FFMPEG_RAW_URL:-https://code.ffmpeg.org/FFmpeg/FFmpeg/raw/branch/master/configure}"
# --proto/--proto-redir pin both the initial request and any redirect target to
# HTTPS, so --location can never be downgraded to plain HTTP.
CURL_OPTS=(--silent --show-error --fail --location --proto '=https' --proto-redir '=https' --max-time 30 --user-agent "wave-codec-watch/1")

# ── tag check ───────────────────────────────────────────────────────────────
# `git ls-remote --tags` does a single TCP round-trip; we never clone.
# Pattern: refs/tags/n<major>.<minor>... — we want major>=8 with minor>=2,
# or any major>=9. The egrep is anchored so we don't false-trigger on n80.x.

tags=$(git ls-remote --tags "$FFMPEG_GIT_URL" 2>/dev/null || true)
if [ -z "$tags" ]; then
  echo "upstream unreachable: $FFMPEG_GIT_URL" >&2
  exit 2
fi

# Strip refs/tags/ prefix; drop ^{} dereference suffixes; keep nX.Y... names.
tag_names=$(echo "$tags" | awk '{print $2}' | sed 's|refs/tags/||; s|\^{}$||' | sort -u)

# Match n8.[2-9] or n8.[2-9].N or n[9-]+.Y...
qualifying_tag=$(echo "$tag_names" | grep -E '^n(8\.[2-9]|[9-9]+\.[0-9]+)([.\-].*)?$' | head -n1 || true)

if [ -n "$qualifying_tag" ]; then
  echo "found: tag $qualifying_tag"
  exit 10
fi

# ── configure-flag check ────────────────────────────────────────────────────
# Fetch master configure, look for `--enable-libavm` declared as a real option.
# We match against the option-list block, not docstrings, to avoid false
# positives from comments mentioning libavm.

configure=$(curl "${CURL_OPTS[@]}" "$FFMPEG_RAW_URL" || true)
if [ -z "$configure" ]; then
  echo "upstream unreachable: $FFMPEG_RAW_URL" >&2
  exit 2
fi

if echo "$configure" | grep -qE '^[[:space:]]*--enable-libavm[[:space:]]*\\?[[:space:]]*$|^[[:space:]]*libavm[[:space:]]*\)$'; then
  echo "found: libavm-flag"
  exit 11
fi

# Neither signal tripped.
echo "no-op: 8.2+ not tagged, libavm flag not in master configure"
exit 0
