# Provenance: net-new; models the public API of spoonnotfound/fake-ollama (MIT). See CHASSIS.md.
"""Ollama frontend (:11434) — the NET-NEW surface that lets Ollama-speaking clients connect.

Cline / Kilo / Droid and other tools probe `/api/tags` for model discovery then call `/api/chat`
or `/api/generate`. This frontend answers those from the injected Engine (NDJSON streaming),
defaulting to passthrough to a real Ollama upstream when offload is off or a request isn't trivial.
Credit: endpoint shapes follow spoonnotfound/fake-ollama (MIT) — modeled, not vendored.
"""
from __future__ import annotations

import json
import time

from .engine import Engine
from .server import BaseProxyHandler

_MAX = 2000
_NDJSON = "application/x-ndjson"


def _chat_user_text(messages: list) -> str:
    out = []
    for m in messages:
        if m.get("role") == "system":
            continue
        c = m.get("content")
        out.append(c if isinstance(c, str) else " ".join(p.get("text", "") for p in c if isinstance(p, dict)))
    return "\n".join(out)


def _chat_local_able(body: dict) -> bool:
    if body.get("tools"):
        return False
    users = [m for m in body.get("messages", []) if m.get("role") == "user"]
    return len(users) == 1 and len(json.dumps(body.get("messages", []))) < _MAX


def _chat_done(text: str, model: str | None) -> dict:
    return {"model": model or "local", "created_at": _now(), "message": {"role": "assistant", "content": text},
            "done": True, "done_reason": "stop", "_served_by": "local-offload"}


def _gen_done(text: str, model: str | None) -> dict:
    return {"model": model or "local", "created_at": _now(), "response": text,
            "done": True, "done_reason": "stop", "_served_by": "local-offload"}


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _ndjson_stream(text: str, model: str | None, key: str) -> bytes:
    """NDJSON: one object per chunk under `key` ('message' obj for chat, 'response' str for generate)."""
    lines = []
    for i in range(0, len(text), 24):
        piece = text[i:i + 24]
        if key == "message":
            lines.append(json.dumps({"model": model or "local", "created_at": _now(),
                                     "message": {"role": "assistant", "content": piece}, "done": False}))
        else:
            lines.append(json.dumps({"model": model or "local", "created_at": _now(),
                                     "response": piece, "done": False}))
    final = _chat_done("", model) if key == "message" else _gen_done("", model)
    lines.append(json.dumps(final))
    return ("\n".join(lines) + "\n").encode()


def make_ollama_frontend(engine: Engine, *, offload: bool = True,
                         upstream: str = "http://127.0.0.1:11434", models: list | None = None,
                         version: str = "0.18.3", log=lambda r: None):
    """Build a configured Ollama-API handler class bound to `engine`."""
    models = models or ["local"]

    class OllamaFrontend(BaseProxyHandler):
        pass

    OllamaFrontend.upstream = upstream
    OllamaFrontend.forward_headers = ("authorization", "content-type")
    OllamaFrontend.log = staticmethod(log)

    def do_GET(self) -> None:
        if self.path == "/api/tags":
            return self.send_json({"models": [
                {"name": m, "model": m, "modified_at": _now(), "size": 0, "details": {"family": "local"}}
                for m in models]})
        if self.path == "/api/version":
            # Ollama clients (Cline/Kilo/Droid + the `ollama` CLI) run a version-compat check on
            # connect and bail on an unparseable/too-old string — must be a clean semver.
            return self.send_json({"version": version})
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self._write(b"ok")
            return
        self.send_response(404)
        self.end_headers()

    def do_HEAD(self) -> None:
        # `HEAD /` is the first thing the `ollama` CLI sends (health probe). The default handler
        # answers 501, which the client reads as "server broken" and aborts before /api/chat.
        self.send_response(200)
        self.end_headers()

    def handle_post(self, raw: bytes, body: dict) -> None:
        if self.path.endswith("/api/show"):
            # Capability probe — clients reject a model that doesn't advertise chat/completion.
            name = (body.get("name") or body.get("model") or (models[0] if models else "local"))
            return self.send_json({"license": "", "modelfile": "", "parameters": "",
                                   "template": "{{ .Prompt }}", "capabilities": ["completion"],
                                   "details": {"family": "local", "families": ["local"], "format": "gguf",
                                               "parameter_size": "local", "quantization_level": "mixed"},
                                   "model_info": {"general.architecture": "local", "name": name}})
        is_chat = self.path.endswith("/api/chat")
        is_gen = self.path.endswith("/api/generate")
        if is_gen:
            eligible = isinstance(body.get("prompt"), str) and len(body["prompt"]) < _MAX
        else:
            eligible = is_chat and _chat_local_able(body)
        decision = "local" if (eligible and offload) else "upstream"
        log({"api": "ollama", "path": self.path, "model": body.get("model"),
             "offload_eligible": eligible, "decision": decision, "stream": body.get("stream", True)})
        if decision == "local":
            text_in = body["prompt"] if is_gen else _chat_user_text(body.get("messages", []))
            neutral = {"messages": [{"role": "user", "content": text_in}], "model": body.get("model")}
            try:
                text = (engine.complete(neutral) or {}).get("text", "")
            except Exception as e:
                log({"api": "ollama", "path": self.path, "local_error": str(e)[:120], "decision": "fell_through"})
                return self._passthrough(raw)
            stream = body.get("stream", True)  # Ollama defaults stream=true
            key = "response" if is_gen else "message"
            if stream:
                return self.send_stream(_ndjson_stream(text, body.get("model"), key), content_type=_NDJSON)
            return self.send_json(_gen_done(text, body.get("model")) if is_gen else _chat_done(text, body.get("model")))
        self._passthrough(raw)

    OllamaFrontend.do_GET = do_GET
    OllamaFrontend.do_HEAD = do_HEAD
    OllamaFrontend.handle_post = handle_post
    return OllamaFrontend
