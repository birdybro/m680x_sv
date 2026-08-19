"""Architectural arithmetic facts shared by the independent Python models.

The functions in this module describe result values and only the condition-code
bits affected by an operation.  A CPU model merges those updates with the
unaffected bits in its own condition-code register.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping


@dataclass(frozen=True)
class ALUResult:
    """A bounded integer result and the condition-code bits it defines."""

    value: int
    flags: Mapping[str, bool]


@dataclass(frozen=True)
class DAAResult:
    """A DAA result, including whether the manual defines the input case."""

    value: int
    flags: Mapping[str, bool]
    adjustment: int
    defined: bool


def _u8(value: int, name: str) -> int:
    if not isinstance(value, int) or not 0 <= value <= 0xFF:
        raise ValueError(f"{name} must be an 8-bit unsigned integer")
    return value


def _u16(value: int, name: str) -> int:
    if not isinstance(value, int) or not 0 <= value <= 0xFFFF:
        raise ValueError(f"{name} must be a 16-bit unsigned integer")
    return value


def _bit(value: int | bool, name: str) -> int:
    if value not in (0, 1, False, True):
        raise ValueError(f"{name} must be zero or one")
    return int(value)


def _nz(value: int, sign_mask: int) -> dict[str, bool]:
    return {"N": bool(value & sign_mask), "Z": value == 0}


def add8(left: int, right: int, carry_in: int | bool = 0) -> ALUResult:
    """Return the M6800-family eight-bit ADD/ADC value and HNZVC facts."""

    left = _u8(left, "left")
    right = _u8(right, "right")
    carry = _bit(carry_in, "carry_in")
    total = left + right + carry
    value = total & 0xFF
    flags = _nz(value, 0x80)
    flags.update(
        {
            "H": (left & 0x0F) + (right & 0x0F) + carry > 0x0F,
            "V": bool((~(left ^ right) & (left ^ value)) & 0x80),
            "C": total > 0xFF,
        }
    )
    return ALUResult(value, flags)


def sub8(left: int, right: int, borrow_in: int | bool = 0) -> ALUResult:
    """Return the eight-bit SUB/SBC/CMP value and NZVC facts.

    The family uses C as a borrow input for SBC, so borrow_in is subtracted.
    """

    left = _u8(left, "left")
    right = _u8(right, "right")
    borrow = _bit(borrow_in, "borrow_in")
    value = (left - right - borrow) & 0xFF
    flags = _nz(value, 0x80)
    flags.update(
        {
            "V": bool(((left ^ right) & (left ^ value)) & 0x80),
            "C": left < right + borrow,
        }
    )
    return ALUResult(value, flags)


def add16(left: int, right: int) -> ALUResult:
    """Return the MC6801/HD6301 ADDD value and NZVC facts."""

    left = _u16(left, "left")
    right = _u16(right, "right")
    total = left + right
    value = total & 0xFFFF
    flags = _nz(value, 0x8000)
    flags.update(
        {
            "V": bool((~(left ^ right) & (left ^ value)) & 0x8000),
            "C": total > 0xFFFF,
        }
    )
    return ALUResult(value, flags)


def sub16(left: int, right: int) -> ALUResult:
    """Return the 16-bit SUBD/CPX value and NZVC facts."""

    left = _u16(left, "left")
    right = _u16(right, "right")
    value = (left - right) & 0xFFFF
    flags = _nz(value, 0x8000)
    flags.update(
        {
            "V": bool(((left ^ right) & (left ^ value)) & 0x8000),
            "C": left < right,
        }
    )
    return ALUResult(value, flags)


def and8(left: int, right: int) -> ALUResult:
    return _logical8(_u8(left, "left") & _u8(right, "right"))


def or8(left: int, right: int) -> ALUResult:
    return _logical8(_u8(left, "left") | _u8(right, "right"))


def xor8(left: int, right: int) -> ALUResult:
    return _logical8(_u8(left, "left") ^ _u8(right, "right"))


def _logical8(value: int) -> ALUResult:
    flags = _nz(value, 0x80)
    flags["V"] = False
    return ALUResult(value, flags)


def neg8(operand: int) -> ALUResult:
    operand = _u8(operand, "operand")
    value = (-operand) & 0xFF
    flags = _nz(value, 0x80)
    flags.update({"V": operand == 0x80, "C": operand != 0})
    return ALUResult(value, flags)


def com8(operand: int) -> ALUResult:
    value = _u8(operand, "operand") ^ 0xFF
    flags = _nz(value, 0x80)
    flags.update({"V": False, "C": True})
    return ALUResult(value, flags)


def lsr8(operand: int) -> ALUResult:
    operand = _u8(operand, "operand")
    value = operand >> 1
    carry = bool(operand & 0x01)
    return ALUResult(value, {"N": False, "Z": value == 0, "V": carry, "C": carry})


def asr8(operand: int) -> ALUResult:
    operand = _u8(operand, "operand")
    value = (operand >> 1) | (operand & 0x80)
    carry = bool(operand & 0x01)
    negative = bool(value & 0x80)
    return ALUResult(value, {"N": negative, "Z": value == 0, "V": negative ^ carry, "C": carry})


def asl8(operand: int) -> ALUResult:
    operand = _u8(operand, "operand")
    value = (operand << 1) & 0xFF
    carry = bool(operand & 0x80)
    negative = bool(value & 0x80)
    return ALUResult(value, {"N": negative, "Z": value == 0, "V": negative ^ carry, "C": carry})


def ror8(operand: int, carry_in: int | bool) -> ALUResult:
    operand = _u8(operand, "operand")
    carry = _bit(carry_in, "carry_in")
    value = (operand >> 1) | (carry << 7)
    carry_out = bool(operand & 0x01)
    negative = bool(value & 0x80)
    return ALUResult(value, {"N": negative, "Z": value == 0, "V": negative ^ carry_out, "C": carry_out})


def rol8(operand: int, carry_in: int | bool) -> ALUResult:
    operand = _u8(operand, "operand")
    carry = _bit(carry_in, "carry_in")
    value = ((operand << 1) | carry) & 0xFF
    carry_out = bool(operand & 0x80)
    negative = bool(value & 0x80)
    return ALUResult(value, {"N": negative, "Z": value == 0, "V": negative ^ carry_out, "C": carry_out})


def inc8(operand: int) -> ALUResult:
    operand = _u8(operand, "operand")
    value = (operand + 1) & 0xFF
    flags = _nz(value, 0x80)
    flags["V"] = operand == 0x7F
    return ALUResult(value, flags)


def dec8(operand: int) -> ALUResult:
    operand = _u8(operand, "operand")
    value = (operand - 1) & 0xFF
    flags = _nz(value, 0x80)
    flags["V"] = operand == 0x80
    return ALUResult(value, flags)


def tst8(operand: int) -> ALUResult:
    operand = _u8(operand, "operand")
    flags = _nz(operand, 0x80)
    flags.update({"V": False, "C": False})
    return ALUResult(operand, flags)


def clr8() -> ALUResult:
    return ALUResult(0, {"N": False, "Z": True, "V": False, "C": False})


def mul8(left: int, right: int) -> ALUResult:
    """Return the MC6801/HD6301 unsigned product and documented C fact."""

    product = _u8(left, "left") * _u8(right, "right")
    return ALUResult(product, {"C": bool(product & 0x0080)})


def daa8(accumulator: int, half_carry: int | bool, carry: int | bool) -> DAAResult:
    """Apply the manufacturer DAA table.

    The Motorola and Hitachi tables define only states obtainable by BCD ADD,
    ADC, or ABA operands.  Inputs outside those nine table rows are identified
    with ``defined=False``; no silicon-equivalence claim is made for them.
    """

    accumulator = _u8(accumulator, "accumulator")
    h = _bit(half_carry, "half_carry")
    c = _bit(carry, "carry")
    high = accumulator >> 4
    low = accumulator & 0x0F
    adjustment: int | None = None
    carry_out = c

    if c == 0 and h == 0 and 0 <= high <= 9 and 0 <= low <= 9:
        adjustment, carry_out = 0x00, 0
    elif c == 0 and h == 0 and 0 <= high <= 8 and 0xA <= low <= 0xF:
        adjustment, carry_out = 0x06, 0
    elif c == 0 and h == 1 and 0 <= high <= 9 and 0 <= low <= 3:
        adjustment, carry_out = 0x06, 0
    elif c == 0 and h == 0 and 0xA <= high <= 0xF and 0 <= low <= 9:
        adjustment, carry_out = 0x60, 1
    elif c == 0 and h == 0 and 9 <= high <= 0xF and 0xA <= low <= 0xF:
        adjustment, carry_out = 0x66, 1
    elif c == 0 and h == 1 and 0xA <= high <= 0xF and 0 <= low <= 3:
        adjustment, carry_out = 0x66, 1
    elif c == 1 and h == 0 and 0 <= high <= 2 and 0 <= low <= 9:
        adjustment, carry_out = 0x60, 1
    elif c == 1 and h == 0 and 0 <= high <= 2 and 0xA <= low <= 0xF:
        adjustment, carry_out = 0x66, 1
    elif c == 1 and h == 1 and 0 <= high <= 3 and 0 <= low <= 3:
        adjustment, carry_out = 0x66, 1

    if adjustment is None:
        return DAAResult(accumulator, {}, 0, False)
    value = (accumulator + adjustment) & 0xFF
    return DAAResult(
        value,
        {"N": bool(value & 0x80), "Z": value == 0, "C": bool(carry_out)},
        adjustment,
        True,
    )
