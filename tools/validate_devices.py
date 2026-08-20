#!/usr/bin/env python3
"""Validate the clean-room architectural and device support matrix."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

from tools.fetch_references import DEFAULT_MANIFEST, ReferenceError, load_manifest


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DEVICES = ROOT / "spec" / "devices.yml"
STATUS_FIELDS = {
    "cpu_core",
    "architectural_tests",
    "cycle_count_tests",
    "bus_trace_tests",
    "device_wrapper",
    "internal_memory",
    "gpio",
    "timer",
    "serial",
    "low_power",
}
ARCHITECTURE_FIELDS = {
    "lineage",
    "register_set",
    "condition_code_register",
    "addressing_modes",
    "stack_behavior",
    "base_reset_behavior",
    "base_interrupt_behavior",
    "opcode_lineage",
    "undefined_behavior",
    "references",
}
DEVICE_FIELDS = {
    "id",
    "display_name",
    "manufacturer",
    "architecture",
    "implementation_scope",
    "release_target",
    "address_width",
    "internal_memory",
    "peripherals",
    "operating_modes",
    "interrupt_sources",
    "interrupt_priority",
    "vectors",
    "external_interface",
    "clocking",
    "documented_quirks",
    "undefined_by_documentation",
    "status",
    "references",
}
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")


class DeviceSpecError(RuntimeError):
    """Raised when the compatibility specification is inconsistent."""


def _load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DeviceSpecError(f"cannot load device specification {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise DeviceSpecError("device specification must be an object")
    return value


def _nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_list(value: object, *, allow_empty: bool = False) -> bool:
    return (
        isinstance(value, list)
        and (allow_empty or bool(value))
        and all(_nonempty_string(item) for item in value)
    )


def _validate_citations(citations: object, known_references: set[str], owner: str) -> None:
    if not isinstance(citations, list) or not citations:
        raise DeviceSpecError(f"{owner}: references must be a non-empty list")
    for citation in citations:
        if not isinstance(citation, dict) or set(citation) != {"id", "locators"}:
            raise DeviceSpecError(f"{owner}: malformed reference citation")
        if citation["id"] not in known_references:
            raise DeviceSpecError(f"{owner}: unknown reference id {citation['id']!r}")
        if not _string_list(citation["locators"]):
            raise DeviceSpecError(f"{owner}: citation needs precise locators")


def validate_devices(spec: dict, reference_manifest: dict) -> None:
    if spec.get("schema_version") != 1:
        raise DeviceSpecError("device schema_version must be 1")
    statuses = spec.get("status_values")
    required_statuses = {
        "COMPLETE",
        "PARTIAL",
        "NOT_IMPLEMENTED",
        "NOT_APPLICABLE",
        "UNDEFINED_BY_DOCUMENTATION",
    }
    if not isinstance(statuses, list) or set(statuses) != required_statuses:
        raise DeviceSpecError("status_values must contain the five defined values")
    known_references = {item["id"] for item in reference_manifest["references"]}

    architectures = spec.get("architectures")
    if not isinstance(architectures, dict) or not architectures:
        raise DeviceSpecError("architectures must be a non-empty object")
    for architecture_id, architecture in architectures.items():
        if not ID_RE.fullmatch(architecture_id) or not isinstance(architecture, dict):
            raise DeviceSpecError(f"invalid architecture {architecture_id!r}")
        if set(architecture) != ARCHITECTURE_FIELDS:
            raise DeviceSpecError(f"{architecture_id}: architecture fields are incomplete")
        for field in (
            "lineage",
            "stack_behavior",
            "base_reset_behavior",
            "base_interrupt_behavior",
            "opcode_lineage",
        ):
            if not _nonempty_string(architecture[field]):
                raise DeviceSpecError(f"{architecture_id}: {field} must be non-empty")
        for field in ("register_set", "addressing_modes", "undefined_behavior"):
            if not _string_list(architecture[field]):
                raise DeviceSpecError(f"{architecture_id}: {field} must be non-empty strings")
        ccr = architecture["condition_code_register"]
        if not isinstance(ccr, dict) or not _string_list(ccr.get("implemented_bits")):
            raise DeviceSpecError(f"{architecture_id}: invalid condition-code register")
        _validate_citations(architecture["references"], known_references, architecture_id)

    devices = spec.get("devices")
    if not isinstance(devices, list) or not devices:
        raise DeviceSpecError("devices must be a non-empty list")
    seen_ids: set[str] = set()
    for device in devices:
        if not isinstance(device, dict) or set(device) != DEVICE_FIELDS:
            raise DeviceSpecError("device record fields are incomplete or unknown")
        device_id = device["id"]
        if not isinstance(device_id, str) or not ID_RE.fullmatch(device_id):
            raise DeviceSpecError("invalid device id")
        if device_id in seen_ids:
            raise DeviceSpecError(f"duplicate device id: {device_id}")
        seen_ids.add(device_id)
        if device["architecture"] not in architectures:
            raise DeviceSpecError(f"{device_id}: unknown architecture")
        if device["implementation_scope"] not in {"CPU_DEVICE", "CPU_CORE_ONLY", "FULL_MCU"}:
            raise DeviceSpecError(f"{device_id}: invalid implementation_scope")
        if not isinstance(device["address_width"], int) or not 8 <= device["address_width"] <= 32:
            raise DeviceSpecError(f"{device_id}: invalid address_width")
        for field in ("display_name", "manufacturer", "release_target", "external_interface", "clocking"):
            if not _nonempty_string(device[field]):
                raise DeviceSpecError(f"{device_id}: {field} must be non-empty")
        for field in (
            "internal_memory",
            "peripherals",
            "operating_modes",
            "interrupt_sources",
            "interrupt_priority",
            "documented_quirks",
            "undefined_by_documentation",
        ):
            allow_empty = field in {"internal_memory", "peripherals"}
            if not _string_list(device[field], allow_empty=allow_empty):
                raise DeviceSpecError(f"{device_id}: invalid {field}")
        if not isinstance(device["vectors"], dict) or not device["vectors"]:
            raise DeviceSpecError(f"{device_id}: vectors must be non-empty")
        if set(device["status"]) != STATUS_FIELDS:
            raise DeviceSpecError(f"{device_id}: status fields are incomplete")
        if any(value not in required_statuses for value in device["status"].values()):
            raise DeviceSpecError(f"{device_id}: invalid status value")
        if device["release_target"] == "v1" and any(
            value in {"PARTIAL", "NOT_IMPLEMENTED"}
            for value in device["status"].values()
        ):
            raise DeviceSpecError(
                f"{device_id}: v1 target retains a non-terminal implementation status"
            )
        if device["implementation_scope"] == "FULL_MCU" and any(
            device["status"][field] == "NOT_APPLICABLE"
            for field in ("device_wrapper", "internal_memory", "gpio")
        ):
            raise DeviceSpecError(f"{device_id}: full MCU marks required integration NOT_APPLICABLE")
        _validate_citations(device["references"], known_references, device_id)

    required_targets = {
        "mc6800",
        "mc6801",
        "mc6803",
        "m6805_cpu",
        "mc68705p5",
        "hd6301v1",
        "hd6303r",
        "hd63701v0",
        "hd63705v0",
    }
    if not required_targets <= seen_ids:
        raise DeviceSpecError(f"missing required v1 targets: {sorted(required_targets - seen_ids)}")

    investigated = spec.get("investigated_not_v1")
    if not isinstance(investigated, list) or not investigated:
        raise DeviceSpecError("investigated_not_v1 must record deferred documented variants")
    for item in investigated:
        if not isinstance(item, dict) or set(item) != {"families", "status", "reason"}:
            raise DeviceSpecError("malformed investigated_not_v1 record")
        if not _string_list(item["families"]) or item["status"] != "NOT_IMPLEMENTED" or not _nonempty_string(item["reason"]):
            raise DeviceSpecError("invalid investigated_not_v1 record")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--devices", type=Path, default=DEFAULT_DEVICES)
    parser.add_argument("--references", type=Path, default=DEFAULT_MANIFEST)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        spec = _load_json(args.devices)
        references = load_manifest(args.references)
        validate_devices(spec, references)
    except (DeviceSpecError, ReferenceError) as exc:
        print(f"device specification error: {exc}", file=sys.stderr)
        return 1
    print(
        f"device specification valid: {len(spec['architectures'])} architectures, "
        f"{len(spec['devices'])} targets"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
