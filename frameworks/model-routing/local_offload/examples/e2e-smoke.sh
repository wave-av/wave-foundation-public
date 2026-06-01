#!/usr/bin/env bash
# E2E dogfood smoke for the local-offload chassis.
# Boots the Anthropic frontend (offload ON) against a LOCAL backend, polls /health, then:
#   1) asserts the OFFLOAD path serves a trivial turn locally (NO frontier key needed) — the real proof
#   2) optionally runs `claude -p` if ANTHROPIC_API_KEY is set (its tool-bearing main turn passes
#      through to the frontier; trivial sub-turns offload — that's by design)
#
# Endpoint is env-driven so NO host/IP is committed. Point it at your backend:
#   WAVE_SMOKE_ENDPOINT=http://<host>:11434 WAVE_SMOKE_MODEL=<tag> ./e2e-smoke.sh
set -uo pipefail

ENDPOINT="${WAVE_SMOKE_ENDPOINT:-http://127.0.0.1:11434}"
MODEL="${WAVE_SMOKE_MODEL:-llama3.2}"
PORT="${WAVE_PROXY_PORT:-8188}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${HERE}/../.." && pwd)" # frameworks/model-routing
PROFILES="$(mktemp -t wave-smoke-profiles.XXXXXX.json)"
LOG="$(mktemp -t wave-smoke.XXXXXX.jsonl)"

cleanup() {
  [[ -n "${SHIM_PID:-}" ]] && kill "${SHIM_PID}" 2>/dev/null
  rm -f "${PROFILES}" "${LOG}"
}
trap cleanup EXIT

cat >"${PROFILES}" <<JSON
{
  "endpoints": {
    "local": {"base_url": "${ENDPOINT}", "api_style": "ollama", "model": "${MODEL}"},
    "frontier": {"base_url": "https://api.anthropic.com", "api_style": "anthropic", "model": "claude-sonnet-4-6", "api_key_env": "ANTHROPIC_API_KEY"}
  },
  "profiles": {
    "Fast": {"endpoint": "local", "temperature": 0, "max_tokens": 32, "timeout_s": 60, "fallback": ["Frontier"]},
    "Frontier": {"endpoint": "frontier", "max_tokens": 64, "fallback": []}
  }
}
JSON

echo "smoke: backend=${ENDPOINT} model=${MODEL} port=${PORT}"
(cd "${PKG_ROOT}" && PYTHONPATH=. WAVE_PROXY_PORT="${PORT}" \
  python3 -m local_offload.shim.run --anthropic --offload --profiles "${PROFILES}" --log "${LOG}") &
SHIM_PID=$!

# poll /health instead of a fixed sleep
for _ in $(seq 1 50); do
  if curl -fsS -m2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
if ! curl -fsS -m2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  echo "FAIL: shim did not become healthy on :${PORT}" >&2
  exit 1
fi

echo "== 1) offload path (no key) =="
RESP="$(curl -fsS -m60 "http://127.0.0.1:${PORT}/v1/messages" -H 'content-type: application/json' \
  -d '{"model":"claude-sonnet-4-6","max_tokens":16,"messages":[{"role":"user","content":"Reply with exactly one word: PONG"}]}')"
SERVED="$(printf '%s' "${RESP}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("usage") or {}).get("_served_by",""))' 2>/dev/null || true)"
TEXT="$(printf '%s' "${RESP}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("content") or [{}])[0].get("text",""))' 2>/dev/null || true)"
echo "   served_by=${SERVED:-?} text=${TEXT:0:40}"
if [[ "${SERVED}" != "local-offload" ]]; then
  echo "FAIL: trivial turn was not served locally (got: ${RESP:0:200})" >&2
  exit 1
fi
echo "   OK: trivial turn offloaded to local, no frontier key used"

echo "== 2) claude -p (optional) =="
if [[ -n "${ANTHROPIC_API_KEY:-}" ]] && command -v claude >/dev/null 2>&1; then
  ANTHROPIC_BASE_URL="http://127.0.0.1:${PORT}" claude -p "Reply with exactly one word: PONG" 2>&1 | head -5 || true
  echo "   (main turn passes through to frontier by design; see decision log)"
else
  echo "   skipped (set ANTHROPIC_API_KEY + install claude to run the full client path)"
fi

echo "== decision log =="
tail -5 "${LOG}" 2>/dev/null || true
echo "SMOKE PASS"
