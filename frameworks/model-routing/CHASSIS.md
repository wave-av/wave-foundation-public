# Local-Offload Chassis

Reusable, pure-stdlib local-first router/proxy extracted from `wave-av/wave-dispatch`. It is the
runnable implementation of tiers 1→4 in [`README.md`](./README.md): start at the cheapest local
tier, escalate to a hosted frontier only on structured failure.

Importable as `local_offload` (the dir is hyphenated, so the package is the underscore subdir):

```bash
PYTHONPATH=<repo>/frameworks/model-routing python -m local_offload.shim.run --all --profiles my-profiles.json
```

## Three deliverables

### 1. Declarative named-profile router (`local_offload/profiles/`)

`Fast / Expert / Heavy / Code` profiles (+ your own), each binding `temperature + max_tokens +
timeout` to a **named endpoint** (local OR hosted) with an ordered **fallback chain**. The default
chain is `local → Heavy(local) → Frontier(hosted)` — only `Frontier` leaves your machine.

```python
from local_offload.profiles import ProfileRouter
r = ProfileRouter.from_file("profiles.json")
r.run("Fast", request, call)            # tries Fast's endpoint, walks fallback on structured failure
```

Config is JSON-Schema-shaped (`profiles/schema.json`) and validated by a hand-rolled zero-dep
loader. See `profiles/profiles.default.json` for the shipped defaults and the temperature map.

### 2. Multi-frontend drop-in shim (`local_offload/shim/`)

One engine, presented simultaneously in three wire formats so existing agents connect **unmodified**:

| Frontend | Port | Client |
|---|---|---|
| Anthropic Messages | `8088` | Claude Code (`ANTHROPIC_BASE_URL`) |
| OpenAI Chat Completions | `8090` | Codex / Cursor / aider (`OPENAI_BASE_URL`) |
| Ollama API (`/api/chat,generate,tags`) | `11434` | Cline / Kilo / Droid |

The `Engine` seam (`shim/engine.py`) lets any backend serve: ships `OllamaEngine`
(OpenAI-compatible, covers Ollama/vLLM/llama.cpp), `AnthropicEngine`, and `ProfileRouterEngine`
(routes through a profile's fallback chain). Inject your own to present *anything*.

> `AnthropicEngine` is the **reference implementation of the [`frameworks/claude-api`](../claude-api/README.md)
> request-shape standard**: it drops `temperature`/`top_p`/`top_k` for Opus 4.8/4.7 (they 400), sets
> `thinking:{adaptive}` + `output_config.effort`, pins a current API version, streams large outputs,
> and caches the system prefix. Carries a `claude-api-lint: skip` header because it names those params
> by design to strip them. When editing the frontier hop, follow [`model-matrix.md`](../claude-api/model-matrix.md) —
> the `claude-api-shape` gate enforces it everywhere else.

### 3. Hybrid escalate-to-frontier (`local_offload/escalation/`)

- `cost_decision` — decision-theoretic breakeven: escalate iff expected cost of local exceeds the
  price of a frontier call (no magic threshold; breakeven ≈ 0.37 at default cost units). Includes a
  Free-Energy variant that adds an epistemic penalty for uncertainty.
- `cascade` — calibrated-margin rule: classifier fast-path when confident, else escalate. sklearn-free
  (classifier + escalation target injected as callables; conformal supported via an injected predicate).

## The honest-design invariant (load-bearing)

Every frontend **defaults to passthrough** and **falls through to the real upstream on ANY local
error** — before response headers are sent. Offload can only save money, it can never break the agent
loop. This is asserted by the non-skippable `tests/test_shim_passthrough.py` and gates merge.

Offload is **OFF by default** (`WAVE_PROXY_OFFLOAD` unset = passthrough + measure). Watch `proxy.jsonl`
before enabling.

## Quick start / dogfood

```bash
cd frameworks/model-routing
# 1. boot the Anthropic frontend (offload ON) against your local backend
WAVE_PROXY_OFFLOAD=1 PYTHONPATH=. python -m local_offload.shim.run --anthropic --profiles my-profiles.json
# 2. point Claude Code at it (opt-in, reversible)
ANTHROPIC_BASE_URL=http://localhost:8088 claude
```

Trivial turns (no tools, single short user message) are served locally with **no frontier key**.
Tool-bearing / multi-turn main turns pass through to the frontier (they need a real key) — by design.
The `examples/e2e-smoke.sh` harness proves the offload path end-to-end (health-polled, env-driven
endpoint, asserts `served_by=local-offload`).

## Consuming in a spoke

Vendor `frameworks/model-routing/` read-only via the standard `CONSUME.md` path, then:

1. Keep your own `profiles.json` in your repo (the shipped defaults are a template, not live config).
2. `PYTHONPATH=.foundation/frameworks/model-routing python -m local_offload.shim.run …`
3. Supply hosted keys via env (the endpoint's `api_key_env` names the var; values never live in config).

Because the chassis is **additive and opt-in-by-import**, a spoke that doesn't import it is unaffected.

## Testing

`python -m pytest local_offload/tests` — 32 tests: profile resolution/fallback/cycle-guard/schema
rejection; cost/cascade math; the passthrough invariant across all three frontends; golden wire
formats (Anthropic SSE order, OpenAI stream, Ollama NDJSON). All offline (transport injected).

## Provenance & credits

Extracted from `wave-av/wave-dispatch` (`proxy.py`, `openai_proxy.py`, `cost_decision.py`,
`cascade_router.py`). The Ollama frontend models the public API shape of
[`spoonnotfound/fake-ollama`](https://github.com/spoonnotfound/fake-ollama) (MIT) — credited, not
vendored. Non-goals (kept in the engine, by design): ML training (sklearn/DSPy/GEPA/bandit/conformal),
vLLM/serving substrate, multimodal, and any hardware-specific quantization.
