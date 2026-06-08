#!/usr/bin/env python3
"""validate-meters.py — the canonical-meter-registry gate (frameworks/pricing).

Enforces, against the single source of record `meters.json`:

  1. MARGIN-SAFETY (the money guard): every meter's list_price_usd >= cogs_usd (the dearest covered-backend
     cost). A unit is never sold below the priciest backend that could serve it. decisions rate-variants
     (x402 / overage / premium) must each clear the base account rate. Meters with cogs_usd=null (unpriced,
     e.g. api_calls) are skipped. This is the exact invariant tests/test_pricing_ladder.py pins in dispatch,
     lifted to the platform registry.

  2. SINGLE-SOURCE / NO-DRIFT: the meter enums duplicated in pricing.schema.json (`meter` + `topology_meters`)
     and billing-config.schema.json (`name`) MUST equal the registry's active meters (plus any deprecated alias
     the registry still lists in `replaces`). Kills the storage_gb-vs-wave_storage_gb / voice_minutes-vs-
     voice_synthesis_minutes drift class — ONE list, three checked mirrors, not four hand-edited copies.

  3. CENTS-CONSISTENCY (optional): if a billing.config.yaml is present, every per_unit meter's rate_cents must
     equal list_price_usd x 100 (the CENTS INVARIANT; passthrough/none meters skipped).

IO is separated from logic: `validate(...)` is a pure function (testable with crafted dicts); main() just loads
the files and calls it. Reads the schemas — never hardcodes the meter list — so it can't disagree with what it
enforces. Pure stdlib (json; optional yaml only for the billing.config cross-check).

Usage:  validate-meters.py            # validate the registry + schema mirrors (+ any billing.config.yaml)
Exit:   0 clean, 1 violations (printed with the fix), 2 load/parse error.
"""
from __future__ import annotations

import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REGISTRY = os.path.join(HERE, "meters.json")
PRICING_SCHEMA = os.path.join(HERE, "pricing.schema.json")
BILLING_SCHEMA = os.path.join(os.path.dirname(HERE), "billing", "billing-config.schema.json")


def load_json(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def find_meter_enums(node, found: list[list[str]]) -> None:
    """Recursively collect every `enum` that contains a known canonical meter — robust to schema nesting."""
    if isinstance(node, dict):
        enum = node.get("enum")
        if isinstance(enum, list) and "decisions" in enum:
            found.append(enum)
        for v in node.values():
            find_meter_enums(v, found)
    elif isinstance(node, list):
        for v in node:
            find_meter_enums(v, found)


def validate(reg: dict, pricing_schema: dict, billing_schema: dict,
             billing_configs: list[dict] | None = None) -> list[str]:
    """Pure validator: returns a list of violation strings (empty = clean)."""
    errors: list[str] = []
    meters = reg.get("meters", {})
    if not meters:
        return ["[registry] meters.json has no meters"]

    active = set(meters.keys())
    deprecated = {a for m in meters.values() for a in (m.get("replaces") or []) if not a.startswith("wave_")}
    allowed = active | deprecated

    # 1. MARGIN-SAFETY
    for name, m in meters.items():
        cogs, price = m.get("cogs_usd"), m.get("list_price_usd")
        if cogs is None:
            continue  # unpriced — invariant intentionally skipped (cogs_source records why)
        if price is None:
            errors.append(f"[margin] {name}: cogs_usd={cogs} but list_price_usd is null (priced floor, no price).")
        elif price < cogs:
            errors.append(f"[margin] {name}: list_price_usd ${price} < dearest-backend COGS ${cogs} — below cost. "
                          f"Raise the price or correct cogs_source: {m.get('cogs_source', '?')}")
    rates = meters.get("decisions", {}).get("rates", {})
    base = rates.get("account")
    if base is not None:
        for k in ("x402", "overage", "premium"):
            v = rates.get(k)
            if v is not None and v < base:
                errors.append(f"[margin] decisions.rates.{k} ${v} < account ${base} — variant below base rate.")

    # 2. SINGLE-SOURCE / NO-DRIFT
    p_enums: list[list[str]] = []
    find_meter_enums(pricing_schema, p_enums)
    b_enums: list[list[str]] = []
    find_meter_enums(billing_schema, b_enums)
    if not p_enums:
        errors.append("[drift] pricing.schema.json has no meter enum (expected `meter` + `topology_meters`).")
    if not b_enums:
        errors.append("[drift] billing-config.schema.json has no meter `name` enum.")
    for label, enums in (("pricing.schema.json", p_enums), ("billing-config.schema.json", b_enums)):
        for enum in enums:
            es = set(enum)
            if active - es:
                errors.append(f"[drift] {label} enum missing active registry meters: {sorted(active - es)}. "
                              f"Add them (single source = meters.json).")
            if es - allowed:
                errors.append(f"[drift] {label} enum has names not in the registry nor a deprecated alias: "
                              f"{sorted(es - allowed)}. Add to meters.json first, or remove.")
    if len(p_enums) >= 2 and set(p_enums[0]) != set(p_enums[1]):
        errors.append("[drift] pricing.schema.json `meter` and `topology_meters` enums disagree — keep identical.")

    # 3. CENTS-CONSISTENCY (optional)
    for cfg in (billing_configs or []):
        src = cfg.get("__path__", "billing.config.yaml")
        for entry in cfg.get("meters", []):
            nm, rc = entry.get("name"), entry.get("rate_cents")
            m = meters.get(nm)
            if not m or m.get("billing") != "per_unit" or m.get("list_price_usd") is None or rc is None:
                continue
            want = round(m["list_price_usd"] * 100, 6)
            if round(float(rc), 6) != want:
                errors.append(f"[cents] {src}: meter {nm} rate_cents={rc} != list_price_usd x 100 = {want}.")
    return errors


def _load_billing_configs() -> list[dict]:
    cfgs: list[dict] = []
    paths = glob.glob(os.path.join(os.path.dirname(os.path.dirname(HERE)), "**", "billing.config.yaml"), recursive=True)
    if not paths:
        return cfgs
    try:
        import yaml  # noqa: PLC0415
    except ImportError:
        print("::notice::pyyaml not installed — skipping the optional billing.config cents cross-check.")
        return cfgs
    for p in paths:
        d = yaml.safe_load(open(p, encoding="utf-8")) or {}
        d["__path__"] = os.path.relpath(p)
        cfgs.append(d)
    return cfgs


def main() -> int:
    try:
        reg = load_json(REGISTRY)
        pricing_schema = load_json(PRICING_SCHEMA)
        billing_schema = load_json(BILLING_SCHEMA)
    except Exception as e:  # noqa: BLE001
        print(f"::error::could not load registry/schemas: {e}", file=sys.stderr)
        return 2
    errors = validate(reg, pricing_schema, billing_schema, _load_billing_configs())
    if errors:
        print(f"meter-registry: {len(errors)} violation(s)\n", file=sys.stderr)
        for e in errors:
            print("  ✗ " + e, file=sys.stderr)
        return 1
    meters = reg["meters"]
    priced = [n for n, m in meters.items() if m.get("cogs_usd") is not None]
    print(f"✓ meter-registry clean: {len(meters)} canonical meters, {len(priced)} margin-safe (≥ dearest COGS), "
          f"schema enums consistent with meters.json.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
