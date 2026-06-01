# Champions Registry & Capability Graph

**Applies when:** deciding which local model handles a request, or wiring a spoke to the
fleet. `champions.json` is the **single source of truth** the [routing chassis](./CHASSIS.md)
and [wave-dispatch](https://github.com/wave-av/wave-dispatch) read. Spokes consume it; they
never re-tune or hardcode model names. Seeded by the bench ([tuning-methodology.md](./tuning-methodology.md)).

## The 7 axes (capability taxonomy)

The 2025–26 literature rewards these with *distinct* techniques, so they are distinct axes:

| Axis | Covers | Distinct technique |
|---|---|---|
| `quantitative-reasoning` | math + physics + scientific calc | long-CoT distilled bases |
| `code` | write/edit/refactor/transform | RLVR signal strongest (compiler/tests = verifier) |
| `semantic-symbolic` | tool-use, structured/JSON, neuro-symbolic | grammar-constrained decoding |
| `agentic-tool-calling` | multi-turn plan+act | multi-turn credit assignment |
| `retrieval-grounding` | RAG faithfulness, anti-hallucination | grounding/faithfulness metric |
| `long-context` | large-context comprehension | ctx-window + no-truncation |
| `behavioral-values` | WAVE steering + moderation posture | SYSTEM contract (universal — see steering.md) |

`behavioral-values` is universal (every model carries it). The other 6 are performance axes —
selective, gated by the GEPA band (0.50–0.80 on real traffic).

## Three relationship modes — how models work together

A model can play any of these per request:

| Mode | Meaning | Mechanism |
|---|---|---|
| **interchangeable** | many models satisfy one axis → pick one | bandit / cheapest-that-passes over `axes[*].champions` |
| **dependent (escalation)** | required quality exceeds the cheap tier → escalate | `cost_decision` + `conformal` ambiguity set → `escalate_to` |
| **composable (pipeline)** | task needs multiple capabilities in sequence | orchestrator chains axis-champions per `pipelines` |

## The decision funnel (one path, per request)

```
request → classify {axis,difficulty,confidence} (wave-router, ~30ms JSON)
        → conformal: singleton set? yes → proceed | no (ambiguous) → escalate
        → single axis → interchangeable pick (bandit) | multi → composable pipeline
        → cost-check each hop (E[local] vs E[escalate])
        → run → verify-gate (eval_gate dangerous==0) → on fail, escalate (never silent-direct)
        → log verdict-delta (real-traffic signal → bandit reward + recalibration)
```

Every step is an existing dispatch component; the registry just declares the graph.

## Schema (`champions.json`)

```jsonc
{
  "version": "x.y.z", "calibrated_at": "ISO", "calibration": "real-traffic|pilot",
  "endpoint": { "studio": "http://100.92.89.55:11434", "fallback": "anthropic/claude-haiku-4-5" },
  "axes": {
    "<axis>": {
      "bar": 0.80, "escalate_to": "claude_reason",
      "champions": [ { "model": "...", "base_digest": "sha256-…",  // pinned (adapter base-match)
                       "size_b": 30.5, "acc": 0.93, "ci_lb": 0.88, "lat_s": 2.3 } ]  // ranked
    }
  },
  "bases":    { "<family>": { "digest": "sha256-…", "role_clone_count": 25 } },
  "overlays": { "wave-stripe": { "base": "<family>", "system_ref": "overlays/stripe.txt" } },
  "pipelines":{ "pr-audit": ["retrieval-grounding","code","behavioral-values"] },
  "fallback": "anthropic/claude-haiku-4-5",      // dispatch-unreachable = never a hard block
  "ops_flags":{ "<model>": "BROKEN — reason; excluded" }
}
```

## Consolidation rule (bases + overlays, not a flat list)

Role-specialized models that share a base blob are **base + SYSTEM overlay**, NOT separate
champions. (E.g. on the current Studio fleet, 38 `wave-*` role-models collapse to **5 base
blobs** + overlays.) The registry stores 5 bases + N overlay refs, not 38 full models — this
is the anti-sprawl invariant. Champion-vs-redundant among *distinct* bases is decided by the
bench, not by hand.

## Integrity (anti-drift)

- `base_digest` MUST pin the exact deployed blob. Consumers assert **deployed == source hash**
  (the [CONSUME.md](../../CONSUME.md) attestation pattern) — this kills the on-disk↔deployed
  drift class. A stale `FROM` or a divergent on-disk Modelfile fails the attestation.

## Severity

| Violation | Severity |
|---|---|
| Hardcoding a model name/endpoint instead of reading the registry | Major |
| Champion row without a pinned base_digest | Major |
