#!/usr/bin/env python3
"""audit-discoverability.py — the WAVE discoverability gate (frameworks/discoverability).

Scores any WAVE spoke against the single standard in `surfaces.json`: are the required machine-readable
surfaces served, with the right content-type and the required JSON keys / substrings, and does the HTML
<head> carry og:image/og:title/canonical/json-ld? Required failures drop the score and (in CI) fail the
build; recommended failures are advisory.

IO is separated from logic: `audit(host, fetched, head, std)` is PURE (testable with crafted dicts);
`main()` does the network fetch + HTML head parse, then calls audit(). Reads surfaces.json — never
hardcodes the list — so it can't disagree with the standard it enforces.

Usage:  audit-discoverability.py <host>      # e.g. audit-discoverability.py moq.wave.online
Exit:   0 clean (no required violations), 1 required violations, 2 load/network error.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
STANDARD = os.path.join(HERE, "surfaces.json")


def load_standard(path: str = STANDARD) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _ct_matches(expected: str, actual: str) -> bool:
    # compare the media type only; ignore charset / params
    return actual.split(";")[0].strip().lower() == expected.split(";")[0].strip().lower()


def audit(host: str, fetched: dict, head: dict, std: dict) -> dict:
    """Pure scorer. `fetched`: path -> (status, content_type, body). `head`: head-check name -> bool."""
    violations: list[dict] = []

    for s in std["surfaces"]:
        path, tier = s["path"], s["tier"]
        got = fetched.get(path)
        if got is None:
            violations.append({"path": path, "tier": tier, "reason": "not served (no response)"})
            continue
        status, ct, body = got
        if status != 200:
            violations.append({"path": path, "tier": tier, "reason": f"status {status}"})
            continue
        if not _ct_matches(s["content_type"], ct):
            violations.append({"path": path, "tier": tier, "reason": f"content-type {ct!r} != {s['content_type']!r}"})
            continue
        for needle in s.get("must_contain", []):
            if needle not in body:
                violations.append({"path": path, "tier": tier, "reason": f"missing {needle!r}"})
        for key in s.get("json_keys", []):
            try:
                doc = json.loads(body)
            except (ValueError, TypeError):
                violations.append({"path": path, "tier": tier, "reason": "invalid JSON"})
                break
            if key not in doc:
                violations.append({"path": path, "tier": tier, "reason": f"missing JSON key {key!r}"})

    for h in std.get("html_head_checks", []):
        if not head.get(h["name"], False):
            violations.append({"head": h["name"], "tier": h["tier"], "reason": f"<head> missing {h['name']}"})

    required_total = sum(1 for s in std["surfaces"] if s["tier"] == "required") + \
        sum(1 for h in std.get("html_head_checks", []) if h["tier"] == "required")
    required_fail = sum(1 for v in violations if v["tier"] == "required")
    score = 100 if required_total == 0 else round(100 * (required_total - required_fail) / required_total)
    return {"host": host, "score": max(0, score), "violations": violations}


# ── network IO (impure; not unit-tested) ─────────────────────────────────────
def _fetch(url: str):
    try:
        req = urllib.request.Request(url, headers={"user-agent": "wave-discoverability-audit/1.0"})
        with urllib.request.urlopen(req, timeout=15) as r:  # noqa: S310 — https-only hosts in practice
            return (r.status, r.headers.get("content-type", ""), r.read().decode("utf-8", "replace"))
    except Exception as e:  # noqa: BLE001 — auditor must never crash on one bad surface
        return (0, "", f"<fetch-error: {e}>")


class _Head(HTMLParser):
    def __init__(self):
        super().__init__()
        self.found = {"og:image": False, "og:title": False, "canonical": False, "json-ld": False}

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "meta" and a.get("property") == "og:image":
            self.found["og:image"] = True
        if tag == "meta" and a.get("property") == "og:title":
            self.found["og:title"] = True
        if tag == "link" and a.get("rel") == "canonical":
            self.found["canonical"] = True
        if tag == "script" and a.get("type") == "application/ld+json":
            self.found["json-ld"] = True


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: audit-discoverability.py <host>", file=sys.stderr)
        return 2
    host = argv[1].replace("https://", "").replace("http://", "").strip("/")
    std = load_standard()
    base = f"https://{host}"
    fetched = {s["path"]: _fetch(base + s["path"]) for s in std["surfaces"]}
    parser = _Head()
    try:
        parser.feed(_fetch(base + "/")[2])
    except Exception:  # noqa: BLE001
        pass
    report = audit(host, fetched, parser.found, std)
    print(json.dumps(report, indent=2))
    return 1 if any(v["tier"] == "required" for v in report["violations"]) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
