#!/usr/bin/env bash
# studio-batch-eval.sh — run the 0-cost local batch-eval loop on Studio (task #21).
#
# $0 marginal cost: every case runs against LOCAL Ollama models on the Mac Studio — no Claude, no
# egress. Intended to run unattended (cron/launchd) so champion models are continuously re-verified
# on real eval cases; the JSON report feeds the champions.json reseal loop.
#
# Usage (on Studio, or over SSH with OLLAMA_HOST set to the Studio Tailscale IP):
#   OLLAMA_HOST=http://100.92.89.55:11434 \
#   MODELS="wave-qwen3-coder-30b,wave-deepseek-r1-32b,wave-granite4" \
#   bash studio-batch-eval.sh [cases.jsonl]
#
# Writes the report to $OUT_DIR/batch-eval-<utc-date>.json and exits non-zero if any model scored 0
# on a non-empty batch (so a cron wrapper can alert). No secrets, no network beyond the local backend.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROUTING_ROOT="$(cd "$HERE/../.." && pwd)"   # frameworks/model-routing (so `python -m local_offload...` resolves)
CASES="${1:-$HERE/eval-cases.sample.jsonl}"
MODELS="${MODELS:-wave-qwen3-coder-30b}"
BASE="${OLLAMA_HOST:-http://100.92.89.55:11434}"
OUT_DIR="${OUT_DIR:-$HOME/.wave/batch-evals}"

command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 2; }
[ -f "$CASES" ] || { echo "cases file not found: $CASES" >&2; exit 2; }
mkdir -p "$OUT_DIR"

# date without args is fine here (this is a normal shell, not a Workflow script).
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$OUT_DIR/batch-eval-$stamp.json"

echo "→ batch-eval: models=[$MODELS] base=$BASE cases=$CASES" >&2
set +e
( cd "$ROUTING_ROOT" && python3 -m local_offload.batch_eval "$CASES" --models "$MODELS" --base "$BASE" ) | tee "$out"
rc="${PIPESTATUS[0]}"
set -e

echo "→ report: $out (exit $rc; 0=all models scored >0, 1=a model scored 0)" >&2
exit "$rc"
