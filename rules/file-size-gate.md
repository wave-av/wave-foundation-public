# File-Size Gate (two-tier)

Harvested from an internal WAVE repo's `.claude/rules/35-file-size/`. Small files = fast AI reads = composable.

| Gate | Limit | Behavior |
|------|-------|----------|
| **Soft** | 500 lines | Warning. Next feature goes in a new file. Stop adding. |
| **Hard** | 800 lines | BLOCK. Split before merge. No exceptions. |

Exceptions: `*.types.ts`, `*.d.ts`, generated files, event registries.

**Enforcement layers:** rule (AI sees before writing) → pre-commit hook (hard gate) → CI (hard gate) →
review tools (soft gate warning). Dispatch's `eval_gate.py` already enforces this — it's the reference impl.

**Why:** 300-line files use ~84% less context than 1800-line ones; smaller blast radius; faster review;
LEGO-block composability.
