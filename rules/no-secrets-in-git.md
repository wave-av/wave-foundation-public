---
paths:
  - "**/*"
---

# No Secrets in Git-Tracked Files

Never commit API keys, tokens, passwords, or credentials to version control.

Use environment variables, .env files (gitignored), or secret managers instead.

**Canonical secret-pattern set** (single source of truth — `self-check.yml` / `scripts/check-public-env.py`,
documented in [`public-env.md`](./public-env.md)): `sk-…`, `sk_(live|test)_…`, `sbp_…`, `github_pat_…`,
`ghp_…`, `AKIA…`, `AIzaSy…`, `xai-…`, `xoxb-…`, `Bearer …`, `-----BEGIN … PRIVATE KEY`, plus a JWT
`service_role`-claim sniff. Secret-scan against this set before every push; don't maintain a divergent
list here.
