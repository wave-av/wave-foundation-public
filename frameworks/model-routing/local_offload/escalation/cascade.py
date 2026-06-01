# Provenance: decision rule extracted from wave-av/wave-dispatch cascade_router.py. See CHASSIS.md.
"""Calibrated-margin cascade: classifier speed on the easy majority, escalation on the uncertain tail.

The engine's finding: a fast classifier's MARGIN is calibrated (high margin ⇒ usually right). So use
the classifier when margin ≥ threshold (fast, $0 decode), else fall back to a heavier/accurate path.

This is the *decision rule* only — sklearn / embeddings / training stay in the engine. The classifier
and the escalation target are INJECTED as callables, so the policy is testable with synthetic inputs
and carries zero ML dependencies.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Sequence


def _margin(proba_or_margin) -> float:
    """Top1-minus-top2 margin. Accepts a probability sequence (computes margin) or a bare float margin."""
    if isinstance(proba_or_margin, (int, float)):
        return float(proba_or_margin)
    order = sorted((float(x) for x in proba_or_margin), reverse=True)
    return order[0] - (order[1] if len(order) > 1 else 0.0)


@dataclass(frozen=True)
class CascadePolicy:
    """Route a request to the fast classifier path or escalate.

    margin_thresh: confident when the classifier margin ≥ this (default 0.30, the engine's proven
        0-dangerous setting). use_conformal: when True, confidence is decided by an injected
        `confident_fn(proba) -> bool` (the spoke supplies its precomputed conformal predicate;
        conformal.py is intentionally NOT vendored).
    """

    margin_thresh: float = 0.30
    use_conformal: bool = False

    def route(
        self,
        text: str,
        classify: Callable[[str], tuple[str, Sequence[float] | float]],
        escalate: Callable[[str], str],
        confident_fn: Callable[[Sequence[float] | float], bool] | None = None,
    ) -> dict:
        """classify(text) -> (label, proba_vector_or_margin). On confidence, return the classifier
        label (fast path). Otherwise call escalate(text) -> label (accurate path)."""
        label, proba = classify(text)
        if self.use_conformal:
            if confident_fn is None:
                raise ValueError("use_conformal=True requires a confident_fn(proba)->bool predicate")
            confident = bool(confident_fn(proba))
        else:
            confident = _margin(proba) >= self.margin_thresh
        if confident:
            return {"route": label, "path": "fast", "escalated": False, "margin": round(_margin(proba), 4)}
        return {"route": escalate(text), "path": "escalate", "escalated": True, "margin": round(_margin(proba), 4)}
