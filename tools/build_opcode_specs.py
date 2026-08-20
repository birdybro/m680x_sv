#!/usr/bin/env python3
"""Build expanded opcode records from primary-manual factual tables."""

from __future__ import annotations

import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "spec" / "opcodes"
ALL_FLAGS = ["H", "I", "N", "Z", "V", "C"]


BRANCHES = {
    0x20: ("BRA", "always"),
    0x22: ("BHI", "C=0 and Z=0"),
    0x23: ("BLS", "C=1 or Z=1"),
    0x24: ("BCC", "C=0"),
    0x25: ("BCS", "C=1"),
    0x26: ("BNE", "Z=0"),
    0x27: ("BEQ", "Z=1"),
    0x28: ("BVC", "V=0"),
    0x29: ("BVS", "V=1"),
    0x2A: ("BPL", "N=0"),
    0x2B: ("BMI", "N=1"),
    0x2C: ("BGE", "N xor V=0"),
    0x2D: ("BLT", "N xor V=1"),
    0x2E: ("BGT", "Z=0 and (N xor V)=0"),
    0x2F: ("BLE", "Z=1 or (N xor V)=1"),
}


RMW_ROWS = {
    0x0: "NEG",
    0x3: "COM",
    0x4: "LSR",
    0x6: "ROR",
    0x7: "ASR",
    0x8: "ASL",
    0x9: "ROL",
    0xA: "DEC",
    0xC: "INC",
    0xD: "TST",
    0xF: "CLR",
}


AB_ROWS = {
    0x0: "SUB",
    0x1: "CMP",
    0x2: "SBC",
    0x4: "AND",
    0x5: "BIT",
    0x6: "LDA",
    0x7: "STA",
    0x8: "EOR",
    0x9: "ADC",
    0xA: "ORA",
    0xB: "ADD",
}


def _dedupe(items: list[str]) -> list[str]:
    return list(dict.fromkeys(items))


def _undefined(opcode: int, architecture: str, reference_id: str, locator: str) -> dict:
    return {
        "opcode": opcode,
        "opcode_hex": f"{opcode:02X}",
        "classification": "undefined_behavior",
        "mnemonic": None,
        "aliases": [],
        "architectural_applicability": [architecture],
        "addressing_mode": None,
        "length": None,
        "cycles": None,
        "conditional_cycles": [],
        "registers_read": [],
        "registers_written": [],
        "flags_read": [],
        "flags_affected": [],
        "flags_undefined": [],
        "flag_semantics": {},
        "memory_operations": [],
        "stack_effects": [],
        "branch_behavior": None,
        "vector_behavior": None,
        "primary_reference": {"id": reference_id, "locator": locator},
        "notes": "No architectural behavior is assigned by the cited manufacturer instruction set.",
    }


def _opcode_trap(opcode: int, architecture: str, reference_id: str) -> dict:
    return {
        "opcode": opcode,
        "opcode_hex": f"{opcode:02X}",
        "classification": "documented_special_behavior",
        "mnemonic": "TRAP",
        "aliases": [],
        "architectural_applicability": [architecture],
        "addressing_mode": "trap-on-fetch",
        "length": 1,
        "cycles": 13,
        "conditional_cycles": [],
        "registers_read": ["PC", "SP", "X", "A", "B", "CCR"],
        "registers_written": ["PC", "SP", "CCR"],
        "flags_read": [],
        "flags_affected": ["I"],
        "flags_undefined": [],
        "flag_semantics": {"I": "set after the pre-trap CCR value is stacked"},
        "memory_operations": [
            "read undefined opcode at PC",
            "read discarded byte at opcode address plus one",
            "read FFFF during trap entry",
            "read FFFF during the trap-only additional cycle",
            "write seven-byte complete processor state to stack",
            "read trap vector at FFEE:FFEF",
        ],
        "stack_effects": [
            "push retry PC low, retry PC high, X low, X high, A, B, then pre-trap CCR",
        ],
        "branch_behavior": None,
        "vector_behavior": "unmaskable trap through FFEE:FFEF; RTI retries the undefined opcode",
        "primary_reference": {
            "id": reference_id,
            "locator": "HD6301V1 section 2.13 printed page 167; Q&A III.5.2 figure III-8 printed pages 500-501",
        },
        "notes": "Every operation-code-map cell left undefined invokes the documented opcode-error TRAP.",
    }


def _operation_root(mnemonic: str) -> str:
    roots = (
        "SUBD",
        "ADDD",
        "LSRD",
        "ASLD",
        "SUB",
        "CMP",
        "SBC",
        "AND",
        "BIT",
        "LDA",
        "STA",
        "EOR",
        "ADC",
        "ORA",
        "ADD",
        "NEG",
        "COM",
        "LSR",
        "ROR",
        "ASR",
        "ASL",
        "ROL",
        "DEC",
        "INC",
        "TST",
        "CLR",
    )
    for root in roots:
        if mnemonic.startswith(root):
            return root
    return mnemonic


def _flag_facts(mnemonic: str, architecture: str) -> tuple[list[str], list[str], list[str], dict[str, str]]:
    root = _operation_root(mnemonic)
    read: list[str] = []
    affected: list[str] = []
    undefined: list[str] = []
    semantics: dict[str, str] = {}

    if root in {"ADD", "ADC"} or mnemonic == "ABA":
        affected = ["H", "N", "Z", "V", "C"]
        semantics = {
            "H": "carry from result bit 3 into bit 4",
            "N": "most-significant result bit",
            "Z": "1 exactly when the result is zero",
            "V": "two's-complement addition overflow",
            "C": "carry out of the most-significant result bit",
        }
        if root == "ADC":
            read = ["C"]
    elif root in {"SUB", "CMP", "SBC"} or mnemonic in {"SBA", "CBA"}:
        affected = ["N", "Z", "V", "C"]
        semantics = {
            "N": "most-significant result bit",
            "Z": "1 exactly when the subtraction result is zero",
            "V": "two's-complement subtraction overflow",
            "C": "borrow from the most-significant result bit",
        }
        if root == "SBC":
            read = ["C"]
    elif root in {"SUBD", "ADDD"}:
        affected = ["N", "Z", "V", "C"]
        semantics = {
            "N": "result bit 15",
            "Z": "1 exactly when the 16-bit result is zero",
            "V": "16-bit two's-complement overflow",
            "C": "16-bit carry or borrow",
        }
    elif mnemonic == "CPX":
        affected = ["N", "Z", "V"] + (["C"] if architecture in {"m6801", "hd6301"} else [])
        semantics = {
            "N": "most-significant bit of the 16-bit comparison result",
            "Z": "1 exactly when X equals the 16-bit operand",
            "V": "two's-complement overflow from the high-byte comparison",
        }
        if architecture in {"m6801", "hd6301"}:
            semantics["C"] = "borrow from the 16-bit comparison"
    elif mnemonic in {"AIM", "OIM", "EIM", "TIM"}:
        affected = ["N", "Z", "V"]
        semantics = {
            "N": "most-significant bit of the logical result",
            "Z": "1 exactly when the logical result is zero",
            "V": "cleared",
        }
    elif root in {"AND", "BIT", "LDA", "STA", "EOR", "ORA"} or mnemonic in {
        "LDX",
        "STX",
        "LDS",
        "STS",
        "TAB",
        "TBA",
    }:
        affected = ["N", "Z", "V"]
        semantics = {
            "N": "most-significant result bit",
            "Z": "1 exactly when the result is zero",
            "V": "cleared",
        }
    elif mnemonic in {"LDD", "STD"}:
        affected = ["N", "Z", "V"]
        semantics = {"N": "result bit 15", "Z": "1 exactly when D is zero", "V": "cleared"}
    elif root == "NEG":
        affected = ["N", "Z", "V", "C"]
        semantics = {
            "N": "result bit 7",
            "Z": "1 exactly when the result is zero",
            "V": "1 exactly when the original operand is 80 hex",
            "C": "1 exactly when the original operand is nonzero",
        }
    elif root == "COM":
        affected = ["N", "Z", "V", "C"]
        semantics = {"N": "result bit 7", "Z": "1 exactly when the result is zero", "V": "cleared", "C": "set"}
    elif root in {"ASL", "ROL", "ROR", "ASR", "LSR"} or mnemonic in {"ASLD", "LSRD"}:
        affected = ["N", "Z", "V", "C"]
        width = "16-bit" if mnemonic in {"ASLD", "LSRD"} else "8-bit"
        semantics = {
            "N": "most-significant result bit",
            "Z": f"1 exactly when the {width} result is zero",
            "V": "N xor C after the shift",
            "C": "bit shifted out of the operand",
        }
        if root in {"ROL", "ROR"}:
            read = ["C"]
        if root in {"LSR", "LSRD"}:
            semantics["N"] = "cleared"
    elif root in {"INC", "DEC"}:
        affected = ["N", "Z", "V"]
        boundary = "7F hex" if root == "INC" else "80 hex"
        semantics = {
            "N": "result bit 7",
            "Z": "1 exactly when the result is zero",
            "V": f"1 exactly when the original operand is {boundary}",
        }
    elif root == "TST":
        affected = ["N", "Z", "V", "C"]
        semantics = {"N": "operand bit 7", "Z": "1 exactly when the operand is zero", "V": "cleared", "C": "cleared"}
    elif root == "CLR":
        affected = ["N", "Z", "V", "C"]
        semantics = {"N": "cleared", "Z": "set", "V": "cleared", "C": "cleared"}
    elif mnemonic in {"INX", "DEX"}:
        affected = ["Z"]
        semantics = {"Z": "1 exactly when the 16-bit result is zero"}
    elif mnemonic == "DAA":
        read = ["H", "C"]
        affected = ["N", "Z", "C"]
        undefined = ["V"]
        semantics = {
            "N": "adjusted result bit 7",
            "Z": "1 exactly when the adjusted result is zero",
            "C": "decimal carry selected by the manufacturer adjustment table",
            "V": "undefined by the manufacturer manual",
        }
    elif mnemonic == "MUL":
        affected = ["C"]
        semantics = {"C": "product bit 7 (bit 7 of accumulator B after multiplication)"}
    elif mnemonic in {"CLC", "SEC", "CLI", "SEI", "CLV", "SEV"}:
        flag = {"CLC": "C", "SEC": "C", "CLI": "I", "SEI": "I", "CLV": "V", "SEV": "V"}[mnemonic]
        affected = [flag]
        semantics = {flag: "set" if mnemonic.startswith("SE") else "cleared"}
    elif mnemonic == "TAP":
        affected = ALL_FLAGS.copy()
        semantics = {flag: f"loaded from accumulator A bit {5 - index}" for index, flag in enumerate(ALL_FLAGS)}
    elif mnemonic == "RTI":
        affected = ALL_FLAGS.copy()
        semantics = {flag: "restored from the stacked CCR" for flag in ALL_FLAGS}
    elif mnemonic == "SWI":
        affected = ["I"]
        semantics = {"I": "set after CCR is stacked"}
    elif mnemonic == "BRN":
        pass
    elif mnemonic.startswith("B") and mnemonic not in {"BSR"}:
        condition = next((condition for name, condition in BRANCHES.values() if name == mnemonic), None)
        if mnemonic in {"BCC", "BCS"}:
            read = ["C"]
        elif mnemonic in {"BNE", "BEQ"}:
            read = ["Z"]
        elif mnemonic in {"BVC", "BVS"}:
            read = ["V"]
        elif mnemonic in {"BPL", "BMI"}:
            read = ["N"]
        elif condition and "C" in condition and "Z" in condition:
            read = ["C", "Z"]
        elif condition and "N" in condition and "V" in condition and "Z" in condition:
            read = ["N", "V", "Z"]
        elif condition and "N" in condition and "V" in condition:
            read = ["N", "V"]
    return read, affected, undefined, semantics


def _register_facts(mnemonic: str, mode: str) -> tuple[list[str], list[str]]:
    read = ["PC"]
    written = ["PC"]
    if mode == "indexed-unsigned-8":
        read.append("X")

    root = _operation_root(mnemonic)
    if mnemonic in {"ABA", "SBA", "CBA"}:
        read += ["A", "B"]
        if mnemonic != "CBA":
            written.append("A")
    elif mnemonic == "TAB":
        read.append("A")
        written.append("B")
    elif mnemonic == "TBA":
        read.append("B")
        written.append("A")
    elif mnemonic in {"TAP"}:
        read.append("A")
        written.append("CCR")
    elif mnemonic == "TPA":
        read.append("CCR")
        written.append("A")
    elif mnemonic in {"INX", "DEX", "ABX"}:
        read.append("X")
        written.append("X")
        if mnemonic == "ABX":
            read.append("B")
    elif mnemonic == "TSX":
        read.append("SP")
        written.append("X")
    elif mnemonic == "TXS":
        read.append("X")
        written.append("SP")
    elif mnemonic in {"INS", "DES"}:
        read.append("SP")
        written.append("SP")
    elif mnemonic.startswith("PSH"):
        register = mnemonic[-1]
        read += [register, "SP"]
        written.append("SP")
    elif mnemonic.startswith("PUL"):
        register = mnemonic[-1]
        read.append("SP")
        written += ["SP", register]
    elif mnemonic in {"BSR", "JSR"}:
        read.append("SP")
        written.append("SP")
    elif mnemonic == "RTS":
        read.append("SP")
        written.append("SP")
    elif mnemonic == "RTI":
        read.append("SP")
        written += ["SP", "CCR", "X", "A", "B"]
    elif mnemonic in {"SWI", "WAI"}:
        read += ["SP", "CCR", "X", "A", "B"]
        written.append("SP")
        if mnemonic == "SWI":
            written.append("CCR")
    elif mnemonic == "MUL":
        read += ["A", "B"]
        written += ["A", "B"]
    elif mnemonic == "DAA":
        read.append("A")
        written.append("A")
    elif mnemonic == "XGDX":
        read += ["A", "B", "X"]
        written += ["A", "B", "X"]
    elif mnemonic in {"ASLD", "LSRD", "ADDD", "SUBD"}:
        read += ["A", "B"]
        written += ["A", "B"]
    elif mnemonic == "LDD":
        written += ["A", "B"]
    elif mnemonic == "STD":
        read += ["A", "B"]
    elif mnemonic == "CPX":
        read.append("X")
    elif mnemonic == "LDX":
        written.append("X")
    elif mnemonic == "STX":
        read.append("X")
    elif mnemonic == "LDS":
        written.append("SP")
    elif mnemonic == "STS":
        read.append("SP")
    elif root in RMW_ROWS.values() and mnemonic != root:
        register = mnemonic[-1]
        if root != "CLR":
            read.append(register)
        if root != "TST":
            written.append(register)
    elif root in AB_ROWS.values():
        register = mnemonic[-1]
        if root == "LDA":
            written.append(register)
        elif root == "STA":
            read.append(register)
        elif root in {"CMP", "BIT"}:
            read.append(register)
        else:
            read.append(register)
            written.append(register)
    return _dedupe(read), _dedupe(written)


def _memory_facts(mnemonic: str, mode: str, length: int) -> list[str]:
    operations = ["read opcode at PC"]
    if length > 1:
        operations.append(f"read {length - 1} instruction operand byte(s)")
    root = _operation_root(mnemonic)
    memory_mode = mode in {"direct", "indexed-unsigned-8", "extended"}
    if mnemonic in {"AIM", "OIM", "EIM", "TIM"}:
        operations.append("read effective-address byte")
        if mnemonic != "TIM":
            operations.append("write modified effective-address byte")
    elif memory_mode and mnemonic not in {"JMP", "JSR"}:
        if root == "STA" or mnemonic in {"STX", "STS", "STD"}:
            width = 2 if mnemonic in {"STX", "STS", "STD"} else 1
            operations.append(f"write {width} effective-address byte(s)")
        elif root in RMW_ROWS.values():
            if root != "CLR":
                operations.append("read effective-address byte")
            if root == "CLR":
                operations.append("write zero to effective-address byte")
            elif root != "TST":
                operations.append("write modified effective-address byte")
        else:
            width = 2 if mnemonic in {"CPX", "LDX", "LDS", "LDD", "ADDD", "SUBD"} else 1
            operations.append(f"read {width} effective-address byte(s)")
    if mnemonic in {"BSR", "JSR"}:
        operations += ["write return-PC low byte to stack", "write return-PC high byte to stack"]
    elif mnemonic in {"PSHA", "PSHB"}:
        operations.append("write register byte to stack")
    elif mnemonic == "PSHX":
        operations.append("write two X bytes to stack")
    elif mnemonic in {"PULA", "PULB"}:
        operations.append("read register byte from stack")
    elif mnemonic == "PULX":
        operations.append("read two X bytes from stack")
    elif mnemonic == "RTS":
        operations.append("read two return-PC bytes from stack")
    elif mnemonic == "RTI":
        operations.append("read CCR, B, A, X, and PC bytes from stack")
    elif mnemonic in {"SWI", "WAI"}:
        operations.append("write PC, X, A, B, and CCR bytes to stack")
        if mnemonic == "SWI":
            operations.append("read SWI vector at FFFA:FFFB")
    return operations


def _control_facts(mnemonic: str, condition: str | None = None) -> tuple[list[str], str | None, str | None]:
    stack: list[str] = []
    branch: str | None = None
    vector: str | None = None
    if condition is not None:
        branch = f"add signed 8-bit displacement to post-instruction PC when {condition}"
    elif mnemonic == "BRN":
        branch = "never changes PC beyond normal two-byte instruction advance"
    elif mnemonic == "BSR":
        branch = "push post-instruction PC and add signed 8-bit displacement"
        stack = ["push PCL, then PCH; SP decrements after each byte"]
    elif mnemonic == "JMP":
        branch = "load PC with the effective address"
    elif mnemonic == "JSR":
        branch = "push post-instruction PC and load PC with the effective address"
        stack = ["push PCL, then PCH; SP decrements after each byte"]
    elif mnemonic == "RTS":
        branch = "pull the saved PC and resume at it"
        stack = ["increment SP and pull PCH, then increment SP and pull PCL"]
    elif mnemonic == "RTI":
        branch = "restore saved PC after restoring the complete machine state"
        stack = ["pull CCR, B, A, X high, X low, PC high, and PC low in documented order"]
    elif mnemonic in {"PSHA", "PSHB"}:
        stack = [f"store {mnemonic[-1]} at SP, then decrement SP"]
    elif mnemonic in {"PULA", "PULB"}:
        stack = [f"increment SP, then load {mnemonic[-1]} from stack"]
    elif mnemonic == "PSHX":
        stack = ["push X low, then X high; decrement SP after each byte"]
    elif mnemonic == "PULX":
        stack = ["increment SP and pull X high, then increment SP and pull X low"]
    elif mnemonic == "INS":
        stack = ["increment SP by one without accessing stack memory"]
    elif mnemonic == "DES":
        stack = ["decrement SP by one without accessing stack memory"]
    elif mnemonic == "TXS":
        stack = ["replace SP with X minus one"]
    elif mnemonic == "LDS":
        stack = ["replace SP with the 16-bit operand"]
    elif mnemonic == "SWI":
        stack = ["push PCL, PCH, X low, X high, A, B, and CCR; decrement SP after each byte"]
        vector = "load PC from the software-interrupt vector at FFFA:FFFB"
    elif mnemonic == "WAI":
        stack = ["push PCL, PCH, X low, X high, A, B, and CCR once, then wait"]
        vector = "on an accepted interrupt, load that source's vector without stacking the state again"
    return stack, branch, vector


def _aliases(mnemonic: str, architecture: str) -> list[str]:
    aliases = {
        "ASL": ["LSL"],
        "ASLA": ["LSLA"],
        "ASLB": ["LSLB"],
        "ASLD": ["LSLD"],
    }.get(mnemonic, [])
    if architecture in {"m6801", "hd6301"} and mnemonic == "BCC":
        aliases.append("BHS")
    if architecture in {"m6801", "hd6301"} and mnemonic == "BCS":
        aliases.append("BLO")
    return aliases


def _instruction(
    opcode: int,
    architecture: str,
    mnemonic: str,
    mode: str,
    length: int,
    cycles: int,
    reference_id: str,
    locator: str,
    *,
    condition: str | None = None,
    notes: str = "",
) -> dict:
    flags_read, flags_affected, flags_undefined, flag_semantics = _flag_facts(
        mnemonic, architecture
    )
    registers_read, registers_written = _register_facts(mnemonic, mode)
    stack_effects, branch_behavior, vector_behavior = _control_facts(mnemonic, condition)
    memory_operations = _memory_facts(mnemonic, mode, length)
    conditional_cycles: list[str] = []
    if architecture == "m6801" and mnemonic == "WAI":
        memory_operations.append("repeat read at post-stack SP while waiting")
        conditional_cycles.append(
            "after an unmasked request: 5 E-cycles to the first handler opcode "
            "for NMI or IRQ2; 6 E-cycles for IRQ1"
        )
    return {
        "opcode": opcode,
        "opcode_hex": f"{opcode:02X}",
        "classification": "documented_instruction",
        "mnemonic": mnemonic,
        "aliases": _aliases(mnemonic, architecture),
        "architectural_applicability": [architecture],
        "addressing_mode": mode,
        "length": length,
        "cycles": cycles,
        "conditional_cycles": conditional_cycles,
        "registers_read": registers_read,
        "registers_written": registers_written,
        "flags_read": flags_read,
        "flags_affected": flags_affected,
        "flags_undefined": flags_undefined,
        "flag_semantics": flag_semantics,
        "memory_operations": memory_operations,
        "stack_effects": stack_effects,
        "branch_behavior": branch_behavior,
        "vector_behavior": vector_behavior,
        "primary_reference": {"id": reference_id, "locator": locator},
        "notes": notes,
    }


def _empty_architecture(architecture: str, reference_id: str, locator: str) -> list[dict]:
    return [_undefined(opcode, architecture, reference_id, locator) for opcode in range(256)]


def _put(records: list[dict], record: dict) -> None:
    opcode = record["opcode"]
    if records[opcode]["classification"] != "undefined_behavior":
        raise ValueError(f"duplicate opcode definition {opcode:02X}")
    records[opcode] = record


def build_m6800() -> dict:
    architecture = "m6800"
    reference_id = "motorola-m6800-prm-1976"
    undefined_reference_id = "motorola-mc6800-system-design-data-1976"
    undefined_locator = "MC6800 MPU tables 2-7 complete instruction set; opcode is not assigned"
    records = _empty_architecture(architecture, undefined_reference_id, undefined_locator)

    inherent = {
        0x01: ("NOP", 2), 0x06: ("TAP", 2), 0x07: ("TPA", 2),
        0x08: ("INX", 4), 0x09: ("DEX", 4), 0x0A: ("CLV", 2),
        0x0B: ("SEV", 2), 0x0C: ("CLC", 2), 0x0D: ("SEC", 2),
        0x0E: ("CLI", 2), 0x0F: ("SEI", 2), 0x10: ("SBA", 2),
        0x11: ("CBA", 2), 0x16: ("TAB", 2), 0x17: ("TBA", 2),
        0x19: ("DAA", 2), 0x1B: ("ABA", 2), 0x30: ("TSX", 4),
        0x31: ("INS", 4), 0x32: ("PULA", 4), 0x33: ("PULB", 4),
        0x34: ("DES", 4), 0x35: ("TXS", 4), 0x36: ("PSHA", 4),
        0x37: ("PSHB", 4), 0x39: ("RTS", 5), 0x3B: ("RTI", 10),
        0x3E: ("WAI", 9), 0x3F: ("SWI", 12),
    }
    for opcode, (mnemonic, cycles) in inherent.items():
        _put(records, _instruction(opcode, architecture, mnemonic, "inherent", 1, cycles, reference_id, f"appendix A, {mnemonic} instruction entry"))

    for opcode, (mnemonic, condition) in BRANCHES.items():
        _put(records, _instruction(opcode, architecture, mnemonic, "relative", 2, 4, reference_id, f"appendix A, {mnemonic} instruction entry", condition=condition))
    _put(records, _instruction(0x8D, architecture, "BSR", "relative", 2, 8, reference_id, "appendix A, BSR instruction entry"))

    for low, root in RMW_ROWS.items():
        for high, suffix, mode, length, cycles in (
            (0x4, "A", "accumulator-a", 1, 2),
            (0x5, "B", "accumulator-b", 1, 2),
            (0x6, "", "indexed-unsigned-8", 2, 7),
            (0x7, "", "extended", 3, 6),
        ):
            mnemonic = root + suffix
            _put(records, _instruction((high << 4) | low, architecture, mnemonic, mode, length, cycles, reference_id, f"appendix A, {root} instruction entry"))
    for high, mode, length, cycles in ((0x6, "indexed-unsigned-8", 2, 4), (0x7, "extended", 3, 3)):
        _put(records, _instruction((high << 4) | 0xE, architecture, "JMP", mode, length, cycles, reference_id, "appendix A, JMP instruction entry"))

    modes_8 = {
        0x8: ("immediate-8", 2, 2),
        0x9: ("direct", 2, 3),
        0xA: ("indexed-unsigned-8", 2, 5),
        0xB: ("extended", 3, 4),
        0xC: ("immediate-8", 2, 2),
        0xD: ("direct", 2, 3),
        0xE: ("indexed-unsigned-8", 2, 5),
        0xF: ("extended", 3, 4),
    }
    for high, (mode, length, cycles) in modes_8.items():
        accumulator = "A" if high < 0xC else "B"
        for low, root in AB_ROWS.items():
            if root == "STA" and mode.startswith("immediate"):
                continue
            mnemonic = root + accumulator
            actual_cycles = cycles + (1 if root == "STA" else 0)
            _put(records, _instruction((high << 4) | low, architecture, mnemonic, mode, length, actual_cycles, reference_id, f"appendix A, {root} instruction entry"))

    for opcode, mode, length, cycles in (
        (0x8C, "immediate-16", 3, 3), (0x9C, "direct", 2, 4),
        (0xAC, "indexed-unsigned-8", 2, 6), (0xBC, "extended", 3, 5),
    ):
        _put(records, _instruction(opcode, architecture, "CPX", mode, length, cycles, reference_id, "appendix A, CPX instruction entry", notes="On MC6800, C is not affected and N/V are not intended for conditional branching."))
    for base, load, store in ((0x80, "LDS", "STS"), (0xC0, "LDX", "STX")):
        for offset, mode, length, cycles in (
            (0x0E, "immediate-16", 3, 3), (0x1E, "direct", 2, 4),
            (0x2E, "indexed-unsigned-8", 2, 6), (0x3E, "extended", 3, 5),
        ):
            _put(records, _instruction(base + offset, architecture, load, mode, length, cycles, reference_id, f"appendix A, {load} instruction entry"))
        for offset, mode, length, cycles in (
            (0x1F, "direct", 2, 5), (0x2F, "indexed-unsigned-8", 2, 7),
            (0x3F, "extended", 3, 6),
        ):
            _put(records, _instruction(base + offset, architecture, store, mode, length, cycles, reference_id, f"appendix A, {store} instruction entry"))
    for opcode, mode, length, cycles in ((0xAD, "indexed-unsigned-8", 2, 8), (0xBD, "extended", 3, 9)):
        _put(records, _instruction(opcode, architecture, "JSR", mode, length, cycles, reference_id, "appendix A, JSR instruction entry"))

    return {
        "schema_version": 1,
        "architecture": architecture,
        "title": "Motorola M6800 opcode classification",
        "primary_references": [
            {"id": reference_id, "locators": ["appendix A instruction entries", "chapters 4-5"]},
            {"id": undefined_reference_id, "locators": ["MC6800 MPU tables 2-7"]},
        ],
        "opcodes": records,
    }


def build_m6801() -> dict:
    architecture = "m6801"
    reference_id = "motorola-mc6801-reference-1983"
    records = _empty_architecture(architecture, reference_id, "appendix B operation code map, cell marked undefined")

    inherent = {
        0x01: ("NOP", 2), 0x04: ("LSRD", 3), 0x05: ("ASLD", 3),
        0x06: ("TAP", 2), 0x07: ("TPA", 2), 0x08: ("INX", 3),
        0x09: ("DEX", 3), 0x0A: ("CLV", 2), 0x0B: ("SEV", 2),
        0x0C: ("CLC", 2), 0x0D: ("SEC", 2), 0x0E: ("CLI", 2),
        0x0F: ("SEI", 2), 0x10: ("SBA", 2), 0x11: ("CBA", 2),
        0x16: ("TAB", 2), 0x17: ("TBA", 2), 0x19: ("DAA", 2),
        0x1B: ("ABA", 2), 0x30: ("TSX", 3), 0x31: ("INS", 3),
        0x32: ("PULA", 4), 0x33: ("PULB", 4), 0x34: ("DES", 3),
        0x35: ("TXS", 3), 0x36: ("PSHA", 3), 0x37: ("PSHB", 3),
        0x38: ("PULX", 5), 0x39: ("RTS", 5), 0x3A: ("ABX", 3),
        0x3B: ("RTI", 10), 0x3C: ("PSHX", 4), 0x3D: ("MUL", 10),
        0x3E: ("WAI", 9), 0x3F: ("SWI", 12),
    }
    for opcode, (mnemonic, cycles) in inherent.items():
        _put(records, _instruction(opcode, architecture, mnemonic, "inherent", 1, cycles, reference_id, f"appendix A, {mnemonic} instruction entry"))

    for opcode, (mnemonic, condition) in BRANCHES.items():
        _put(records, _instruction(opcode, architecture, mnemonic, "relative", 2, 3, reference_id, f"figure 4-2 and appendix A, {mnemonic}", condition=condition))
    _put(records, _instruction(0x21, architecture, "BRN", "relative", 2, 3, reference_id, "figure 4-2 and appendix A, BRN"))
    _put(records, _instruction(0x8D, architecture, "BSR", "relative", 2, 6, reference_id, "figure 4-2 and appendix A, BSR"))

    for low, root in RMW_ROWS.items():
        for high, suffix, mode, length, cycles in (
            (0x4, "A", "accumulator-a", 1, 2),
            (0x5, "B", "accumulator-b", 1, 2),
            (0x6, "", "indexed-unsigned-8", 2, 6),
            (0x7, "", "extended", 3, 6),
        ):
            mnemonic = root + suffix
            _put(records, _instruction((high << 4) | low, architecture, mnemonic, mode, length, cycles, reference_id, f"figure 4-2 and appendix A, {root}"))
    for high, mode, length in ((0x6, "indexed-unsigned-8", 2), (0x7, "extended", 3)):
        _put(records, _instruction((high << 4) | 0xE, architecture, "JMP", mode, length, 3, reference_id, "figure 4-2 and appendix A, JMP"))

    modes_8 = {
        0x8: ("immediate-8", 2, 2), 0x9: ("direct", 2, 3),
        0xA: ("indexed-unsigned-8", 2, 4), 0xB: ("extended", 3, 4),
        0xC: ("immediate-8", 2, 2), 0xD: ("direct", 2, 3),
        0xE: ("indexed-unsigned-8", 2, 4), 0xF: ("extended", 3, 4),
    }
    for high, (mode, length, cycles) in modes_8.items():
        accumulator = "A" if high < 0xC else "B"
        for low, root in AB_ROWS.items():
            if root == "STA" and mode.startswith("immediate"):
                continue
            _put(records, _instruction((high << 4) | low, architecture, root + accumulator, mode, length, cycles, reference_id, f"figure 4-2 and appendix A, {root}"))

    for mnemonic, opcodes in {
        "SUBD": [(0x83, "immediate-16", 3, 4), (0x93, "direct", 2, 5), (0xA3, "indexed-unsigned-8", 2, 6), (0xB3, "extended", 3, 6)],
        "ADDD": [(0xC3, "immediate-16", 3, 4), (0xD3, "direct", 2, 5), (0xE3, "indexed-unsigned-8", 2, 6), (0xF3, "extended", 3, 6)],
        "LDD": [(0xCC, "immediate-16", 3, 3), (0xDC, "direct", 2, 4), (0xEC, "indexed-unsigned-8", 2, 5), (0xFC, "extended", 3, 5)],
        "STD": [(0xDD, "direct", 2, 4), (0xED, "indexed-unsigned-8", 2, 5), (0xFD, "extended", 3, 5)],
    }.items():
        for opcode, mode, length, cycles in opcodes:
            _put(records, _instruction(opcode, architecture, mnemonic, mode, length, cycles, reference_id, f"figure 4-2 and appendix A, {mnemonic}"))

    for opcode, mode, length, cycles in (
        (0x8C, "immediate-16", 3, 4), (0x9C, "direct", 2, 5),
        (0xAC, "indexed-unsigned-8", 2, 6), (0xBC, "extended", 3, 6),
    ):
        _put(records, _instruction(opcode, architecture, "CPX", mode, length, cycles, reference_id, "figure 4-2 and appendix A, CPX", notes="MC6801 CPX sets C and supports every applicable conditional branch."))
    for base, load, store in ((0x80, "LDS", "STS"), (0xC0, "LDX", "STX")):
        for offset, mode, length, cycles in (
            (0x0E, "immediate-16", 3, 3), (0x1E, "direct", 2, 4),
            (0x2E, "indexed-unsigned-8", 2, 5), (0x3E, "extended", 3, 5),
        ):
            _put(records, _instruction(base + offset, architecture, load, mode, length, cycles, reference_id, f"figure 4-2 and appendix A, {load}"))
        for offset, mode, length, cycles in (
            (0x1F, "direct", 2, 4), (0x2F, "indexed-unsigned-8", 2, 5),
            (0x3F, "extended", 3, 5),
        ):
            _put(records, _instruction(base + offset, architecture, store, mode, length, cycles, reference_id, f"figure 4-2 and appendix A, {store}"))
    for opcode, mode, length, cycles in (
        (0x9D, "direct", 2, 5), (0xAD, "indexed-unsigned-8", 2, 6),
        (0xBD, "extended", 3, 6),
    ):
        _put(records, _instruction(opcode, architecture, "JSR", mode, length, cycles, reference_id, "figure 4-2 and appendix A, JSR"))

    return {
        "schema_version": 1,
        "architecture": architecture,
        "title": "Motorola MC6801/MC6803 opcode classification",
        "primary_references": [{"id": reference_id, "locators": ["figure 4-2 instruction summary", "appendix A instruction entries", "appendix B operation code map"]}],
        "opcodes": records,
    }


HD6301_INHERENT_CYCLES = {
    "NOP": 1,
    "LSRD": 1,
    "ASLD": 1,
    "TAP": 1,
    "TPA": 1,
    "INX": 1,
    "DEX": 1,
    "CLV": 1,
    "SEV": 1,
    "CLC": 1,
    "SEC": 1,
    "CLI": 1,
    "SEI": 1,
    "SBA": 1,
    "CBA": 1,
    "TAB": 1,
    "TBA": 1,
    "DAA": 2,
    "ABA": 1,
    "TSX": 1,
    "INS": 1,
    "PULA": 3,
    "PULB": 3,
    "DES": 1,
    "TXS": 1,
    "PSHA": 4,
    "PSHB": 4,
    "PULX": 4,
    "RTS": 5,
    "ABX": 1,
    "RTI": 10,
    "PSHX": 5,
    "MUL": 7,
    "WAI": 9,
    "SWI": 12,
}


def _hd6301_cycles(record: dict) -> int:
    mnemonic = record["mnemonic"]
    mode = record["addressing_mode"]
    root = _operation_root(mnemonic)
    if mnemonic in HD6301_INHERENT_CYCLES:
        return HD6301_INHERENT_CYCLES[mnemonic]
    if mnemonic == "BSR":
        return 5
    if mode == "relative":
        return 3
    if mnemonic == "JMP":
        return 3
    if mnemonic == "JSR":
        return {"direct": 5, "indexed-unsigned-8": 5, "extended": 6}[mode]
    if root in RMW_ROWS.values():
        if mode in {"accumulator-a", "accumulator-b"}:
            return 1
        if root == "CLR":
            return 5
        if root == "TST":
            return 4
        return 6
    if mnemonic in {"ADDD", "SUBD", "LDD"}:
        return {"immediate-16": 3, "direct": 4, "indexed-unsigned-8": 5, "extended": 5}[mode]
    if mnemonic in {"CPX", "LDS", "LDX"}:
        return {"immediate-16": 3, "direct": 4, "indexed-unsigned-8": 5, "extended": 5}[mode]
    if mnemonic in {"STD", "STS", "STX"}:
        return {"direct": 4, "indexed-unsigned-8": 5, "extended": 5}[mode]
    if root in AB_ROWS.values():
        return {"immediate-8": 2, "direct": 3, "indexed-unsigned-8": 4, "extended": 4}[mode]
    raise ValueError(f"no HD6301 cycle fact for {record['opcode_hex']} {mnemonic} {mode}")


def build_hd6301() -> dict:
    architecture = "hd6301"
    reference_id = "hitachi-hd6301-hd6303-series-handbook-1989"
    map_locator = "HD6301V1 section 3.2, tables 3-2-1 through 3-2-5, printed pages 171-175"
    records = deepcopy(build_m6801()["opcodes"])
    for record in records:
        record["architectural_applicability"] = [architecture]
        record["primary_reference"] = {"id": reference_id, "locator": map_locator}
        if record["classification"] == "documented_instruction":
            record["cycles"] = _hd6301_cycles(record)
            if record["mnemonic"] == "WAI":
                record["conditional_cycles"] = []
                record["memory_operations"] = [
                    operation
                    for operation in record["memory_operations"]
                    if operation != "repeat read at post-stack SP while waiting"
                ]
                record["memory_operations"].append(
                    "present FFFF with read/write strobes inactive while waiting"
                )
                record["primary_reference"]["locator"] = (
                    "Q&A III.4.5, WAI pin states (printed page 493)"
                )
                record["notes"] = (
                    "Unlike the MC6801, WAI presents FFFF while the data bus is "
                    "high impedance and the read/write strobes are inactive."
                )
            elif record["mnemonic"] == "CPX":
                record["notes"] = "HD6301 CPX affects C and supports every applicable conditional branch."
            elif record["mnemonic"] == "DAA":
                record["flags_undefined"] = []
                record["flag_semantics"].pop("V")
                record["notes"] = "Hitachi documents V as not affected; this differs from Motorola's undefined MC6801 DAA overflow state."
        else:
            record["notes"] = "Undefined map cells are converted to documented opcode traps after applying Hitachi extensions."

    extensions = {
        0x18: ("XGDX", "inherent", 1, 2),
        0x1A: ("SLP", "inherent", 1, 4),
        0x61: ("AIM", "indexed-unsigned-8", 3, 7),
        0x62: ("OIM", "indexed-unsigned-8", 3, 7),
        0x65: ("EIM", "indexed-unsigned-8", 3, 7),
        0x6B: ("TIM", "indexed-unsigned-8", 3, 5),
        0x71: ("AIM", "direct", 3, 6),
        0x72: ("OIM", "direct", 3, 6),
        0x75: ("EIM", "direct", 3, 6),
        0x7B: ("TIM", "direct", 3, 4),
    }
    for opcode, (mnemonic, mode, length, cycles) in extensions.items():
        _put(
            records,
            _instruction(
                opcode,
                architecture,
                mnemonic,
                mode,
                length,
                cycles,
                reference_id,
                map_locator,
                notes="Hitachi extension to the HD6801 instruction set.",
            ),
        )

    for record in list(records):
        if record["classification"] == "undefined_behavior":
            records[record["opcode"]] = _opcode_trap(
                record["opcode"], architecture, reference_id
            )

    return {
        "schema_version": 1,
        "architecture": architecture,
        "title": "Hitachi HD6301/HD6303/HD63701 opcode classification",
        "primary_references": [
            {
                "id": reference_id,
                "locators": [
                    "HD6301V1 section 3.2, tables 3-2-1 through 3-2-5, printed pages 171-175",
                    "HD6301V1 section 3.3, cycle-by-cycle operation tables",
                ],
            }
        ],
        "opcodes": records,
    }


M6805_BRANCHES = {
    0x20: ("BRA", "always"),
    0x21: ("BRN", "never"),
    0x22: ("BHI", "C=0 and Z=0"),
    0x23: ("BLS", "C=1 or Z=1"),
    0x24: ("BCC", "C=0"),
    0x25: ("BCS", "C=1"),
    0x26: ("BNE", "Z=0"),
    0x27: ("BEQ", "Z=1"),
    0x28: ("BHCC", "H=0"),
    0x29: ("BHCS", "H=1"),
    0x2A: ("BPL", "N=0"),
    0x2B: ("BMI", "N=1"),
    0x2C: ("BMC", "I=0"),
    0x2D: ("BMS", "I=1"),
    0x2E: ("BIL", "the external interrupt input is low"),
    0x2F: ("BIH", "the external interrupt input is high"),
}


M6805_DATA_ROWS = {
    0x0: "SUB",
    0x1: "CMP",
    0x2: "SBC",
    0x3: "CPX",
    0x4: "AND",
    0x5: "BIT",
    0x6: "LDA",
    0x7: "STA",
    0x8: "EOR",
    0x9: "ADC",
    0xA: "ORA",
    0xB: "ADD",
    0xC: "JMP",
    0xD: "JSR",
    0xE: "LDX",
    0xF: "STX",
}


def _m6805_flag_facts(mnemonic: str) -> tuple[list[str], list[str], list[str], dict[str, str]]:
    root = _operation_root(mnemonic)
    read: list[str] = []
    affected: list[str] = []
    undefined: list[str] = []
    semantics: dict[str, str] = {}

    if root in {"ADD", "ADC"}:
        affected = ["H", "N", "Z", "C"]
        semantics = {
            "H": "carry from result bit 3 into bit 4",
            "N": "result bit 7",
            "Z": "1 exactly when the result is zero",
            "C": "carry out of result bit 7",
        }
        if root == "ADC":
            read = ["C"]
    elif root in {"SUB", "CMP", "SBC"} or mnemonic == "CPX":
        affected = ["N", "Z", "C"]
        semantics = {
            "N": "result bit 7",
            "Z": "1 exactly when the subtraction result is zero",
            "C": "borrow from result bit 7",
        }
        if root == "SBC":
            read = ["C"]
    elif root in {"AND", "BIT", "LDA", "STA", "EOR", "ORA"} or mnemonic in {"LDX", "STX"}:
        affected = ["N", "Z"]
        semantics = {"N": "result bit 7", "Z": "1 exactly when the result is zero"}
    elif root == "NEG":
        affected = ["N", "Z", "C"]
        semantics = {
            "N": "result bit 7",
            "Z": "1 exactly when the result is zero",
            "C": "1 exactly when the original operand is nonzero",
        }
    elif root == "COM":
        affected = ["N", "Z", "C"]
        semantics = {"N": "result bit 7", "Z": "1 exactly when the result is zero", "C": "set"}
    elif root in {"ASL", "ROL", "ROR", "ASR", "LSR"}:
        affected = ["N", "Z", "C"]
        semantics = {
            "N": "result bit 7",
            "Z": "1 exactly when the result is zero",
            "C": "bit shifted out of the operand",
        }
        if root in {"ROL", "ROR"}:
            read = ["C"]
        if root == "LSR":
            semantics["N"] = "cleared"
    elif root in {"INC", "DEC"}:
        affected = ["N", "Z"]
        semantics = {"N": "result bit 7", "Z": "1 exactly when the result is zero"}
    elif root == "TST":
        affected = ["N", "Z"]
        semantics = {"N": "operand bit 7", "Z": "1 exactly when the operand is zero"}
    elif root == "CLR":
        affected = ["N", "Z"]
        semantics = {"N": "cleared", "Z": "set"}
    elif mnemonic.startswith("BRSET") or mnemonic.startswith("BRCLR"):
        affected = ["C"]
        semantics = {"C": "copy of the tested memory bit"}
    elif mnemonic == "DAA":
        read = ["H", "C"]
        affected = ["N", "Z", "C"]
        semantics = {
            "N": "adjusted result bit 7",
            "Z": "1 exactly when the adjusted result is zero",
            "C": "decimal carry selected by the manufacturer adjustment table",
        }
    elif mnemonic in {"CLC", "SEC", "CLI", "SEI"}:
        flag = {"CLC": "C", "SEC": "C", "CLI": "I", "SEI": "I"}[mnemonic]
        affected = [flag]
        semantics = {flag: "set" if mnemonic in {"SEC", "SEI"} else "cleared"}
    elif mnemonic in {"STOP", "WAIT"}:
        affected = ["I"]
        semantics = {"I": "cleared when entering the low-power mode"}
    elif mnemonic == "RTI":
        affected = ["H", "I", "N", "Z", "C"]
        semantics = {flag: "restored from the stacked CCR" for flag in affected}
    elif mnemonic == "SWI":
        affected = ["I"]
        semantics = {"I": "set after CCR is stacked"}
    elif mnemonic in {"BCC", "BCS"}:
        read = ["C"]
    elif mnemonic in {"BNE", "BEQ"}:
        read = ["Z"]
    elif mnemonic in {"BHI", "BLS"}:
        read = ["C", "Z"]
    elif mnemonic in {"BHCC", "BHCS"}:
        read = ["H"]
    elif mnemonic in {"BPL", "BMI"}:
        read = ["N"]
    elif mnemonic in {"BMC", "BMS"}:
        read = ["I"]
    return read, affected, undefined, semantics


def _m6805_register_facts(mnemonic: str, mode: str) -> tuple[list[str], list[str]]:
    read = ["PC"]
    written = ["PC"]
    if mode in {"indexed-no-offset", "indexed-unsigned-8", "indexed-unsigned-16"}:
        read.append("X")

    root = _operation_root(mnemonic)
    if mode == "accumulator-a":
        if root != "CLR":
            read.append("A")
        if root != "TST":
            written.append("A")
    elif mode == "index-register-x":
        if root != "CLR":
            read.append("X")
        if root != "TST":
            written.append("X")
    elif root in {"ADD", "ADC", "SUB", "CMP", "SBC", "AND", "BIT", "EOR", "ORA"}:
        read.append("A")
        if root not in {"CMP", "BIT"}:
            written.append("A")
    elif mnemonic == "LDA":
        written.append("A")
    elif mnemonic == "STA":
        read.append("A")
    elif mnemonic == "CPX":
        read.append("X")
    elif mnemonic == "LDX":
        written.append("X")
    elif mnemonic == "STX":
        read.append("X")
    elif mnemonic == "TAX":
        read.append("A")
        written.append("X")
    elif mnemonic == "TXA":
        read.append("X")
        written.append("A")
    elif mnemonic == "DAA":
        read.append("A")
        written.append("A")
    elif mnemonic == "RSP":
        written.append("SP")
    elif mnemonic in {"BSR", "JSR", "RTS"}:
        read.append("SP")
        written.append("SP")
    elif mnemonic == "RTI":
        read.append("SP")
        written += ["SP", "CCR", "A", "X"]
    elif mnemonic == "SWI":
        read += ["SP", "CCR", "A", "X"]
        written += ["SP", "CCR"]
    elif mnemonic in {"STOP", "WAIT"}:
        written.append("CCR")
    return _dedupe(read), _dedupe(written)


def _m6805_memory_facts(
    architecture: str, mnemonic: str, mode: str, length: int
) -> list[str]:
    operations = ["read opcode at PC"]
    if length > 1:
        operations.append(f"read {length - 1} instruction operand byte(s)")
    root = _operation_root(mnemonic)
    memory_mode = mode in {"direct", "extended", "indexed-no-offset", "indexed-unsigned-8", "indexed-unsigned-16"}
    if mode == "bit-test-branch-direct":
        operations.append("read direct-address byte to test selected bit")
    elif mode == "bit-set-clear-direct":
        operations += ["read direct-address byte", "write modified direct-address byte"]
    elif memory_mode and mnemonic not in {"JMP", "JSR"}:
        if mnemonic in {"STA", "STX"}:
            operations.append("write effective-address byte")
        elif root in RMW_ROWS.values():
            if root != "CLR":
                operations.append("read effective-address byte")
            if root == "CLR":
                operations.append("write zero to effective-address byte")
            elif root != "TST":
                operations.append("write modified effective-address byte")
        else:
            operations.append("read effective-address byte")
    if mnemonic in {"BSR", "JSR"}:
        operations += ["write return-PC low byte to stack", "write return-PC high byte to stack"]
    elif mnemonic == "RTS":
        operations.append("read two return-PC bytes from stack")
    elif mnemonic == "RTI":
        operations.append("read CCR, A, X, and PC bytes from stack")
    elif mnemonic == "SWI":
        operations += ["write PC, X, A, and CCR bytes to stack", "read SWI vector at FFFC:FFFD"]
        if architecture == "m6805":
            operations.append("read first handler opcode at resolved vector on cycle 11")
    return operations


def _m6805_control_facts(mnemonic: str, condition: str | None) -> tuple[list[str], str | None, str | None]:
    stack: list[str] = []
    branch: str | None = None
    vector: str | None = None
    if condition == "never":
        branch = "never changes PC beyond normal two-byte instruction advance"
    elif condition is not None:
        instruction_length = 3 if mnemonic.startswith(("BRSET", "BRCLR")) else 2
        branch = f"add signed 8-bit displacement to post-{instruction_length}-byte-instruction PC when {condition}"
    elif mnemonic == "BSR":
        branch = "push post-instruction PC and add signed 8-bit displacement"
        stack = ["push PCL, then PCH; SP decrements after each byte"]
    elif mnemonic == "JMP":
        branch = "load PC with the effective address"
    elif mnemonic == "JSR":
        branch = "push post-instruction PC and load PC with the effective address"
        stack = ["push PCL, then PCH; SP decrements after each byte"]
    elif mnemonic == "RTS":
        branch = "pull the saved PC and resume at it"
        stack = ["increment SP and pull PCH, then increment SP and pull PCL"]
    elif mnemonic == "RTI":
        branch = "restore saved PC after restoring the complete machine state"
        stack = ["pull CCR, A, X, PC high, and PC low in documented order"]
    elif mnemonic == "SWI":
        stack = ["push PCL, PCH, X, A, and CCR; decrement SP after each byte"]
        vector = "load PC from the software-interrupt vector at FFFC:FFFD"
    return stack, branch, vector


def _m6805_instruction(
    opcode: int,
    architecture: str,
    mnemonic: str,
    mode: str,
    length: int,
    cycles: int,
    reference_id: str,
    locator: str,
    *,
    condition: str | None = None,
    notes: str = "",
) -> dict:
    flags_read, flags_affected, flags_undefined, flag_semantics = _m6805_flag_facts(mnemonic)
    registers_read, registers_written = _m6805_register_facts(mnemonic, mode)
    stack_effects, branch_behavior, vector_behavior = _m6805_control_facts(mnemonic, condition)
    aliases: list[str] = []
    if mnemonic == "ASL":
        aliases = ["LSL"]
    elif mnemonic == "ASLA":
        aliases = ["LSLA"]
    elif mnemonic == "ASLX":
        aliases = ["LSLX"]
    return {
        "opcode": opcode,
        "opcode_hex": f"{opcode:02X}",
        "classification": "documented_instruction",
        "mnemonic": mnemonic,
        "aliases": aliases,
        "architectural_applicability": [architecture],
        "addressing_mode": mode,
        "length": length,
        "cycles": cycles,
        "conditional_cycles": [],
        "registers_read": registers_read,
        "registers_written": registers_written,
        "flags_read": flags_read,
        "flags_affected": flags_affected,
        "flags_undefined": flags_undefined,
        "flag_semantics": flag_semantics,
        "memory_operations": _m6805_memory_facts(architecture, mnemonic, mode, length),
        "stack_effects": stack_effects,
        "branch_behavior": branch_behavior,
        "vector_behavior": vector_behavior,
        "primary_reference": {"id": reference_id, "locator": locator},
        "notes": notes,
    }


def _build_6805_family(architecture: str, *, hitachi: bool) -> dict:
    if hitachi:
        reference_id = "hitachi-hd6305-series-handbook-1988"
        title = "Hitachi HD6305/HD63705 opcode classification"
        map_locator = "section 1.2, table 1-7 operation code map, printed page 26"
    else:
        reference_id = "motorola-m6805-family-users-manual-1983"
        title = "Motorola M6805 HMOS opcode classification"
        map_locator = "appendix D operation code map and appendix C instruction entries"
    records = _empty_architecture(architecture, reference_id, f"{map_locator}; cell is unassigned")

    bit_branch_cycles = 5 if hitachi else 10
    bit_modify_cycles = 5 if hitachi else 7
    for bit in range(8):
        for is_clear in (False, True):
            opcode = bit * 2 + int(is_clear)
            mnemonic = f"BR{'CLR' if is_clear else 'SET'}{bit}"
            condition = f"direct-address bit {bit} is {'clear' if is_clear else 'set'}"
            _put(records, _m6805_instruction(opcode, architecture, mnemonic, "bit-test-branch-direct", 3, bit_branch_cycles, reference_id, map_locator, condition=condition))
            modify_opcode = 0x10 + opcode
            modify_mnemonic = f"B{'CLR' if is_clear else 'SET'}{bit}"
            _put(records, _m6805_instruction(modify_opcode, architecture, modify_mnemonic, "bit-set-clear-direct", 2, bit_modify_cycles, reference_id, map_locator))

    branch_cycles = 3 if hitachi else 4
    for opcode, (mnemonic, condition) in M6805_BRANCHES.items():
        _put(records, _m6805_instruction(opcode, architecture, mnemonic, "relative", 2, branch_cycles, reference_id, map_locator, condition=condition))

    for low, root in RMW_ROWS.items():
        modes = (
            (0x3, "", "direct", 2, 5 if hitachi else 6),
            (0x4, "A", "accumulator-a", 1, 2 if hitachi else 4),
            (0x5, "X", "index-register-x", 1, 2 if hitachi else 4),
            (0x6, "", "indexed-unsigned-8", 2, 6 if hitachi else 7),
            (0x7, "", "indexed-no-offset", 1, 5 if hitachi else 6),
        )
        for high, suffix, mode, length, cycles in modes:
            if hitachi and root == "TST" and mode in {"direct", "indexed-unsigned-8", "indexed-no-offset"}:
                cycles -= 1
            _put(records, _m6805_instruction((high << 4) | low, architecture, root + suffix, mode, length, cycles, reference_id, map_locator))

    if hitachi:
        controls = {
            0x80: ("RTI", 8), 0x81: ("RTS", 5), 0x83: ("SWI", 10),
            0x8D: ("DAA", 2), 0x8E: ("STOP", 4), 0x8F: ("WAIT", 4),
            0x97: ("TAX", 2), 0x98: ("CLC", 1), 0x99: ("SEC", 1),
            0x9A: ("CLI", 2), 0x9B: ("SEI", 2), 0x9C: ("RSP", 2),
            0x9D: ("NOP", 1), 0x9F: ("TXA", 2), 0xAD: ("BSR", 5),
        }
    else:
        controls = {
            0x80: ("RTI", 9), 0x81: ("RTS", 6), 0x83: ("SWI", 11),
            0x97: ("TAX", 2), 0x98: ("CLC", 2), 0x99: ("SEC", 2),
            0x9A: ("CLI", 2), 0x9B: ("SEI", 2), 0x9C: ("RSP", 2),
            0x9D: ("NOP", 2), 0x9F: ("TXA", 2), 0xAD: ("BSR", 8),
        }
    for opcode, (mnemonic, cycles) in controls.items():
        mode = "relative" if mnemonic == "BSR" else "inherent"
        length = 2 if mnemonic == "BSR" else 1
        notes = ""
        instruction_locator = map_locator
        if not hitachi and mnemonic == "SWI":
            instruction_locator = "appendix G table G2, printed page 239"
        if not hitachi and opcode in {0x8E, 0x8F}:
            raise AssertionError("HMOS specification must not include CMOS-only low-power instructions")
        _put(records, _m6805_instruction(
            opcode, architecture, mnemonic, mode, length, cycles,
            reference_id, instruction_locator, notes=notes,
        ))
    if not hitachi:
        for opcode, mnemonic in ((0x8E, "STOP"), (0x8F, "WAIT")):
            records[opcode]["notes"] = f"{mnemonic} is documented for the M146805 CMOS family only, not the M6805 HMOS architecture classified here."

    modes = {
        0xA: ("immediate-8", 2, 2),
        0xB: ("direct", 2, 3 if hitachi else 4),
        0xC: ("extended", 3, 4 if hitachi else 5),
        0xD: ("indexed-unsigned-16", 3, 5 if hitachi else 6),
        0xE: ("indexed-unsigned-8", 2, 4 if hitachi else 5),
        0xF: ("indexed-no-offset", 1, 3 if hitachi else 4),
    }
    for high, (mode, length, base_cycles) in modes.items():
        for low, mnemonic in M6805_DATA_ROWS.items():
            if high == 0xA and mnemonic in {"STA", "JMP", "JSR", "STX"}:
                continue
            cycles = base_cycles
            if mnemonic in {"STA", "STX"}:
                cycles += 1
            elif mnemonic == "JMP":
                cycles -= 1
            elif mnemonic == "JSR":
                if hitachi:
                    cycles += 1 if mode == "indexed-unsigned-16" else 2
                else:
                    cycles += {"direct": 3, "extended": 3, "indexed-unsigned-16": 3, "indexed-unsigned-8": 3, "indexed-no-offset": 3}[mode]
            _put(records, _m6805_instruction((high << 4) | low, architecture, mnemonic, mode, length, cycles, reference_id, map_locator))

    return {
        "schema_version": 1,
        "architecture": architecture,
        "title": title,
        "primary_references": [{"id": reference_id, "locators": [map_locator]}],
        "opcodes": records,
    }


def build_m6805() -> dict:
    return _build_6805_family("m6805", hitachi=False)


def build_hd6305() -> dict:
    return _build_6805_family("hd6305", hitachi=True)


BUILDERS = {
    "m6800": build_m6800,
    "m6801": build_m6801,
    "hd6301": build_hd6301,
    "m6805": build_m6805,
    "hd6305": build_hd6305,
}


def rendered_specs() -> dict[Path, str]:
    return {
        OUTPUT_DIR / f"{architecture}.json": json.dumps(builder(), indent=2, sort_keys=False) + "\n"
        for architecture, builder in BUILDERS.items()
    }


def write_specs(check: bool) -> bool:
    success = True
    for path, expected in rendered_specs().items():
        if check:
            try:
                actual = path.read_text(encoding="utf-8")
            except OSError:
                actual = ""
            if actual != expected:
                print(f"generated opcode specification is stale: {path}", file=sys.stderr)
                success = False
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as output:
            output.write(expected)
            temporary = Path(output.name)
        temporary.replace(path)
        print(f"wrote {path}")
    return success


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if committed outputs are stale")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    return 0 if write_specs(parse_args(argv).check) else 1


if __name__ == "__main__":
    raise SystemExit(main())
