# Troubleshooting: Next.js Build Lock Error

> **Created:** 2026-01-21 | **Resolution Time:** <1 minute | **Root Cause:** Concurrent processes

---

## Problem Statement

When attempting to run `npm run build` or `npm run validate:comprehensive`, the build fails with:

```
⨯ Unable to acquire lock at /path/to/.next/lock, is another instance of next build running?
```

---

## Root Cause

The `.next/lock` file is held by another process, typically:

1. A running dev server (`npm run dev`)
2. A previous build that crashed
3. A background TypeScript check

---

## Solution

### Quick Fix

```bash
# Kill any Next.js processes and remove lock
pkill -f "next" && rm -f .next/lock
```

### Before Running Builds

Always check for running dev server:

```bash
# Check if port 3000 is in use
lsof -i :3000

# If dev server is running, stop it first
pkill -f "next dev"
```

### Automated Script

```bash
#!/bin/bash
# scripts/safe-build.sh
set -e

# Check for dev server
if lsof -i :3000 &>/dev/null; then
  echo "⚠️  Dev server running on port 3000"
  read -p "Stop it and continue? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    pkill -f "next dev"
    sleep 2
  else
    echo "Aborting build"
    exit 1
  fi
fi

# Remove stale lock
rm -f .next/lock

# Run build
npm run build
```

---

## Detection Patterns

```
# Error patterns that match this issue:
Unable to acquire lock at .*/\.next/lock
is another instance of next build running
ENOENT: no such file or directory.*\.next/lock
```

---

## Prevention

1. **Don't run dev server and build simultaneously**
2. **Use separate terminals** for dev and validation
3. **Create a `safe-build` script** that checks first
4. **CI/CD doesn't have this issue** (fresh environment)

---

## Related

- `.claude/troubleshooting/INDEX.md` - Troubleshooting index
- `scripts/validate-production.js` - Comprehensive validation
