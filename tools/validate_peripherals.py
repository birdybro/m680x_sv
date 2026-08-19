#!/usr/bin/env python3
"""Validate independently written MCU peripheral specifications."""

from __future__ import annotations

import json
from pathlib import Path
import sys

from tools.fetch_references import load_manifest
from tools.validate_devices import _load_json


ROOT = Path(__file__).resolve().parents[1]
SPEC_DIRECTORY = ROOT / "spec" / "peripherals"


class PeripheralSpecError(RuntimeError):
    """Raised when a peripheral specification is incomplete or contradictory."""


def _hex_address(value: object, owner: str) -> int:
    if not isinstance(value, str):
        raise PeripheralSpecError(f"{owner}: address must be a hexadecimal string")
    try:
        return int(value, 16)
    except ValueError as exc:
        raise PeripheralSpecError(f"{owner}: invalid address {value!r}") from exc


def validate_peripheral(spec: dict, devices: dict, references: dict) -> None:
    required = {
        "schema_version", "device", "address_width", "memory_regions", "registers",
        "timer", "interrupts", "implementation_scope",
    }
    if set(spec) != required or spec["schema_version"] != 1:
        raise PeripheralSpecError("peripheral record has incomplete fields or schema")
    device_ids = {device["id"] for device in devices["devices"]}
    if spec["device"] not in device_ids:
        raise PeripheralSpecError(f"unknown device {spec['device']!r}")
    width = spec["address_width"]
    if not isinstance(width, int) or not 8 <= width <= 24:
        raise PeripheralSpecError("invalid address width")
    limit = (1 << width) - 1
    previous_end = -1
    for region in spec["memory_regions"]:
        if set(region) != {"start", "end", "kind", "access"}:
            raise PeripheralSpecError("malformed memory region")
        start = _hex_address(region["start"], region["kind"])
        end = _hex_address(region["end"], region["kind"])
        if start > end or end > limit or start <= previous_end:
            raise PeripheralSpecError("memory regions overlap, are unsorted, or exceed address width")
        previous_end = end
    known_references = {reference["id"] for reference in references["references"]}
    seen_addresses: set[int] = set()
    for register in spec["registers"]:
        required_register = {"address", "name", "read", "write", "reset", "reference"}
        if set(register) != required_register:
            raise PeripheralSpecError("malformed register record")
        address = _hex_address(register["address"], register["name"])
        if address > limit or address in seen_addresses:
            raise PeripheralSpecError("duplicate or out-of-range register address")
        seen_addresses.add(address)
        citation = register["reference"]
        if set(citation) != {"id", "locator"} or citation["id"] not in known_references or not citation["locator"]:
            raise PeripheralSpecError(f"{register['name']}: invalid reference")
    vectors: set[str] = set()
    priorities: set[int] = set()
    for interrupt in spec["interrupts"]:
        if set(interrupt) != {"source", "vector", "priority"} or interrupt["vector"] in vectors:
            raise PeripheralSpecError("malformed or duplicate interrupt vector")
        vectors.add(interrupt["vector"])
        if isinstance(interrupt["priority"], int):
            if interrupt["priority"] in priorities:
                raise PeripheralSpecError("duplicate numeric interrupt priority")
            priorities.add(interrupt["priority"])


def main() -> int:
    devices = _load_json(ROOT / "spec" / "devices.yml")
    references = load_manifest(ROOT / "docs" / "references.yml")
    paths = sorted(SPEC_DIRECTORY.glob("*.json"))
    if not paths:
        print("peripheral specification error: no specifications", file=sys.stderr)
        return 1
    try:
        for path in paths:
            validate_peripheral(json.loads(path.read_text(encoding="utf-8")), devices, references)
    except (OSError, json.JSONDecodeError, PeripheralSpecError) as exc:
        print(f"peripheral specification error: {exc}", file=sys.stderr)
        return 1
    print(f"peripheral specifications valid: {len(paths)} device profile(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
