#!/usr/bin/env python3
"""Validate every SKILL.md's frontmatter. This is the gate that would have caught the
2026-05-26 regression (a bulk edit that blanked `allowed-tools` lists).

Checks per SKILL.md:
  - frontmatter delimited by `---` ... `---`
  - frontmatter is valid YAML
  - no duplicate top-level keys (YAML silently keeps the last — we reject it)
  - name: present, a string, equals the directory name, kebab/underscore-safe
  - description: present, non-empty, 20–400 chars, no trailing dangling connector
  - allowed-tools / hooks: if the key is present it must be NON-EMPTY
    (empty after a bulk edit is the regression signature)
  - category prefix (taxonomy/skills.md): canonical skills SHOULD use an approved prefix
    (advisory WARNING; staging/ harvest is exempt while it's being migrated)

Exit 1 if any ERROR. Style issues (e.g. description not starting with "Use when", or an
unapproved category prefix) are WARNINGS and do not fail unless --strict.

Usage: python3 scripts/validate-skills.py [roots...]   (default: plugin/skills staging/skills)
"""
import sys
import os
import re
import glob
import subprocess

NAME_RE = re.compile(r"^[a-z0-9_]+(?:-[a-z0-9_]+)*$")
TOPKEY_RE = re.compile(r"^([A-Za-z_][\w-]*):")
DANGLE_RE = re.compile(r"\b(and|or|using|with|for|the|to|that|a|an|of|in|on|via|based)\s*$", re.I)

# Approved category prefixes — MUST stay in sync with taxonomy/skills.md (single source of truth;
# to add one, propose it there first, then add it here). `plan-` is the foundation's own planning
# category (plan-generate/enhance/to-action/audit).
APPROVED_PREFIXES = (
    "ai-", "streaming-", "infra-", "platform-", "security-", "monitoring-", "dev-", "doc-",
    "payments-", "compliance-", "integration-", "events-", "perf-", "agent-", "analytics-",
    "testing-", "database-", "workflow-", "context-", "plan-",
)
# Allowed without an advisory: the WAVE product namespace + reserved internal prefixes.
NAMESPACE_PREFIXES = ("wave-", "_core-", "_external", "_consolidated", "_archived")

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. `pip install pyyaml`", file=sys.stderr)
    sys.exit(2)


def frontmatter(text):
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n?", text, re.S)
    return m.group(1) if m else None


def dup_top_keys(fm):
    seen, dups = set(), set()
    for line in fm.split("\n"):
        m = TOPKEY_RE.match(line)
        if m:
            k = m.group(1)
            (dups if k in seen else seen).add(k)
    return sorted(dups)


def check(skill_path):
    errs, warns = [], []
    d = os.path.basename(os.path.dirname(skill_path))
    text = open(skill_path, encoding="utf-8", errors="replace").read()
    fm = frontmatter(text)
    if fm is None:
        return [f"{skill_path}: no frontmatter block"], []

    dups = dup_top_keys(fm)
    if dups:
        errs.append(f"{skill_path}: duplicate frontmatter keys: {', '.join(dups)}")

    try:
        data = yaml.safe_load(fm) or {}
    except yaml.YAMLError as e:
        return [f"{skill_path}: invalid YAML frontmatter: {e}"], []
    if not isinstance(data, dict):
        return [f"{skill_path}: frontmatter is not a mapping"], []

    name = data.get("name")
    if not name or not isinstance(name, str):
        errs.append(f"{skill_path}: missing/empty name")
    else:
        if name != d:
            errs.append(f"{skill_path}: name '{name}' != directory '{d}'")
        if not NAME_RE.match(name):
            errs.append(f"{skill_path}: name '{name}' not kebab-case")
        # Category-prefix taxonomy (taxonomy/skills.md). Advisory for canonical skills; staging/
        # is the un-migrated harvest (#16/#17), so it's exempt to keep the signal clean.
        norm = skill_path.replace(os.sep, "/")
        is_staging = norm.startswith("staging/") or "/staging/" in norm
        allowed = APPROVED_PREFIXES + NAMESPACE_PREFIXES
        if not is_staging and not any(name.startswith(p) for p in allowed):
            warns.append(f"{skill_path}: name '{name}' has no approved category prefix "
                         f"(see taxonomy/skills.md)")

    desc = data.get("description")
    if not desc or not isinstance(desc, str) or not desc.strip():
        errs.append(f"{skill_path}: missing/empty description")
    else:
        ds = desc.strip()
        if len(ds) < 20:
            errs.append(f"{skill_path}: description too short ({len(ds)} chars)")
        if len(ds) > 400:
            warns.append(f"{skill_path}: description long ({len(ds)} chars)")
        if DANGLE_RE.search(ds):
            errs.append(f"{skill_path}: description ends mid-phrase (truncated): '...{ds[-40:]}'")
        if not ds.lower().startswith("use when"):
            warns.append(f"{skill_path}: description should start with 'Use when'")

    # The regression signature: a key present but emptied out. Also catch blank/whitespace-only
    # entries (e.g. `allowed-tools: [""]`) and scalar misuse without crashing on len().
    for key in ("allowed-tools", "hooks"):
        if key not in data:
            continue
        v = data[key]
        empty = (
            v is None
            or (isinstance(v, (list, dict, str)) and len(v) == 0)
            or (isinstance(v, list) and all(not str(x).strip() for x in v))
            or (isinstance(v, str) and not v.strip())
        )
        if empty:
            errs.append(f"{skill_path}: '{key}' present but EMPTY (lost its value?)")

    return errs, warns


def main():
    args = sys.argv[1:]
    roots = [a for a in args if a != "--strict"]
    strict = "--strict" in args
    # Default: scan ALL tracked *SKILL.md at any depth (identical coverage to the reusable
    # checks.yml gate), skipping vendored/archived nested collections. Explicit roots (args)
    # use a one-level glob for ad-hoc scoping.
    skip = ("/references/", "/_external/", "/_consolidated", "/_archived", "/node_modules/", "/dist/")
    if roots:
        skills = sorted(s for r in roots for s in glob.glob(os.path.join(r, "*", "SKILL.md")))
    else:
        tracked = subprocess.run(
            ["git", "ls-files", "*SKILL.md"], capture_output=True, text=True
        ).stdout.splitlines()
        skills = sorted(f for f in tracked if not any(x in "/" + f for x in skip))
    if not skills:
        print("no SKILL.md found", file=sys.stderr)
        return 1

    all_errs, all_warns = [], []
    for sk in skills:
        e, w = check(sk)
        all_errs += e
        all_warns += w

    for w in all_warns:
        print(f"WARN  {w}")
    for e in all_errs:
        print(f"ERROR {e}")

    fail = bool(all_errs) or (strict and bool(all_warns))
    print(f"\nvalidated {len(skills)} skills — {len(all_errs)} errors, {len(all_warns)} warnings"
          + (" [strict]" if strict else ""))
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
