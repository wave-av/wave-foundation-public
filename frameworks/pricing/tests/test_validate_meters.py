"""Teeth tests for validate-meters.py — prove the meter-registry gate actually catches the failures it claims.

The real registry + schemas must pass clean; deliberately injecting a below-COGS price, a decisions
rate-variant under the base rate, an enum that drops an active meter, and an enum with an unknown meter
must each produce a violation. (If any negative case passed, the gate would be decorative.)

Pure stdlib + pytest. Loads the hyphenated module via importlib.
"""
import copy
import importlib.util
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PRICING = os.path.dirname(HERE)
BILLING = os.path.join(os.path.dirname(PRICING), "billing")

_spec = importlib.util.spec_from_file_location("validate_meters", os.path.join(PRICING, "validate-meters.py"))
vm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(vm)


def _load(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)


REG = _load(os.path.join(PRICING, "meters.json"))
PSCHEMA = _load(os.path.join(PRICING, "pricing.schema.json"))
BSCHEMA = _load(os.path.join(BILLING, "billing-config.schema.json"))


def test_real_registry_is_clean():
    assert vm.validate(REG, PSCHEMA, BSCHEMA) == []


def test_below_cogs_is_caught():
    reg = copy.deepcopy(REG)
    reg["meters"]["storage_gb"]["list_price_usd"] = 0.001  # below the $0.023 S3 floor
    errs = vm.validate(reg, PSCHEMA, BSCHEMA)
    assert any("margin" in e and "storage_gb" in e for e in errs), errs


def test_priced_floor_without_price_is_caught():
    reg = copy.deepcopy(REG)
    reg["meters"]["stream_minutes"]["list_price_usd"] = None  # has cogs but no price
    errs = vm.validate(reg, PSCHEMA, BSCHEMA)
    assert any("margin" in e and "stream_minutes" in e for e in errs), errs


def test_decisions_variant_below_base_is_caught():
    reg = copy.deepcopy(REG)
    reg["meters"]["decisions"]["rates"]["overage"] = 0.00005  # below the 0.0001 account rate
    errs = vm.validate(reg, PSCHEMA, BSCHEMA)
    assert any("decisions.rates.overage" in e for e in errs), errs


def test_enum_missing_active_meter_is_caught():
    pschema = copy.deepcopy(PSCHEMA)
    # drop storage_minutes from the first meter enum we find
    found = []
    vm.find_meter_enums(pschema, found)
    found[0].remove("storage_minutes")
    errs = vm.validate(REG, pschema, BSCHEMA)
    assert any("drift" in e and "storage_minutes" in e for e in errs), errs


def test_enum_unknown_meter_is_caught():
    bschema = copy.deepcopy(BSCHEMA)
    found = []
    vm.find_meter_enums(bschema, found)
    found[0].append("frames_rendered")  # not a registry meter nor a deprecated alias
    errs = vm.validate(REG, bschema, BSCHEMA)
    assert any("drift" in e and "frames_rendered" in e for e in errs), errs


def test_cents_mismatch_is_caught():
    # a billing.config that bills decisions at the wrong cents (should be 0.0001 x 100 = 0.01)
    bad_cfg = {"__path__": "x/billing.config.yaml", "meters": [{"name": "decisions", "rate_cents": 100}]}
    errs = vm.validate(REG, PSCHEMA, BSCHEMA, [bad_cfg])
    assert any("cents" in e and "decisions" in e for e in errs), errs
