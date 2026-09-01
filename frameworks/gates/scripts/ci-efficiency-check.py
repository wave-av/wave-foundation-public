#!/usr/bin/env python3
"""ci-efficiency-check.py: static CI-efficiency gate (issue #3932, gha-billing-efficiency P3).

Four rules, all STATIC text checks over workflow YAML. Zero API cost: no gh calls, no
network, just PyYAML over .github/workflows. The August 2026 org billing audit measured
the waste classes these rules kill: cron spam and double-fires alone were ~$35/mo of pure
noise, and every PR pays again for workflows whose scheduled pass already covers the tree.

  DOUBLE-FIRE              a workflow with both schedule: and push:/pull_request: triggers.
                           Every PR and push pays for a workflow whose scheduled pass already
                           covers the same tree. Split the scheduled sweep into its own file.
  COMMENT-FANOUT           an issue_comment / pull_request_review(_comment) trigger with no
                           author filter or command-prefix guard visible in the file. Without
                           a guard, ANY comment on ANY issue or PR fires a paid run.
  FAST-CRON                a cron that fires more than once per hour: two or more distinct
                           minute values in the minute field (a '*' counts as all sixty).
                           Sub-hour crons multiply runner cost around the clock.
  FAST-CRON-ON-EXPENSIVE   a sub-hour cron whose job runs on a GitHub-hosted paid label
                           (ubuntu-latest and friends). A fast cron must use a cheap or
                           fenced runner family: blacksmith-*, depot-*, self-hosted.

MODES
  Advisory (default): findings print as ::warning:: annotations and the exit code is 0.
  A hard fail here would break every fleet PR at once on existing violations, so the gate
  ships advisory and flips to blocking only after the burn-down tracked in #3932.
  --strict: findings print as ::error:: and exit 1. The blocking flip is exactly this flag
  plus dropping the job-level continue-on-error; nothing else changes.

USAGE
  python3 ci-efficiency-check.py [files...]     no args: every .github/workflows/*.{yml,yaml}
  python3 ci-efficiency-check.py --strict ...   exit 1 on any finding (the blocking mode)

The live gate INLINES this file verbatim in .github/workflows/checks.yml (job
ci-efficiency): checks.yml is a reusable workflow that runs on the CALLER's checkout, and
consumer repos carry no foundation scripts. test-ci-efficiency.sh byte-compares the inline
twin against this file so the two can never drift; same shape as secret-scan.sh.
"""

import argparse
import glob
import re
import sys

try:
    import yaml
except ImportError:
    yaml = None

# GitHub-hosted paid labels: the expensive set for FAST-CRON-ON-EXPENSIVE. Cheap or fenced
# families (blacksmith-*, depot-*, self-hosted, and any unrecognized label) never match:
# the rule only fires on labels it can PROVE are GitHub-hosted, so an unknown private
# runner pool is never a false finding.
EXPENSIVE_RUNNER_RE = re.compile(
    r"^(ubuntu-(latest|\d{2}\.\d{2})|macos-(latest|\d+)|windows-(latest|\d{4}))$"
)

# Guard signals for COMMENT-FANOUT: any of these anywhere in the file counts as a visible
# author filter or command match and suppresses the finding. Deliberately generous (raw
# text, not only if: blocks, because a guard may sit in an env: or a with: handoff to an
# action): the advisory gate must not cry wolf. A false negative only slows the #3932
# burn-down; a false positive erodes trust in every warning the gate prints.
GUARD_RES = (
    re.compile(r"github\.event\.comment\.user"),
    re.compile(r"github\.event\.review\.user"),
    re.compile(r"github\.event\.sender"),
    re.compile(r"author_association"),
    re.compile(r"github\.actor"),
    re.compile(r"github\.event\.comment\.body"),
    re.compile(r"github\.event\.review\.body"),
)

COMMENT_TRIGGERS = ("issue_comment", "pull_request_review", "pull_request_review_comment")
PR_OR_PUSH_TRIGGERS = ("push", "pull_request", "pull_request_target")


def _safe(value):
    # The live gate runs this check on the CALLER's tree, so every YAML value read here
    # (paths, job names, cron strings, runner labels) is untrusted caller content. Strip
    # CR/LF and break the command prefix before interpolating into a ::-prefixed
    # annotation line; same guard the WAS lint uses (checks.yml, #890).
    return str(value).replace("\r", " ").replace("\n", " ").replace("::", ":​:")


def expand_field(field, lo, hi):
    """Expand one cron field to the set of integers it matches, or None if unparseable.

    Handles the shapes GitHub crons use: '*' (with optional /N step), 'A-B' (with optional
    /N), bare 'A', comma lists, and vixie-style 'A/N' (A to the field top, every N).
    """
    values = set()
    for part in str(field).split(","):
        part = part.strip()
        if not part:
            return None
        step = 1
        had_step = False
        if "/" in part:
            base, _, step_text = part.partition("/")
            part = base
            had_step = True
            try:
                step = int(step_text)
            except ValueError:
                return None
            if step < 1:
                return None
        if part == "*":
            start, end = lo, hi
        elif "-" in part:
            a, _, b = part.partition("-")
            try:
                start, end = int(a), int(b)
            except ValueError:
                return None
        else:
            try:
                start = int(part)
            except ValueError:
                return None
            end = hi if had_step else start
        if start > end:
            return None
        values.update(range(start, end + 1, step))
    return values


def cron_minutes(cron):
    """Return the set of minute values a 5-field cron matches, or None if unparseable."""
    fields = str(cron).split()
    if len(fields) != 5:
        return None
    return expand_field(fields[0], 0, 59)


def check_file(path):
    """Return the findings for one workflow file as a list of (rule, message) pairs."""
    findings = []
    if yaml is None:
        # Self-contained guard: main() already refuses to run without PyYAML, but this
        # function stays independently safe (and type-clean) if called directly.
        print("::notice::ci-efficiency: PyYAML unavailable; cannot check workflow files.")
        return findings
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as exc:
        print(f"::notice::ci-efficiency: cannot read {_safe(path)} ({exc}); skipping")
        return findings
    try:
        doc = yaml.safe_load(text)
    except Exception as exc:
        print(f"::notice::ci-efficiency: {_safe(path)} unparseable ({exc}); skipping")
        return findings
    if not isinstance(doc, dict):
        return findings

    # YAML 1.1 parses a bare on: key as boolean True; same dance the WAS lint does.
    on = doc.get("on", doc.get(True, {}))
    if isinstance(on, str):
        on = {on: None}
    elif isinstance(on, list):
        on = {k: None for k in on}
    if not isinstance(on, dict):
        on = {}

    # DOUBLE-FIRE: schedule: plus push:/pull_request: on one workflow.
    fired = sorted(t for t in PR_OR_PUSH_TRIGGERS if t in on)
    if "schedule" in on and fired:
        findings.append((
            "DOUBLE-FIRE",
            f"has both schedule: and {'/'.join(fired)}: triggers; every PR or push pays "
            "for a workflow whose scheduled pass already covers the tree. Split the "
            "scheduled sweep into its own workflow file.",
        ))

    # FAST-CRON: any schedule entry that fires more than once per hour. Two or more
    # distinct minute values always yield a sub-hour gap; a single minute value never
    # does (the worst case is exactly hourly).
    sched = on.get("schedule")
    entries = sched if isinstance(sched, list) else [sched] if isinstance(sched, dict) else []
    fast = False
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        cron = entry.get("cron")
        if cron is None:
            continue
        minutes = cron_minutes(cron)
        if minutes is None:
            print(f"ci-efficiency: {_safe(path)}: cron '{_safe(cron)}' unparseable; skipping it")
            continue
        if len(minutes) >= 2:
            fast = True
            findings.append((
                "FAST-CRON",
                f"cron '{_safe(cron)}' fires more than once per hour; sub-hour crons "
                "multiply runner cost around the clock. Keep the interval at 60 minutes "
                "or slower.",
            ))

    # FAST-CRON-ON-EXPENSIVE: a sub-hour cron whose job sits on a GitHub-hosted paid
    # label. One finding per offending job; expression-valued runs-on labels cannot be
    # resolved statically and are skipped.
    if fast:
        for job_name, job in (doc.get("jobs") or {}).items():
            if not isinstance(job, dict):
                continue
            runs_on = job.get("runs-on")
            if runs_on is None:
                continue
            labels = runs_on if isinstance(runs_on, list) else [runs_on]
            for label in labels:
                label = str(label)
                if "{{" in label:
                    continue
                if EXPENSIVE_RUNNER_RE.match(label):
                    findings.append((
                        "FAST-CRON-ON-EXPENSIVE",
                        f"sub-hour cron on GitHub-hosted runner '{_safe(label)}' (job "
                        f"'{_safe(job_name)}'); a fast cron must use a cheap or fenced "
                        "runner family: blacksmith-*, depot-*, or self-hosted.",
                    ))
                    break

    # COMMENT-FANOUT: a comment-shaped trigger with no visible guard.
    comment_events = sorted(t for t in COMMENT_TRIGGERS if t in on)
    if comment_events and not any(rx.search(text) for rx in GUARD_RES):
        findings.append((
            "COMMENT-FANOUT",
            f"{', '.join(comment_events)} trigger with no author filter or command-prefix "
            "guard visible in the file; any comment on any issue or PR fires a paid run. "
            "Add an if: on the sender or author, or match a command prefix (the pr-agent "
            "cost-abuse gate in wave-foundation is the house pattern).",
        ))

    return findings


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Static CI-efficiency gate: double-fire, comment-fanout, fast-cron "
        "and fast-cron-on-expensive checks over GitHub workflow YAML (#3932)."
    )
    parser.add_argument(
        "files",
        nargs="*",
        help="workflow files to check; with no args, every .github/workflows/*.{yml,yaml}",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="exit 1 on any finding (the future blocking mode after the #3932 burn-down)",
    )
    args = parser.parse_args(argv)

    if yaml is None:
        # Advisory mode fails OPEN (a missing dependency must never wedge a caller's PR);
        # strict mode fails CLOSED (the blocking flip must not fail silent).
        mode = "strict" if args.strict else "advisory"
        print(f"::notice::ci-efficiency: PyYAML unavailable; cannot check workflows in {mode} mode.")
        return 1 if args.strict else 0

    if args.files:
        paths = list(args.files)
    else:
        paths = sorted(
            glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml")
        )

    level = "error" if args.strict else "warning"
    total = 0
    for path in paths:
        for rule, message in check_file(path):
            print(f"::{level}::ci-efficiency[{rule}] {_safe(path)}: {message}")
            total += 1
    mode = "strict" if args.strict else "advisory: warnings only, the gate stays green"
    print(f"ci-efficiency: scanned {len(paths)} workflow file(s), {total} finding(s) ({mode})")
    if total and args.strict:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
