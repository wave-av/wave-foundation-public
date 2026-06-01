# Provenance: engine seam for the local-offload chassis (wave-av/wave-dispatch). See CHASSIS.md.
# claude-api-lint: skip — this is the reference shim that ENFORCES the request-shape rules (it names
# temperature/top_p/top_k precisely so it can strip them for Opus). It is the fix, not a violation.
"""The Engine seam — what makes the shim present ANY backend.

A frontend speaks a wire format (Anthropic/OpenAI/Ollama); an Engine speaks to a backend. They meet
on a NEUTRAL shape so a frontend never knows which backend served it:

    request  = {"messages": [{"role", "content"}], "model", "temperature", "max_tokens", "tools"?, "timeout"?}
    response = {"text": str, "model": str, "raw": dict}

Ships three reference engines (Ollama/OpenAI-compatible, Anthropic) + a `ProfileRouterEngine` that
routes a request through a named profile's fallback chain (this is the seam tying F1 to the shim).
Pure stdlib (urllib).
"""
from __future__ import annotations

import json
import os
import urllib.request
from typing import Any, Callable, Protocol, runtime_checkable

from ..profiles.router import Endpoint, Plan, ProfileRouter


@runtime_checkable
class Engine(Protocol):
    def complete(self, req: dict) -> dict: ...  # -> {"text", "model", "raw"}


def _post_json(url: str, payload: dict, headers: dict, timeout: float) -> dict:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=data, method="POST", headers={"Content-Type": "application/json", **headers}
    )
    with urllib.request.urlopen(req, timeout=timeout) as up:
        return json.loads(up.read())


def _post_json_stream(url: str, payload: dict, headers: dict, timeout: float) -> dict:
    # frameworks/claude-api: stream large generations and accumulate SSE into one Messages object
    # (stdlib equivalent of .get_final_message()), so callers see a single non-streamed response shape.
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=data, method="POST",
        headers={"Content-Type": "application/json", "Accept": "text/event-stream", **headers},
    )
    msg: dict[str, Any] = {"content": [], "stop_reason": None}
    blocks: dict[int, dict] = {}
    with urllib.request.urlopen(req, timeout=timeout) as up:
        for line in up:
            line = line.decode().strip()
            if not line.startswith("data:"):
                continue
            ev = json.loads(line[5:].strip())
            t = ev.get("type")
            if t == "message_start":
                m = ev.get("message", {})
                msg.update({k: v for k, v in m.items() if k != "content"})
                msg["content"] = []
            elif t == "content_block_start":
                blocks[ev["index"]] = dict(ev.get("content_block", {}))
            elif t == "content_block_delta":
                d = ev.get("delta", {})
                b = blocks.setdefault(ev["index"], {"type": "text", "text": ""})
                if d.get("type") == "text_delta":
                    b["text"] = b.get("text", "") + d.get("text", "")
            elif t == "message_delta":
                msg.update(ev.get("delta", {}))
                if "usage" in ev:
                    msg.setdefault("usage", {}).update(ev["usage"])
    msg["content"] = [blocks[i] for i in sorted(blocks)]
    return msg


def _key(api_key_env: str | None) -> str | None:
    return os.environ.get(api_key_env) if api_key_env else None


class OllamaEngine:
    """Wraps an OpenAI-compatible `/v1/chat/completions` endpoint (Ollama, vLLM, llama.cpp, …)."""

    def __init__(self, base_url: str, model: str | None = None, api_key_env: str | None = None, timeout: float = 120):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.api_key_env = api_key_env
        self.timeout = timeout

    def complete(self, req: dict) -> dict:
        model = req.get("model") or self.model
        payload = {
            "model": model,
            "messages": req.get("messages", []),
            "temperature": req.get("temperature"),
            "max_tokens": req.get("max_tokens"),
            "stream": False,
        }
        payload = {k: v for k, v in payload.items() if v is not None}
        headers = {}
        key = _key(self.api_key_env)
        if key:
            headers["Authorization"] = f"Bearer {key}"
        raw = _post_json(f"{self.base_url}/v1/chat/completions", payload, headers, req.get("timeout") or self.timeout)
        text = ((raw.get("choices") or [{}])[0].get("message") or {}).get("content", "")
        return {"text": text, "model": model, "raw": raw}


class AnthropicEngine:
    """Wraps the Anthropic Messages API — the hosted frontier backstop."""

    def __init__(self, base_url: str = "https://api.anthropic.com", model: str | None = None,
                 api_key_env: str | None = "ANTHROPIC_API_KEY", timeout: float = 120,
                 anthropic_version: str | None = None):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.api_key_env = api_key_env
        self.timeout = timeout
        # frameworks/claude-api: pin a current API version so Opus 4.8 features (adaptive thinking,
        # output_config.effort, 1h cache ttl) are exposed; the legacy 2023-06-01 may not surface them.
        self.anthropic_version = anthropic_version or os.environ.get("ANTHROPIC_VERSION", "2024-10-22")

    def complete(self, req: dict) -> dict:
        model = req.get("model") or self.model
        max_tokens = req.get("max_tokens", 1024)
        messages = req.get("messages", [])
        payload: dict[str, Any] = {
            "model": model,
            "max_tokens": max_tokens,
            "messages": messages,
        }

        # frameworks/claude-api: Opus 4.8/4.7 REMOVED temperature/top_p/top_k — sending ANY returns HTTP 400.
        # Steer via prompting + output_config.effort + adaptive thinking instead. Sonnet/Haiku still accept temperature.
        is_opus = bool(model) and str(model).startswith("claude-opus-4-")
        if not is_opus and req.get("temperature") is not None:
            payload["temperature"] = req["temperature"]

        # frameworks/claude-api: adaptive thinking is the ONLY supported form on Opus 4.8/4.7
        # (thinking={type:'enabled',budget_tokens:N} returns 400 — budget_tokens fully removed).
        # output_config.effort steers reasoning (low|medium|high|max|xhigh; default high; max/xhigh are Opus-tier).
        if is_opus:
            payload["thinking"] = {"type": "adaptive"}
            payload["output_config"] = {"effort": req.get("effort") or "high"}

        # frameworks/claude-api: prompt caching — put ONE cache_control breakpoint on the last stable prefix
        # block so a repeated prefix is cached (~0.1x reads vs full $5/MTok input). Render order is
        # tools -> system -> messages, and a breakpoint caches everything rendered before it: so a marker on
        # the last `system` block ALSO caches the tools that precede it (no separate tool breakpoint needed).
        # Only when there is NO system block do we mark the last tool, so a tools-only request still caches.
        # TTL: default 5-minute ephemeral; pass req["cache_ttl"]=="1h" for the 1-hour cache (2x write cost —
        # worth it only for bursty traffic with gaps > 5m). Min cacheable prefix: Opus 4.8 + Sonnet 4.6/4.5
        # = 1,024 tokens (Opus 4.8 LOWERED the min vs 4.7 — short prompts that missed on 4.7 now cache);
        # Opus 4.7/4.6/4.5 + Haiku 4.5 = 4,096; below the minimum it silently won't cache
        # (cache_creation_input_tokens stays 0). Verify with usage.cache_read_input_tokens.
        cc = {"type": "ephemeral", "ttl": "1h"} if req.get("cache_ttl") == "1h" else {"type": "ephemeral"}
        system = req.get("system")
        if system is not None:
            if isinstance(system, str):
                system = [{"type": "text", "text": system}]
            if isinstance(system, list) and system:
                system = [dict(b) for b in system]
                system[-1]["cache_control"] = cc
            payload["system"] = system
        if req.get("tools"):
            tools = [dict(t) for t in req["tools"]]
            if system is None and tools:
                # no system breakpoint to cache the (earlier-rendered) tools → cache the tool list itself
                tools[-1]["cache_control"] = cc
            payload["tools"] = tools

        headers = {"anthropic-version": self.anthropic_version}
        key = _key(self.api_key_env)
        if key:
            headers["x-api-key"] = key

        url = f"{self.base_url}/v1/messages"
        timeout = req.get("timeout") or self.timeout
        # frameworks/claude-api: stream when max_tokens > ~16000 — non-streaming risks SDK/HTTP timeout
        # (frontier supports 128K output). Accumulate SSE into one Messages object (.get_final_message equivalent).
        if isinstance(max_tokens, int) and max_tokens > 16000:
            payload["stream"] = True
            raw = _post_json_stream(url, payload, headers, max(timeout, max_tokens / 100))
        else:
            raw = _post_json(url, payload, headers, timeout)

        text = " ".join(b.get("text", "") for b in raw.get("content", []) if b.get("type") == "text")
        # frameworks/claude-api: surface non-end_turn stop reasons so the router can fall back / signal callers.
        out: dict[str, Any] = {"text": text, "model": model, "raw": raw}
        stop = raw.get("stop_reason")
        if stop and stop != "end_turn":
            out["stop_reason"] = stop
            if stop == "refusal":
                out["refusal_category"] = (raw.get("stop_details") or {}).get("category")
        return out


def engine_for(ep: Endpoint, timeout: float = 120) -> Engine:
    """Build the right Engine for an endpoint's api_style."""
    if ep.api_style in ("ollama", "openai"):
        return OllamaEngine(ep.base_url, ep.model, ep.api_key_env, timeout)
    if ep.api_style == "anthropic":
        # frameworks/claude-api: anthropic_version defaults to a current Opus-4.8-capable version (see AnthropicEngine).
        return AnthropicEngine(ep.base_url, ep.model, ep.api_key_env or "ANTHROPIC_API_KEY", timeout)
    raise ValueError(f"unknown api_style {ep.api_style!r}")


class ProfileRouterEngine:
    """An Engine backed by a ProfileRouter: routes a request through a profile's fallback chain.

    This is the F2.4 seam — a frontend can be handed this Engine and transparently get
    local→Heavy→frontier behavior. The per-endpoint transport is built by `engine_factory`
    (defaults to `engine_for`), so tests can inject a fake.
    """

    def __init__(self, router: ProfileRouter, profile: str = "Fast",
                 engine_factory: Callable[[Endpoint, float], Engine] = engine_for,
                 on_hop: Callable[[dict], None] | None = None):
        self.router = router
        self.profile = profile
        self.engine_factory = engine_factory
        self.on_hop = on_hop

    def complete(self, req: dict) -> dict:
        def call(ep: Endpoint, plan: Plan, request: dict) -> dict:
            eng = self.engine_factory(ep, plan.timeout_s or 120)
            r = dict(request)
            if ep.model:
                r["model"] = ep.model  # the endpoint's model is authoritative for this hop; the
                # client's requested model (e.g. a frontier name) is meaningless to a local backend
            if plan.temperature is not None:
                r.setdefault("temperature", plan.temperature)
            if plan.effort is not None:
                # frameworks/claude-api: carry profile effort to the Anthropic frontier hop (output_config.effort)
                r.setdefault("effort", plan.effort)
            if plan.max_tokens is not None:
                r.setdefault("max_tokens", plan.max_tokens)
            if plan.timeout_s is not None:
                r["timeout"] = plan.timeout_s
            return eng.complete(r)

        name = req.get("_profile") or self.profile
        return self.router.run(name, req, call, on_hop=self.on_hop)
