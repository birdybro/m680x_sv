#!/usr/bin/env python3
"""Generate deterministic MC6801/MC6803 peripheral model/RTL cycle vectors."""

from __future__ import annotations

import argparse
import random
from pathlib import Path

from model.mc6801_device import MC6801CycleInputs, MC6801DeviceModel


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "sim" / "generated" / "mc6801_peripheral_vectors_pkg.sv"
CYCLES_PER_MODE = 768
SEEDS = {2: 0x68030002, 3: 0x68030003}

FIELDS = (
    ("address", 16),
    ("valid", 1),
    ("write", 1),
    ("data", 8),
    ("external_data", 8),
    ("port1", 8),
    ("port2", 5),
    ("irq1_n", 1),
    ("interrupt_mask", 1),
    ("standby_power_ok", 1),
    ("read_data", 8),
    ("external_bus", 1),
    ("timer_irq", 1),
    ("sci_irq", 1),
    ("irq_request", 1),
    ("irq_vector", 16),
    ("timer", 16),
    ("output_compare", 16),
    ("input_capture", 16),
    ("tcsr", 8),
    ("trcsr", 8),
    ("receive_data", 8),
    ("port1_output", 8),
    ("port1_oe", 8),
    ("port2_output", 5),
    ("port2_oe", 5),
    ("sci_tx", 1),
    ("sci_clock", 1),
    ("irq1_pending", 1),
    ("irq2_pending", 1),
    ("rame", 1),
    ("standby_power", 1),
)
VECTOR_WIDTH = sum(width for _name, width in FIELDS)


def pack(values: dict[str, int | bool]) -> int:
    packed = 0
    for name, width in FIELDS:
        value = int(values[name])
        if not 0 <= value < 1 << width:
            raise ValueError(f"{name}={value} does not fit in {width} bits")
        packed = (packed << width) | value
    return packed


def build_mode(mode: int) -> list[int]:
    model = MC6801DeviceModel(mode)
    rows: list[int] = []

    def cycle(
        address: int = 0,
        *,
        valid: bool = False,
        write: bool = False,
        data: int = 0,
        port1: int = 0x3C,
        port2: int = 0x1F,
        irq1_n: bool = True,
        interrupt_mask: bool = True,
        standby_power_ok: bool = True,
    ) -> None:
        external_data = model.external_memory[address]
        inputs = MC6801CycleInputs(
            address=address,
            valid=valid,
            write=write,
            data=data,
            port1=port1,
            port2=port2,
            irq1_n=irq1_n,
            interrupt_mask=interrupt_mask,
            standby_power_ok=standby_power_ok,
        )
        result = model.cycle(inputs)
        port1_output, port1_oe, port2_output, port2_oe = model.port_outputs()
        state = model.state
        sci_divisor = (16, 128, 1024, 4096)[state.rmcr & 0x03]
        rows.append(pack({
            "address": address & 0xFFFF,
            "valid": valid,
            "write": write,
            "data": data,
            "external_data": external_data,
            "port1": port1,
            "port2": port2,
            "irq1_n": irq1_n,
            "interrupt_mask": interrupt_mask,
            "standby_power_ok": standby_power_ok,
            "read_data": result.read_data,
            "external_bus": result.external_bus,
            "timer_irq": result.timer_irq,
            "sci_irq": result.sci_irq,
            "irq_request": result.irq_request,
            "irq_vector": result.irq_vector,
            "timer": state.timer,
            "output_compare": state.output_compare,
            "input_capture": state.input_capture,
            "tcsr": state.tcsr,
            "trcsr": state.trcsr,
            "receive_data": state.receive_data,
            "port1_output": port1_output,
            "port1_oe": port1_oe,
            "port2_output": port2_output,
            "port2_oe": port2_oe,
            "sci_tx": state.sci_tx,
            "sci_clock": bool(state.timer & (sci_divisor >> 1)),
            "irq1_pending": state.irq1_pending,
            "irq2_pending": state.irq2_pending,
            "rame": state.rame,
            "standby_power": state.standby_power,
        }))

    def read(address: int, **kwargs: int | bool) -> None:
        cycle(address, valid=True, **kwargs)

    def write(address: int, data: int, **kwargs: int | bool) -> None:
        cycle(address, valid=True, write=True, data=data, **kwargs)

    # Directed prefix: decode, GPIO, timer flags/clears/capture, interrupt
    # retention, and an internally-clocked NRZ transmit/receive transaction.
    cycle()
    write(0x0002, 0xA5)
    write(0x0000, 0xF0)
    read(0x0002, port1=0x3C)
    read(0x0000)
    write(0x0080, 0x5A)
    read(0x0080)
    write(0x0004, 0x77)
    read(0x0004)
    write(0x000B, 0xFF)
    write(0x000C, 0xFC)
    write(0x0008, 0x1D)
    write(0x0009, 0x00)
    for _ in range(10):
        cycle(interrupt_mask=False)
    read(0x0008, interrupt_mask=False)
    write(0x000C, 0x40, interrupt_mask=False)
    read(0x0009, interrupt_mask=False)
    cycle(port2=0x1F, interrupt_mask=False)
    cycle(port2=0x1F, interrupt_mask=False)
    cycle(port2=0x1E, interrupt_mask=False)
    cycle(port2=0x1E, interrupt_mask=False)
    read(0x0008, interrupt_mask=False)
    read(0x000D, interrupt_mask=False)
    cycle(irq1_n=False, interrupt_mask=False)
    cycle(interrupt_mask=True)
    write(0x0010, 0x04)
    read(0x0011)
    write(0x0013, 0xA6)
    write(0x0011, 0x0A)
    for _ in range(16 * 11):
        cycle(port2=0x08, interrupt_mask=False)
    for level in [0, *(0x3C >> bit & 1 for bit in range(8)), 1]:
        for _ in range(16):
            cycle(port2=level << 3, interrupt_mask=False)
    read(0x0011, interrupt_mask=False)
    read(0x0012, interrupt_mask=False)

    rng = random.Random(SEEDS[mode])
    addresses = [
        0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0008, 0x000A,
        0x000B, 0x000C, 0x000D, 0x000E, 0x0010, 0x0011, 0x0012,
        0x0013, 0x0014, 0x0080, 0x0200, 0xFFFF,
    ]
    while len(rows) < CYCLES_PER_MODE:
        valid = rng.random() < 0.72
        address = rng.choice(addresses)
        write_enable = valid and rng.random() < 0.43
        # Avoid repeated FRC presets in the random tail because the manual
        # warns that they perturb an internally clocked SCI stream.
        if address in {0x000A, 0x000D, 0x000E, 0x0012}:
            write_enable = False
        cycle(
            address,
            valid=valid,
            write=write_enable,
            data=rng.randrange(256),
            port1=rng.randrange(256),
            port2=rng.randrange(32),
            irq1_n=rng.random() >= 0.04,
            interrupt_mask=rng.random() < 0.35,
            standby_power_ok=rng.random() >= 0.02,
        )
    return rows


def render() -> str:
    rows = {mode: build_mode(mode) for mode in (2, 3)}
    hex_digits = (VECTOR_WIDTH + 3) // 4
    lines = [
        "// SPDX-License-Identifier: MIT",
        "// Generated by tools/build_mc6801_peripheral_vectors.py; do not edit.",
        "package mc6801_peripheral_vectors_pkg;",
        f"  localparam int unsigned MC6801_PERIPHERAL_VECTOR_COUNT = {CYCLES_PER_MODE};",
        "  typedef struct packed {",
    ]
    for name, width in FIELDS:
        suffix = "" if width == 1 else f" [{width - 1}:0]"
        lines.append(f"    logic{suffix} {name};")
    lines.extend([
        "  } mc6801_peripheral_vector_t;",
        "",
        "  function automatic mc6801_peripheral_vector_t mc6801_peripheral_vector(",
        "    input logic [2:0] mode, input logic [9:0] cycle_index",
        "  );",
        "    begin",
        "      mc6801_peripheral_vector = '0;",
        "      case ({mode, cycle_index})",
    ])
    for mode, mode_rows in rows.items():
        lines.append(f"        // Mode {mode}, seed {SEEDS[mode]:08x}.")
        for index, value in enumerate(mode_rows):
            key = (mode << 10) | index
            lines.append(
                f"        13'h{key:04x}: mc6801_peripheral_vector = "
                f"{VECTOR_WIDTH}'h{value:0{hex_digits}x};"
            )
    lines.extend([
        "        default: ;",
        "      endcase",
        "    end",
        "  endfunction",
        "endpackage",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    generated = render()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != generated:
            raise SystemExit(f"stale peripheral vectors: run {Path(__file__).name}")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(generated, encoding="utf-8")
        print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
