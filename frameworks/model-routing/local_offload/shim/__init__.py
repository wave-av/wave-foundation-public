# Provenance: extracted from wave-av/wave-dispatch (local-offload chassis). See CHASSIS.md.
"""Multi-frontend drop-in shim (HARVEST delta #3). Frontends (F4) reuse the F2 scaffold + engine seam."""
from .anthropic_frontend import make_anthropic_frontend
from .engine import (
    AnthropicEngine,
    Engine,
    OllamaEngine,
    ProfileRouterEngine,
    engine_for,
)
from .ollama_frontend import make_ollama_frontend
from .openai_frontend import make_openai_frontend
from .server import BaseProxyHandler, make_logger, run_server

__all__ = [
    "AnthropicEngine",
    "Engine",
    "OllamaEngine",
    "ProfileRouterEngine",
    "engine_for",
    "BaseProxyHandler",
    "make_logger",
    "run_server",
    "make_anthropic_frontend",
    "make_openai_frontend",
    "make_ollama_frontend",
]
