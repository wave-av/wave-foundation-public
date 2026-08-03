#!/usr/bin/env bash
# waveci-common.sh — the facts run-local.sh, verify-receipt.sh and pre-push.sh must agree on.
#
# This file exists because of #926. That issue is about one gate living in four places and drifting
# two ways; the same failure was about to happen here, one layer down. The runner WRITES a receipt
# and the verifier READS it, so they must derive the repo name, the receipt path and the gate list
# identically — and "identically" held by two copies and a comment is exactly the contract #926
# proved nobody enforces. If the verifier computed a receipt path even slightly differently it would
# report "unverified" for receipts that exist, and the natural fix would be to stop trusting the
# verifier.
#
# Sourced, never executed. No side effects beyond defining functions; callers set their own `set`
# flags, so nothing here depends on -e being on or off.

# waveci_repo_name — identifies the PROJECT, never the checkout.
#
# `basename "$ROOT"` looks right and is wrong: in a git worktree it yields the scratch directory
# name (`wf-runner-4a91c`), which gives every worktree its own remote sync path (so the warm rsync
# cache is never shared and each pays a full cold sync) and keys receipts by a throwaway name no
# verifier can resolve. Prefer the origin remote; fall back to the MAIN checkout's directory
# (git-common-dir points at the real repo, not the worktree); only then basename.
#
# `basename … .git` rather than a regex ON PURPOSE: BSD sed (macOS) rejects the non-greedy `+?` that
# GNU sed accepts, so a regex here fails on exactly the platform this runs from. basename handles
# both `git@host:org/repo.git` and `https://host/org/repo.git` portably.
waveci_repo_name() {
  local root="$1" origin_url repo common
  origin_url=$(git config --get remote.origin.url 2>/dev/null || true)
  repo=""
  [ -n "$origin_url" ] && repo=$(basename "$origin_url" .git)
  if [ -z "$repo" ]; then
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    repo=$(basename "$(dirname "${common:-$root/.git}")")
  fi
  printf '%s' "$repo"
}

# waveci_repo_name_ok — the repo name reaches an `rsync --delete` destination on the CI host and a
# receipt filename, so it is validated rather than trusted. The `case` is not redundant with the
# regex: it rejects the traversal and degenerate forms explicitly, which is the failure a reader
# checks for first.
waveci_repo_name_ok() {
  case "$1" in
    ""|"."|".."|*/*) return 1 ;;
  esac
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

waveci_sha_ok() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }

# A gate id becomes a path segment (`frameworks/gates/scripts/<id>.sh`) and a `git show` argument, so
# it is charset-validated before use. Ids come from registry.yaml today, but the verifier also reads
# them out of a receipt file, which is plain JSON on disk that anything can write.
waveci_gate_id_ok() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

waveci_receipt_dir() { printf '%s' "${WAVECI_RECEIPTS:-$HOME/.claude/state/waveci-receipts}"; }

# ── The receipt writer (#967) ────────────────────────────────────────────────────────────────────
#
# These three used to be inlined in run-local.sh, which rsyncs to a remote host and execs docker —
# so nothing could execute them, and every property verify-receipt.sh checks was a property NOTHING
# asserted the writer emits. The reader's drill builds its fixtures BY HAND, which is right for a
# reader (it can then exercise malformed receipts a real writer would never produce) but means those
# fixtures encoded an *understanding* of the format rather than the writer's behaviour. Extracted
# here, the format has one definition and `test-run-local.sh` can round-trip it through the real
# verifier with no network and no container.

# waveci_tree_state — prints `<dirty>\t<tree_id>`: `false\tclean`, or `true\tdirty-<12 hex>`.
#
# #934: rsync ships the WORKING TREE, so on a dirty tree the commit is not what ran — and for a
# pre-push runner dirty is the normal case. The porcelain status is fingerprinted so the receipt can
# say so, and so a dirty run and a clean run at the same sha get different filenames.
#
# The `-z` output is PIPED, never captured into a variable first: command substitution strips NUL
# bytes (bash warns), which runs the record separators together and makes two different dirty states
# hash alike. A fingerprint that quietly loses resolution is worse than none, because it still looks
# authoritative — test-run-local.sh case N pins this with a real collision pair.
#
# This hashes the STATUS, not file contents: two dirty runs with different edits to the same file
# collide. Deliberate cost ceiling (hashing the payload means a second full tree walk per run), and
# still strictly better than today's alternative, where dirty is invisible.
# The trailing newline is LOAD-BEARING, not formatting. run-local.sh consumes this with
# `read -r DIRTY TREE_ID < <(waveci_tree_state)` under `set -e`, and `read` returns 1 when it hits
# EOF without a delimiter — so an unterminated line sets both variables correctly and then kills the
# runner on the very next statement. Caught by case A0, which is why that case exists.
waveci_tree_state() {
  if git diff --quiet HEAD 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    printf 'false\tclean\n'
  else
    printf 'true\tdirty-%s\n' "$(git status --porcelain=v1 -z 2>/dev/null | shasum -a 256 | cut -c1-12)"
  fi
}

# waveci_receipt_path <dir> <repo> <sha> <dirty> <tree_id>
#
# A clean run keeps the historical `<repo>-<sha>.json` name byte-identical, so existing receipts stay
# comparable and verify-receipt.sh — which only ever consults that name — is unaffected. Only a dirty
# run gets the extra segment, and that is the run that was previously indistinguishable: before #935
# a dirty run OVERWROTE the clean receipt at the same sha, which is how a receipt keyed d23a5d7c came
# to carry a gate_file_sha256 from a different commit.
waveci_receipt_path() {
  if [ "$4" = true ]; then printf '%s/%s-%s-%s.json' "$1" "$2" "$3" "$5"
  else printf '%s/%s-%s.json' "$1" "$2" "$3"; fi
}

# waveci_gate_row <gate> <gate_file_sha256> <exit_code> <output_sha256>
#
# One gate's entry. Every field here is a field verify-receipt.sh reads, so the shape is defined once
# rather than in the writer and again in whatever test claims to check the writer.
#
# `output_sha256` is a HASH, never the output: secret-scan PRINTS credential-shaped lines when it
# fails, and persisting those would make the receipt store a new place credentials come to rest. The
# hash still proves two runs produced the same result.
waveci_gate_row() {
  printf '{"gate":"%s","gate_file_sha256":"%s","exit_code":%s,"output_sha256":"%s"}' "$1" "$2" "$3" "$4"
}

# waveci_receipt_json <repo> <sha> <dirty> <tree_id> <host> <image> <ts> [<gate-row-json> ...]
#
# `dirty` is emitted as a JSON BOOLEAN, unquoted. verify-receipt.sh tests `d.get("dirty") is not
# False`, so a `"false"` STRING would make every receipt silently unverifiable and the failure would
# look like a verifier bug. The literal is validated rather than trusted for that reason.
#
# NOT escaped: host and image are interpolated raw, so a `WAVECI_HOST` containing a quote can forge
# fields (later duplicate keys win in json.load). That is knowingly accepted — this file is unsigned
# and lives in a directory the local user can write, so anyone who can set that env var can equally
# author the receipt by hand. See the threat-model note in verify-receipt.sh's header.
waveci_receipt_json() {
  local repo="$1" sha="$2" dirty="$3" tree_id="$4" host="$5" image="$6" ts="$7" joined="" r
  case "$dirty" in true|false) ;; *) echo "waveci_receipt_json: dirty must be true|false, got '$dirty'" >&2; return 1 ;; esac
  shift 7
  for r in ${1+"$@"}; do
    [ -n "$joined" ] && joined="$joined,"
    joined="$joined$r"
  done
  printf '{"repo":"%s","sha":"%s","dirty":%s,"tree_id":"%s","host":"%s","image":"%s","ts":"%s","gates":[%s]}\n' \
    "$repo" "$sha" "$dirty" "$tree_id" "$host" "$image" "$ts" "$joined"
}

# waveci_registry_gates — runnable gates as `id<TAB>script`, read from registry.yaml so this can
# never drift from what CI runs. Only gates whose script lives under frameworks/gates/scripts/ are
# runnable in the container; the others (commit-msg hooks, vendored linters) have different
# invocation contracts.
#
# ⚠️ THE SCRIPT PATH IS RETURNED, NOT RECONSTRUCTED. An id is not its filename: of the four runnable
# gates, three disagree (`file-size` -> `check-file-size.sh`, `model-string` ->
# `check-model-strings.sh`, `model-thinking-capability` -> `check-model-thinking-capability.sh`).
# Deriving `scripts/<id>.sh` is why run-local.sh's own documented default — "every gate in
# registry.yaml" — died INFRA on the second gate and had never once run to completion. The registry
# already states the path; anything that guesses it instead is a second source of truth.
waveci_registry_gates() {
  python3 - "${1:-frameworks/gates/registry.yaml}" <<'PY'
import re, sys, pathlib
txt = pathlib.Path(sys.argv[1]).read_text()
for gid, script in re.findall(r"^  - id:\s*(\S+)(?:.|\n)*?^    script:\s*(\S+)", txt, re.M):
    if script.startswith("frameworks/gates/scripts/"):
        print(f"{gid}\t{script}")
PY
}
