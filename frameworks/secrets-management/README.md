# Secrets Management Framework

The choice of secrets-storage system shapes incident blast-radius and rotation friction. This doc compares the four real options for WAVE-stack repos and codifies which to pick for which use-case.

## Storage choices

| Tool | Best for | Cost | Rotation | Notes |
|------|----------|------|----------|-------|
| **Doppler** | Multi-env, multi-app (preferred for WAVE) | $0–14/user | CLI + dashboard | Already used by dispatch + wave-foundation consumers. Per-config inheritance, audit trail, GitHub Action sync. |
| **1Password** | Personal/team-shared dev creds | $0 (personal) – $8/user | manual | Best for human dev creds (SSH keys, AWS console). Service Account API for CI. |
| **HashiCorp Vault** | High-scale, multi-cloud, dynamic creds | Self-host (free) / paid Cloud | API + dynamic | Heaviest setup. Worth it if you need dynamic DB creds (per-pod, 1-hour TTL). |
| **AWS Secrets Manager / GCP Secret Manager** | Cloud-vendor lock-in OK | $0.40/secret/month + reads | rotation hooks | Lowest friction inside a single cloud. Cross-cloud is painful. |
| **GitHub Actions secrets** | CI-only consumption | $0 | manual rotate | Adequate for CI tokens that NEVER reach prod. Not for runtime secrets. |
| **Environment-variable hardcoded** | NEVER | "free" | impossible | Always a finding in `secret-scan` / `gitleaks`. Forbidden by foundation policy. |

## The WAVE default: Doppler + GitHub Actions for CI

Why Doppler-default:

1. **Per-environment configs** (dev/staging/prod) with explicit inheritance, not hardcoded `.env.production`
2. **CLI dev experience** — `doppler run -- npm start` injects env at runtime; no `.env` file on disk
3. **Audit trail** — every read is logged with user/service
4. **Free tier** covers most WAVE consumers (under 5 users, 3 envs)

CI consumes Doppler via the official action; runtime servers consume via CLI or SDK.

## What goes WHERE

| Class | Lives in | Read by |
|-------|----------|---------|
| Runtime API keys (Stripe, OpenAI, Anthropic, Resend, etc.) | Doppler | Runtime server via CLI/SDK |
| CI tokens (NPM_TOKEN, PYPI_TOKEN, CARGO_TOKEN) | GitHub Actions secrets | CI workflows only |
| GHA-only OIDC roles | OIDC token exchange (no storage) | CI workflows only |
| Per-user dev SSH/AWS console | 1Password | Humans |
| Dynamic DB creds (per-pod, short TTL) | Vault | Runtime via sidecar |
| Public-bundled config | committed `*.example.env` | App, public |

## The hard rules

1. **Never commit raw secrets.** Enforced by `secret-scan` gate + gitleaks (changed-files + full-repo) + per-commit hook. See `rules/no-secrets-in-git.md`.
2. **No floating dep specs for internal scopes.** `dependency_confusion_gate` enforces. See `rules/dependency-confusion.md`.
3. **Rotate on suspected exposure** within 24h. The rotation runbook is `frameworks/incident-response/runbooks/secret-rotation.md` (when wired).
4. **Phase-3 spend-authority**: rail keys (Stripe, Bridge, Tempo, Privy) NEVER read directly by agents. They flow through the spend-authority capability. `check-spend-authority.sh` scans for direct imports. See `frameworks/security/spend-authority.md`.

## Migration: from `.env` files to Doppler

For a consuming repo currently using `.env`:

```bash
# 1. Sign up + install
brew install dopplerhq/cli/doppler
doppler login

# 2. Set up project
doppler setup        # interactive — picks project + config

# 3. Import existing .env
doppler secrets upload .env  # uploads all keys to current config

# 4. Switch dev to CLI-injected env
echo 'eval "$(doppler run --command print-env)"' >> .envrc   # direnv users
# or just prefix commands: doppler run -- npm start

# 5. Delete the .env (no longer needed)
git rm .env  &&  echo .env >> .gitignore   # if not already
```

## GitHub Actions integration

```yaml
- uses: dopplerhq/secrets-fetch-action@<pinned-sha>
  with:
    doppler-token: ${{ secrets.DOPPLER_SERVICE_TOKEN }}
- run: npm test  # all Doppler env vars now in $env
```

Token rotation: regenerate the service token in Doppler dashboard, update the GH org/repo secret, run a CI smoke. No code changes.

## Per-repo secrets inventory (`SECRETS.md`)

Every governed repo carries a `SECRETS.md` — the inventory of which secrets it needs, where the
canonical value lives, and how it rotates (names + locations only, **never values**). The scaffolder
seeds it from `scaffolder/templates/SECRETS.md` (placeholder-substituted, written once); fill in one
row per secret. It complements this framework: this doc decides *which store* to use; `SECRETS.md`
records *what this repo actually uses* so rotation and ownership are auditable per repo.

## Cross-references

- [`rules/no-secrets-in-git.md`](../../rules/no-secrets-in-git.md) — hard rule + scanner config
- [`rules/dependency-confusion.md`](../../rules/dependency-confusion.md) — supply-chain version
- [`frameworks/security-scanners/README.md`](../security-scanners/README.md) — broader scanner stack
- [`docs/threat-model.md`](../../docs/threat-model.md) — secrets-handling OWASP mapping
- [`scripts/check-spend-authority.sh`](../../scripts/check-spend-authority.sh) — rail-key import gate
