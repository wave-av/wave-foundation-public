# Natural systems — the *why* behind the Ambiguity Gate

**Thesis:** the two hardest problems in a multi-agent estate are **uncertainty** (ambiguity → wrong
action) and **coordination** (many agents, no central controller). Nature already solved both, repeatedly,
in systems with **no central control** — physics relaxes to stable states, cells and colonies coordinate
through a shared environment, viruses thrive on uncertainty by being maximally efficient. We copy those
mechanisms instead of inventing fragile bespoke ones.

The [Ambiguity Gate](./README.md) and its sibling [`agent-lease/`](../agent-lease/) are specific instances
of the patterns below. This file is the map. Each row: **natural mechanism → what it does → our concrete
mechanism → status**.

---

## Biological systems (decentralized coordination + error-correction)

| Mechanism | What it does | Our mechanism | Status |
|---|---|---|---|
| **Stigmergy** (ant pheromone trails) | Agents coordinate via marks left in a shared environment, never by messaging each other | git PRs + task `owner` + `refs/agent-leases` + `DECISIONS.md` are the trail; agents read the environment, not each other | ✅ live (`agent-lease`) |
| **DNA proofreading + mismatch repair** | Verify against a template *before* committing the base; correct errors | The Ambiguity Gate: research against ground truth → record → then act. Read-before-edit. Adversarial verify. | ✅ live (the gate) |
| **Quorum sensing** (bacteria act only at signal threshold) | Don't commit to a costly action until enough independent signals agree | N-of-M adversarial verify before accepting a finding; an ADR requires cited evidence (≥1 verified fact) before acting | ✅ partial |
| **Homeostasis / negative feedback** | Sensors detect drift → corrective loop returns to setpoint | CI ratchets + foundation gate + drift checks keep the codebase at "green"; the sweep auto-unblocks behind PRs | ✅ live |
| **Apoptosis** (programmed cell death) | Damaged/obsolete components self-remove cleanly | Archive superseded repos, retire dead workflows, close no-op PRs (each a recorded decision) | ✅ live |
| **Immune self/non-self + layered defense** | Distinguish self; defense in depth; allowlist "self" | Fail-closed auth, layered gate (secret-scan → size → skill), `# pragma: allowlist secret` = "self" markers | ✅ live |
| **Degeneracy / redundancy** (many paths, one function) | Survive single-path failure | Fallback chains (local → OpenRouter → hosted); multi-rail settlement; multiple canonical wallets | 🔵 in progress |

## Physics (relaxation to stable states + conserved invariants)

| Mechanism | What it does | Our mechanism | Status |
|---|---|---|---|
| **Relaxation to ground state / least action** | Systems settle to the lowest-energy stable configuration | Converge to ONE source-of-truth; "one hub, thin spokes"; collapse many systems into the gateway | ✅ live |
| **Conservation laws / invariants** | Quantities that must hold across any transform | Invariant tests (spoke no-auth / attribution / no-cache; passthrough-byte-identity harness) | ✅ live |
| **Error-correcting codes** | Redundancy detects + repairs corruption | Idempotency; `git ls-tree HEAD \| wc -l` verify after a worktree-corruption incident; atomic Git-Data-API commits | ✅ live |
| **Locality / no action-at-a-distance** | Effects propagate through local interactions, not jumps | Edit the *source*, let sync propagate; never reach across the public/private boundary (gate trigger #4; ADR-002, ADR-004) | ✅ live (the gate) |
| **Metastability + a kick** | A stuck local minimum needs energy to escape | Merge-queue deadlock → close/reopen to un-stick (a deliberate kick) | ✅ known |
| **Annealing** (explore hot → settle cool) | Broad exploration first, then converge | Brainstorm / judge-panel → synthesize → single decision; workflow fan-out → dedupe → act | ✅ live |
| **Non-perturbing measurement** | Observe without changing state | Read-only probes (positive e2e, no minting); `--dry-run`; clone-and-inspect before mutate | ✅ live (the gate) |

## Viral / epidemic systems (efficiency + propagation under uncertainty)

Viruses **thrive on uncertainty and act efficiently** — minimal genome, maximal effect. We adopt the
*strategy* (efficient, propagating, resilient change), defensively.

| Mechanism | What it does | Our mechanism | Status |
|---|---|---|---|
| **Minimal payload / hijack host machinery** | Carry almost nothing; use the host's ribosomes | Reuse existing infra over building new: vendor the proven `_checks.yml`; use the gate/scaffolder; smallest diff that works | ✅ live |
| **Single insertion point → exponential propagation** | One infection replicates through the whole host | Fix the **generator**, not the instances: the scaffolder governs *every future repo*; a moving `@v1` tag propagates to every consumer on one edit | ✅ live |
| **Receptor specificity (targeting)** | Bind only the right cell → precise, low-waste | Precise clear-air strikes: hot-repo avoidance + lease + open-PR check select exactly the safe, high-leverage target | ✅ live (`agent-lease`) |
| **Lysogeny / dormancy** | Integrate into the genome; activate when conditions are right | Wired-but-inert features behind flags + dependency gates; scaffolds that activate when prereqs land; `[OPERATOR]`-gated tasks | ✅ live |
| **Antigenic drift / quasispecies** | A population of variants survives changing defenses | Ratchets that survive back-merge drift; multiple approaches in a judge panel; gate pinned to a moving `@v1` (adapts without breaking) | ✅ live |
| **R0 / herd immunity (defensive inverse)** | Propagation stops when enough nodes are immune | Org-wide governance fan-out: every repo carries the gate → a bad change can't spread | 🔵 in progress |

---

## The meta-principle

**Decentralized, evidence-driven, minimal-footprint, self-propagating, fail-closed.** No central
controller; coordinate through shared state (stigmergy); never act on ambiguity without proofreading
against ground truth (DNA repair / the Ambiguity Gate); make the smallest change at the highest-leverage
insertion point (viral); converge to one stable source-of-truth (physics); keep invariants and self-heal
(homeostasis). When designing any new system or agent behavior, ask: *what does the cell / the colony /
the virus / the equilibrium do here?* — then copy it.
