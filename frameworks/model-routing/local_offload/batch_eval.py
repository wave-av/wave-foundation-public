# Provenance: 0-cost local batch-eval loop for the local-offload chassis (task #21). See CHASSIS.md.
"""Run a batch of internal eval cases against LOCAL models — $0, no Claude.

The Token Leveragizer's whole premise is that most internal work never needs a frontier call. This is
the harness that keeps us honest about *which* local model can actually carry an axis: point it at the
Studio Ollama endpoint (or any OpenAI-compatible local backend), feed it a JSONL of eval cases, and it
reports pass-rate + latency per model at zero marginal cost. It backs the `champions.json` reseal loop
(the `bench_real.py` runs cited there) and can run unattended on Studio as a cron.

Design:
  - An eval case is `{"id", "prompt", "check"}`. `check` is one of:
        {"contains": "..."}   substring (case-insensitive) must appear
        {"equals": "..."}     trimmed exact match
        {"regex": "..."}      Python regex search
        {"any": [check, ...]} passes if ANY sub-check passes
  - The engine is INJECTED (anything with `.complete(req) -> {"text", ...}`), defaulting to the shim's
    OllamaEngine, so tests run with a fake transport and no network. Mirrors ProfileRouterEngine's
    engine_factory seam.
  - Cost is structurally $0 (local inference); the report records `cost_usd: 0.0` so downstream
    accounting can prove the loop never billed.

Pure stdlib. CLI: `python -m local_offload.batch_eval cases.jsonl --models wave-qwen3-coder-30b,...`
"""
from __future__ import annotations

import json
import re
import time
from typing import Any, Callable, Iterable

from .shim.engine import OllamaEngine

# Default local backend: the Studio Ollama endpoint (Tailscale IP). Override with --base / OLLAMA_HOST.
DEFAULT_BASE_URL = "http://100.92.89.55:11434"


def score(text: str, check: dict) -> bool:
    """True iff `text` satisfies `check`. Unknown check shapes fail closed (never silently pass)."""
    if "contains" in check:
        return str(check["contains"]).lower() in (text or "").lower()
    if "equals" in check:
        return (text or "").strip() == str(check["equals"]).strip()
    if "regex" in check:
        return re.search(str(check["regex"]), text or "") is not None
    if "any" in check and isinstance(check["any"], list):
        return any(score(text, sub) for sub in check["any"])
    return False


def run_batch(
    cases: Iterable[dict],
    engine: Any,
    model: str,
    max_tokens: int = 512,
    timeout: float = 120,
    clock: Callable[[], float] = time.monotonic,
) -> dict:
    """Run every case through `engine` for one `model`; return a per-model report.

    Each case is scored independently; a transport error on a case is recorded as a failure with the
    error text (the loop never aborts the batch on one bad case). Latency is wall-clock per case.
    """
    results = []
    passed = 0
    t_total0 = clock()
    for case in cases:
        cid = case.get("id", "?")
        prompt = case.get("prompt", "")
        check = case.get("check", {})
        t0 = clock()
        try:
            out = engine.complete({
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": max_tokens,
                "timeout": timeout,
            })
            text = out.get("text", "")
            ok = score(text, check)
            err = None
        except Exception as e:  # noqa: BLE001 — one bad case must not abort the batch
            text, ok, err = "", False, str(e)
        dt = clock() - t0
        passed += 1 if ok else 0
        results.append({"id": cid, "ok": ok, "latency_s": round(dt, 3), **({"error": err} if err else {})})

    n = len(results)
    return {
        "model": model,
        "n": n,
        "passed": passed,
        "pass_rate": round(passed / n, 4) if n else 0.0,
        "wall_s": round(clock() - t_total0, 3),
        "cost_usd": 0.0,  # local inference — structurally zero marginal cost
        "cases": results,
    }


def run_models(
    cases: list[dict],
    models: list[str],
    engine_factory: Callable[[str], Any] | None = None,
    **batch_kwargs: Any,
) -> dict:
    """Run the same case set across several LOCAL models; return `{summary, reports}`.

    `engine_factory(model) -> engine` lets tests inject a fake; default builds an OllamaEngine against
    DEFAULT_BASE_URL (read from batch_kwargs['base_url'] if provided).
    """
    base_url = batch_kwargs.pop("base_url", DEFAULT_BASE_URL)
    if engine_factory is None:
        def engine_factory(_model: str) -> Any:  # noqa: ANN001
            return OllamaEngine(base_url)
    reports = [run_batch(cases, engine_factory(m), m, **batch_kwargs) for m in models]
    return {
        "summary": {
            "models": len(models),
            "cases": len(cases),
            "total_cost_usd": 0.0,
            "best": max(reports, key=lambda r: r["pass_rate"])["model"] if reports else None,
        },
        "reports": reports,
    }


def load_cases(path: str) -> list[dict]:
    """Load eval cases from a JSONL file (one `{id,prompt,check}` per line; blank lines skipped)."""
    cases = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                cases.append(json.loads(line))
    return cases


def main(argv: list[str] | None = None) -> int:
    import argparse
    import os

    ap = argparse.ArgumentParser(description="0-cost local batch-eval loop (task #21).")
    ap.add_argument("cases", help="JSONL file of {id,prompt,check} eval cases")
    ap.add_argument("--models", required=True, help="comma-separated local model names")
    ap.add_argument("--base", default=os.environ.get("OLLAMA_HOST", DEFAULT_BASE_URL),
                    help="OpenAI-compatible local backend base URL (default: $OLLAMA_HOST or Studio)")
    ap.add_argument("--max-tokens", type=int, default=512)
    args = ap.parse_args(argv)

    cases = load_cases(args.cases)
    models = [m.strip() for m in args.models.split(",") if m.strip()]
    report = run_models(cases, models, base_url=args.base, max_tokens=args.max_tokens)
    print(json.dumps(report, indent=2))
    # Non-zero exit if any model scored 0 on a non-empty batch — a signal for the cron wrapper.
    worst = min((r["pass_rate"] for r in report["reports"]), default=1.0)
    return 0 if (not cases or worst > 0.0) else 1


if __name__ == "__main__":
    raise SystemExit(main())
