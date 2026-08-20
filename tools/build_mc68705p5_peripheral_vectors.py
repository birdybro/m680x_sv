#!/usr/bin/env python3
"""Generate deterministic MC68705P5 peripheral model/RTL cycle vectors."""

from __future__ import annotations

import argparse
import random
from pathlib import Path

from model.mc68705p5_device import MC68705P5CycleInputs, MC68705P5DeviceModel


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "sim" / "generated" / "mc68705p5_peripheral_vectors_pkg.sv"
VECTOR_COUNT = 768
SEED = 0x68705A05

FIELDS = (
    ("address", 16), ("valid", 1), ("write", 1), ("data", 8),
    ("program_data", 8), ("port_a", 8), ("port_b", 8), ("port_c", 4),
    ("timer_pin", 1), ("int_n", 1), ("interrupt_mask", 1),
    ("vpp_present", 1), ("bootstrap_voltage", 1), ("read_data", 8),
    ("program_address", 11), ("program_read", 1), ("timer_irq", 1),
    ("external_irq", 1), ("irq_request", 1), ("irq_vector", 16),
    ("bootstrap_mode", 1),
    ("port_a_output", 8), ("port_a_oe", 8), ("port_b_output", 8),
    ("port_b_oe", 8), ("port_c_output", 4), ("port_c_oe", 4),
    ("timer_data", 8), ("tcr", 8), ("pcr", 8),
    ("eprom_latch_enable", 1), ("eprom_program_enable", 1),
    ("eprom_program_address", 11), ("eprom_program_data", 8),
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


def build_vectors() -> list[int]:
    model = MC68705P5DeviceModel()
    rows: list[int] = []

    def cycle(
        address: int = 0,
        *,
        valid: bool = False,
        write: bool = False,
        data: int = 0,
        port_a: int = 0x3C,
        port_b: int = 0x5A,
        port_c: int = 0x09,
        timer_pin: bool = False,
        int_n: bool = True,
        interrupt_mask: bool = True,
        vpp_present: bool = False,
        bootstrap_voltage: bool = False,
    ) -> None:
        inputs = MC68705P5CycleInputs(
            address=address,
            valid=valid,
            write=write,
            data=data,
            port_a=port_a,
            port_b=port_b,
            port_c=port_c,
            timer=timer_pin,
            int_n=int_n,
            interrupt_mask=interrupt_mask,
            vpp_present=vpp_present,
            bootstrap_voltage=bootstrap_voltage,
        )
        selected_address = model.selected_program_address(inputs)
        program_data = (selected_address ^ 0xA6) & 0xFF
        model.program_memory[selected_address] = program_data
        result = model.cycle(inputs)
        outputs = model.port_outputs()
        state = model.state
        rows.append(pack({
            "address": address & 0xFFFF,
            "valid": valid,
            "write": write,
            "data": data,
            "program_data": program_data,
            "port_a": port_a,
            "port_b": port_b,
            "port_c": port_c,
            "timer_pin": timer_pin,
            "int_n": int_n,
            "interrupt_mask": interrupt_mask,
            "vpp_present": vpp_present,
            "bootstrap_voltage": bootstrap_voltage,
            "read_data": result.read_data,
            "program_address": result.program_address,
            "program_read": result.program_read,
            "timer_irq": result.timer_irq,
            "external_irq": result.external_irq,
            "irq_request": result.irq_request,
            "irq_vector": result.irq_vector,
            "bootstrap_mode": result.bootstrap_mode,
            "port_a_output": outputs[0],
            "port_a_oe": outputs[1],
            "port_b_output": outputs[2],
            "port_b_oe": outputs[3],
            "port_c_output": outputs[4],
            "port_c_oe": outputs[5],
            "timer_data": state.timer_data,
            "tcr": state.tcr(model.mask_option),
            "pcr": state.pcr(vpp_present),
            "eprom_latch_enable": result.eprom_latch_enable,
            "eprom_program_enable": result.eprom_program_enable,
            "eprom_program_address": state.eprom_address_latch,
            "eprom_program_data": state.eprom_data_latch,
        }))

    def read(address: int, **values: int | bool) -> None:
        cycle(address, valid=True, **values)

    def write(address: int, data: int, **values: int | bool) -> None:
        cycle(address, valid=True, write=True, data=data, **values)

    # Directed prefix covers registers, both RAM edges, all four timer source
    # modes, external interrupt acknowledgement, bootstrap selection, and PCR.
    cycle()
    read(0x7FE, bootstrap_voltage=True)
    read(0x7FF, bootstrap_voltage=False)
    for address, data in (
        (0x000, 0xA5), (0x001, 0x5A), (0x002, 0x09),
        (0x004, 0xF0), (0x005, 0x0F), (0x006, 0x05),
        (0x010, 0x12), (0x011, 0x56), (0x07E, 0x78), (0x07F, 0x34),
    ):
        write(address, data)
    for address in (*range(0x000, 0x010), 0x010, 0x07F, 0x080, 0x783,
                    0x784, 0x785, 0x7F6, 0x7F8, 0x7FA, 0x7FE, 0x7FF):
        read(address)
    write(0x009, 0x00)
    write(0x008, 0x02)
    cycle()
    cycle()
    write(0x009, 0x50, timer_pin=False)
    write(0x008, 0x02, timer_pin=False)
    cycle(timer_pin=False)
    cycle(timer_pin=True)
    write(0x009, 0x60, timer_pin=True)
    cycle(timer_pin=True)
    write(0x009, 0x70, timer_pin=True)
    cycle(timer_pin=False)
    cycle(timer_pin=True)
    write(0x009, 0x09, timer_pin=False)
    for _ in range(4):
        cycle(timer_pin=False)
    cycle(int_n=False, interrupt_mask=False)
    read(0x7FA, int_n=False, interrupt_mask=False)
    cycle(int_n=True, interrupt_mask=False)
    read(0x7FE, bootstrap_voltage=True)
    read(0x7FF, bootstrap_voltage=True)
    write(0x00B, 0x02, vpp_present=True, bootstrap_voltage=True)
    write(0x080, 0xC3, vpp_present=True, bootstrap_voltage=True)
    read(0x080, vpp_present=True, bootstrap_voltage=True)
    write(0x00B, 0x00, vpp_present=True, bootstrap_voltage=True)
    cycle(vpp_present=True, bootstrap_voltage=True)
    write(0x00B, 0x03, vpp_present=True, bootstrap_voltage=True)

    rng = random.Random(SEED)
    addresses = [
        *range(0x000, 0x010), 0x010, 0x011, 0x07E, 0x07F,
        0x080, 0x100, 0x783, 0x784, 0x785, 0x7F6, 0x7F7,
        0x7F8, 0x7FA, 0x7FE, 0x7FF, 0x0800, 0xFFFF,
    ]
    while len(rows) < VECTOR_COUNT:
        valid = rng.random() < 0.74
        address = rng.choice(addresses)
        write_enable = valid and rng.random() < 0.43
        cycle(
            address,
            valid=valid,
            write=write_enable,
            data=rng.randrange(256),
            port_a=rng.randrange(256),
            port_b=rng.randrange(256),
            port_c=rng.randrange(16),
            timer_pin=rng.random() < 0.5,
            int_n=rng.random() >= 0.04,
            interrupt_mask=rng.random() < 0.35,
            vpp_present=rng.random() < 0.28,
            bootstrap_voltage=rng.random() < 0.18,
        )
    return rows


def render() -> str:
    rows = build_vectors()
    hex_digits = (VECTOR_WIDTH + 3) // 4
    lines = [
        "// SPDX-License-Identifier: MIT",
        "// Generated by tools/build_mc68705p5_peripheral_vectors.py; do not edit.",
        "package mc68705p5_peripheral_vectors_pkg;",
        f"  localparam int unsigned MC68705P5_PERIPHERAL_VECTOR_COUNT = {VECTOR_COUNT};",
        "  typedef struct packed {",
    ]
    for name, width in FIELDS:
        suffix = "" if width == 1 else f" [{width - 1}:0]"
        lines.append(f"    logic{suffix} {name};")
    lines.extend([
        "  } mc68705p5_peripheral_vector_t;",
        "",
        "  function automatic mc68705p5_peripheral_vector_t mc68705p5_peripheral_vector(",
        "    input logic [9:0] cycle_index",
        "  );",
        "    begin",
        "      mc68705p5_peripheral_vector = '0;",
        "      case (cycle_index)",
        f"        // Seed {SEED:08x}.",
    ])
    for index, value in enumerate(rows):
        lines.append(
            f"        10'h{index:03x}: mc68705p5_peripheral_vector = "
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
