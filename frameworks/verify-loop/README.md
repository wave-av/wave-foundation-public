# verify-loop — the WAVE fractal verify primitive (X.1)

> One loop, every scale. Build it **once**; instantiate it everywhere.

`discover → run the real path → emit {verdict, provenance} → refuse to advance on red → make the red visible.`

That single shape is the whole WAVE "prove-it" discipline. It verifies:

| Scale | Unit | Instance |
|------|------|----------|
| Example | a code block / step in a doc | example-runner / `doc-tests.mjs` |
| Doc | a guide followed cold | sandbox-walker |
| Surface | docs.wave.online, api… | wave-bench grader |
| Fleet | all live surfaces | `conformance.sh` |
| Platform | a render / settlement / context window | `wave.*-attestation/v0` |

This module is the reusable substrate those instances share, so the SSRF-safe fetch
path, the existence semantics, the bounded concurrency, and the secret-scrubbed
provenance are written and audited **in one place** — never re-implemented (and
never re-mis-implemented) per consumer. (NORTHSTAR §1 / `docs/docs-dogfood/NORTHSTAR.md`.)

## SSoT + vendoring (the bench pattern)

`frameworks/verify-loop/verify-loop.mjs` is the **single source of truth**. Consumers
in other repos **vendor a byte-identical copy** (e.g. `scripts/lib/verify-loop.mjs`)
and add a `*-ssot-drift` CI check that re-fetches this file and `git diff --exit-code`s
it — exactly how spokes vendor `bench.mjs`. **Never fork it**; fix it here and let the
drift check pull the update.

## API

```js
import {
  existsByStatus, probe, mapLimit, verdict, provenance, runChecks, scrubSecrets,
} from "./verify-loop.mjs";
```

- **`existsByStatus(status)`** → a documented route "exists" if it answers `2xx/3xx`,
  or `401/402/403` (auth/payment-gated is *healthy*, not broken). `404/410/5xx/none` fail.
- **`probe(url, {timeoutMs, fetchImpl})`** → SSRF-safe existence probe: GET-only,
  http/https-only, **no URL credentials**, `redirect:"manual"` (a 3xx proves life but is
  **not chased** into a private network), hard timeout. `{status, ok, error?}`.
- **`mapLimit(items, n, fn)`** → bounded-concurrency map; preserves order, ≤ `n` in flight.
- **`verdict(checks)`** → fold `{name, ok, detail?}[]` → `{ok, total, pass, fail, red[]}`.
  `ok===false` is the *refuse-on-red* signal.
- **`provenance({tool, startedAt, finishedAt, inputs, extra})`** → a structured,
  **secret-free** run record (timestamps passed in by the caller so the primitive stays
  pure). Recursively redacts secret-ish keys, URL credentials + secret query params, and
  opaque token-shaped strings.
- **`runChecks(targets, opts)`** → the loop in one call: probe every `{name, url}` →
  `{verdict, provenance, results}`.

## Security invariants

- **SSRF:** method/protocol/credential/redirect/timeout enforced in `probe`. For fully
  *untrusted* URLs, pass an additionally private-IP-blocking `fetchImpl`.
- **No fabricated provenance:** derive timestamps/inputs from the real run; never invent.
- **No secret leakage:** `scrubSecrets` runs on everything that enters `provenance`.

## Self-test ("a gate that can only PASS is worse than none")

```sh
node frameworks/verify-loop/verify-loop.mjs   # hermetic self-test, exits non-zero on any fail
node --test frameworks/verify-loop/tests/       # same via node:test
```

The self-test includes known-**bad** inputs the loop must **reject** (404/5xx → fail,
non-http → fail, url-creds → fail), so a regression that makes everything green fails here.
CI: `.github/workflows/verify-loop.yml`.
