#!/usr/bin/env python3
"""Generate deterministic HD63705V0 peripheral model/RTL cycle vectors."""

from __future__ import annotations

import argparse
import random
from pathlib import Path

from model.hd63705v0_device import HD63705V0CycleInputs, HD63705V0DeviceModel


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "sim" / "generated" / "hd63705_peripheral_vectors_pkg.sv"
VECTOR_COUNT = 768
SEED = 0x63705000

FIELDS = (
    ("address", 16), ("valid", 1), ("write", 1), ("data", 8),
    ("program_data", 8), ("port_a", 8), ("port_b", 8), ("port_c", 8),
    ("port_d", 7), ("timer_pin", 1), ("int_n", 1), ("int2_n", 1),
    ("interrupt_mask", 1), ("waiting", 1), ("stopped", 1),
    ("read_data", 8), ("program_bus", 1), ("timer_irq", 1),
    ("sci_irq", 1), ("int_irq", 1), ("int2_irq", 1), ("irq_request", 1),
    ("irq_vector", 16), ("port_a_output", 8), ("port_a_oe", 8),
    ("port_b_output", 8), ("port_b_oe", 8), ("port_c_output", 8),
    ("port_c_oe", 8), ("port_d_output", 7), ("port_d_oe", 7),
    ("timer_data", 8), ("tcr", 8), ("mr", 8), ("scr", 8), ("ssr", 8),
    ("sdr", 8), ("sci_tx", 1), ("sci_clock", 1),
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
    model = HD63705V0DeviceModel()
    rows: list[int] = []

    def cycle(
        address: int = 0,
        *,
        valid: bool = False,
        write: bool = False,
        data: int = 0,
        port_a: int = 0x3C,
        port_b: int = 0x5A,
        port_c: int = 0xC3,
        port_d: int = 0x7F,
        timer_pin: bool = False,
        int_n: bool = True,
        int2_n: bool = True,
        interrupt_mask: bool = True,
        waiting: bool = False,
        stopped: bool = False,
    ) -> None:
        physical_address = address & 0x3FFF
        program_data = (physical_address ^ 0xA6) & 0xFF
        model.program_memory[physical_address] = program_data
        inputs = HD63705V0CycleInputs(
            address=address,
            valid=valid,
            write=write,
            data=data,
            port_a=port_a,
            port_b=port_b,
            port_c=port_c,
            port_d=port_d,
            timer=timer_pin,
            int_n=int_n,
            int2_n=int2_n,
            interrupt_mask=interrupt_mask,
            waiting=waiting,
            stopped=stopped,
        )
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
            "port_d": port_d,
            "timer_pin": timer_pin,
            "int_n": int_n,
            "int2_n": int2_n,
            "interrupt_mask": interrupt_mask,
            "waiting": waiting,
            "stopped": stopped,
            "read_data": result.read_data,
            "program_bus": result.program_bus,
            "timer_irq": result.timer_irq,
            "sci_irq": result.sci_irq,
            "int_irq": result.int_irq,
            "int2_irq": result.int2_irq,
            "irq_request": result.irq_request,
            "irq_vector": result.irq_vector,
            "port_a_output": outputs[0],
            "port_a_oe": outputs[1],
            "port_b_output": outputs[2],
            "port_b_oe": outputs[3],
            "port_c_output": outputs[4],
            "port_c_oe": outputs[5],
            "port_d_output": outputs[6],
            "port_d_oe": outputs[7],
            "timer_data": state.timer_data,
            "tcr": state.tcr,
            "mr": state.mr,
            "scr": state.scr,
            "ssr": state.ssr,
            "sdr": state.sci_data,
            "sci_tx": state.transmit_output,
            "sci_clock": state.sci_clock,
        }))

    def read(address: int, **values: int | bool) -> None:
        cycle(address, valid=True, **values)

    def write(address: int, data: int, **values: int | bool) -> None:
        cycle(address, valid=True, write=True, data=data, **values)

    # Directed prefix covers every register, both RAM edges, all timer source
    # classes, external request retention, serial edges, and STOP transitions.
    cycle()
    for address, data in ((0x00, 0xA5), (0x01, 0x5A), (0x02, 0xC3), (0x03, 0x69),
                          (0x04, 0xF0), (0x05, 0x0F), (0x06, 0xAA), (0x07, 0x55),
                          (0x40, 0x12), (0x41, 0x56), (0xFE, 0x78), (0xFF, 0x34)):
        write(address, data)
    for address in (*range(0x00, 0x13), 0x40, 0xFF, 0x1000, 0x1FFF, 0x2000):
        read(address)
    write(0x08, 0x02)
    write(0x09, 0x30)
    cycle(timer_pin=False)
    cycle(timer_pin=True)
    cycle(timer_pin=True)
    cycle(timer_pin=False)
    cycle(timer_pin=True, waiting=True, interrupt_mask=False)
    write(0x09, 0x48, timer_pin=True)
    for _ in range(4):
        cycle(timer_pin=True)
    write(0x0A, 0x00, int_n=True, int2_n=True)
    cycle(int_n=False, int2_n=False, interrupt_mask=False)
    read(0x1FFA, int_n=True, int2_n=True, interrupt_mask=False)
    write(0x0A, 0x00, interrupt_mask=False)
    write(0x10, 0xF0, port_d=0x7F)
    write(0x11, 0x30, port_d=0x7F)
    write(0x12, 0xA5, port_d=0x7F)
    for bit in range(8):
        receive = (0x3C >> bit) & 1
        cycle(port_d=0x0F | (receive << 4))
        cycle(port_d=0x2F | (receive << 4))
    read(0x12, port_d=0x7F)
    cycle(stopped=True)
    cycle(stopped=True)
    cycle(stopped=True, int_n=False, interrupt_mask=False)
    cycle(stopped=False, int_n=True)

    rng = random.Random(SEED)
    addresses = [
        *range(0x00, 0x13), 0x13, 0x3F, 0x40, 0x41, 0xFE, 0xFF,
        0x0100, 0x0FFF, 0x1000, 0x1234, 0x1FF4, 0x1FFA, 0x1FFF,
        0x2000, 0x3FFF, 0x7FFF, 0xFFFF,
    ]
    stopped = False
    while len(rows) < VECTOR_COUNT:
        if rng.random() < 0.025:
            stopped = not stopped
        valid = rng.random() < 0.72
        address = rng.choice(addresses)
        write_enable = valid and rng.random() < 0.43
        if (address & 0x3FFF) >= 0x1000:
            write_enable = False
        cycle(
            address,
            valid=valid,
            write=write_enable,
            data=rng.randrange(256),
            port_a=rng.randrange(256),
            port_b=rng.randrange(256),
            port_c=rng.randrange(256),
            port_d=rng.randrange(128),
            timer_pin=rng.random() < 0.5,
            int_n=rng.random() >= 0.04,
            int2_n=rng.random() >= 0.04,
            interrupt_mask=rng.random() < 0.35,
            waiting=not stopped and rng.random() < 0.06,
            stopped=stopped,
        )
    return rows


def render() -> str:
    rows = build_vectors()
    hex_digits = (VECTOR_WIDTH + 3) // 4
    lines = [
        "// SPDX-License-Identifier: MIT",
        "// Generated by tools/build_hd63705_peripheral_vectors.py; do not edit.",
        "package hd63705_peripheral_vectors_pkg;",
        f"  localparam int unsigned HD63705_PERIPHERAL_VECTOR_COUNT = {VECTOR_COUNT};",
        "  typedef struct packed {",
    ]
    for name, width in FIELDS:
        suffix = "" if width == 1 else f" [{width - 1}:0]"
        lines.append(f"    logic{suffix} {name};")
    lines.extend([
        "  } hd63705_peripheral_vector_t;",
        "",
        "  function automatic hd63705_peripheral_vector_t hd63705_peripheral_vector(",
        "    input logic [9:0] cycle_index",
        "  );",
        "    begin",
        "      hd63705_peripheral_vector = '0;",
        "      case (cycle_index)",
        f"        // Seed {SEED:08x}.",
    ])
    for index, value in enumerate(rows):
        lines.append(
            f"        10'h{index:03x}: hd63705_peripheral_vector = "
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
