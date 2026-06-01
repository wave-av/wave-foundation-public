---
paths:
  - "**/*"
---

# No Secrets in Git-Tracked Files

Never commit API keys, tokens, passwords, or credentials to version control.

Use environment variables, .env files (gitignored), or secret managers instead.

Check for patterns: `sk_`, `sbp_`, `github_pat_`, `Bearer`, `password=`, `secret=`
