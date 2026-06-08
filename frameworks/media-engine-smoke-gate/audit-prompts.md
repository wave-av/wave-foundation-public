# Media-engine smoke-gate — pre-completion audit

Run this before claiming any WAVE media-engine module or adapter is done. Answer each in the
PR description. If any answer is "no", the work is **not complete** — keep going.

## Created
- [ ] Does real code exist for this thing (a header/impl/module), not a placeholder, stub, or `void`-ed no-op?
- [ ] If it's a "model only" (engine core) item, does it ship the actual contract (struct/interface/fn), not just a doc?

## Smoked
- [ ] Is there a dependency-free E2E test that exercises the real behavior (not just "compiles")?
- [ ] Does the test use fixed oracle values / known-answer cases so it's deterministic (no hardware, no network, no clock-of-the-day)?
- [ ] On success, does it print a UNIQUE sentinel `WAVE <THING> TEST PASS`?
- [ ] On any failed assertion, does it exit non-zero AND not print the PASS sentinel?

## Wired
- [ ] Is the test built + run by the repo's build (`build.sh` / `ctest` / `npm test`)?
- [ ] Does CI assert it with the sentinel grep: `<run-the-test> | grep -q "WAVE <THING> TEST PASS"`?
- [ ] Is it listed in `.gitignore` (built binaries) / CMake `foreach` / the CI step list — i.e. it can't be silently dropped?

## Green
- [ ] Is that CI step passing on this PR (not skipped, not red)?
- [ ] Did you run the full smoke suite locally and see every `WAVE … TEST PASS` line?

## Honest-scope
- [ ] Does the PR body state what the smoke does NOT yet cover (real hardware bind, live network, draft-revision edges)?
- [ ] Are any fabricated/placeholder numbers explicitly called out (e.g. "integrity counts are observed-only until the wire handler lands")?

> If you wrote "done" anywhere, replace it with the green sentinel line(s) that prove it.
