// claude-api-lint: skip — this suite's fixtures spell out forbidden request shapes on purpose; every
// assertion below is that lint-request-shape.sh CATCHES (or correctly ignores) them.
//
// Model-family detection in lint-request-shape.sh must agree with modern-claude-contract.md §1 (v2) — the
// same algorithm as frameworks/model-routing/local_offload/shim/claude_family.py — on the contract's
// full §2 id list, verbatim: dated ids, dotted aggregator ids and [1m] ids gate the rules exactly like
// their bare ids, and legacy ids (Opus ≤4.6, Sonnet 4.x, Haiku, claude-3-x, non-Claude) gate nothing.
// governance/lib/claude-family-parity.test.mjs holds the linter, claude_family.py and claude-family.mjs
// to one id list, v2's ids included.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const LINT = fileURLToPath(new URL('./lint-request-shape.sh', import.meta.url));

const MODERN = [
  'claude-opus-4-7', 'claude-opus-4-7-20260115', 'claude-opus-4-8', 'claude-opus-4-8-20260501', // claude-api-lint: ignore — dated id named in a fixture, never sent
  'claude-opus-5', 'claude-opus-5-20260601', 'claude-opus-5-5', 'claude-opus-5-5-20260915', // claude-api-lint: ignore — dated id named in a fixture, never sent
  'claude-opus-5-5[1m]', 'claude-sonnet-5', 'claude-sonnet-5-20260701', 'claude-fable-5', // claude-api-lint: ignore — dated id named in a fixture, never sent
  'claude-fable-5-1', 'anthropic/claude-opus-5.5', 'anthropic/claude-opus-4.8', 'anthropic/claude-sonnet-5',
];
const LEGACY = [
  'claude-opus-4-6', 'claude-opus-4-6-20260205', 'claude-opus-4-5-20251101', 'claude-opus-4-1-20250805', // claude-api-lint: ignore — dated id named in a fixture, never sent
  'claude-opus-4-20250514', 'claude-sonnet-4-6', 'claude-sonnet-4-5', 'claude-sonnet-4-20250514', // claude-api-lint: ignore — dated id named in a fixture, never sent
  'claude-3-7-sonnet-20250219', 'claude-haiku-4-5', 'claude-haiku-4-5-20251001', 'gpt-5', '', // claude-api-lint: ignore — dated id named in a fixture, never sent
];

/** Write each fixture body to its own .py file, lint them all in ONE run, return the findings (✗, which
 *  fail the lint) and the UNVERIFIED warnings (⚠, which never do). */
function lint(bodies) {
  const dir = mkdtempSync(join(tmpdir(), 'lint-shape-'));
  try {
    const files = bodies.map((body, i) => {
      const f = join(dir, `f${i}.py`);
      writeFileSync(f, body);
      return f;
    });
    const r = spawnSync('bash', [LINT, ...files], { encoding: 'utf8' });
    const lines = r.stderr.split('\n');
    const findings = [];
    const warnings = [];
    for (let i = 0; i < lines.length; i++) {
      const m = /^claude-api-lint: (✗|⚠ UNVERIFIED) .*\/f(\d+)\.py:(\d+)$/.exec(lines[i]);
      if (m) (m[1] === '✗' ? findings : warnings).push({ fixture: Number(m[2]), line: Number(m[3]), msg: lines[i + 1] ?? '' });
    }
    return { status: r.status, findings, warnings, stdout: r.stdout, stderr: r.stderr };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// line 1 makes the file Claude-related; the id line is escaped from rule 1 (dated ids); lines 3/4 are
// the shapes the MODERN family 400s on.
const fixture = (id) => `# anthropic\nMODEL = "${id}"  # claude-api-lint: ignore\ntemperature = 0.2\nbudget_tokens = 1024\n`;

test('§2: sampling + budget_tokens are flagged for exactly the 16 MODERN ids', () => {
  const ids = [...MODERN, ...LEGACY];
  const { findings } = lint(ids.map(fixture));
  const flagged = (line, needle) =>
    new Set(findings.filter((x) => x.line === line && x.msg.includes(needle)).map((x) => ids[x.fixture]));
  assert.deepEqual([...flagged(3, 'temperature/top_p/top_k')].sort(), [...MODERN].sort());
  assert.deepEqual([...flagged(4, 'budget_tokens')].sort(), [...MODERN].sort());
  assert.deepEqual(findings.filter((x) => x.line !== 3 && x.line !== 4), [], 'no other rule fired');
});

test('per-model rules gate on the §1-parsed version, whatever the id spelling', () => {
  const cases = [
    // [id, shape line, flagged?]  — rule 6 disabled thinking
    ['anthropic/claude-opus-5.5', 'thinking = {"type": "disabled"}', true],
    ['claude-mythos-5', 'thinking = {"type": "disabled"}', true],
    ['claude-opus-4-8-20260501', 'thinking = {"type": "disabled"}', false], // claude-api-lint: ignore — dated id named in a fixture, never sent
    ['claude-opus-5-5-fast', 'thinking = {"type": "disabled"}', true], // v2: -fast normalizes to Opus 5.5
    ['claude-mythos-preview', 'thinking = {"type": "disabled"}', false], // not stated for Preview: UNVERIFIED warning, not a 400 (§3 v3.3 e)
    // rule 7 forced tool_choice
    ['anthropic/claude-fable-5.1', 'tool_choice = {"type": "any"}', true],
    ['claude-fable-5', 'tool_choice = {"type": "any"}', false],
    ['claude-mythos-5-1', 'tool_choice = {"type": "tool", "name": "x"}', true],
    ['claude-mythos-preview', 'tool_choice = {"type": "any"}', true], // error-codes.md:125
    // Mythos Preview is modern by prefix (§1 v2) — rule 3 — but takes budget_tokens thinking
    // (prompt-caching.md:293) and, per model-migration.md:191, prefill — so not rules 2 or 8
    ['claude-mythos-preview', 'temperature = 0.2', true],
    ['claude-mythos-preview', 'budget_tokens = 1024', false],
    ['claude-mythos-preview', 'msgs = [{"role": "assistant", "content": "{"}]', false],
    // rule 8 assistant-role literal on the 4.6+ family
    ['claude-opus-4-6-20260205', 'msgs = [{"role": "assistant", "content": "{"}]', true], // claude-api-lint: ignore — dated id named in a fixture, never sent
    ['claude-opus-4-5-20251101', 'msgs = [{"role": "assistant", "content": "{"}]', false], // claude-api-lint: ignore — dated id named in a fixture, never sent
    // rule 9 computer_2025* on Opus 5.5
    ['claude-opus-5-5-20260915', 'tools = [{"type": "computer_20251124"}]', true], // claude-api-lint: ignore — dated id named in a fixture, never sent
    ['claude-opus-5-50', 'tools = [{"type": "computer_20251124"}]', false],
    // rule 4 effort on Haiku 4.5
    ['claude-haiku-4-5-20251001', 'output_config = {"effort": "low"}', true], // claude-api-lint: ignore — dated id named in a fixture, never sent
    ['claude-sonnet-4-6', 'output_config = {"effort": "low"}', false],
  ];
  const { findings } = lint(cases.map(([id, shape]) => `# anthropic\nMODEL = "${id}"  # claude-api-lint: ignore\n${shape}\n`));
  cases.forEach(([id, shape, want], i) => {
    const got = findings.some((x) => x.fixture === i && x.line === 3);
    assert.equal(got, want, `${id} + ${shape}`);
  });
});

test('rule 7 still sees Mythos 5.1 in its Bedrock and dated spellings (round-4 N1)', () => {
  // The id token must stop at "-v1:0" / "-{DATE}". At b0eb1893 its mythos branch took digits and,
  // grep -o keeping the longest match, produced claude-mythos-5-1-v1 / claude-mythos-5-1-, which parse
  // as nothing: forced tool_choice went unflagged. The real-date id is the control (flagged at both).
  const ids = [
    'anthropic.claude-mythos-5-1-v1:0',
    'claude-mythos-5-1-{DATE}',
    'claude-mythos-5-1-<DATE>',
    'claude-mythos-5-1-20260915', // claude-api-lint: ignore — dated id named in a fixture, never sent
  ];
  const { findings } = lint(ids.map((id) => `# anthropic\nMODEL = "${id}"  # claude-api-lint: ignore\ntool_choice = {"type": "any"}\n`));
  const flagged = ids.filter((_, i) => findings.some((x) => x.fixture === i && x.line === 3 && x.msg.includes('forced tool_choice')));
  assert.deepEqual(flagged, ids);
});

// One fixture per id: line 3 is the shape under test.
const shaped = (ids, shape) => ids.map((id) => `# anthropic\nMODEL = "${id}"  # claude-api-lint: ignore\n${shape}\n`);
const OFF_LINE = 'thinking = {"type": "disabled"}';

test('rule 6 is a hard 400 only on the §3 table rows that never take disabled; a no-row id is UNVERIFIED (v3.3 e)', () => {
  const never = ['claude-opus-5-5', 'claude-fable-5', 'claude-fable-5-1', 'claude-mythos-5', 'claude-mythos-5-1'];
  const accepts = ['claude-opus-4-7', 'claude-opus-4-8', 'claude-opus-5', 'claude-sonnet-5'];
  // no row in the §3 table (v3.2/v3.3), and Preview, whose row is all "not stated"
  const unverified = ['claude-mythos-6', 'claude-fable-5-2', 'claude-opus-6', 'claude-mythos-preview-2', 'claude-mythos-preview'];
  const ids = [...never, ...accepts, ...unverified];
  const { findings, warnings } = lint(shaped(ids, OFF_LINE));
  const at3 = (xs) => xs.filter((x) => x.line === 3).map((x) => ids[x.fixture]).sort();
  assert.deepEqual(at3(findings), [...never].sort(), 'hard rule 6');
  assert.deepEqual(at3(warnings), [...unverified].sort(), 'UNVERIFIED warnings');
  for (const w of warnings) assert.ok(w.msg.includes(` ${ids[w.fixture]}:`), `the warning names its id: ${w.msg}`);
  // a file that also names a "Never" row gets the hard error, not the warning
  const both = lint([`# anthropic\nMODELS = ["claude-opus-5-5", "claude-mythos-6"]  # claude-api-lint: ignore\n${OFF_LINE}\n`]);
  assert.equal(both.findings.length, 1);
  assert.equal(both.warnings.length, 0);
});

test('UNVERIFIED warnings alone never fail the lint', () => {
  const ids = ['claude-mythos-6', 'claude-opus-6'];
  const { status, findings, warnings, stdout } = lint(shaped(ids, OFF_LINE));
  assert.equal(findings.length, 0);
  assert.equal(warnings.length, 2);
  assert.equal(status, 0);
  assert.match(stdout, /✓ no forbidden Claude-API request shapes \(2 UNVERIFIED warning\(s\) above/);
});

test('rule 7 fires ONLY on Opus 5.5 / Fable 5.1 / Mythos 5.1 / Mythos Preview (contract §3 v3.4)', () => {
  const rejects = ['claude-opus-5-5', 'claude-fable-5-1', 'claude-mythos-5-1', 'claude-mythos-preview'];
  // models.md:74 and model-migration.md:1868 list forced tool_choice as a breaking change FROM these
  const accepts = ['claude-opus-4-7', 'claude-opus-4-8', 'claude-opus-5', 'claude-sonnet-5', 'claude-fable-5', 'claude-mythos-5', 'claude-mythos-6'];
  const ids = [...rejects, ...accepts];
  for (const shape of ['tool_choice = {"type": "any"}', 'tool_choice = {"type": "tool", "name": "x"}']) {
    const { findings } = lint(shaped(ids, shape));
    const flagged = findings.filter((x) => x.line === 3 && x.msg.includes('forced tool_choice')).map((x) => ids[x.fixture]);
    assert.deepEqual(flagged.sort(), [...rejects].sort(), shape);
  }
});

test('rule 1 covers every §1 family and still exempts aggregator slugs', () => {
  const { findings } = lint([
    'MODEL = "claude-fable-5-20260101"\n',
    'MODEL = "anthropic/claude-fable-5-20260101"\n',
    'MODEL = "claude-opus-4-8-20260501"\n', // claude-api-lint: ignore — dated id named in a fixture, never sent
  ]);
  assert.deepEqual(findings.map((x) => x.fixture).sort(), [0, 2]);
});

// Final-review F1 (2026-09-22): the input bound, MAX_MODEL_ID_LEN = 256, as in claude_family.py. The
// suffix loop in file_model_ids is quadratic in a token's length, so an over-long token is not a Claude
// id. It gates no rule, and the lint prints one note per run.
test('an id token over 256 chars gates no rule and is noted once per run; one AT the bound still gates', () => {
  const overCap = [`claude-opus-5-5${'-20260101'.repeat(30)}`, `claude-mythos-preview-${'a'.repeat(235)}`];
  const atCap = `claude-mythos-preview-${'a'.repeat(234)}`;
  const { findings, stderr } = lint([...overCap.map(fixture), fixture(atCap)]);
  assert.deepEqual([...new Set(findings.map((x) => x.fixture))], [2]);
  assert.equal(stderr.match(/over 256 chars/g)?.length, 1);
});
