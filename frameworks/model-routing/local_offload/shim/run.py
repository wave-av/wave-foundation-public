# Provenance: boot CLI for the local-offload chassis shim (wave-av/wave-dispatch). See CHASSIS.md.
"""Boot one or more drop-in frontends from a single profiles config, all over one engine.

    python -m local_offload.shim.run --all --profiles profiles.default.json
    python -m local_offload.shim.run --anthropic            # just Claude Code

Each frontend runs in its own thread, sharing one ProfileRouterEngine (so all three honor the same
local->Heavy->frontier fallback). Offload is OFF by default (passthrough + measure) — set --offload
or WAVE_PROXY_OFFLOAD=1 before pointing a real client at it.
"""
from __future__ import annotations

import argparse
import os
import threading

from ..profiles.router import ProfileRouter
from .anthropic_frontend import make_anthropic_frontend
from .engine import ProfileRouterEngine
from .ollama_frontend import make_ollama_frontend
from .openai_frontend import make_openai_frontend
from .server import make_logger, run_server


def _default_profiles_path() -> str:
    return os.path.join(os.path.dirname(__file__), "..", "profiles", "profiles.default.json")


def main(argv: list | None = None) -> None:
    ap = argparse.ArgumentParser(prog="local_offload.shim.run", description="Boot the drop-in offload shim.")
    ap.add_argument("--anthropic", action="store_true", help="Anthropic Messages frontend (Claude Code)")
    ap.add_argument("--openai", action="store_true", help="OpenAI Chat Completions frontend (Codex/Cursor/aider)")
    ap.add_argument("--ollama", action="store_true", help="Ollama API frontend (Cline/Kilo/Droid)")
    ap.add_argument("--all", action="store_true", help="Boot all three frontends")
    ap.add_argument("--profiles", default=_default_profiles_path(), help="Path to a profiles.json")
    ap.add_argument("--profile", default=os.environ.get("WAVE_PROFILE", "Fast"), help="Default profile name")
    ap.add_argument("--offload", action="store_true", default=os.environ.get("WAVE_PROXY_OFFLOAD") == "1",
                    help="Enable offload (default OFF = passthrough + measure)")
    ap.add_argument("--log", default=os.environ.get("WAVE_PROXY_LOG", "proxy.jsonl"), help="JSONL decision log path")
    args = ap.parse_args(argv)

    want = {"anthropic": args.anthropic or args.all, "openai": args.openai or args.all, "ollama": args.ollama or args.all}
    if not any(want.values()):
        ap.error("choose at least one of --anthropic / --openai / --ollama / --all")

    router = ProfileRouter.from_file(args.profiles)
    log = make_logger(args.log)
    engine = ProfileRouterEngine(router, profile=args.profile, on_hop=log)

    threads = []
    if want["anthropic"]:
        port = int(os.environ.get("WAVE_PROXY_PORT", "8088"))
        h = make_anthropic_frontend(engine, offload=args.offload, log=log)
        threads.append(_spawn("anthropic", h, port))
    if want["openai"]:
        port = int(os.environ.get("WAVE_OAI_PORT", "8090"))
        h = make_openai_frontend(engine, offload=args.offload, log=log)
        threads.append(_spawn("openai", h, port))
    if want["ollama"]:
        port = int(os.environ.get("WAVE_OLLAMA_PORT", "11434"))
        models = [router._endpoints[e].model for e in router._endpoints if router._endpoints[e].model]  # noqa: SLF001
        h = make_ollama_frontend(engine, offload=args.offload, models=models or ["local"], log=log)
        threads.append(_spawn("ollama", h, port))

    print(f"offload={'ON (trivial only)' if args.offload else 'OFF (passthrough+measure)'} | profile={args.profile} | log={args.log}")
    for t in threads:
        t.join()


def _spawn(name: str, handler_cls, port: int) -> threading.Thread:
    print(f"  {name:>9} frontend -> http://127.0.0.1:{port}")
    t = threading.Thread(target=run_server, args=(handler_cls, "127.0.0.1", port), daemon=True)
    t.start()
    return t


if __name__ == "__main__":
    main()
