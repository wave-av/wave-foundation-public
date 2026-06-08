"""Teeth tests for audit-discoverability.py — prove the gate catches what it claims.

A spoke that serves every required surface with valid bodies must score clean; dropping a required
surface, returning the wrong content-type, or missing a required JSON key / head tag must each be a
violation. Pure stdlib + pytest; the auditor's network IO is never exercised here (we pass `fetched`).
"""
import importlib.util
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
_spec = importlib.util.spec_from_file_location(
    "audit_discoverability", os.path.join(ROOT, "audit-discoverability.py")
)
ad = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ad)

with open(os.path.join(ROOT, "surfaces.json"), encoding="utf-8") as fh:
    STD = json.load(fh)


def _ok_fetched():
    """A fully-compliant spoke response set keyed by path -> (status, content_type, body)."""
    return {
        "/robots.txt": (200, "text/plain; charset=utf-8", "User-agent: *\nAllow: /\nSitemap: https://x.wave.online/sitemap.xml\n"),
        "/sitemap.xml": (200, "application/xml; charset=utf-8", '<?xml version="1.0"?><urlset xmlns="x"></urlset>'),
        "/llms.txt": (200, "text/plain; charset=utf-8", "# wave X\nWAVE protocol plane spoke"),
        "/index.json": (200, "application/json; charset=utf-8", '{"name":"wave X","surfaces":[]}'),
        "/og.png": (200, "image/png", "\x89PNG\r\n"),
        "/manifest.webmanifest": (200, "application/manifest+json; charset=utf-8", '{"name":"wave X"}'),
        "/.well-known/did.json": (200, "application/json; charset=utf-8", '{"id":"did:web:x.wave.online","verificationMethod":[]}'),
    }


def _ok_head():
    return {"og:image": True, "og:title": True, "canonical": True, "json-ld": True}


def test_clean_spoke_has_no_required_violations():
    report = ad.audit("x.wave.online", _ok_fetched(), _ok_head(), STD)
    required_violations = [v for v in report["violations"] if v["tier"] == "required"]
    assert required_violations == [], required_violations
    assert report["score"] == 100


def test_missing_required_surface_is_a_violation():
    fetched = _ok_fetched()
    del fetched["/.well-known/did.json"]
    report = ad.audit("x.wave.online", fetched, _ok_head(), STD)
    assert any(v.get("path") == "/.well-known/did.json" and v["tier"] == "required" for v in report["violations"])
    assert report["score"] < 100


def test_wrong_content_type_is_a_violation():
    fetched = _ok_fetched()
    fetched["/og.png"] = (200, "image/svg+xml", "<svg/>")  # svg never unfurls — must be raster
    report = ad.audit("x.wave.online", fetched, _ok_head(), STD)
    assert any(v.get("path") == "/og.png" and "content-type" in v["reason"] for v in report["violations"])


def test_missing_required_json_key_is_a_violation():
    fetched = _ok_fetched()
    fetched["/.well-known/did.json"] = (200, "application/json", '{"id":"did:web:x"}')  # no verificationMethod
    report = ad.audit("x.wave.online", fetched, _ok_head(), STD)
    assert any(v.get("path") == "/.well-known/did.json" and "verificationMethod" in v["reason"] for v in report["violations"])


def test_missing_required_head_tag_is_a_violation():
    head = _ok_head()
    head["og:image"] = False
    report = ad.audit("x.wave.online", _ok_fetched(), head, STD)
    assert any(v.get("head") == "og:image" and v["tier"] == "required" for v in report["violations"])
