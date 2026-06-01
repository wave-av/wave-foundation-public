# Consumer Attestation — deployed == source

One question, asked everywhere: **is the thing running the exact thing we
committed?** A consumer that vendors the foundation, a Worker deployed to the
edge, a model served from Ollama, a package on five registries — each can silently
drift from its source. This framework is the single posture for catching that:
**pin a content hash at write time, re-assert it in CI, fail closed on mismatch.**

It generalizes the three attestations already in the foundation:

- `.foundation-version` + `consume.sh --check` (vendored docs/rules — CONSUME.md §3)
- `check-registry-parity.py` (same version across npm/PyPI/crates/… — CONSUME.md §4)
- `modelfile-registry.json` `manifest_id` vs `ollama list` (model-routing — CONSUME.md §5)

## The pattern

1. **Pin at write time.** Whatever produces the artifact records the source hash
   alongside it — the git commit you vendored, the digest you deployed, the
   `manifest_id` you served. The pin lives *with* the artifact (committed file,
   deploy annotation, registry field), never in a wiki.

2. **Re-derive at check time.** CI (or a periodic job) recomputes the hash from the
   live artifact and compares it to the pin. Recompute — never trust a second copy
   of the pin.

3. **Fail closed.** Mismatch → non-zero exit / blocked deploy / drift alert. A
   *missing* pin is also a mismatch (treat absent as drift), so a removed or
   renamed pin can't silently pass. This is the same fail-closed stance as the
   open-core held-count gate and the type-check sentinel.

```
  write ──► pin(hash)         check ──► hash' = derive(live)
                                        assert hash' == pin   else FAIL
```

## When to attest

| Artifact | Pin | Check |
|----------|-----|-------|
| Vendored `.foundation/` tree | `.foundation-version` (commit) | `consume.sh --check` (exit 2 on drift) |
| Edge Worker (deployed==source) | deployed version digest | compare to the built artifact hash (dispatch #83) |
| Multi-registry package | canonical version in your config | `check-registry-parity.py` per registry |
| Served model | `manifest_id` in `modelfile-registry.json` | vs `ollama list` ID before routing |
| Container image | image digest (not a moving tag) | admission check / deploy gate |

## Rules

- **Pin digests, not moving tags.** `@v1` / `:latest` are for *humans choosing*
  what to adopt; the attestation pins the *resolved* digest. (Renovate `pinDigests`
  + `pinact` do this for Actions; do the same for images + packages.)
- **The pin is committed, the check is required.** A pin nobody verifies is a
  comment. Wire the check as a required status (or a blocking deploy step).
- **Absent pin == drift.** Default to fail when the pin line is missing — never
  default-open. (This is exactly the bug fixed in the open-core publish gate: a
  missing count line now counts as held>0.)
- **Recompute, don't re-read.** Compare against a freshly derived hash, not a
  cached/second copy of the pin — otherwise you attest the pin against itself.

## Anti-patterns

- ❌ Trusting a moving tag (`@v1`, `:latest`) as the attestation — it can move under you.
- ❌ Treating a missing/unparseable pin as "probably fine" (fail-open).
- ❌ Pinning in CI config but never running the check (a pin nobody asserts).
- ❌ Comparing two copies of the pin instead of deriving the hash from the live artifact.

## Relation to other frameworks

- [`security-scanners`](../security-scanners/) — supply-chain pinning (pinact, gitleaks-incremental).
- [`model-routing`](../model-routing/) — `manifest_id` attestation before routing.
- `CONSUME.md` §3-5 — the three concrete attestations this generalizes.
