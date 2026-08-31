#!/usr/bin/env node
// tap-count-real-tests.mjs — given a suite path and that suite's TAP output on stdin, print how
// many of its subtests are REAL tests rather than the file-level subtest node emits for the file
// itself.
//
// WHY THIS EXISTS (#1047, split out of #1012). `# tests N` cannot tell a hollow suite from a real
// one: when a file registers nothing, node reports the FILE ITSELF as the single subtest, so a
// hollow suite still prints `# tests 1`. The discriminator is the subtest NAME — but the NAME node
// uses for that file-level subtest is version-dependent. Measured in Docker, same image family,
// varying only the runtime:
//
//   node 20.20.2 -> "# Subtest: /w/sub/deep.test.mjs"   resolved ABSOLUTE path
//   node 22.23.1 -> "# Subtest: sub/deep.test.mjs"      relative path
//   node 24.18.1 -> "# Subtest: sub/deep.test.mjs"      relative path
//
// The previous implementation string-matched an ENUMERATION of the two spellings it knew. That is
// load-bearing rather than cosmetic, because the drill validating the step runs under a DIFFERENT
// node than the step itself (gate-self-tests has no setup-node; node-suites pins 24). So the
// enumeration could rot — a runner image bump, a changed pin, or a third spelling — while the drill
// stayed green and hollow suites sailed through as coverage. A fail-open you cannot see.
//
// Also measured: node 22/24 NORMALISE the argv, reporting `./x.test.mjs` as `x.test.mjs`. So the
// old exact-match was already one `./` away from missing, with no test covering it.
//
// THE FIX IS TO STOP ENUMERATING. Canonicalise the subtest name and the suite path through the
// SAME function and compare. Any spelling that denotes the same file compares equal, including
// spellings that do not exist yet — which is the property the enumeration could never have.
//
// Pure computation: reads stdin and argv, writes stdout. No network, no spawn, no writes.
import { readFileSync, realpathSync } from 'node:fs';
import { resolve } from 'node:path';

const usage = 'usage: node scripts/tap-count-real-tests.mjs <suite-path>  (TAP on stdin)';

const suite = process.argv[2];
if (!suite) {
  console.error(`::error::tap-count-real-tests.mjs: no suite path given. ${usage}`);
  process.exit(2);
}

/**
 * Canonicalise a path the same way for BOTH sides of the comparison.
 *
 * `resolve` makes a relative name absolute against cwd — which is precisely the base node used
 * when it printed a relative one. `realpathSync` then collapses symlinks, and it matters: macOS
 * `/tmp` is a symlink to `/private/tmp`, and the drill for this step runs under `mktemp`, so one
 * side can arrive already-resolved and the other not. Running both through the identical function
 * makes that cancel instead of producing a spurious mismatch.
 *
 * A name that is not a path at all — a real test called "a" — simply resolves to something that is
 * not the suite, which is the correct answer. realpathSync throws for it (no such file), so fall
 * back to the resolved value rather than letting a normal case raise.
 */
function canonical(p) {
  const abs = resolve(p);
  try {
    return realpathSync(abs);
  } catch {
    return abs;
  }
}

const suiteCanonical = canonical(suite);

// fd 0. An empty stdin is legitimate (a suite that printed nothing) and yields 0.
let tap = '';
try {
  tap = readFileSync(0, 'utf8');
} catch (err) {
  console.error(`::error::tap-count-real-tests.mjs: could not read TAP from stdin: ${err.message}`);
  process.exit(2);
}

let subtests = 0;
let selfNamed = 0;
for (const line of tap.split('\n')) {
  // TAP indents nested subtests, so the marker is matched after leading whitespace rather than
  // anchored hard to column 0 — a nested `# Subtest:` is still a subtest.
  const match = /^\s*# Subtest: (.*)$/.exec(line);
  if (!match) continue;
  subtests += 1;
  if (canonical(match[1].trim()) === suiteCanonical) selfNamed += 1;
}

console.log(String(subtests - selfNamed));
