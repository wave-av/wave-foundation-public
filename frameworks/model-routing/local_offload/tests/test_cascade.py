# Provenance: tests for the cascade decision rule (F3). See CHASSIS.md.
import pytest

from local_offload.escalation import CascadePolicy


def test_confident_margin_takes_fast_path():
    calls = {"escalate": 0}

    def classify(_):
        return ("local", [0.8, 0.1, 0.1])  # margin 0.7 >= 0.30

    def escalate(_):
        calls["escalate"] += 1
        return "router"

    res = CascadePolicy(margin_thresh=0.30).route("x", classify, escalate)
    assert res["path"] == "fast" and res["route"] == "local"
    assert calls["escalate"] == 0  # escalate never called on the fast path


def test_uncertain_escalates():
    def classify(_):
        return ("local", [0.40, 0.38, 0.22])  # margin 0.02 < 0.30

    res = CascadePolicy(margin_thresh=0.30).route("x", classify, lambda _: "router")
    assert res["path"] == "escalate" and res["route"] == "router"


def test_bare_margin_float_supported():
    res = CascadePolicy(margin_thresh=0.30).route("x", lambda _: ("a", 0.5), lambda _: "b")
    assert res["path"] == "fast"


def test_conformal_requires_predicate():
    with pytest.raises(ValueError):
        CascadePolicy(use_conformal=True).route("x", lambda _: ("a", [0.9, 0.1]), lambda _: "b")


def test_conformal_predicate_used():
    res = CascadePolicy(use_conformal=True).route(
        "x", lambda _: ("a", [0.5, 0.5]), lambda _: "b", confident_fn=lambda p: True)
    assert res["path"] == "fast"
