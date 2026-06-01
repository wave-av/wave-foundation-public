# Provenance: tests for the profile router (F1). See CHASSIS.md.
import json
import os

import pytest

from local_offload.profiles import ProfileConfigError, ProfileRouter, load_profiles

DEFAULTS = os.path.join(os.path.dirname(__file__), "..", "profiles", "profiles.default.json")


def test_defaults_load_and_resolve():
    profiles, endpoints = load_profiles(DEFAULTS)
    r = ProfileRouter(profiles, endpoints)
    plan = r.resolve("Fast")
    assert plan.endpoint.name == "local"
    assert plan.temperature == 0.25
    assert plan.fallback_chain == ("Heavy", "Frontier")  # local -> Heavy -> frontier


def test_resolve_merges_endpoint():
    profiles, endpoints = load_profiles(DEFAULTS)
    plan = ProfileRouter(profiles, endpoints).resolve("Frontier")
    assert plan.endpoint.api_style == "anthropic"
    assert plan.endpoint.api_key_env == "ANTHROPIC_API_KEY"
    assert plan.fallback_chain == ()  # terminal


def _write(tmp_path, obj):
    p = tmp_path / "p.json"
    p.write_text(json.dumps(obj))
    return str(p)


def test_reject_bad_api_style(tmp_path):
    bad = {"endpoints": {"x": {"base_url": "http://h", "api_style": "nope"}},
           "profiles": {"A": {"endpoint": "x"}}}
    with pytest.raises(ProfileConfigError):
        load_profiles(_write(tmp_path, bad))


def test_reject_unknown_endpoint(tmp_path):
    bad = {"endpoints": {"x": {"base_url": "http://h", "api_style": "ollama"}},
           "profiles": {"A": {"endpoint": "ghost"}}}
    with pytest.raises(ProfileConfigError):
        load_profiles(_write(tmp_path, bad))


def test_reject_unknown_fallback(tmp_path):
    bad = {"endpoints": {"x": {"base_url": "http://h", "api_style": "ollama"}},
           "profiles": {"A": {"endpoint": "x", "fallback": ["ghost"]}}}
    with pytest.raises(ProfileConfigError):
        load_profiles(_write(tmp_path, bad))


def test_fallback_cycle_guarded(tmp_path):
    cyc = {"endpoints": {"x": {"base_url": "http://h", "api_style": "ollama"}},
           "profiles": {"A": {"endpoint": "x", "fallback": ["B", "A"]},
                        "B": {"endpoint": "x", "fallback": ["A"]}}}
    r = ProfileRouter(*load_profiles(_write(tmp_path, cyc)))
    # A's chain dedupes/cycle-guards to [A, B] (the trailing A is dropped)
    assert r.resolve("A").fallback_chain == ("B",)


def test_run_walks_fallback_to_success():
    profiles, endpoints = load_profiles(DEFAULTS)
    r = ProfileRouter(profiles, endpoints)
    hops = []

    def call(ep, plan, req):
        if ep.api_style == "ollama":
            raise TimeoutError("local down")
        return {"served_by": ep.name}

    res = r.run("Fast", {"q": 1}, call, on_hop=hops.append)
    assert res["served_by"] == "frontier"
    assert [h["profile"] for h in hops] == ["Fast", "Heavy", "Frontier"]
    assert [h["ok"] for h in hops] == [False, False, True]


def test_run_is_bad_escalates():
    profiles, endpoints = load_profiles(DEFAULTS)
    r = ProfileRouter(profiles, endpoints)

    def call(ep, plan, req):
        return {"served_by": ep.name, "text": "" if ep.api_style == "ollama" else "ok"}

    res = r.run("Code", {"q": 1}, call, is_bad=lambda x: x["text"] == "")
    assert res["served_by"] == "frontier"
