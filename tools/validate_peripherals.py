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


PERIPHERAL_SECTIONS = {
    "registers", "timer", "interrupts", "gpio", "sci", "operating_modes",
    "memory_control",
}
OPTIONAL_PERIPHERAL_SECTIONS = {"interrupt_controller"}


def validate_peripheral(spec: dict, devices: dict, references: dict) -> None:
    full_required = {
        "schema_version", "device", "address_width", "memory_regions", "registers",
        "timer", "interrupts", "implementation_scope",
    }
    inherited_required = {
        "schema_version", "device", "address_width", "memory_regions", "inherits",
        "implementation_scope",
    }
    required = inherited_required if "inherits" in spec else full_required
    allowed = full_required | PERIPHERAL_SECTIONS | OPTIONAL_PERIPHERAL_SECTIONS | {"inherits"}
    if not required <= set(spec) or set(spec) - allowed or spec["schema_version"] != 1:
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
    if "inherits" in spec:
        inheritance = spec["inherits"]
        required_inheritance = {"device", "sections", "scope", "restrictions", "reference"}
        if not isinstance(inheritance, dict) or set(inheritance) != required_inheritance:
            raise PeripheralSpecError("malformed peripheral-profile inheritance")
        sections = inheritance["sections"]
        if (
            inheritance["device"] == spec["device"]
            or not isinstance(sections, list)
            or not sections
            or len(set(sections)) != len(sections)
            or not set(sections) <= PERIPHERAL_SECTIONS
            or any(section in spec for section in sections)
            or any(section not in spec and section not in sections for section in PERIPHERAL_SECTIONS)
        ):
            raise PeripheralSpecError("invalid inherited peripheral sections")
        if not isinstance(inheritance["scope"], str) or not inheritance["scope"].strip():
            raise PeripheralSpecError("inherited peripheral scope must be non-empty")
        if (
            not isinstance(inheritance["restrictions"], list)
            or not inheritance["restrictions"]
            or not all(isinstance(item, str) and item.strip() for item in inheritance["restrictions"])
        ):
            raise PeripheralSpecError("inherited peripheral restrictions must be non-empty")
        citation = inheritance["reference"]
        if (
            not isinstance(citation, dict)
            or set(citation) != {"id", "locator"}
            or citation["id"] not in known_references
            or not citation["locator"]
        ):
            raise PeripheralSpecError("invalid peripheral inheritance reference")
    seen_addresses: set[int] = set()
    for register in spec.get("registers", []):
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
    for interrupt in spec.get("interrupts", []):
        if set(interrupt) != {"source", "vector", "priority"} or interrupt["vector"] in vectors:
            raise PeripheralSpecError("malformed or duplicate interrupt vector")
        vectors.add(interrupt["vector"])
        if isinstance(interrupt["priority"], int):
            if interrupt["priority"] in priorities:
                raise PeripheralSpecError("duplicate numeric interrupt priority")
            priorities.add(interrupt["priority"])

    def validate_citations(value: object, owner: str) -> None:
        if isinstance(value, dict):
            if "reference" in value:
                citation = value["reference"]
                if not isinstance(citation, dict) or set(citation) != {"id", "locator"}:
                    raise PeripheralSpecError(f"{owner}: malformed reference")
                if citation["id"] not in known_references or not citation["locator"]:
                    raise PeripheralSpecError(f"{owner}: invalid reference")
            for key, nested in value.items():
                if key != "reference":
                    validate_citations(nested, f"{owner}.{key}")
        elif isinstance(value, list):
            for index, nested in enumerate(value):
                validate_citations(nested, f"{owner}[{index}]")

    for section in (
        "timer", "gpio", "sci", "operating_modes", "memory_control",
        "interrupt_controller",
    ):
        if section in spec:
            validate_citations(spec[section], section)


def validate_inheritance_graph(specs: dict[str, dict]) -> None:
    """Require every inherited section to resolve to an acyclic device profile."""

    for device, spec in specs.items():
        if "inherits" not in spec:
            continue
        base = spec["inherits"]["device"]
        if base not in specs:
            raise PeripheralSpecError(f"{device}: unknown inherited profile {base!r}")
        for section in spec["inherits"]["sections"]:
            if section not in specs[base]:
                raise PeripheralSpecError(f"{device}: base profile lacks {section!r}")

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(device: str) -> None:
        if device in visiting:
            raise PeripheralSpecError("cyclic peripheral-profile inheritance")
        if device in visited:
            return
        visiting.add(device)
        spec = specs[device]
        if "inherits" in spec:
            visit(spec["inherits"]["device"])
        visiting.remove(device)
        visited.add(device)

    for device in specs:
        visit(device)


def main() -> int:
    devices = _load_json(ROOT / "spec" / "devices.yml")
    references = load_manifest(ROOT / "docs" / "references.yml")
    paths = sorted(SPEC_DIRECTORY.glob("*.json"))
    if not paths:
        print("peripheral specification error: no specifications", file=sys.stderr)
        return 1
    try:
        specs: dict[str, dict] = {}
        for path in paths:
            spec = json.loads(path.read_text(encoding="utf-8"))
            validate_peripheral(spec, devices, references)
            if spec["device"] in specs:
                raise PeripheralSpecError("duplicate peripheral device profile")
            specs[spec["device"]] = spec
        validate_inheritance_graph(specs)
    except (OSError, json.JSONDecodeError, PeripheralSpecError) as exc:
        print(f"peripheral specification error: {exc}", file=sys.stderr)
        return 1
    print(f"peripheral specifications valid: {len(paths)} device profile(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
