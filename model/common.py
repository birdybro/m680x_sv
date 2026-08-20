"""Common data containers for the independent instruction-level models."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


class UndefinedBehavior(RuntimeError):
    """Raised when execution reaches behavior not defined by primary manuals."""


@dataclass(frozen=True)
class BusAccess:
    """An architecturally ordered memory access within one instruction."""

    kind: str
    address: int
    data: int
    purpose: str
    data_defined: bool = True
    address_defined_mask: int = 0xFFFF


@dataclass
class InstructionTrace:
    """Deterministic instruction-level trace emitted by a model step."""

    instruction: int
    pc: int
    opcode: int
    mnemonic: str
    architecture: str
    documented_cycles: int
    state_before: dict[str, int | bool]
    state_after: dict[str, int | bool] = field(default_factory=dict)
    effective_address: int | None = None
    accesses: list[BusAccess] = field(default_factory=list)
    undefined_flags: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return {
            "instruction": self.instruction,
            "pc": self.pc,
            "opcode": self.opcode,
            "mnemonic": self.mnemonic,
            "architecture": self.architecture,
            "documented_cycles": self.documented_cycles,
            "state_before": self.state_before,
            "state_after": self.state_after,
            "effective_address": self.effective_address,
            "accesses": [access.__dict__ for access in self.accesses],
            "undefined_flags": self.undefined_flags,
        }


class Memory:
    """A deterministic 64 KiB byte-addressable memory image."""

    SIZE = 0x10000

    def __init__(self, initial: bytes | bytearray | None = None) -> None:
        self.data = bytearray(self.SIZE)
        if initial is not None:
            if len(initial) > self.SIZE:
                raise ValueError("initial memory image exceeds 64 KiB")
            self.data[: len(initial)] = initial

    def __getitem__(self, address: int) -> int:
        return self.data[address & 0xFFFF]

    def __setitem__(self, address: int, value: int) -> None:
        if not isinstance(value, int) or not 0 <= value <= 0xFF:
            raise ValueError("memory values must be eight-bit integers")
        self.data[address & 0xFFFF] = value

    def load(self, address: int, values: bytes | bytearray | list[int]) -> None:
        for offset, value in enumerate(values):
            self[address + offset] = value


def load_opcode_spec(architecture: str) -> dict:
    path = ROOT / "spec" / "opcodes" / f"{architecture}.json"
    try:
        spec = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"cannot load opcode specification {path}: {exc}") from exc
    if spec.get("architecture") != architecture or len(spec.get("opcodes", [])) != 256:
        raise RuntimeError(f"invalid opcode specification for {architecture}")
    return spec
