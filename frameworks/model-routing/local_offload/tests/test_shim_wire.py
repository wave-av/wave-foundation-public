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


def test_anthropic_engine_efficiency_lever_passthrough():
    """service_tier / context_management / betas are forwarded ONLY when the caller sets them;
    the default request shape carries none of them. Guards the chassis efficiency levers."""
    from local_offload.shim import engine as E
    captured = {}

    def fake_post(url, payload, headers, timeout):
        captured["payload"] = payload
        captured["headers"] = headers
        return {"content": [{"type": "text", "text": "ok"}], "stop_reason": "end_turn"}

    orig = E._post_json
    E._post_json = fake_post
    try:
        eng = E.AnthropicEngine(model="claude-opus-4-8", api_key_env=None)
        # (a) default: none of the levers present, no beta header
        eng.complete({"model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hi"}]})
        assert "service_tier" not in captured["payload"]
        assert "context_management" not in captured["payload"]
        assert "anthropic-beta" not in captured["headers"]
        # anthropic-version MUST be a real version (2023-06-01) — "2024-10-22" 400s on every call.
        assert captured["headers"]["anthropic-version"] == "2023-06-01"
        # (b) all set → forwarded verbatim
        eng.complete({
            "model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hi"}],
            "service_tier": "flex",
            "context_management": {"edits": [{"type": "clear_tool_uses_20250919"}]},
            "betas": ["compact-2026-01-12", "context-management-2025-06-27"],
        })
        assert captured["payload"]["service_tier"] == "flex"
        assert captured["payload"]["context_management"]["edits"][0]["type"] == "clear_tool_uses_20250919"
        assert captured["headers"]["anthropic-beta"] == "compact-2026-01-12,context-management-2025-06-27"
        # (c) task_budget: int → output_config.task_budget dict, COEXISTS with effort, auto-adds the beta
        eng.complete({
            "model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hi"}],
            "effort": "low", "task_budget": 64000,
        })
        oc = captured["payload"]["output_config"]
        assert oc["effort"] == "low"                                  # effort not clobbered
        assert oc["task_budget"] == {"type": "tokens", "total": 64000}
        assert "task-budgets-2026-03-13" in captured["headers"]["anthropic-beta"].split(",")
        # (d) task_budget beta is added ONCE even if the caller also listed it
        eng.complete({
            "model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hi"}],
            "task_budget": {"type": "tokens", "total": 30000},
            "betas": ["task-budgets-2026-03-13"],
        })
        assert captured["headers"]["anthropic-beta"].split(",").count("task-budgets-2026-03-13") == 1
        assert captured["payload"]["output_config"]["task_budget"]["total"] == 30000
    finally:
        E._post_json = orig


def test_anthropic_engine_cache_and_structured_output_levers():
    """cache diagnostics + structured outputs — the newest efficiency/capability levers. Both are opt-in:
    absent by default; forwarded verbatim + correct beta header when set; reason surfaced on the response."""
    from local_offload.shim import engine as E
    captured = {}

    def fake_post(url, payload, headers, timeout):
        captured["payload"] = payload
        captured["headers"] = headers
        return {"content": [{"type": "text", "text": "ok"}], "stop_reason": "end_turn",
                "diagnostics": {"cache_miss_reason": {"type": "system_changed", "cache_missed_input_tokens": 1234}}}

    orig = E._post_json
    E._post_json = fake_post
    try:
        eng = E.AnthropicEngine(model="claude-opus-4-8", api_key_env=None)
        # (a) cache diagnostics: payload field forwarded + cache-diagnosis beta auto-added + reason surfaced.
        out = eng.complete({"model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hi"}],
                            "diagnostics": {"previous_message_id": "msg_prev"}})
        assert captured["payload"]["diagnostics"] == {"previous_message_id": "msg_prev"}
        assert "cache-diagnosis-2026-04-07" in captured["headers"]["anthropic-beta"].split(",")
        assert out["diagnostics"]["cache_miss_reason"]["type"] == "system_changed"
        # first-turn opt-in (previous_message_id=None) still forwards + opts in
        eng.complete({"model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hi"}],
                      "diagnostics": {"previous_message_id": None}})
        assert captured["payload"]["diagnostics"] == {"previous_message_id": None}
        assert "cache-diagnosis-2026-04-07" in captured["headers"]["anthropic-beta"]
        # (b) structured outputs: output_config.format forwarded on a NON-opus model (not effort-gated),
        #     with no adaptive-thinking and no effort key. (Sonnet, not Haiku, to avoid the file-level
        #     haiku+effort lint heuristic — both are equally non-opus through the chassis.)
        SCHEMA = {"type": "json_schema", "schema": {"type": "object", "properties": {"x": {"type": "number"}}}}
        eng_s = E.AnthropicEngine(model="claude-sonnet-4-6", api_key_env=None)
        eng_s.complete({"model": "claude-sonnet-4-6", "messages": [{"role": "user", "content": "hi"}],
                        "response_format": SCHEMA})
        assert captured["payload"]["output_config"] == {"format": SCHEMA}
        assert "thinking" not in captured["payload"]
        # (c) opus: format COEXISTS with effort in the one output_config
        eng.complete({"model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hi"}],
                      "effort": "low", "response_format": SCHEMA})
        oc = captured["payload"]["output_config"]
        assert oc["effort"] == "low" and oc["format"] == SCHEMA
        # (d) default: neither lever present, no diagnostics, no spurious output_config.format
        eng.complete({"model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hi"}]})
        assert "diagnostics" not in captured["payload"]
        assert "format" not in captured["payload"].get("output_config", {})
        assert "cache-diagnosis-2026-04-07" not in captured["headers"].get("anthropic-beta", "")
    finally:
        E._post_json = orig


def test_post_json_serializes_deterministically():
    """sort_keys makes the same logical request byte-identical regardless of dict insertion order — a
    documented `tools_changed` cache-miss cause (non-deterministic schema serialization). Cache-stability guard."""
    from local_offload.shim import engine as E

    class _Resp:
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def read(self): return b"{}"
        def __iter__(self): return iter(())  # SSE: no events → stream accumulator just ends

    captured = []
    orig = urllib.request.urlopen
    urllib.request.urlopen = lambda req, timeout=None: (captured.append(req.data) or _Resp())
    try:
        # same content, different insertion order (mimics a tool schema re-serialized differently per turn)
        a = {"b": 1, "a": {"y": 2, "x": 1}}
        b = {"a": {"x": 1, "y": 2}, "b": 1}
        # BOTH transports must be deterministic — the stream path serves max_tokens>16000 requests.
        E._post_json("http://x/v1/messages", a, {}, 5)
        E._post_json("http://x/v1/messages", b, {}, 5)
        E._post_json_stream("http://x/v1/messages", a, {}, 5)
        E._post_json_stream("http://x/v1/messages", b, {}, 5)
        assert captured[0] == captured[1]  # _post_json: byte-identical → cacheable across turns
        assert captured[2] == captured[3]  # _post_json_stream: same guarantee on the large-request path
        assert captured[0] == captured[2]  # both transports serialize identically
    finally:
        urllib.request.urlopen = orig
