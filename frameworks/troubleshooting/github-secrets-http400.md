# Troubleshooting: GitHub Secrets HTTP 400 Error

> **Created:** 2026-01-21 | **Resolution Time:** ~30 minutes | **Root Cause:** Repository-level API restriction

---

## Problem Statement

When attempting to set GitHub Actions secrets using `gh secret set` or the API, the request fails with:

```
HTTP 400: Bad Request (https://api.github.com/repos/wave-av/wave-surfer-connect/actions/secrets/SECRET_NAME)
```

No additional error details are provided.

---

## Investigation Timeline

### Attempt 1: Standard gh CLI

```bash
echo "secret_value" | gh secret set SECRET_NAME --repo wave-av/wave-surfer-connect
# Result: HTTP 400 Bad Request
```

### Attempt 2: Verify Permissions

```bash
gh auth status
# Result: Token has admin:org, repo, workflow scopes - permissions OK
gh api /repos/wave-av/wave-surfer-connect -q '.permissions'
# Result: {"admin":true,"maintain":true,"pull":true,"push":true,"triage":true}
```

### Attempt 3: Test with Simple Value

```bash
echo "test_value" | gh secret set TEST_SECRET --repo wave-av/wave-surfer-connect
# Result: HTTP 400 - Still fails (not a value issue)
```

### Attempt 4: Manual Encryption with libsodium

```javascript
// Properly encrypted using sealed box
const encryptedValue = sodium.crypto_box_seal(secretBytes, publicKeyBytes);
// Result: Encryption verified correct, API still returns 400
```

### Attempt 5: Raw API Call

```bash
gh api -X PUT /repos/wave-av/wave-surfer-connect/actions/secrets/SECRET_NAME \
  -f encrypted_value="..." -f key_id="..."
# Result: HTTP 400 - Repository-level endpoint consistently fails
```

### Attempt 6: Organization-Level API ✅ SUCCESS

```bash
gh api -X PUT /orgs/wave-av/actions/secrets/SECRET_NAME \
  -f encrypted_value="..." \
  -f key_id="..." \
  -f visibility="selected" \
  -F selected_repository_ids[]=980969460
# Result: SUCCESS - Secret created
```

---

## Root Cause

The **repository-level secrets API** returns HTTP 400 for this specific repository/organization configuration. The exact cause is unclear (likely organization policies or GitHub Enterprise settings), but **organization-level secrets work correctly**.

---

## Solution

### Recommended: Use Organization-Level Secrets

```bash
# Using our automated script (auto-fallback to org level)
node scripts/set-github-secret.mjs SECRET_NAME "value"

# Force organization level
node scripts/set-github-secret.mjs SECRET_NAME "value" --org
```

### Manual Organization-Level

```bash
# 1. Get org public key
PUBLIC_KEY=$(gh api /orgs/wave-av/actions/secrets/public-key -q '.key')
KEY_ID=$(gh api /orgs/wave-av/actions/secrets/public-key -q '.key_id')

# 2. Encrypt (requires libsodium)
ENCRYPTED=$(node -e "..." # See set-github-secret.mjs for encryption code)

# 3. Get repo ID
REPO_ID=$(gh api /repos/wave-av/wave-surfer-connect -q '.id')

# 4. Set org secret with repo access
gh api -X PUT /orgs/wave-av/actions/secrets/SECRET_NAME \
  -f encrypted_value="$ENCRYPTED" \
  -f key_id="$KEY_ID" \
  -f visibility="selected" \
  -F selected_repository_ids[]=$REPO_ID
```

---

## Detection Patterns

When you see these errors, this troubleshooting guide applies:

```
# Error patterns that match this issue:
HTTP 400: Bad Request (/repos/.*/actions/secrets/)
failed to set secret ".*": HTTP 400
gh: Bad Request (HTTP 400)
```

---

## Prevention

1. **Default to org-level secrets** for wave-av repositories
2. **Use `set-github-secret.mjs`** which auto-falls back to org level
3. **Test with simple values first** to isolate encryption vs API issues

---

## Related Resources

- `/scripts/set-github-secret.mjs` - Automated script with fallback
- `/docs/integrations/github/SECRETS-MANAGEMENT.md` - Full documentation
- [GitHub Docs: Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

---

## Lessons Learned

1. **Document investigation as you go** - Don't wait until resolution
2. **Isolate variables systematically** - Test encryption, permissions, endpoints separately
3. **Try alternative API paths** - Organization vs repository level
4. **Create reusable tooling** - Script handles the complexity for future use
