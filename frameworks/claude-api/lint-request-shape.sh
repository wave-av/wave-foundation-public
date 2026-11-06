#!/usr/bin/env bash
# lint-request-shape.sh — block Claude-API request shapes the standard forbids, at commit time.
#
# This is the gate form of frameworks/claude-api/model-matrix.md. It catches the EXACT bug class the
# whole claude-api standard was built to fix (e.g. temperature sent to Opus 4.8 → HTTP 400) BEFORE the
# code lands, in any spoke — instead of discovering it as a 400 in production.
#
# What it flags (hard fail unless escaped):
#   1.  Date-suffixed model IDs        claude-(opus|sonnet|fable|haiku|mythos)-N(-N)?-YYYYMMDD
#                                       (never append a date)
#   2.  budget_tokens                  the MODERN family — Opus ≥4.7, Sonnet ≥5, Fable ≥5, Mythos
#                                       but Preview (fully removed → 400; use adaptive thinking)
#   3.  Sampling params                temperature / top_p / top_k — the MODERN family (removed → 400;
#                                       Opus ≤4.6, Sonnet 4.x and Haiku still accept them)
#   4.  Haiku 4.5 + effort             (output_config.effort errors on Haiku 4.5)
#   5.  Deprecated output_format       (use output_config.format)
#   6.  Opus 5.5 / Fable 5, 5.1 / Mythos 5, 5.1 + disabled thinking   thinking:{type:"disabled"} (400)
#       (the "Never" rows of modern-claude-contract §3's thinking table)
#   7.  Forced tool_choice on Opus 5.5 / Fable 5.1 / Mythos 5.1 / Mythos Preview ONLY (contract §3 v3.4:
#       Opus 4.7/4.8/5, Sonnet 5, Fable 5 and Mythos 5 accept it — models.md:74, model-migration.md:1868)
#       tool_choice:{type:"any"|"tool"}   (400 — "auto"/omitted are unaffected)
#   8.  Assistant-role prefill on the 4.6+ family (Opus ≥4.6 / Sonnet ≥4.6 / Fable ≥5 / Mythos but
#       Preview) a trailing {"role":"assistant",...} to force the response start   (400 — use
#       output_config.format)
#   9.  computer_2025* toolset on Opus 5.5   computer_20251124 / computer_20250124
#       (400 — only computer_toolset_20260801 works there)
#
# What it WARNS about (UNVERIFIED, never fails — contract §3 v3.3 e): disabled thinking in a file that
# names a modern id with NO row in the §3 thinking table (claude-mythos-6, claude-fable-5-2,
# claude-opus-6, …) or claude-mythos-preview (every cell "not stated"), and no rule-6 model. Whether
# that 400s is unverified against the skill; the chassis passes it through and logs it once.
#
# Facts above sourced from the Anthropic claude-api reference bundled with Claude Code 2.1.280
# (fetched 2026-09-22). WHICH model a file names is decided by modern-claude-contract.md §1 (v2), the
# fleet's one family algorithm (normalize -> parse -> compare versions, never string prefixes),
# mirrored from frameworks/model-routing/local_offload/shim/claude_family.py: every Claude id in the
# file is extracted and normalized (lowercase, provider prefix, [1m], '.'->'-', then a trailing
# -YYYYMMDD and -fast in either order, repeated: v3.4), so a dated (claude-opus-4-8-YYYYMMDD), dotted
# aggregator (anthropic/claude-opus-5.5)
# or -fast id gates rules 2-4 and 6-9 exactly like its bare id. Major and minor are one digit each. An
# id that does not parse gates nothing, except a claude-mythos-* id: modern by PREFIX (§1 v2). The
# digitless claude-mythos-preview gates rules 3 and 7 only — the skill has it taking budget_tokens
# thinking (prompt-caching.md:293) and lists thinking config and prefill as breaking changes FROM it
# (model-migration.md:191, :1322), while error-codes.md:125 names it for forced tool_choice.
#
# Scope + false-positive controls:
#   - Only CODE files (py/ts/tsx/js/jsx/mjs/cjs/go/rb/java/kt/cs/php/sh) — NEVER .md, so the standard's
#     own ❌ anti-pattern docs don't trip it.
#   - Patterns 2-4 only fire in files that look Claude-related (mention anthropic / claude- / messages.create
#     / v1/messages), so a generic `temperature` in non-Claude code is ignored.
#   - Escape hatch: a line with `claude-api-lint: ignore`, or any file containing `claude-api-lint: skip`.
#
# Usage:  lint-request-shape.sh [file ...]      # pre-commit passes changed files
#         lint-request-shape.sh                  # no args → scan git-tracked code files
# Exit:   0 clean, 1 violations found (printed to stderr with file:line + the fix). UNVERIFIED warnings
#         (stderr, "⚠") never change the exit status.
set -euo pipefail

CODE_RE='\.(py|ts|tsx|js|jsx|mjs|cjs|go|rb|java|kt|cs|php|sh)$'
DATE_MODEL_RE='claude-(opus|sonnet|fable|haiku|mythos)-[0-9]+(-[0-9]+)?-[0-9]{6,8}'
# Provider-namespaced aggregator slug (<vendor>/claude-…): the aggregator's naming may legitimately
# carry a date suffix (OpenRouter `anthropic/claude-haiku-4-5-20251001`). This rule governs
# Anthropic-DIRECT IDs only, so such slugs are stripped before the date-suffix check. The `/` is the tell.
AGG_SLUG_RE='[A-Za-z0-9_.:-]+/claude-(opus|sonnet|fable|haiku|mythos)[A-Za-z0-9._-]*'
CLAUDE_RE='anthropic|claude-(opus|sonnet|fable|haiku|mythos)|messages\.create|/v1/messages|Anthropic\('
# Model-family detection: modern-claude-contract.md §1 (see the header). ID_TOKEN_RE extracts an
# id-shaped token — family plus '-'/'.'-separated digit groups plus an optional -fast and [1m] — so
# whatever follows an id in source text (".json", a sentence's full stop, "@<date>", "-v1:0") is not
# part of it. Its second branch takes a whole claude-mythos-* id whose first part after the prefix
# starts with a LETTER: digitless claude-mythos-preview (and -preview-2) included, since grep -o keeps
# the longest match. A LETTER, because a branch taking digits there outran the first branch on
# Bedrock/templated Mythos 5.1 ids ("anthropic.claude-mythos-5-1-v1:0" -> claude-mythos-5-1-v1,
# "claude-mythos-5-1-{DATE}" -> claude-mythos-5-1-), which parse as nothing, so rule 7 went quiet.
# ID_PARSE_RE is the contract's grammar — v2: ONE digit each for major and minor — applied AFTER
# normalizing (file_model_ids below).
ID_TOKEN_RE='claude-(opus|sonnet|fable|haiku|mythos)([.-][0-9]+)*(-fast)?(\[1m\])?|claude-mythos-[a-z][a-z0-9]*(-[a-z0-9]+)*'
ID_PARSE_RE='^claude-(opus|sonnet|fable|haiku|mythos)-([0-9])(-([0-9]))?$'
# The input bound (final-review F1, 2026-09-22), MAX_MODEL_ID_LEN in claude_family.py. The suffix loop in
# file_model_ids rescans a token once per suffix it strips (quadratic in its length), so a token longer
# than this is not a Claude id. It gates no rule and is noted once per run. The bound applies to the
# extracted token, which never includes a provider prefix.
MAX_MODEL_ID_LEN=256
overlong_noted=''
SAMPLING_RE='(^|[^a-zA-Z_])(temperature|top_p|top_k)([^a-zA-Z_]|$)'
# quote-agnostic bracket expression (Python/JSON double quotes, JS/TS single quotes) shared by the
# structural patterns below (forced tool_choice, disabled thinking, assistant-role prefill).
Q="['\"]"
# forced tool_choice ({"type":"any"} / {"type":"tool", "name": ...}) — "auto"/"none" are NOT forced
# and must NOT match.
FORCED_TOOL_CHOICE_RE="tool_choice.{0,60}${Q}(any|tool)${Q}"
# thinking:{type:"disabled"} (manual thinking, either enabled or disabled, is rejected on the
# reasoning tier — this rule only needs to catch the "disabled" spelling; "enabled" is covered
# implicitly because these models require adaptive thinking, which is a doc-level, not lint-level, fact).
DISABLED_THINKING_RE='thinking.{0,80}disabled'
# a literal assistant-role message object — the shape a trailing prefill turn takes
# ({"role":"assistant","content":"{"}  /  {'role': 'assistant', ...}).
ASSISTANT_ROLE_RE="${Q}role${Q}[[:space:]]*:[[:space:]]*${Q}assistant${Q}"
# computer_2025* toolset versions (computer_20251124 / computer_20250124) — only
# computer_toolset_20260801 is valid on Opus 5.5.
COMPUTER_2025_RE='computer_2025[0-9]{4}'

# Collect candidate files.
# ENUMERATE ONCE, FAIL CLOSED (#944). `done < <(git ls-files)` cannot propagate the lister's status,
# so a git failure left files=() and the lint printed its ✓ line having read nothing. Vendored into
# spoke repos, so the blast radius is every consumer.
#
# Two fail-open paths here, not one. The `elif git rev-parse` guard means that OUTSIDE a git repo
# the whole enumeration is skipped and the lint passes silently — which reads as "no violations"
# and is really "no input". With no args and no repo there is nothing this lint can be asserting.
files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "claude-api-lint: ✗ not inside a git repository and no file arguments given — nothing to scan. Refusing to report a pass over zero files." >&2
    exit 2
  fi
  list="$(mktemp)"
  chmod 0600 "$list"
  trap 'rm -f "$list"' EXIT
  if ! git ls-files -z >"$list"; then
    echo "claude-api-lint: ✗ git ls-files FAILED — refusing to report a pass over an enumeration that never happened." >&2
    exit 2
  fi
  if [ ! -s "$list" ]; then
    echo "claude-api-lint: ✗ enumerated 0 tracked files. git succeeded, so this is a working-directory problem — refusing to report a pass." >&2
    exit 2
  fi
  while IFS= read -r -d '' f; do files+=("$f"); done <"$list"
fi

violations=0 warnings=0
report() {
  # report <file> <line-no> <message>
  echo "claude-api-lint: ✗ $1:$2" >&2
  echo "    $3" >&2
  violations=$((violations + 1))
}
warn() {
  # warn <file> <line-no> <message> — an UNVERIFIED warning: printed like a report, never fails the lint
  echo "claude-api-lint: ⚠ UNVERIFIED $1:$2" >&2
  echo "    $3" >&2
  warnings=$((warnings + 1))
}

# grep an ERE in a file, emit a report for each hit not carrying the inline-ignore marker.
# Optional $4 = a strip-ERE removed from the line before the hit is re-confirmed — used so a match
# embedded only in an exempt token (e.g. an aggregator slug) doesn't fire. Optional $5 = the reporter
# (default report; warn for an UNVERIFIED warning).
flag_lines() {
  local file="$1" pattern="$2" msg="$3" strip="${4:-}" fn="${5:-report}" hit lineno text probe
  while IFS= read -r hit; do
    lineno="${hit%%:*}"
    text="${hit#*:}"
    case "$text" in *claude-api-lint:\ ignore*) continue ;; esac
    if [ -n "$strip" ]; then
      probe=$(printf '%s' "$text" | sed -E "s#${strip}##g")
      printf '%s' "$probe" | grep -qE "$pattern" || continue # match lived only in an exempt token
    fi
    "$fn" "$file" "$lineno" "$msg"
  done < <(grep -nE "$pattern" "$file" 2>/dev/null || true)
}

# Every Claude model id a file names, normalized per contract §1 (lowercase; drop a provider prefix
# through the last '/'; drop a trailing [1m]; '.' -> '-'; then drop a trailing 8-digit -YYYYMMDD or
# -fast, in either order, until neither is left: v3.4), one per line, deduplicated. The case-insensitive extraction + tr is §1 step 1.
file_model_ids() {
  { grep -oiE "$ID_TOKEN_RE" "$1" 2>/dev/null || true; } |
    tr '[:upper:]' '[:lower:]' |
    awk -v max="$MAX_MODEL_ID_LEN" '{ if (length($0) > max) print "(over-long)"; else print }' |
    sed -E -e 's#^.*/##' -e 's#\[1m\]$##' -e 's#\.#-#g' -e ':a' -e 's#-([0-9]{8}|fast)$##' -e 'ta' |
    sort -u
}

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  printf '%s\n' "$f" | grep -qE "$CODE_RE" || continue
  # Path excludes: honor the repo FIDELITY rule (never rewrite harvested staging/ reference — same
  # set every other hook skips), and don't scan generated/vendored trees or the foundation copy a
  # spoke vendors (which holds this very script + the standard's docs).
  case "$f" in
    staging/* | */node_modules/* | node_modules/* | */dist/* | dist/* | .foundation/* | */vendor/* | vendor/*) continue ;;
  esac
  # file-level skip (e.g. a reference shim that handles these params by design)
  grep -q 'claude-api-lint: skip' "$f" 2>/dev/null && continue

  # 1) date-suffixed model id — always wrong for Anthropic-DIRECT IDs (aggregator slugs are exempt).
  flag_lines "$f" "$DATE_MODEL_RE" "date-suffixed model ID — use the bare ID (e.g. claude-opus-4-8), never append a date." "$AGG_SLUG_RE"

  # patterns 2-5 only in Claude-related files
  grep -qE "$CLAUDE_RE" "$f" 2>/dev/null || continue
  # Model-family flags, from every id the file names, parsed per contract §1 (file_model_ids). ONE
  # flag per rule gate, so a file naming several models (a fallback ladder, a comment listing the
  # family) is still reported at most once per line per rule. An id that does not parse gates nothing
  # but by the mythos prefix. has_modern is the §1 modern family less claude-mythos-preview, which has
  # its own flag (see the header); rule 3 fires on either. `unverified` lists the ids whose thinking is
  # unverified (contract §3 v3.3): Preview, and each modern id with no row in the §3 thinking table.
  has_modern=0 has_46plus=0 has_haiku45=0 has_opus55=0 has_fable5=0 has_fable51=0 has_mythos=0 has_mythos51=0 has_mythos_preview=0
  unverified=''
  while IFS= read -r id; do
    if [ "$id" = '(over-long)' ]; then # the input bound: not a Claude id, so it gates nothing
      [ -n "$overlong_noted" ] || echo "claude-api-lint: note: $f names an id-shaped token over $MAX_MODEL_ID_LEN chars; it is not read as a Claude id (modern-claude-contract §1 input bound)" >&2
      overlong_noted=1
      continue
    fi
    norow=0       # set for a modern id, cleared below if the §3 table has its row
    case "$id" in # §1 v2: every claude-mythos-* id is modern, by PREFIX before parse
      claude-mythos-preview) has_mythos_preview=1 unverified="$unverified $id" ;;
      claude-mythos-*) has_modern=1 has_46plus=1 norow=1 ;;
    esac
    if [[ $id =~ $ID_PARSE_RE ]]; then
      fam=${BASH_REMATCH[1]}
      maj=$((10#${BASH_REMATCH[2]}))
      ver=$((maj * 100 + 10#${BASH_REMATCH[4]:-0})) # (major, minor) as one comparable int: 4.7 -> 407
      # `if`, not `[ … ] && x=1`: a false test must never become the loop's status under `set -e`.
      case "$fam" in
        opus)
          if [ "$ver" -ge 407 ]; then has_modern=1 norow=1; fi
          if [ "$ver" -ge 406 ]; then has_46plus=1; fi
          if [ "$ver" -eq 505 ]; then has_opus55=1; fi
          ;;
        sonnet)
          if [ "$maj" -ge 5 ]; then has_modern=1 norow=1; fi
          if [ "$ver" -ge 406 ]; then has_46plus=1; fi
          ;;
        fable)
          if [ "$maj" -ge 5 ]; then has_modern=1 has_46plus=1 norow=1; fi
          if [ "$ver" -eq 500 ] || [ "$ver" -eq 501 ]; then has_fable5=1; fi
          if [ "$ver" -eq 501 ]; then has_fable51=1; fi
          ;;
        mythos) # modern / 4.6+ come from the prefix case above
          if [ "$ver" -eq 500 ] || [ "$ver" -eq 501 ]; then has_mythos=1; fi
          if [ "$ver" -eq 501 ]; then has_mythos51=1; fi
          ;;
        haiku) # never modern (contract §1)
          if [ "$ver" -eq 405 ]; then has_haiku45=1; fi ;;
      esac
      # the §3 thinking table's rows: the nine keys of claude_family.py's _DISABLED_OK
      case "$fam$ver" in opus407 | opus408 | opus500 | opus505 | sonnet500 | fable500 | fable501 | mythos500 | mythos501) norow=0 ;; esac
    fi
    if [ "$norow" = 1 ]; then unverified="$unverified $id"; fi
  done < <(file_model_ids "$f")

  # 2) budget_tokens — the modern family (contract §1: Opus ≥4.7, Sonnet ≥5, Fable ≥5, Mythos) less
  #    claude-mythos-preview, which takes budget_tokens thinking (prompt-caching.md:293).
  if [ "$has_modern" = 1 ]; then
    flag_lines "$f" '(^|[^a-zA-Z_])budget_tokens([^a-zA-Z_]|$)' \
      "budget_tokens → 400 on the modern family (Opus ≥4.7/Sonnet ≥5/Fable ≥5/Mythos but Preview — fully removed). Use thinking:{type:'adaptive'} + output_config.effort."
  fi
  # 3) sampling params — the modern family. Opus ≤4.6, Sonnet 4.x and Haiku still accept them, so a
  #    file naming only those is not gated (it was, for every claude-opus-4-*, before the §1 rewrite).
  if [ "$has_modern" = 1 ] || [ "$has_mythos_preview" = 1 ]; then
    flag_lines "$f" "$SAMPLING_RE" \
      "temperature/top_p/top_k → 400 on the modern family (Opus ≥4.7/Sonnet ≥5/Fable ≥5/Mythos). Steer via prompting + effort."
  fi
  if [ "$has_haiku45" = 1 ]; then
    flag_lines "$f" '(^|[^a-zA-Z_])effort([^a-zA-Z_]|$)' \
      "output_config.effort errors on Haiku 4.5 — effort is Sonnet-4.6/Opus-4.5+ only."
  fi
  # 6) disabled thinking on the §3 table's "Never" rows — Opus 5.5, Fable 5/5.1, Mythos 5/5.1: thinking
  #    is always on there (the skill's thinking table: Fable 5/5.1 "and the Mythos counterparts" 400 on
  #    it, as Opus 5.5 does). Else, v3.3 (e): an `unverified` id gets a warning, never a hard 400.
  if [ "$has_opus55" = 1 ] || [ "$has_fable5" = 1 ] || [ "$has_mythos" = 1 ]; then
    flag_lines "$f" "$DISABLED_THINKING_RE" \
      "thinking:{type:'disabled'} on Opus 5.5 / Fable 5, 5.1 / Mythos 5, 5.1 → 400 (thinking is always on). Omit thinking, or use {type:'adaptive'}."
  elif [ -n "$unverified" ]; then
    flag_lines "$f" "$DISABLED_THINKING_RE" \
      "thinking:{type:'disabled'} with${unverified}: no verified row in modern-claude-contract §3's thinking table, so whether it 400s is unverified against the claude-api skill (v3.3). A warning, never an error." "" warn
  fi
  # 7) forced tool_choice on Opus 5.5 / Fable 5.1 / Mythos 5.1 / Mythos Preview ONLY (error-codes.md:125;
  #    contract §3 v3.4: every other model accepts it) — {type:"any"} and {type:"tool"} both 400 there;
  #    "auto"/"none"/omitted are unaffected and must NOT match (see FORCED_TOOL_CHOICE_RE).
  if [ "$has_opus55" = 1 ] || [ "$has_fable51" = 1 ] || [ "$has_mythos51" = 1 ] || [ "$has_mythos_preview" = 1 ]; then
    flag_lines "$f" "$FORCED_TOOL_CHOICE_RE" \
      "forced tool_choice ('any'/'tool') on Opus 5.5 / Fable 5.1 / Mythos 5.1 / Mythos Preview → 400. Omit tool_choice (or use 'auto') and let the model choose."
  fi
  # 8) assistant-role prefill on the 4.6+ family (model-matrix.md's Legacy note: Opus 4.6-4.8 +
  #    Sonnet 4.6 reject prefill, Haiku 4.5 still accepts it; the skill extends it to Opus/Sonnet 5,
  #    Fable and Mythos) — a hardcoded trailing {"role":"assistant",...} used to force the response
  #    start. Heuristic (line-scoped, can't see array position): flags any literal assistant-role object
  #    in a gated file; escape a genuine hardcoded history fixture with 'claude-api-lint: ignore'.
  if [ "$has_46plus" = 1 ]; then
    flag_lines "$f" "$ASSISTANT_ROLE_RE" \
      "assistant-role message literal on the 4.6+ family (Opus ≥4.6/Sonnet ≥4.6/Fable/Mythos) — a TRAILING one used as prefill → 400. Use output_config.format for shape; escape a genuine hardcoded conversation-history literal with 'claude-api-lint: ignore'."
  fi
  # 9) computer_2025* toolset versions on Opus 5.5 — only computer_toolset_20260801 is valid there.
  if [ "$has_opus55" = 1 ]; then
    flag_lines "$f" "$COMPUTER_2025_RE" \
      "computer_2025* (e.g. computer_20251124 / computer_20250124) on Opus 5.5 → 400. Use computer_toolset_20260801."
  fi
  # 5) deprecated output_format (but NOT output_config.format)
  while IFS= read -r hit; do
    lineno="${hit%%:*}"
    text="${hit#*:}"
    case "$text" in *output_config*) continue ;; esac
    case "$text" in *claude-api-lint:\ ignore*) continue ;; esac
    report "$f" "$lineno" "output_format is deprecated — use output_config:{format:{...}} on messages.create()."
  done < <(grep -nE '(^|[^a-zA-Z_.])output_format([^a-zA-Z_]|$)' "$f" 2>/dev/null || true)
done

if [ "$violations" -gt 0 ]; then
  echo "claude-api-lint: $violations violation(s). See frameworks/claude-api/model-matrix.md. Escape a deliberate case with 'claude-api-lint: ignore' on the line." >&2
  exit 1
fi
if [ "$warnings" -gt 0 ]; then
  echo "claude-api-lint: ✓ no forbidden Claude-API request shapes ($warnings UNVERIFIED warning(s) above; they never fail the lint)"
else
  echo "claude-api-lint: ✓ no forbidden Claude-API request shapes"
fi
exit 0
