# Provenance: shared scaffold generalized from wave-av/wave-dispatch proxy.py. See CHASSIS.md.
"""Shared HTTP scaffold for the drop-in frontends.

Provides the common, frontend-agnostic machinery the three frontends (F4) reuse:
a `/health` route, transparent `_passthrough` to the real upstream, BrokenPipe-safe writes,
a JSONL decision logger, and a ThreadingHTTPServer runner.

The load-bearing invariant (preserved from the engine): the base `handle_post` DEFAULTS to
passthrough. A frontend offloads only by overriding `handle_post`, and must fall through to
`_passthrough` on ANY local error — offload can only save money, never break the agent loop.
"""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable


def make_logger(path: str) -> Callable[[dict], None]:
    """A best-effort JSONL decision logger; never raises into the request path."""
    def _log(rec: dict) -> None:
        try:
            with open(path, "a") as f:
                f.write(json.dumps({"ts": round(time.time(), 1), **rec}) + "\n")
        except Exception:
            pass
    return _log


class BaseProxyHandler(BaseHTTPRequestHandler):
    """Base handler. Frontends subclass and override `handle_post`; class attrs configure transport."""

    upstream: str = "https://api.anthropic.com"
    forward_headers: tuple[str, ...] = (
        "authorization", "x-api-key", "anthropic-version", "anthropic-beta", "content-type",
    )
    log: Callable[[dict], None] = staticmethod(lambda rec: None)

    def log_message(self, *a) -> None:  # silence stdlib access logs
        pass

    # --- request helpers ---
    def _read_body(self) -> tuple[bytes, dict]:
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n)
        try:
            body = json.loads(raw) if raw else {}
        except Exception:
            body = {}
        return raw, body

    def do_GET(self) -> None:
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self._write(b"ok")
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self) -> None:
        raw, body = self._read_body()
        self.handle_post(raw, body)

    def handle_post(self, raw: bytes, body: dict) -> None:
        """Default behavior: transparent passthrough. Frontends override to add offload."""
        self._passthrough(raw)

    # --- transport ---
    def _passthrough(self, raw: bytes) -> None:
        """Transparent forward to the configured upstream (streaming or not) — the safe default."""
        req = urllib.request.Request(self.upstream + self.path, data=raw, method="POST")
        for h in self.forward_headers:
            v = self.headers.get(h)
            if v:
                req.add_header(h, v)
        try:
            up = urllib.request.urlopen(req, timeout=600)
            self.send_response(up.status)
            for k, v in up.headers.items():
                if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                    self.send_header(k, v)
            self.end_headers()
            while True:
                chunk = up.read(8192)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except urllib.error.HTTPError as e:
            self._safe_error(e.code, e.read())
        except BrokenPipeError:
            pass  # client disconnected mid-response — not our error
        except Exception as e:
            self._safe_error(502, json.dumps({"error": str(e)[:80]}).encode())

    def _safe_error(self, code: int, payload: bytes) -> None:
        try:
            self.send_response(code)
            self.end_headers()
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def _write(self, payload: bytes) -> None:
        try:
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def send_json(self, obj: Any, code: int = 200) -> None:
        resp = json.dumps(obj).encode()
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(resp)))
            self.end_headers()
            self.wfile.write(resp)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def send_stream(self, payload: bytes, content_type: str = "text/event-stream") -> None:
        try:
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass


def run_server(handler_cls, host: str = "127.0.0.1", port: int = 8088) -> None:
    ThreadingHTTPServer((host, port), handler_cls).serve_forever()
