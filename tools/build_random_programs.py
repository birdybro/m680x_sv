#!/usr/bin/env python3
"""Generate deterministic stateful model/RTL differential programs."""

from __future__ import annotations

import argparse
import random
from pathlib import Path

from model.common import Memory
from model.m6800 import M6800Model
from model.m6805 import M6805Model


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "sim" / "generated" / "random_programs_pkg.sv"
PROGRAM_COUNT = 16
INSTRUCTIONS_PER_PROGRAM = 64
START_PC = 0x1000
ARCHITECTURES = ("m6800", "m6801", "hd6301", "m6805", "hd6305")
SEED_BASES = {name: 0x68000000 + index * 0x10000 for index, name in enumerate(ARCHITECTURES)}

M6800_EXCLUDED = {
    "BRA", "BRN", "BHI", "BLS", "BCC", "BCS", "BNE", "BEQ", "BVC", "BVS",
    "BPL", "BMI", "BGE", "BLT", "BGT", "BLE", "BSR", "JMP", "JSR", "RTS",
    "RTI", "SWI", "WAI", "SLP", "PSHA", "PSHB", "PULA", "PULB", "PSHX", "PULX", "DAA",
}
M6805_EXCLUDED = {
    "BRA", "BRN", "BHI", "BLS", "BCC", "BCS", "BNE", "BEQ", "BHCC", "BHCS",
    "BPL", "BMI", "BMC", "BMS", "BIL", "BIH", "BSR", "JMP", "JSR", "RTS",
    "RTI", "SWI", "WAIT", "STOP", "DAA",
}


def candidates(model: M6800Model | M6805Model, m6805_lineage: bool) -> list[dict]:
    allowed_modes = {"inherent", "accumulator-a", "accumulator-b", "index-register-x", "immediate-8", "immediate-16"}
    excluded = M6805_EXCLUDED if m6805_lineage else M6800_EXCLUDED
    return [
        record for record in model.spec["opcodes"]
        if record["classification"] == "documented_instruction"
        and record["addressing_mode"] in allowed_modes
        and record["mnemonic"] not in excluded
    ]


def build_program(architecture: str, program_index: int) -> tuple[int, list[int], list[dict]]:
    seed = SEED_BASES[architecture] + program_index
    rng = random.Random(seed)
    memory = Memory()
    memory.load(0xFFFE, [0x10, 0x00])
    if architecture in {"m6800", "m6801", "hd6301"}:
        model: M6800Model | M6805Model = M6800Model(architecture, memory=memory)
        m6805_lineage = False
    else:
        model = M6805Model(architecture, memory=memory)
        m6805_lineage = True
    model.reset()
    choices = candidates(model, m6805_lineage)
    program: list[int] = []
    expected: list[dict] = []
    for _instruction_index in range(INSTRUCTIONS_PER_PROGRAM):
        record = rng.choice(choices)
        encoded = [record["opcode"]]
        encoded.extend(rng.randrange(256) for _ in range(record["length"] - 1))
        memory.load(model.state.pc, encoded)
        program.extend(encoded)
        trace = model.step()
        expected.append({"cycles": record["cycles"], **trace.state_after})
    return seed, program, expected


def emit_program_bytes(lines: list[str], architecture: str, programs: list[tuple]) -> None:
    lines.extend([
        f"  function automatic logic [7:0] {architecture}_program_byte(",
        "    input logic [7:0] program_index, input logic [7:0] byte_index", "  );",
        "    begin", f"      {architecture}_program_byte = 8'h00;",
        "      case ({program_index, byte_index})",
    ])
    for program_index, (_seed, program, _expected) in enumerate(programs):
        for byte_index, value in enumerate(program):
            lines.append(f"        16'h{program_index:02x}{byte_index:02x}: {architecture}_program_byte = 8'h{value:02x};")
    lines.extend(["        default: ;", "      endcase", "    end", "  endfunction", ""])


def emit_expectations(lines: list[str], architecture: str, programs: list[tuple], m6805: bool) -> None:
    type_name = "random_m6805_state_t" if m6805 else "random_m6800_state_t"
    lines.extend([
        f"  function automatic {type_name} {architecture}_expected(",
        "    input logic [7:0] program_index, input logic [7:0] instruction_index", "  );",
        "    begin", f"      {architecture}_expected = '0;",
        "      case ({program_index, instruction_index})",
    ])
    for program_index, (_seed, _program, expected) in enumerate(programs):
        for instruction_index, state in enumerate(expected):
            key = f"16'h{program_index:02x}{instruction_index:02x}"
            lines.append(f"        {key}: begin")
            prefix = f"          {architecture}_expected"
            lines.append(f"{prefix}.cycles = 4'd{state['cycles']};")
            lines.append(f"{prefix}.a = 8'h{state['A']:02x};")
            if m6805:
                lines.append(f"{prefix}.x = 8'h{state['X']:02x};")
                lines.append(f"{prefix}.ccr = 5'h{state['CCR']:02x};")
            else:
                lines.append(f"{prefix}.b = 8'h{state['B']:02x};")
                lines.append(f"{prefix}.x = 16'h{state['X']:04x};")
                lines.append(f"{prefix}.ccr = 6'h{state['CCR']:02x};")
            lines.append(f"{prefix}.sp = 16'h{state['SP']:04x};")
            lines.append(f"{prefix}.pc = 16'h{state['PC']:04x};")
            lines.append("        end")
    lines.extend(["        default: ;", "      endcase", "    end", "  endfunction", ""])


def render() -> str:
    programs = {
        architecture: [build_program(architecture, index) for index in range(PROGRAM_COUNT)]
        for architecture in ARCHITECTURES
    }
    lines = [
        "// SPDX-License-Identifier: MIT",
        "// Generated by tools/build_random_programs.py; do not edit by hand.",
        "package random_programs_pkg;",
        f"  localparam int unsigned RANDOM_PROGRAM_COUNT = {PROGRAM_COUNT};",
        f"  localparam int unsigned RANDOM_INSTRUCTIONS_PER_PROGRAM = {INSTRUCTIONS_PER_PROGRAM};",
        f"  localparam int unsigned RANDOM_MAX_PROGRAM_BYTES = {max(len(item[1]) for items in programs.values() for item in items)};",
        "  typedef struct packed {",
        "    logic [3:0] cycles; logic [7:0] a; logic [7:0] b; logic [15:0] x;",
        "    logic [15:0] sp; logic [15:0] pc; logic [5:0] ccr;",
        "  } random_m6800_state_t;",
        "  typedef struct packed {",
        "    logic [3:0] cycles; logic [7:0] a; logic [7:0] x;",
        "    logic [15:0] sp; logic [15:0] pc; logic [4:0] ccr;",
        "  } random_m6805_state_t;",
        "",
    ]
    for architecture, items in programs.items():
        lines.append(f"  // Seeds {items[0][0]:08x} through {items[-1][0]:08x}.")
        emit_program_bytes(lines, architecture, items)
        emit_expectations(lines, architecture, items, architecture in {"m6805", "hd6305"})
    lines.extend(["endpackage", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    generated = render()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != generated:
            raise SystemExit(f"stale random programs: run {Path(__file__).name}")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(generated, encoding="utf-8")
        print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
