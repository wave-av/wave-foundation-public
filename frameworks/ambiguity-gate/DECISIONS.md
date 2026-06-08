# DECISIONS — Ambiguity Resolution Log (ADRs)

The durable trail of cross-repo ambiguities the WAVE build has hit and **resolved with evidence**. Per the
[Ambiguity Gate](./README.md): before acting on anything ambiguous, **check here first** — if it's
recorded, inherit the decision; acting against a recorded ADR without *new* evidence is a bug. If your
ambiguity isn't here, run the gate (DETECT → RESEARCH → RECORD → ACT), then append an entry.

This is the **canonical ADR home** for ambiguities that affect more than one repo. Project-local
ambiguities may live in a project's own `DECISIONS.md`; anything cross-repo is recorded here so every
consumer inherits it.

Format: **claim → evidence (ground truth, not belief) → decision → reversible?**

## ADR log

### ADR-001 — WSC→public sync: keep canonical, retire legacy (don't delete both)

- **Ambiguity:** two competing sync workflows (`public-repo-sync.yml` vs `sync-public-repos.yml`); a prior handoff said "delete both."
- **Evidence:** legacy `sync-public-repos.yml` (push:main, hardcoded 7-mirror matrix) has been dead since 2026-04-17 and can't cross-repo push with a repo-scoped `GITHUB_TOKEN`; the canonical `public-repo-sync.yml` (push:staging, dynamic private:false detection) is the live one — but the legacy script `sync-to-public.sh` holds the only real 5-gate security checks.
- **Decision:** retire the legacy workflow, KEEP its security scripts; deeper consolidation is a follow-up. Deleting both would have discarded the only working gates.
- **Reversible:** yes (PR).

### ADR-002 — Public repos vendor `_checks.yml` (cannot consume the private foundation reusable workflow)

- **Ambiguity:** should a public edge repo's gate `uses: wave-av/wave-foundation/.github/workflows/checks.yml@v1` (the consumer-gate example) or a local copy?
- **Evidence:** GitHub Actions does NOT let a public repo consume a PRIVATE repo's reusable workflow — tested end-to-end on a public edge repo (the call fails in 0s, 0 jobs; the org-access setting had no effect).
- **Decision:** public repos vendor `_checks.yml` verbatim (byte-synced to foundation `checks.yml@v1`) + a thin `foundation-gate.yml` wrapper. PRIVATE repos use the `@v1` consume path.
- **Reversible:** yes.

### ADR-003 — Supabase anon key is public-by-design: scrub, never rotate

- **Ambiguity:** a leaked anon JWT in an edge `wrangler.toml` — rotate it?
- **Evidence:** the anon key is public by design (RLS is the real boundary); rotating it = rotating the project JWT secret = invalidates service_role + every session = prod-wide outage.
- **Decision:** scrub from git + serve as a Worker secret from Doppler. Do NOT rotate.
- **Reversible:** scrub yes; rotation would NOT be → never do it.

### ADR-004 — dispatch-edge is a one-way sync MIRROR; ship in PRIVATE wave-dispatch (RESOLVED 2026-06-01, HIGH confidence)

- **Ambiguity:** the agent-commerce plan says "ship features on dispatch-edge," but dispatch-edge is a public open-core repo.
- **Evidence (ground-truth recon):** `wave-dispatch/scripts/sync-public.sh` is one-way PRIVATE→PUBLIC — it clones the public mirror, copies a FIXED open-core subset (README, sdk-README, threat-model, BENCHMARKS, LICENSE, wrangler.example.toml, `sdk/{js,python,rust,ruby}`) into it, and `--force-with-lease`-pushes a PR to mirror master (triggered by `sync-public.yml` on push to master). **CRITICAL NUANCE:** `edge-router/worker.ts` is DELIBERATELY EXCLUDED from the sync — the public worker is a separately hand-curated reference artifact that strips proprietary routing/billing. dispatch-edge is NOT a fork (fork:false, parent:null) and has NO build/test/deploy CI (only `_checks.yml` + `foundation-gate.yml`); the real pipeline + the live deploy config live ONLY in private wave-dispatch. Sync commits are bot-authored. `rules/polyrepo-topology.md` codifies it: wave-dispatch = "Private canonical spoke…source-of-truth"; dispatch-edge = "Public mirror…one-way PR-synced…a mirror, never a fork — humans don't edit it directly."
- **Decision:** ALL worker/routing/x402/MPP/discovery/billing CODE lands in PRIVATE `wave-dispatch/edge-router/`. Update the public surface ONLY via (a) the auto-sync subset (edit the private overlay + `sdk/{js,python,rust,ruby}`, merge to master, let `sync-public.yml` PR it), or (b) for the public reference `worker.ts`, a SEPARATE hand-curated PR that omits proprietary logic. NEVER hand-edit auto-synced files in dispatch-edge (clobbered); NEVER treat dispatch-edge as the build/deploy target.
- **Reversible:** yes — canonical/mirror is a per-repo policy choice; until a flip is explicitly recorded, dispatch-edge stays a mirror.

### ADR-005 — Do NOT re-add the foundation pin-check (deliberately-removed anti-pattern)

- **Ambiguity:** add a `consume.sh --check` pin-drift CI job.
- **Evidence:** foundation `CONSUME.md` + `examples/consumer-gate.yml` explicitly state the SHA-equality pin-check was removed because, as a required check, it turns every foundation commit into a merge-blocking red on every downstream PR. The moving `@v1` tag already keeps the executable gate current.
- **Decision:** closed won't-do. The scaffolder pins `.foundation-version=v1` (major only), no SHA pin-check.
- **Reversible:** n/a.

### ADR-006 — On-prem gate backfill: additive + advisory, no branch-protection flip

- **Ambiguity:** add a *required* gate to the on-prem repos, while another agent has open PRs there?
- **Evidence:** `required_status_checks` = none on all the target repos (currently unprotected); the on-prem agent has 2–3 open PRs per repo.
- **Decision:** add the gate as advisory (new files only, no branch-protection change) so in-flight PRs aren't blocked. Flipping `gate / checks` to required + applying protection is a follow-up after the scaffold PRs land. **This is the precedent the Ambiguity Gate's own enforcement follows — advisory, never blocking.**
- **Reversible:** yes.

### ADR-007 — Canonical WSC reference = `origin/staging`

- **Ambiguity:** main vs staging vs a `phase1` repo/branch.
- **Evidence:** `origin/staging` is latest; `main` lags (promotion target); the local checkout is stale/diverged; no `phase1` repo or branch exists.
- **Decision:** always read latest from `origin/staging`; treat WSC as read-only reference (build in NEW repos).
- **Reversible:** n/a.

---

## Append template

Copy this block, fill it in, bump the number. Keep entries short — claim, the *verified* evidence, the
decision, and whether it can be undone. No evidence → not resolved → escalate, don't append.

```markdown
### ADR-NNN — <one-line decision title>
- **Ambiguity:** <the competing interpretations — name BOTH sides (gate step 1).>
- **Evidence:** <ground truth, not belief: the file you read, the `gh`/`curl`/`git ls-remote` output, the sandbox test, the reference repo you compared against (gate step 2).>
- **Decision:** <what we do now, and the one-line reason the evidence forces it.>
- **Reversible:** <yes (how) | no (so we're extra-sure) | n/a.>
```

> The PR/commit that acts on this ADR references it (`Refs DECISIONS.md ADR-NNN`) so the next agent
> inherits the resolution (gate step 4).
