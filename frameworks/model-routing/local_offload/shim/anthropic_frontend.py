# Provenance: generalized from wave-av/wave-dispatch proxy.py. See CHASSIS.md.
"""Anthropic Messages frontend (:8088) — lets Claude Code offload via ANTHROPIC_BASE_URL.

Default passthrough; offloads only TRIVIAL turns (no tools, single short user message) when
enabled, serving them from the injected Engine and framing the reply as Anthropic Messages JSON
or SSE. Any engine error falls through to upstream BEFORE headers are sent (fail-safe).
"""
from __future__ import annotations

import json
import time

from .engine import Engine
from .server import BaseProxyHandler

_MAX = 2000


def _user_text(messages: list) -> str:
    out = []
    for m in messages:
        c = m.get("content")
        if isinstance(c, str):
            out.append(c)
        elif isinstance(c, list):
            out.append(" ".join(p.get("text", "") for p in c if isinstance(p, dict)))
    return "\n".join(out)


def local_able(body: dict) -> bool:
    """Only TRIVIAL requests: no tools, a single short user turn. Everything else -> upstream."""
    if body.get("tools"):
        return False
    msgs = body.get("messages", [])
    if len(msgs) > 1:
        return False
    users = [m for m in msgs if m.get("role") == "user"]
    return len(users) == 1 and len(json.dumps(msgs)) < _MAX


def _neutral(body: dict) -> dict:
    # frameworks/claude-api: thread `system` (stable cacheable prefix) + effort through to the engine so the
    # Anthropic frontier hop can set cache_control on the system block and output_config.effort. tools are
    # intentionally absent here — local_able() only offloads trivial, tool-free turns; tool requests go upstream.
    return {
        "messages": [{"role": "user", "content": _user_text(body.get("messages", []))}],
        "model": body.get("model"),
        "temperature": body.get("temperature"),
        "max_tokens": body.get("max_tokens"),
        "system": body.get("system"),
        "effort": (body.get("output_config") or {}).get("effort"),
    }


def _message(text: str, model: str | None) -> dict:
    return {
        "id": f"msg_local_{int(time.time())}", "type": "message", "role": "assistant",
        "model": model or "local", "content": [{"type": "text", "text": text}],
        "stop_reason": "end_turn", "stop_sequence": None,
        "usage": {"input_tokens": 0, "output_tokens": len(text) // 4, "_served_by": "local-offload"},
    }


def _sse(event: str, data: dict) -> bytes:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n".encode()


def _stream(text: str, model: str | None) -> bytes:
    """Anthropic SSE: message_start -> content_block_delta* -> message_stop (full answer chunked)."""
    mid = f"msg_local_{int(time.time())}"
    out = [
        _sse("message_start", {"type": "message_start", "message": {
            "id": mid, "type": "message", "role": "assistant", "model": model or "local",
            "content": [], "stop_reason": None, "stop_sequence": None,
            "usage": {"input_tokens": 0, "output_tokens": 0, "_served_by": "local-offload"}}}),
        _sse("content_block_start", {"type": "content_block_start", "index": 0,
             "content_block": {"type": "text", "text": ""}}),
    ]
    for i in range(0, len(text), 24):
        out.append(_sse("content_block_delta", {"type": "content_block_delta", "index": 0,
                   "delta": {"type": "text_delta", "text": text[i:i + 24]}}))
    out += [
        _sse("content_block_stop", {"type": "content_block_stop", "index": 0}),
        _sse("message_delta", {"type": "message_delta",
             "delta": {"stop_reason": "end_turn", "stop_sequence": None},
             "usage": {"output_tokens": len(text) // 4}}),
        _sse("message_stop", {"type": "message_stop"}),
    ]
    return b"".join(out)


def make_anthropic_frontend(engine: Engine, *, offload: bool = True,
                            upstream: str = "https://api.anthropic.com", log=lambda r: None):
    """Build a configured Anthropic-Messages handler class bound to `engine`."""

    class AnthropicFrontend(BaseProxyHandler):
        pass

    AnthropicFrontend.upstream = upstream
    AnthropicFrontend.forward_headers = (
        "authorization", "x-api-key", "anthropic-version", "anthropic-beta", "content-type")
    AnthropicFrontend.log = staticmethod(log)

    def handle_post(self, raw: bytes, body: dict) -> None:
        eligible = "/v1/messages" in self.path and local_able(body)
        decision = "local" if (eligible and offload) else "anthropic"
        log({"api": "anthropic", "path": self.path, "model": body.get("model"),
             "has_tools": bool(body.get("tools")), "msgs": len(body.get("messages", [])),
             "offload_eligible": eligible, "decision": decision, "stream": bool(body.get("stream"))})
        if decision == "local":
            try:
                text = (engine.complete(_neutral(body)) or {}).get("text", "")  # built BEFORE any send
            except Exception as e:
                log({"api": "anthropic", "path": self.path, "local_error": str(e)[:120],
                     "decision": "fell_through"})
                return self._passthrough(raw)
            if body.get("stream"):
                return self.send_stream(_stream(text, body.get("model")))
            return self.send_json(_message(text, body.get("model")))
        self._passthrough(raw)

    AnthropicFrontend.handle_post = handle_post
    return AnthropicFrontend
