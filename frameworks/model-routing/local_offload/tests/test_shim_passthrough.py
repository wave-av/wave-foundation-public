# Provenance: THE load-bearing invariant test for the shim (F6). See CHASSIS.md.
"""Passthrough-by-default + fail-safe fall-through. Offload can only save money, never break the loop:
  - offload OFF              -> request is forwarded to the real upstream
  - offload ON, engine OK    -> request is served locally (upstream NOT hit)
  - offload ON, engine RAISES-> request still reaches the upstream (fail-safe), never a 5xx to client
This test is non-skippable; it gates merge.
"""
import json
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from local_offload.shim import (
    make_anthropic_frontend,
    make_ollama_frontend,
    make_openai_frontend,
)

FRONTENDS = [
    ("anthropic", make_anthropic_frontend, "/v1/messages"),
    ("openai", make_openai_frontend, "/v1/chat/completions"),
    ("ollama", make_ollama_frontend, "/api/chat"),
]


class _Upstream(BaseHTTPRequestHandler):
    hits: list = []

    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        self.rfile.read(n)
        type(self).hits.append(self.path)
        body = json.dumps({"upstream": True}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class _Good:
    def complete(self, req):
        return {"text": "LOCAL", "model": "m"}


class _Bad:
    def complete(self, req):
        raise RuntimeError("local backend down")


def _boot(handler_cls):
    s = ThreadingHTTPServer(("127.0.0.1", 0), handler_cls)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s, s.server_address[1]


def _post(port, path, body):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    return json.loads(urllib.request.urlopen(req, timeout=10).read())


REQ = {"model": "x", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 8}


@pytest.fixture()
def upstream():
    _Upstream.hits = []
    s, port = _boot(_Upstream)
    yield port
    s.shutdown()


@pytest.mark.parametrize("name,factory,path", FRONTENDS)
def test_offload_off_passes_through(upstream, name, factory, path):
    handler = factory(_Good(), offload=False, upstream=f"http://127.0.0.1:{upstream}")
    s, port = _boot(handler)
    try:
        resp = _post(port, path, REQ)
        assert resp == {"upstream": True}, name
        assert _Upstream.hits, f"{name}: upstream not hit"
    finally:
        s.shutdown()


@pytest.mark.parametrize("name,factory,path", FRONTENDS)
def test_engine_error_falls_through(upstream, name, factory, path):
    handler = factory(_Bad(), offload=True, upstream=f"http://127.0.0.1:{upstream}")
    s, port = _boot(handler)
    try:
        resp = _post(port, path, REQ)
        assert resp == {"upstream": True}, f"{name}: engine error did not fall through"
        assert _Upstream.hits, f"{name}: upstream not hit on fail-safe"
    finally:
        s.shutdown()


@pytest.mark.parametrize("name,factory,path", FRONTENDS)
def test_offload_on_serves_local(upstream, name, factory, path):
    handler = factory(_Good(), offload=True, upstream=f"http://127.0.0.1:{upstream}")
    s, port = _boot(handler)
    try:
        # read raw: the Ollama frontend defaults to NDJSON streaming, so don't assume single JSON
        req = urllib.request.Request(f"http://127.0.0.1:{port}{path}",
                                     data=json.dumps(REQ).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
        raw = urllib.request.urlopen(req, timeout=10).read().decode()
        assert _Upstream.hits == [], f"{name}: upstream hit despite local serve"
        assert "LOCAL" in raw, f"{name}: local text missing"
    finally:
        s.shutdown()
