"""Independent HD63701V0 27256-style digital PROM-mode model.

Hitachi #U07 section 3.1, figure 3-2, figure 3-3, and table 3-1 define
the pin mapping, 4-KiB array, erased-value reads, and CE/OE/VPP states.
Programming voltage magnitude, pulse duration, and storage physics are outside
this model; a program state emits a request to an integration-owned array.
"""

from __future__ import annotations

from dataclasses import dataclass


DEFINED_STATES = frozenset(
    {"read", "output_disable", "program", "verify", "program_inhibit"}
)
PROM_ARRAY_BYTES = 0x1000
MCU_EPROM_BASE = 0xF000


@dataclass(frozen=True)
class HD63701V0PromInputs:
    prom_mode: bool
    program_voltage: bool
    ce_n: bool
    oe_n: bool
    port1: int
    port3: int
    port4_address: int
    irq_a9: bool
    program_data: int


@dataclass(frozen=True)
class HD63701V0PromCycle:
    state: str
    address: int
    internal_address: bool
    storage_address: int
    storage_read: bool
    data: int
    data_oe: bool
    program_data: int
    program_request: bool
    mcu_stopped: bool


def prom_address(*, port1: int, port4_address: int, irq_a9: bool) -> int:
    """Map the PROM-mode Port-1/Port-4/IRQ pins to A14:A0."""

    port1 &= 0xFF
    port4_address &= 0x3F
    return (
        ((port4_address >> 1) & 1) << 14
        | ((port4_address >> 2) & 0xF) << 10
        | int(irq_a9) << 9
        | (port4_address & 1) << 8
        | port1
    )


def prom_cycle(inputs: HD63701V0PromInputs) -> HD63701V0PromCycle:
    address = prom_address(
        port1=inputs.port1,
        port4_address=inputs.port4_address,
        irq_a9=inputs.irq_a9,
    )
    internal = address < PROM_ARRAY_BYTES
    storage_address = MCU_EPROM_BASE | (address & (PROM_ARRAY_BYTES - 1))

    if not inputs.prom_mode:
        state = "mcu"
    elif not inputs.program_voltage and not inputs.ce_n and not inputs.oe_n:
        state = "read"
    elif not inputs.program_voltage and not inputs.ce_n and inputs.oe_n:
        state = "output_disable"
    elif inputs.program_voltage and not inputs.ce_n and inputs.oe_n:
        state = "program"
    elif inputs.program_voltage and inputs.ce_n and not inputs.oe_n:
        state = "verify"
    elif inputs.program_voltage and inputs.ce_n and inputs.oe_n:
        state = "program_inhibit"
    else:
        state = "undefined_by_documentation"

    data_oe = state in {"read", "verify"}
    storage_read = data_oe and internal
    program_request = state == "program" and internal
    data = inputs.program_data & 0xFF if internal else 0xFF

    return HD63701V0PromCycle(
        state=state,
        address=address,
        internal_address=internal,
        storage_address=storage_address,
        storage_read=storage_read,
        data=data,
        data_oe=data_oe,
        program_data=inputs.port3 & 0xFF,
        program_request=program_request,
        mcu_stopped=inputs.prom_mode,
    )
