#!/usr/bin/env python3
"""Validate expanded 256-value opcode specifications."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from tools.fetch_references import DEFAULT_MANIFEST, ReferenceError, load_manifest


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OPCODE_DIR = ROOT / "spec" / "opcodes"
DEFAULT_DEVICE_SPEC = ROOT / "spec" / "devices.yml"
RECORD_FIELDS = {
    "opcode", "opcode_hex", "classification", "mnemonic", "aliases",
    "architectural_applicability", "addressing_mode", "length", "cycles",
    "conditional_cycles", "registers_read", "registers_written", "flags_read",
    "flags_affected", "flags_undefined", "flag_semantics", "memory_operations",
    "stack_effects", "branch_behavior", "vector_behavior", "primary_reference", "notes",
}
CLASSIFICATIONS = {
    "documented_instruction",
    "documented_illegal_reserved",
    "documented_special_behavior",
    "undefined_behavior",
}
FLAGS = {"H", "I", "N", "Z", "V", "C"}


class OpcodeSpecError(RuntimeError):
    """Raised for incomplete or contradictory opcode records."""


def load_opcode_spec(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise OpcodeSpecError(f"cannot load opcode specification {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise OpcodeSpecError(f"{path}: top level must be an object")
    return value


def _strings(value: object) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) and item for item in value)


def validate_opcode_spec(spec: dict, known_references: set[str]) -> None:
    if spec.get("schema_version") != 1:
        raise OpcodeSpecError("opcode schema_version must be 1")
    architecture = spec.get("architecture")
    if not isinstance(architecture, str) or not architecture:
        raise OpcodeSpecError("architecture must be non-empty")
    opcodes = spec.get("opcodes")
    if not isinstance(opcodes, list) or len(opcodes) != 256:
        raise OpcodeSpecError(f"{architecture}: exactly 256 opcode records are required")

    seen: set[int] = set()
    for index, record in enumerate(opcodes):
        if not isinstance(record, dict) or set(record) != RECORD_FIELDS:
            raise OpcodeSpecError(f"{architecture}: opcode record {index} has incomplete fields")
        opcode = record["opcode"]
        if not isinstance(opcode, int) or not 0 <= opcode <= 255:
            raise OpcodeSpecError(f"{architecture}: invalid opcode value at record {index}")
        if opcode in seen:
            raise OpcodeSpecError(f"{architecture}: duplicate opcode {opcode:02X}")
        seen.add(opcode)
        if record["opcode_hex"] != f"{opcode:02X}":
            raise OpcodeSpecError(f"{architecture}: inconsistent opcode_hex for {opcode:02X}")
        if record["classification"] not in CLASSIFICATIONS:
            raise OpcodeSpecError(f"{architecture}: invalid classification for {opcode:02X}")
        if record["architectural_applicability"] != [architecture]:
            raise OpcodeSpecError(f"{architecture}: applicability conflict for {opcode:02X}")
        for field in (
            "aliases", "conditional_cycles", "registers_read", "registers_written",
            "flags_read", "flags_affected", "flags_undefined", "memory_operations", "stack_effects",
        ):
            if not _strings(record[field]):
                raise OpcodeSpecError(f"{architecture}: {field} must be strings for {opcode:02X}")
        if not set(record["flags_read"] + record["flags_affected"] + record["flags_undefined"]) <= FLAGS:
            raise OpcodeSpecError(f"{architecture}: unknown flag for {opcode:02X}")
        if set(record["flags_affected"]) & set(record["flags_undefined"]):
            raise OpcodeSpecError(f"{architecture}: affected/undefined flag conflict for {opcode:02X}")
        if set(record["flag_semantics"]) != set(record["flags_affected"] + record["flags_undefined"]):
            raise OpcodeSpecError(f"{architecture}: flag semantics mismatch for {opcode:02X}")
        reference = record["primary_reference"]
        if (
            not isinstance(reference, dict)
            or set(reference) != {"id", "locator"}
            or reference["id"] not in known_references
            or not isinstance(reference["locator"], str)
            or not reference["locator"]
        ):
            raise OpcodeSpecError(f"{architecture}: invalid reference for {opcode:02X}")

        if record["classification"] in {
            "documented_instruction", "documented_special_behavior"
        }:
            if not isinstance(record["mnemonic"], str) or not record["mnemonic"]:
                raise OpcodeSpecError(f"{architecture}: defined behavior {opcode:02X} needs mnemonic")
            if not isinstance(record["addressing_mode"], str) or not record["addressing_mode"]:
                raise OpcodeSpecError(f"{architecture}: defined behavior {opcode:02X} needs addressing mode")
            if not isinstance(record["length"], int) or not 1 <= record["length"] <= 4:
                raise OpcodeSpecError(f"{architecture}: invalid length for {opcode:02X}")
            if not isinstance(record["cycles"], int) or record["cycles"] <= 0:
                raise OpcodeSpecError(f"{architecture}: missing cycles for {opcode:02X}")
            if not record["memory_operations"]:
                raise OpcodeSpecError(f"{architecture}: defined behavior {opcode:02X} needs memory facts")
            if (
                record["classification"] == "documented_instruction"
                and record["memory_operations"][0] != "read opcode at PC"
            ):
                raise OpcodeSpecError(f"{architecture}: instruction {opcode:02X} needs opcode fetch")
        else:
            for field in ("mnemonic", "addressing_mode", "length", "cycles"):
                if record[field] is not None:
                    raise OpcodeSpecError(f"{architecture}: undefined {opcode:02X} assigns {field}")

    if seen != set(range(256)):
        raise OpcodeSpecError(f"{architecture}: opcode values are not exactly 00-FF")


def validate_directory(
    opcode_dir: Path,
    reference_manifest: dict,
    expected_architectures: set[str] | None = None,
) -> tuple[int, int]:
    known_references = {item["id"] for item in reference_manifest["references"]}
    paths = sorted(opcode_dir.glob("*.json"))
    if not paths:
        raise OpcodeSpecError(f"no opcode specifications in {opcode_dir}")
    architectures: set[str] = set()
    documented = 0
    for path in paths:
        spec = load_opcode_spec(path)
        validate_opcode_spec(spec, known_references)
        architecture = spec["architecture"]
        if architecture in architectures:
            raise OpcodeSpecError(f"duplicate architecture file: {architecture}")
        architectures.add(architecture)
        documented += sum(
            record["classification"] == "documented_instruction" for record in spec["opcodes"]
        )
    if expected_architectures is not None and architectures != expected_architectures:
        missing = sorted(expected_architectures - architectures)
        extra = sorted(architectures - expected_architectures)
        raise OpcodeSpecError(f"opcode/device architecture conflict: missing={missing}, extra={extra}")
    return len(paths), documented


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--opcode-dir", type=Path, default=DEFAULT_OPCODE_DIR)
    parser.add_argument("--devices", type=Path, default=DEFAULT_DEVICE_SPEC)
    parser.add_argument("--references", type=Path, default=DEFAULT_MANIFEST)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        references = load_manifest(args.references)
        devices = json.loads(args.devices.read_text(encoding="utf-8"))
        expected_architectures = set(devices["architectures"])
        files, documented = validate_directory(
            args.opcode_dir, references, expected_architectures
        )
    except (OpcodeSpecError, ReferenceError, OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        print(f"opcode specification error: {exc}", file=sys.stderr)
        return 1
    print(f"opcode specifications valid: {files} architectures, {files * 256} classified values, {documented} documented instruction encodings")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
