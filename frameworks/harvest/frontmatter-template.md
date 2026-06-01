# Harvest provenance frontmatter — template

Every file harvested into `staging/<source-repo>/` gets this frontmatter block
prepended (HTML-comment form so the file's syntax stays valid for any language).

## Template

```text
<!-- @harvest
source_repo: wave-av/<source-repo>
source_path: <path/from/source/root>
source_sha:  <40-char git sha at time of harvest>
source_url:  https://github.com/wave-av/<source-repo>/blob/<sha>/<path>
harvested_at: <ISO 8601 UTC, e.g. 2026-05-31T00:00:00Z>
harvested_by: <agent-or-username>
reason: <one-line "why is this a foundation candidate"; cite 2+ spokes>
proven_in:
  - wave-av/<repo-1>:<path>
  - wave-av/<repo-2>:<path>
status: harvest      # harvest → review → promoted (mirror of label flow)
promotion_target: frameworks/<which-framework>  # or rules/, taxonomy/, etc.
-->
```

## Why every field is mandatory

| Field | Why |
|-------|-----|
| `source_repo` + `source_path` + `source_sha` | reproducibility — you can `git checkout <sha>` and see the original |
| `source_url` | one-click navigation to the original |
| `harvested_at` + `harvested_by` | accountability + audit trail |
| `reason` | future maintainers need to know *why* this is here, not just where it came from |
| `proven_in` (2+) | enforces the "2+ spokes" rule from `README.md` |
| `status` | tells the promotion gate what state this file is in |
| `promotion_target` | declares intent — where this WILL live once promoted |

## Language-specific framing

For files whose top-line comment syntax isn't `<!-- -->`:

- **Shell scripts (`.sh`)** — wrap in `: <<'HARVEST'` ... `HARVEST` heredoc above
  the shebang, OR use `#` line comments (one per field).
- **SQL (`.sql`)** — use `--` line comments (one per field).
- **TypeScript / JavaScript** — use `/* ... */` block comment.
- **Python (`.py`)** — use `#` line comments (one per field) above the imports.
- **YAML / JSON** — JSON can't carry comments; ship the frontmatter as a
  sibling `.harvest.json` file with the same path. YAML uses `#` line comments.

The `scripts/harvest-from-repo.sh` runner picks the right form per extension.

## Lifecycle of `status`

```
harvest    → file just landed, no review yet
review     → maintainer is curating, may rewrite or generalize in-place
promoted   → a sibling file in canonical (frameworks/, rules/, …) supersedes this;
             staging copy stays for provenance
deprecated → pattern was wrong-fit; do not promote
```

The promotion gate refuses to merge a canonical-path PR if the corresponding
`staging/` file is still in `harvest` status — review must finish first.
