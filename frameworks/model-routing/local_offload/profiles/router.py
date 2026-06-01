# Provenance: extracted from wave-av/wave-dispatch (local-offload chassis). See CHASSIS.md.
"""Declarative named-profile router (HARVEST delta #1).

A profiles file maps named profiles (Fast/Expert/Heavy/Code + custom) to named endpoints
(local or hosted) with an ordered fallback chain. The router resolves a profile name to a
concrete Plan and executes the chain `profile -> fallback[0] -> ... -> frontier backstop`,
walking to the next candidate only on STRUCTURED failure (timeout / connection / 5xx / is_bad).

Pure Python stdlib. Transport is injected via a `call` callable so the router is testable
without a live model and agnostic to the wire format.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

_API_STYLES = ("anthropic", "openai", "ollama")


class ProfileConfigError(ValueError):
    """Raised when a profiles file is structurally invalid or referentially broken."""


@dataclass(frozen=True)
class Endpoint:
    name: str
    base_url: str
    api_style: str
    model: str | None = None
    api_key_env: str | None = None


@dataclass(frozen=True)
class Plan:
    """A resolved, executable view of a profile at one hop in the chain."""

    profile: str
    endpoint: Endpoint
    temperature: float | None
    max_tokens: int | None
    timeout_s: float | None
    # frameworks/claude-api: Opus 4.8/4.7 steer reasoning via output_config.effort (low|medium|high|max|xhigh), NOT temperature.
    effort: str | None = None
    fallback_chain: tuple[str, ...] = field(default=())  # remaining profiles to try after this one


def _require(cond: bool, msg: str) -> None:
    if not cond:
        raise ProfileConfigError(msg)


def _parse_endpoint(name: str, raw: dict[str, Any]) -> Endpoint:
    _require(isinstance(raw, dict), f"endpoint {name!r} must be an object")
    _require("base_url" in raw and isinstance(raw["base_url"], str), f"endpoint {name!r} needs string base_url")
    style = raw.get("api_style")
    _require(style in _API_STYLES, f"endpoint {name!r} api_style must be one of {_API_STYLES}")
    key_env = raw.get("api_key_env")
    _require(key_env is None or isinstance(key_env, str), f"endpoint {name!r} api_key_env must be string|null")
    return Endpoint(name, raw["base_url"], style, raw.get("model"), key_env)


def load_profiles(path: str | Path) -> tuple[dict[str, dict], dict[str, Endpoint]]:
    """Load + validate a profiles file. Returns (profiles, endpoints).

    Hand-rolled zero-dependency validation (engine is pure-stdlib; see decision D-F.Q2):
    structure, types, api_style enum, and referential integrity (every profile.endpoint and
    every fallback name resolves). Cycle detection happens lazily at run() time, not here, so a
    self-referential-but-unused chain still loads.
    """
    data = json.loads(Path(path).read_text())
    _require(isinstance(data, dict), "profiles file must be a JSON object")
    _require(isinstance(data.get("endpoints"), dict) and data["endpoints"], "missing/empty 'endpoints'")
    _require(isinstance(data.get("profiles"), dict) and data["profiles"], "missing/empty 'profiles'")

    endpoints = {name: _parse_endpoint(name, raw) for name, raw in data["endpoints"].items()}
    profiles: dict[str, dict] = {}
    for name, raw in data["profiles"].items():
        _require(isinstance(raw, dict), f"profile {name!r} must be an object")
        ep = raw.get("endpoint")
        _require(isinstance(ep, str) and ep in endpoints, f"profile {name!r} endpoint {ep!r} not in endpoints")
        fb = raw.get("fallback", [])
        _require(isinstance(fb, list) and all(isinstance(x, str) for x in fb), f"profile {name!r} fallback must be string[]")
        profiles[name] = raw

    # referential integrity for fallback names (deferred-resolvable forward refs are still names that must exist)
    for name, raw in profiles.items():
        for fb in raw.get("fallback", []):
            _require(fb in profiles, f"profile {name!r} fallback references unknown profile {fb!r}")
    return profiles, endpoints


class ProfileRouter:
    """Resolve profile names to Plans and execute the fallback chain."""

    def __init__(self, profiles: dict[str, dict], endpoints: dict[str, Endpoint]):
        self._profiles = profiles
        self._endpoints = endpoints

    @classmethod
    def from_file(cls, path: str | Path) -> "ProfileRouter":
        return cls(*load_profiles(path))

    def _ordered_candidates(self, name: str) -> list[str]:
        """The profile itself followed by its fallback list, deduped, cycle-guarded.

        Fallback is treated as a flat ordered list (not transitively expanded): a profile's
        chain is exactly `[name, *fallback]`. Duplicates and any re-reference of an
        already-seen profile are dropped so a misconfigured cycle can never loop.
        """
        _require(name in self._profiles, f"unknown profile {name!r}")
        seen: set[str] = set()
        chain: list[str] = []
        for cand in (name, *self._profiles[name].get("fallback", [])):
            if cand in seen:
                continue
            seen.add(cand)
            chain.append(cand)
        return chain

    def resolve(self, name: str) -> Plan:
        """Resolve one profile name to a Plan (endpoint + params + remaining fallback chain)."""
        chain = self._ordered_candidates(name)
        raw = self._profiles[name]
        return Plan(
            profile=name,
            endpoint=self._endpoints[raw["endpoint"]],
            temperature=raw.get("temperature"),
            max_tokens=raw.get("max_tokens"),
            timeout_s=raw.get("timeout_s"),
            effort=raw.get("effort"),  # frameworks/claude-api: maps to output_config.effort on Anthropic frontier hop
            fallback_chain=tuple(chain[1:]),
        )

    def run(
        self,
        name: str,
        request: Any,
        call: Callable[[Endpoint, Plan, Any], Any],
        is_bad: Callable[[Any], bool] | None = None,
        on_hop: Callable[[dict], None] | None = None,
    ) -> Any:
        """Execute the chain. Try each candidate's endpoint via `call`; advance to the next on
        STRUCTURED failure (call raises, or `is_bad(resp)` is true). Return the first good
        response. `on_hop` (optional, injected by the shim's jsonl logger) records every attempt.

        Raises the last exception (or RuntimeError on is_bad-only failure) if the whole chain fails.
        """
        candidates = self._ordered_candidates(name)
        last_exc: Exception | None = None
        for hop, cand in enumerate(candidates):
            plan = self.resolve(cand)
            rec = {"profile": cand, "endpoint": plan.endpoint.name, "hop": hop}
            try:
                resp = call(plan.endpoint, plan, request)
            except Exception as exc:  # structured failure: timeout / connection / 5xx surfaced by call
                last_exc = exc
                if on_hop:
                    on_hop({**rec, "ok": False, "error": type(exc).__name__})
                continue
            bad = bool(is_bad(resp)) if is_bad else False
            if on_hop:
                on_hop({**rec, "ok": not bad})
            if not bad:
                return resp
        if last_exc is not None:
            raise last_exc
        raise RuntimeError(f"all {len(candidates)} candidates failed is_bad for profile {name!r}")
