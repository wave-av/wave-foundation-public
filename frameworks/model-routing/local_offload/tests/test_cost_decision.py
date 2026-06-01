# Provenance: tests for the escalation policy (F3). See CHASSIS.md.
from local_offload.escalation import CostPolicy, breakeven_p, decide, free_energy_decide


def test_breakeven_default():
    assert abs(breakeven_p() - 0.37) < 1e-9


def test_escalate_monotonicity():
    assert decide(0.95, "low")["escalate"] is False
    assert decide(0.30, "high")["escalate"] is True


def test_free_energy_entropy_pushes_escalation():
    # same confidence; high uncertainty (entropy) should escalate where low does not
    assert free_energy_decide(0.8, "low", entropy=0.0)["escalate"] is False
    assert free_energy_decide(0.8, "low", entropy=2.0)["escalate"] is True


def test_free_energy_none_entropy_falls_back_to_decide():
    a = free_energy_decide(0.6, "medium", entropy=None)
    b = decide(0.6, "medium")
    assert a["escalate"] == b["escalate"]


def test_cost_policy_override():
    cp = CostPolicy(c_bad=10)
    assert abs(cp.breakeven_p() - 0.67) < 1e-9
    assert cp.decide(0.95, "low")["escalate"] is False
