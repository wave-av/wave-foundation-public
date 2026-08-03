// Permission hardening for the intent ledger (Corridor CWE-276, finding 5b342dff).
//
// The ledger stores action items clipped verbatim from Claude Code session transcripts. Confirmed
// live on 2026-08-02 before this fix: a 1.1 MB ledger at 0644 under a 0755 state directory, i.e.
// world-readable on any shared developer or CI host.
//
// The test that carries the weight is PRE-EXISTING WIDE FILE. Creating with `{ mode }` is a no-op
// when the path already exists, so a fix that only passed a mode to writeFileSync/mkdirSync would
// pass a naive "write it and check the bits" test while leaving every already-deployed ledger
// exactly as exposed as it was. That is the regression this file exists to catch.

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, statSync, chmodSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { writeLedger, appendLedger, narrowPermissions, readLedger } from './intent-ledger.mjs';

const perms = (p) => statSync(p).mode & 0o777;

function scratch() {
  const dir = mkdtempSync(join(tmpdir(), 'ledger-perms-'));
  return { dir, ledger: join(dir, 'state', 'intent-ledger.jsonl') };
}

const ENTRY = [{ id: 'a1', kind: 'user-ask', text: 'ship it', status: 'open' }];

test('a freshly created ledger is owner-only, and so is its directory', () => {
  const { dir, ledger } = scratch();
  try {
    writeLedger(ENTRY, ledger);
    assert.equal(perms(ledger), 0o600, 'ledger file must be 0600');
    assert.equal(perms(join(dir, 'state')), 0o700, 'state directory must be 0700');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('a ledger FILE that ALREADY exists world-readable is narrowed on the next write', () => {
  // The real-world case: the fix has to remediate state that predates it. `mode` on open is
  // ignored for an existing path, so this fails against any create-time-only implementation.
  const { dir, ledger } = scratch();
  try {
    mkdirSync(join(dir, 'state'), { recursive: true });
    chmodSync(join(dir, 'state'), 0o755);
    writeFileSync(ledger, '');
    chmodSync(ledger, 0o644);
    assert.equal(perms(ledger), 0o644, 'precondition: the ledger starts wide');

    appendLedger(ENTRY, ledger);

    assert.equal(perms(ledger), 0o600, 'an existing 0644 ledger must be narrowed to 0600');
    assert.deepEqual(readLedger(ledger), ENTRY, 'narrowing must not cost us the contents');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('a NO-OP append (nothing captured) still remediates an existing wide ledger', () => {
  // On a machine where every PreCompact dedupes to zero fresh items, appendLedger([]) is the only
  // write-path call that ever runs. An early return that skips narrowing would leave the
  // pre-existing 0644 ledger world-readable indefinitely.
  const { dir, ledger } = scratch();
  try {
    mkdirSync(join(dir, 'state'), { recursive: true });
    writeFileSync(ledger, '');
    chmodSync(ledger, 0o644);

    appendLedger([], ledger);

    assert.equal(perms(ledger), 0o600, 'a wide ledger must be narrowed even when nothing is appended');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('a PRE-EXISTING custom parent directory is NOT chmodded: only the ledger file is ours', () => {
  // The ledger path is user-configurable (--ledger / $INTENT_LEDGER), so dirname can be $HOME,
  // /tmp, or a shared project dir. Tightening a directory the hook did not create would revoke
  // access other users and tools legitimately have.
  const { dir, ledger } = scratch();
  try {
    mkdirSync(join(dir, 'state'), { recursive: true });
    chmodSync(join(dir, 'state'), 0o755);

    appendLedger(ENTRY, ledger);

    assert.equal(perms(join(dir, 'state')), 0o755, 'a pre-existing non-default dir must be left alone');
    assert.equal(perms(ledger), 0o600, 'the ledger file itself is still narrowed');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('the DEFAULT machine-level state dir IS narrowed even when it pre-exists wide', () => {
  // This is the deployed-ledger remediation the finding is about: ~/.claude/state created 0755 by
  // whatever touched it first. A fresh module instance (query-string import) picks up the
  // overridden HOME so its homedir()-derived default points into the scratch area.
  const home = mkdtempSync(join(tmpdir(), 'ledger-home-'));
  const stateDir = join(home, '.claude', 'state');
  const prevHome = process.env.HOME;
  try {
    mkdirSync(stateDir, { recursive: true });
    chmodSync(stateDir, 0o755);
    process.env.HOME = home;
    return import('./intent-ledger.mjs?home-override').then((mod) => {
      mod.appendLedger(ENTRY, join(stateDir, 'intent-ledger.jsonl'));
      assert.equal(statSync(stateDir).mode & 0o777, 0o700, 'the default state dir must be remediated even when it pre-exists');
      // The no-op write path must remediate the default dir too, not just the file.
      chmodSync(stateDir, 0o755);
      mod.appendLedger([], join(stateDir, 'intent-ledger.jsonl'));
      assert.equal(statSync(stateDir).mode & 0o777, 0o700, 'a no-op append must still remediate the default state dir');
    }).finally(() => {
      process.env.HOME = prevHome;
      rmSync(home, { recursive: true, force: true });
    });
  } catch (err) {
    process.env.HOME = prevHome;
    rmSync(home, { recursive: true, force: true });
    throw err;
  }
});

test('narrowPermissions preserves setgid/sticky special bits while narrowing', () => {
  // chmod(2) takes the full mode: passing only the low 9 bits would strip setuid/setgid/sticky,
  // which is a behavior CHANGE (e.g. de-stickying a /tmp-like dir), not a narrowing. Note 0o1755
  // starts wide, so the narrowing branch actually fires and must carry the sticky bit through.
  const { dir } = scratch();
  try {
    const state = join(dir, 'state');
    mkdirSync(state, { recursive: true });
    chmodSync(state, 0o1755); // sticky + wide, like /tmp
    narrowPermissions(state, 0o700);
    assert.equal(statSync(state).mode & 0o7777, 0o1700, 'sticky bit must survive the narrowing');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('narrowPermissions only ever CLEARS bits — it can never widen a path', () => {
  // A ledger someone locked down harder than we ask for must stay locked down. This is the
  // property that makes it safe to run on every SessionStart and PreCompact.
  const { dir, ledger } = scratch();
  try {
    mkdirSync(join(dir, 'state'), { recursive: true });
    writeFileSync(ledger, '');
    chmodSync(ledger, 0o400);
    narrowPermissions(ledger, 0o600);
    assert.equal(perms(ledger), 0o400, '0400 is already narrower than 0600 and must be left alone');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('the WRITE PATH cannot widen an already-narrow ledger either', () => {
  // Same property, exercised through appendLedger rather than the helper directly — the helper
  // being narrowing-only does not by itself prove the caller does not widen first.
  //
  // 0200 (write-only), not 0400: it is the only mode narrower than 0600 that append can still
  // open. A 0400 ledger makes appendLedger throw EACCES, which is correct — a read-only ledger
  // SHOULD fail loudly rather than silently drop captured intent — so it is not exercised here.
  const { dir, ledger } = scratch();
  try {
    mkdirSync(join(dir, 'state'), { recursive: true });
    writeFileSync(ledger, '');
    chmodSync(ledger, 0o200);

    appendLedger(ENTRY, ledger);

    assert.equal(perms(ledger), 0o200, 'a 0200 ledger must survive a write still at 0200');
    assert.equal(perms(ledger) & ~0o600, 0, 'no bit outside the allowed mask may ever be set');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('narrowPermissions is best-effort — a missing path must not throw', () => {
  // It runs inside a hook on every SessionStart/PreCompact. A throw here takes the session
  // startup down, which is a strictly worse outcome than a permission left unchanged.
  assert.doesNotThrow(() => narrowPermissions(join(tmpdir(), 'ledger-perms-definitely-absent'), 0o600));
});
