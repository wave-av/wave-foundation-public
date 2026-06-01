# Provenance: generalized from wave-av/wave-dispatch openai_proxy.py. See CHASSIS.md.
"""OpenAI Chat Completions frontend (:8090) — the agent-agnostic offload path.

Point Codex / Cursor / aider / Continue at it: OPENAI_BASE_URL=http://localhost:8090/v1
Default passthrough; offloads TRIVIAL turns from the injected Engine. A `tool_able` hook is left
as a documented seam (the engine decides) — this frontend ships text-only, fail-safe to upstream.
"""
from __future__ import annotations

import json
import time

from .engine import Engine
from .server import BaseProxyHandler

_MAX = 2000


def local_able(body: dict) -> bool:
    if body.get("tools") or body.get("functions"):
        return False
    msgs = body.get("messages", [])
    users = [m for m in msgs if m.get("role") == "user"]
    non_system = [m for m in msgs if m.get("role") != "system"]
    return len(users) == 1 and len(non_system) <= 1 and len(json.dumps(msgs)) < _MAX


def _user_text(messages: list) -> str:
    out = []
    for m in messages:
        if m.get("role") == "system":
            continue
        c = m.get("content")
        if isinstance(c, str):
            out.append(c)
        elif isinstance(c, list):
            out.append(" ".join(p.get("text", "") for p in c if isinstance(p, dict)))
    return "\n".join(out)


def _neutral(body: dict) -> dict:
    return {
        "messages": [{"role": "user", "content": _user_text(body.get("messages", []))}],
        "model": body.get("model"),
        "temperature": body.get("temperature"),
        "max_tokens": body.get("max_tokens"),
    }


def _completion(text: str, model: str | None) -> dict:
    return {
        "id": f"chatcmpl-local-{int(time.time())}", "object": "chat.completion",
        "created": int(time.time()), "model": model or "local",
        "choices": [{"index": 0, "message": {"role": "assistant", "content": text},
                     "finish_reason": "stop"}],
        "usage": {"prompt_tokens": 0, "completion_tokens": len(text) // 4, "total_tokens": len(text) // 4,
                  "_served_by": "local-offload"},
    }


def _stream(text: str, model: str | None) -> bytes:
    cid = f"chatcmpl-local-{int(time.time())}"
    base = {"id": cid, "object": "chat.completion.chunk", "created": int(time.time()), "model": model or "local"}
    out = [f"data: {json.dumps({**base, 'choices': [{'index': 0, 'delta': {'role': 'assistant'}, 'finish_reason': None}]})}\n\n".encode()]
    for i in range(0, len(text), 24):
        chunk = {**base, "choices": [{"index": 0, "delta": {"content": text[i:i + 24]}, "finish_reason": None}]}
        out.append(f"data: {json.dumps(chunk)}\n\n".encode())
    out.append(f"data: {json.dumps({**base, 'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}]})}\n\n".encode())
    out.append(b"data: [DONE]\n\n")
    return b"".join(out)


def make_openai_frontend(engine: Engine, *, offload: bool = True,
                         upstream: str = "https://api.openai.com", log=lambda r: None):
    """Build a configured OpenAI Chat-Completions handler class bound to `engine`."""

    class OpenAIFrontend(BaseProxyHandler):
        pass

    OpenAIFrontend.upstream = upstream
    OpenAIFrontend.forward_headers = ("authorization", "content-type", "openai-organization", "openai-beta")
    OpenAIFrontend.log = staticmethod(log)

    def handle_post(self, raw: bytes, body: dict) -> None:
        eligible = "/chat/completions" in self.path and local_able(body)
        decision = "local" if (eligible and offload) else "upstream"
        log({"api": "openai", "path": self.path, "model": body.get("model"),
             "has_tools": bool(body.get("tools") or body.get("functions")),
             "msgs": len(body.get("messages", [])), "offload_eligible": eligible,
             "decision": decision, "stream": bool(body.get("stream"))})
        if decision == "local":
            try:
                text = (engine.complete(_neutral(body)) or {}).get("text", "")
            except Exception as e:
                log({"api": "openai", "path": self.path, "local_error": str(e)[:120], "decision": "fell_through"})
                return self._passthrough(raw)
            if body.get("stream"):
                return self.send_stream(_stream(text, body.get("model")))
            return self.send_json(_completion(text, body.get("model")))
        self._passthrough(raw)

    OpenAIFrontend.handle_post = handle_post
    return OpenAIFrontend
