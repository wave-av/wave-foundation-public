#!/usr/bin/env bash
# workflow-policy-harness.sh — shared setup for the WAS workflow-policy self-tests.
# SOURCE this; do not execute it. It is deliberately NOT named test-*.sh: the gate-self-tests job
# discovers suites with `git ls-files 'frameworks/gates/test-*.sh'`, a non-recursive glob, so a
# helper under lib/ is picked up by neither that glob nor a stray `bash frameworks/gates/test-*.sh`.
#
# Extracted from test-workflow-policy.sh when adding rule9 (#1020) pushed that file past the ~6000
# token hard gate. The seam is real, not a size dodge: this file answers "where does the lint under
# test come from", and the two suites that source it answer two different questions —
#   test-workflow-policy.sh         — the ENFORCE path + the rule registry's structure/provenance
#   test-workflow-policy-shadow.sh  — the SHADOW path: shadow rules' fixtures + canary routing
#
# The lint itself is INLINED in .github/workflows/checks.yml (step "Workflow-policy enforce"),
# because checks.yml is a reusable workflow that runs against the CALLER's checkout. Nothing here
# duplicates that python — it is SOURCED verbatim from checks.yml (yaml-parse the step's `run:`,
# strip the `python3 - <<'PY' ... PY` heredoc wrapper) and executed against golden fixtures. If the
# inline lint changes, both suites automatically test the new version — nothing to hand-sync.
#
# Provides: REPO_ROOT · CHECKS_YML · FIXTURES · work · lint_py · run_lint()
set -euo pipefail

# ../ from lib/ — resolved off THIS file, so it holds no matter which suite sources it.
GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$GATES_DIR/../.." && pwd)"
CHECKS_YML="$REPO_ROOT/.github/workflows/checks.yml"
FIXTURES="$GATES_DIR/fixtures/workflow-policy"
STEP_NAME="Workflow-policy enforce"

[ -f "$CHECKS_YML" ] || { echo "error: $CHECKS_YML not found" >&2; exit 1; }
[ -d "$FIXTURES" ] || { echo "error: $FIXTURES not found" >&2; exit 1; }

python3 -c "import yaml" 2>/dev/null || pip install --quiet --disable-pip-version-check pyyaml

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

lint_py="$work/workflow-policy-lint.py"

# Extract the exact python source of the "Workflow-policy enforce" step from checks.yml, verbatim.
python3 - "$CHECKS_YML" "$STEP_NAME" "$lint_py" <<'EXTRACT'
import sys, yaml

checks_yml, step_name, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
doc = yaml.safe_load(open(checks_yml))
jobs = doc.get("jobs") or {}
run_src = None
for job in jobs.values():
    if not isinstance(job, dict):
        continue
    for step in job.get("steps") or []:
        if isinstance(step, dict) and step.get("name") == step_name:
            run_src = step.get("run")
            break
    if run_src is not None:
        break

if run_src is None:
    sys.exit(f"error: step '{step_name}' not found in {checks_yml}")

# The step's `run:` block is a shell script that does `python3 - <<'PY' ... PY`.
# YAML block-scalar parsing already dedented the common leading whitespace, so we just need
# to slice out the heredoc body between the opening marker and the closing bare 'PY' line.
lines = run_src.splitlines()
start = end = None
for i, line in enumerate(lines):
    if start is None and "<<'PY'" in line:
        start = i + 1
        continue
    if start is not None and line.strip() == "PY":
        end = i
        break

if start is None or end is None:
    sys.exit("error: could not locate python3 - <<'PY' ... PY heredoc in the step's run: block")

python_src = "\n".join(lines[start:end]) + "\n"
open(out_path, "w").write(python_src)
EXTRACT

[ -s "$lint_py" ] || { echo "error: extracted lint source is empty — extraction failed" >&2; exit 1; }
echo "extracted lint source from checks.yml step '$STEP_NAME' -> $lint_py ($(wc -l < "$lint_py") lines)"

run_lint() {
  # Runs the extracted lint against a single fixture, isolated in its own .github/workflows/ dir
  # (the lint globs .github/workflows/*.yml relative to cwd).
  local fixture="$1"
  local dir
  dir="$work/run-$(basename "$fixture" .yml)"
  mkdir -p "$dir/.github/workflows"
  cp "$fixture" "$dir/.github/workflows/"
  ( cd "$dir" && python3 "$lint_py" )
}
