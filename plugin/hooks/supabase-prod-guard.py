#!/usr/bin/env python3
"""PreToolUse guard: BLOCK any write to a Supabase project listed in WAVE_SUPABASE_PROD_REFS
(comma-separated, configured per environment via AGENTS.local.md or shell env). Agents never
direct-edit prod — develop on the staging branch (WAVE_SUPABASE_STAGING_REF), then merge_branch
to promote. Read-only SELECTs on prod are allowed. Reads {tool_name, tool_input} on stdin;
exit 2 = block (reason to stderr).

Covers two attack surfaces:
  1. Supabase MCP tools (apply_migration / execute_sql / ...) targeting a prod project ref.
  2. Bash commands that reach prod directly via psql / a postgres connection string.

Public-extractable: prod-ref literals live in env vars only. Private overlays set the values
via AGENTS.local.md (gitignored) or the agent's shell environment.
"""
import os, sys, json, re

# Read prod refs from environment — comma-separated, whitespace-tolerant. An empty set means
# the hook is inert (suitable for the public open-core copy where the operator hasn't yet
# configured their own prod ref).
PROD_REFS = {r.strip() for r in os.environ.get("WAVE_SUPABASE_PROD_REFS", "").split(",") if r.strip()}
STAGING = os.environ.get("WAVE_SUPABASE_STAGING_REF", "")

# Any write keyword appearing ANYWHERE (not just as a prefix) → treat as a write. This is
# bypass-resistant: multi-statement ("select 1; delete ..."), CTE-wrapped, and SELECT-prefixed
# writes all match. A pure read (no write keyword) is the only thing allowed on prod.
WRITE_RE = re.compile(r"\b(insert|update|delete|drop|alter|create|truncate|grant|revoke|copy|merge)\b")
DO_RE = re.compile(r"\bdo\b\s*\$[a-z0-9_]*\$", re.I)  # PL/pgSQL DO blocks ($$ or $tag$)


def is_write_sql(sql: str) -> bool:
    s = sql.lower()
    return bool(WRITE_RE.search(s) or DO_RE.search(s))


try:
    ev = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = ev.get("tool_name", "")
ti = ev.get("tool_input", {}) or {}

# 1. Bash path — block psql / connection-string writes that target a prod ref.
if tool == "Bash" or tool.endswith("Bash"):
    cmd = str(ti.get("command", ""))
    low = cmd.lower()
    hits_prod = any(ref in low for ref in PROD_REFS)  # case-insensitive
    hits_pg = bool(re.search(r"\bpsql\b|postgres(?:ql)?://", low))
    if hits_prod and hits_pg and (WRITE_RE.search(low) or DO_RE.search(low)):
        print(f"BLOCKED: Bash command targets WAVE PRODUCTION Supabase via psql/connection string. "
              f"Agents NEVER direct-edit prod. Use the staging project ({STAGING}) and promote via merge_branch.",
              file=sys.stderr)
        sys.exit(2)
    sys.exit(0)

# 2. Supabase MCP tools.
if "supabase" not in tool:
    sys.exit(0)
pid = str(ti.get("project_id", "") or ti.get("project_ref", ""))
if pid not in PROD_REFS:
    sys.exit(0)

sql = str(ti.get("query", ""))
# No SELECT-prefix bypass: is_write_sql flags a write keyword anywhere, so a pure read is the
# only thing that clears the guard (fail-safe: over-blocks a read mentioning a write word).
is_write = ("apply_migration" in tool) or is_write_sql(sql)

if is_write:
    print(f"BLOCKED: '{tool}' is a WRITE to WAVE PRODUCTION Supabase ({pid}). "
          f"Agents NEVER direct-edit prod. Develop on the staging branch ({STAGING}), then "
          f"merge_branch to promote. (Read-only SELECT on prod is allowed.)", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
