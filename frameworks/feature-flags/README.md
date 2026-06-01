# Feature Flags Framework

Feature flags decouple deploy from release: code ships dark, gets exposed to a fraction of traffic, expands when stable. The cost: every flag is a branch in the codebase + an external service in the request path. This doc codifies which tool fits which scale and when flags actually pay for themselves.

## When a flag is worth its weight

Use a flag when:

1. **Risk per release is high** — payment-flow changes, schema migrations, anything where a 1% blast-radius is meaningfully better than 100%
2. **Rollout is gradual** — you want to expose at 1% → 10% → 50% → 100% over hours/days
3. **A/B test of UX or pricing** — you need stratified randomization + statistical comparison
4. **Kill-switch** — you need to disable a feature in seconds without a deploy

Don't use a flag when:

- The feature is binary (everyone gets it or no-one does on next deploy) — that's just a deploy
- The branch will live > 90 days — that's tech debt accumulating two codepaths

## Tool choice

| Tool | Best for | Cost | Notes |
|------|----------|------|-------|
| **PostHog** | WAVE default — already in stack for product analytics | $0–free tier covers 1M events/mo | Same project owns flags + analytics + replay → A/B tests cohere |
| **GrowthBook** | Self-host bias / GitOps for flags | $0 (self-host) / paid SaaS | YAML-defined flags, GitOps workflow. Best when "flag changes need PR review" is required |
| **LaunchDarkly** | Enterprise scale, complex targeting rules | $$$$ (per-seat + per-MAU) | Heaviest feature set. Worth it at 100M+ MAU with deep segmentation needs |
| **Unleash** | OSS, self-host, mature SDK | $0 (self-host) | Functional but less integrated than PostHog for typical WAVE stack |
| **Hardcoded env var** | Short-lived kill-switches | $0 | Re-deploy is acceptable. NOT for rollouts. |

## The WAVE default: PostHog

Why:

1. PostHog is already in most WAVE consumer stacks (analytics + session replay)
2. Free tier covers typical traffic
3. **Same project** for flags + analytics means A/B tests have built-in metrics integration
4. SDK quality: official JS/Python/Go SDKs with bootstrap support for SSR/edge

Trade-off: GitOps purists prefer GrowthBook (YAML-defined flags reviewed via PR). For WAVE's velocity-first culture, the dashboard-driven workflow is fine.

## The hard rules

1. **Every flag has an end-of-life date.** Add `eol:` to the flag description in your tool of choice. Past EOL = mandatory cleanup.
2. **Stale flag detection runs weekly.** See `frameworks/feature-flags/check-stale-flags.md` (when wired).
3. **Server-side default = current behavior.** A flag-fetch failure must fall through to "feature off" or "current behavior" — never the new thing.
4. **No flag in a kernel module / hot path.** Anywhere the flag-fetch latency matters more than the rollout safety, hardcode and ship via deploy.

## Boundaries: when NOT to flag

| Class | Do | Don't |
|-------|----|----|
| Auth tokens / session keys | hardcode + deploy | flag |
| Schema migrations | feature-flag the consuming code, not the schema | flag the migration |
| Pricing | flag (A/B test legitimate) | flag for stealth |
| Security fixes | hardcode + deploy ASAP | flag |
| Tracking IDs / pixel | hardcode + deploy | flag |

## Cleanup discipline

A flag is debt. Two markers indicate it's time to remove:

1. **Rollout = 100% for > 14 days** with no regressions → remove the flag, hardcode the new path, deploy
2. **Rollout = 0% for > 30 days** → the feature was abandoned; remove the flag, remove the new path

A flag stale-finder (PostHog API → "flags not toggled in 90 days") can post to Slack / open issues automatically. See `frameworks/feature-flags/stale-flag-finder.md` (when wired).

## Cross-references

- [`docs/threat-model.md`](../../docs/threat-model.md) — flags are NOT a substitute for the auth/spend-authority gates
- [`frameworks/secrets-management/README.md`](../secrets-management/README.md) — flag-fetch API tokens go in Doppler
- [`frameworks/methodologies/README.md`](../methodologies/README.md) — methodology #17 (Automation Coverage) — flag-stale checks add to the surface
