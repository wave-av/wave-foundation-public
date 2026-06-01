# Frameworks

The executable + procedural patterns proven on BurnRate + dispatch, made portable.

## Eval gate (pre-commit)

A hook that blocks commits failing the project's eval suite. Dispatch's also enforces **file size**
(800 hard / 500 soft — see `rules/build-conventions.md`). One source here; projects symlink it.

## Hooks pack

- `pre-commit` → eval gate + secret-scan.
- `Stop`/goal hooks → autonomous-completion loops (use deliberately; always provide an off-ramp).
- prompt-refine hook → local LLM cleans/structures the prompt before it hits the model.

## CI review

Automated PR review (CodeRabbit / the pr-review-toolkit agents) wired per repo from one config.

## Methodology registry

`methodology-registry.json` is the canonical registry — a method-priority engine adapted per repo
type. See [`methodology.md`](methodology.md) for how to run the cycle.

## Troubleshooting runbook

`troubleshooting/` — cross-project gotchas with root cause + fix: Claude Code errors (deferred-skill
`cache_control`, plan-skill empty response, CC 2.1.27 gateway validation) and common dev failures
(GitHub secrets HTTP 400, Next.js build lock, optimization regressions). Start at
`troubleshooting/INDEX.md`. Promoted from the harvest as generic, foundation-level knowledge.

## Prompt-context hooks

`prompts/` — cross-project Claude Code lifecycle hooks that **safely inject context** into prompts
(SessionStart, UserPromptSubmit). Three reference patterns: `session-start-context.sh`,
`lifecycle-prompt-preprocess.sh`, `graph-prompt-context.sh`. See `prompts/README.md`.

## Security review workflow

`security/security-review-workflow.md` — combined security analysis (Corridor for plan/threat
modeling + Serena for AST-aware code analysis) for PR + feature review. Vendor-neutral; promoted
from the WSC harvest. Pairs with the security gates in `.github/workflows/` (zizmor, pinact,
secret-scan).

## Build on WAVE — meta-dogfood positioning

`build-on-wave/` — the strategic claim that **everything WAVE customers can build, we built first.** Maps each public SDK + spoke + operator app to (a) something WAVE runs in production, and (b) something a customer or AI agent can replicate from public APIs. Includes the canonical "signal everywhere" landing-page spec (`signal-everywhere.md`) and a machine-readable repo manifest (`repo-manifest.json`) listing every Layer-0/1/2/3/4 surface with license + SDK + role. Pairs with `protocol-plane/` (the five-layer architecture this argument rests on) and `pricing/` (same model across every layer).

## Claude API standard

`claude-api/` — how every WAVE surface uses the Claude API correctly. Default model `claude-opus-4-8`.
Per-model constraints + the fix for each (`model-matrix.md`), prompt caching, thinking/effort, batch
(50%, **not ZDR**), the full tool-use family, files/media, context management, **per-user WIF tokens +
usage attribution** (`identity-and-usage.md`), the Admin API, cloud-platform deltas, and **local-vs-hosted**
routing (`local-inference.md`). `COVERAGE.md` maps the entire Anthropic doc surface (from `llms.txt`) to
covered / N-A / TODO; `reference/` is a pinned doc snapshot (refresh via `refresh-docs.sh`). Pairs with
`model-routing/` — the Leveragizer tier this standard's frontier hop runs through. Vendored into spokes by
`consume.sh` like every other framework here.

## Dogfood law

Every framework here must be one we actually run. If it's not enabled in at least dispatch + one other
project, it's a draft, not a framework.
