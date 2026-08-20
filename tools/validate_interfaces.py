#!/usr/bin/env python3
"""Validate independently written device-interface specifications."""

from __future__ import annotations

import json
from pathlib import Path
import sys

from tools.fetch_references import load_manifest
from tools.validate_devices import _load_json


ROOT = Path(__file__).resolve().parents[1]
SPEC_DIRECTORY = ROOT / "spec" / "interfaces"
VALID_STATUS = {"COMPLETE", "PARTIAL", "NOT_IMPLEMENTED", "NOT_APPLICABLE"}
REQUIRED_SIGNALS = {
    "mc6800-bus-control": {
        "clk_i", "clock_enable_i", "reset_n_i", "irq_n_i", "nmi_n_i",
        "halt_n_i", "tsc_i", "dbe_i", "data_i", "address_o",
        "address_oe_o", "data_o", "data_oe_o", "read_not_write_o",
        "read_not_write_oe_o", "vma_o", "ba_o",
    },
    "mc6800-four-subphase-integration-bus": {
        "phase_clk_i", "phase_reset_n_i", "clock_enable_i", "reset_n_i",
        "irq_n_i", "nmi_n_i", "halt_n_i", "tsc_i", "dbe_i", "data_i",
        "phi1_o", "phi2_o", "bus_phase_o", "address_o", "address_oe_o",
        "data_o", "data_oe_o", "read_not_write_o", "read_not_write_oe_o",
        "vma_o", "ba_o",
    },
    "mc6801-four-subphase-device-bus": {
        "phase_clk_i", "phase_reset_n_i", "clock_enable_i", "reset_n_i",
        "e_o", "bus_phase_o", "sc1_i", "sc1_o", "sc1_oe_o", "sc2_o",
        "port3_i", "port3_o", "port3_oe_o", "port4_i", "port4_o",
        "port4_oe_o", "operating_mode_o",
    },
    "hd6303r-four-subphase-device-bus": {
        "phase_clk_i", "phase_reset_n_i", "clock_enable_i", "reset_n_i",
        "standby_n_i", "standby_power_ok_i", "e_o", "bus_phase_o",
        "sc1_o", "sc1_oe_o", "sc2_o", "port1_i", "port1_o",
        "port1_oe_o", "port3_i", "port3_o", "port3_oe_o", "port4_o",
        "port4_oe_o", "standby_active_o",
    },
    "hd6301v1-four-subphase-device-bus": {
        "phase_clk_i", "phase_reset_n_i", "clock_enable_i", "reset_n_i",
        "standby_n_i", "standby_power_ok_i", "e_o", "bus_phase_o",
        "sc1_i", "sc1_o", "sc1_oe_o", "sc2_o", "port1_i", "port1_o",
        "port1_oe_o", "port3_i", "port3_o", "port3_oe_o", "port4_i",
        "port4_o", "port4_oe_o", "standby_active_o", "program_address_o",
        "program_read_o", "program_data_i",
    },
    "hd63701v0-four-subphase-device-bus": {
        "phase_clk_i", "phase_reset_n_i", "clock_enable_i", "reset_n_i",
        "standby_n_i", "standby_power_ok_i", "e_o", "bus_phase_o",
        "sc1_i", "sc1_o", "sc1_oe_o", "sc2_o", "port1_i", "port1_o",
        "port1_oe_o", "port2_i", "port2_o", "port2_oe_o", "port3_i",
        "port3_o", "port3_oe_o", "port4_i", "port4_o", "port4_oe_o",
        "standby_active_o", "program_address_o", "program_read_o",
        "program_data_i",
    },
}


class InterfaceSpecError(RuntimeError):
    """Raised when a device-interface specification is incomplete."""


def validate_interface(spec: dict, devices: dict, references: dict) -> None:
    required = {
        "schema_version", "interface", "device", "clock_model", "signals",
        "halt_interrupt_behavior", "references", "implementation_status",
    }
    if set(spec) != required or spec["schema_version"] != 1:
        raise InterfaceSpecError("interface record has incomplete fields or schema")
    device_ids = {device["id"] for device in devices["devices"]}
    if spec["device"] not in device_ids:
        raise InterfaceSpecError(f"unknown device {spec['device']!r}")
    if not isinstance(spec["interface"], str) or not spec["interface"]:
        raise InterfaceSpecError("interface needs an identifier")

    clock_fields = {"rtl_boundary", "historical_boundary", "status", "limitation"}
    if not isinstance(spec["clock_model"], dict) or set(spec["clock_model"]) != clock_fields:
        raise InterfaceSpecError("clock model is incomplete")
    if spec["clock_model"]["status"] not in VALID_STATUS:
        raise InterfaceSpecError("clock model has invalid status")

    if not isinstance(spec["signals"], list) or not spec["signals"]:
        raise InterfaceSpecError("interface signals must be a non-empty list")
    names: set[str] = set()
    for signal in spec["signals"]:
        if not isinstance(signal, dict) or set(signal) != {
            "name", "historical", "direction", "fact"
        }:
            raise InterfaceSpecError("malformed interface signal")
        if (
            signal["direction"] not in {"input", "output"}
            or not all(isinstance(signal[field], str) and signal[field].strip()
                       for field in ("name", "historical", "fact"))
        ):
            raise InterfaceSpecError(f"invalid signal {signal['name']!r}")
        if signal["name"] in names:
            raise InterfaceSpecError(f"duplicate signal {signal['name']!r}")
        names.add(signal["name"])
    missing = REQUIRED_SIGNALS.get(spec["interface"], set()) - names
    if missing:
        raise InterfaceSpecError(f"missing required signals: {sorted(missing)}")

    known_references = {reference["id"] for reference in references["references"]}
    if not isinstance(spec["references"], list) or not spec["references"]:
        raise InterfaceSpecError("interface needs references")
    for citation in spec["references"]:
        if (
            not isinstance(citation, dict)
            or set(citation) != {"id", "locators"}
            or citation["id"] not in known_references
        ):
            raise InterfaceSpecError("invalid interface reference")
        if not citation["locators"] or not all(citation["locators"]):
            raise InterfaceSpecError("interface reference needs locators")
    if (
        not isinstance(spec["halt_interrupt_behavior"], str)
        or not spec["halt_interrupt_behavior"].strip()
    ):
        raise InterfaceSpecError("halt interrupt behavior must be documented")
    if (
        not isinstance(spec["implementation_status"], dict)
        or not spec["implementation_status"]
        or not all(isinstance(field, str) and field for field in spec["implementation_status"])
        or any(status not in VALID_STATUS
               for status in spec["implementation_status"].values())
    ):
        raise InterfaceSpecError("invalid implementation status")


def main() -> int:
    devices = _load_json(ROOT / "spec" / "devices.yml")
    references = load_manifest(ROOT / "docs" / "references.yml")
    paths = sorted(SPEC_DIRECTORY.glob("*.json"))
    if not paths:
        print("interface specification error: no specifications", file=sys.stderr)
        return 1
    try:
        for path in paths:
            validate_interface(json.loads(path.read_text(encoding="utf-8")), devices, references)
    except (OSError, json.JSONDecodeError, InterfaceSpecError) as exc:
        print(f"interface specification error: {exc}", file=sys.stderr)
        return 1
    print(f"interface specifications valid: {len(paths)} device interface(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
