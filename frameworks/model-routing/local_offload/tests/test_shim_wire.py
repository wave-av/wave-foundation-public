# Provenance: golden wire-format tests for the three frontends (F6). See CHASSIS.md.
"""Assert each frontend emits its native wire format correctly (the 'drop-in' promise),
served from a fake engine so it's deterministic + offline."""
import json
import os
import threading
import urllib.request
from http.server import ThreadingHTTPServer

from local_offload.shim import (
    make_anthropic_frontend,
    make_ollama_frontend,
    make_openai_frontend,
)

FIX = os.path.join(os.path.dirname(__file__), "fixtures")
TEXT = "PONG-" * 12  # long enough to span multiple 24-char delta chunks


def _fixture(name):
    with open(os.path.join(FIX, name)) as f:
        return json.load(f)


class _Engine:
    def complete(self, req):
        return {"text": TEXT, "model": "m"}


def _boot(handler_cls):
    s = ThreadingHTTPServer(("127.0.0.1", 0), handler_cls)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s, s.server_address[1]


def _raw(port, path, body):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    return urllib.request.urlopen(req, timeout=10).read().decode()


def test_anthropic_nonstream_shape():
    s, port = _boot(make_anthropic_frontend(_Engine(), offload=True))
    try:
        d = json.loads(_raw(port, "/v1/messages", _fixture("anthropic_trivial.json")))
        assert d["type"] == "message" and d["role"] == "assistant"
        assert d["content"][0]["text"] == TEXT
        assert d["usage"]["_served_by"] == "local-offload"
    finally:
        s.shutdown()


def test_anthropic_sse_event_order():
    body = {**_fixture("anthropic_trivial.json"), "stream": True}
    s, port = _boot(make_anthropic_frontend(_Engine(), offload=True))
    try:
        raw = _raw(port, "/v1/messages", body)
        events = [ln[7:] for ln in raw.splitlines() if ln.startswith("event: ")]
        assert events[0] == "message_start"
        assert "content_block_start" in events and "content_block_stop" in events
        assert events[-1] == "message_stop"
        deltas = "".join(json.loads(ln[6:])["delta"]["text"]
                         for ln in raw.splitlines() if ln.startswith("data: ") and "text_delta" in ln)
        assert deltas == TEXT  # chunks reconstruct exactly
    finally:
        s.shutdown()


def test_openai_stream_shape():
    body = {**_fixture("openai_trivial.json"), "stream": True}
    s, port = _boot(make_openai_frontend(_Engine(), offload=True))
    try:
        raw = _raw(port, "/v1/chat/completions", body)
        assert raw.rstrip().endswith("data: [DONE]")
        content = "".join(
            json.loads(ln[6:])["choices"][0]["delta"].get("content", "")
            for ln in raw.splitlines() if ln.startswith("data: ") and ln[6:].strip() != "[DONE]")
        assert content == TEXT
    finally:
        s.shutdown()


def test_ollama_chat_nonstream_and_tags():
    s, port = _boot(make_ollama_frontend(_Engine(), offload=True, models=["local"]))
    try:
        d = json.loads(_raw(port, "/api/chat", _fixture("ollama_chat.json")))
        assert d["message"]["content"] == TEXT and d["done"] is True
        tags = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/api/tags", timeout=5).read())
        assert [m["name"] for m in tags["models"]] == ["local"]
    finally:
        s.shutdown()


def test_ollama_client_handshake():
    # Real Ollama clients (Cline/Kilo/Droid + `ollama` CLI) run a preflight BEFORE /api/chat:
    # HEAD / (health) → 200, GET /api/version → clean semver, POST /api/show → advertises completion.
    # A missing endpoint here makes the client abort with a generic error. (Regression guard, 2026-05-30.)
    import re
    s, port = _boot(make_ollama_frontend(_Engine(), offload=True, models=["local"]))
    try:
        head = urllib.request.Request(f"http://127.0.0.1:{port}/", method="HEAD")
        assert urllib.request.urlopen(head, timeout=5).status == 200
        ver = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/api/version", timeout=5).read())
        assert re.match(r"^\d+\.\d+\.\d+$", ver["version"]), ver
        show = json.loads(_raw(port, "/api/show", {"name": "local"}))
        assert "completion" in show.get("capabilities", []), show
    finally:
        s.shutdown()


def test_ollama_chat_ndjson_stream():
    body = {"model": "local", "stream": True, "messages": [{"role": "user", "content": "hi"}]}
    s, port = _boot(make_ollama_frontend(_Engine(), offload=True))
    try:
        raw = _raw(port, "/api/chat", body)
        lines = [json.loads(ln) for ln in raw.splitlines() if ln.strip()]
        assert lines[-1]["done"] is True
        assert all(ln["done"] is False for ln in lines[:-1])
        content = "".join(ln["message"]["content"] for ln in lines[:-1])
        assert content == TEXT
    finally:
        s.shutdown()
