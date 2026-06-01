# Provenance: lifted near-verbatim from wave-av/wave-dispatch cost_decision.py (T32). See CHASSIS.md.
"""Decision-theoretic escalation gate — replaces an arbitrary confidence threshold.

The right question isn't "is confidence high?" but "does the EXPECTED cost of running local
exceed the price of escalating to a frontier?". Minimize expected cost:

    E[cost | local]    = (1 - p_local)  * C_bad
    E[cost | escalate] = C_claude + (1 - p_claude) * C_bad

Escalate iff E[escalate] < E[local]. Solving gives a BREAKEVEN local success-prob; the threshold
falls straight out of the cost ratio — no magic number. Pure stdlib.

Module functions preserve the engine's exact behavior. `CostPolicy` wraps the cost constants in an
overridable dataclass so a spoke can retune without editing this vendored file.
"""
from __future__ import annotations

from dataclasses import dataclass

# units match the engine's route_metric.cost: a wrong shipped answer = 5, frontier spend = 3.
C_BAD = 5.0       # cost of shipping a wrong answer (under-escalation)
C_CLAUDE = 3.0    # cost (frontier spend) of escalating — the thing the local tier avoids
P_CLAUDE = 0.97   # assumed P(correct) once escalated

_DIFF_PENALTY = {"low": 0.0, "medium": 0.10, "high": 0.25}


def breakeven_p(c_bad=C_BAD, c_claude=C_CLAUDE, p_claude=P_CLAUDE):
    """Local success-prob below which escalation is cheaper in expectation (≈0.37 at defaults)."""
    return 1.0 - (c_claude / c_bad) - (1.0 - p_claude)


def calibrate(confidence, difficulty="medium", shrink=0.85, base=0.5):
    """Shrink overconfident self-reported confidence toward a base rate; penalize hard tasks."""
    p = base + shrink * (float(confidence) - base)
    return max(0.0, min(1.0, p - _DIFF_PENALTY.get(difficulty, 0.10)))


def decide(confidence, difficulty="medium", p_local=None,
           c_bad=C_BAD, c_claude=C_CLAUDE, p_claude=P_CLAUDE):
    p_local = calibrate(confidence, difficulty) if p_local is None else p_local
    e_local = (1.0 - p_local) * c_bad
    e_escalate = c_claude + (1.0 - p_claude) * c_bad
    escalate = e_escalate < e_local
    be = breakeven_p(c_bad, c_claude, p_claude)
    return {
        "escalate": escalate,
        "p_local": round(p_local, 3),
        "breakeven_p": round(be, 3),
        "E_cost_local": round(e_local, 3),
        "E_cost_escalate": round(e_escalate, 3),
        "reason": (f"local success {p_local:.2f} < breakeven {be:.2f}" if escalate
                   else f"local success {p_local:.2f} >= breakeven {be:.2f}"),
    }


def free_energy_decide(confidence, difficulty="medium", entropy=None, lam=1.0, p_local=None,
                       c_bad=C_BAD, c_claude=C_CLAUDE, p_claude=P_CLAUDE):
    """Free-Energy gate: expected cost (pragmatic) + epistemic penalty lam*H on the LOCAL arm only
    (escalation resolves uncertainty). entropy in nats (0=certain); None falls back to decide()."""
    if entropy is None:
        return decide(confidence, difficulty, p_local, c_bad, c_claude, p_claude)
    p_local = calibrate(confidence, difficulty) if p_local is None else p_local
    f_local = (1.0 - p_local) * c_bad + lam * float(entropy)
    f_escalate = c_claude + (1.0 - p_claude) * c_bad
    return {
        "escalate": f_escalate < f_local,
        "p_local": round(p_local, 3), "entropy": round(float(entropy), 3), "lambda": lam,
        "F_local": round(f_local, 3), "F_escalate": round(f_escalate, 3),
        "reason": f"F_local {f_local:.2f} (cost+{lam}*H) {'>' if f_escalate < f_local else '<='} F_escalate {f_escalate:.2f}",
    }


def fit_calibration(pairs):
    """pairs: [(confidence, was_correct_bool)] -> binned reliability table (confidence -> empirical p)."""
    bins: dict[float, list[int]] = {}
    for conf, ok in pairs:
        b = round(float(conf) * 5) / 5.0
        bins.setdefault(b, [0, 0])
        bins[b][0] += 1 if ok else 0
        bins[b][1] += 1
    return {b: round(c / n, 3) for b, (c, n) in sorted(bins.items())}


@dataclass(frozen=True)
class CostPolicy:
    """Overridable wrapper around the cost constants. Defaults are the engine's verbatim values."""

    c_bad: float = C_BAD
    c_claude: float = C_CLAUDE
    p_claude: float = P_CLAUDE

    def breakeven_p(self) -> float:
        return breakeven_p(self.c_bad, self.c_claude, self.p_claude)

    def decide(self, confidence, difficulty="medium", p_local=None) -> dict:
        return decide(confidence, difficulty, p_local, self.c_bad, self.c_claude, self.p_claude)

    def free_energy_decide(self, confidence, difficulty="medium", entropy=None, lam=1.0, p_local=None) -> dict:
        return free_energy_decide(confidence, difficulty, entropy, lam, p_local,
                                  self.c_bad, self.c_claude, self.p_claude)
