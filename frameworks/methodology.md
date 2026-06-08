# Methodology Engine

The 20-method priority scoring system adapted from BurnRate's 105-method engine. Canonical registry: `methodology-registry.json` in this repo.

## How it works

```
PRIORITY = (Impact × Signal × FreshnessDecay) / Cost
```

Methods are scored and sorted. Run the highest-priority method that hasn't been run recently (FreshnessDecay penalizes recently-run methods). Track results in `methodology-cycles/`.

## The 20 methods (cross-project subset)

| ID | Name | Category | Impact | Cost | When to run |
|----|------|----------|--------|------|-------------|
| 1 | Single Source of Truth | architecture | 9 | 2 | When config drift is observed |
| 2 | DRY Audit | architecture | 7 | 2 | When duplication creeps in |
| 3 | SOLID for Scripts | architecture | 8 | 3 | When scripts grow complex |
| 4 | Documentation Coverage | content | 8 | 2 | After feature work |
| 5 | Cross-Reference Integrity | content | 9 | 2 | Before release |
| 6 | Security Audit | security | 10 | 2 | Every sprint |
| 7 | Error Handling Completeness | architecture | 7 | 2 | After new integrations |
| 8 | Convention Consistency | architecture | 7 | 1 | Periodically |
| 9 | Template Quality | content | 8 | 3 | When templates change |
| 10 | Hook Reliability | operations | 9 | 3 | After hook changes |
| 11 | Context Efficiency | performance | 8 | 2 | When CLAUDE.md grows |
| 12 | Dependency Audit | security | 6 | 1 | Monthly |
| 13 | Portability Check | architecture | 6 | 2 | Before sharing |
| 14 | Ollama Model Quality | operations | 7 | 3 | After Modelfile changes |
| 15 | User Feedback Loop | meta | 10 | 1 | Every session |
| 16 | Zero State Handling | operations | 7 | 2 | Before first-run scenarios |
| 17 | Automation Coverage | operations | 8 | 3 | Quarterly |
| 18 | Plugin Integration | operations | 6 | 2 | After plugin changes |
| 19 | Knowledge Capture | meta | 8 | 2 | At session end |
| 20 | Competitive Analysis | strategy | 5 | 2 | Quarterly |

Full data with `lastRun` and `findings` in `methodology-registry.json`.

## Running the engine

Drive the cycle from the registry: pick the highest-priority method that hasn't run
recently, run it, then record the result back into the registry (`lastRun` + `findings`).
A consuming repo wires this up with a small helper — a `methodology-cycle` script or a
`methodology-audit` skill — exposing:

```text
next      # which method to run next (highest priority × staleness)
record    # record a run result against a method
history   # view recent cycle history
```

## Project adaptation

The registry is tuned for tooling/config repos. For product repos, adapt:

- Replace method 14 (Ollama Model Quality) with relevant domain-specific method
- Raise threshold for "run recently" (larger teams move faster)
- Add product-specific categories (payments, streaming, auth)

Some product repos run their own more advanced methodology engine (a pipeline-discipline skill) with a separate implementation.

## Dogfood law

Same as all frameworks: a method we don't run ourselves is a draft, not a method.
