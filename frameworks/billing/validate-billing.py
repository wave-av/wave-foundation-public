#!/usr/bin/env python3
"""validate-billing.py — validate a product's billing.config.yaml against the WAVE Billing & Settlement
Contract (frameworks/billing/README.md + billing-config.schema.json).

This is the gate form of the contract: it runs at commit time (vendored via consume.sh) and in the
`billing-contract` CI job, so a settlement-topology mistake — above all the CENTS INVARIANT (the 100×
under-bill class) — is caught as code is written, not as a mis-billed invoice in production.

Schema-DRIVEN, no drift: the canonical meter set and the pinned invariants (`passthrough_unit_decimal`,
`idempotency`) are read FROM billing-config.schema.json, not hardcoded here — so the validator can never
disagree with the contract it enforces (the same principle as dispatch's reconcile importing its provisioners).

If a sibling pricing.yaml is present, every billed meter is cross-checked to be a meter that pricing.yaml
declares — catching a billing.config that bills something the product doesn't price.

Pure stdlib + pyyaml (already a foundation dep). No jsonschema/node/ajv toolchain required.

Usage:  validate-billing.py [billing.config.yaml ...]    # pre-commit passes changed files
        validate-billing.py                               # no args → all billing.config.yaml under cwd
Exit:   0 clean, 1 violations (printed to stderr with the fix), 2 schema/load error.
"""
from __future__ import annotations

import glob
import json
import os
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA = os.path.join(HERE, "billing-config.schema.json")


def load_schema() -> dict:
    with open(SCHEMA, encoding="utf-8") as fh:
        return json.load(fh)


def _const(schema: dict, prop: str) -> str:
    return schema["properties"][prop]["const"]


def _canonical_meters(schema: dict) -> set[str]:
    return set(schema["properties"]["meters"]["items"]["properties"]["name"]["enum"])


def validate_one(path: str, schema: dict) -> list[str]:
    """Return a list of human-readable errors (empty = valid)."""
    errs: list[str] = []
    try:
        with open(path, encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh) or {}
    except (OSError, yaml.YAMLError) as e:
        return [f"{path}: cannot read/parse ({e})"]
    if not isinstance(cfg, dict):
        return [f"{path}: top-level must be a mapping"]

    p = lambda m: errs.append(f"{path}: {m}")  # noqa: E731

    for req in schema["required"]:
        if req not in cfg:
            p(f"missing required key '{req}'")

    allowed = set(schema["properties"])
    for k in cfg:
        if k not in allowed:
            p(f"unknown key '{k}' (schema is additionalProperties:false)")

    auth_enum = schema["properties"]["authoritative"]["enum"]
    if cfg.get("authoritative") not in auth_enum:
        p(f"authoritative={cfg.get('authoritative')!r} not in {auth_enum}")

    # THE CENTS INVARIANT — pinned const in the schema, read from it (no hardcode drift).
    want_passthrough = _const(schema, "passthrough_unit_decimal")
    if str(cfg.get("passthrough_unit_decimal")) != want_passthrough:
        p(f"passthrough_unit_decimal must be {want_passthrough!r} (THE cents invariant — any other value "
          f"silently mis-bills 100×); got {cfg.get('passthrough_unit_decimal')!r}")

    want_idem = _const(schema, "idempotency")
    if cfg.get("idempotency") != want_idem:
        p(f"idempotency must be {want_idem!r} (one UUID per decision to every sink); got {cfg.get('idempotency')!r}")

    shadows = cfg.get("shadows") or []
    if not isinstance(shadows, list):
        p("shadows must be a list")
    else:
        for s in shadows:
            if s not in ("stripe", "metronome"):
                p(f"shadow {s!r} is not a known provider")
        if cfg.get("authoritative") in shadows:
            p(f"authoritative provider {cfg.get('authoritative')!r} must not also be a shadow")

    mirror = cfg.get("mirror", None)
    if mirror not in (None, "supabase"):
        p(f"mirror={mirror!r} must be null or 'supabase'")

    canonical = _canonical_meters(schema)
    meters = cfg.get("meters")
    billed: set[str] = set()
    if not isinstance(meters, list) or not meters:
        p("meters must be a non-empty list")
    else:
        for m in meters:
            if not isinstance(m, dict):
                p(f"meter entry {m!r} must be a mapping")
                continue
            name = m.get("name")
            billed.add(name)
            if name not in canonical:
                p(f"meter {name!r} is not a canonical meter (no product-local twins); registry: {sorted(canonical)}")
            rate = m.get("rate_cents")
            if not isinstance(rate, (int, float)) or rate < 0:
                p(f"meter {name!r} rate_cents must be a number >= 0 (stored in CENTS = code-dollars × 100); got {rate!r}")
            agg = m.get("aggregation", "sum")
            if agg not in ("sum", "last", "count"):
                p(f"meter {name!r} aggregation {agg!r} not in [sum,last,count]")

    # Conditional: metronome-authoritative requires the org connection (gate cleared).
    if cfg.get("authoritative") == "metronome" and cfg.get("metronome_connection_gated", True) is not False:
        p("authoritative=metronome requires metronome_connection_gated:false (the org OAuth connection must "
          "be established before Metronome can be the invoicing-of-record provider)")

    # Cross-check against a sibling pricing.yaml, if present.
    pricing = os.path.join(os.path.dirname(os.path.abspath(path)), "pricing.yaml")
    if billed and os.path.exists(pricing):
        try:
            with open(pricing, encoding="utf-8") as fh:
                pdoc = yaml.safe_load(fh) or {}
            priced = set(pdoc.get("meter") or [])
            for b in billed:
                if b in canonical and priced and b not in priced:
                    p(f"meter {b!r} is billed but not declared in sibling pricing.yaml.meter {sorted(priced)}")
            if pdoc.get("product") and cfg.get("product") and pdoc["product"] != cfg["product"]:
                p(f"product {cfg['product']!r} != pricing.yaml product {pdoc['product']!r}")
        except (OSError, yaml.YAMLError):
            pass  # pricing.yaml is validated by its own gate; don't double-fail here

    return errs


def main() -> int:
    try:
        schema = load_schema()
    except (OSError, json.JSONDecodeError) as e:
        sys.stderr.write(f"cannot load schema {SCHEMA}: {e}\n")
        return 2

    paths = sys.argv[1:] or sorted(glob.glob("**/billing.config.yaml", recursive=True))
    paths = [p for p in paths if os.path.basename(p) == "billing.config.yaml"]
    if not paths:
        print("no billing.config.yaml found — nothing to validate (a product adopts the contract by adding one)")
        return 0

    all_errs: list[str] = []
    for path in paths:
        e = validate_one(path, schema)
        all_errs += e
        print(f"{'✓' if not e else '✗'} {path}" + ("" if not e else f"  ({len(e)} error(s))"))

    if all_errs:
        sys.stderr.write("\nbilling-contract violations:\n  - " + "\n  - ".join(all_errs) + "\n")
        return 1
    print(f"billing-contract: {len(paths)} config(s) valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
