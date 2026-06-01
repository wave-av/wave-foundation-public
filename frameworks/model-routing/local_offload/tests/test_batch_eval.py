# Provenance: tests for the 0-cost local batch-eval loop (task #21). See CHASSIS.md.
"""Unit tests for batch_eval — fake engine, no network, deterministic clock."""
from local_offload.batch_eval import run_batch, run_models, score


def test_score_check_shapes():
    assert score("The answer is 42.", {"contains": "answer"})
    assert score("The answer is 42.", {"contains": "ANSWER"})  # case-insensitive
    assert score("  42 ", {"equals": "42"})  # trimmed
    assert score("result=42", {"regex": r"\d+"})
    assert score("yes", {"any": [{"equals": "no"}, {"contains": "ye"}]})
    assert not score("nope", {"contains": "answer"})
    assert not score("x", {"unknown_shape": 1})  # fails closed


class FakeEngine:
    """Returns a canned text per prompt substring; raises for a sentinel to exercise error handling."""

    def __init__(self, replies: dict, boom: str | None = None):
        self.replies = replies
        self.boom = boom
        self.calls = 0

    def complete(self, req: dict) -> dict:
        self.calls += 1
        prompt = req["messages"][0]["content"]
        if self.boom and self.boom in prompt:
            raise RuntimeError("backend down")
        for needle, text in self.replies.items():
            if needle in prompt:
                return {"text": text, "model": req["model"], "raw": {}}
        return {"text": "", "model": req["model"], "raw": {}}


def _clock():
    """Deterministic monotonic clock: 0,1,2,... seconds per call."""
    t = {"n": -1}

    def tick() -> float:
        t["n"] += 1
        return float(t["n"])

    return tick


def test_run_batch_scores_and_reports():
    cases = [
        {"id": "a", "prompt": "2+2?", "check": {"contains": "4"}},
        {"id": "b", "prompt": "capital of France?", "check": {"equals": "Paris"}},
    ]
    eng = FakeEngine({"2+2": "4", "France": "Paris"})
    rep = run_batch(cases, eng, "wave-test-30b", clock=_clock())
    assert rep["model"] == "wave-test-30b"
    assert rep["n"] == 2 and rep["passed"] == 2 and rep["pass_rate"] == 1.0
    assert rep["cost_usd"] == 0.0  # local — never billed
    assert eng.calls == 2
    assert all("latency_s" in c for c in rep["cases"])


def test_run_batch_records_failures_and_errors_without_aborting():
    cases = [
        {"id": "good", "prompt": "say hi", "check": {"contains": "hi"}},
        {"id": "wrong", "prompt": "say hi", "check": {"contains": "bye"}},  # model says hi, check wants bye
        {"id": "boom", "prompt": "explode now", "check": {"contains": "x"}},
    ]
    eng = FakeEngine({"say hi": "hi there"}, boom="explode")
    rep = run_batch(cases, eng, "m", clock=_clock())
    assert rep["passed"] == 1 and rep["n"] == 3
    byid = {c["id"]: c for c in rep["cases"]}
    assert byid["good"]["ok"] is True
    assert byid["wrong"]["ok"] is False and "error" not in byid["wrong"]
    assert byid["boom"]["ok"] is False and byid["boom"]["error"] == "backend down"  # error captured, batch continued


def test_run_models_picks_best_and_sums_zero_cost():
    cases = [{"id": "a", "prompt": "2+2?", "check": {"contains": "4"}}]
    factories = {
        "good-model": FakeEngine({"2+2": "4"}),
        "bad-model": FakeEngine({"2+2": "five"}),
    }
    out = run_models(cases, ["good-model", "bad-model"], engine_factory=lambda m: factories[m], clock=_clock())
    assert out["summary"]["best"] == "good-model"
    assert out["summary"]["total_cost_usd"] == 0.0
    assert len(out["reports"]) == 2
