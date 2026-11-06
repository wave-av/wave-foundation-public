#!/usr/bin/env bash
# run-local — run registry-declared gates in a CLEAN x86_64 container, and emit a receipt.
#
# WHY THIS EXISTS (#929). Running a gate on the dev machine does not tell you what CI will say. This
# Mac is arm64, resolves `grep` to `ugrep`, and exports NODE_ENV=production — all three have already
# produced verdicts that disagreed with CI, including a secret-scan pipeline that read CLEAN locally
# and DETECTED in a container on the same tree (#926). So the gate runs where CI runs: x86_64 Linux,
# GNU coreutils, empty environment. The container inherits nothing from your shell, which is the
# point — it is for FIDELITY, not for horsepower.
#
# It deliberately runs the SAME script files CI runs (frameworks/gates/scripts/*.sh, declared in
# registry.yaml). It does not reimplement them. A local runner that reimplements its gates is a
# second source of truth, which is the exact defect #926 documents.
#
# Usage:
#   run-local.sh [gate-id ...]        # default: every gate in registry.yaml with a script under gates/
#   WAVECI_HOST=user@runner run-local.sh secret-scan   # or put the address in ~/.config/waveci/host
#
# Exit codes — a red pre-push must be unambiguous about WHY:
#   0  every gate passed
#   1  a GATE failed (your code)
#   2  INFRASTRUCTURE failed (host unreachable, rsync/docker/image error, missing script)
#      Never conflated: an unreachable CI host must never read as "clean".
set -euo pipefail

# Sourced before anything else: the verifier reads what this script writes, so the repo-name, gate
# list and receipt path must come from ONE definition, not two that agree today. See the lib header.
HERE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frameworks/gates/scripts/lib/waveci-common.sh
. "$HERE_LIB/lib/waveci-common.sh"

# WHY THERE IS NO ADDRESS IN THIS FILE. `frameworks/` is mirrored to a PUBLIC repo, and the runner is
# reached over Tailscale — its CGNAT address is internal infrastructure. The open-core
# audit holds back any publishable file containing one, which meant this script (and the README) sat
# permanently un-mirrorable, and `open-core-audit` is a REQUIRED check, so nothing in the repo could
# merge. Allowlisting the file would have made the audit green while publishing the address, which is
# the opposite of what the gate is for. So the address lives OUTSIDE the repo.
#
# Precedence: $WAVECI_HOST, else a one-line config file. Unset is INFRASTRUCTURE (exit 2), not a gate
# failure — "I have not configured the runner" is not evidence about your code, and pre-push.sh's
# policy already routes 2 to allow-with-a-warning-and-no-receipt.
HOST="${WAVECI_HOST:-}"
HOST_FILE="${WAVECI_HOST_FILE:-$HOME/.config/waveci/host}"
if [ -z "$HOST" ] && [ -f "$HOST_FILE" ]; then
  HOST=$(tr -d '[:space:]' <"$HOST_FILE")
fi
# Pinned by DIGEST, not tag. A moving tag would make the "same computation as CI" claim false across
# time — the same argument this repo already applies to SHA-pinned actions.
IMAGE="${WAVECI_IMAGE:-debian@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df}"
REMOTE_ROOT="/var/tmp/waveci"
MARKER=".waveci-workdir"    # see hardening note on rsync --delete below

die_infra() { echo "run-local: INFRA: $*" >&2; exit 2; }

# Checked HERE, not where HOST is assigned: die_infra is defined just above, and calling it earlier
# would be an undefined function — `command not found`, exit 127, which pre-push.sh classifies as
# infrastructure anyway but reports as a mystery instead of the one-line fix.
[ -n "$HOST" ] || die_infra "no runner configured. Set WAVECI_HOST=user@host, or put that one line in
       $HOST_FILE — the address is internal infrastructure, deliberately not committed because this
       tree is mirrored publicly (scripts/sync-public.sh)."

command -v rsync >/dev/null || die_infra "rsync not found locally"
command -v docker >/dev/null || die_infra "docker CLI not found locally"

ROOT=$(git rev-parse --show-toplevel) || die_infra "not inside a git repo"
cd "$ROOT"
SHA=$(git rev-parse HEAD)

# #934 — rsync ships the WORKING TREE, so the commit is not what ran whenever the tree is dirty,
# which for a pre-push runner is the normal case and the entire reason the tool exists. A receipt
# saying `"sha": <commit>` then asserts that a COMMIT passed while what actually ran was that commit
# plus uncommitted edits. Observed self-refuting in the wild: a receipt keyed d23a5d7c recorded a
# `gate_file_sha256` belonging to a different commit entirely.
#
# Refusing to run on a dirty tree would be the wrong fix — a runner that only works on clean
# checkouts is a runner nobody reaches for before a push. So the receipt is made to say what it
# actually knows. The derivation lives in the lib (#967) because this script cannot execute outside
# a session with the runner host, and the property was therefore untestable where it sat.
IFS=$'\t' read -r DIRTY TREE_ID < <(waveci_tree_state)

# REPO derivation and its validation live in the shared lib because the VERIFIER has to compute the
# identical value — it reads the receipt this script writes. Two copies plus a comment saying "keep
# these in sync" is the exact contract #926 proved nobody enforces; a verifier that derived the path
# even slightly differently would report "unverified" for receipts that exist, and the natural fix
# would be to stop trusting the verifier.
#
# HARDENING — `rsync --delete` into a mis-derived remote path is destructive on the CI host, so the
# derived name is validated rather than trusted.
REPO=$(waveci_repo_name "$ROOT")
waveci_repo_name_ok "$REPO" || die_infra "refusing to sync: unsafe repo name '$REPO'"
DEST="$REMOTE_ROOT/$REPO"

# Second belt: --delete only ever runs against a directory WE created and marked. A typo can then
# neither create-and-wipe an arbitrary path nor delete something that was already there.
ssh -o BatchMode=yes "$HOST" "mkdir -p '$DEST' && touch '$DEST/$MARKER' && test -f '$DEST/$MARKER'" \
  || die_infra "cannot prepare $HOST:$DEST"

# Ship the tree. --delete keeps the remote an exact mirror so a deleted file cannot linger and mask a
# failure; the .gitignore filter and .git exclusion keep it to roughly what actions/checkout sees.
# This is the incremental step that takes a warm run from ~1m50s (full tar stream) to seconds.
rsync -a --delete --delete-excluded \
      --filter=':- .gitignore' --exclude='.git/' --exclude="$MARKER" \
      -e "ssh -o BatchMode=yes" "$ROOT/" "$HOST:$DEST/" >/dev/null \
  || die_infra "rsync to $HOST:$DEST failed"

# Which gates? Read the registry so this can never drift from what CI runs — as `id<TAB>script`,
# because an id is NOT its filename (see the lib). Named ids on the command line are resolved
# through the same registry rather than pattern-matched into a path.
mapfile -t REGISTRY_ROWS < <(waveci_registry_gates) \
  || die_infra "could not read frameworks/gates/registry.yaml"
GATES=()
if [ "$#" -gt 0 ]; then
  for want in "$@"; do
    row=""
    for r in "${REGISTRY_ROWS[@]}"; do
      [ "${r%%$'\t'*}" = "$want" ] && { row="$r"; break; }
    done
    [ -n "$row" ] || die_infra "gate '$want' is not a runnable gate in registry.yaml"
    GATES+=("$row")
  done
else
  GATES=("${REGISTRY_ROWS[@]}")
fi
[ "${#GATES[@]}" -gt 0 ] || die_infra "no runnable gates found"

RECEIPT_DIR="$(waveci_receipt_dir)"
mkdir -p "$RECEIPT_DIR"
RECEIPT="$(waveci_receipt_path "$RECEIPT_DIR" "$REPO" "$SHA" "$DIRTY" "$TREE_ID")"
rows=(); worst=0

for row in "${GATES[@]}"; do
  gate="${row%%$'\t'*}"
  script="${row#*$'\t'}"
  [ -f "$script" ] || die_infra "gate '$gate' has no script at $script"
  gate_sha=$(shasum -a 256 "$script" | cut -d' ' -f1)

  # `|| true` around the capture ONLY — an infra failure inside docker still surfaces, because a
  # missing image or unreachable daemon exits 125/126/127, which we separate from a gate's 1.
  set +e
  out=$(DOCKER_HOST="ssh://$HOST" docker run --rm \
          --network none --read-only --tmpfs /tmp \
          --cap-drop ALL --security-opt no-new-privileges \
          --pids-limit 512 --memory 2g \
          -v "$DEST:/w:ro" -w /w "$IMAGE" bash "$script" 2>&1)
  rc=$?
  set -e
  case "$rc" in
    0) echo "  ✓ $gate" ;;
    1) echo "  ✗ $gate"; printf '%s\n' "$out" | sed 's/^/      /'; [ "$worst" -lt 1 ] && worst=1 ;;
    *) printf '%s\n' "$out" | sed 's/^/      /' >&2; die_infra "docker exited $rc running '$gate'" ;;
  esac

  # RECEIPT CONTENT — deliberately no gate output; see waveci_gate_row for why the hash is all that
  # is kept. `gate_sha` above hashes the WORKING TREE copy on purpose: the working tree is what got
  # rsynced and therefore what actually ran. verify-receipt.sh recomputes it from `git show <sha>:`,
  # and the two agree exactly when the tree is clean — which is the only case it will read, because a
  # dirty run lands under a filename it never consults.
  out_sha=$(printf '%s' "$out" | shasum -a 256 | cut -d' ' -f1)
  rows+=("$(waveci_gate_row "$gate" "$gate_sha" "$rc" "$out_sha")")
done

# The receipt is an INTEGRITY AID, NOT AN AUTHENTICATION MECHANISM. It is unsigned: anyone with write
# access to the receipt dir can author one by hand. It exists so "I ran the gates" is checkable
# against a specific commit AND a specific gate version — `gate_file_sha256` is what stops a stale
# receipt from vouching for a gate whose logic has since changed. It is NOT evidence against a
# motivated local user, and nothing downstream should treat it as such. Signing it would buy
# tamper-evidence at the cost of key management on every dev machine — not worth it for a tool whose
# threat model is "did I actually run this", not "is this developer lying".
waveci_receipt_json "$REPO" "$SHA" "$DIRTY" "$TREE_ID" "$HOST" "$IMAGE" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ${rows[@]+"${rows[@]}"} > "$RECEIPT"

echo "receipt: $RECEIPT"
# Said out loud, not just recorded. A receipt whose caveat is only legible to something that parses
# JSON is a caveat that gets skipped by the human reading the terminal — and the human is who decides
# whether to push. `dirty` means the gates passed over content that is not in any commit yet.
[ "$DIRTY" = true ] && echo "warning: tree is DIRTY — these gates ran over uncommitted content, NOT over $SHA"
exit "$worst"
