# Sandbox Runtime Framework

Implementation patterns for [sandbox-execution rule](../../rules/sandbox-execution.md).

## What lives here

- `dispatch.md` — how a calling app submits work to a sandbox and gets results back (synchronous vs queued)
- `oidc-flow.md` — `VERCEL_SANDBOX_AUTH_TYPE=oidc` exchange diagram
- `snapshot-build.md` — how a snapshot is built, tested, and pinned

## Quickstart

```ts
import { runInSandbox } from "@wave/sandbox";

const result = await runInSandbox({
  runtime: "claude",
  code: untrustedCode,
  injectSecrets: ["OPENAI_API_KEY"], // MUST also be in VERCEL_SANDBOX_ALLOWED_SECRET_KEYS
  networkAllowedHosts: ["api.openai.com"],
  timeoutMs: 30_000,
  vcpu: 1,
  memoryGb: 1,
});
```

The wrapper enforces every cap from the [rule](../../rules/sandbox-execution.md) before the Vercel API is called — short-circuits invalid configurations at the call site instead of trusting platform-side validation.

## Boundaries

- Wrapper is in `@wave/sandbox` (separate package; not vendored through `consume.sh`).
- This framework dir holds the **patterns and decision records**, not the runtime code.
